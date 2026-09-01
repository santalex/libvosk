#!/usr/bin/env bash
# ==============================================================================
# LibVosk 跨平台 E2E 自动化测试调度脚本
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

LIB_DIR="${1:-}"
MODEL_DIR="${SCRIPT_DIR}/model"
WAV_FILE="${SCRIPT_DIR}/test.wav"

if [ -z "${LIB_DIR}" ]; then
    echo "用法: $0 <产物目录路径，如 dist/macos/arm64 或 dist/windows-gnu/x86_64>"
    exit 1
fi

LIB_DIR="$(cd "${LIB_DIR}" && pwd)"

echo "=============================================================================="
echo "  LibVosk E2E 自动化测试调度器"
echo "  测试目标目录: ${LIB_DIR}"
echo "=============================================================================="

# 1. 自动准备官方测试音频
if [ ! -f "${WAV_FILE}" ]; then
    echo "--> 正在下载官方标准测试音频 (16kHz PCM test.wav)..."
    curl -fsSL "https://raw.githubusercontent.com/alphacep/vosk-api/master/python/example/test.wav" -o "${WAV_FILE}"
fi

# 2. 自动准备官方轻量级英文模型 (vosk-model-small-en-us-0.15)
if [ ! -d "${MODEL_DIR}" ] || [ ! -f "${MODEL_DIR}/am/final.mdl" ]; then
    echo "--> 正在下载官方轻量级测试模型 (vosk-model-small-en-us-0.15, ~40MB)..."
    mkdir -p "${SCRIPT_DIR}/model_tmp"
    curl -fsSL "https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip" -o "${SCRIPT_DIR}/model.zip"
    unzip -q -o "${SCRIPT_DIR}/model.zip" -d "${SCRIPT_DIR}/model_tmp"
    rm -rf "${MODEL_DIR}"
    mv "${SCRIPT_DIR}/model_tmp/vosk-model-small-en-us-0.15" "${MODEL_DIR}"
    rm -rf "${SCRIPT_DIR}/model_tmp" "${SCRIPT_DIR}/model.zip"
fi

# 3. 确定头文件与库文件
HEADER_FILE="${LIB_DIR}/vosk_api.h"
if [ ! -f "${HEADER_FILE}" ]; then
    HEADER_FILE="${ROOT_DIR}/src/apple/vosk-api/src/vosk_api.h"
fi

export DYLD_LIBRARY_PATH="${LIB_DIR}:${DYLD_LIBRARY_PATH:-}"
export DYLD_FALLBACK_LIBRARY_PATH="${LIB_DIR}:${DYLD_FALLBACK_LIBRARY_PATH:-}"
export LD_LIBRARY_PATH="${LIB_DIR}:${LD_LIBRARY_PATH:-}"

echo "--> 正在编译 E2E 测试可执行程序..."
CC="${CC:-gcc}"
if [ "$(uname)" = "Darwin" ]; then
    CC="clang"
fi

TEST_BIN="${SCRIPT_DIR}/test_e2e_runner"
rm -f "${TEST_BIN}"

# 检测动态库 vs 静态库
if [ -f "${LIB_DIR}/libvosk.dylib" ]; then
    echo "--> [macOS 动态库测试] 链接 libvosk.dylib ..."
    "${CC}" -O2 -I"$(dirname "${HEADER_FILE}")" "${SCRIPT_DIR}/test_vosk_e2e.c" \
        -L"${LIB_DIR}" -lvosk -Wl,-rpath,"${LIB_DIR}" -o "${TEST_BIN}"
    "${TEST_BIN}" "${MODEL_DIR}" "${WAV_FILE}"

elif [ -f "${LIB_DIR}/libvosk.so" ]; then
    echo "--> [Linux 动态库测试] 链接 libvosk.so ..."
    "${CC}" -O2 -I"$(dirname "${HEADER_FILE}")" "${SCRIPT_DIR}/test_vosk_e2e.c" \
        -L"${LIB_DIR}" -lvosk -lpthread -lm -ldl -Wl,-rpath,"${LIB_DIR}" -o "${TEST_BIN}"
    "${TEST_BIN}" "${MODEL_DIR}" "${WAV_FILE}"

elif [ -f "${LIB_DIR}/libvosk.a" ]; then
    echo "--> [静态库测试] 链接 libvosk.a ..."
    if [ "$(uname)" = "Darwin" ]; then
        clang++ -O2 -I"$(dirname "${HEADER_FILE}")" "${SCRIPT_DIR}/test_vosk_e2e.c" \
            "${LIB_DIR}/libvosk.a" -framework Accelerate -lpthread -lm -ldl -o "${TEST_BIN}"
    else
        g++ -O2 -I"$(dirname "${HEADER_FILE}")" "${SCRIPT_DIR}/test_vosk_e2e.c" \
            "${LIB_DIR}/libvosk.a" -lpthread -lm -ldl -o "${TEST_BIN}"
    fi
    "${TEST_BIN}" "${MODEL_DIR}" "${WAV_FILE}"

elif [ -f "${LIB_DIR}/libvosk.dll" ]; then
    echo "--> [Windows GNU 动态库测试] (若在 Wine 或 Windows 宿主下运行) ..."
    if command -v wine >/dev/null 2>&1; then
        x86_64-w64-mingw32-gcc -O2 -I"$(dirname "${HEADER_FILE}")" "${SCRIPT_DIR}/test_vosk_e2e.c" \
            -L"${LIB_DIR}" -lvosk -o "${TEST_BIN}.exe"
        WINEDEBUG=-all wine "${TEST_BIN}.exe" "${MODEL_DIR}" "${WAV_FILE}"
    else
        echo "⚠️ 注意: 当前非 Windows 环境且无 Wine，跳过 Windows 运行时执行。"
    fi
else
    echo "❌ 错误: 在 ${LIB_DIR} 中未找到可测试的 libvosk 动态库或静态库！"
    exit 1
fi

rm -f "${TEST_BIN}" "${TEST_BIN}.exe"
echo "✔ 🎉 E2E 自动化测试调度完成！"
