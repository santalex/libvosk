#!/bin/bash
set -e

# ==============================================================================
# build.sh - Vosk API 全平台 (64位 & 32位) 交叉架构工业级 Docker & Native 编译主控引擎
#
# 支持参数 (GNU 命名风格):
#   --os <macos|ios|tvos|watchos|visionos|apple|windows-msvc|windows-gnu|windows|linux|android|all> (默认: all)
#   --arch <x86_64|aarch64|arm64|arm64-v8a|riscv64|armv7l|x86|universal|all> (默认: all)
#   --link-type <all|static|shared>           (默认: all)
#   --vosk-tag <v0.3.50|v0.3.45|master|...>   (默认: v0.3.50)
#   -p, --package                             编译完成后自动重组打包 Zip 与 Python Wheels
#   --only-package                            跳过编译，直接对现有的 dist/ 目录进行全量打包
#   -y, --yes                                 非交互模式自动确认全量编译
#   -h, --help                                显示帮助指南
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

TARGET_OS="all"
TARGET_ARCH="all"
LINK_TYPE="all"
VOSK_TAG="v0.3.50"
DO_PACKAGE=false
ONLY_PACKAGE=false
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
    echo "  --os <系统>         指定目标系统 (macos|ios|tvos|watchos|visionos|apple|windows-msvc|windows-gnu|windows|linux|android|all, 默认: all)"
    echo "  --arch <架构>       指定目标架构 (x86_64|aarch64|arm64|arm64-v8a|riscv64|armv7l|x86|universal|all, 默认: all)"
    echo "  --link-type <形式>  指定打包产物形式 (all|static|shared, 默认: all)"
    echo "  --vosk-tag <版本>   指定 Vosk API Git Tag 版本 (默认: v0.3.50)"
    echo "  -p, --package       编译完成后自动打包产物 (生成 Zip 压缩包与 Python Wheels 到 packages/)"
    echo "  --only-package      跳过编译阶段，直接提取现有的 dist/ 目录打包输出至 packages/"
    echo "  -y, --yes           自动跳过全量打包二次确认"
    echo "  -h, --help          显示帮助说明"
    echo ""
    echo "使用示例:"
    echo "  ./build.sh --only-package                       # 直接提取当前 dist/ 打包输出至 packages/"
    echo "  ./build.sh --os windows-gnu --arch x86_64 -p    # 编译 Windows GNU (MinGW) 并自动打包"
    echo "  ./build.sh --os android --arch arm64-v8a -p      # 编译 Android 并自动打包"
    echo "  ./build.sh --os macos --arch universal -p        # 编译 macOS Universal 并打包"
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
        -p|--package)
            DO_PACKAGE=true
            shift
            ;;
        --only-package)
            ONLY_PACKAGE=true
            DO_PACKAGE=true
            shift
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

