#!/bin/bash
set -e

# ==============================================================================
# build.sh - Vosk API macOS, iOS & tvOS (Apple 全生态) 自动编译与 XCFramework 打包引擎

#
# 支持功能:
#   1. macOS (arm64 Apple Silicon & x86_64 Intel) 动态库 (.dylib) + 静态库 (.a) 编译
#   2. lipo 命令合成 macOS Universal 胖二进制
#   3. iOS (iphoneos 真机 arm64 & iphonesimulator 模拟器 arm64/x86_64) 静态库编译
#   4. tvOS (appletvos 真机 arm64 & appletvsimulator 模拟器 arm64/x86_64) 静态库编译
#   5. xcodebuild 构建通用跨平台 libvosk.xcframework
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMAND="${1:-macos}"
SPECIFIED_ARCH="$2"

DEPLOYMENT_TARGET_MACOS="11.0"
DEPLOYMENT_TARGET_IOS="12.0"
DEPLOYMENT_TARGET_TVOS="12.0"
DEPLOYMENT_TARGET_WATCHOS="6.0"
DEPLOYMENT_TARGET_VISIONOS="1.0"
export MACOSX_DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET_MACOS}"

MACOS_SDK_PATH=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)
IPHONEOS_SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)
IPHONESIMULATOR_SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null || true)
APPLETVOS_SDK_PATH=$(xcrun --sdk appletvos --show-sdk-path 2>/dev/null || true)
APPLETVSIMULATOR_SDK_PATH=$(xcrun --sdk appletvsimulator --show-sdk-path 2>/dev/null || true)
WATCHOS_SDK_PATH=$(xcrun --sdk watchos --show-sdk-path 2>/dev/null || true)
WATCHSIMULATOR_SDK_PATH=$(xcrun --sdk watchsimulator --show-sdk-path 2>/dev/null || true)
XROS_SDK_PATH=$(xcrun --sdk xros --show-sdk-path 2>/dev/null || true)
XRSIMULATOR_SDK_PATH=$(xcrun --sdk xrsimulator --show-sdk-path 2>/dev/null || true)

show_help() {
    echo "=============================================================================="
    echo "  Vosk API Apple (macOS / iOS / tvOS) 原生/交叉编译打包引擎"
    echo "=============================================================================="
    echo "用法:"
    echo "  ./build.sh [platform] [arch]"
    echo ""
    echo "支持平台 (platform):"
    echo "  macos      - 编译 macOS 动态库 (.dylib)、静态库 (.a) 及 XCFramework"
    echo "  ios        - 编译 iOS 真机与模拟器静态库，并打包为 libvosk.xcframework"
    echo "  tvos       - 编译 tvOS 真机与模拟器静态库，并打包为 libvosk.xcframework"
    echo "  all        - 编译全平台 (macOS + iOS + tvOS) 并生成超级大一统 XCFramework"
    echo "  help | -h  - 显示本帮助信息"
    echo ""
    echo "支持架构 (arch，仅限 macos 平台):"
    echo "  arm64      - 针对 Apple Silicon (M1/M2/M3/M4) 架构 (macOS 11.0+)"
    echo "  x86_64     - 针对 Intel 64 位 CPU 架构 (macOS 11.0+)"
    echo "  universal  - 编译 x86_64 与 arm64 并合成 Universal 胖二进制"
    echo "  (默认)     - 自动检测当前宿主 CPU 架构 (当前检测为: $(uname -m))"
    echo ""
    echo "常用示例:"
    echo "  ./build.sh macos            # 构建当前宿主架构的 macOS 动态库与静态库"
    echo "  ./build.sh macos arm64      # 构建 ARM64 架构库文件"
    echo "  ./build.sh macos universal  # 构建 macOS Universal 双架构胖二进制"
    echo "  ./build.sh ios              # 构建 iOS 全套静态库与 XCFramework"
    echo "  ./build.sh tvos             # 构建 tvOS 全套静态库与 XCFramework"
    echo "  ./build.sh all              # 一键构建 Apple 全平台"
    echo "=============================================================================="
}

