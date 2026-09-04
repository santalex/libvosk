#!/bin/bash
set -e

# ==============================================================================
# build.sh - Vosk API Apple Native (macOS, iOS, tvOS, visionOS) Build Engine
#
# Supported features:
#   1. macOS (arm64 Apple Silicon & x86_64 Intel) dynamic (.dylib) + static (.a)
#   2. lipo synthesis for macOS Universal fat binaries
#   3. iOS (iphoneos arm64 & iphonesimulator arm64/x86_64) static libraries
#   4. tvOS (appletvos arm64 & appletvsimulator arm64/x86_64) static libraries
#   5. visionOS (xros arm64 & xrsimulator arm64) static libraries
#   6. xcodebuild assembly for cross-platform libvosk.xcframework
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DIST_DIR="${DIST_DIR:-${REPO_ROOT}/dist}"
COMMAND="${1:-macos}"
SPECIFIED_ARCH="$2"

DEPLOYMENT_TARGET_MACOS="11.0"
DEPLOYMENT_TARGET_IOS="12.0"
DEPLOYMENT_TARGET_TVOS="12.0"
DEPLOYMENT_TARGET_VISIONOS="1.0"
export MACOSX_DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET_MACOS}"
export MAKEFLAGS="-s --no-print-directory"
# Ensure Apple Xcode toolchain is prioritized to prevent external LLVM contamination
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH}"

MACOS_SDK_PATH=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)
IPHONEOS_SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)
IPHONESIMULATOR_SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null || true)
APPLETVOS_SDK_PATH=$(xcrun --sdk appletvos --show-sdk-path 2>/dev/null || true)
APPLETVSIMULATOR_SDK_PATH=$(xcrun --sdk appletvsimulator --show-sdk-path 2>/dev/null || true)
XROS_SDK_PATH=$(xcrun --sdk xros --show-sdk-path 2>/dev/null || true)
XRSIMULATOR_SDK_PATH=$(xcrun --sdk xrsimulator --show-sdk-path 2>/dev/null || true)

show_help() {
    echo "=============================================================================="
    echo "  Vosk API Apple (macOS / iOS / tvOS / visionOS) Native Build Engine"
    echo "=============================================================================="
    echo "Usage:"
    echo "  ./build.sh [platform] [arch]"
    echo ""
    echo "Supported platforms (platform):"
    echo "  macos      - Build macOS dynamic (.dylib), static (.a) and XCFramework"
    echo "  ios        - Build iOS device & simulator static libs, package XCFramework"
    echo "  tvos       - Build tvOS device & simulator static libs, package XCFramework"
    echo "  visionos   - Build visionOS device & simulator static libs, package XCFramework"
    echo "  all        - Build all Apple platforms and assemble Apple Super XCFramework"
    echo "  help | -h  - Show this help message"
    echo ""
    echo "Supported architectures (arch, macOS only):"
    echo "  arm64      - Target Apple Silicon (M1/M2/M3/M4) (macOS 11.0+)"
    echo "  x86_64     - Target Intel 64-bit CPU (macOS 11.0+)"
    echo "  universal  - Build both x86_64 & arm64 and lipo into Universal fat binary"
    echo "  (default)  - Auto-detect host CPU architecture (detected: $(uname -m))"
    echo ""
    echo "Examples:"
    echo "  ./build.sh macos            # Build macOS libraries for current host arch"
    echo "  ./build.sh macos arm64      # Build macOS ARM64 library"
    echo "  ./build.sh macos universal  # Build macOS Universal fat binary"
    echo "  ./build.sh ios              # Build iOS static libraries and XCFramework"
    echo "  ./build.sh tvos             # Build tvOS static libraries and XCFramework"
    echo "  ./build.sh visionos         # Build visionOS static libraries and XCFramework"
    echo "  ./build.sh all              # Build full Apple platforms and Super XCFramework"
    echo "=============================================================================="
}

