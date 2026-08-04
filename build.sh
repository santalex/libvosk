#!/bin/bash
set -e

# ==============================================================================
# build.sh - Vosk API 全平台 (64位 & 32位) 交叉架构工业级 Docker & Native 编译主控引擎

#
# 支持参数 (GNU 命名风格):
#   --os <macos|ios|apple|windows|linux|android|all> (默认: all)
#   --arch <x86_64|aarch64|arm64|arm64-v8a|riscv64|armv7l|x86|universal|all> (默认: all)
#   --link-type <all|static|shared>           (默认: all)
#   --vosk-tag <v0.3.50|v0.3.45|master|...>   (默认: v0.3.50)
#   -y, --yes                                 非交互模式自动确认全量编译
#   -h, --help                                显示帮助指南
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

TARGET_OS="all"
TARGET_ARCH="all"
LINK_TYPE="all"
VOSK_TAG="v0.3.50"
AUTO_YES=false
HAS_EXPLICIT_FLAGS=false

show_help() {
    echo "=============================================================================="
    echo "  Vosk API 全平台 64位/全架构 构建引擎 (libvosk build.sh)"
    echo "=============================================================================="
    echo "用法:"
    echo "  ./build.sh [选项]"
    echo ""
    echo "选项说明:"
    echo "  --os <系统>         指定目标系统 (macos|ios|apple|windows|linux|android|all, 默认: all)"
    echo "  --arch <架构>       指定目标架构 (x86_64|aarch64|arm64|arm64-v8a|riscv64|armv7l|x86|universal|all, 默认: all)"
    echo "  --link-type <形式>  指定打包产物形式 (all|static|shared, 默认: all)"
    echo "  --vosk-tag <版本>   指定 Vosk API Git Tag 版本 (默认: v0.3.50)"
    echo "  -y, --yes           自动跳过全量打包二次确认"
    echo "  -h, --help          显示帮助说明"
    echo ""
    echo "使用示例:"
    echo "  ./build.sh --os macos --arch universal          # 编译 macOS Universal 胖二进制"
    echo "  ./build.sh --os ios --arch universal            # 编译 iOS XCFramework 跨架构静态库"
    echo "  ./build.sh --os windows --arch x86_64           # 编译 Windows 64位 Intel/AMD"
    echo "  ./build.sh --os linux --arch riscv64            # 编译 Linux RISC-V 64位"
    echo "  ./build.sh --os android --arch arm64-v8a        # 编译 Android 64位 ARM"
    echo "  ./build.sh --os all --yes                       # 全量出厂编译 (跳过交互提示)"
    echo "=============================================================================="
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --os|-o)
            TARGET_OS="$2"
            HAS_EXPLICIT_FLAGS=true
            shift 2
            ;;
        --arch|-a)
            TARGET_ARCH="$2"
            HAS_EXPLICIT_FLAGS=true
            shift 2
            ;;
        --link-type|-l)
            LINK_TYPE="$2"
            HAS_EXPLICIT_FLAGS=true
            shift 2
            ;;
        --vosk-tag|-v)
            VOSK_TAG="$2"
            HAS_EXPLICIT_FLAGS=true
            shift 2
            ;;
        -y|--yes)
            AUTO_YES=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "❌ 未知参数: $1"
            show_help
            exit 1
            ;;
    esac
done

# 如果用户未传递任何显式架构/系统标志，且处于交互式终端 (TTY)，弹出防手滑二次确认
if [ "${HAS_EXPLICIT_FLAGS}" = false ] && [ "${AUTO_YES}" = false ] && [ -t 0 ]; then
    echo "=============================================================================="
    echo "  ⚠️ 警告: 您未指定任何平台选项，默认即将启动【全平台全架构】全量编译！"
    echo "  ⏱️ 注意: 全量编译包含 11 个跨架构产物，在单机完整构建预计需要 1 ~ 2+ 小时！"
    echo "  👉 提示: 您随时可以输入 -h / --help 查看帮助，仅编译特定系统或架构。"
    echo "           (示例: ./build.sh --os windows --arch x86_64)"
    echo "=============================================================================="
    read -p "确认要继续启动全量全平台编译吗？[y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "💡 操作已取消。请输入 ./build.sh --help 查看特定系统/架构的编译用法。"
        exit 0
    fi