# ------------------------------------------------------------------------------
# 源码依赖准备函数 (Kaldi & Vosk API)
# ------------------------------------------------------------------------------
prepare_dependencies() {
    cd "${SCRIPT_DIR}"

    # 确保 macOS/CI 拥有 OpenFST 编译所需的 autoconf/automake/libtool 工具链
    if ! command -v autoreconf &> /dev/null; then
        echo "--> 检测到缺少 autoreconf，正在使用 Homebrew 自动安装 autoconf automake libtool..."
        brew install autoconf automake libtool 2>/dev/null || true
    fi

    if [ ! -d "kaldi" ]; then
        echo "--> 正在克隆 Vosk 官方适配版 Kaldi 源码库..."
        git clone -b vosk-android --single-branch --depth=1 https://github.com/alphacep/kaldi kaldi
    fi

    # 允许跳过仅训练阶段需要的 Python2.7 / Subversion / Sox / gfortran 校验
    if [ -f "kaldi/tools/Makefile" ]; then
        sed -i '' 's/extras\/check_dependencies.sh/true/g' kaldi/tools/Makefile 2>/dev/null || true
    fi
    if [ -f "kaldi/tools/extras/check_dependencies.sh" ]; then
        sed -i '' 's/exit 1/exit 0/g' kaldi/tools/extras/check_dependencies.sh 2>/dev/null || true
    fi

    if [ ! -d "kaldi/tools/openfst-1.8.0" ]; then
        echo "--> 正在为 Apple 平台编译 OpenFST..."
        cd kaldi/tools
        git clone --depth=1 https://github.com/alphacep/openfst openfst-1.8.0
        make openfst
        cd "${SCRIPT_DIR}"
    fi

    if [ ! -d "vosk-api" ]; then
        echo "--> 正在克隆 Vosk API 源码库..."
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
# 内部 Helper 函数: OpenFST 编译
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

    make -j$(sysctl -n hw.ncpu) openfst \
        OPENFST_CONFIGURE="${HOST_FLAGS} --enable-static --enable-shared --enable-far --enable-ngram-fsts --enable-lookahead-fsts --with-pic" \
        CXXFLAGS="-O3 ${ARCH_FLAGS}" CFLAGS="-O3 ${ARCH_FLAGS}" LDFLAGS="${ARCH_FLAGS}"
}

# ------------------------------------------------------------------------------
# 内部 Helper 函数: Kaldi 编译
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
    make depend -j$(sysctl -n hw.ncpu)
    CXXFLAGS="${ARCH_FLAGS}" CFLAGS="${ARCH_FLAGS}" LDFLAGS="${ARCH_FLAGS}" \
        make -j$(sysctl -n hw.ncpu) online2 lm rnnlm
}

# ------------------------------------------------------------------------------
# 内部 Helper 函数: 静态库 libtool 归档与准备
# ------------------------------------------------------------------------------
archive_static_lib() {
    local OUT_DIR=$1
    local KALDI_ROOT="${SCRIPT_DIR}/kaldi"

    mkdir -p "${OUT_DIR}"

    echo "--> 正在合并归档静态库..."
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

    ranlib -no_warning_for_no_symbols -c "${OUT_DIR}/libvosk.a" 2>/dev/null || ranlib "${OUT_DIR}/libvosk.a" 2>/dev/null || true

    cp -fv "${SCRIPT_DIR}/vosk-api/src/vosk_api.h" "${OUT_DIR}/vosk_api.h" 2>/dev/null || true
    local LIB_SIZE=$(du -sh "${OUT_DIR}/libvosk.a" | cut -f1)
    echo "✔ 静态库打包完成: ${OUT_DIR}/libvosk.a (${LIB_SIZE})"
}

# ------------------------------------------------------------------------------
# 内部 Helper 函数: 准备 头文件 目录
# ------------------------------------------------------------------------------
prepare_headers() {
    local HEADERS_DIR="${SCRIPT_DIR}/dist/headers"
    mkdir -p "${HEADERS_DIR}"
    cp -f "${SCRIPT_DIR}/vosk-api/src/vosk_api.h" "${HEADERS_DIR}/"
    echo "${HEADERS_DIR}"
}