# ------------------------------------------------------------------------------
# Dependency Preparation (Kaldi & Vosk API)
# ------------------------------------------------------------------------------
prepare_dependencies() {
    cd "${SCRIPT_DIR}"

    if ! command -v autoreconf &> /dev/null; then
        echo "--> autoreconf not found, installing autoconf automake libtool via Homebrew..."
        brew install autoconf automake libtool 2>/dev/null || true
    fi

    if [ ! -d "kaldi" ]; then
        echo "--> Cloning Vosk-adapted Kaldi source repository..."
        git clone -b vosk-android --single-branch --depth=1 https://github.com/alphacep/kaldi kaldi
    fi

    if [ -f "kaldi/tools/Makefile" ]; then
        sed -i '' 's/extras\/check_dependencies.sh/true/g' kaldi/tools/Makefile 2>/dev/null || true
    fi
    if [ -f "kaldi/tools/extras/check_dependencies.sh" ]; then
        sed -i '' 's/exit 1/exit 0/g' kaldi/tools/extras/check_dependencies.sh 2>/dev/null || true
    fi

    if [ ! -d "kaldi/tools/openfst-1.8.0" ]; then
        echo "--> Compiling OpenFST for Apple platforms..."
        cd kaldi/tools
        git clone -q --depth=1 https://github.com/alphacep/openfst openfst-1.8.0
        make -s openfst LIBTOOLFLAGS="--silent" OPENFST_CONFIGURE="--enable-silent-rules"
        cd "${SCRIPT_DIR}"
    fi

    if [ ! -d "vosk-api" ]; then
        echo "--> Cloning Vosk API source repository..."
        local TAG_ARG=""
        if [ -n "$VOSK_TAG" ] && [ "$VOSK_TAG" != "master" ]; then
            TAG_ARG="-b ${VOSK_TAG}"
        fi
        git clone ${TAG_ARG} --single-branch --depth=1 https://github.com/alphacep/vosk-api vosk-api
        if [ -f "vosk-api/src/Makefile" ]; then
            sed -i '' 's/-g -O3/-O3/g' vosk-api/src/Makefile || true
        fi
    fi
}

# ------------------------------------------------------------------------------
# Helper: OpenFST Compilation
# ------------------------------------------------------------------------------
compile_openfst() {
    local ARCH_FLAGS=$1
    local HOST_FLAGS=$2

    cd "${SCRIPT_DIR}/kaldi/tools"
    if [ -f Makefile ]; then
        sed -i '' 's/-msse -msse2//g' Makefile
    fi
    if [ -d "openfst-1.8.0" ] && [ -f "openfst-1.8.0/Makefile" ]; then
        make -C openfst-1.8.0 clean || true
    fi
    rm -f openfst-1.8.0/Makefile || true

    local APPLE_CC=$(xcrun -f clang)
    local APPLE_CXX=$(xcrun -f clang++)

    make -s -j$(sysctl -n hw.ncpu) openfst \
        OPENFST_CONFIGURE="${HOST_FLAGS} --enable-silent-rules --enable-static --enable-shared --enable-far --enable-ngram-fsts --enable-lookahead-fsts --with-pic" \
        LIBTOOLFLAGS="--silent" \
        CC="${APPLE_CC} ${ARCH_FLAGS}" \
        CXX="${APPLE_CXX} ${ARCH_FLAGS}" \
        CXXFLAGS="-O3 ${ARCH_FLAGS}" CFLAGS="-O3 ${ARCH_FLAGS}" LDFLAGS="${ARCH_FLAGS}"
}

# ------------------------------------------------------------------------------
# Helper: Kaldi Compilation
# ------------------------------------------------------------------------------
compile_kaldi() {
    local ARCH_FLAGS=$1
    local IS_SHARED=$2

    local SHARED_ARG="--static"
    if [ "$IS_SHARED" = "1" ]; then
        SHARED_ARG="--shared"
    fi

    cd "${SCRIPT_DIR}/kaldi/src"
    make clean || true
    find . -name ".depend" -delete 2>/dev/null || true
    CXXFLAGS="${ARCH_FLAGS}" CFLAGS="${ARCH_FLAGS}" LDFLAGS="${ARCH_FLAGS}" ./configure ${SHARED_ARG} --use-cuda=no

    if [ -f kaldi.mk ]; then
        sed -i '' 's/-msse -msse2//g' kaldi.mk
    fi
    make -s depend -j$(sysctl -n hw.ncpu)
    CXXFLAGS="${ARCH_FLAGS}" CFLAGS="${ARCH_FLAGS}" LDFLAGS="${ARCH_FLAGS}" \
        make -s -j$(sysctl -n hw.ncpu) online2 lm rnnlm
}

