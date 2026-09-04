#!/bin/bash
set -e

# ==============================================================================
# build.sh - Vosk API Multi-Platform (64-Bit & 32-Bit) Build & Packaging Engine
#
# Supported options (GNU style):
#   --os <macos|ios|tvos|visionos|apple|windows-msvc|windows-gnu|linux|android|all> (default: all)
#   --arch <x86_64|aarch64|arm64|arm64-v8a|riscv64|armv7l|x86|universal|all> (default: all)
#   --link-type <all|static|shared>           (default: all)
#   --vosk-tag <v0.3.50|v0.3.45|master|...>   (default: v0.3.50)
#   -p, --package                             Package Zip archives & Python Wheels after build
#   --only-package                            Skip build, package existing dist/ artifacts
#   -y, --yes                                 Auto-confirm full build in non-interactive mode
#   -h, --help                                Show this help message
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
    echo "  Vosk API Multi-Platform Build Engine (libvosk build.sh)"
    echo "=============================================================================="
    echo "Usage:"
    echo "  ./build.sh [options]"
    echo ""
    echo "Options:"
    echo "  --os <system>       Target OS (macos|ios|tvos|visionos|apple|windows-msvc|windows-gnu|linux|android|all, default: all)"
    echo "  --arch <arch>       Target architecture (x86_64|aarch64|arm64|arm64-v8a|riscv64|armv7l|x86|universal|all, default: all)"
    echo "  --link-type <type>  Artifact linkage type (all|static|shared, default: all)"
    echo "  --vosk-tag <tag>    Vosk API Git Tag version (default: v0.3.50)"
    echo "  -p, --package       Package artifacts into Zip & Python Wheels in packages/"
    echo "  --only-package      Skip build phase, extract and package existing dist/ to packages/"
    echo "  -y, --yes           Auto-confirm full multi-platform build without interactive prompt"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./build.sh --only-package                       # Package current dist/ artifacts"
    echo "  ./build.sh --os windows-gnu --arch x86_64 -p    # Build Windows MinGW x86_64 & package"
    echo "  ./build.sh --os android --arch arm64-v8a -p      # Build Android arm64-v8a & package"
    echo "  ./build.sh --os macos --arch universal -p        # Build macOS Universal & package"
    echo "  ./build.sh --os visionos -p                     # Build visionOS & package"
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
            echo "[ERROR] Unknown parameter: $1"
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
    echo "  [Packaging Engine] Packaging artifacts from ${DIST_DIR} to ${PKG_DIR} ..."
    echo "=============================================================================="

    # 1. Generic Platform ZIP Assembly (Windows / Linux / Android)
    find "${DIST_DIR}" -mindepth 2 -maxdepth 2 -type d | while read -r dir; do
        rel_path="${dir#"${DIST_DIR}"/}"
        
        # Skip Apple, special folders, and XCFramework directories
        if [[ "$rel_path" == *".xcframework"* ]] || [[ "$rel_path" == *"apple"* ]] || [[ "$rel_path" == *"headers"* ]] || [[ "$rel_path" == *"python"* ]]; then
            continue
        fi

        os_name=$(echo "$rel_path" | cut -d'/' -f1)
        arch_name=$(echo "$rel_path" | cut -d'/' -f2)

        # Apple OS targets are packaged in the Apple dedicated section
        if [ "$os_name" = "macos" ] || [ "$os_name" = "ios" ] || [ "$os_name" = "tvos" ] || [ "$os_name" = "visionos" ]; then
            continue
        fi
        
        if [ -n "$os_name" ] && [ -n "$arch_name" ]; then
            pkg_prefix="libvosk-${VOSK_TAG}-${os_name}-${arch_name}"
            echo "Packaging Zip [${os_name}-${arch_name}] -> ${pkg_prefix} ..."

            # A. Shared Library Package (.so / .dll / .dylib / libvosk.lib + header)
            mkdir -p tmp_shared
            find "$dir" -maxdepth 3 \( -name "*.so" -o -name "*.dll" -o -name "*.dylib" -o -name "libvosk.lib" \) -exec cp -f {} tmp_shared/ \; 2>/dev/null || true
            if [ -n "$(find tmp_shared -type f \( -name "*.so" -o -name "*.dll" -o -name "*.dylib" -o -name "libvosk.lib" \) 2>/dev/null)" ]; then
                find "$dir" -maxdepth 3 -name "vosk_api.h" -exec cp -f {} tmp_shared/ \; 2>/dev/null || true
                if [ ! -f tmp_shared/vosk_api.h ]; then
                    find "${DIST_DIR}" -maxdepth 3 -name "vosk_api.h" -exec cp -f {} tmp_shared/ \; 2>/dev/null || true
                fi
                (cd tmp_shared && zip -r -q "${PKG_DIR}/${pkg_prefix}-shared.zip" .)
            fi
            rm -rf tmp_shared

            # B. Static Library Package (.a / .lib + header)
            mkdir -p tmp_static
            find "$dir" -maxdepth 3 \( -name "*.a" -o -name "*static*.lib" -o -name "vosk.lib" \) -not -name "libvosk.lib" -exec cp -f {} tmp_static/ \; 2>/dev/null || true
            if [ -n "$(find tmp_static -type f \( -name "*.a" -o -name "*static*.lib" -o -name "vosk.lib" \) 2>/dev/null)" ]; then
                find "$dir" -maxdepth 3 -name "vosk_api.h" -exec cp -f {} tmp_static/ \; 2>/dev/null || true
                if [ ! -f tmp_static/vosk_api.h ]; then
                    find "${DIST_DIR}" -maxdepth 3 -name "vosk_api.h" -exec cp -f {} tmp_static/ \; 2>/dev/null || true
                fi
                (cd tmp_static && zip -r -q "${PKG_DIR}/${pkg_prefix}-static.zip" .)
            fi
            rm -rf tmp_static
        fi
    done

    # 2. Apple Ecosystem Native Packaging (macOS / iOS / tvOS / visionOS)
    local mac_header=$(find "${DIST_DIR}" -name "vosk_api.h" 2>/dev/null | head -n 1)
    if [ -z "$mac_header" ] && [ -f "${SCRIPT_DIR}/src/apple/vosk-api/src/vosk_api.h" ]; then
        mac_header="${SCRIPT_DIR}/src/apple/vosk-api/src/vosk_api.h"
    fi

    if [ -d "${DIST_DIR}/macos" ] || [ -d "${DIST_DIR}/ios" ] || [ -d "${DIST_DIR}/tvos" ] || [ -d "${DIST_DIR}/visionos" ]; then
        # macOS Single Arch Packages
        mac_arm64_dylib=""
        mac_x86_dylib=""
        mac_arm64_a=""
        mac_x86_a=""

        for mac_arch in arm64 x86_64; do
            mac_dir="${DIST_DIR}/macos/${mac_arch}"
            if [ -d "$mac_dir" ]; then
                pkg_prefix="libvosk-${VOSK_TAG}-macos-${mac_arch}"
                echo "Packaging macOS Zip [${mac_arch}] -> ${pkg_prefix} ..."

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
        mac_arm64_dylib=$(find "${DIST_DIR}/macos/arm64" -name "*.dylib" 2>/dev/null | head -n 1)
        mac_x86_dylib=$(find "${DIST_DIR}/macos/x86_64" -name "*.dylib" 2>/dev/null | head -n 1)
        mac_arm64_a=$(find "${DIST_DIR}/macos/arm64" -name "*.a" 2>/dev/null | head -n 1)
        mac_x86_a=$(find "${DIST_DIR}/macos/x86_64" -name "*.a" 2>/dev/null | head -n 1)

        if [ -n "$mac_arm64_dylib" ] && [ -n "$mac_x86_dylib" ] && [ -f "$mac_arm64_dylib" ] && [ -f "$mac_x86_dylib" ] && [ "$(uname)" = "Darwin" ]; then
            echo "Packaging macOS Universal Shared Zip -> libvosk-${VOSK_TAG}-macos-universal-shared.zip ..."
            mkdir -p tmp_mac_uni
            lipo -create "$mac_arm64_dylib" "$mac_x86_dylib" -output tmp_mac_uni/libvosk.dylib 2>/dev/null || true
            if [ -f "tmp_mac_uni/libvosk.dylib" ]; then
                mkdir -p "${DIST_DIR}/macos/universal" && cp -f tmp_mac_uni/libvosk.dylib "${DIST_DIR}/macos/universal/"
                mkdir -p tmp_mac_shared && cp tmp_mac_uni/libvosk.dylib tmp_mac_shared/ && if [ -n "$mac_header" ]; then cp "$mac_header" tmp_mac_shared/; fi
                (cd tmp_mac_shared && zip -r -q "${PKG_DIR}/libvosk-${VOSK_TAG}-macos-universal-shared.zip" .)
                rm -rf tmp_mac_shared
            fi
            rm -rf tmp_mac_uni
        fi

        if [ -n "$mac_arm64_a" ] && [ -n "$mac_x86_a" ] && [ -f "$mac_arm64_a" ] && [ -f "$mac_x86_a" ] && [ "$(uname)" = "Darwin" ]; then
            echo "Packaging macOS Universal Static Zip -> libvosk-${VOSK_TAG}-macos-universal-static.zip ..."
            mkdir -p tmp_mac_uni
            lipo -create "$mac_arm64_a" "$mac_x86_a" -output tmp_mac_uni/libvosk.a 2>/dev/null || true
            if [ -f "tmp_mac_uni/libvosk.a" ]; then
                mkdir -p "${DIST_DIR}/macos/universal" && cp -f tmp_mac_uni/libvosk.a "${DIST_DIR}/macos/universal/"
                mkdir -p tmp_mac_static && cp tmp_mac_uni/libvosk.a tmp_mac_static/ && if [ -n "$mac_header" ]; then cp "$mac_header" tmp_mac_static/; fi
                (cd tmp_mac_static && zip -r -q "${PKG_DIR}/libvosk-${VOSK_TAG}-macos-universal-static.zip" .)
                rm -rf tmp_mac_static

                if [ -n "$mac_header" ]; then
                    mkdir -p tmp_headers && cp "$mac_header" tmp_headers/
                    xcodebuild -create-xcframework -library tmp_mac_uni/libvosk.a -headers tmp_headers -output tmp_mac_uni/libvosk.xcframework 2>/dev/null || true
                    if [ -d "tmp_mac_uni/libvosk.xcframework" ]; then
                        echo "Packaging macOS XCFramework Zip -> libvosk-${VOSK_TAG}-macos-xcframework.zip ..."
                        mkdir -p tmp_mac_xcf && cp -R tmp_mac_uni/libvosk.xcframework tmp_mac_xcf/ && cp "$mac_header" tmp_mac_xcf/
                        (cd tmp_mac_xcf && zip -r -q "${PKG_DIR}/libvosk-${VOSK_TAG}-macos-xcframework.zip" .)
                        rm -rf tmp_mac_xcf
                    fi
                    rm -rf tmp_headers
                fi
            fi
            rm -rf tmp_mac_uni
        fi

        # iOS / tvOS / visionOS Static Packages and XCFramework Packages
        for apple_os in ios tvos visionos; do
            apple_dir="${DIST_DIR}/${apple_os}"
            if [ -d "$apple_dir" ]; then
                mkdir -p tmp_apple_static
                find "$apple_dir" -name "*.a" -not -path "*.xcframework/*" -exec cp -f {} tmp_apple_static/ \; 2>/dev/null || true
                if [ -n "$(find tmp_apple_static -type f -name "*.a" 2>/dev/null)" ]; then
                    echo "Packaging Apple [${apple_os}] Static Zip -> libvosk-${VOSK_TAG}-${apple_os}-static.zip ..."
                    if [ -n "$mac_header" ]; then cp "$mac_header" tmp_apple_static/; fi
                    (cd tmp_apple_static && zip -r -q "${PKG_DIR}/libvosk-${VOSK_TAG}-${apple_os}-static.zip" .)
                fi
                rm -rf tmp_apple_static

                xcf_dir=$(find "$apple_dir" -maxdepth 2 -type d -name "*.xcframework" 2>/dev/null | head -n 1)
                if [ -n "$xcf_dir" ]; then
                    echo "Packaging Apple [${apple_os}] XCFramework Zip -> libvosk-${VOSK_TAG}-${apple_os}-xcframework.zip ..."
                    mkdir -p tmp_apple_xcf
                    cp -R "$xcf_dir" tmp_apple_xcf/
                    if [ -n "$mac_header" ]; then cp "$mac_header" tmp_apple_xcf/; fi
                    (cd tmp_apple_xcf && zip -r -q "${PKG_DIR}/libvosk-${VOSK_TAG}-${apple_os}-xcframework.zip" .)
                    rm -rf tmp_apple_xcf
                fi
            fi
        done

        # 3. Apple Multi-Platform Super XCFramework (macOS + iOS + tvOS + visionOS)
        if [ "$(uname)" = "Darwin" ] && [ -n "$mac_header" ]; then
            mkdir -p tmp_apple_super
            mkdir -p tmp_headers && cp "$mac_header" tmp_headers/

            mac_a=$(find "${DIST_DIR}/macos" -name "libvosk.a" 2>/dev/null | grep universal | head -n 1)
            if [ -z "$mac_a" ]; then mac_a=$(find "${DIST_DIR}/macos" -name "libvosk.a" 2>/dev/null | head -n 1); fi
            ios_arm64_a=$(find "${DIST_DIR}/ios" -path "*/iphoneos_arm64/libvosk.a" 2>/dev/null | head -n 1)
            ios_sim_a=$(find "${DIST_DIR}/ios" -path "*/iphonesimulator_universal/libvosk.a" 2>/dev/null | head -n 1)
            tvos_arm64_a=$(find "${DIST_DIR}/tvos" -path "*/appletvos_arm64/libvosk.a" 2>/dev/null | head -n 1)
            tvos_sim_a=$(find "${DIST_DIR}/tvos" -path "*/appletvsimulator_universal/libvosk.a" 2>/dev/null | head -n 1)
            visionos_xros_a=$(find "${DIST_DIR}/visionos" -path "*/xros_arm64/libvosk.a" 2>/dev/null | head -n 1)
            visionos_sim_a=$(find "${DIST_DIR}/visionos" -path "*/xrsimulator_arm64/libvosk.a" 2>/dev/null | head -n 1)

            XCF_CMD=(xcodebuild -create-xcframework)
            apple_targets_count=0
            if [ -n "$mac_a" ]; then XCF_CMD+=(-library "$mac_a" -headers tmp_headers); apple_targets_count=$((apple_targets_count + 1)); fi
            if [ -n "$ios_arm64_a" ]; then XCF_CMD+=(-library "$ios_arm64_a" -headers tmp_headers); apple_targets_count=$((apple_targets_count + 1)); fi
            if [ -n "$ios_sim_a" ]; then XCF_CMD+=(-library "$ios_sim_a" -headers tmp_headers); apple_targets_count=$((apple_targets_count + 1)); fi
            if [ -n "$tvos_arm64_a" ]; then XCF_CMD+=(-library "$tvos_arm64_a" -headers tmp_headers); apple_targets_count=$((apple_targets_count + 1)); fi
            if [ -n "$tvos_sim_a" ]; then XCF_CMD+=(-library "$tvos_sim_a" -headers tmp_headers); apple_targets_count=$((apple_targets_count + 1)); fi
            if [ -n "$visionos_xros_a" ]; then XCF_CMD+=(-library "$visionos_xros_a" -headers tmp_headers); apple_targets_count=$((apple_targets_count + 1)); fi
            if [ -n "$visionos_sim_a" ]; then XCF_CMD+=(-library "$visionos_sim_a" -headers tmp_headers); apple_targets_count=$((apple_targets_count + 1)); fi
            XCF_CMD+=(-output tmp_apple_super/libvosk.xcframework)

            # Assemble Super XCFramework when at least 2 cross-platform slices exist
            if [ "$apple_targets_count" -ge 2 ]; then
                echo "Packaging Apple Multi-Platform Super XCFramework Zip -> libvosk-${VOSK_TAG}-apple-xcframework.zip ..."
                "${XCF_CMD[@]}" 2>/dev/null || true
                rm -rf tmp_headers

                if [ -d "tmp_apple_super/libvosk.xcframework" ]; then
                    cp "$mac_header" tmp_apple_super/ 2>/dev/null || true
                    (cd tmp_apple_super && zip -r -q "${PKG_DIR}/libvosk-${VOSK_TAG}-apple-xcframework.zip" .)
                fi
            else
                rm -rf tmp_headers
            fi
            rm -rf tmp_apple_super

            # 4. Apple Multi-Platform Unified Static Package (macOS + iOS + tvOS + visionOS for non-Xcode builds)
            if [ "$apple_targets_count" -ge 2 ]; then
                mkdir -p tmp_apple_all_static
                found_apple_static=0
                for apple_os in macos ios tvos visionos; do
                    if [ -d "${DIST_DIR}/${apple_os}" ]; then
                        for a_file in $(find "${DIST_DIR}/${apple_os}" -name "*.a" -not -path "*.xcframework/*" 2>/dev/null); do
                            sub_target=$(basename $(dirname "$a_file"))
                            mkdir -p "tmp_apple_all_static/${apple_os}/${sub_target}"
                            cp -f "$a_file" "tmp_apple_all_static/${apple_os}/${sub_target}/"
                            found_apple_static=$((found_apple_static + 1))
                        done
                    fi
                done
                if [ "$found_apple_static" -gt 0 ]; then
                    echo "Packaging Apple Multi-Platform Unified Static Zip -> libvosk-${VOSK_TAG}-apple-static.zip ..."
                    cp "$mac_header" tmp_apple_all_static/
                    (cd tmp_apple_all_static && zip -r -q "${PKG_DIR}/libvosk-${VOSK_TAG}-apple-static.zip" .)
                fi
                rm -rf tmp_apple_all_static
            fi
        fi
    fi

    # 4. Python Wheel Assembly (3 Tiers)
    if command -v python3 >/dev/null 2>&1; then
        echo "Packaging Python Wheels ..."
        python3 -m pip install setuptools wheel cffi >/dev/null 2>&1 || true

        # A. Single-target Wheel
        for dylib_path in $(find "${DIST_DIR}" \( -name "libvosk.dylib" -o -name "libvosk.so" -o -name "libvosk.dll" \) -not -path "*.xcframework/*" 2>/dev/null); do
            target_name=$(basename $(dirname "$dylib_path"))
            os_name=$(basename $(dirname $(dirname "$dylib_path")))
            if [ -n "$target_name" ] && [ -n "$os_name" ] && [ "$os_name" != "." ] && [ "$os_name" != "dist" ] && [ "$target_name" != "universal" ]; then
                plat_tag="${os_name}_${target_name}"
                clean_plat="${plat_tag//-/_}"
                echo "Packaging Python Wheel [${clean_plat}] -> libvosk-${VOSK_TAG//v/}-py3-none-${clean_plat}.whl ..."
                rm -rf tmp_py_build && mkdir -p tmp_py_build/vosk
                cp -R src/python/vosk/* tmp_py_build/vosk/
                cp src/python/setup.py tmp_py_build/
                cp "$dylib_path" tmp_py_build/vosk/
                if [[ "$os_name" == *"windows"* ]]; then
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
            for dylib_path in $(find "${DIST_DIR}" \( -name "libvosk.dylib" -o -name "libvosk.so" -o -name "libvosk.dll" \) -not -path "*.xcframework/*" 2>/dev/null); do
                if [[ "$dylib_path" == *"${os_sys}"* ]]; then
                    arch_sub=$(basename $(dirname "$dylib_path"))
                    mkdir -p "tmp_os_build/vosk/lib/${os_sys}_${arch_sub}"
                    cp -f "$dylib_path" "tmp_os_build/vosk/lib/${os_sys}_${arch_sub}/"
                    if [[ "$os_sys" == *"windows"* ]]; then
                        find "$(dirname "$dylib_path")" -maxdepth 1 -name "*.dll" -exec cp -f {} "tmp_os_build/vosk/lib/${os_sys}_${arch_sub}/" \; 2>/dev/null || true
                    fi
                    found_count=$((found_count + 1))
                fi
            done
            if [ $found_count -ge 2 ]; then
                echo "Packaging OS-Universal Python Wheel [${plat_out}] -> libvosk-${VOSK_TAG//v/}-py3-none-${plat_out}.whl ..."
                (cd tmp_os_build && VOSK_TAG="${VOSK_TAG}" python3 setup.py bdist_wheel --plat-name="${plat_out}" >/dev/null 2>&1) || true
                cp tmp_os_build/dist/*.whl "${PKG_DIR}/" 2>/dev/null || true
            fi
            rm -rf tmp_os_build
        done

        # C. Super Any Universal Wheel
        found_any_count=0
        rm -rf tmp_all_build && mkdir -p tmp_all_build/vosk/lib
        cp -R src/python/vosk/* tmp_all_build/vosk/
        cp src/python/setup.py tmp_all_build/
        for dylib_path in $(find "${DIST_DIR}" \( -name "libvosk.dylib" -o -name "libvosk.so" -o -name "libvosk.dll" \) -not -path "*.xcframework/*" 2>/dev/null); do
            target_sub=$(basename $(dirname "$dylib_path"))
            os_sub=$(basename $(dirname $(dirname "$dylib_path")))
            mkdir -p "tmp_all_build/vosk/lib/${os_sub}_${target_sub}"
            cp -f "$dylib_path" "tmp_all_build/vosk/lib/${os_sub}_${target_sub}/"
            if [[ "$os_sub" == *"windows"* ]]; then
                find "$(dirname "$dylib_path")" -maxdepth 1 -name "*.dll" -exec cp -f {} "tmp_all_build/vosk/lib/${os_sub}_${target_sub}/" \; 2>/dev/null || true
            fi
            found_any_count=$((found_any_count + 1))
        done
        if [ $found_any_count -ge 2 ]; then
            echo "Packaging Super Universal Python Wheel -> libvosk-${VOSK_TAG//v/}-py3-none-any.whl ..."
            (cd tmp_all_build && VOSK_TAG="${VOSK_TAG}" python3 setup.py bdist_wheel --plat-name="any" >/dev/null 2>&1) || true
            cp tmp_all_build/dist/*.whl "${PKG_DIR}/" 2>/dev/null || true
        fi
        rm -rf tmp_all_build
    fi

    # 5. Generate SHA256SUMS.txt
    (cd "${PKG_DIR}" && shasum -a 256 * > SHA256SUMS.txt 2>/dev/null || true)

    # 6. Verify Packages via tools/verify_packages.py
    if command -v python3 >/dev/null 2>&1 && [ -f "${SCRIPT_DIR}/tools/verify_packages.py" ]; then
        python3 "${SCRIPT_DIR}/tools/verify_packages.py" "${PKG_DIR}"
    fi

    echo "=============================================================================="
    echo "[OK] Artifact packaging complete! Output directory: ${PKG_DIR}"
    echo "=============================================================================="
    ls -lh "${PKG_DIR}"
}

if [ "${ONLY_PACKAGE}" = true ]; then
    package_all
    exit 0
fi

# Interactive confirmation prompt when no explicit target is passed
if [ "${HAS_EXPLICIT_FLAGS}" = false ] && [ "${AUTO_YES}" = false ] && [ -t 0 ]; then
    echo "=============================================================================="
    echo "  [WARNING] No platform specified. This will build ALL platforms & architectures."
    echo "  [INFO] Full build produces 11 cross-arch targets and may take 1-2+ hours."
    echo "  [HINT] Use -h / --help to build specific targets (e.g., ./build.sh --os macos)."
    echo "=============================================================================="
    read -p "Continue with full multi-platform build? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Operation cancelled. See ./build.sh --help for specific target usage."
        exit 0
    fi
fi

echo "=============================================================================="
echo "  Vosk API Master Build Engine"
echo "  Target OS   : ${TARGET_OS}"
echo "  Target Arch : ${TARGET_ARCH}"
echo "  Link Type   : ${LINK_TYPE}"
echo "  Vosk Tag    : ${VOSK_TAG}"
echo "=============================================================================="

build_target_docker() {
    local OS=$1
    local ARCH=$2
    local DOCKER_DIR="${SCRIPT_DIR}/src/${OS}/${ARCH}"
    local DOCKERFILE="${DOCKER_DIR}/Dockerfile"
    local OUT_DIR="${SCRIPT_DIR}/dist/${OS}/${ARCH}"

    if [ ! -f "${DOCKERFILE}" ]; then
        echo "[INFO] Skipping: Dockerfile not found (${DOCKERFILE})"
        return 0
    fi

    echo "=============================================================================="
    echo "  [Docker Sandbox] Building ${OS} [${ARCH}] ..."
    echo "=============================================================================="
    mkdir -p "${OUT_DIR}"

    local IMAGE_TAG="libvosk-${OS}-${ARCH}:latest"
    local CONTAINER_NAME="temp-libvosk-${OS}-${ARCH}-$(date +%s)"

    docker build --build-arg VOSK_TAG="${VOSK_TAG}" -t "${IMAGE_TAG}" -f "${DOCKERFILE}" "${SCRIPT_DIR}"

    echo "--> Extracting artifacts [${OS} - ${ARCH}] ..."
    docker create --name "${CONTAINER_NAME}" "${IMAGE_TAG}"
    docker cp "${CONTAINER_NAME}:/opt/dist/${OS}/${ARCH}/." "${OUT_DIR}/" 2>/dev/null || \
    docker cp "${CONTAINER_NAME}:/opt/dist/${ARCH}/${ARCH}/." "${OUT_DIR}/" 2>/dev/null || true

    docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true

    echo "[OK] Built and extracted ${OS} [${ARCH}]: ${OUT_DIR}"
    ls -lh "${OUT_DIR}"
}

build_apple_native() {
    local PLATFORM=$1
    local ARCH=$2
    echo "=============================================================================="
    echo "  [Native Build] Invoking Apple build flow (${PLATFORM} - ${ARCH}) ..."
    echo "=============================================================================="
    local ARCH_ARG="${ARCH}"
    if [ "${ARCH}" = "all" ]; then
        ARCH_ARG="universal"
    fi
    VOSK_TAG="${VOSK_TAG}" bash "${SCRIPT_DIR}/src/apple/build.sh" "${PLATFORM}" "${ARCH_ARG}"

    local ROOT_DIST_DST="${SCRIPT_DIR}/dist"
    rm -rf "${SCRIPT_DIR}/src/apple/dist" "${ROOT_DIST_DST}/apple"

    if [ -d "${ROOT_DIST_DST}/${PLATFORM}/${ARCH_ARG}" ]; then
        echo "[OK] Apple [${PLATFORM} - ${ARCH_ARG}] artifacts exported: ${ROOT_DIST_DST}/${PLATFORM}/${ARCH_ARG}"
        ls -lh "${ROOT_DIST_DST}/${PLATFORM}/${ARCH_ARG}"
    elif [ -d "${ROOT_DIST_DST}/${PLATFORM}" ]; then
        echo "[OK] Apple [${PLATFORM}] artifacts exported: ${ROOT_DIST_DST}/${PLATFORM}"
        ls -lh "${ROOT_DIST_DST}/${PLATFORM}"
    elif [ -d "${ROOT_DIST_DST}" ]; then
        echo "[OK] Apple artifacts exported: ${ROOT_DIST_DST}"
        ls -lh "${ROOT_DIST_DST}"
    fi
}

# 1. Apple Target Handling (macos / ios / tvos / visionos / apple)
if [ "${TARGET_OS}" = "macos" ] || [ "${TARGET_OS}" = "ios" ] || [ "${TARGET_OS}" = "tvos" ] || [ "${TARGET_OS}" = "visionos" ] || [ "${TARGET_OS}" = "apple" ] || [ "${TARGET_OS}" = "all" ]; then
    if [ "$(uname)" = "Darwin" ]; then
        if [ "${TARGET_OS}" = "macos" ]; then
            build_apple_native "macos" "${TARGET_ARCH}"
        elif [ "${TARGET_OS}" = "ios" ]; then
            build_apple_native "ios" "${TARGET_ARCH}"
        elif [ "${TARGET_OS}" = "tvos" ]; then
            build_apple_native "tvos" "${TARGET_ARCH}"
        elif [ "${TARGET_OS}" = "visionos" ]; then
            build_apple_native "visionos" "${TARGET_ARCH}"
        else
            build_apple_native "all" "${TARGET_ARCH}"
        fi
    else
        echo "[INFO] Note: Apple targets (macOS/iOS/tvOS/visionOS) require a macOS host environment. Skipping on non-macOS."
    fi
fi

# 2. Windows-GNU Target Handling (Docker / MinGW-w64 Cross-Compilation)
if [ "${TARGET_OS}" = "windows-gnu" ] || [ "${TARGET_OS}" = "all" ]; then
    if [ "${TARGET_ARCH}" = "x86_64" ] || [ "${TARGET_ARCH}" = "all" ]; then build_target_docker "windows-gnu" "x86_64"; fi
    if [ "${TARGET_ARCH}" = "arm64" ] || [ "${TARGET_ARCH}" = "aarch64" ] || [ "${TARGET_ARCH}" = "all" ]; then build_target_docker "windows-gnu" "arm64"; fi
    if [ "${TARGET_ARCH}" = "x86" ] || [ "${TARGET_ARCH}" = "i686" ] || [ "${TARGET_ARCH}" = "all" ]; then build_target_docker "windows-gnu" "x86"; fi
fi

# 3. Windows-MSVC Target Handling (Native MSVC / PowerShell Build)
if [ "${TARGET_OS}" = "windows-msvc" ] || [ "${TARGET_OS}" = "all" ]; then
    if [ "$(uname)" = "Darwin" ] || [ "$(expr substr $(uname -s) 1 5)" = "Linux" ]; then
        echo "[INFO] Note: Windows-MSVC targets require native MSVC (run .\\src\\windows-msvc\\build.ps1 on Windows)."
    fi
fi

# 4. Linux Target Handling
if [ "${TARGET_OS}" = "linux" ] || [ "${TARGET_OS}" = "all" ]; then
    if [ "${TARGET_ARCH}" = "x86_64" ] || [ "${TARGET_ARCH}" = "all" ]; then build_target_docker "linux" "x86_64"; fi
    if [ "${TARGET_ARCH}" = "aarch64" ] || [ "${TARGET_ARCH}" = "arm64" ] || [ "${TARGET_ARCH}" = "all" ]; then build_target_docker "linux" "aarch64"; fi
    if [ "${TARGET_ARCH}" = "riscv64" ] || [ "${TARGET_ARCH}" = "all" ]; then build_target_docker "linux" "riscv64"; fi
    if [ "${TARGET_ARCH}" = "armv7l" ] || [ "${TARGET_ARCH}" = "all" ]; then build_target_docker "linux" "armv7l"; fi
    if [ "${TARGET_ARCH}" = "x86" ] || [ "${TARGET_ARCH}" = "all" ]; then build_target_docker "linux" "x86"; fi
fi

# 5. Android Target Handling
if [ "${TARGET_OS}" = "android" ] || [ "${TARGET_OS}" = "all" ]; then
    if [ "${TARGET_ARCH}" = "arm64-v8a" ] || [ "${TARGET_ARCH}" = "aarch64" ] || [ "${TARGET_ARCH}" = "all" ]; then build_target_docker "android" "arm64-v8a"; fi
    if [ "${TARGET_ARCH}" = "x86_64" ] || [ "${TARGET_ARCH}" = "all" ]; then build_target_docker "android" "x86_64"; fi
fi

# 6. Package if --package was specified
if [ "${DO_PACKAGE}" = true ]; then
    package_all
fi

echo "=============================================================================="
if [ "${TARGET_OS}" = "all" ] && [ "${TARGET_ARCH}" = "all" ]; then
    echo "[OK] Full multi-platform Vosk API build tasks complete!"
else
    echo "[OK] Vosk API [OS: ${TARGET_OS}, Arch: ${TARGET_ARCH}] build task complete!"
fi
echo "Artifacts directory: ${SCRIPT_DIR}/dist"
echo "=============================================================================="