fi

echo "=============================================================================="
echo "  Vosk API 主打包引擎启动"
echo "  目标系统 (OS)   : ${TARGET_OS}"
echo "  目标架构 (ARCH) : ${TARGET_ARCH}"
echo "  链接形式 (LINK) : ${LINK_TYPE}"
echo "  Vosk Tag 版本   : ${VOSK_TAG}"
echo "=============================================================================="

build_target_docker() {
    local OS=$1
    local ARCH=$2
    local DOCKER_DIR="${SCRIPT_DIR}/src/${OS}/${ARCH}"
    local DOCKERFILE="${DOCKER_DIR}/Dockerfile"
    local OUT_DIR="${SCRIPT_DIR}/dist/${OS}/${ARCH}"

    if [ ! -f "${DOCKERFILE}" ]; then
        echo "⚠️ 跳过: 未找到对应 Dockerfile (${DOCKERFILE})"
        return 0
    fi

    echo "=============================================================================="
    echo "  [Docker 沙盒] 正在编译 ${OS} [${ARCH}] ..."
    echo "=============================================================================="
    mkdir -p "${OUT_DIR}"

    local IMAGE_TAG="reavox-vosk-${OS}-${ARCH}:latest"
    local CONTAINER_NAME="temp-reavox-${OS}-${ARCH}-$(date +%s)"

    docker build --build-arg VOSK_TAG="${VOSK_TAG}" -t "${IMAGE_TAG}" -f "${DOCKERFILE}" "${DOCKER_DIR}"

    echo "--> 正在抽取产物 [${OS} - ${ARCH}] ..."
    docker create --name "${CONTAINER_NAME}" "${IMAGE_TAG}"
    docker cp "${CONTAINER_NAME}:/opt/dist/${OS}/${ARCH}/." "${OUT_DIR}/" 2>/dev/null || \
    docker cp "${CONTAINER_NAME}:/opt/dist/windows/aarch64/." "${OUT_DIR}/" 2>/dev/null || \
    docker cp "${CONTAINER_NAME}:/opt/dist/${ARCH}/${ARCH}/." "${OUT_DIR}/" 2>/dev/null || true

    docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true

    echo "✔ 🎉 ${OS} [${ARCH}] 构建并解包导出成功: ${OUT_DIR}"
    ls -lh "${OUT_DIR}"
}

build_apple_native() {
    local PLATFORM=$1
    local ARCH=$2
    echo "=============================================================================="
    echo "  [Native 编译] 正在调用 Apple 构建流 (${PLATFORM} - ${ARCH}) ..."
    echo "=============================================================================="
    local ARCH_ARG="${ARCH}"
    if [ "${ARCH}" = "all" ]; then
        ARCH_ARG="universal"
    fi
    VOSK_TAG="${VOSK_TAG}" bash "${SCRIPT_DIR}/src/apple/build.sh" "${PLATFORM}" "${ARCH_ARG}"

    echo "--> 正在抽取同步 Apple 目标二进制产物到根目录 dist/apple/ ..."
    local APPLE_DIST_SRC="${SCRIPT_DIR}/src/apple/dist"
    local ROOT_DIST_DST="${SCRIPT_DIR}/dist/apple"

    if [ -d "${APPLE_DIST_SRC}" ]; then
        mkdir -p "${ROOT_DIST_DST}"
        cp -Rf "${APPLE_DIST_SRC}/"* "${ROOT_DIST_DST}/" 2>/dev/null || true
        rm -rf "${APPLE_DIST_SRC}"
    fi

    if [ -d "${ROOT_DIST_DST}/${PLATFORM}/${ARCH_ARG}" ]; then
        echo "✔ 🎉 Apple [${PLATFORM} - ${ARCH_ARG}] 产物导出成功: ${ROOT_DIST_DST}/${PLATFORM}/${ARCH_ARG}"
        ls -lh "${ROOT_DIST_DST}/${PLATFORM}/${ARCH_ARG}"
    elif [ -d "${ROOT_DIST_DST}/${PLATFORM}" ]; then
        echo "✔ 🎉 Apple [${PLATFORM}] 产物导出成功: ${ROOT_DIST_DST}/${PLATFORM}"
        ls -lh "${ROOT_DIST_DST}/${PLATFORM}"
    elif [ -d "${ROOT_DIST_DST}" ]; then
        echo "✔ 🎉 Apple 产物导出成功: ${ROOT_DIST_DST}"
        ls -lh "${ROOT_DIST_DST}"
    fi
}