# ------------------------------------------------------------------------------
# Helper: Static Library Archiving and Slimming
# ------------------------------------------------------------------------------
archive_static_lib() {
    local OUT_DIR=$1
    local KALDI_ROOT="${SCRIPT_DIR}/kaldi"

    mkdir -p "${OUT_DIR}"

    echo "--> Archiving static library..."
    /usr/bin/libtool -static -o "${OUT_DIR}/libvosk.a" \
        *.o \
        "${KALDI_ROOT}/src/online2/kaldi-online2.a" \
        "${KALDI_ROOT}/src/decoder/kaldi-decoder.a" \
        "${KALDI_ROOT}/src/ivector/kaldi-ivector.a" \
        "${KALDI_ROOT}/src/cudamatrix/kaldi-cudamatrix.a" \
        "${KALDI_ROOT}/src/transform/kaldi-transform.a" \
        "${KALDI_ROOT}/src/chain/kaldi-chain.a" \
        "${KALDI_ROOT}/src/nnet3/kaldi-nnet3.a" \
        "${KALDI_ROOT}/src/gmm/kaldi-gmm.a" \
        "${KALDI_ROOT}/src/tree/kaldi-tree.a" \
        "${KALDI_ROOT}/src/feat/kaldi-feat.a" \
        "${KALDI_ROOT}/src/lat/kaldi-lat.a" \
        "${KALDI_ROOT}/src/lm/kaldi-lm.a" \
        "${KALDI_ROOT}/src/rnnlm/kaldi-rnnlm.a" \
        "${KALDI_ROOT}/src/hmm/kaldi-hmm.a" \
        "${KALDI_ROOT}/src/matrix/kaldi-matrix.a" \
        "${KALDI_ROOT}/src/fstext/kaldi-fstext.a" \
        "${KALDI_ROOT}/src/util/kaldi-util.a" \
        "${KALDI_ROOT}/src/base/kaldi-base.a" \
        "${KALDI_ROOT}/tools/openfst-1.8.0/lib/libfst.a" \
        "${KALDI_ROOT}/tools/openfst-1.8.0/lib/libfstngram.a"

    local SLIM_TOOL="${SCRIPT_DIR}/../../tools/slim_archive.py"
    if [ -f "${SLIM_TOOL}" ]; then
        python3 "${SLIM_TOOL}" "${OUT_DIR}/libvosk.a" "${OUT_DIR}/libvosk.a" --header "${SCRIPT_DIR}/vosk-api/src/vosk_api.h" 2>/dev/null || true
    fi
    strip -S "${OUT_DIR}/libvosk.a" 2>/dev/null || true
    ranlib -no_warning_for_no_symbols -c "${OUT_DIR}/libvosk.a" 2>/dev/null || ranlib "${OUT_DIR}/libvosk.a" 2>/dev/null || true

    cp -fv "${SCRIPT_DIR}/vosk-api/src/vosk_api.h" "${OUT_DIR}/vosk_api.h" 2>/dev/null || true
    local LIB_SIZE=$(du -sh "${OUT_DIR}/libvosk.a" | cut -f1)
    echo "[OK] Static library packaged: ${OUT_DIR}/libvosk.a (${LIB_SIZE})"
}

# ------------------------------------------------------------------------------
# Helper: Prepare Headers
# ------------------------------------------------------------------------------
prepare_headers() {
    local HEADERS_DIR="${DIST_DIR}/headers"
    mkdir -p "${HEADERS_DIR}"
    cp -f "${SCRIPT_DIR}/vosk-api/src/vosk_api.h" "${HEADERS_DIR}/"
    echo "${HEADERS_DIR}"
}

# ------------------------------------------------------------------------------
# 1. Build macOS Dynamic Shared Library (.dylib)
# ------------------------------------------------------------------------------
build_macos_shared() {
    local TARGET_ARCH=$1
    local SDK_PATH="${MACOS_SDK_PATH}"
    local KALDI_ROOT="${SCRIPT_DIR}/kaldi"

    echo "--> Building macOS dynamic library (.dylib) [${TARGET_ARCH}] (minOS: ${DEPLOYMENT_TARGET_MACOS})..."
    local ARCH_FLAGS="-arch ${TARGET_ARCH} -isysroot ${SDK_PATH} -mmacosx-version-min=${DEPLOYMENT_TARGET_MACOS}"
    local HOST_FLAGS="--host=${TARGET_ARCH}-apple-darwin"

    compile_openfst "${ARCH_FLAGS}" "${HOST_FLAGS}"
    compile_kaldi "${ARCH_FLAGS}" 1

    cd "${SCRIPT_DIR}/vosk-api/src"
    make clean || true
    KALDI_ROOT="${KALDI_ROOT}" EXT=dylib make -s -j$(sysctl -n hw.ncpu) \
        OPENFST_ROOT="${KALDI_ROOT}/tools/openfst-1.8.0" \
        HAVE_ACCELERATE=1 \
        HAVE_OPENBLAS_CLAPACK=0 \
        HAVE_MKL=0 \
        USE_SHARED=0 \
        EXTRA_CFLAGS="${ARCH_FLAGS}" \
        EXTRA_LDFLAGS="${ARCH_FLAGS} -Wl,-install_name,@rpath/libvosk.dylib"

    local OUT_DIR="${DIST_DIR}/macos/${TARGET_ARCH}"
    mkdir -p "${OUT_DIR}"
    cp -fv libvosk.dylib "${OUT_DIR}/libvosk.dylib"
    cp -fv vosk_api.h "${OUT_DIR}/vosk_api.h"
    echo "[OK] macOS dynamic library built [${TARGET_ARCH}]: ${OUT_DIR}/libvosk.dylib"
}

