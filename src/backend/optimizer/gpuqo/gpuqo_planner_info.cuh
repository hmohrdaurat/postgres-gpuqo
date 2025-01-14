/*-------------------------------------------------------------------------
 *
 * gpuqo_planner_info.cuh
 *	  structure for planner info in GPU memory
 *
 * src/include/optimizer/gpuqo.cuh
 *
 *-------------------------------------------------------------------------
 */
#ifndef GPUQO_PLANNER_INFO_CUH
#define GPUQO_PLANNER_INFO_CUH

#include <optimizer/gpuqo_common.h>
#include "gpuqo_bitmapset.cuh"
#include "gpuqo_bitmapset_dynamic.cuh"
#include "gpuqo_postgres.cuh"

// structure representing join of two relations used by CUDA and CPU code 
// of GPUQO

// blah
template<typename BitmapsetN>
struct JoinRelation{
	BitmapsetN left_rel_id;
	BitmapsetN right_rel_id;
	float rows;
	PathCost cost;
	int width;

public:
	__host__ __device__
	bool operator<(const JoinRelation<BitmapsetN> &o) const
	{
		if (cost.total == o.cost.total)
			return cost.startup < o.cost.startup;
		else
			return cost.total < o.cost.total;
	}
};

template<typename BitmapsetN>
struct JoinRelationDetailed : public JoinRelation<BitmapsetN>{
	BitmapsetN id;
	BitmapsetN edges;
};

template<typename BitmapsetN>
struct JoinRelationDpsize : public JoinRelationDetailed<BitmapsetN> {
	uint_t<BitmapsetN> left_rel_idx;
	uint_t<BitmapsetN> right_rel_idx;
};

template<typename BitmapsetN>
struct QueryTree{
	BitmapsetN id;
	float rows;
	PathCost cost;
	int width;
	struct QueryTree<BitmapsetN>* left;
	struct QueryTree<BitmapsetN>* right;
};

// base_rels in GpuqoPlannerInfo
template<typename BitmapsetN>
struct BaseRelation{
	BitmapsetN id;
	// number of rows after applying filters
	float rows;
	// full cardinality of the table
	float tuples;
	// bytes per record (width of a join relation is the sum of the widths)
	int width;
	// startup+final cost as in Postgres
	PathCost cost;
	// wheter it is a temporary table made up by multiple tables
	bool composite;
};

struct GpuqoPlannerInfoParams {
		float effective_cache_size;
		float seq_page_cost;
		float random_page_cost;
		float cpu_tuple_cost;
		float cpu_index_tuple_cost;
		float cpu_operator_cost;
		float disable_cost;
		bool enable_seqscan;
		bool enable_indexscan;
		bool enable_tidscan;
		bool enable_sort;
		bool enable_hashagg;
		bool enable_nestloop;
		bool enable_mergejoin;
		bool enable_hashjoin;
		int work_mem;
};

template<typename BitmapsetN>
struct EqClasses {
		int n;
		// bitmapset of the relations in the class
		BitmapsetN* relids;
		int n_sels;
		// selectivities between each pair of relations for this equivalence class (one for each unordered pair)
		float* sels;
		int n_fks;
		// bitmapset for each pair indicating a foreign key is present(1 bitmapset for each member in the class)
		BitmapsetN* fks; 
		int n_vars;
		// statistics about the actual columns (one for each member in the class)
		VarInfo* vars;
};


template<typename BitmapsetN>
struct GpuqoPlannerInfo{
	// used by cuda loader ignore it
	unsigned int size;

	// count how many iterations for early stop
	//int total_iters;

	// number of relations (tables) in the query
	int n_rels;
	// iters used by idp1 to stop earlier
	int n_iters;
	
	// stuff given to the gpu, don't worry about it
	GpuqoPlannerInfoParams params;
	
	// base relation has got an id, each id is a bitmapset (line 63)
	BaseRelation<BitmapsetN> base_rels[BitmapsetN::SIZE];
	// adjacency matrix of the query graph
	BitmapsetN edge_table[BitmapsetN::SIZE];
	// subtrees[i] contains all the nodes in the subtree of the tree rooted in table 0
	// (it is used only if some flags are set and only for trees).
	BitmapsetN subtrees[BitmapsetN::SIZE];
	// Used to compute selectivity (group of equal atttributs from the A.b = B.a constraints in the WHERE)
	// in above case the EqClass qould be {A.b, B.a}
	EqClasses<BitmapsetN> eq_classes;
};

