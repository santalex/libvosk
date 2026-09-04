#!/usr/bin/env python3
"""
==============================================================================
LibVosk Static Library Slimming Engine (Transitive Symbol Reachability Slimmer)
==============================================================================
Overview:
  When Kaldi and OpenFST are bundled into a static archive, hundreds of offline
  binaries, training algorithms, and diagnostic modules get included, swelling
  libvosk.a to over 360MB.
  
  This tool analyzes root public C API symbols from vosk_api.h and computes
  the transitive closure of required object files (.o / .obj). It eliminates
  unreferenced modules while preserving OpenFST static initializers and factory
  registrations, yielding a compact (~20MB) zero-loss static library.
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


def _record_symbol(bucket, sym_name):
    bucket.add(sym_name)
    if sym_name.startswith("_"):
        bucket.add(sym_name[1:])


def _classify_nm_symbol(sym_type, has_value):
    """Classify GNU/POSIX nm symbol character -> defined / undefined."""
    if not sym_type:
        return None
    kind = sym_type[0]
    if kind == "U":
        return "undefined"
    if kind in ("v", "w") and not has_value:
        return "undefined"
    if kind in "TtDdBbCcWwSsRrVvGgAau":
        return "defined"
    return None


def parse_symbols_nm(obj_path, nm_tool="nm"):
    """Parse defined and undefined symbols from .o file using nm."""
    defined = set()
    undefined = set()

    try:
        res = subprocess.run(
            [nm_tool, "-g", "-P", "-p", str(obj_path)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if res.returncode != 0:
            res = subprocess.run(
                [nm_tool, "-g", "-p", str(obj_path)],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True)
        for line in res.stdout.splitlines():
            parts = line.strip().split()
            if len(parts) < 2:
                continue

            if len(parts[1]) == 1 and parts[1].isalpha():
                sym_name, sym_type = parts[0], parts[1]
                has_value = len(parts) >= 3
            elif len(parts[0]) == 1 and parts[0].isalpha():
                sym_type, sym_name = parts[0], parts[-1]
                has_value = False
            else:
                sym_type, sym_name = parts[-2], parts[-1]
                has_value = parts[0] not in ("U", "v", "w")

            kind = _classify_nm_symbol(sym_type, has_value)
            if kind == "undefined":
                _record_symbol(undefined, sym_name)
            elif kind == "defined":
                _record_symbol(defined, sym_name)
    except Exception:
        pass

    return defined, undefined


def parse_symbols_msvc(obj_path):
    """Parse symbols from Windows MSVC .obj file using dumpbin."""
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
    """Pure Python extractor for GNU/BSD/MSVC format ar archives."""
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
                    f.read(1)  # 2-byte alignment padding
                
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
                safe_name = filename.replace("\\", "/").split("/")[-1]
                if not safe_name.endswith(".o") and not safe_name.endswith(".obj"):
                    safe_name = f"{safe_name}.o"
                out_file = Path(output_dir) / f"{counter:04d}_{safe_name}"
                with open(out_file, "wb") as out_f:
                    out_f.write(data)
            return counter
    except Exception:
        return 0


def extract_header_symbols(header_path):
    """Extract public vosk_* C API symbols from vosk_api.h."""
    root_symbols = set()
    if header_path and os.path.isfile(str(header_path)):
        try:
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
        except Exception:
            pass

    if not root_symbols:
        builtin = [
            "vosk_model_new", "vosk_model_free", "vosk_model_find_word",
            "vosk_spk_model_new", "vosk_spk_model_free",
            "vosk_recognizer_new", "vosk_recognizer_new_spk", "vosk_recognizer_new_grm",
            "vosk_recognizer_free", "vosk_recognizer_set_spk_model", "vosk_recognizer_set_grm",
            "vosk_recognizer_set_threshold", "vosk_recognizer_set_max_alternatives",
            "vosk_recognizer_set_words", "vosk_recognizer_set_partial_words", "vosk_recognizer_set_nlsml",
            "vosk_recognizer_set_endpointer_mode", "vosk_recognizer_set_endpointer_delays",
            "vosk_recognizer_accept_waveform", "vosk_recognizer_accept_waveform_s",
            "vosk_recognizer_accept_waveform_f", "vosk_recognizer_result",
            "vosk_recognizer_partial_result", "vosk_recognizer_final_result",
            "vosk_recognizer_reset", "vosk_set_log_level", "vosk_gpu_init", "vosk_gpu_thread_init",
            "vosk_batch_model_new", "vosk_batch_model_free", "vosk_batch_model_wait",
            "vosk_batch_recognizer_new", "vosk_batch_recognizer_free",
            "vosk_batch_recognizer_accept_waveform", "vosk_batch_recognizer_set_nlsml",
            "vosk_batch_recognizer_finish_stream", "vosk_batch_recognizer_front_result",
            "vosk_batch_recognizer_pop", "vosk_batch_recognizer_get_pending_chunks",
            "vosk_text_processor_new", "vosk_text_processor_free", "vosk_text_processor_itn"
        ]
        for s in builtin:
            root_symbols.add(s)
            root_symbols.add(f"_{s}")
    return root_symbols


def slim_archive(input_archive, output_archive, header_path, nm_tool="nm", ar_tool="ar", ranlib_tool=None):
    start_time = time.time()
    input_path = Path(input_archive).resolve()
    output_path = Path(output_archive).resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    if not input_path.exists():
        print(f"[ERROR] Input archive does not exist: {input_path}")
        sys.exit(1)
        
    orig_size_mb = input_path.stat().st_size / (1024 * 1024)
    print("==============================================================================")
    print("  LibVosk Static Library Slimming Engine")
    print(f"  Input file: {input_path.name} ({orig_size_mb:.2f} MB)")
    print("==============================================================================")

    temp_dir = Path(tempfile.mkdtemp(prefix="vosk_slim_"))
    try:
        # 1. Extract all object files
        print("--> [1/4] Extracting object files from archive...")
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
            print("[ERROR] Failed to extract any object files (.o/.obj) from archive!")
            sys.exit(1)
        print(f"    Extracted {len(all_objs)} object files (.o/.obj)")

        # 2. Extract public API root symbols
        root_symbols = extract_header_symbols(header_path)
        print(f"    Extracted {len(root_symbols)} root Vosk C API symbols from header")

        # 3. Build symbol dependency graph
        print("--> [2/4] Parsing symbol tables and building dependency graph...", flush=True)
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
                ("f2c" in name_lower) or
                ("nnet-attention" in name_lower) or
                ("clusterable" in name_lower) or
                ("mapped-file" in name_lower) or
                ("nthbit" in name_lower)
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

        print(f"    Identified {len(kept_objs)} initial root nodes (API + OpenFST/Math core)")

        # 4. Transitive reachability closure (BFS)
        print("--> [3/4] Performing transitive reachability closure analysis...")
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
        print(f"    Closure complete: retained {kept_count} objects (pruned {pruned_count} unused objects)")

        # 5. Repack slimmed archive
        print("--> [4/4] Repacking slimmed archive...")
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
                if ranlib_tool:
                    subprocess.run([ranlib_tool, str(output_path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
                elif sys.platform == "darwin":
                    subprocess.run(["strip", "-S", str(output_path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
                    subprocess.run(["ranlib", "-no_warning_for_no_symbols", "-c", str(output_path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
                else:
                    subprocess.run(["strip", "--strip-debug", str(output_path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
                    subprocess.run(["ranlib", str(output_path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            except Exception:
                pass

        new_size_mb = output_path.stat().st_size / (1024 * 1024)
        savings_pct = (1.0 - (new_size_mb / orig_size_mb)) * 100.0
        elapsed = time.time() - start_time

        print("==============================================================================")
        print(f"[OK] Slimming complete in {elapsed:.2f}s")
        print(f"  Original size : {orig_size_mb:.2f} MB")
        print(f"  Slimmed size  : {new_size_mb:.2f} MB (reduced by {savings_pct:.1f}%)")
        print(f"  Output file   : {output_path}")
        print("==============================================================================")

    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="LibVosk Static Library Slimming Engine")
    parser.add_argument("input", help="Input static library file (.a / .lib)")
    parser.add_argument("output", help="Output slimmed static library file")
    parser.add_argument("--header", default="src/apple/vosk-api/src/vosk_api.h", help="Path to vosk_api.h")
    parser.add_argument("--nm", default="nm", help="Path to nm tool")
    parser.add_argument("--ar", default="ar", help="Path to ar tool")
    parser.add_argument("--ranlib", default=None, help="Path to ranlib tool")
    
    args = parser.parse_args()
    slim_archive(args.input, args.output, args.header, nm_tool=args.nm, ar_tool=args.ar, ranlib_tool=args.ranlib)