# ------------------------------------------------------------------------------
# 2. Build macOS Static Library (.a)
# ------------------------------------------------------------------------------
build_macos_static() {
    local TARGET_ARCH=$1
    local SDK_PATH="${MACOS_SDK_PATH}"
    local KALDI_ROOT="${SCRIPT_DIR}/kaldi"

    echo "--> Building macOS static library (.a) [${TARGET_ARCH}] (minOS: ${DEPLOYMENT_TARGET_MACOS})..."
    local ARCH_FLAGS="-arch ${TARGET_ARCH} -isysroot ${SDK_PATH} -mmacosx-version-min=${DEPLOYMENT_TARGET_MACOS}"
    local HOST_FLAGS="--host=${TARGET_ARCH}-apple-darwin"

    compile_openfst "${ARCH_FLAGS}" "${HOST_FLAGS}"
    compile_kaldi "${ARCH_FLAGS}" 0

    cd "${SCRIPT_DIR}/vosk-api/src"
    make clean || true
    make -s -j$(sysctl -n hw.ncpu) \
        recognizer.o language_model.o model.o spk_model.o vosk_api.o postprocessor.o \
        KALDI_ROOT="${KALDI_ROOT}" \
        OPENFST_ROOT="${KALDI_ROOT}/tools/openfst-1.8.0" \
        HAVE_ACCELERATE=1 \
        HAVE_OPENBLAS_CLAPACK=0 \
        HAVE_MKL=0 \
        USE_SHARED=0 \
        EXTRA_CFLAGS="${ARCH_FLAGS}" \
        EXTRA_LDFLAGS="${ARCH_FLAGS}"

    local OUT_DIR="${DIST_DIR}/macos/${TARGET_ARCH}"
    archive_static_lib "${OUT_DIR}"

    echo "[OK] macOS static library packaged [${TARGET_ARCH}]: ${OUT_DIR}/libvosk.a"
}

# ------------------------------------------------------------------------------
# 3. Build iOS Static Library
# ------------------------------------------------------------------------------
build_ios_static() {
    local SDK=$1
    local TARGET_ARCH=$2
    local SDK_PATH=$3
    local KALDI_ROOT="${SCRIPT_DIR}/kaldi"

    echo "--> Building iOS static library [${SDK} / ${TARGET_ARCH}]..."

    local SDK_FLAG=""
    local PLATFORM_NAME=""
    if [ "$SDK" = "iphoneos" ]; then
        SDK_FLAG="-miphoneos-version-min=${DEPLOYMENT_TARGET_IOS}"
        PLATFORM_NAME="iphoneos"
    else
        SDK_FLAG="-mios-simulator-version-min=${DEPLOYMENT_TARGET_IOS}"
        PLATFORM_NAME="iphonesimulator"
    fi

    local ARCH_FLAGS="-arch ${TARGET_ARCH} -isysroot ${SDK_PATH} ${SDK_FLAG}"
    local HOST_FLAGS="--host=${TARGET_ARCH}-apple-darwin"

    compile_openfst "${ARCH_FLAGS}" "${HOST_FLAGS}"
    compile_kaldi "${ARCH_FLAGS}" 0

    cd "${SCRIPT_DIR}/vosk-api/src"
    make clean || true
    make -s -j$(sysctl -n hw.ncpu) \
        recognizer.o language_model.o model.o spk_model.o vosk_api.o postprocessor.o \
        KALDI_ROOT="${KALDI_ROOT}" \
        OPENFST_ROOT="${KALDI_ROOT}/tools/openfst-1.8.0" \
        HAVE_ACCELERATE=1 \
        HAVE_OPENBLAS_CLAPACK=0 \
        HAVE_MKL=0 \
        USE_SHARED=0 \
        EXTRA_CFLAGS="${ARCH_FLAGS}" \
        EXTRA_LDFLAGS="${ARCH_FLAGS}"

    local OUT_DIR="${DIST_DIR}/ios/${PLATFORM_NAME}_${TARGET_ARCH}"
    archive_static_lib "${OUT_DIR}"

    echo "[OK] iOS static library packaged [${PLATFORM_NAME}_${TARGET_ARCH}]: ${OUT_DIR}/libvosk.a"
}