# ------------------------------------------------------------------------------
# 1. 编译 macOS 单架构动态共享库 (.dylib)
# ------------------------------------------------------------------------------
build_macos_shared() {
    local TARGET_ARCH=$1
    local ARCH_FLAGS="-arch ${TARGET_ARCH} -mmacosx-version-min=${DEPLOYMENT_TARGET_MACOS} -isysroot ${MACOS_SDK_PATH}"
    local HOST_FLAGS="--host=${TARGET_ARCH}-apple-darwin"
    local KALDI_ROOT="${SCRIPT_DIR}/kaldi"

    echo "--> 正在编译 macOS 动态库 (.dylib) [${TARGET_ARCH}] (minOS: ${DEPLOYMENT_TARGET_MACOS})..."

    compile_openfst "${ARCH_FLAGS}" "${HOST_FLAGS}"
    compile_kaldi "${ARCH_FLAGS}" 1

    # Vosk API 动态库打包
    cd "${SCRIPT_DIR}/vosk-api/src"
    make clean || true
    KALDI_ROOT="${KALDI_ROOT}" EXT=dylib make -j$(sysctl -n hw.ncpu) \
        OPENFST_ROOT="${KALDI_ROOT}/tools/openfst-1.8.0" \
        HAVE_ACCELERATE=1 \
        HAVE_OPENBLAS_CLAPACK=0 \
        HAVE_MKL=0 \
        USE_SHARED=0 \
        EXTRA_CFLAGS="${ARCH_FLAGS}" \
        EXTRA_LDFLAGS="${ARCH_FLAGS} -Wl,-install_name,@rpath/libvosk.dylib"

    local OUT_DIR="${SCRIPT_DIR}/dist/macos/${TARGET_ARCH}"
    mkdir -p "${OUT_DIR}"
    cp -fv libvosk.dylib "${OUT_DIR}/libvosk.dylib"
    cp -fv "${SCRIPT_DIR}/vosk-api/src/vosk_api.h" "${OUT_DIR}/vosk_api.h" 2>/dev/null || true
    echo "✔ macOS 动态库编译完成 [${TARGET_ARCH}]: ${OUT_DIR}/libvosk.dylib"
}

# ------------------------------------------------------------------------------
# 2. 编译 macOS 单架构静态归档库 (.a)
# ------------------------------------------------------------------------------
build_macos_static() {
    local TARGET_ARCH=$1
    local ARCH_FLAGS="-arch ${TARGET_ARCH} -mmacosx-version-min=${DEPLOYMENT_TARGET_MACOS} -isysroot ${MACOS_SDK_PATH}"
    local HOST_FLAGS="--host=${TARGET_ARCH}-apple-darwin"
    local KALDI_ROOT="${SCRIPT_DIR}/kaldi"

    echo "--> 正在编译 macOS 静态库 (.a) [${TARGET_ARCH}] (minOS: ${DEPLOYMENT_TARGET_MACOS})..."

    compile_openfst "${ARCH_FLAGS}" "${HOST_FLAGS}"
    compile_kaldi "${ARCH_FLAGS}" 0

    # Vosk API 静态目标文件编译与归档打包
    cd "${SCRIPT_DIR}/vosk-api/src"
    make clean || true
    make -j$(sysctl -n hw.ncpu) \
        KALDI_ROOT="${KALDI_ROOT}" \
        OPENFST_ROOT="${KALDI_ROOT}/tools/openfst-1.8.0" \
        HAVE_ACCELERATE=1 \
        HAVE_OPENBLAS_CLAPACK=0 \
        HAVE_MKL=0 \
        USE_SHARED=0 \
        EXTRA_CFLAGS="${ARCH_FLAGS}" \
        EXTRA_LDFLAGS="${ARCH_FLAGS}"

    local OUT_DIR="${SCRIPT_DIR}/dist/macos/${TARGET_ARCH}"
    archive_static_lib "${OUT_DIR}"

    echo "✔ macOS 静态库打包完成 [${TARGET_ARCH}]: ${OUT_DIR}/libvosk.a"
}

# ------------------------------------------------------------------------------
# 3. 编译 iOS 单架构静态库
# ------------------------------------------------------------------------------
build_ios_static() {
    local SDK=$1
    local TARGET_ARCH=$2
    local SDK_PATH=$3
    local KALDI_ROOT="${SCRIPT_DIR}/kaldi"

    echo "--> 正在编译 iOS 静态库 [${SDK} / ${TARGET_ARCH}]..."

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

    # Vosk API iOS 打包
    cd "${SCRIPT_DIR}/vosk-api/src"
    make clean || true
    make -j$(sysctl -n hw.ncpu) \
        KALDI_ROOT="${KALDI_ROOT}" \
        OPENFST_ROOT="${KALDI_ROOT}/tools/openfst-1.8.0" \
        HAVE_ACCELERATE=1 \
        HAVE_OPENBLAS_CLAPACK=0 \
        HAVE_MKL=0 \
        USE_SHARED=0 \
        EXTRA_CFLAGS="${ARCH_FLAGS}" \
        EXTRA_LDFLAGS="${ARCH_FLAGS}"

    local OUT_DIR="${SCRIPT_DIR}/dist/ios/${PLATFORM_NAME}_${TARGET_ARCH}"
    archive_static_lib "${OUT_DIR}"

    echo "✔ iOS 静态库打包完成 [${PLATFORM_NAME}_${TARGET_ARCH}]: ${OUT_DIR}/libvosk.a"
}

