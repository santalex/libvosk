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

    # A. OpenFST (Alphacep OpenFST Repository)
    if (-not (Test-Path (Join-Path $openfstDir "src\include\fst\fst.h"))) {
        Write-Host "--> Cloning OpenFST repository (alphacep/openfst)..." -ForegroundColor Yellow
        if (Test-Path $openfstDir) {
            Remove-Item -Recurse -Force $openfstDir -ErrorAction SilentlyContinue
        }
        git clone --depth=1 https://github.com/alphacep/openfst $openfstDir
    }

    # Patch OpenFST compat.h for MSVC C++17 alias template deprecation compatibility
    $fstCompatH = Join-Path "$openfstDir\src\include\fst" "compat.h"
    if (Test-Path $fstCompatH) {
        $fstCompatContent = Get-Content -Raw $fstCompatH
        $fstCompatContent = $fstCompatContent -replace '__declspec\(deprecated\(message\)\)', '[[deprecated(message)]]'
        Set-Content -Path $fstCompatH -Value $fstCompatContent -Encoding UTF8
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
    $OutDir = Join-Path $RootDir "dist\windows-msvc\$targetArch"
    New-Item -ItemType Directory -Path $BuildWorkDir -Force | Out-Null
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

    $DepsDir = Join-Path $ScriptDir "deps"
    $OpenBLASDir = Join-Path $BuildWorkDir "openblas"
    $OpenFSTDir = Join-Path $DepsDir "openfst"
    $KaldiDir = Join-Path $DepsDir "kaldi"
    $VoskApiDir = Join-Path $DepsDir "vosk-api"

    # --------------------------------------------------------------------------
    # 3.1 Setup OpenBLAS MSVC binaries
    # --------------------------------------------------------------------------
    $blasLib = Join-Path $OpenBLASDir "lib\libopenblas.lib"
    if (-not (Test-Path $blasLib)) {
        Write-Host "--> Downloading OpenBLAS binaries for $targetArch..." -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $OpenBLASDir -Force | Out-Null
        
        $blasZip = Join-Path $BuildWorkDir "openblas.zip"
        $blasUrl = "https://github.com/OpenMathLib/OpenBLAS/releases/download/v0.3.28/openblas-0.3.28-x64.zip"
        if ($targetArch -eq "x86") {
            $blasUrl = "https://github.com/OpenMathLib/OpenBLAS/releases/download/v0.3.28/openblas-0.3.28-x86.zip"
        }
        
        Invoke-WebRequest -Uri $blasUrl -OutFile $blasZip -UseBasicParsing
        Expand-Archive -Path $blasZip -DestinationPath $OpenBLASDir -Force
        Remove-Item -Force $blasZip

        # Disable Fortran string length extensions so Kaldi standard C LAPACK calls match cleanly
        $lapackHeader = Join-Path $OpenBLASDir "include\lapack.h"
        if (Test-Path $lapackHeader) {
            $content = Get-Content $lapackHeader -Raw
            $content = $content.Replace("#define LAPACK_FORTRAN_STRLEN_END", "/* #define LAPACK_FORTRAN_STRLEN_END */")
            Set-Content -Path $lapackHeader -Value $content -NoNewline
        }

        # Generate MSVC import library (.lib) from DLL exports
        $libDir = Join-Path $OpenBLASDir "lib"
        New-Item -ItemType Directory -Path $libDir -Force | Out-Null
        $dllFile = Join-Path $OpenBLASDir "bin\libopenblas.dll"
        if (-not (Test-Path $dllFile)) {
            $dllFile = (Get-ChildItem -Path $OpenBLASDir -Recurse -Filter "*.dll" | Select-Object -First 1).FullName
        }
        if (Test-Path $dllFile) {
            Write-Host "--> Generating MSVC import library from $dllFile..." -ForegroundColor Yellow
            $exportsText = & dumpbin.exe /exports $dllFile
            $defLines = @("LIBRARY $([System.IO.Path]::GetFileName($dllFile))", "EXPORTS")
            foreach ($line in $exportsText) {
                if ($line -match '^\s+\d+\s+[0-9A-Fa-f]+\s+[0-9A-Fa-f]+\s+([a-zA-Z0-9_]+)') {
                    $defLines += "    $($Matches[1])"
                }
            }
            $defPath = Join-Path $libDir "libopenblas.def"
            [System.IO.File]::WriteAllLines($defPath, $defLines)
            $machineArg = if ($targetArch -eq "x86_64") { "/MACHINE:X64" } elseif ($targetArch -eq "arm64") { "/MACHINE:ARM64" } else { "/MACHINE:X86" }
            & lib.exe "/DEF:$defPath" "/OUT:$blasLib" $machineArg
            Write-Host "--> Successfully created MSVC import library: $blasLib ($($defLines.Count - 2) exported symbols)" -ForegroundColor Green
        }
    }

    # --------------------------------------------------------------------------
    # 3.2 Build OpenFST with MSVC cl.exe
    # --------------------------------------------------------------------------
    Write-Host "--> Compiling OpenFST with MSVC cl.exe..." -ForegroundColor Yellow
    $fstObjDir = Join-Path $BuildWorkDir "fst_objs"
    New-Item -ItemType Directory -Path $fstObjDir -Force | Out-Null

    $fstCcFiles = @()
    if (Test-Path "$OpenFSTDir\src\lib") {
        Get-ChildItem -Path "$OpenFSTDir\src\lib" -Filter "*.cc" | ForEach-Object { $fstCcFiles += $_.FullName }
    }
    if (Test-Path "$OpenFSTDir\src\extensions\ngram") {
        Get-ChildItem -Path "$OpenFSTDir\src\extensions\ngram" -Filter "*.cc" | ForEach-Object { $fstCcFiles += $_.FullName }
    }

    $compatHeader = Join-Path $ScriptDir "msvc_compat.h"
    $fstInclude = "$OpenFSTDir\src\include"

    $fstClArgs = @(
        "/nologo",
        "/c",
        "/std:c++17",
        "/O2",
        "/Gy",
        "/Gw",
        "/EHsc",
        "/MD",
        "/DNOMINMAX",
        "/DWIN32_LEAN_AND_MEAN",
        "/D_CRT_SECURE_NO_WARNINGS",
        "/DFST_NO_DYNAMIC_LINKING=1",
        "/D_USE_MATH_DEFINES",
        "/Dssize_t=intptr_t",
        "/FI$compatHeader",
        "/I$fstInclude"
    )

    Push-Location $fstObjDir
    try {
        & cl.exe $fstClArgs $fstCcFiles
        if ($LASTEXITCODE -ne 0) {
            Write-Error "OpenFST compilation failed with exit code $LASTEXITCODE"
            exit 1
        }
    } finally {
        Pop-Location
    }

    $fstLibOut = Join-Path $fstObjDir "fst.lib"
    $fstObjs = Get-ChildItem -Path $fstObjDir -Filter "*.obj" | ForEach-Object { $_.FullName }
    & lib.exe /NOLOGO "/OUT:$fstLibOut" $fstObjs
    Write-Host "OpenFST static library generated: $fstLibOut" -ForegroundColor Green

    # --------------------------------------------------------------------------
    # 3.3 Compile Kaldi Modules with MSVC cl.exe
    # --------------------------------------------------------------------------
    Write-Host "--> Compiling Kaldi Modules with MSVC cl.exe..." -ForegroundColor Yellow
    $kaldiObjDir = Join-Path $BuildWorkDir "kaldi_objs"
    New-Item -ItemType Directory -Path $kaldiObjDir -Force | Out-Null

    # Kaldi modules required by Vosk API
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
        "chain",
        "online2",
        "rnnlm",
        "ivector"
    )

    $clArgs = @(
        "/nologo",
        "/c",
        "/std:c++17",
        "/O2",
        "/Gy",
        "/Gw",
        "/EHsc",
        "/MD",
        "/DNOMINMAX",
        "/DWIN32_LEAN_AND_MEAN",
        "/D_CRT_SECURE_NO_WARNINGS",
        "/DHAVE_OPENBLAS=1",
        "/DHAVE_CUDA=0",
        "/DKALDI_DOUBLEPRECISION=0",
        "/DFST_NO_DYNAMIC_LINKING=1",
        "/D_USE_MATH_DEFINES",
        "/Dssize_t=intptr_t",
        "/Dlapack_complex_float=std::complex<float>",
        "/Dlapack_complex_double=std::complex<double>",
        "/DLAPACK_COMPLEX_CUSTOM=1",
        "/D_SILENCE_ALL_CXX17_DEPRECATION_WARNINGS",
        "/FI$compatHeader",
        "/I$KaldiDir\src",
        "/I$fstInclude",
        "/I$OpenBLASDir\include",
        "/I$VoskApiDir\src"
    )

    # Compile each module in its own subfolder to prevent object filename collisions
    foreach ($m in $modules) {
        $mPath = Join-Path "$KaldiDir\src" $m
        if (Test-Path $mPath) {
            $mCcFiles = @()
            Get-ChildItem -Path $mPath -Filter "*.cc" | ForEach-Object {
                if (-not ($_.Name -like "*-test.cc") -and -not ($_.Name -like "*-bin.cc") -and -not ($_.Name -like "online-nnet2-decoding*")) {
                    $mCcFiles += $_.FullName
                }
            }
            if ($mCcFiles.Count -gt 0) {
                $mObjDir = Join-Path $kaldiObjDir $m
                New-Item -ItemType Directory -Path $mObjDir -Force | Out-Null
                Write-Host "--> Compiling Kaldi module '$m' ($($mCcFiles.Count) files)..." -ForegroundColor Gray
                
                $batchSize = 30
                for ($i = 0; $i -lt $mCcFiles.Count; $i += $batchSize) {
                    $batch = $mCcFiles[$i..[Math]::Min($i + $batchSize - 1, $mCcFiles.Count - 1)]
                    $currentClArgs = $clArgs + $batch
                    Push-Location $mObjDir
                    try {
                        & cl.exe $currentClArgs
                        if ($LASTEXITCODE -ne 0) {
                            Write-Error "Kaldi module $m batch compilation failed with exit code $LASTEXITCODE"
                            exit 1
                        }
                    } finally {
                        Pop-Location
                    }
                }
            }
        }
    }

    # --------------------------------------------------------------------------
    # 3.4 Compile Vosk API (CPU Standard Sources)
    # --------------------------------------------------------------------------
    Write-Host "--> Compiling Vosk API CPU sources..." -ForegroundColor Yellow
    $voskSources = @(
        "vosk_api.cc",
        "recognizer.cc",
        "model.cc",
        "spk_model.cc",
        "language_model.cc"
    )
    $voskCcFiles = @()
    foreach ($src in $voskSources) {
        $fullPath = Join-Path "$VoskApiDir\src" $src
        if (Test-Path $fullPath) {
            $voskCcFiles += $fullPath
        }
    }
    if (Test-Path "$VoskApiDir\src\postprocessor.cc") {
        $voskCcFiles += "$VoskApiDir\src\postprocessor.cc"
    }

    $voskObjDir = Join-Path $kaldiObjDir "vosk"
    New-Item -ItemType Directory -Path $voskObjDir -Force | Out-Null
    Push-Location $voskObjDir
    try {
        & cl.exe $clArgs $voskCcFiles
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Vosk API compilation failed with exit code $LASTEXITCODE"
            exit 1
        }
    } finally {
        Pop-Location
    }

    # --------------------------------------------------------------------------
    # 3.5 Build Static Library (libvosk.lib)
    # --------------------------------------------------------------------------
    $allObjs = Get-ChildItem -Path $kaldiObjDir -Recurse -Filter "*.obj" | ForEach-Object { $_.FullName }
    $fstLibs = @($fstLibOut)
    $blasLibs = Get-ChildItem -Path "$OpenBLASDir\lib" -Filter "*.lib" | ForEach-Object { $_.FullName }

    if ($LinkType -eq "all" -or $LinkType -eq "static") {
        Write-Host "--> Packaging static library (libvosk.lib)..." -ForegroundColor Green
        
        $staticOut = Join-Path $OutDir "libvosk.lib"
        $staticOutAlt = Join-Path $OutDir "libvosk_static.lib"
        
        $rspFile = Join-Path $BuildWorkDir "static_lib.rsp"
        $rspLines = @("/NOLOGO", "/OUT:$staticOut") + $allObjs + $fstLibs + $blasLibs
        [System.IO.File]::WriteAllLines($rspFile, $rspLines)

        $rspArg = "@$rspFile"
        & lib.exe $rspArg
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Static library creation failed with exit code $LASTEXITCODE"
            exit 1
        }
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
        $implibOut = if ($LinkType -eq "all") { Join-Path $OutDir "libvosk_dll.lib" } else { Join-Path $OutDir "libvosk.lib" }
        
        $dllRspFile = Join-Path $BuildWorkDir "dll_link.rsp"
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
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Dynamic library link failed with exit code $LASTEXITCODE"
            exit 1
        }

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