# ------------------------------------------------------------------------------
# 4. Build tvOS Static Library
# ------------------------------------------------------------------------------
build_tvos_static() {
    local SDK=$1
    local TARGET_ARCH=$2
    local SDK_PATH=$3
    local KALDI_ROOT="${SCRIPT_DIR}/kaldi"

    echo "--> Building tvOS static library [${SDK} / ${TARGET_ARCH}]..."

    local SDK_FLAG=""
    local PLATFORM_NAME=""
    if [ "$SDK" = "appletvos" ]; then
        SDK_FLAG="-mtvos-version-min=${DEPLOYMENT_TARGET_TVOS}"
        PLATFORM_NAME="appletvos"
    else
        SDK_FLAG="-mtvos-simulator-version-min=${DEPLOYMENT_TARGET_TVOS}"
        PLATFORM_NAME="appletvsimulator"
    fi

    local ARCH_FLAGS="-arch ${TARGET_ARCH} -isysroot ${SDK_PATH} ${SDK_FLAG}"
    local HOST_FLAGS="--host=${TARGET_ARCH}-apple-darwin"

    compile_openfst "${ARCH_FLAGS}" "${HOST_FLAGS}"
    compile_kaldi "${ARCH_FLAGS}" 0

    cd "${SCRIPT_DIR}/vosk-api/src"
    make clean || true
    make -s -j$(sysctl -n hw.ncpu) \
        recognizer.o language_model.o model.o spk_model.o vosk_api.o postprocessor.o \
        KALDI_ROOT="${KALDI_ROOT}" \
        OPENFST_ROOT="${KALDI_ROOT}/tools/openfst-1.8.0" \
        HAVE_ACCELERATE=1 \
        HAVE_OPENBLAS_CLAPACK=0 \
        HAVE_MKL=0 \
        USE_SHARED=0 \
        EXTRA_CFLAGS="${ARCH_FLAGS}" \
        EXTRA_LDFLAGS="${ARCH_FLAGS}"

    local OUT_DIR="${DIST_DIR}/tvos/${PLATFORM_NAME}_${TARGET_ARCH}"
    archive_static_lib "${OUT_DIR}"

    echo "[OK] tvOS static library packaged [${PLATFORM_NAME}_${TARGET_ARCH}]: ${OUT_DIR}/libvosk.a"
}

# ------------------------------------------------------------------------------
# 5. Combined Helper for macOS Target (Shared + Static)
# ------------------------------------------------------------------------------
build_macos_target_combined() {
    local TARGET_ARCH=$1
    echo "========================================================="
    echo ">> Building macOS dynamic & static libraries [ ${TARGET_ARCH} ]..."
    echo "========================================================="

    build_macos_shared "${TARGET_ARCH}"
    build_macos_static "${TARGET_ARCH}"

    echo "[OK] macOS [ ${TARGET_ARCH} ] build complete -> ${DIST_DIR}/macos/${TARGET_ARCH}/"
}

