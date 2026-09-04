# Vosk API Multi-Platform (64-Bit & 32-Bit) Cross-Arch Prebuilt Distribution

[![Build and Distribute LibVosk Multi-Platform](https://github.com/santalex/libvosk/actions/workflows/build.yml/badge.svg)](https://github.com/santalex/libvosk/actions/workflows/build.yml)
[![License](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)
[![Platform Matrix](https://img.shields.io/badge/Platforms-macOS%20%7C%20iOS%20%7C%20tvOS%20%7C%20visionOS%20%7C%20Windows%20%7C%20Linux%20%7C%20Android%20%7C%20RISC--V-brightgreen.svg)]()


This repository provides an automated, hermetic, multi-platform build engine and binary distribution for [Vosk API](https://github.com/alphacep/vosk-api) (v0.3.50+), covering 64-bit, 32-bit, and cross-architecture targets across Desktop, Mobile, TV, Spatial Computing, and Embedded Linux ecosystems.

> [!NOTE]
> ### Platform Testing & Verification Policy
>
> - **Battle-Tested in Real-World Production**:
>   - **macOS (`arm64` Apple Silicon & `x86_64` Intel)**: Actively used and battle-tested in real daily production desktop workflows.
>   - **Windows (`x86_64`, MSVC)**: Extensively verified in real-world desktop production applications with proven stability.
>   - **Linux (`x86_64`)**: Extensively verified in real-world desktop production environments (including Linux Mint and Ubuntu x86_64).
>
> - **CI Automated E2E Testing**:
>   - Native host platforms (macOS, Linux x86_64, Windows MSVC) undergo automated End-to-End (E2E) ASR decoding test suites (`tests/test_vosk_e2e.c`) in CI.
>
> - **Community Cross-Compiled Targets (User Testing Required)**:
>   - **iOS / tvOS / visionOS / Android / Windows GNU / Linux (ARM/RISC-V)**:
>   - All binaries are built using standard toolchains and strictly verified for package structure, Mach-O / ELF slice integrity, and C API symbol export (`tools/verify_packages.py`).
>   - **Notice**: Due to personal hardware and time limitations, the maintainer cannot regression-test on every physical device or emulator environment. **Developers are strongly advised to thoroughly test and evaluate these binaries in their target hardware before deploying to production.** Community feedback, test reports, and PRs are warmly welcomed.
>
> ---
>
> ### Why watchOS is Not Supported
> watchOS is intentionally not supported due to strict system runtime and hardware constraints:
> 1. **Strict Memory Ceiling**: watchOS enforces very aggressive Jetsam limits (~30MB-80MB for third-party apps). Offline Kaldi ASR acoustic and language models require substantial memory that easily triggers out-of-memory termination.
> 2. **Architecture & ABI Conflict**: Modern watchOS uses the `arm64_32` (ILP32) ABI (64-bit registers with 32-bit pointers), which conflicts with upstream Kaldi / OpenFST 64-bit integer indexing and standard Autotools toolchains.
> 3. **Thermal & Battery Constraints**: Continuous offline speech recognition matrix computation is unsuitable for wearable battery capacities and thermal envelopes.

---

## Supported Target Platform Matrix

| OS / Ecosystem | Architecture (`--arch`) | Shared Package (`-shared.zip`) | Static Package (`-static.zip`) | XCFramework Package (`-xcframework.zip`) |
| :--- | :--- | :--- | :--- | :--- |
| **macOS** | `arm64` *(macOS 11.0+)* | `libvosk-macos-arm64-shared.zip` (`.dylib`) | `libvosk-macos-arm64-static.zip` (`.a`) | - |
| **macOS** | `x86_64` *(macOS 11.0+)* | `libvosk-macos-x86_64-shared.zip` (`.dylib`) | `libvosk-macos-x86_64-static.zip` (`.a`) | - |
| **macOS** | `universal` *(macOS 11.0+)* | `libvosk-macos-universal-shared.zip` | `libvosk-macos-universal-static.zip` | `libvosk-macos-xcframework.zip` |
| **iOS** | `universal` *(iOS 12.0+)* | - | `libvosk-ios-static.zip` (`.a`) | `libvosk-ios-xcframework.zip` |
| **tvOS** | `universal` *(tvOS 12.0+)* | - | `libvosk-tvos-static.zip` (`.a`) | `libvosk-tvos-xcframework.zip` |
| **visionOS** | `universal` *(visionOS 1.0+)* | - | `libvosk-visionos-static.zip` (`.a`) | `libvosk-visionos-xcframework.zip` |
| **Apple** | `universal` (macOS+iOS+tvOS+visionOS) | - | - | `libvosk-apple-xcframework.zip` (Super `XCFramework`) |
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

## Quick Start

### Build All Target Binaries
```bash
./build.sh
```

### Build Specific OS and Architecture
```bash
# macOS Universal (arm64 + x86_64)
./build.sh --os macos --arch universal

# iOS / tvOS / visionOS XCFramework
./build.sh --os ios --arch universal
./build.sh --os tvos --arch universal
./build.sh --os visionos --arch universal

# Apple Super XCFramework (All 4 Apple OSs: macOS + iOS + tvOS + visionOS)
./build.sh --os apple --arch universal

# Windows GNU (MinGW-w64 Cross-Compilation)
./build.sh --os windows-gnu --arch x86_64
./build.sh --os windows-gnu --arch arm64

# Windows MSVC (Native PowerShell Build)
.\src\windows-msvc\build.ps1 -Arch x86_64

# Linux RISC-V 64-bit / ARM64
./build.sh --os linux --arch riscv64
./build.sh --os linux --arch aarch64

# Android ARM64
./build.sh --os android --arch arm64-v8a
```

---

## Automated Testing & Static Library Slimming

### 1. End-to-End (E2E) Test Suite
The repository includes an automated cross-platform E2E test harness covering model loading, streaming recognition, word timestamps, and recognizer reset:
```bash
./tests/run_tests.sh dist/macos/arm64
```

### 2. Static Library Transitive Slimming
Safely prunes unused Kaldi offline and training object files, reducing static archive size from ~360MB to ~19MB (94%+ reduction) in seconds:
```bash
python3 tools/slim_archive.py dist/macos/arm64/libvosk.a dist/macos/arm64/libvosk_slim.a
```

---

## Performance & Acceleration Notes

### CPU Acceleration (OpenBLAS & Apple Accelerate)
- **Apple (macOS / iOS / tvOS / visionOS)**: Compiled with native Apple `Accelerate.framework` (AMX / Neon vector instructions) for peak M-series / A-series efficiency.
- **x86_64 (Linux / Windows)**: Multi-threaded OpenBLAS with dynamic AVX2 / FMA instruction dispatch.
- **ARM64 (Linux / Android)**: OpenBLAS Neon vectorization.
- **RISC-V 64**: Compiled with OpenBLAS 64-bit RISC-V optimization flags.

### GPU Acceleration (NVIDIA CUDA)
For NVIDIA GPU acceleration on Linux/Windows, CUDA dynamic linking requires compiling against CUDA Toolkit headers. Instructions and Docker build flags can be found in `src/linux/x86_64/Dockerfile`.

---

## Disclaimer & License

### Disclaimer
This repository is maintained primarily for personal workflows and experimental builds. The macOS, Windows (MSVC), and Linux (x86_64) binaries are battle-tested in real-world desktop production applications. Other cross-compiled targets are provided to the open-source community on an **"AS IS"** basis, without warranties or conditions of any kind, either express or implied.

Users are encouraged to evaluate and verify the prebuilt artifacts for their own specific hardware and software environments before adopting them.

### License
This project and the distributed binaries are licensed under the [Apache License, Version 2.0](LICENSE), in full alignment with upstream [Vosk API](https://github.com/alphacep/vosk-api).