# 1. Apple 目标处理 (macos / ios / tvos / apple)
if [ "${TARGET_OS}" = "macos" ] || [ "${TARGET_OS}" = "ios" ] || [ "${TARGET_OS}" = "tvos" ] || [ "${TARGET_OS}" = "apple" ] || [ "${TARGET_OS}" = "all" ]; then
    if [ "$(uname)" = "Darwin" ]; then
        if [ "${TARGET_OS}" = "macos" ]; then
            build_apple_native "macos" "${TARGET_ARCH}"
        elif [ "${TARGET_OS}" = "ios" ]; then
            build_apple_native "ios" "${TARGET_ARCH}"
        elif [ "${TARGET_OS}" = "tvos" ]; then
            build_apple_native "tvos" "${TARGET_ARCH}"
        else
            build_apple_native "all" "${TARGET_ARCH}"
        fi
    else
        echo "⚠️ 注意: 编译 Apple (macOS/iOS/tvOS) 必须在 macOS 宿主机环境运行，非 macOS 自动跳过。"
    fi
fi

# 2. Windows 目标处理
if [ "${TARGET_OS}" = "windows" ] || [ "${TARGET_OS}" = "all" ]; then
    if [ "${TARGET_ARCH}" = "x86_64" ] || [ "${TARGET_ARCH}" = "all" ]; then build_target_docker "windows" "x86_64"; fi
    if [ "${TARGET_ARCH}" = "arm64" ] || [ "${TARGET_ARCH}" = "aarch64" ] || [ "${TARGET_ARCH}" = "all" ]; then build_target_docker "windows" "arm64"; fi
    if [ "${TARGET_ARCH}" = "x86" ] || [ "${TARGET_ARCH}" = "i686" ] || [ "${TARGET_ARCH}" = "all" ]; then build_target_docker "windows" "x86"; fi
fi

# 3. Linux 目标处理
if [ "${TARGET_OS}" = "linux" ] || [ "${TARGET_OS}" = "all" ]; then
    if [ "${TARGET_ARCH}" = "x86_64" ] || [ "${TARGET_ARCH}" = "all" ]; then build_target_docker "linux" "x86_64"; fi
    if [ "${TARGET_ARCH}" = "aarch64" ] || [ "${TARGET_ARCH}" = "arm64" ] || [ "${TARGET_ARCH}" = "all" ]; then build_target_docker "linux" "aarch64"; fi
    if [ "${TARGET_ARCH}" = "riscv64" ] || [ "${TARGET_ARCH}" = "all" ]; then build_target_docker "linux" "riscv64"; fi
    if [ "${TARGET_ARCH}" = "armv7l" ] || [ "${TARGET_ARCH}" = "all" ]; then build_target_docker "linux" "armv7l"; fi
    if [ "${TARGET_ARCH}" = "x86" ] || [ "${TARGET_ARCH}" = "all" ]; then build_target_docker "linux" "x86"; fi
fi

# 4. Android 目标处理
if [ "${TARGET_OS}" = "android" ] || [ "${TARGET_OS}" = "all" ]; then
    if [ "${TARGET_ARCH}" = "arm64-v8a" ] || [ "${TARGET_ARCH}" = "aarch64" ] || [ "${TARGET_ARCH}" = "all" ]; then build_target_docker "android" "arm64-v8a"; fi
    if [ "${TARGET_ARCH}" = "x86_64" ] || [ "${TARGET_ARCH}" = "all" ]; then build_target_docker "android" "x86_64"; fi
fi

echo "=============================================================================="
if [ "${TARGET_OS}" = "all" ] && [ "${TARGET_ARCH}" = "all" ]; then
    echo "✔ 🎉 全平台全架构 Vosk API 编译构建任务全部完成！"
else
    echo "✔ 🎉 Vosk API [系统: ${TARGET_OS}, 架构: ${TARGET_ARCH}] 编译构建任务完成！"
fi
echo "产物目录: ${SCRIPT_DIR}/dist"
echo "=============================================================================="
