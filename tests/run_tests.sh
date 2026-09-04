#!/usr/bin/env bash
# ==============================================================================
# LibVosk Cross-Platform E2E Test Runner
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

LIB_DIR="${1:-}"
ASR_DIR="${SCRIPT_DIR}/asr"
SPK_DIR="${SCRIPT_DIR}/spk"
WAV_FILE="${SCRIPT_DIR}/test.wav"

if [ -z "${LIB_DIR}" ]; then
    echo "Usage: $0 <artifacts_dir_path, e.g. dist/macos/arm64 or dist/windows-gnu/x86_64>"
    exit 1
fi

LIB_DIR="$(cd "${LIB_DIR}" && pwd)"

echo "=============================================================================="
echo "  LibVosk E2E Automated Test Runner"
echo "  Target Directory: ${LIB_DIR}"
echo "=============================================================================="

# 1. Prepare test audio
if [ ! -f "${WAV_FILE}" ]; then
    echo "--> Downloading official standard test audio (16kHz PCM test.wav)..."
    curl -fsSL "https://raw.githubusercontent.com/alphacep/vosk-api/master/python/example/test.wav" -o "${WAV_FILE}"
fi

# 2. Prepare ASR model
if [ ! -d "${ASR_DIR}" ] || [ ! -f "${ASR_DIR}/am/final.mdl" ]; then
    if [ ! -f "${SCRIPT_DIR}/asr.zip" ]; then
        echo "--> Downloading ASR test model (vosk-model-small-en-us-0.15, ~40MB)..."
        curl -fsSL "https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip" -o "${SCRIPT_DIR}/asr.zip"
    fi
    echo "--> Extracting ASR model..."
    mkdir -p "${SCRIPT_DIR}/tmp_asr"
    unzip -q -o "${SCRIPT_DIR}/asr.zip" -d "${SCRIPT_DIR}/tmp_asr"
    rm -rf "${ASR_DIR}"
    INNER_ASR=$(find "${SCRIPT_DIR}/tmp_asr" -maxdepth 2 -type f -name "final.mdl" -exec dirname {} \; | sed 's#/am$##' | head -n 1)
    if [ -n "${INNER_ASR}" ] && [ -d "${INNER_ASR}" ]; then
        mv "${INNER_ASR}" "${ASR_DIR}"
    else
        FIRST_DIR=$(find "${SCRIPT_DIR}/tmp_asr" -mindepth 1 -maxdepth 1 -type d | head -n 1)
        mv "${FIRST_DIR}" "${ASR_DIR}"
    fi
    rm -rf "${SCRIPT_DIR}/tmp_asr"
fi

# 3. Prepare Speaker model
if [ ! -d "${SPK_DIR}" ] || [ ! -f "${SPK_DIR}/final.ext.raw" ]; then
    if [ ! -f "${SCRIPT_DIR}/spk.zip" ]; then
        echo "--> Downloading Speaker model (vosk-model-spk-0.4, ~13MB)..."
        curl -fsSL "https://alphacephei.com/vosk/models/vosk-model-spk-0.4.zip" -o "${SCRIPT_DIR}/spk.zip"
    fi
    echo "--> Extracting Speaker model..."
    mkdir -p "${SCRIPT_DIR}/tmp_spk"
    unzip -q -o "${SCRIPT_DIR}/spk.zip" -d "${SCRIPT_DIR}/tmp_spk"
    rm -rf "${SPK_DIR}"
    INNER_SPK=$(find "${SCRIPT_DIR}/tmp_spk" -maxdepth 2 -type f -name "final.ext.raw" -exec dirname {} \; | head -n 1)
    if [ -n "${INNER_SPK}" ] && [ -d "${INNER_SPK}" ]; then
        mv "${INNER_SPK}" "${SPK_DIR}"
    else
        FIRST_DIR=$(find "${SCRIPT_DIR}/tmp_spk" -mindepth 1 -maxdepth 1 -type d | head -n 1)
        mv "${FIRST_DIR}" "${SPK_DIR}"
    fi
    rm -rf "${SCRIPT_DIR}/tmp_spk"
fi

# 4. Determine header and library paths
HEADER_FILE="${LIB_DIR}/vosk_api.h"
if [ ! -f "${HEADER_FILE}" ]; then
    HEADER_FILE="${ROOT_DIR}/src/apple/vosk-api/src/vosk_api.h"
fi

