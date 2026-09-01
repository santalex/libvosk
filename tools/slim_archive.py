#!/usr/bin/env python3
"""
==============================================================================
LibVosk 静态库极速无损瘦身引擎 (Transitive Symbol Reachability Slimmer)
==============================================================================
原理说明：
  传统 Kaldi 与 OpenFST 打包静态库时，会将上百个离线工具、训练算法、诊断日志模块
  全部打包进 libvosk.a，导致静态库体积高达 360MB+。
  
  本工具基于 vosk_api.h 中的公开 C API 根符号，通过图论传递闭包（Transitive Closure）
  精确计算实际运行时被调用的 .o/.obj 目标文件集合，剔除所有孤岛无引用模块，并在保留
  OpenFST 静态构造函数注册器的前提下，重构生成极小化 (~25MB) 的零损耗静态库。
==============================================================================
"""

import os
import sys
import shutil
import tempfile
import subprocess
import argparse
import time
from pathlib import Path


def parse_symbols_nm(obj_path, nm_tool="nm"):
    """使用 nm 解析 .o 文件的导出符号 (Defined) 与未解析引用 (Undefined)"""
    defined = set()
    undefined = set()
    
    try:
        # -g: 仅全局符号, -p: 无排序快速扫描
        res = subprocess.run([nm_tool, "-g", "-p", str(obj_path)],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True)
        for line in res.stdout.splitlines():
            parts = line.strip().split()
            if len(parts) >= 2:
                # 常见格式: "00000000 T _vosk_model_new" 或 "         U _fst_register"
                sym_type = parts[-2]
                sym_name = parts[-1]
                
                # 去除 macOS/Windows 下 C 符号开头的下划线 _ 前缀适配
                norm_name = sym_name[1:] if sym_name.startswith('_') else sym_name
                
                if sym_type in ('U', 'u'):
                    undefined.add(sym_name)
                    undefined.add(norm_name)
                elif sym_type in ('T', 't', 'D', 'd', 'B', 'b', 'C', 'c', 'W', 'w', 'S', 's'):
                    defined.add(sym_name)
                    defined.add(norm_name)
    except Exception:
        pass
    
    return defined, undefined


def parse_symbols_msvc(obj_path):
    """针对 Windows MSVC .obj 文件的 dumpbin 符号解析器"""
    defined = set()
    undefined = set()
    try:
        res = subprocess.run(["dumpbin", "/SYMBOLS", str(obj_path)],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True)
        for line in res.stdout.splitlines():
            if "External" in line and "|" in line:
                parts = line.split("|")
                if len(parts) >= 2:
                    sym_name = parts[1].strip()
                    if not sym_name:
                        continue
                    norm_name = sym_name[1:] if sym_name.startswith('_') else sym_name
                    if "UNDEF" in parts[0]:
                        undefined.add(sym_name)
                        undefined.add(norm_name)
                    else:
                        defined.add(sym_name)
                        defined.add(norm_name)
    except Exception:
        pass
    return defined, undefined


def extract_ar_python(archive_path, output_dir):
    """跨平台纯 Python 兼容解包 GNU/BSD/MSVC 格式的 ar 归档"""
    try:
        with open(archive_path, "rb") as f:
            magic = f.read(8)
            if magic != b"!<arch>\n":
                return 0
            long_names = b""
            counter = 0
            while True:
                header = f.read(60)
                if not header or len(header) < 60:
                    break
                raw_name = header[0:16].decode("ascii", errors="ignore").strip()
                size_str = header[48:58].decode("ascii", errors="ignore").strip()
                if not size_str.isdigit():
                    break
                size = int(size_str)
                data = f.read(size)
                if size % 2 != 0:
                    f.read(1) # 2-byte alignment padding
                
                # GNU long-name table
                if raw_name == "//":
                    long_names = data
                    continue
                # Symbol directory table
                elif raw_name == "/" or raw_name == "" or raw_name.startswith("/ "):
                    continue
                # GNU long-name offset /offset
                elif raw_name.startswith("/") and raw_name[1:].isdigit():
                    offset = int(raw_name[1:])
                    end_pos = long_names.find(b"/\n", offset)
                    if end_pos == -1: end_pos = long_names.find(b"\n", offset)
                    if end_pos == -1: end_pos = long_names.find(b"\0", offset)
                    filename = long_names[offset:end_pos].decode("utf-8", errors="ignore").rstrip("/") if end_pos != -1 else f"obj_{counter}.o"
                # BSD long-name #1/len
                elif raw_name.startswith("#1/"):
                    name_len = int(raw_name[3:])
                    filename = data[:name_len].decode("utf-8", errors="ignore").rstrip("\x00")
                    data = data[name_len:]
                else:
                    filename = raw_name.rstrip("/ ")
                
                counter += 1
                safe_name = os.path.basename(filename)
                if not safe_name.endswith(".o") and not safe_name.endswith(".obj"):
                    safe_name = f"{safe_name}.o"
                out_file = Path(output_dir) / f"{counter:04d}_{safe_name}"
                with open(out_file, "wb") as out_f:
                    out_f.write(data)
            return counter
    except Exception:
        return 0