# ------------------------------------------------------------------------------
# 6. High-level Multi-arch Builders (macOS / iOS / tvOS / visionOS / All)
# ------------------------------------------------------------------------------
build_macos_all() {
    echo "--> Building macOS Universal (arm64 + x86_64) libraries & XCFramework..."
    build_macos_target_combined "x86_64"
    build_macos_target_combined "arm64"

    mkdir -p "${DIST_DIR}/macos/universal"

    lipo -create \
        "${DIST_DIR}/macos/x86_64/libvosk.dylib" \
        "${DIST_DIR}/macos/arm64/libvosk.dylib" \
        -output "${DIST_DIR}/macos/universal/libvosk.dylib"

    lipo -create \
        "${DIST_DIR}/macos/x86_64/libvosk.a" \
        "${DIST_DIR}/macos/arm64/libvosk.a" \
        -output "${DIST_DIR}/macos/universal/libvosk.a"

    cp -fv "${SCRIPT_DIR}/vosk-api/src/vosk_api.h" "${DIST_DIR}/macos/universal/vosk_api.h" 2>/dev/null || true

    local HEADERS_DIR=$(prepare_headers)

    local MACOS_XCFRAMEWORK_DIR="${DIST_DIR}/macos/libvosk.xcframework"
    rm -rf "${MACOS_XCFRAMEWORK_DIR}"
    xcodebuild -create-xcframework \
        -library "${DIST_DIR}/macos/universal/libvosk.a" \
        -headers "${HEADERS_DIR}" \
        -output "${MACOS_XCFRAMEWORK_DIR}"

    echo "[OK] macOS Universal dynamic library: dist/macos/universal/libvosk.dylib"
    echo "[OK] macOS Universal static library: dist/macos/universal/libvosk.a"
    echo "[OK] macOS libvosk.xcframework: ${MACOS_XCFRAMEWORK_DIR}"
}

