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

    Set-Location $DepsDir

    # A. OpenFST (MSVC Port)
    if (-not (Test-Path "openfst")) {
        Write-Host "--> Cloning OpenFST repository..." -ForegroundColor Yellow
        git clone --depth=1 https://github.com/alphacep/openfst openfst
    }

    # B. Kaldi (Vosk Fork)
    if (-not (Test-Path "kaldi")) {
        Write-Host "--> Cloning Kaldi repository..." -ForegroundColor Yellow
        git clone -b vosk-android --single-branch --depth=1 https://github.com/alphacep/kaldi kaldi
    }

    # C. Vosk API
    if (-not (Test-Path "vosk-api")) {
        Write-Host "--> Cloning Vosk API repository (Tag: $VoskTag)..." -ForegroundColor Yellow
        $tagParam = if ($VoskTag -and $VoskTag -ne "master") { "-b", "$VoskTag" } else { @() }
        git clone @tagParam --single-branch --depth=1 https://github.com/alphacep/vosk-api vosk-api
    }

    Set-Location $ScriptDir
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
    New-Item -ItemType Directory -Path $fstBuild -Force | Out-Null
    
    $cmakeArch = switch ($targetArch) {
        "x86_64" { "x64" }
        "x86"    { "Win32" }
        "arm64"  { "ARM64" }
        default  { "x64" }
    }

    cmake -B $fstBuild -S "$DepsDir\openfst" -A $cmakeArch `
          -DFST_NO_DYNAMIC_LINKING=ON `
          -DENABLE_SHARED=OFF `
          -DENABLE_STATIC=ON `
          -DENABLE_LOOKAHEAD_FSTS=ON `
          -DENABLE_NGRAM_FSTS=ON `
          -DCMAKE_BUILD_TYPE=Release `
          -DCMAKE_CXX_FLAGS="/O2 /Gy /Gw /EHsc /MD /D_CRT_SECURE_NO_WARNINGS"

    cmake --build $fstBuild --config Release --parallel

    # --------------------------------------------------------------------------
    # 3.3 Compile Kaldi Core Inference Modules (Dead-Code Pruning)
    # --------------------------------------------------------------------------
    Write-Host "--> Compiling Kaldi core inference modules..." -ForegroundColor Yellow
    $kaldiObjDir = Join-Path $BuildWorkDir "kaldi_objs"
    New-Item -ItemType Directory -Path $kaldiObjDir -Force | Out-Null

    $kaldiInclude = "$KaldiDir\src"
    $fstInclude = "$DepsDir\openfst\src\include"
    $blasInclude = "$OpenBLASDir\include"
    $voskInclude = "$VoskApiDir\src"

    # Core inference modules only (no CUDA, no training, no online bin)
    $modules = @("base", "matrix", "util", "feat", "tree", "gmm", "lat", "hmm", "decoder", "nnet3", "online2", "rnnlm")
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
        "/DFST_NO_DYNAMIC_LINKING=1",
        "/D_USE_MATH_DEFINES",
        "/I$kaldiInclude",
        "/I$fstInclude",
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
        $fstLibs = Get-ChildItem -Path $fstBuild -Recurse -Filter "*.lib" | ForEach-Object { $_.FullName }
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
        $fstLibs = Get-ChildItem -Path $fstBuild -Recurse -Filter "*.lib" | ForEach-Object { $_.FullName }
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
