# ==============================================================================
# Dockerfile.linuxarmv7l - ReaVox Linux ARM 32-bit (armv7l) Vosk API 全自动化 Docker 沙盒
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
        gcc-arm-linux-gnueabihf \
        g++-arm-linux-gnueabihf \
    && rm -rf /var/lib/apt/lists/*

# 1. 编译 Linux ARM32 (armv7l) OpenFST 库
RUN mkdir -p /opt/kaldi \
    && cd /opt/kaldi \
    && git clone --depth=1 https://github.com/alphacep/openfst \
    && cd openfst \
    && autoreconf -i \
    && CXX=arm-linux-gnueabihf-g++ CC=arm-linux-gnueabihf-gcc AR=arm-linux-gnueabihf-ar \
        CFLAGS="-O3 -DNDEBUG -g0 -ffunction-sections -fdata-sections -fPIC -mfpu=neon" CXXFLAGS="-O3 -DNDEBUG -g0 -ffunction-sections -fdata-sections -fPIC -mfpu=neon" ./configure --prefix=/opt/kaldi/local \
        --enable-shared --enable-static --with-pic --disable-bin \
        --enable-lookahead-fsts --enable-ngram-fsts --host=arm-linux-gnueabihf \
        && make -j $(nproc) \
        && make install

# 2. 编译 Linux ARM32 (armv7l) OpenBLAS 核心数学库
RUN cd /opt/kaldi \
    && git clone -b v0.3.20 --single-branch --depth=1 https://github.com/xianyi/OpenBLAS \
    && cd OpenBLAS \
    && make HOSTCC=gcc CC=arm-linux-gnueabihf-gcc TARGET=ARMV7 DYNAMIC_ARCH=0 ONLY_CBLAS=1 USE_LOCKING=1 USE_THREAD=0 NO_FORTRAN=1 NO_SHARED=1 CFLAGS="-O3 -DNDEBUG -g0 -fPIC -mfpu=neon" -j $(nproc) \
    && make PREFIX=/opt/kaldi/local NO_SHARED=1 install \
    && cd /opt/kaldi/local/lib \
    && ln -sf libopenblas.a libopenblas.so 2>/dev/null || true \
    && ln -sf libopenblas.a liblapack.a 2>/dev/null || true \
    && ln -sf libopenblas.a libblas.a 2>/dev/null || true \
    && ln -sf libopenblas.a libf2c.a 2>/dev/null || true

# 3. 编译 Linux ARM32 (armv7l) Kaldi 核心引擎
RUN cd /opt/kaldi \
    && git clone -b vosk --single-branch --depth=1 https://github.com/alphacep/kaldi \
    && cd kaldi/src \
    && sed -i 's/-msse -msse2//g' configure \
    && CXX=arm-linux-gnueabihf-g++ CC=arm-linux-gnueabihf-gcc AR=arm-linux-gnueabihf-ar \
        CFLAGS="-O3 -DNDEBUG -g0 -ffunction-sections -fdata-sections -fPIC -mfpu=neon" CXXFLAGS="-O3 -DNDEBUG -g0 -ffunction-sections -fdata-sections -fPIC -mfpu=neon" ./configure --static --static-math=yes --use-cuda=no --host=arm-linux-gnueabihf \
        --mathlib=OPENBLAS --openblas-root=/opt/kaldi/local \
        --fst-root=/opt/kaldi/local --fst-version=1.8.0 \
    && if [ -f kaldi.mk ]; then sed -i 's/-msse -msse2//g' kaldi.mk && sed -i 's/-g //g' kaldi.mk && sed -i 's/-O1/-O3 -DNDEBUG -g0 -ffunction-sections -fdata-sections/g' kaldi.mk; fi \
    && make depend -j \
    && make -j $(nproc) online2 rnnlm

# 4. 编译 Vosk API 并打包 Linux ARM32 (armv7l) 目标产物 (libvosk.so, libvosk.a, vosk_api.h)
ARG VOSK_TAG=v0.3.50
RUN cd /opt \
    && if [ -n "$VOSK_TAG" ] && [ "$VOSK_TAG" != "master" ]; then \
           git clone -b "${VOSK_TAG}" --single-branch --depth=1 https://github.com/alphacep/vosk-api; \
       else \
           git clone --depth=1 https://github.com/alphacep/vosk-api; \
       fi \
    && cd vosk-api/src \
    && CXX=arm-linux-gnueabihf-g++ CC=arm-linux-gnueabihf-gcc AR=arm-linux-gnueabihf-ar \
        KALDI_ROOT=/opt/kaldi/kaldi OPENBLAS_ROOT=/opt/kaldi/local OPENFST_ROOT=/opt/kaldi/local EXT=so make -j $(nproc) \
            HAVE_ACCELERATE=0 \
            HAVE_OPENBLAS=1 \
            HAVE_MKL=0 \
            USE_SHARED=0 \
            EXTRA_CFLAGS="-O3 -DNDEBUG -g0 -ffunction-sections -fdata-sections -fPIC -mfpu=neon" \
            EXTRA_LDFLAGS="-Wl,--gc-sections" \
    && mkdir -p /opt/dist/linux/armv7l \
    && cp -fv libvosk.so /opt/dist/linux/armv7l/libvosk.so \
    && arm-linux-gnueabihf-strip --strip-all /opt/dist/linux/armv7l/libvosk.so \
    && cp -fv vosk_api.h /opt/dist/linux/armv7l/vosk_api.h \
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
        [ -f "$lib" ] && arm-linux-gnueabihf-ar x "$lib"; \
    done \
    && arm-linux-gnueabihf-strip --strip-debug *.o 2>/dev/null || true \
    && arm-linux-gnueabihf-ar rcs /opt/dist/linux/armv7l/libvosk.a *.o \
    && arm-linux-gnueabihf-ranlib /opt/dist/linux/armv7l/libvosk.a \
    && rm -rf /opt/build_tmp
