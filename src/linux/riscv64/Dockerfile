# ==============================================================================
# Dockerfile.riscv64 - ReaVox Linux RISC-V 64-bit (riscv64) Vosk API 全自动化 Docker 构建沙盒
# ==============================================================================
FROM ubuntu:20.04

RUN apt-get update -o Acquire::Retries=3 && \
    DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC apt-get install -y \
        -o Acquire::Retries=3 \
        -o Acquire::http::Timeout="30" \
        --no-install-recommends \
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
    gcc-riscv64-linux-gnu \
    g++-riscv64-linux-gnu \
    python3 \
    && rm -rf /var/lib/apt/lists/*

COPY tools/slim_archive.py /opt/tools/slim_archive.py

# 1. 编译 Linux RISC-V 64 OpenFST 库
RUN mkdir -p /opt/kaldi \
    && cd /opt/kaldi \
    && git clone --depth=1 https://github.com/alphacep/openfst \
    && cd openfst \
    && autoreconf -i \
    && CXX=riscv64-linux-gnu-g++ CC=riscv64-linux-gnu-gcc AR=riscv64-linux-gnu-ar \
    CFLAGS="-O3 -DNDEBUG -g0 -ffunction-sections -fdata-sections -fPIC" CXXFLAGS="-O3 -DNDEBUG -g0 -ffunction-sections -fdata-sections -fPIC" ./configure --prefix=/opt/kaldi/local \
    --enable-shared --enable-static --with-pic --disable-bin \
    --enable-lookahead-fsts --enable-ngram-fsts --host=riscv64-linux-gnu \
    && make -j $(nproc) \
    && make install

# 2. 编译 Linux RISC-V 64 OpenBLAS 核心数学库
RUN cd /opt/kaldi \
    && git clone -b v0.3.20 --single-branch --depth=1 https://github.com/xianyi/OpenBLAS \
    && cd OpenBLAS \
    && make HOSTCC=gcc CC=riscv64-linux-gnu-gcc TARGET=RISCV64_GENERIC DYNAMIC_ARCH=0 ONLY_CBLAS=1 USE_LOCKING=1 USE_THREAD=0 NO_FORTRAN=1 NO_SHARED=1 CFLAGS="-O3 -DNDEBUG -g0 -fPIC" -j $(nproc) \
    && make PREFIX=/opt/kaldi/local NO_SHARED=1 install \
    && cd /opt/kaldi/local/lib \
    && ln -sf libopenblas.a libopenblas.so 2>/dev/null || true \
    && ln -sf libopenblas.a liblapack.a 2>/dev/null || true \
    && ln -sf libopenblas.a libblas.a 2>/dev/null || true \
    && ln -sf libopenblas.a libf2c.a 2>/dev/null || true

# 3. 编译 Linux RISC-V 64 Kaldi 核心引擎
RUN cd /opt/kaldi \
    && git clone -b vosk --single-branch --depth=1 https://github.com/alphacep/kaldi \
    && cd kaldi/src \
    && sed -i 's:TARGET_ARCH="`uname -m`":TARGET_ARCH=riscv64:g' configure \
    && sed -i 's/!= aarch64\*/!= aarch64\* \&\& "$TARGET_ARCH" != riscv64\*/g' configure \
    && sed -i 's/aarch64\*)/aarch64\*|riscv64\*)/g' configure \
    && sed -i 's/-msse -msse2//g' configure \
    && CXX=riscv64-linux-gnu-g++ CC=riscv64-linux-gnu-gcc AR=riscv64-linux-gnu-ar \
        CFLAGS="-O3 -DNDEBUG -g0 -ffunction-sections -fdata-sections -fPIC" CXXFLAGS="-O3 -DNDEBUG -g0 -ffunction-sections -fdata-sections -fPIC" ./configure --static --static-math=yes --use-cuda=no --host=riscv64-linux-gnu \
        --mathlib=OPENBLAS --openblas-root=/opt/kaldi/local \
        --fst-root=/opt/kaldi/local --fst-version=1.8.0 \
    && if [ -f kaldi.mk ]; then sed -i 's/-msse -msse2//g' kaldi.mk && sed -i 's/-g //g' kaldi.mk && sed -i 's/-O1/-O3 -DNDEBUG -g0 -ffunction-sections -fdata-sections/g' kaldi.mk; fi \
    && make depend -j \
    && make -j $(nproc) online2 rnnlm