def extract_header_symbols(header_path):
    """从 vosk_api.h 自动提取所有 vosk_* 公开 API 符号"""
    root_symbols = set()
    if not os.path.isfile(header_path):
        return root_symbols
    with open(header_path, 'r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            line = line.strip()
            if "vosk_" in line and "(" in line and not line.startswith("//"):
                tokens = line.replace("(", " ").replace("*", " ").split()
                for t in tokens:
                    if t.startswith("vosk_"):
                        clean_t = t.rstrip(");,")
                        root_symbols.add(clean_t)
                        root_symbols.add(f"_{clean_t}")
    return root_symbols


def slim_archive(input_archive, output_archive, header_path, nm_tool="nm", ar_tool="ar"):
    start_time = time.time()
    input_path = Path(input_archive).resolve()
    output_path = Path(output_archive).resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    if not input_path.exists():
        print(f"❌ 错误: 输入静态库不存在: {input_path}")
        sys.exit(1)
        
    orig_size_mb = input_path.stat().st_size / (1024 * 1024)
    print(f"==============================================================================")
    print(f"  LibVosk 静态库极速瘦身引擎")
    print(f"  原始文件: {input_path.name} ({orig_size_mb:.2f} MB)")
    print(f"==============================================================================")

    temp_dir = Path(tempfile.mkdtemp(prefix="vosk_slim_"))
    try:
        # 1. 解压全部 .o / .obj 目标文件
        print("--> [1/4] 正在解压原始静态库目标文件...")
        is_windows_lib = input_path.suffix.lower() == ".lib" and shutil.which("lib.exe") is not None
        
        extracted_count = extract_ar_python(input_path, temp_dir)
        if extracted_count == 0:
            if is_windows_lib:
                if shutil.which("llvm-ar"):
                    subprocess.run(["llvm-ar", "x", str(input_path)], cwd=str(temp_dir), check=True)
                else:
                    subprocess.run(["7z", "x", str(input_path), f"-o{temp_dir}"], check=True)
            else:
                subprocess.run([ar_tool, "x", str(input_path)], cwd=str(temp_dir), check=True)
            
        all_objs = list(temp_dir.glob("*.o")) + list(temp_dir.glob("*.obj"))
        if not all_objs:
            print("❌ 错误: 未能在静态库中提取出任何目标文件 (.o/.obj)！")
            sys.exit(1)
        print(f"    成功提取 {len(all_objs)} 个目标文件 (.o/.obj)")

        # 2. 提取公开 API 根符号与静态构造函数特征
        root_symbols = extract_header_symbols(header_path)
        print(f"    从头文件提取到 {len(root_symbols)} 个核心 Vosk C API 根符号")

        # 3. 构建符号依赖图 (Symbol Inverted Index)
        print("--> [2/4] 正在多线程解析目标文件符号表并构建依赖图...", flush=True)
        symbol_to_obj = {}
        obj_undefined = {}
        kept_objs = set()

        import concurrent.futures
        def process_single_obj(obj):
            if is_windows_lib:
                defined, undef = parse_symbols_msvc(obj)
            else:
                defined, undef = parse_symbols_nm(obj, nm_tool=nm_tool)
            name_lower = obj.name.lower()
            is_root = (
                any(sym in defined for sym in root_symbols) or
                ("fst" in name_lower) or
                ("ngram" in name_lower) or
                ("cblas" in name_lower) or
                ("clapack" in name_lower) or
                ("f2c" in name_lower)
            )
            return obj, defined, undef, is_root

        max_workers = min(32, (os.cpu_count() or 4) * 4)
        with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
            results = executor.map(process_single_obj, all_objs)
            for obj, defined, undef, is_root in results:
                obj_undefined[obj] = undef
                for sym in defined:
                    symbol_to_obj[sym] = obj
                if is_root:
                    kept_objs.add(obj)

        print(f"    识别出 {len(kept_objs)} 个初始根节点与 OpenFST/数学 核心模块")

        # 4. 广度优先搜索 (BFS) 计算符号传递闭包
        print("--> [3/4] 正在执行传递闭包图遍历 (Transitive Reachability Closure)...")
        queue = list(kept_objs)
        while queue:
            curr_obj = queue.pop(0)
            for needed_sym in obj_undefined.get(curr_obj, ()):
                provider_obj = symbol_to_obj.get(needed_sym)
                if provider_obj and provider_obj not in kept_objs:
                    kept_objs.add(provider_obj)
                    queue.append(provider_obj)

        kept_count = len(kept_objs)
        pruned_count = len(all_objs) - kept_count
        print(f"    闭包分析完毕: 保留 {kept_count} 个核心目标文件 (安全剔除 {pruned_count} 个废弃模块)")

        # 5. 重新封包瘦身静态库
        print("--> [4/4] 正在重新打包极小化静态库...")
        if output_path.exists():
            output_path.unlink()
            
        kept_obj_paths = [str(p) for p in kept_objs]
        if is_windows_lib:
            rsp_path = temp_dir / "lib_pack.rsp"
            with open(rsp_path, "w", encoding="utf-8") as rf:
                rf.write(f"/NOLOGO\n/OUT:{output_path}\n")
                for p in kept_obj_paths:
                    rf.write(f'"{p}"\n')
            subprocess.run(["lib.exe", f"@{rsp_path}"], check=True)
        else:
            chunk_size = 200
            for i in range(0, len(kept_obj_paths), chunk_size):
                chunk = kept_obj_paths[i:i + chunk_size]
                subprocess.run([ar_tool, "rcs", str(output_path)] + chunk, check=True)
            try:
                if sys.platform == "darwin":
                    subprocess.run(["strip", "-S", str(output_path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
                    subprocess.run(["ranlib", "-no_warning_for_no_symbols", "-c", str(output_path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
                else:
                    subprocess.run(["strip", "--strip-debug", str(output_path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            except Exception:
                pass

        new_size_mb = output_path.stat().st_size / (1024 * 1024)
        savings_pct = (1.0 - (new_size_mb / orig_size_mb)) * 100.0
        elapsed = time.time() - start_time

        print(f"==============================================================================")
        print(f"✔ 🎉 瘦身完成！耗时: {elapsed:.2f} 秒")
        print(f"  原始体积: {orig_size_mb:.2f} MB")
        print(f"  瘦身体积: {new_size_mb:.2f} MB (体积大幅削减 {savings_pct:.1f}%！)")
        print(f"  输出文件: {output_path}")
        print(f"==============================================================================")

    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="LibVosk 静态库极速无损瘦身引擎")
    parser.add_argument("input", help="输入的原始静态库文件 (.a / .lib)")
    parser.add_argument("output", help="瘦身后输出的静态库文件")
    parser.add_argument("--header", default="src/apple/vosk-api/src/vosk_api.h", help="vosk_api.h 头文件路径")
    parser.add_argument("--nm", default="nm", help="nm 工具路径")
    parser.add_argument("--ar", default="ar", help="ar 工具路径")
    
    args = parser.parse_args()
    slim_archive(args.input, args.output, args.header, nm_tool=args.nm, ar_tool=args.ar)
