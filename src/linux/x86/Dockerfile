# ==============================================================================
# Dockerfile.linuxx86 - ReaVox Linux (x86 32-bit) Vosk API 全自动化 Docker 构建沙盒
# ==============================================================================
FROM ubuntu:20.04

RUN apt-get update -o Acquire::Retries=3 && \
    DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC apt-get install -y \
        -o Acquire::Retries=3 \
        -o Acquire::http::Timeout="30" \
        --no-install-recommends \
        ca-certificates \
        g++ \
        g++-multilib \
        gcc-multilib \
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
    && ln -sf /usr/bin/g++ /usr/local/bin/i686-linux-gnu-c++ \
    && ln -sf /usr/bin/g++ /usr/local/bin/i686-linux-gnu-g++ \
    && ln -sf /usr/bin/gcc /usr/local/bin/i686-linux-gnu-gcc \
    && ln -sf /usr/bin/ar /usr/local/bin/i686-linux-gnu-ar \
    && ln -sf /usr/bin/ranlib /usr/local/bin/i686-linux-gnu-ranlib \
    && ln -sf /usr/bin/strip /usr/local/bin/i686-linux-gnu-strip \
    && rm -rf /var/lib/apt/lists/*


# 1. 编译 Linux x86 (32-bit) OpenFST 库
RUN mkdir -p /opt/kaldi \
    && cd /opt/kaldi \
    && git clone --depth=1 https://github.com/alphacep/openfst \
    && cd openfst \
    && autoreconf -i \
    && CFLAGS="-O3 -fPIC -m32 -msse -msse2 -mfpmath=sse" CXXFLAGS="-O3 -fPIC -m32 -msse -msse2 -mfpmath=sse" ./configure --prefix=/opt/kaldi/local \
        --enable-shared --enable-static --with-pic --disable-bin \
        --enable-lookahead-fsts --enable-ngram-fsts --host=i686-linux-gnu \
    && make -j $(nproc) \
    && make install

# 2. 编译 Linux x86 (32-bit) OpenBLAS 核心数学库
RUN cd /opt/kaldi \
    && git clone -b v0.3.20 --single-branch --depth=1 https://github.com/xianyi/OpenBLAS \
    && cd OpenBLAS \
    && make HOSTCC=gcc BINARY=32 CFLAGS="-m32 -msse -msse2 -mfpmath=sse" CXXFLAGS="-m32 -msse -msse2 -mfpmath=sse" ONLY_CBLAS=1 DYNAMIC_ARCH=1 USE_LOCKING=1 USE_THREAD=0 NO_FORTRAN=1 NO_SHARED=1 -j $(nproc) \
    && make PREFIX=/opt/kaldi/local NO_SHARED=1 install \
    && cd /opt/kaldi/local/lib \
    && ln -sf libopenblas.a libopenblas.so 2>/dev/null || true \
    && ln -sf libopenblas.a liblapack.a 2>/dev/null || true \
    && ln -sf libopenblas.a libblas.a 2>/dev/null || true \
    && ln -sf libopenblas.a libf2c.a 2>/dev/null || true

# 3. 编译 Linux x86 (32-bit) Kaldi 核心引擎
RUN cd /opt/kaldi \
    && git clone -b vosk --single-branch --depth=1 https://github.com/alphacep/kaldi \
    && cd kaldi/src \
    && CXX="g++ -m32" CC="gcc -m32" CFLAGS="-O3 -fPIC -m32 -msse -msse2 -mfpmath=sse" CXXFLAGS="-O3 -fPIC -m32 -msse -msse2 -mfpmath=sse" ./configure --static --static-math=yes --use-cuda=no --host=i686-linux-gnu \
        --mathlib=OPENBLAS --openblas-root=/opt/kaldi/local \
        --fst-root=/opt/kaldi/local --fst-version=1.8.0 \
    && make depend -j \
    && make -j $(nproc) online2 rnnlm


# 4. 编译 Vosk API 并打包 Linux x86 (32-bit) 目标产物 (libvosk.so, libvosk.a, vosk_api.h)
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
            EXTRA_CFLAGS="-O3 -fPIC -m32 -msse -msse2 -mfpmath=sse" \
            EXTRA_LDFLAGS="-m32" \
 \
    && mkdir -p /opt/dist/linux/x86 \
    && cp -fv libvosk.so /opt/dist/linux/x86/libvosk.so \
    && cp -fv vosk_api.h /opt/dist/linux/x86/vosk_api.h \
    && mkdir -p /opt/build_tmp \
    && cd /opt/build_tmp \
    && cp /opt/vosk-api/src/*.o . 2>/dev/null || true \
    && for lib in /opt/kaldi/kaldi/src/*/*.a /opt/kaldi/local/lib/*.a; do ar x "$lib"; done \
    && ar rcs /opt/dist/linux/x86/libvosk.a *.o \
    && rm -rf /opt/build_tmp
