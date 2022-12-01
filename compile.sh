./configure --enable-cassert --enable-debug --enable-depend CFLAGS="-ggdb -Og -g3 -fno-omit-frame-pointer -march=native -mtune=native -DENABLE_GPUQO -DGPUQO_PROFILE" CPPFLAGS="-march=native -mtune=native -DENABLE_GPUQO -DGPUQO_PROFILE" --enable-cuda=/usr/local/cuda --with-cudasm=61 --with-icu
make -j $(nproc) enable_gpuqo_profiling=yes enable_debug=yes cost_function=postgres
