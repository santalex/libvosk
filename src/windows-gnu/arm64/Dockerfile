# ==============================================================================
# Dockerfile - LibVosk Windows GNU ARM64 (aarch64) llvm-mingw 全自动化交叉编译沙盒
# ==============================================================================
FROM ubuntu:20.04

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC apt-get install -y --no-install-recommends \
        ca-certificates \
        g++ \
        bzip2 \
        unzip \
        make \
        wget \
        git \
        cmake \
        xz-utils \
        automake \
        autoconf \
        libtool \
        pkg-config \
        python3 \
    && rm -rf /var/lib/apt/lists/*

COPY tools/slim_archive.py /opt/tools/slim_archive.py

# 1. 安装 Windows ARM64 llvm-mingw 工具链
RUN cd /opt && \
    wget https://github.com/mstorsjo/llvm-mingw/releases/download/20240820/llvm-mingw-20240820-msvcrt-ubuntu-20.04-x86_64.tar.xz \
    && tar xf llvm-mingw-20240820-msvcrt-ubuntu-20.04-x86_64.tar.xz \
    && mv llvm-mingw-20240820-msvcrt-ubuntu-20.04-x86_64 llvm-mingw \
    && rm -f llvm-mingw-20240820-msvcrt-ubuntu-20.04-x86_64.tar.xz

ENV PATH="$PATH:/opt/llvm-mingw/bin"

# 2. 编译 Windows ARM64 OpenFST 库
RUN mkdir -p /opt/kaldi \
    && cd /opt/kaldi \
    && git clone --depth=1 https://github.com/alphacep/openfst \
    && cd openfst \
    && autoreconf -i \
    && CXX=aarch64-w64-mingw32-g++ CXXFLAGS="-O3 -ftree-vectorize -DFST_NO_DYNAMIC_LINKING" \
        ./configure --prefix=/opt/kaldi/local \
        --enable-shared --enable-static --with-pic --disable-bin \
        --enable-lookahead-fsts --enable-ngram-fsts --host=aarch64-w64-mingw32 \
    && make -j $(nproc) \
    && make install

# 3. 编译 Windows ARM64 OpenBLAS 核心数学库
RUN cd /opt/kaldi \
    && git clone -b v0.3.20 --single-branch --depth=1 https://github.com/xianyi/OpenBLAS \
    && cd OpenBLAS \
    && make HOSTCC=gcc CC=aarch64-w64-mingw32-gcc ONLY_CBLAS=1 USE_LOCKING=1 USE_THREAD=0 USE_OPENMP=0 DYNAMIC_ARCH=0 TARGET=ARMV8 ARCH=arm64 BINARY=64 -j $(nproc) \
    && make PREFIX=/opt/kaldi/local install

# 4. 编译 Windows ARM64 CLAPACK (线性代数与 Fortran 桥接)
RUN cd /opt/kaldi \
    && git clone -b v3.2.1 --single-branch --depth=1 https://github.com/alphacep/clapack \
    && mkdir clapack/BUILD \
    && cd clapack/BUILD \
    && cmake -DCMAKE_C_COMPILER_TARGET=aarch64-w64-mingw32 -DCMAKE_C_COMPILER=aarch64-w64-mingw32-gcc -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_CROSSCOMPILING=True .. \
    && make -C F2CLIBS/libf2c \
    && make -C BLAS \
    && make -C SRC \
    && find . -name "*.a" -exec cp {} /opt/kaldi/local/lib \;

# 5. 编译 Windows ARM64 Kaldi 核心引擎
RUN cd /opt/kaldi \
    && git clone -b vosk-android --single-branch --depth=1 https://github.com/alphacep/kaldi \
    && cd kaldi/src \
    && CXX=aarch64-w64-mingw32-g++ CXXFLAGS="-O3 -ftree-vectorize -DFST_NO_DYNAMIC_LINKING" ./configure --shared --mingw=yes --use-cuda=no \
        --mathlib=OPENBLAS_CLAPACK \
        --host=aarch64-w64-mingw32 --openblas-clapack-root=/opt/kaldi/local \
        --fst-root=/opt/kaldi/local --fst-version=1.8.0 \
    && make depend -j \
    && make LLVM_BUILD=1 -j $(nproc) online2 rnnlm

# 6. 编译 Vosk API 并打包 Windows ARM64 全套目标产物
ARG VOSK_TAG=v0.3.50
RUN cd /opt \
    && if [ -n "$VOSK_TAG" ] && [ "$VOSK_TAG" != "master" ]; then \
           git clone -b "${VOSK_TAG}" --single-branch --depth=1 https://github.com/alphacep/vosk-api; \
       else \
           git clone --depth=1 https://github.com/alphacep/vosk-api; \
       fi \
    && cd vosk-api/src \
    && CXX=aarch64-w64-mingw32-g++ CC=aarch64-w64-mingw32-gcc AR=aarch64-w64-mingw32-ar \
        KALDI_ROOT=/opt/kaldi/kaldi OPENBLAS_ROOT=/opt/kaldi/local OPENFST_ROOT=/opt/kaldi/local EXT=dll make -j $(nproc) \
            HAVE_ACCELERATE=0 \
            HAVE_OPENBLAS_CLAPACK=1 \
            HAVE_MKL=0 \
            USE_SHARED=0 \
            EXTRA_CFLAGS="-O3 -ftree-vectorize" \
            EXTRA_LDFLAGS="-Wl,--out-implib,libvosk.dll.a" \
    && mkdir -p /opt/dist/windows-gnu/arm64 \
    && cp -fv libvosk.dll /opt/dist/windows-gnu/arm64/libvosk.dll \
    && cp -fv libvosk.dll.a /opt/dist/windows-gnu/arm64/libvosk.dll.a \
    && cp -fv libvosk.dll.a /opt/dist/windows-gnu/arm64/libvosk.lib \
    && cp -fv vosk_api.h /opt/dist/windows-gnu/arm64/vosk_api.h \
    && mkdir -p /opt/build_tmp \
    && cd /opt/build_tmp \
    && cp /opt/vosk-api/src/*.o . 2>/dev/null || true \
    && for lib in /opt/kaldi/kaldi/src/*/*.a /opt/kaldi/local/lib/*.a; do aarch64-w64-mingw32-ar x "$lib"; done \
    && aarch64-w64-mingw32-strip --strip-debug *.o 2>/dev/null || true \
    && aarch64-w64-mingw32-ar rcs /opt/dist/windows-gnu/arm64/libvosk.a *.o \
    && rm -rf /opt/build_tmp \
    && python3 /opt/tools/slim_archive.py /opt/dist/windows-gnu/arm64/libvosk.a /opt/dist/windows-gnu/arm64/libvosk.a --header /opt/dist/windows-gnu/arm64/vosk_api.h --nm aarch64-w64-mingw32-nm --ar aarch64-w64-mingw32-ar \
    && cp -fv /opt/dist/windows-gnu/arm64/libvosk.a /opt/dist/windows-gnu/arm64/libvosk_static.lib
