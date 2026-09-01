# ==============================================================================
# build.ps1 - Vosk API Windows (MSVC Native) 工业级自动编译与瘦身打包主引擎
#
# 支持参数:
#   -Arch <x86_64|arm64|x86|all>       (默认: x86_64)
#   -LinkType <all|static|shared>      (默认: all)
#   -VoskTag <v0.3.50|master|...>      (默认: v0.3.50)
#   -OnlyPackage                       直接对现有 dist/ 目录打包
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
Write-Host "  Vosk API Windows (MSVC) 原生构建引擎" -ForegroundColor Cyan
Write-Host "  目标架构 (Arch)   : $Arch" -ForegroundColor Cyan
Write-Host "  链接形式 (Link)   : $LinkType" -ForegroundColor Cyan
Write-Host "  Vosk 版本 (Tag)   : $VoskTag" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan

# ------------------------------------------------------------------------------
# 1. 激活 MSVC 编译环境 (vcvarsall.bat)
# ------------------------------------------------------------------------------
function Initialize-MSVC-Environment([string]$targetArch) {
    Write-Host "--> 正在初始化 Visual Studio 2022 MSVC 编译环境 ($targetArch)..." -ForegroundColor Yellow

    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) {
        $vswhere = "vswhere.exe"
    }

    $vsInstallPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vsInstallPath -or -not (Test-Path $vsInstallPath)) {
        # 兼容 GitHub Actions 默认路径
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
        throw "❌ 未找到 Visual Studio MSVC 安装路径！请确保已安装 C++ 构建工具。"
    }

    $vcvars = Join-Path $vsInstallPath "VC\Auxiliary\Build\vcvarsall.bat"
    if (-not (Test-Path $vcvars)) {
        throw "❌ 未找到 vcvarsall.bat: $vcvars"
    }

    $vcArch = switch ($targetArch) {
        "x86_64" { "x64" }
        "x86"    { "x86" }
        "arm64"  { "x64_arm64" }
        default  { "x64" }
    }

    # 导出 MSVC 环境变量到当前 PowerShell 会话
    $tempFile = [System.IO.Path]::GetTempFileName()
    cmd.exe /c "`"$vcvars`" $vcArch && set > `"$tempFile`""
    Get-Content $tempFile | ForEach-Object {
        if ($_ -match "^(.*?)=(.*)$") {
            Set-Item -Force -Path "env:$($matches[1])" -Value "$($matches[2])"
        }
    }
    Remove-Item -Force $tempFile

    Write-Host "✔ MSVC 环境已成功加载 (CL: $(cl.exe 2>&1 | Select-Object -First 1))" -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 2. 源码与依赖准备
# ------------------------------------------------------------------------------
function Prepare-Dependencies {
    $DepsDir = Join-Path $ScriptDir "deps"
    if (-not (Test-Path $DepsDir)) {
        New-Item -ItemType Directory -Path $DepsDir -Force | Out-Null
    }

    Set-Location $DepsDir

    # A. OpenFST (MSVC 移植版)
    if (-not (Test-Path "openfst")) {
        Write-Host "--> 正在克隆 OpenFST 源码..." -ForegroundColor Yellow
        git clone --depth=1 https://github.com/alphacep/openfst openfst
    }

    # B. Kaldi (Vosk 适配版)
    if (-not (Test-Path "kaldi")) {
        Write-Host "--> 正在克隆 Kaldi 源码..." -ForegroundColor Yellow
        git clone -b vosk-android --single-branch --depth=1 https://github.com/alphacep/kaldi kaldi
    }

    # C. Vosk API 源码
    if (-not (Test-Path "vosk-api")) {
        Write-Host "--> 正在克隆 Vosk API 源码 (Tag: $VoskTag)..." -ForegroundColor Yellow
        $tagParam = if ($VoskTag -and $VoskTag -ne "master") { "-b $VoskTag" } else { "" }
        git clone $tagParam --single-branch --depth=1 https://github.com/alphacep/vosk-api vosk-api
    }

    Set-Location $ScriptDir
}

