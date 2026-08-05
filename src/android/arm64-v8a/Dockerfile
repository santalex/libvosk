# ==============================================================================
# Dockerfile.android - ReaVox Android (arm64-v8a) Vosk API 全自动化 Docker 构建沙盒
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
        automake \
        autoconf \
        libtool \
        pkg-config \
    && rm -rf /var/lib/apt/lists/*

# 1. 下载并安装 Android NDK r25c
RUN cd /opt && \
    wget -q https://dl.google.com/android/repository/android-ndk-r25c-linux.zip \
    && unzip -q android-ndk-r25c-linux.zip \
    && mv android-ndk-r25c android-ndk \
    && rm -f android-ndk-r25c-linux.zip

ENV NDK=/opt/android-ndk
ENV TOOLCHAIN=$NDK/toolchains/llvm/prebuilt/linux-x86_64
ENV TARGET=aarch64-linux-android
ENV API=21
ENV AR=$TOOLCHAIN/bin/llvm-ar
ENV CC=$TOOLCHAIN/bin/$TARGET$API-clang
ENV CXX=$TOOLCHAIN/bin/$TARGET$API-clang++
ENV RANLIB=$TOOLCHAIN/bin/llvm-ranlib
ENV STRIP=$TOOLCHAIN/bin/llvm-strip

# 2. 编译 Android ARM64 OpenFST 库
RUN mkdir -p /opt/kaldi \
    && cd /opt/kaldi \
    && git clone --depth=1 https://github.com/alphacep/openfst \
    && cd openfst \
    && autoreconf -i \
    && CFLAGS="-O3 -fPIC" CXXFLAGS="-O3 -fPIC" ./configure --prefix=/opt/kaldi/local \
        --enable-shared --enable-static --with-pic --disable-bin \
        --enable-lookahead-fsts --enable-ngram-fsts --host=$TARGET \
    && make -j $(nproc) \
    && make install

# 3. 编译 Android ARM64 OpenBLAS 核心数学库
RUN cd /opt/kaldi \
    && git clone -b v0.3.20 --single-branch --depth=1 https://github.com/xianyi/OpenBLAS \
    && cd OpenBLAS \
    && make HOSTCC=gcc CC=$CC AR=$AR TARGET=ARMV8 DYNAMIC_ARCH=0 ONLY_CBLAS=1 USE_LOCKING=1 USE_THREAD=0 NO_FORTRAN=1 NO_SHARED=1 -j $(nproc) \
    && make PREFIX=/opt/kaldi/local NO_SHARED=1 install \
    && cd /opt/kaldi/local/lib \
    && ln -sf libopenblas.a libopenblas.so 2>/dev/null || true \
    && ln -sf libopenblas.a liblapack.a 2>/dev/null || true \
    && ln -sf libopenblas.a libblas.a 2>/dev/null || true \
    && ln -sf libopenblas.a libf2c.a 2>/dev/null || true

# 4. 编译 Android ARM64 Kaldi 核心引擎
RUN cd /opt/kaldi \
    && git clone -b vosk-android --single-branch --depth=1 https://github.com/alphacep/kaldi \
    && cd kaldi/src \
    && sed -i 's/-msse -msse2//g' configure \
    && CFLAGS="-O3 -fPIC" CXXFLAGS="-O3 -fPIC" ./configure --static --static-math=yes --use-cuda=no --android-incdir=$NDK/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include --host=$TARGET \
        --mathlib=OPENBLAS --openblas-root=/opt/kaldi/local \
        --fst-root=/opt/kaldi/local --fst-version=1.8.0 \
    && make depend -j \
    && make -j $(nproc) online2 rnnlm

# 5. 编译 Vosk API 并打包 Android arm64-v8a 目标产物 (libvosk.so, libvosk.a, vosk_api.h)
ARG VOSK_TAG=v0.3.50
RUN cd /opt \
    && if [ -n "$VOSK_TAG" ] && [ "$VOSK_TAG" != "master" ]; then \
           git clone -b "${VOSK_TAG}" --single-branch --depth=1 https://github.com/alphacep/vosk-api; \
       else \
           git clone --depth=1 https://github.com/alphacep/vosk-api; \
       fi \
    && cd vosk-api/src \
    && KALDI_ROOT=/opt/kaldi/kaldi OPENBLAS_ROOT=/opt/kaldi/local OPENFST_ROOT=/opt/kaldi/local EXT=so make -j $(nproc) \
            HAVE_ACCELERATE=0 \
            HAVE_OPENBLAS=1 \
            HAVE_MKL=0 \
            USE_SHARED=0 \
            EXTRA_CFLAGS="-O3 -fPIC" \
    && mkdir -p /opt/dist/android/arm64-v8a \
    && cp -fv vosk_api.h /opt/dist/android/arm64-v8a/vosk_api.h \
    && mkdir -p /opt/build_tmp \
    && cd /opt/build_tmp \
    && cp /opt/vosk-api/src/*.o . 2>/dev/null || true \
    && for lib in /opt/kaldi/kaldi/src/*/*.a /opt/kaldi/local/lib/*.a; do $AR x "$lib"; done \
    && $AR rcs /opt/dist/android/arm64-v8a/libvosk.a *.o \
    && $CXX -shared -Wl,-soname,libvosk.so -o /opt/dist/android/arm64-v8a/libvosk.so *.o -lm -ldl -llog \
    && rm -rf /opt/build_tmp