package_all() {
    local PKG_DIR="${SCRIPT_DIR}/packages"
    local DIST_DIR="${SCRIPT_DIR}/dist"
    mkdir -p "${PKG_DIR}"

    echo "=============================================================================="
    echo "  [打包引擎] 正在从 ${DIST_DIR} 提取产物打包至 ${PKG_DIR} ..."
    echo "=============================================================================="

    # 1. 通用平台 ZIP 组装 (Windows / Linux / Android)
    find "${DIST_DIR}" -mindepth 2 -maxdepth 2 -type d | while read -r dir; do
        rel_path="${dir#"${DIST_DIR}"/}"
        
        # 避免处理 apple, python 等特殊目录
        if [[ "$rel_path" == *"apple"* ]] || [[ "$rel_path" == *"python"* ]]; then continue; fi

        os_name=$(echo "$rel_path" | cut -d'/' -f1)
        arch_name=$(echo "$rel_path" | cut -d'/' -f2)
        
        if [ -n "$os_name" ] && [ -n "$arch_name" ]; then
            if [ "$os_name" = "windows" ]; then
                pkg_prefix="libvosk-${VOSK_TAG}-windows-msvc-${arch_name}"
            else
                pkg_prefix="libvosk-${VOSK_TAG}-${os_name}-${arch_name}"
            fi
            echo "Packaging Zip [${os_name}-${arch_name}] -> ${pkg_prefix} ..."

            # A. Shared 动态库包 (.so / .dll / .dylib / libvosk.lib + header)
            mkdir -p tmp_shared
            find "$dir" -maxdepth 3 \( -name "*.so" -o -name "*.dll" -o -name "*.dylib" -o -name "libvosk.lib" \) -exec cp -f {} tmp_shared/ \; 2>/dev/null || true
            if [ -n "$(find tmp_shared -type f \( -name "*.so" -o -name "*.dll" -o -name "*.dylib" -o -name "libvosk.lib" \) 2>/dev/null)" ]; then
                find "$dir" -maxdepth 3 -name "vosk_api.h" -exec cp -f {} tmp_shared/ \; 2>/dev/null || true
                find "${DIST_DIR}" -name "vosk_api.h" -exec cp -f {} tmp_shared/ \; 2>/dev/null || true
                (cd tmp_shared && zip -r -q "${PKG_DIR}/${pkg_prefix}-shared.zip" .)
            fi
            rm -rf tmp_shared

            # B. Static 纯静态库包 (.a / libvosk_static.lib + header)
            mkdir -p tmp_static
            find "$dir" -maxdepth 3 \( -name "*.a" -o -name "libvosk_static.lib" \) -exec cp -f {} tmp_static/ \; 2>/dev/null || true
            rm -f tmp_static/*.dll.a
            if [ -n "$(find tmp_static -type f \( -name "*.a" -o -name "libvosk_static.lib" \) 2>/dev/null)" ]; then
                find "$dir" -maxdepth 3 -name "vosk_api.h" -exec cp -f {} tmp_static/ \; 2>/dev/null || true
                find "${DIST_DIR}" -name "vosk_api.h" -exec cp -f {} tmp_static/ \; 2>/dev/null || true
                (cd tmp_static && zip -r -q "${PKG_DIR}/${pkg_prefix}-static.zip" .)
            fi
            rm -rf tmp_static
        fi
    done

    # 2. Apple 平台 (macOS / iOS / tvOS / macOS XCFramework)
    if [ -d "${DIST_DIR}/apple" ] || [ -d "${DIST_DIR}/macos" ]; then
        echo "Packaging Apple (macOS / iOS / tvOS / XCFramework) Zip packages..."
        mac_arm64_dylib=$(find "${DIST_DIR}" -path "*/macos/arm64/*" -name "*.dylib" 2>/dev/null | head -n 1)
        mac_x86_dylib=$(find "${DIST_DIR}" -path "*/macos/x86_64/*" -name "*.dylib" 2>/dev/null | head -n 1)
        mac_arm64_a=$(find "${DIST_DIR}" -path "*/macos/arm64/*" -name "*.a" 2>/dev/null | head -n 1)
        mac_x86_a=$(find "${DIST_DIR}" -path "*/macos/x86_64/*" -name "*.a" 2>/dev/null | head -n 1)
        mac_header=$(find "${DIST_DIR}" -name "vosk_api.h" 2>/dev/null | head -n 1)

        # 单架构 macOS
        for mac_arch in arm64 x86_64; do
            mac_dir=$(find "${DIST_DIR}" -type d -path "*/macos/${mac_arch}" 2>/dev/null | head -n 1)
            if [ -n "$mac_dir" ]; then
                pkg_prefix="libvosk-${VOSK_TAG}-macos-${mac_arch}"
                mkdir -p tmp_mac_shared
                find "$mac_dir" -name "*.dylib" -exec cp -f {} tmp_mac_shared/ \; 2>/dev/null || true
                if [ -n "$(find tmp_mac_shared -type f -name "*.dylib" 2>/dev/null)" ]; then
                    if [ -n "$mac_header" ]; then cp "$mac_header" tmp_mac_shared/; fi
                    (cd tmp_mac_shared && zip -r -q "${PKG_DIR}/${pkg_prefix}-shared.zip" .)
                fi
                rm -rf tmp_mac_shared

                mkdir -p tmp_mac_static
                find "$mac_dir" -name "*.a" -exec cp -f {} tmp_mac_static/ \; 2>/dev/null || true
                if [ -n "$(find tmp_mac_static -type f -name "*.a" 2>/dev/null)" ]; then
                    if [ -n "$mac_header" ]; then cp "$mac_header" tmp_mac_static/; fi
                    (cd tmp_mac_static && zip -r -q "${PKG_DIR}/${pkg_prefix}-static.zip" .)
                fi
                rm -rf tmp_mac_static
            fi
        done

        # Universal macOS & macOS XCFramework
        if [ -n "$mac_arm64_dylib" ] && [ -n "$mac_x86_dylib" ] && [ "$(uname)" = "Darwin" ]; then
            mkdir -p tmp_mac_uni
            lipo -create "$mac_arm64_dylib" "$mac_x86_dylib" -output tmp_mac_uni/libvosk.dylib 2>/dev/null || true
            lipo -create "$mac_arm64_a" "$mac_x86_a" -output tmp_mac_uni/libvosk.a 2>/dev/null || true
            if [ -n "$mac_header" ]; then cp "$mac_header" tmp_mac_uni/; fi

            mkdir -p tmp_mac_shared && cp tmp_mac_uni/libvosk.dylib tmp_mac_shared/ && if [ -n "$mac_header" ]; then cp "$mac_header" tmp_mac_shared/; fi
            (cd tmp_mac_shared && zip -r -q "${PKG_DIR}/libvosk-${VOSK_TAG}-macos-universal-shared.zip" .)
            rm -rf tmp_mac_shared

            mkdir -p tmp_mac_static && cp tmp_mac_uni/libvosk.a tmp_mac_static/ && if [ -n "$mac_header" ]; then cp "$mac_header" tmp_mac_static/; fi
            (cd tmp_mac_static && zip -r -q "${PKG_DIR}/libvosk-${VOSK_TAG}-macos-universal-static.zip" .)
            rm -rf tmp_mac_static

            if [ -n "$mac_header" ]; then
                mkdir -p tmp_headers && cp "$mac_header" tmp_headers/
                xcodebuild -create-xcframework -library tmp_mac_uni/libvosk.a -headers tmp_headers -output tmp_mac_uni/libvosk.xcframework 2>/dev/null || true
                if [ -d "tmp_mac_uni/libvosk.xcframework" ]; then
                    mkdir -p tmp_mac_xcf && cp -R tmp_mac_uni/libvosk.xcframework tmp_mac_xcf/ && cp "$mac_header" tmp_mac_xcf/
                    (cd tmp_mac_xcf && zip -r -q "${PKG_DIR}/libvosk-${VOSK_TAG}-macos-xcframework.zip" .)
                    rm -rf tmp_mac_xcf
                fi
                rm -rf tmp_headers
            fi
            rm -rf tmp_mac_uni
        fi

        # iOS / tvOS 平台静态包与 XCFramework 包
        for apple_os in ios tvos; do
            apple_dir=$(find "${DIST_DIR}" -type d -name "$apple_os" 2>/dev/null | head -n 1)
            if [ -n "$apple_dir" ]; then
                mkdir -p tmp_apple_static
                find "$apple_dir" -name "*.a" -exec cp -f {} tmp_apple_static/ \; 2>/dev/null || true
                if [ -n "$(find tmp_apple_static -type f -name "*.a" 2>/dev/null)" ]; then
                    if [ -n "$mac_header" ]; then cp "$mac_header" tmp_apple_static/; fi
                    (cd tmp_apple_static && zip -r -q "${PKG_DIR}/libvosk-${VOSK_TAG}-${apple_os}-static.zip" .)
                fi
                rm -rf tmp_apple_static

                xcf_dir=$(find "$apple_dir" -type d -name "*.xcframework" 2>/dev/null | head -n 1)
                if [ -n "$xcf_dir" ]; then
                    mkdir -p tmp_apple_xcf
                    cp -R "$xcf_dir" tmp_apple_xcf/
                    if [ -n "$mac_header" ]; then cp "$mac_header" tmp_apple_xcf/; fi
                    (cd tmp_apple_xcf && zip -r -q "${PKG_DIR}/libvosk-${VOSK_TAG}-${apple_os}-xcframework.zip" .)
                    rm -rf tmp_apple_xcf
                fi
            fi
        done

        # 3. Apple 全平台 (macOS + iOS + tvOS) Super XCFramework 大一统包
        if [ "$(uname)" = "Darwin" ] && [ -n "$mac_header" ]; then
            mkdir -p tmp_apple_super
            mkdir -p tmp_headers && cp "$mac_header" tmp_headers/

            mac_a=$(find "${DIST_DIR}" -path "*/macos/universal/libvosk.a" -o -path "*/macos/arm64/libvosk.a" 2>/dev/null | head -n 1)
            ios_arm64_a=$(find "${DIST_DIR}" -path "*/iphoneos_arm64/libvosk.a" 2>/dev/null | head -n 1)
            ios_sim_a=$(find "${DIST_DIR}" -path "*/iphonesimulator_universal/libvosk.a" 2>/dev/null | head -n 1)
            tvos_arm64_a=$(find "${DIST_DIR}" -path "*/appletvos_arm64/libvosk.a" 2>/dev/null | head -n 1)
            tvos_sim_a=$(find "${DIST_DIR}" -path "*/appletvsimulator_universal/libvosk.a" 2>/dev/null | head -n 1)

            XCF_CMD=(xcodebuild -create-xcframework)
            if [ -n "$mac_a" ]; then XCF_CMD+=(-library "$mac_a" -headers tmp_headers); fi
            if [ -n "$ios_arm64_a" ]; then XCF_CMD+=(-library "$ios_arm64_a" -headers tmp_headers); fi
            if [ -n "$ios_sim_a" ]; then XCF_CMD+=(-library "$ios_sim_a" -headers tmp_headers); fi
            if [ -n "$tvos_arm64_a" ]; then XCF_CMD+=(-library "$tvos_arm64_a" -headers tmp_headers); fi
            if [ -n "$tvos_sim_a" ]; then XCF_CMD+=(-library "$tvos_sim_a" -headers tmp_headers); fi
            XCF_CMD+=(-output tmp_apple_super/libvosk.xcframework)

            "${XCF_CMD[@]}" 2>/dev/null || true
            rm -rf tmp_headers

            if [ -d "tmp_apple_super/libvosk.xcframework" ]; then
                cp "$mac_header" tmp_apple_super/ 2>/dev/null || true
                (cd tmp_apple_super && zip -r -q "${PKG_DIR}/libvosk-${VOSK_TAG}-apple-xcframework.zip" .)
            fi
            rm -rf tmp_apple_super
        fi
    fi

    # 4. Python Wheel 组装 (3 级梯度包)
    if command -v python3 >/dev/null 2>&1; then
        echo "Packaging Python Wheels ..."
        python3 -m pip install setuptools wheel cffi >/dev/null 2>&1 || true

        # A. 单目标 Wheel
        for dylib_path in $(find "${DIST_DIR}" -name "libvosk.dylib" -o -name "libvosk.so" -o -name "libvosk.dll" 2>/dev/null); do
            target_name=$(basename $(dirname "$dylib_path"))
            os_name=$(basename $(dirname $(dirname "$dylib_path")))
            if [ -n "$target_name" ] && [ -n "$os_name" ] && [ "$os_name" != "." ] && [ "$os_name" != "dist" ] && [ "$target_name" != "universal" ]; then
                if [ "$os_name" = "windows" ]; then
                    plat_tag="windows_msvc_${target_name}"
                else
                    plat_tag="${os_name}_${target_name}"
                fi
                clean_plat="${plat_tag//-/_}"
                echo "Packaging Python Wheel [${clean_plat}] -> libvosk-${VOSK_TAG//v/}-py3-none-${clean_plat}.whl ..."
                rm -rf tmp_py_build && mkdir -p tmp_py_build/vosk
                cp -R src/python/vosk/* tmp_py_build/vosk/
                cp src/python/setup.py tmp_py_build/
                cp "$dylib_path" tmp_py_build/vosk/
                if [ "$os_name" = "windows" ]; then
                    find "$(dirname "$dylib_path")" -maxdepth 1 -name "*.dll" -exec cp -f {} tmp_py_build/vosk/ \; 2>/dev/null || true
                fi
                (cd tmp_py_build && VOSK_TAG="${VOSK_TAG}" python3 setup.py bdist_wheel --plat-name="${clean_plat}" >/dev/null 2>&1) || true
                cp tmp_py_build/dist/*.whl "${PKG_DIR}/" 2>/dev/null || true
                rm -rf tmp_py_build
            fi
        done

        # B. OS Universal Wheel
        for os_sys in macos windows linux android; do
            plat_out="${os_sys}_universal"
            if [ "$os_sys" = "macos" ]; then plat_out="macosx_universal"; fi
            if [ "$os_sys" = "windows" ]; then plat_out="windows_msvc_universal"; fi
            
            rm -rf tmp_os_build && mkdir -p tmp_os_build/vosk/lib
            cp -R src/python/vosk/* tmp_os_build/vosk/
            cp src/python/setup.py tmp_os_build/
            found_count=0
            for dylib_path in $(find "${DIST_DIR}" -name "libvosk.dylib" -o -name "libvosk.so" -o -name "libvosk.dll" 2>/dev/null); do
                if [[ "$dylib_path" == *"${os_sys}"* ]]; then
                    arch_sub=$(basename $(dirname "$dylib_path"))
                    mkdir -p "tmp_os_build/vosk/lib/${os_sys}_${arch_sub}"
                    cp -f "$dylib_path" "tmp_os_build/vosk/lib/${os_sys}_${arch_sub}/"
                    if [ "$os_sys" = "windows" ]; then
                        find "$(dirname "$dylib_path")" -maxdepth 1 -name "*.dll" -exec cp -f {} "tmp_os_build/vosk/lib/${os_sys}_${arch_sub}/" \; 2>/dev/null || true
                    fi
                    found_count=$((found_count + 1))
                fi
            done
            if [ $found_count -gt 0 ]; then
                echo "Packaging OS-Universal Python Wheel [${plat_out}] -> libvosk-${VOSK_TAG//v/}-py3-none-${plat_out}.whl ..."
                (cd tmp_os_build && VOSK_TAG="${VOSK_TAG}" python3 setup.py bdist_wheel --plat-name="${plat_out}" >/dev/null 2>&1) || true
                cp tmp_os_build/dist/*.whl "${PKG_DIR}/" 2>/dev/null || true
            fi
            rm -rf tmp_os_build
        done

        # C. Super Any Universal Wheel (仅在找到至少一个动态库时生成)
        _dylib_count=$(find "${DIST_DIR}" -name "libvosk.dylib" -o -name "libvosk.so" -o -name "libvosk.dll" 2>/dev/null | wc -l | tr -d ' ')
        if [ "${_dylib_count}" -gt 0 ]; then
            echo "Packaging Super Universal Python Wheel -> libvosk-${VOSK_TAG//v/}-py3-none-any.whl (${_dylib_count} dynamic libs) ..."
            rm -rf tmp_all_build && mkdir -p tmp_all_build/vosk/lib
            cp -R src/python/vosk/* tmp_all_build/vosk/
            cp src/python/setup.py tmp_all_build/
            for dylib_path in $(find "${DIST_DIR}" -name "libvosk.dylib" -o -name "libvosk.so" -o -name "libvosk.dll" 2>/dev/null); do
                target_sub=$(basename $(dirname "$dylib_path"))
                os_sub=$(basename $(dirname $(dirname "$dylib_path")))
                mkdir -p "tmp_all_build/vosk/lib/${os_sub}_${target_sub}"
                cp -f "$dylib_path" "tmp_all_build/vosk/lib/${os_sub}_${target_sub}/"
                if [ "$os_sub" = "windows" ]; then
                    find "$(dirname "$dylib_path")" -maxdepth 1 -name "*.dll" -exec cp -f {} "tmp_all_build/vosk/lib/${os_sub}_${target_sub}/" \; 2>/dev/null || true
                fi
            done
            (cd tmp_all_build && VOSK_TAG="${VOSK_TAG}" python3 setup.py bdist_wheel --plat-name="any" >/dev/null 2>&1) || true
            cp tmp_all_build/dist/*.whl "${PKG_DIR}/" 2>/dev/null || true
            rm -rf tmp_all_build
        else
            echo "Skipping Super Universal Python Wheel (no dynamic libraries found in dist/)"
        fi
    fi

    # 5. 生成 SHA256SUMS.txt
    (cd "${PKG_DIR}" && shasum -a 256 * > SHA256SUMS.txt 2>/dev/null || true)

    # 6. 调用 tools/verify_packages.py 全量审计校验
    if command -v python3 >/dev/null 2>&1 && [ -f "${SCRIPT_DIR}/tools/verify_packages.py" ]; then
        python3 "${SCRIPT_DIR}/tools/verify_packages.py" "${PKG_DIR}"
    fi

    echo "=============================================================================="
    echo "✔ 🎉 产物打包全量完成！输出目录: ${PKG_DIR}"
    echo "=============================================================================="
    ls -lh "${PKG_DIR}"
}

# 如果仅仅是单独打包模式 (--only-package)，执行完毕直接退出
if [ "${ONLY_PACKAGE}" = true ]; then
    package_all
    exit 0
fi

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

    docker build --build-arg VOSK_TAG="${VOSK_TAG}" -t "${IMAGE_TAG}" -f "${DOCKERFILE}" "${SCRIPT_DIR}"

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

    echo "--> 正在抽取同步 Apple 目标二进制产物到根目录 dist/ 及 dist/apple/ ..."
    local APPLE_DIST_SRC="${SCRIPT_DIR}/src/apple/dist"
    local ROOT_DIST_DST="${SCRIPT_DIR}/dist"

    if [ -d "${APPLE_DIST_SRC}" ]; then
        mkdir -p "${ROOT_DIST_DST}" "${ROOT_DIST_DST}/apple"
        cp -Rf "${APPLE_DIST_SRC}/"* "${ROOT_DIST_DST}/" 2>/dev/null || true
        cp -Rf "${APPLE_DIST_SRC}/"* "${ROOT_DIST_DST}/apple/" 2>/dev/null || true
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

# 1. Apple 目标处理 (macos / ios / tvos / watchos / visionos / apple)
if [ "${TARGET_OS}" = "macos" ] || [ "${TARGET_OS}" = "ios" ] || [ "${TARGET_OS}" = "tvos" ] || [ "${TARGET_OS}" = "watchos" ] || [ "${TARGET_OS}" = "visionos" ] || [ "${TARGET_OS}" = "apple" ] || [ "${TARGET_OS}" = "all" ]; then
    if [ "$(uname)" = "Darwin" ]; then
        if [ "${TARGET_OS}" = "macos" ]; then
            build_apple_native "macos" "${TARGET_ARCH}"
        elif [ "${TARGET_OS}" = "ios" ]; then
            build_apple_native "ios" "${TARGET_ARCH}"
        elif [ "${TARGET_OS}" = "tvos" ]; then
            build_apple_native "tvos" "${TARGET_ARCH}"
        elif [ "${TARGET_OS}" = "watchos" ]; then
            build_apple_native "watchos" "${TARGET_ARCH}"
        elif [ "${TARGET_OS}" = "visionos" ]; then
            build_apple_native "visionos" "${TARGET_ARCH}"
        else
            build_apple_native "all" "${TARGET_ARCH}"
        fi
    else
        echo "⚠️ 注意: 编译 Apple (macOS/iOS/tvOS/watchOS/visionOS) 必须在 macOS 宿主机环境运行，非 macOS 自动跳过。"
    fi
fi

# 2. Windows-GNU 目标处理 (Docker / MinGW-w64 跨平台交叉编译)
if [ "${TARGET_OS}" = "windows-gnu" ] || [ "${TARGET_OS}" = "all" ]; then
    if [ "${TARGET_ARCH}" = "x86_64" ] || [ "${TARGET_ARCH}" = "all" ]; then build_target_docker "windows-gnu" "x86_64"; fi
    if [ "${TARGET_ARCH}" = "arm64" ] || [ "${TARGET_ARCH}" = "aarch64" ] || [ "${TARGET_ARCH}" = "all" ]; then build_target_docker "windows-gnu" "arm64"; fi
    if [ "${TARGET_ARCH}" = "x86" ] || [ "${TARGET_ARCH}" = "i686" ] || [ "${TARGET_ARCH}" = "all" ]; then build_target_docker "windows-gnu" "x86"; fi
fi

# 3. Windows-MSVC 目标处理 (原生 MSVC / PowerShell 构建)
if [ "${TARGET_OS}" = "windows-msvc" ] || [ "${TARGET_OS}" = "windows" ] || [ "${TARGET_OS}" = "all" ]; then
    if [ "$(uname)" = "Darwin" ] || [ "$(expr substr $(uname -s) 1 5)" = "Linux" ]; then
        echo "💡 提示: Windows-MSVC 目标使用原生 MSVC 纯净编译架构 (在 Windows 宿主上运行 .\\src\\windows-msvc\\build.ps1)。"
    fi
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

# 5. 如果开启了 --package 标志，触发打包
if [ "${DO_PACKAGE}" = true ]; then
    package_all
fi

echo "=============================================================================="
if [ "${TARGET_OS}" = "all" ] && [ "${TARGET_ARCH}" = "all" ]; then
    echo "✔ 🎉 全平台全架构 Vosk API 编译构建任务全部完成！"
else
    echo "✔ 🎉 Vosk API [系统: ${TARGET_OS}, 架构: ${TARGET_ARCH}] 编译构建任务完成！"
fi
echo "产物目录: ${SCRIPT_DIR}/dist"
echo "=============================================================================="