# ------------------------------------------------------------------------------
# 4. 编译 tvOS 单架构静态库
# ------------------------------------------------------------------------------
build_tvos_static() {
    local SDK=$1
    local TARGET_ARCH=$2
    local SDK_PATH=$3
    local KALDI_ROOT="${SCRIPT_DIR}/kaldi"

    echo "--> 正在编译 tvOS 静态库 [${SDK} / ${TARGET_ARCH}]..."

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

    # Vosk API tvOS 打包
    cd "${SCRIPT_DIR}/vosk-api/src"
    make clean || true
    make -j$(sysctl -n hw.ncpu) \
        KALDI_ROOT="${KALDI_ROOT}" \
        OPENFST_ROOT="${KALDI_ROOT}/tools/openfst-1.8.0" \
        HAVE_ACCELERATE=1 \
        HAVE_OPENBLAS_CLAPACK=0 \
        HAVE_MKL=0 \
        USE_SHARED=0 \
        EXTRA_CFLAGS="${ARCH_FLAGS}" \
        EXTRA_LDFLAGS="${ARCH_FLAGS}"

    local OUT_DIR="${SCRIPT_DIR}/dist/tvos/${PLATFORM_NAME}_${TARGET_ARCH}"
    archive_static_lib "${OUT_DIR}"

    echo "✔ tvOS 静态库打包完成 [${PLATFORM_NAME}_${TARGET_ARCH}]: ${OUT_DIR}/libvosk.a"
}

# ------------------------------------------------------------------------------
# 5. 单架构组合构建 helper (依次构建动态库与静态库)
# ------------------------------------------------------------------------------
build_macos_target_combined() {
    local TARGET_ARCH=$1
    echo "========================================================="
    echo "▶ 开始为 macOS [ ${TARGET_ARCH} ] 构建动态库与静态库..."
    echo "========================================================="

    build_macos_shared "${TARGET_ARCH}"
    build_macos_static "${TARGET_ARCH}"

    echo "✔ macOS [ ${TARGET_ARCH} ] 构建完成 -> ${SCRIPT_DIR}/dist/macos/${TARGET_ARCH}/"
}

# ------------------------------------------------------------------------------
# 6. 高阶全量模块打包器 (macOS / iOS / tvOS / All)
# ------------------------------------------------------------------------------
build_macos_all() {
    echo "--> 正在构建 macOS 双架构 Universal (arm64 + x86_64) 全量库及 XCFramework..."
    build_macos_target_combined "x86_64"
    build_macos_target_combined "arm64"

    mkdir -p "${SCRIPT_DIR}/dist/macos/universal"

    lipo -create \
        "${SCRIPT_DIR}/dist/macos/x86_64/libvosk.dylib" \
        "${SCRIPT_DIR}/dist/macos/arm64/libvosk.dylib" \
        -output "${SCRIPT_DIR}/dist/macos/universal/libvosk.dylib"

    lipo -create \
        "${SCRIPT_DIR}/dist/macos/x86_64/libvosk.a" \
        "${SCRIPT_DIR}/dist/macos/arm64/libvosk.a" \
        -output "${SCRIPT_DIR}/dist/macos/universal/libvosk.a"

    cp -fv "${SCRIPT_DIR}/vosk-api/src/vosk_api.h" "${SCRIPT_DIR}/dist/macos/universal/vosk_api.h" 2>/dev/null || true

    local HEADERS_DIR=$(prepare_headers)

    local MACOS_XCFRAMEWORK_DIR="${SCRIPT_DIR}/dist/macos/libvosk.xcframework"
    rm -rf "${MACOS_XCFRAMEWORK_DIR}"
    xcodebuild -create-xcframework \
        -library "${SCRIPT_DIR}/dist/macos/universal/libvosk.a" \
        -headers "${HEADERS_DIR}" \
        -output "${MACOS_XCFRAMEWORK_DIR}"

    echo "✔ 成功合成 macOS Universal 动态库: dist/macos/universal/libvosk.dylib"
    echo "✔ 成功合成 macOS Universal 静态库: dist/macos/universal/libvosk.a"
    echo "✔ 成功生成 macOS libvosk.xcframework: ${MACOS_XCFRAMEWORK_DIR}"
}