build_ios_all() {
    echo "--> Building iOS platform static libraries & XCFramework..."
    mkdir -p "${DIST_DIR}/ios/iphonesimulator_universal"

    if [ -n "${IPHONEOS_SDK_PATH}" ]; then
        build_ios_static "iphoneos" "arm64" "${IPHONEOS_SDK_PATH}"
    fi
    if [ -n "${IPHONESIMULATOR_SDK_PATH}" ]; then
        build_ios_static "iphonesimulator" "arm64" "${IPHONESIMULATOR_SDK_PATH}"
        build_ios_static "iphonesimulator" "x86_64" "${IPHONESIMULATOR_SDK_PATH}"

        lipo -create \
            "${DIST_DIR}/ios/iphonesimulator_arm64/libvosk.a" \
            "${DIST_DIR}/ios/iphonesimulator_x86_64/libvosk.a" \
            -output "${DIST_DIR}/ios/iphonesimulator_universal/libvosk.a"
    fi

    local HEADERS_DIR=$(prepare_headers)

    local XCFRAMEWORK_DIR="${DIST_DIR}/ios/libvosk.xcframework"
    rm -rf "${XCFRAMEWORK_DIR}"
    
    local XCF_ARGS=()
    if [ -f "${DIST_DIR}/ios/iphoneos_arm64/libvosk.a" ]; then
        XCF_ARGS+=(-library "${DIST_DIR}/ios/iphoneos_arm64/libvosk.a" -headers "${HEADERS_DIR}")
    fi
    if [ -f "${DIST_DIR}/ios/iphonesimulator_universal/libvosk.a" ]; then
        XCF_ARGS+=(-library "${DIST_DIR}/ios/iphonesimulator_universal/libvosk.a" -headers "${HEADERS_DIR}")
    fi

    if [ ${#XCF_ARGS[@]} -gt 0 ]; then
        xcodebuild -create-xcframework "${XCF_ARGS[@]}" -output "${XCFRAMEWORK_DIR}"
        echo "[OK] Generated iOS libvosk.xcframework: ${XCFRAMEWORK_DIR}"
    fi
}

build_tvos_all() {
    echo "--> Building tvOS platform static libraries & XCFramework..."
    mkdir -p "${DIST_DIR}/tvos/appletvsimulator_universal"

    if [ -n "${APPLETVOS_SDK_PATH}" ]; then
        build_tvos_static "appletvos" "arm64" "${APPLETVOS_SDK_PATH}"
    fi
    if [ -n "${APPLETVSIMULATOR_SDK_PATH}" ]; then
        build_tvos_static "appletvsimulator" "arm64" "${APPLETVSIMULATOR_SDK_PATH}"
        build_tvos_static "appletvsimulator" "x86_64" "${APPLETVSIMULATOR_SDK_PATH}"

        lipo -create \
            "${DIST_DIR}/tvos/appletvsimulator_arm64/libvosk.a" \
            "${DIST_DIR}/tvos/appletvsimulator_x86_64/libvosk.a" \
            -output "${DIST_DIR}/tvos/appletvsimulator_universal/libvosk.a"
    fi

    local HEADERS_DIR=$(prepare_headers)

    local XCFRAMEWORK_DIR="${DIST_DIR}/tvos/libvosk.xcframework"
    rm -rf "${XCFRAMEWORK_DIR}"
    
    local XCF_ARGS=()
    if [ -f "${DIST_DIR}/tvos/appletvos_arm64/libvosk.a" ]; then
        XCF_ARGS+=(-library "${DIST_DIR}/tvos/appletvos_arm64/libvosk.a" -headers "${HEADERS_DIR}")
    fi
    if [ -f "${DIST_DIR}/tvos/appletvsimulator_universal/libvosk.a" ]; then
        XCF_ARGS+=(-library "${DIST_DIR}/tvos/appletvsimulator_universal/libvosk.a" -headers "${HEADERS_DIR}")
    fi

    if [ ${#XCF_ARGS[@]} -gt 0 ]; then
        xcodebuild -create-xcframework "${XCF_ARGS[@]}" -output "${XCFRAMEWORK_DIR}"
        echo "[OK] Generated tvOS libvosk.xcframework: ${XCFRAMEWORK_DIR}"
    fi
}

build_visionos_static() {
    local SDK=$1
    local TARGET_ARCH=$2
    local SDK_PATH=$3
    local KALDI_ROOT="${SCRIPT_DIR}/kaldi"

    echo "--> Building visionOS static library [${SDK} / ${TARGET_ARCH}]..."

    local TARGET_TRIPLE=""
    local PLATFORM_NAME=""
    if [ "$SDK" = "xros" ]; then
        TARGET_TRIPLE="arm64-apple-xros${DEPLOYMENT_TARGET_VISIONOS}"
        PLATFORM_NAME="xros"
    else
        TARGET_TRIPLE="arm64-apple-xros${DEPLOYMENT_TARGET_VISIONOS}-simulator"
        PLATFORM_NAME="xrsimulator"
    fi

    local ARCH_FLAGS="-target ${TARGET_TRIPLE} -isysroot ${SDK_PATH}"
    local HOST_FLAGS="--host=aarch64-apple-darwin"

    compile_openfst "${ARCH_FLAGS}" "${HOST_FLAGS}"
    compile_kaldi "${ARCH_FLAGS}" 0

    cd "${SCRIPT_DIR}/vosk-api/src"
    make clean || true
    make -s -j$(sysctl -n hw.ncpu) \
        recognizer.o language_model.o model.o spk_model.o vosk_api.o postprocessor.o \
        KALDI_ROOT="${KALDI_ROOT}" \
        OPENFST_ROOT="${KALDI_ROOT}/tools/openfst-1.8.0" \
        HAVE_ACCELERATE=1 \
        HAVE_OPENBLAS_CLAPACK=0 \
        HAVE_MKL=0 \
        USE_SHARED=0 \
        EXTRA_CFLAGS="${ARCH_FLAGS}" \
        EXTRA_LDFLAGS="${ARCH_FLAGS}"

    local OUT_DIR="${DIST_DIR}/visionos/${PLATFORM_NAME}_${TARGET_ARCH}"
    archive_static_lib "${OUT_DIR}"

    echo "[OK] visionOS static library packaged [${PLATFORM_NAME}_${TARGET_ARCH}]: ${OUT_DIR}/libvosk.a"
}

build_visionos_all() {
    echo "--> Building visionOS platform static libraries & XCFramework..."
    if [ -n "${XROS_SDK_PATH}" ]; then
        build_visionos_static "xros" "arm64" "${XROS_SDK_PATH}"
    fi
    if [ -n "${XRSIMULATOR_SDK_PATH}" ]; then
        build_visionos_static "xrsimulator" "arm64" "${XRSIMULATOR_SDK_PATH}"
    fi

    local HEADERS_DIR=$(prepare_headers)
    local XCFRAMEWORK_DIR="${DIST_DIR}/visionos/libvosk.xcframework"
    rm -rf "${XCFRAMEWORK_DIR}"
    
    local XCF_ARGS=()
    if [ -f "${DIST_DIR}/visionos/xros_arm64/libvosk.a" ]; then
        XCF_ARGS+=(-library "${DIST_DIR}/visionos/xros_arm64/libvosk.a" -headers "${HEADERS_DIR}")
    fi
    if [ -f "${DIST_DIR}/visionos/xrsimulator_arm64/libvosk.a" ]; then
        XCF_ARGS+=(-library "${DIST_DIR}/visionos/xrsimulator_arm64/libvosk.a" -headers "${HEADERS_DIR}")
    fi

    if [ ${#XCF_ARGS[@]} -gt 0 ]; then
        xcodebuild -create-xcframework "${XCF_ARGS[@]}" -output "${XCFRAMEWORK_DIR}"
        echo "[OK] Generated visionOS libvosk.xcframework: ${XCFRAMEWORK_DIR}"
    fi
}

build_apple_all() {
    echo "--> Building Apple multi-platform (macOS + iOS + tvOS + visionOS) Super XCFramework..."
    build_macos_all
    build_ios_all
    build_tvos_all
    build_visionos_all

    local HEADERS_DIR=$(prepare_headers)

    local XCFRAMEWORK_DIR="${DIST_DIR}/apple-xcframework/libvosk.xcframework"
    rm -rf "${XCFRAMEWORK_DIR}"
    
    local XCF_ARGS=()
    if [ -f "${DIST_DIR}/macos/universal/libvosk.a" ]; then
        XCF_ARGS+=(-library "${DIST_DIR}/macos/universal/libvosk.a" -headers "${HEADERS_DIR}")
    fi
    if [ -f "${DIST_DIR}/ios/iphoneos_arm64/libvosk.a" ]; then
        XCF_ARGS+=(-library "${DIST_DIR}/ios/iphoneos_arm64/libvosk.a" -headers "${HEADERS_DIR}")
    fi
    if [ -f "${DIST_DIR}/ios/iphonesimulator_universal/libvosk.a" ]; then
        XCF_ARGS+=(-library "${DIST_DIR}/ios/iphonesimulator_universal/libvosk.a" -headers "${HEADERS_DIR}")
    fi
    if [ -f "${DIST_DIR}/tvos/appletvos_arm64/libvosk.a" ]; then
        XCF_ARGS+=(-library "${DIST_DIR}/tvos/appletvos_arm64/libvosk.a" -headers "${HEADERS_DIR}")
    fi
    if [ -f "${DIST_DIR}/tvos/appletvsimulator_universal/libvosk.a" ]; then
        XCF_ARGS+=(-library "${DIST_DIR}/tvos/appletvsimulator_universal/libvosk.a" -headers "${HEADERS_DIR}")
    fi
    if [ -f "${DIST_DIR}/visionos/xros_arm64/libvosk.a" ]; then
        XCF_ARGS+=(-library "${DIST_DIR}/visionos/xros_arm64/libvosk.a" -headers "${HEADERS_DIR}")
    fi
    if [ -f "${DIST_DIR}/visionos/xrsimulator_arm64/libvosk.a" ]; then
        XCF_ARGS+=(-library "${DIST_DIR}/visionos/xrsimulator_arm64/libvosk.a" -headers "${HEADERS_DIR}")
    fi

    if [ ${#XCF_ARGS[@]} -gt 0 ]; then
        xcodebuild -create-xcframework "${XCF_ARGS[@]}" -output "${XCFRAMEWORK_DIR}"
        echo "[OK] Generated Apple multi-platform Super XCFramework: ${XCFRAMEWORK_DIR}"
    fi
}

# ------------------------------------------------------------------------------
# Dispatch Entry
# ------------------------------------------------------------------------------
if [ "$COMMAND" = "help" ] || [ "$COMMAND" = "-h" ] || [ "$COMMAND" = "--help" ]; then
    show_help
    exit 0
fi

prepare_dependencies

case "$COMMAND" in
    macos)
        CHOSEN_ARCH="${SPECIFIED_ARCH:-$(uname -m)}"
        if [ "$CHOSEN_ARCH" = "universal" ] || [ "$CHOSEN_ARCH" = "all" ]; then
            build_macos_all
        else
            build_macos_target_combined "$CHOSEN_ARCH"
        fi
        ;;

    ios)
        build_ios_all
        ;;

    tvos)
        build_tvos_all
        ;;

    visionos)
        CHOSEN_ARCH="${SPECIFIED_ARCH:-all}"
        if [ "$CHOSEN_ARCH" = "universal" ] || [ "$CHOSEN_ARCH" = "all" ]; then
            build_visionos_all
        elif [ "$CHOSEN_ARCH" = "simulator" ] || [ "$CHOSEN_ARCH" = "xrsimulator" ]; then
            build_visionos_static "xrsimulator" "arm64" "${XRSIMULATOR_SDK_PATH}"
        else
            build_visionos_static "xros" "arm64" "${XROS_SDK_PATH}"
        fi
        ;;

    all)
        build_apple_all
        ;;

    *)
        echo "[ERROR] Error: Unknown command '$COMMAND'"
        echo ""
        show_help
        exit 1
        ;;
esac