# ------------------------------------------------------------------------------
# 3. 编译单架构目标 (x86_64 / arm64 / x86)
# ------------------------------------------------------------------------------
function Build-Target-Arch([string]$targetArch) {
    Write-Host "==============================================================================" -ForegroundColor Cyan
    Write-Host "  [MSVC 构建] 开始编译 Windows [$targetArch] ..." -ForegroundColor Cyan
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
    # 3.1 准备 OpenBLAS (MSVC 兼容版)
    # --------------------------------------------------------------------------
    if (-not (Test-Path "$OpenBLASDir\lib\openblas.lib")) {
        Write-Host "--> 正在下载/配置 Windows MSVC OpenBLAS ($targetArch)..." -ForegroundColor Yellow
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
    # 3.2 使用 CMake + MSVC 编译 OpenFST
    # --------------------------------------------------------------------------
    Write-Host "--> 正在通过 CMake 编译 OpenFST 静态库..." -ForegroundColor Yellow
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
    # 3.3 编译 Kaldi 核心推理模块 (仅核心，死代码剔除)
    # --------------------------------------------------------------------------
    Write-Host "--> 正在编译 Kaldi 核心推理模块 (死代码极致瘦身)..." -ForegroundColor Yellow
    $kaldiObjDir = Join-Path $BuildWorkDir "kaldi_objs"
    New-Item -ItemType Directory -Path $kaldiObjDir -Force | Out-Null

    $kaldiInclude = "$KaldiDir\src"
    $fstInclude = "$DepsDir\openfst\src\include"
    $blasInclude = "$OpenBLASDir\include"

    $includes = @(
        "/I`"$kaldiInclude`"",
        "/I`"$fstInclude`"",
        "/I`"$blasInclude`"",
        "/I`"$VoskApiDir\src`""
    ) -join " "

    # 核心推理模块清单 (剔除所有训练、CUDA和离线未用模块)
    $modules = @("base", "matrix", "util", "feat", "tree", "gmm", "lat", "hmm", "decoder", "nnet3", "online2", "rnnlm")
    $ccFiles = @()
    foreach ($m in $modules) {
        $mPath = Join-Path "$KaldiDir\src" $m
        if (Test-Path $mPath) {
            Get-ChildItem -Path $mPath -Filter "*.cc" | ForEach-Object {
                # 排除测试用例与训练主程序
                if (-not ($_.Name -like "*-test.cc") -and -not ($_.Name -like "*-bin.cc")) {
                    $ccFiles += $_.FullName
                }
            }
        }
    }

    Write-Host "--> 正在使用 MSVC cl.exe 编译 $($ccFiles.Count) 个 Kaldi 核心源文件..." -ForegroundColor Gray
    
    # 优化编译选项: /O2(极速性能), /Gy(函数级链接), /Gw(数据级链接), /GL(全程序优化), /MD(动态运行时)
    $clFlags = "/nologo /c /O2 /Gy /Gw /GL /EHsc /MD /D_CRT_SECURE_NO_WARNINGS /DHAVE_OPENBLAS=1 /DFST_NO_DYNAMIC_LINKING=1 /D_USE_MATH_DEFINES"

    # 分批次编译以防命令行过长
    $batchSize = 40
    for ($i = 0; $i -lt $ccFiles.Count; $i += $batchSize) {
        $batch = $ccFiles[$i..[Math]::Min($i + $batchSize - 1, $ccFiles.Count - 1)]
        $filesStr = ($batch | ForEach-Object { "`"$_`"" }) -join " "
        cmd.exe /c "cd /d `"$kaldiObjDir`" && cl.exe $clFlags $includes $filesStr"
    }

    # --------------------------------------------------------------------------
    # 3.4 编译 Vosk API
    # --------------------------------------------------------------------------
    Write-Host "--> 正在编译 Vosk API (vosk_api.cc)..." -ForegroundColor Yellow
    cmd.exe /c "cd /d `"$kaldiObjDir`" && cl.exe $clFlags $includes `"$VoskApiDir\src\vosk_api.cc`""

    # --------------------------------------------------------------------------
    # 3.5 打包纯净版静态库 (libvosk.lib)
    # --------------------------------------------------------------------------
    if ($LinkType -eq "all" -or $LinkType -eq "static") {
        Write-Host "--> 正在使用 MSVC lib.exe 打包瘦身纯静态库 (libvosk.lib)..." -ForegroundColor Green
        
        $allObjs = Get-ChildItem -Path $kaldiObjDir -Filter "*.obj" | ForEach-Object { "`"$($_.FullName)`"" }
        $fstLibs = Get-ChildItem -Path $fstBuild -Recurse -Filter "*.lib" | ForEach-Object { "`"$($_.FullName)`"" }
        $blasLibs = Get-ChildItem -Path "$OpenBLASDir\lib" -Filter "*.lib" | ForEach-Object { "`"$($_.FullName)`"" }

        $staticOut = Join-Path $OutDir "libvosk.lib"
        $staticOutAlt = Join-Path $OutDir "libvosk_static.lib"
        
        # 将参数写入响应文件，防止命令行长度溢出
        $rspFile = Join-Path $BuildWorkDir "static_lib.rsp"
        $rspContent = @("/NOLOGO", "/LTCG", "/OUT:`"$staticOut`"") + $allObjs + $fstLibs + $blasLibs
        $rspContent | Set-Content -Path $rspFile -Encoding ASCII

        cmd.exe /c "lib.exe @`"$rspFile`""
        Copy-Item -Path $staticOut -Destination $staticOutAlt -Force

        $libSizeMB = [Math]::Round((Get-Item $staticOut).Length / 1MB, 2)
        Write-Host "✔ 🎉 MSVC 纯静态库打包成功: $staticOut (${libSizeMB} MB)" -ForegroundColor Green
    }

    # --------------------------------------------------------------------------
    # 3.6 编译动态库 (libvosk.dll + 导入库 libvosk.lib)
    # --------------------------------------------------------------------------
    if ($LinkType -eq "all" -or $LinkType -eq "shared") {
        Write-Host "--> 正在使用 MSVC link.exe 链接动态库 (libvosk.dll)..." -ForegroundColor Green
        
        $dllOut = Join-Path $OutDir "libvosk.dll"
        $implibOut = Join-Path $OutDir "libvosk.lib"
        
        $dllRspFile = Join-Path $BuildWorkDir "dll_link.rsp"
        $allObjs = Get-ChildItem -Path $kaldiObjDir -Filter "*.obj" | ForEach-Object { "`"$($_.FullName)`"" }
        $fstLibs = Get-ChildItem -Path $fstBuild -Recurse -Filter "*.lib" | ForEach-Object { "`"$($_.FullName)`"" }
        $blasLibs = Get-ChildItem -Path "$OpenBLASDir\lib" -Filter "*.lib" | ForEach-Object { "`"$($_.FullName)`"" }

        $dllRspContent = @(
            "/NOLOGO",
            "/DLL",
            "/OPT:REF,ICF",
            "/OUT:`"$dllOut`"",
            "/IMPLIB:`"$implibOut`"",
            "ws2_32.lib",
            "advapi32.lib",
            "userenv.lib"
        ) + $allObjs + $fstLibs + $blasLibs
        
        $dllRspContent | Set-Content -Path $dllRspFile -Encoding ASCII

        cmd.exe /c "link.exe @`"$dllRspFile`""

        # 拷贝 OpenBLAS DLL 供动态库运行时加载
        Get-ChildItem -Path "$OpenBLASDir\bin" -Filter "*.dll" -ErrorAction SilentlyContinue | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $OutDir -Force
        }

        $dllSizeMB = [Math]::Round((Get-Item $dllOut).Length / 1MB, 2)
        Write-Host "✔ 🎉 MSVC 动态链接库生成成功: $dllOut (${dllSizeMB} MB)" -ForegroundColor Green
    }

    # 拷贝 C API 头文件
    Copy-Item -Path "$VoskApiDir\src\vosk_api.h" -Destination $OutDir -Force
    Write-Host "✔ 导出完成: $OutDir" -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 4. 执行入口
# ------------------------------------------------------------------------------
if ($OnlyPackage) {
    Write-Host "💡 仅打包模式已跳过编译。" -ForegroundColor Yellow
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
Write-Host "✔ 🎉 全部 Windows MSVC 目标构建完成！" -ForegroundColor Green
Write-Host "==============================================================================" -ForegroundColor Green
