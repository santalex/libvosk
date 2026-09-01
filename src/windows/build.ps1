# ==============================================================================
# build.ps1 - Vosk API Windows (MSVC Native) Build & Slimming Engine
#
# Arguments:
#   -Arch <x86_64|arm64|x86|all>       (Default: x86_64)
#   -LinkType <all|static|shared>      (Default: all)
#   -VoskTag <v0.3.50|master|...>      (Default: v0.3.50)
#   -OnlyPackage                       Package existing dist directory
# ==============================================================================

[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [ValidateSet("x86_64", "arm64", "x86", "all")]
    [string]$Arch = "x86_64",

    [Parameter(Position = 1)]
    [ValidateSet("all", "static", "shared")]
    [string]$LinkType = "all",

    [Parameter(Position = 2)]
    [string]$VoskTag = "v0.3.50",

    [switch]$OnlyPackage = $false
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir = Split-Path -Parent (Split-Path -Parent $ScriptDir)
Set-Location $ScriptDir

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "  Vosk API Windows (MSVC) Native Build Engine" -ForegroundColor Cyan
Write-Host "  Target Arch : $Arch" -ForegroundColor Cyan
Write-Host "  Link Type   : $LinkType" -ForegroundColor Cyan
Write-Host "  Vosk Tag    : $VoskTag" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan

# ------------------------------------------------------------------------------
# 1. Initialize MSVC Environment (vcvarsall.bat)
# ------------------------------------------------------------------------------
function Initialize-MSVC-Environment([string]$targetArch) {
    Write-Host "--> Initializing MSVC environment for $targetArch..." -ForegroundColor Yellow

    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) {
        $vswhere = "vswhere.exe"
    }

    $vsInstallPath = ""
    try {
        $vsInstallPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    } catch {
        $vsInstallPath = ""
    }

    if (-not $vsInstallPath -or -not (Test-Path $vsInstallPath)) {
        $candidates = @(
            "C:\Program Files\Microsoft Visual Studio\2022\Enterprise",
            "C:\Program Files\Microsoft Visual Studio\2022\Community",
            "C:\Program Files\Microsoft Visual Studio\2022\Professional",
            "C:\Program Files\Microsoft Visual Studio\2022\BuildTools",
            "C:\Program Files (x86)\Microsoft Visual Studio\2019\Enterprise",
            "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community"
        )
        foreach ($c in $candidates) {
            if (Test-Path $c) {
                $vsInstallPath = $c
                break
            }
        }
    }

    if (-not $vsInstallPath) {
        throw "Visual Studio MSVC installation path not found!"
    }

    $vcvars = Join-Path $vsInstallPath "VC\Auxiliary\Build\vcvarsall.bat"
    if (-not (Test-Path $vcvars)) {
        throw "vcvarsall.bat not found at: $vcvars"
    }

    $vcArch = switch ($targetArch) {
        "x86_64" { "x64" }
        "x86"    { "x86" }
        "arm64"  { "x64_arm64" }
        default  { "x64" }
    }

    $tempFile = [System.IO.Path]::GetTempFileName()
    cmd.exe /c "`"$vcvars`" $vcArch && set > `"$tempFile`""
    Get-Content $tempFile | ForEach-Object {
        if ($_ -match "^(.*?)=(.*)$") {
            Set-Item -Force -Path "env:$($matches[1])" -Value "$($matches[2])"
        }
    }
    Remove-Item -Force $tempFile

    Write-Host "MSVC environment successfully loaded." -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 2. Prepare Source Code & Dependencies
# ------------------------------------------------------------------------------
function Prepare-Dependencies {
    $DepsDir = Join-Path $ScriptDir "deps"
    if (-not (Test-Path $DepsDir)) {
        New-Item -ItemType Directory -Path $DepsDir -Force | Out-Null
    }

    $openfstDir = Join-Path $DepsDir "openfst"
    $kaldiDir = Join-Path $DepsDir "kaldi"
    $voskDir = Join-Path $DepsDir "vosk-api"

    # A. OpenFST (CMake & MSVC Compatible Port)
    if (-not (Test-Path (Join-Path $openfstDir "CMakeLists.txt"))) {
        Write-Host "--> Cloning OpenFST repository (k2-fsa CMake port)..." -ForegroundColor Yellow
        if (Test-Path $openfstDir) {
            Remove-Item -Recurse -Force $openfstDir -ErrorAction SilentlyContinue
        }
        git clone --depth=1 https://github.com/k2-fsa/openfst $openfstDir
    }

    # B. Kaldi (Vosk Fork)
    if (-not (Test-Path (Join-Path $kaldiDir "src"))) {
        Write-Host "--> Cloning Kaldi repository..." -ForegroundColor Yellow
        if (Test-Path $kaldiDir) {
            Remove-Item -Recurse -Force $kaldiDir -ErrorAction SilentlyContinue
        }
        git clone -b vosk-android --single-branch --depth=1 https://github.com/alphacep/kaldi $kaldiDir
    }

    # Generate Kaldi version.h if missing
    $versionH = Join-Path "$kaldiDir\src\base" "version.h"
    if (-not (Test-Path $versionH)) {
        "#ifndef KALDI_BASE_VERSION_H_`n#define KALDI_BASE_VERSION_H_`n#define KALDI_VERSION `"5.5`"`n#define KALDI_GIT_HEAD `"vosk`"`n#endif" | Set-Content -Path $versionH -Encoding ASCII
    }

    # C. Vosk API
    if (-not (Test-Path (Join-Path $voskDir "src"))) {
        Write-Host "--> Cloning Vosk API repository (Tag: $VoskTag)..." -ForegroundColor Yellow
        if (Test-Path $voskDir) {
            Remove-Item -Recurse -Force $voskDir -ErrorAction SilentlyContinue
        }
        $tagParam = if ($VoskTag -and $VoskTag -ne "master") { "-b", "$VoskTag" } else { @() }
        git clone @tagParam --single-branch --depth=1 https://github.com/alphacep/vosk-api $voskDir
    }
}

# ------------------------------------------------------------------------------
# 3. Build Single Target Architecture (x86_64 / arm64 / x86)
# ------------------------------------------------------------------------------
function Build-Target-Arch([string]$targetArch) {
    Write-Host "==============================================================================" -ForegroundColor Cyan
    Write-Host "  Building Windows [$targetArch] ..." -ForegroundColor Cyan
    Write-Host "==============================================================================" -ForegroundColor Cyan

    Initialize-MSVC-Environment $targetArch

    $BuildWorkDir = Join-Path $ScriptDir "build_$targetArch"
    $OutDir = Join-Path $RootDir "dist\windows\$targetArch"
    New-Item -ItemType Directory -Path $BuildWorkDir -Force | Out-Null
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

    $DepsDir = Join-Path $ScriptDir "deps"
    $OpenBLASDir = Join-Path $BuildWorkDir "openblas"
    $OpenFSTDir = Join-Path $BuildWorkDir "openfst"
    $KaldiDir = Join-Path $DepsDir "kaldi"
    $VoskApiDir = Join-Path $DepsDir "vosk-api"

    # --------------------------------------------------------------------------
    # 3.1 Setup OpenBLAS MSVC binaries
    # --------------------------------------------------------------------------
    $blasLib = Join-Path $OpenBLASDir "lib\libopenblas.lib"
    if (-not (Test-Path $blasLib)) {
        Write-Host "--> Downloading OpenBLAS MSVC binaries for $targetArch..." -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $OpenBLASDir -Force | Out-Null
        
        $blasZip = Join-Path $BuildWorkDir "openblas.zip"
        $blasUrl = "https://github.com/OpenMathLib/OpenBLAS/releases/download/v0.3.28/openblas-0.3.28-x64.zip"
        if ($targetArch -eq "x86") {
            $blasUrl = "https://github.com/OpenMathLib/OpenBLAS/releases/download/v0.3.28/openblas-0.3.28-x86.zip"
        }
        
        Invoke-WebRequest -Uri $blasUrl -OutFile $blasZip -UseBasicParsing
        Expand-Archive -Path $blasZip -DestinationPath $OpenBLASDir -Force
        Remove-Item -Force $blasZip
    }

    # --------------------------------------------------------------------------
    # 3.2 Build OpenFST with CMake + MSVC
    # --------------------------------------------------------------------------
    Write-Host "--> Building OpenFST with CMake..." -ForegroundColor Yellow
    $fstBuild = Join-Path $BuildWorkDir "fst_build"
    $fstInstall = Join-Path $BuildWorkDir "fst_install"
    New-Item -ItemType Directory -Path $fstBuild -Force | Out-Null
    New-Item -ItemType Directory -Path $fstInstall -Force | Out-Null
    
    $cmakeArch = switch ($targetArch) {
        "x86_64" { "x64" }
        "x86"    { "Win32" }
        "arm64"  { "ARM64" }
        default  { "x64" }
    }

    cmake -B $fstBuild -S "$DepsDir\openfst" -A $cmakeArch `
          -DBUILD_SHARED_LIBS=OFF `
          -DFST_NO_DYNAMIC_LINKING=ON `
          -DENABLE_LOOKAHEAD_FSTS=ON `
          -DENABLE_NGRAM_FSTS=ON `
          -DCMAKE_INSTALL_PREFIX="$fstInstall" `
          -DCMAKE_BUILD_TYPE=Release `
          -DCMAKE_CXX_FLAGS="/O2 /Gy /Gw /EHsc /MD /D_CRT_SECURE_NO_WARNINGS"

    cmake --build $fstBuild --config Release --target install --parallel

    # --------------------------------------------------------------------------
    # 3.3 Compile Kaldi Core Inference Modules (Dead-Code Pruning)
    # --------------------------------------------------------------------------
    Write-Host "--> Compiling Kaldi core inference modules..." -ForegroundColor Yellow
    $kaldiObjDir = Join-Path $BuildWorkDir "kaldi_objs"
    New-Item -ItemType Directory -Path $kaldiObjDir -Force | Out-Null

    $kaldiInclude = "$KaldiDir\src"
    $blasInclude = "$OpenBLASDir\include"
    $voskInclude = "$VoskApiDir\src"

    # Core inference modules (CPU fallback for CuMatrix and lattice/graph helpers)
    $modules = @(
        "base",
        "matrix",
        "cudamatrix",
        "util",
        "feat",
        "tree",
        "gmm",
        "transform",
        "fstext",
        "hmm",
        "lm",
        "decoder",
        "lat",
        "nnet3",
        "online2",
        "rnnlm",
        "ivector"
    )
    $ccFiles = @()
    foreach ($m in $modules) {
        $mPath = Join-Path "$KaldiDir\src" $m
        if (Test-Path $mPath) {
            Get-ChildItem -Path $mPath -Filter "*.cc" | ForEach-Object {
                if (-not ($_.Name -like "*-test.cc") -and -not ($_.Name -like "*-bin.cc")) {
                    $ccFiles += $_.FullName
                }
            }
        }
    }

    Write-Host "--> Found $($ccFiles.Count) Kaldi source files to compile..." -ForegroundColor Gray
    
    $clArgs = @(
        "/nologo",
        "/c",
        "/O2",
        "/Gy",
        "/Gw",
        "/GL",
        "/EHsc",
        "/MD",
        "/D_CRT_SECURE_NO_WARNINGS",
        "/DHAVE_OPENBLAS=1",
        "/DHAVE_CUDA=0",
        "/DKALDI_DOUBLEPRECISION=0",
        "/DFST_NO_DYNAMIC_LINKING=1",
        "/D_USE_MATH_DEFINES",
        "/Dlapack_complex_float=std::complex<float>",
        "/Dlapack_complex_double=std::complex<double>",
        "/DLAPACK_COMPLEX_CUSTOM=1",
        "/I$kaldiInclude",
        "/I$fstInstall\include",
        "/I$DepsDir\openfst\src\include",
        "/I$DepsDir\openfst\include",
        "/I$DepsDir\openfst",
        "/I$blasInclude",
        "/I$voskInclude"
    )

    # Batch compile in groups of 30
    $batchSize = 30
    for ($i = 0; $i -lt $ccFiles.Count; $i += $batchSize) {
        $batch = $ccFiles[$i..[Math]::Min($i + $batchSize - 1, $ccFiles.Count - 1)]
        $currentClArgs = $clArgs + $batch
        
        Push-Location $kaldiObjDir
        try {
            & cl.exe $currentClArgs
        } finally {
            Pop-Location
        }
    }

    # --------------------------------------------------------------------------
    # 3.4 Compile Vosk API
    # --------------------------------------------------------------------------
    Write-Host "--> Compiling Vosk API (vosk_api.cc)..." -ForegroundColor Yellow
    Push-Location $kaldiObjDir
    try {
        & cl.exe $clArgs "$VoskApiDir\src\vosk_api.cc"
    } finally {
        Pop-Location
    }

    # --------------------------------------------------------------------------
    # 3.5 Build Static Library (libvosk.lib)
    # --------------------------------------------------------------------------
    if ($LinkType -eq "all" -or $LinkType -eq "static") {
        Write-Host "--> Packaging static library (libvosk.lib)..." -ForegroundColor Green
        
        $allObjs = Get-ChildItem -Path $kaldiObjDir -Filter "*.obj" | ForEach-Object { $_.FullName }
        $fstLibs = Get-ChildItem -Path @($fstInstall, $fstBuild) -Recurse -Filter "*.lib" | ForEach-Object { $_.FullName } | Select-Object -Unique
        $blasLibs = Get-ChildItem -Path "$OpenBLASDir\lib" -Filter "*.lib" | ForEach-Object { $_.FullName }

        $staticOut = Join-Path $OutDir "libvosk.lib"
        $staticOutAlt = Join-Path $OutDir "libvosk_static.lib"
        
        $rspFile = Join-Path $BuildWorkDir "static_lib.rsp"
        $rspLines = @("/NOLOGO", "/LTCG", "/OUT:$staticOut") + $allObjs + $fstLibs + $blasLibs
        [System.IO.File]::WriteAllLines($rspFile, $rspLines)

        $rspArg = "@$rspFile"
        & lib.exe $rspArg
        Copy-Item -Path $staticOut -Destination $staticOutAlt -Force

        $libSizeMB = [Math]::Round((Get-Item $staticOut).Length / 1MB, 2)
        Write-Host "MSVC static library generated: $staticOut (${libSizeMB} MB)" -ForegroundColor Green
    }

    # --------------------------------------------------------------------------
    # 3.6 Build Dynamic Library (libvosk.dll + libvosk.lib)
    # --------------------------------------------------------------------------
    if ($LinkType -eq "all" -or $LinkType -eq "shared") {
        Write-Host "--> Linking dynamic library (libvosk.dll)..." -ForegroundColor Green
        
        $dllOut = Join-Path $OutDir "libvosk.dll"
        $implibOut = Join-Path $OutDir "libvosk.lib"
        
        $dllRspFile = Join-Path $BuildWorkDir "dll_link.rsp"
        $allObjs = Get-ChildItem -Path $kaldiObjDir -Filter "*.obj" | ForEach-Object { $_.FullName }
        $fstLibs = Get-ChildItem -Path @($fstInstall, $fstBuild) -Recurse -Filter "*.lib" | ForEach-Object { $_.FullName } | Select-Object -Unique
        $blasLibs = Get-ChildItem -Path "$OpenBLASDir\lib" -Filter "*.lib" | ForEach-Object { $_.FullName }

        $dllRspLines = @(
            "/NOLOGO",
            "/DLL",
            "/OPT:REF,ICF",
            "/OUT:$dllOut",
            "/IMPLIB:$implibOut",
            "ws2_32.lib",
            "advapi32.lib",
            "userenv.lib"
        ) + $allObjs + $fstLibs + $blasLibs
        
        [System.IO.File]::WriteAllLines($dllRspFile, $dllRspLines)

        $dllRspArg = "@$dllRspFile"
        & link.exe $dllRspArg

        # Copy runtime DLLs
        Get-ChildItem -Path "$OpenBLASDir\bin" -Filter "*.dll" -ErrorAction SilentlyContinue | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $OutDir -Force
        }

        $dllSizeMB = [Math]::Round((Get-Item $dllOut).Length / 1MB, 2)
        Write-Host "MSVC dynamic library generated: $dllOut (${dllSizeMB} MB)" -ForegroundColor Green
    }

    # Copy header
    Copy-Item -Path "$VoskApiDir\src\vosk_api.h" -Destination $OutDir -Force
    Write-Host "Build output exported to: $OutDir" -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 4. Entrypoint
# ------------------------------------------------------------------------------
if ($OnlyPackage) {
    Write-Host "OnlyPackage mode: skipping build." -ForegroundColor Yellow
    exit 0
}

Prepare-Dependencies

if ($Arch -eq "all") {
    Build-Target-Arch "x86_64"
    Build-Target-Arch "arm64"
    Build-Target-Arch "x86"
} else {
    Build-Target-Arch $Arch
}

Write-Host "==============================================================================" -ForegroundColor Green
Write-Host "Windows MSVC build completed successfully!" -ForegroundColor Green
Write-Host "==============================================================================" -ForegroundColor Green
