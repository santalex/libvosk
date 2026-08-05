# Vosk API Multi-Platform (64-Bit & 32-Bit) Cross-Arch Prebuilt Distribution

[![Build and Distribute LibVosk Multi-Platform](https://github.com/santalex/libvosk/actions/workflows/build.yml/badge.svg)](https://github.com/santalex/libvosk/actions/workflows/build.yml)
[![License](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)
[![Platform Matrix](https://img.shields.io/badge/Platforms-macOS%20%7C%20iOS%20%7C%20tvOS%20%7C%20Windows%20%7C%20Linux%20%7C%20Android%20%7C%20RISC--V-brightgreen.svg)]()


This repository provides an automated, hermetic, Docker-based multi-platform build engine and binary distribution for [Vosk API](https://github.com/alphacep/vosk-api) (v0.3.50+), covering 64-bit, 32-bit, and cross-architecture targets across Desktop, Mobile, TV, and Embedded Linux ecosystems.

> [!NOTE]
> **Status Note**: Currently, only the **macOS static libraries (`libvosk-macos-*-static.zip` / `.a`)** have been fully tested and verified in production environments. Binary packages for other platforms are compiled using standard toolchains and provided as prebuilt releases.

---


## 🌐 Supported Target Platform Matrix

| OS / Ecosystem | Architecture (`--arch`) | Shared Package (`-shared.zip`) | Static Package (`-static.zip`) | XCFramework Package (`-xcframework.zip`) |
| :--- | :--- | :--- | :--- | :--- |
| **macOS** | `arm64` | `libvosk-macos-arm64-shared.zip` (`.dylib`) | `libvosk-macos-arm64-static.zip` (`.a`) | - |
| **macOS** | `x86_64` | `libvosk-macos-x86_64-shared.zip` (`.dylib`) | `libvosk-macos-x86_64-static.zip` (`.a`) | - |
| **macOS** | `universal` | `libvosk-macos-universal-shared.zip` | `libvosk-macos-universal-static.zip` | `libvosk-macos-xcframework.zip` |
| **iOS** | `universal` | - | `libvosk-ios-static.zip` (`.a`) | `libvosk-ios-xcframework.zip` |
| **tvOS** | `universal` | - | `libvosk-tvos-static.zip` (`.a`) | `libvosk-tvos-xcframework.zip` |
| **Apple** | `universal` (macOS+iOS+tvOS) | - | - | `libvosk-apple-xcframework.zip` (Super `XCFramework`) |
| **Windows** | `x86_64` | `libvosk.dll` + `libvosk.lib` | `libvosk_static.lib` + `libvosk.a` | - |
| **Windows** | `arm64` | `libvosk.dll` + `libvosk.lib` | `libvosk_static.lib` + `libvosk.a` | - |
| **Windows** | `x86` | `libvosk.dll` + `libvosk.lib` | `libvosk_static.lib` + `libvosk.a` | - |
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

# iOS XCFramework
./build.sh --os ios --arch universal

# tvOS XCFramework
./build.sh --os tvos --arch universal

# Apple Super XCFramework (macOS + iOS + tvOS)
./build.sh --os apple --arch universal

# Windows 64-bit Intel/AMD
./build.sh --os windows --arch x86_64

# Windows 64-bit ARM
./build.sh --os windows --arch arm64

# Windows 32-bit Intel
./build.sh --os windows --arch x86

# Linux RISC-V 64-bit
./build.sh --os linux --arch riscv64

# Linux ARM64
./build.sh --os linux --arch aarch64

# Android 64-bit ARM
./build.sh --os android --arch arm64-v8a
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

## 📄 License
Licensed under the Apache License, Version 2.0.