# 4. 编译 Vosk API 并打包 Linux RISC-V 64 目标产物 (libvosk.so, libvosk.a, vosk_api.h)
ARG VOSK_TAG=v0.3.50
RUN cd /opt \
    && if [ -n "$VOSK_TAG" ] && [ "$VOSK_TAG" != "master" ]; then \
    git clone -b "${VOSK_TAG}" --single-branch --depth=1 https://github.com/alphacep/vosk-api; \
    else \
    git clone --depth=1 https://github.com/alphacep/vosk-api; \
    fi \
    && cd vosk-api/src \
    && CXX=riscv64-linux-gnu-g++ CC=riscv64-linux-gnu-gcc AR=riscv64-linux-gnu-ar \
    KALDI_ROOT=/opt/kaldi/kaldi OPENBLAS_ROOT=/opt/kaldi/local OPENFST_ROOT=/opt/kaldi/local EXT=so make -j $(nproc) \
    HAVE_ACCELERATE=0 \
    HAVE_OPENBLAS=1 \
    HAVE_MKL=0 \
    USE_SHARED=0 \
    EXTRA_CFLAGS="-O3 -DNDEBUG -g0 -ffunction-sections -fdata-sections -fPIC" \
    EXTRA_LDFLAGS="-Wl,--gc-sections" \
    && mkdir -p /opt/dist/linux/riscv64 \
    && cp -fv libvosk.so /opt/dist/linux/riscv64/libvosk.so \
    && riscv64-linux-gnu-strip --strip-all /opt/dist/linux/riscv64/libvosk.so \
    && cp -fv vosk_api.h /opt/dist/linux/riscv64/vosk_api.h \
    && mkdir -p /opt/build_tmp \
    && cd /opt/build_tmp \
    && cp /opt/vosk-api/src/*.o . 2>/dev/null || true \
    && for lib in \
        /opt/kaldi/kaldi/src/online2/*.a \
        /opt/kaldi/kaldi/src/decoder/*.a \
        /opt/kaldi/kaldi/src/gmm/*.a \
        /opt/kaldi/kaldi/src/tree/*.a \
        /opt/kaldi/kaldi/src/feat/*.a \
        /opt/kaldi/kaldi/src/lat/*.a \
        /opt/kaldi/kaldi/src/lm/*.a \
        /opt/kaldi/kaldi/src/rnnlm/*.a \
        /opt/kaldi/kaldi/src/hmm/*.a \
        /opt/kaldi/kaldi/src/nnet3/*.a \
        /opt/kaldi/kaldi/src/matrix/*.a \
        /opt/kaldi/kaldi/src/fstext/*.a \
        /opt/kaldi/kaldi/src/util/*.a \
        /opt/kaldi/kaldi/src/base/*.a \
        /opt/kaldi/local/lib/libfst*.a \
        /opt/kaldi/local/lib/libopenblas.a; do \
        [ -f "$lib" ] && riscv64-linux-gnu-ar x "$lib"; \
    done \
    && riscv64-linux-gnu-strip --strip-debug *.o 2>/dev/null || true \
    && riscv64-linux-gnu-ar rcs /opt/dist/linux/riscv64/libvosk.a *.o \
    && riscv64-linux-gnu-ranlib /opt/dist/linux/riscv64/libvosk.a \
    && rm -rf /opt/build_tmp \
    && python3 /opt/tools/slim_archive.py /opt/dist/linux/riscv64/libvosk.a /opt/dist/linux/riscv64/libvosk.a --header /opt/dist/linux/riscv64/vosk_api.h --nm riscv64-linux-gnu-nm --ar riscv64-linux-gnu-ar
