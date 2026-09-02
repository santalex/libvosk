# ==============================================================================
# Dockerfile - LibVosk Windows GNU (x86_64) MinGW-w64 全自动化 Docker 构建沙盒
# ==============================================================================
FROM debian:11

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        g++ \
        bzip2 \
        unzip \
        make \
        wget \
        git \
        cmake \
        automake \
        autoconf \
        libtool \
        pkg-config \
        g++-mingw-w64-x86-64-posix \
        gfortran-mingw-w64-x86-64 \
        python3 \
    && rm -rf /var/lib/apt/lists/*

COPY tools/slim_archive.py /opt/tools/slim_archive.py

# 1. 编译 Windows x86_64 OpenFST 库
RUN mkdir -p /opt/kaldi \
    && cd /opt/kaldi \
    && git clone --depth=1 https://github.com/alphacep/openfst \
    && cd openfst \
    && autoreconf -i \
    && CXX=x86_64-w64-mingw32-g++-posix CC=x86_64-w64-mingw32-gcc-posix AR=x86_64-w64-mingw32-ar \
        CXXFLAGS="-O3 -fPIC -DFST_NO_DYNAMIC_LINKING" \
        ./configure --prefix=/opt/kaldi/local \
        --enable-shared --enable-static --with-pic --disable-bin \
        --enable-lookahead-fsts --enable-ngram-fsts --host=x86_64-w64-mingw32 \
    && make -j $(nproc) \
    && make install

# 2. 编译 Windows x86_64 OpenBLAS 核心数学库
RUN cd /opt/kaldi \
    && git clone -b v0.3.20 --single-branch --depth=1 https://github.com/xianyi/OpenBLAS \
    && cd OpenBLAS \
    && make HOSTCC=gcc BINARY=64 CC=x86_64-w64-mingw32-gcc-posix AR=x86_64-w64-mingw32-ar ONLY_CBLAS=1 TARGET=NEHALEM USE_LOCKING=1 USE_THREAD=0 -j $(nproc) \
    && make PREFIX=/opt/kaldi/local install

# 3. 编译 Windows x86_64 CLAPACK 库 (提供 libf2c.a, libblas.a, liblapack.a)
RUN cd /opt/kaldi \
    && git clone -b v3.2.1 --single-branch --depth=1 https://github.com/alphacep/clapack \
    && mkdir clapack/BUILD \
    && cd clapack/BUILD \
    && cmake -DCMAKE_C_COMPILER_TARGET=x86_64-w64-mingw32 -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc-posix -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++-posix -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_CROSSCOMPILING=True .. \
    && make -C F2CLIBS/libf2c \
    && make -C BLAS \
    && make -C SRC \
    && find . -name "*.a" -exec cp {} /opt/kaldi/local/lib \;

# 4. 编译 Windows x86_64 Kaldi 核心引擎
RUN cd /opt/kaldi \
    && git clone -b vosk-android --single-branch --depth=1 https://github.com/alphacep/kaldi \
    && cd kaldi/src \
    && CXX=x86_64-w64-mingw32-g++-posix CC=x86_64-w64-mingw32-gcc-posix AR=x86_64-w64-mingw32-ar \
        CXXFLAGS="-O3 -fPIC -DFST_NO_DYNAMIC_LINKING" ./configure --shared --mingw=yes --use-cuda=no --host=x86_64-w64-mingw32 \
        --mathlib=OPENBLAS_CLAPACK --openblas-clapack-root=/opt/kaldi/local \
        --fst-root=/opt/kaldi/local --fst-version=1.8.0 \
    && make depend -j \
    && make -j $(nproc) online2 rnnlm

# 5. 编译 Vosk API 并打包 Windows x86_64 目标产物 (自包含 libvosk.dll + libvosk.a)
ARG VOSK_TAG=v0.3.50
RUN cd /opt \
    && if [ -n "$VOSK_TAG" ] && [ "$VOSK_TAG" != "master" ]; then \
           git clone -b "${VOSK_TAG}" --single-branch --depth=1 https://github.com/alphacep/vosk-api; \
       else \
           git clone --depth=1 https://github.com/alphacep/vosk-api; \
       fi \
    && cd vosk-api/src \
    && CXX=x86_64-w64-mingw32-g++-posix CC=x86_64-w64-mingw32-gcc-posix AR=x86_64-w64-mingw32-ar \
        KALDI_ROOT=/opt/kaldi/kaldi OPENBLAS_ROOT=/opt/kaldi/local OPENFST_ROOT=/opt/kaldi/local EXT=dll make -j $(nproc) \
            HAVE_ACCELERATE=0 \
            HAVE_OPENBLAS_CLAPACK=1 \
            HAVE_MKL=0 \
            USE_SHARED=0 \
            EXTRA_CFLAGS="-O3 -ftree-vectorize" \
            EXTRA_LDFLAGS="-Wl,--out-implib,libvosk.dll.a" \
    && mkdir -p /opt/dist/windows-gnu/x86_64 \
    && cp -fv libvosk.dll /opt/dist/windows-gnu/x86_64/libvosk.dll \
    && cp -fv libvosk.dll.a /opt/dist/windows-gnu/x86_64/libvosk.dll.a \
    && cp -fv libvosk.dll.a /opt/dist/windows-gnu/x86_64/libvosk.lib \
    && cp -fv vosk_api.h /opt/dist/windows-gnu/x86_64/vosk_api.h \
    && mkdir -p /opt/build_tmp \
    && cd /opt/build_tmp \
    && cp /opt/vosk-api/src/*.o . 2>/dev/null || true \
    && for lib in /opt/kaldi/kaldi/src/*/*.a /opt/kaldi/local/lib/*.a; do x86_64-w64-mingw32-ar x "$lib"; done \
    && x86_64-w64-mingw32-strip --strip-debug *.o 2>/dev/null || true \
    && x86_64-w64-mingw32-ar rcs /opt/dist/windows-gnu/x86_64/libvosk.a *.o \
    && rm -rf /opt/build_tmp \
    && python3 /opt/tools/slim_archive.py /opt/dist/windows-gnu/x86_64/libvosk.a /opt/dist/windows-gnu/x86_64/libvosk.a --header /opt/dist/windows-gnu/x86_64/vosk_api.h --nm x86_64-w64-mingw32-nm --ar x86_64-w64-mingw32-ar \
    && cp -fv /opt/dist/windows-gnu/x86_64/libvosk.a /opt/dist/windows-gnu/x86_64/libvosk_static.lib
