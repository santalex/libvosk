# ==============================================================================
# Dockerfile - LibVosk Windows GNU (x86 32-bit) MinGW-w64 全自动化 Docker 构建沙盒
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
        g++-mingw-w64-i686-posix \
        gfortran-mingw-w64-i686 \
        python3 \
    && rm -rf /var/lib/apt/lists/*

COPY tools/slim_archive.py /opt/tools/slim_archive.py

# 1. 编译 Windows x86 (32-bit) OpenFST 库
RUN mkdir -p /opt/kaldi \
    && cd /opt/kaldi \
    && git clone --depth=1 https://github.com/alphacep/openfst \
    && cd openfst \
    && autoreconf -i \
    && CXX=i686-w64-mingw32-g++-posix CC=i686-w64-mingw32-gcc-posix AR=i686-w64-mingw32-ar \
        CFLAGS="-O3 -fPIC -msse -msse2 -mfpmath=sse -DFST_NO_DYNAMIC_LINKING" \
        CXXFLAGS="-O3 -fPIC -msse -msse2 -mfpmath=sse -DFST_NO_DYNAMIC_LINKING" ./configure --prefix=/opt/kaldi/local \
        --enable-shared --enable-static --with-pic --disable-bin \
        --enable-lookahead-fsts --enable-ngram-fsts --host=i686-w64-mingw32 \
    && make -j $(nproc) \
    && make install

# 2. 编译 Windows x86 (32-bit) OpenBLAS 核心数学库
RUN cd /opt/kaldi \
    && git clone -b v0.3.20 --single-branch --depth=1 https://github.com/xianyi/OpenBLAS \
    && cd OpenBLAS \
    && make HOSTCC=gcc BINARY=32 TARGET=NEHALEM CC=i686-w64-mingw32-gcc-posix AR=i686-w64-mingw32-ar CFLAGS="-msse -msse2 -mfpmath=sse" CXXFLAGS="-msse -msse2 -mfpmath=sse" ONLY_CBLAS=1 USE_LOCKING=1 USE_THREAD=0 -j $(nproc) \
    && make PREFIX=/opt/kaldi/local install

# 3. 编译 Windows x86 (32-bit) CLAPACK 库 (提供 libf2c.a, libblas.a, liblapack.a)
RUN cd /opt/kaldi \
    && git clone -b v3.2.1 --single-branch --depth=1 https://github.com/alphacep/clapack \
    && mkdir clapack/BUILD \
    && cd clapack/BUILD \
    && cmake -DCMAKE_C_COMPILER_TARGET=i686-w64-mingw32 -DCMAKE_C_COMPILER=i686-w64-mingw32-gcc-posix -DCMAKE_CXX_COMPILER=i686-w64-mingw32-g++-posix -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_CROSSCOMPILING=True .. \
    && make -C F2CLIBS/libf2c \
    && make -C BLAS \
    && make -C SRC \
    && find . -name "*.a" -exec cp {} /opt/kaldi/local/lib \;

# 4. 编译 Windows x86 (32-bit) Kaldi 核心引擎
RUN cd /opt/kaldi \
    && git clone -b vosk-android --single-branch --depth=1 https://github.com/alphacep/kaldi \
    && cd kaldi/src \
    && CXX=i686-w64-mingw32-g++-posix CC=i686-w64-mingw32-gcc-posix AR=i686-w64-mingw32-ar \
        CFLAGS="-O3 -fPIC -msse -msse2 -mfpmath=sse -DFST_NO_DYNAMIC_LINKING" \
        CXXFLAGS="-O3 -fPIC -msse -msse2 -mfpmath=sse -DFST_NO_DYNAMIC_LINKING" ./configure --shared --mingw=yes --use-cuda=no --host=i686-w64-mingw32 \
        --mathlib=OPENBLAS_CLAPACK --openblas-clapack-root=/opt/kaldi/local \
        --fst-root=/opt/kaldi/local --fst-version=1.8.0 \
    && make depend -j \
    && make -j $(nproc) online2 rnnlm

# 5. 编译 Vosk API 并打包 Windows x86 (32-bit) 目标产物
ARG VOSK_TAG=v0.3.50
RUN cd /opt \
    && if [ -n "$VOSK_TAG" ] && [ "$VOSK_TAG" != "master" ]; then \
           git clone -b "${VOSK_TAG}" --single-branch --depth=1 https://github.com/alphacep/vosk-api; \
       else \
           git clone --depth=1 https://github.com/alphacep/vosk-api; \
       fi \
    && cd vosk-api/src \
    && CXX=i686-w64-mingw32-g++-posix CC=i686-w64-mingw32-gcc-posix AR=i686-w64-mingw32-ar \
        KALDI_ROOT=/opt/kaldi/kaldi OPENBLAS_ROOT=/opt/kaldi/local OPENFST_ROOT=/opt/kaldi/local EXT=dll make -j $(nproc) \
            HAVE_ACCELERATE=0 \
            HAVE_OPENBLAS_CLAPACK=1 \
            HAVE_MKL=0 \
            USE_SHARED=0 \
            EXTRA_CFLAGS="-O3 -msse -msse2 -mfpmath=sse -DFST_NO_DYNAMIC_LINKING" \
            EXTRA_LDFLAGS="-Wl,--out-implib,libvosk.dll.a" \
    && mkdir -p /opt/dist/windows-gnu/x86 \
    && cp -fv libvosk.dll /opt/dist/windows-gnu/x86/libvosk.dll \
    && cp -fv libvosk.dll.a /opt/dist/windows-gnu/x86/libvosk.dll.a \
    && cp -fv libvosk.dll.a /opt/dist/windows-gnu/x86/libvosk.lib \
    && cp -fv vosk_api.h /opt/dist/windows-gnu/x86/vosk_api.h \
    && mkdir -p /opt/build_tmp \
    && cd /opt/build_tmp \
    && cp /opt/vosk-api/src/*.o . 2>/dev/null || true \
    && for lib in /opt/kaldi/kaldi/src/*/*.a /opt/kaldi/local/lib/*.a; do i686-w64-mingw32-ar x "$lib"; done \
    && i686-w64-mingw32-strip --strip-debug *.o 2>/dev/null || true \
    && i686-w64-mingw32-ar rcs /opt/dist/windows-gnu/x86/libvosk.a *.o \
    && rm -rf /opt/build_tmp \
    && python3 /opt/tools/slim_archive.py /opt/dist/windows-gnu/x86/libvosk.a /opt/dist/windows-gnu/x86/libvosk.a --header /opt/dist/windows-gnu/x86/vosk_api.h --nm i686-w64-mingw32-nm --ar i686-w64-mingw32-ar \
    && cp -fv /opt/dist/windows-gnu/x86/libvosk.a /opt/dist/windows-gnu/x86/libvosk_static.lib