export DYLD_LIBRARY_PATH="${LIB_DIR}:${DYLD_LIBRARY_PATH:-}"
export DYLD_FALLBACK_LIBRARY_PATH="${LIB_DIR}:${DYLD_FALLBACK_LIBRARY_PATH:-}"
export LD_LIBRARY_PATH="${LIB_DIR}:${LD_LIBRARY_PATH:-}"

echo "--> Compiling E2E test executable..."
CC="${CC:-gcc}"
if [ "$(uname)" = "Darwin" ]; then
    CC="clang"
fi

TEST_BIN="${SCRIPT_DIR}/test_e2e_runner"
rm -f "${TEST_BIN}"

TESTED_COUNT=0

# 1. Test dynamic shared library (.dylib / .so / .dll)
if [ -f "${LIB_DIR}/libvosk.dylib" ]; then
    echo "--> [1/2] [macOS Dynamic Library Test] Linking libvosk.dylib ..."
    TEST_BIN="${SCRIPT_DIR}/test_e2e_shared"
    "${CC}" -O2 -I"$(dirname "${HEADER_FILE}")" "${SCRIPT_DIR}/test_vosk_e2e.c" \
        -L"${LIB_DIR}" -lvosk -Wl,-rpath,"${LIB_DIR}" -o "${TEST_BIN}"
    "${TEST_BIN}" "${ASR_DIR}" "${WAV_FILE}" "${SPK_DIR}"
    rm -f "${TEST_BIN}"
    TESTED_COUNT=$((TESTED_COUNT + 1))
elif [ -f "${LIB_DIR}/libvosk.so" ]; then
    echo "--> [1/2] [Linux Dynamic Library Test] Linking libvosk.so ..."
    TEST_BIN="${SCRIPT_DIR}/test_e2e_shared"
    "${CC}" -O2 -I"$(dirname "${HEADER_FILE}")" "${SCRIPT_DIR}/test_vosk_e2e.c" \
        -L"${LIB_DIR}" -lvosk -lpthread -lm -ldl -Wl,-rpath,"${LIB_DIR}" -o "${TEST_BIN}"
    "${TEST_BIN}" "${ASR_DIR}" "${WAV_FILE}" "${SPK_DIR}"
    rm -f "${TEST_BIN}"
    TESTED_COUNT=$((TESTED_COUNT + 1))
elif [ -f "${LIB_DIR}/libvosk.dll" ]; then
    echo "--> [1/2] [Windows GNU Dynamic Library Test] ..."
    if command -v wine >/dev/null 2>&1; then
        TEST_BIN="${SCRIPT_DIR}/test_e2e_shared.exe"
        x86_64-w64-mingw32-gcc -O2 -I"$(dirname "${HEADER_FILE}")" "${SCRIPT_DIR}/test_vosk_e2e.c" \
            -L"${LIB_DIR}" -lvosk -o "${TEST_BIN}"
        WINEDEBUG=-all wine "${TEST_BIN}" "${ASR_DIR}" "${WAV_FILE}" "${SPK_DIR}"
        rm -f "${TEST_BIN}"
        TESTED_COUNT=$((TESTED_COUNT + 1))
    fi
fi

# 2. Test static archive (.a)
if [ -f "${LIB_DIR}/libvosk.a" ]; then
    echo "--> [2/2] [Static Library Test] Linking libvosk.a ..."
    TEST_BIN="${SCRIPT_DIR}/test_e2e_static"
    if [ "$(uname)" = "Darwin" ]; then
        clang++ -O2 -I"$(dirname "${HEADER_FILE}")" "${SCRIPT_DIR}/test_vosk_e2e.c" \
            "${LIB_DIR}/libvosk.a" -framework Accelerate -lpthread -lm -ldl -o "${TEST_BIN}"
    else
        g++ -O2 -I"$(dirname "${HEADER_FILE}")" "${SCRIPT_DIR}/test_vosk_e2e.c" \
            "${LIB_DIR}/libvosk.a" -lpthread -lm -ldl -lgfortran -o "${TEST_BIN}"
    fi
    "${TEST_BIN}" "${ASR_DIR}" "${WAV_FILE}" "${SPK_DIR}"
    rm -f "${TEST_BIN}"
    TESTED_COUNT=$((TESTED_COUNT + 1))
fi

if [ "${TESTED_COUNT}" -eq 0 ]; then
    echo "[ERROR] No testable libvosk dynamic or static library found in ${LIB_DIR}!"
    exit 1
fi

rm -f "${TEST_BIN}" "${TEST_BIN}.exe"
echo "[OK] E2E test execution completed successfully!"
