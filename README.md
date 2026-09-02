# Vosk API Multi-Platform (64-Bit & 32-Bit) Cross-Arch Prebuilt Distribution

[![Build and Distribute LibVosk Multi-Platform](https://github.com/santalex/libvosk/actions/workflows/build.yml/badge.svg)](https://github.com/santalex/libvosk/actions/workflows/build.yml)
[![License](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)
[![Platform Matrix](https://img.shields.io/badge/Platforms-macOS%20%7C%20iOS%20%7C%20tvOS%20%7C%20Windows%20%7C%20Linux%20%7C%20Android%20%7C%20RISC--V-brightgreen.svg)]()


This repository provides an automated, hermetic, Docker-based multi-platform build engine and binary distribution for [Vosk API](https://github.com/alphacep/vosk-api) (v0.3.50+), covering 64-bit, 32-bit, and cross-architecture targets across Desktop, Mobile, TV, and Embedded Linux ecosystems.

> [!NOTE]
> **Status & Verification Policy**:
> - **In Active Production Use**: The **macOS binaries (`libvosk-macos-*-static.zip` / `.dylib` / `.a`)** are actively used and battle-tested in real daily production workflows.
> - **CI Automated E2E Testing**: Native host platforms (macOS, Linux x86_64, Windows MSVC) undergo automated End-to-End (E2E) ASR decoding test suites (`tests/test_vosk_e2e.c`) in CI.
> - **Cross-Compiled Targets**: Cross-compiled targets (Windows GNU MinGW, iOS, tvOS, watchOS, visionOS, Android, RISC-V) are built using standard toolchains and verified for package structure and symbols (`tools/verify_packages.py`). To conserve CI resources and avoid heavy emulation, they are not executed in emulator/Wine during CI, and are provided to the community for experimentation. Please refer to the [Disclaimer & License](#️-disclaimer--license) below.

---


## 🌐 Supported Target Platform Matrix

| OS / Ecosystem | Architecture (`--arch`) | Shared Package (`-shared.zip`) | Static Package (`-static.zip`) | XCFramework Package (`-xcframework.zip`) |
| :--- | :--- | :--- | :--- | :--- |
| **macOS** | `arm64` *(macOS 11.0+)* | `libvosk-macos-arm64-shared.zip` (`.dylib`) | `libvosk-macos-arm64-static.zip` (`.a`) | - |
| **macOS** | `x86_64` *(macOS 11.0+)* | `libvosk-macos-x86_64-shared.zip` (`.dylib`) | `libvosk-macos-x86_64-static.zip` (`.a`) | - |
| **macOS** | `universal` *(macOS 11.0+)* | `libvosk-macos-universal-shared.zip` | `libvosk-macos-universal-static.zip` | `libvosk-macos-xcframework.zip` |
| **iOS** | `universal` *(iOS 12.0+)* | - | `libvosk-ios-static.zip` (`.a`) | `libvosk-ios-xcframework.zip` |
| **tvOS** | `universal` *(tvOS 12.0+)* | - | `libvosk-tvos-static.zip` (`.a`) | `libvosk-tvos-xcframework.zip` |
| **~~watchOS~~** | `universal` *(watchOS 6.0+)* | - | `libvosk-watchos-static.zip` (`.a`) | `libvosk-watchos-xcframework.zip` |
| **~~visionOS~~** | `universal` *(visionOS 1.0+)* | - | `libvosk-visionos-static.zip` (`.a`) | `libvosk-visionos-xcframework.zip` |
| **Apple** | `universal` (macOS+iOS+tvOS+watchOS+visionOS) | - | - | `libvosk-apple-xcframework.zip` (Super `XCFramework`) |
| **Windows (MSVC)** | `x86_64` | `libvosk-windows-msvc-x86_64-shared.zip` | `libvosk-windows-msvc-x86_64-static.zip` | - |
| **Windows (MSVC)** | `arm64` | `libvosk-windows-msvc-arm64-shared.zip` | `libvosk-windows-msvc-arm64-static.zip` | - |
| **Windows (MSVC)** | `x86` | `libvosk-windows-msvc-x86-shared.zip` | `libvosk-windows-msvc-x86-static.zip` | - |
| **Windows (GNU)** | `x86_64` | `libvosk-windows-gnu-x86_64-shared.zip` | `libvosk-windows-gnu-x86_64-static.zip` | - |
| **Windows (GNU)** | `arm64` | `libvosk-windows-gnu-arm64-shared.zip` | `libvosk-windows-gnu-arm64-static.zip` | - |
| **Windows (GNU)** | `x86` | `libvosk-windows-gnu-x86-shared.zip` | `libvosk-windows-gnu-x86-static.zip` | - |
| **Linux** | `x86_64` | `libvosk.so` | `libvosk.a` | - |
| **Linux** | `aarch64` | `libvosk.so` | `libvosk.a` | - |
| **Linux** | `riscv64` | `libvosk.so` | `libvosk.a` | - |
| **Linux** | `armv7l` | `libvosk.so` | `libvosk.a` | - |
| **Linux** | `x86` | `libvosk.so` | `libvosk.a` | - |
| **Android** | `arm64-v8a` | `libvosk.so` | `libvosk.a` | - |
| **Android** | `x86_64` | `libvosk.so` | `libvosk.a` | - |

---

## 🚀 Quick Start

### Build All Target Binaries
```bash
./build.sh
```

### Build Specific OS and Architecture
```bash
# macOS Universal (arm64 + x86_64)
./build.sh --os macos --arch universal

# iOS / tvOS / watchOS / visionOS XCFramework
./build.sh --os ios --arch universal
./build.sh --os tvos --arch universal
./build.sh --os watchos --arch universal
./build.sh --os visionos --arch universal

# Apple Super XCFramework (All 5 Apple OSs)
./build.sh --os apple --arch universal

# Windows GNU (MinGW-w64 交叉编译)
./build.sh --os windows-gnu --arch x86_64
./build.sh --os windows-gnu --arch arm64

# Windows MSVC (PowerShell 原生编译)
.\src\windows-msvc\build.ps1 -Arch x86_64

# Linux RISC-V 64-bit / ARM64
./build.sh --os linux --arch riscv64
./build.sh --os linux --arch aarch64

# Android ARM64
./build.sh --os android --arch arm64-v8a
```

---

## 🧪 Automated Testing & Static Library Slimming

### 1. End-to-End (E2E) Test Suite
The repository includes an automated cross-platform E2E test harness covering model loading, streaming recognition, word timestamps, dynamic grammar constraints, and recognizer reset:
```bash
./tests/run_tests.sh dist/macos/arm64
```

### 2. Static Library Transitive Slimming
Safely prunes unused Kaldi offline and training object files, reducing static archive size from ~360MB to ~170MB (53%+ reduction) in seconds:
```bash
python3 tools/slim_archive.py dist/macos/arm64/libvosk.a dist/macos/arm64/libvosk_slim.a
```

---

## ⚡ Performance & Acceleration Notes

### CPU Acceleration (OpenBLAS & Apple Accelerate)
- **Apple (macOS / iOS / tvOS)**: Compiled with native Apple `Accelerate.framework` (AMX / Neon vector instructions) for peak M-series / A-series efficiency.
- **x86_64 (Linux / Windows)**: Multi-threaded OpenBLAS with dynamic AVX2 / FMA instruction dispatch.
- **ARM64 (Linux / Android)**: OpenBLAS Neon vectorization.
- **RISC-V 64**: Compiled with OpenBLAS 64-bit RISC-V optimization flags.

### GPU Acceleration (NVIDIA CUDA)
For NVIDIA GPU acceleration on Linux/Windows, CUDA dynamic linking requires compiling against CUDA Toolkit headers. Instructions and Docker build flags can be found in `src/linux/x86_64/Dockerfile`.

---

## ⚖️ Disclaimer & License

### Disclaimer
This repository is maintained primarily for personal workflows and experimental builds. Currently, only the macOS static binaries have been verified in active use; all multi-platform prebuilt binaries are shared publicly with the open-source community on an **"AS IS"** basis, without warranties or conditions of any kind, either express or implied.

Users are encouraged to evaluate and verify the prebuilt artifacts for their own use cases.

### License
This project and the distributed binaries are licensed under the [Apache License, Version 2.0](LICENSE), in full alignment with upstream [Vosk API](https://github.com/alphacep/vosk-api).