build_ios_all() {
    echo "--> 正在构建 iOS 全量平台静态库与 XCFramework..."
    mkdir -p "${SCRIPT_DIR}/dist/ios/iphonesimulator_universal"

    if [ -n "${IPHONEOS_SDK_PATH}" ]; then
        build_ios_static "iphoneos" "arm64" "${IPHONEOS_SDK_PATH}"
    fi
    if [ -n "${IPHONESIMULATOR_SDK_PATH}" ]; then
        build_ios_static "iphonesimulator" "arm64" "${IPHONESIMULATOR_SDK_PATH}"
        build_ios_static "iphonesimulator" "x86_64" "${IPHONESIMULATOR_SDK_PATH}"

        lipo -create \
            "${SCRIPT_DIR}/dist/ios/iphonesimulator_arm64/libvosk.a" \
            "${SCRIPT_DIR}/dist/ios/iphonesimulator_x86_64/libvosk.a" \
            -output "${SCRIPT_DIR}/dist/ios/iphonesimulator_universal/libvosk.a"
    fi

    local HEADERS_DIR=$(prepare_headers)

    local XCFRAMEWORK_DIR="${SCRIPT_DIR}/dist/ios/libvosk.xcframework"
    rm -rf "${XCFRAMEWORK_DIR}"
    
    local XCF_ARGS=()
    if [ -f "${SCRIPT_DIR}/dist/ios/iphoneos_arm64/libvosk.a" ]; then
        XCF_ARGS+=(-library "${SCRIPT_DIR}/dist/ios/iphoneos_arm64/libvosk.a" -headers "${HEADERS_DIR}")
    fi
    if [ -f "${SCRIPT_DIR}/dist/ios/iphonesimulator_universal/libvosk.a" ]; then
        XCF_ARGS+=(-library "${SCRIPT_DIR}/dist/ios/iphonesimulator_universal/libvosk.a" -headers "${HEADERS_DIR}")
    fi

    if [ ${#XCF_ARGS[@]} -gt 0 ]; then
        xcodebuild -create-xcframework "${XCF_ARGS[@]}" -output "${XCFRAMEWORK_DIR}"
        echo "✔ 成功生成 iOS libvosk.xcframework: ${XCFRAMEWORK_DIR}"
    fi
}

build_tvos_all() {
    echo "--> 正在构建 tvOS 全量平台静态库与 XCFramework..."
    mkdir -p "${SCRIPT_DIR}/dist/tvos/appletvsimulator_universal"

    if [ -n "${APPLETVOS_SDK_PATH}" ]; then
        build_tvos_static "appletvos" "arm64" "${APPLETVOS_SDK_PATH}"
    fi
    if [ -n "${APPLETVSIMULATOR_SDK_PATH}" ]; then
        build_tvos_static "appletvsimulator" "arm64" "${APPLETVSIMULATOR_SDK_PATH}"
        build_tvos_static "appletvsimulator" "x86_64" "${APPLETVSIMULATOR_SDK_PATH}"

        lipo -create \
            "${SCRIPT_DIR}/dist/tvos/appletvsimulator_arm64/libvosk.a" \
            "${SCRIPT_DIR}/dist/tvos/appletvsimulator_x86_64/libvosk.a" \
            -output "${SCRIPT_DIR}/dist/tvos/appletvsimulator_universal/libvosk.a"
    fi

    local HEADERS_DIR=$(prepare_headers)

    local XCFRAMEWORK_DIR="${SCRIPT_DIR}/dist/tvos/libvosk.xcframework"
    rm -rf "${XCFRAMEWORK_DIR}"
    
    local XCF_ARGS=()
    if [ -f "${SCRIPT_DIR}/dist/tvos/appletvos_arm64/libvosk.a" ]; then
        XCF_ARGS+=(-library "${SCRIPT_DIR}/dist/tvos/appletvos_arm64/libvosk.a" -headers "${HEADERS_DIR}")
    fi
    if [ -f "${SCRIPT_DIR}/dist/tvos/appletvsimulator_universal/libvosk.a" ]; then
        XCF_ARGS+=(-library "${SCRIPT_DIR}/dist/tvos/appletvsimulator_universal/libvosk.a" -headers "${HEADERS_DIR}")
    fi

    if [ ${#XCF_ARGS[@]} -gt 0 ]; then
        xcodebuild -create-xcframework "${XCF_ARGS[@]}" -output "${XCFRAMEWORK_DIR}"
        echo "✔ 成功生成 tvOS libvosk.xcframework: ${XCFRAMEWORK_DIR}"
    fi
}

build_watchos_static() {
    local SDK=$1
    local TARGET_ARCH=$2
    local SDK_PATH=$3
    local KALDI_ROOT="${SCRIPT_DIR}/kaldi"

    echo "--> 正在编译 watchOS 静态库 [${SDK} / ${TARGET_ARCH}]..."

    local SDK_FLAG=""
    local PLATFORM_NAME=""
    if [ "$SDK" = "watchos" ]; then
        SDK_FLAG="-mwatchos-version-min=${DEPLOYMENT_TARGET_WATCHOS}"
        PLATFORM_NAME="watchos"
    else
        SDK_FLAG="-mwatchos-simulator-version-min=${DEPLOYMENT_TARGET_WATCHOS}"
        PLATFORM_NAME="watchsimulator"
    fi

    local ARCH_FLAGS="-arch ${TARGET_ARCH} -isysroot ${SDK_PATH} ${SDK_FLAG}"
    local HOST_FLAGS="--host=${TARGET_ARCH}-apple-darwin"

    compile_openfst "${ARCH_FLAGS}" "${HOST_FLAGS}"
    compile_kaldi "${ARCH_FLAGS}" 0

    cd "${SCRIPT_DIR}/vosk-api/src"
    make clean || true
    make -j$(sysctl -n hw.ncpu) \
        KALDI_ROOT="${KALDI_ROOT}" \
        OPENFST_ROOT="${KALDI_ROOT}/tools/openfst-1.8.0" \
        HAVE_ACCELERATE=1 \
        HAVE_OPENBLAS_CLAPACK=0 \
        HAVE_MKL=0 \
        USE_SHARED=0 \
        EXTRA_CFLAGS="${ARCH_FLAGS}" \
        EXTRA_LDFLAGS="${ARCH_FLAGS}"

    local OUT_DIR="${SCRIPT_DIR}/dist/watchos/${PLATFORM_NAME}_${TARGET_ARCH}"
    archive_static_lib "${OUT_DIR}"

    echo "✔ watchOS 静态库打包完成 [${PLATFORM_NAME}_${TARGET_ARCH}]: ${OUT_DIR}/libvosk.a"
}

build_watchos_all() {
    echo "--> 正在构建 watchOS 全量平台静态库与 XCFramework..."
    mkdir -p "${SCRIPT_DIR}/dist/watchos/watchsimulator_universal"

    if [ -n "${WATCHOS_SDK_PATH}" ]; then
        build_watchos_static "watchos" "arm64_32" "${WATCHOS_SDK_PATH}" || true
        build_watchos_static "watchos" "arm64" "${WATCHOS_SDK_PATH}" || true
    fi
    if [ -n "${WATCHSIMULATOR_SDK_PATH}" ]; then
        build_watchos_static "watchsimulator" "arm64" "${WATCHSIMULATOR_SDK_PATH}" || true
        build_watchos_static "watchsimulator" "x86_64" "${WATCHSIMULATOR_SDK_PATH}" || true

        if [ -f "${SCRIPT_DIR}/dist/watchos/watchsimulator_arm64/libvosk.a" ] && [ -f "${SCRIPT_DIR}/dist/watchos/watchsimulator_x86_64/libvosk.a" ]; then
            lipo -create \
                "${SCRIPT_DIR}/dist/watchos/watchsimulator_arm64/libvosk.a" \
                "${SCRIPT_DIR}/dist/watchos/watchsimulator_x86_64/libvosk.a" \
                -output "${SCRIPT_DIR}/dist/watchos/watchsimulator_universal/libvosk.a"
        fi
    fi

    local HEADERS_DIR=$(prepare_headers)
    local XCFRAMEWORK_DIR="${SCRIPT_DIR}/dist/watchos/libvosk.xcframework"
    rm -rf "${XCFRAMEWORK_DIR}"
    
    local XCF_ARGS=()
    if [ -f "${SCRIPT_DIR}/dist/watchos/watchos_arm64_32/libvosk.a" ]; then
        XCF_ARGS+=(-library "${SCRIPT_DIR}/dist/watchos/watchos_arm64_32/libvosk.a" -headers "${HEADERS_DIR}")
    elif [ -f "${SCRIPT_DIR}/dist/watchos/watchos_arm64/libvosk.a" ]; then
        XCF_ARGS+=(-library "${SCRIPT_DIR}/dist/watchos/watchos_arm64/libvosk.a" -headers "${HEADERS_DIR}")
    fi
    if [ -f "${SCRIPT_DIR}/dist/watchos/watchsimulator_universal/libvosk.a" ]; then
        XCF_ARGS+=(-library "${SCRIPT_DIR}/dist/watchos/watchsimulator_universal/libvosk.a" -headers "${HEADERS_DIR}")
    elif [ -f "${SCRIPT_DIR}/dist/watchos/watchsimulator_arm64/libvosk.a" ]; then
        XCF_ARGS+=(-library "${SCRIPT_DIR}/dist/watchos/watchsimulator_arm64/libvosk.a" -headers "${HEADERS_DIR}")
    fi

    if [ ${#XCF_ARGS[@]} -gt 0 ]; then
        xcodebuild -create-xcframework "${XCF_ARGS[@]}" -output "${XCFRAMEWORK_DIR}"
        echo "✔ 成功生成 watchOS libvosk.xcframework: ${XCFRAMEWORK_DIR}"
    fi
}

build_visionos_static() {
    local SDK=$1
    local TARGET_ARCH=$2
    local SDK_PATH=$3
    local KALDI_ROOT="${SCRIPT_DIR}/kaldi"

    echo "--> 正在编译 visionOS 静态库 [${SDK} / ${TARGET_ARCH}]..."

    local SDK_FLAG=""
    local PLATFORM_NAME=""
    if [ "$SDK" = "xros" ]; then
        SDK_FLAG="-target arm64-apple-xros${DEPLOYMENT_TARGET_VISIONOS}"
        PLATFORM_NAME="xros"
    else
        SDK_FLAG="-target arm64-apple-xros${DEPLOYMENT_TARGET_VISIONOS}-simulator"
        PLATFORM_NAME="xrsimulator"
    fi

    local ARCH_FLAGS="-arch ${TARGET_ARCH} -isysroot ${SDK_PATH} ${SDK_FLAG}"
    local HOST_FLAGS="--host=${TARGET_ARCH}-apple-darwin"

    compile_openfst "${ARCH_FLAGS}" "${HOST_FLAGS}"
    compile_kaldi "${ARCH_FLAGS}" 0

    cd "${SCRIPT_DIR}/vosk-api/src"
    make clean || true
    make -j$(sysctl -n hw.ncpu) \
        KALDI_ROOT="${KALDI_ROOT}" \
        OPENFST_ROOT="${KALDI_ROOT}/tools/openfst-1.8.0" \
        HAVE_ACCELERATE=1 \
        HAVE_OPENBLAS_CLAPACK=0 \
        HAVE_MKL=0 \
        USE_SHARED=0 \
        EXTRA_CFLAGS="${ARCH_FLAGS}" \
        EXTRA_LDFLAGS="${ARCH_FLAGS}"

    local OUT_DIR="${SCRIPT_DIR}/dist/visionos/${PLATFORM_NAME}_${TARGET_ARCH}"
    archive_static_lib "${OUT_DIR}"

    echo "✔ visionOS 静态库打包完成 [${PLATFORM_NAME}_${TARGET_ARCH}]: ${OUT_DIR}/libvosk.a"
}

build_visionos_all() {
    echo "--> 正在构建 visionOS 全量平台静态库与 XCFramework..."
    if [ -n "${XROS_SDK_PATH}" ]; then
        build_visionos_static "xros" "arm64" "${XROS_SDK_PATH}" || true
    fi
    if [ -n "${XRSIMULATOR_SDK_PATH}" ]; then
        build_visionos_static "xrsimulator" "arm64" "${XRSIMULATOR_SDK_PATH}" || true
    fi

    local HEADERS_DIR=$(prepare_headers)
    local XCFRAMEWORK_DIR="${SCRIPT_DIR}/dist/visionos/libvosk.xcframework"
    rm -rf "${XCFRAMEWORK_DIR}"
    
    local XCF_ARGS=()
    if [ -f "${SCRIPT_DIR}/dist/visionos/xros_arm64/libvosk.a" ]; then
        XCF_ARGS+=(-library "${SCRIPT_DIR}/dist/visionos/xros_arm64/libvosk.a" -headers "${HEADERS_DIR}")
    fi
    if [ -f "${SCRIPT_DIR}/dist/visionos/xrsimulator_arm64/libvosk.a" ]; then
        XCF_ARGS+=(-library "${SCRIPT_DIR}/dist/visionos/xrsimulator_arm64/libvosk.a" -headers "${HEADERS_DIR}")
    fi

    if [ ${#XCF_ARGS[@]} -gt 0 ]; then
        xcodebuild -create-xcframework "${XCF_ARGS[@]}" -output "${XCFRAMEWORK_DIR}"
        echo "✔ 成功生成 visionOS libvosk.xcframework: ${XCFRAMEWORK_DIR}"
    fi
}

build_apple_all() {
    echo "--> 正在执行 Apple 全平台 (macOS + iOS + tvOS + watchOS + visionOS) 大一统编译流程..."
    build_macos_all
    build_ios_all
    build_tvos_all
    build_watchos_all
    build_visionos_all

    local HEADERS_DIR=$(prepare_headers)

    local XCFRAMEWORK_DIR="${SCRIPT_DIR}/dist/apple/libvosk.xcframework"
    rm -rf "${XCFRAMEWORK_DIR}"
    
    local XCF_ARGS=()
    if [ -f "${SCRIPT_DIR}/dist/macos/universal/libvosk.a" ]; then
        XCF_ARGS+=(-library "${SCRIPT_DIR}/dist/macos/universal/libvosk.a" -headers "${HEADERS_DIR}")
    fi
    if [ -f "${SCRIPT_DIR}/dist/ios/iphoneos_arm64/libvosk.a" ]; then
        XCF_ARGS+=(-library "${SCRIPT_DIR}/dist/ios/iphoneos_arm64/libvosk.a" -headers "${HEADERS_DIR}")
    fi
    if [ -f "${SCRIPT_DIR}/dist/ios/iphonesimulator_universal/libvosk.a" ]; then
        XCF_ARGS+=(-library "${SCRIPT_DIR}/dist/ios/iphonesimulator_universal/libvosk.a" -headers "${HEADERS_DIR}")
    fi
    if [ -f "${SCRIPT_DIR}/dist/tvos/appletvos_arm64/libvosk.a" ]; then
        XCF_ARGS+=(-library "${SCRIPT_DIR}/dist/tvos/appletvos_arm64/libvosk.a" -headers "${HEADERS_DIR}")
    fi
    if [ -f "${SCRIPT_DIR}/dist/tvos/appletvsimulator_universal/libvosk.a" ]; then
        XCF_ARGS+=(-library "${SCRIPT_DIR}/dist/tvos/appletvsimulator_universal/libvosk.a" -headers "${HEADERS_DIR}")
    fi
    if [ -f "${SCRIPT_DIR}/dist/watchos/watchos_arm64_32/libvosk.a" ]; then
        XCF_ARGS+=(-library "${SCRIPT_DIR}/dist/watchos/watchos_arm64_32/libvosk.a" -headers "${HEADERS_DIR}")
    elif [ -f "${SCRIPT_DIR}/dist/watchos/watchos_arm64/libvosk.a" ]; then
        XCF_ARGS+=(-library "${SCRIPT_DIR}/dist/watchos/watchos_arm64/libvosk.a" -headers "${HEADERS_DIR}")
    fi
    if [ -f "${SCRIPT_DIR}/dist/watchos/watchsimulator_universal/libvosk.a" ]; then
        XCF_ARGS+=(-library "${SCRIPT_DIR}/dist/watchos/watchsimulator_universal/libvosk.a" -headers "${HEADERS_DIR}")
    fi
    if [ -f "${SCRIPT_DIR}/dist/visionos/xros_arm64/libvosk.a" ]; then
        XCF_ARGS+=(-library "${SCRIPT_DIR}/dist/visionos/xros_arm64/libvosk.a" -headers "${HEADERS_DIR}")
    fi
    if [ -f "${SCRIPT_DIR}/dist/visionos/xrsimulator_arm64/libvosk.a" ]; then
        XCF_ARGS+=(-library "${SCRIPT_DIR}/dist/visionos/xrsimulator_arm64/libvosk.a" -headers "${HEADERS_DIR}")
    fi

    if [ ${#XCF_ARGS[@]} -gt 0 ]; then
        xcodebuild -create-xcframework "${XCF_ARGS[@]}" -output "${XCFRAMEWORK_DIR}"
        echo "✔ 成功生成 Apple 全平台 Super XCFramework: ${XCFRAMEWORK_DIR}"
    fi
}

# ------------------------------------------------------------------------------
# 调度入口
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

    watchos)
        build_watchos_all
        ;;

    visionos)
        build_visionos_all
        ;;

    all)
        build_apple_all
        ;;

    *)
        echo "❌ 错误: 未知的指令 '$COMMAND'"
        echo ""
        show_help
        exit 1
        ;;
esac