template<>
struct GpuqoPlannerInfo<BitmapsetDynamic>{
	unsigned int size;
	//int total_iters;

	int n_rels;
	int n_iters;
	
	GpuqoPlannerInfoParams params;
	
	BaseRelation<BitmapsetDynamic> *base_rels;
	BitmapsetDynamic *edge_table;
	BitmapsetDynamic *subtrees;

	EqClasses<BitmapsetDynamic> eq_classes;
};

struct CostExtra {
	bool inner_unique;
	bool indexed_join_quals;
	float joinrows;
	float outer_match_frac;
	float match_count;
};

template<typename BitmapsetN>
static
void initGpuqoPlannerInfo(GpuqoPlannerInfo<BitmapsetN>* info) { }

template<> 
void initGpuqoPlannerInfo<BitmapsetDynamic>(GpuqoPlannerInfo<BitmapsetDynamic>* info) { 
	info->base_rels = new BaseRelation<BitmapsetDynamic>[info->n_rels];
	info->edge_table = new BitmapsetDynamic[info->n_rels];
	info->subtrees = new BitmapsetDynamic[info->n_rels];
}

template<typename BitmapsetN>
static
void freeGpuqoPlannerInfo(GpuqoPlannerInfo<BitmapsetN>* info) {
	delete[] info;
}

template<>
void freeGpuqoPlannerInfo<BitmapsetDynamic>(GpuqoPlannerInfo<BitmapsetDynamic>* info) {
	delete[] info->base_rels;
	delete[] info->edge_table;
	delete[] info->subtrees;
	delete[] info;
}

__host__ __device__
inline size_t align64(size_t size) {
	if (size & 7) {
		return (size & (~7)) + 8;
	} else {
		return size & (~7);
	}
}

template<typename BitmapsetN>
__host__ __device__
inline size_t plannerInfoBaseSize() {
	return align64(sizeof(GpuqoPlannerInfo<BitmapsetN>));
}

template<typename BitmapsetN>
__host__ __device__
inline size_t plannerInfoEqClassesSize(int n_eq_classes) {
	return align64(sizeof(BitmapsetN) * n_eq_classes);
}

template<typename BitmapsetN>
__host__ __device__
inline size_t plannerInfoEqClassSelsSize(int n_eq_class_sels) {
	return align64(sizeof(float) * n_eq_class_sels);
}

template<typename BitmapsetN>
__host__ __device__
inline size_t plannerInfoEqClassFksSize(int n_eq_class_fks) {
	return align64(sizeof(BitmapsetN) * n_eq_class_fks);
}

template<typename BitmapsetN>
__host__ __device__
inline size_t plannerInfoEqClassVarsSize(int n_eq_class_vars) {
	return align64(sizeof(struct VarInfo) * n_eq_class_vars);
}

template<typename BitmapsetN>
__host__ __device__
inline size_t plannerInfoSize(size_t n_eq_classes, size_t n_eq_class_sels, 
						size_t n_eq_class_fks, size_t n_eq_class_vars) 
{
	return plannerInfoBaseSize<BitmapsetN>() 
		+ plannerInfoEqClassesSize<BitmapsetN>(n_eq_classes)
		+ plannerInfoEqClassSelsSize<BitmapsetN>(n_eq_class_sels)
		+ plannerInfoEqClassFksSize<BitmapsetN>(n_eq_class_fks)
		+ plannerInfoEqClassVarsSize<BitmapsetN>(n_eq_class_vars);
}

template<typename BitmapsetN>
GpuqoPlannerInfo<BitmapsetN>* 
convertGpuqoPlannerInfo(GpuqoPlannerInfoC *info_c);

template<typename BitmapsetN>
GpuqoPlannerInfo<BitmapsetN>* 
copyToDeviceGpuqoPlannerInfo(GpuqoPlannerInfo<BitmapsetN> *info);

template<typename BitmapsetN>
GpuqoPlannerInfo<BitmapsetN>* 
deleteGpuqoPlannerInfo(GpuqoPlannerInfo<BitmapsetN> *info);

template<typename BitmapsetN>
QueryTreeC* convertQueryTree(QueryTree<BitmapsetN> *info);

#endif							/* GPUQO_PLANNER_INFO_CUH */
