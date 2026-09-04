import os
import zipfile
import sys

# Priority: packages directory relative to script root, or overridden via argv[1]
script_dir = os.path.dirname(os.path.abspath(__file__))
repo_root = os.path.dirname(script_dir)
pkg_dir = os.path.join(repo_root, "packages")

if len(sys.argv) > 1:
    pkg_dir = os.path.abspath(sys.argv[1])

if not os.path.exists(pkg_dir):
    print(f"[ERROR] Packages directory {pkg_dir} does not exist!")
    sys.exit(1)

files = sorted(os.listdir(pkg_dir))
zip_files = [f for f in files if f.endswith(".zip")]
whl_files = [f for f in files if f.endswith(".whl")]

print("=" * 80)
print(f"  VERIFYING PACKAGES IN {pkg_dir}")
print(f"  Found {len(zip_files)} .zip packages and {len(whl_files)} .whl packages.")
print("=" * 80)

passed = 0
failed = 0

def check_file(filename):
    global passed, failed
    filepath = os.path.join(pkg_dir, filename)
    file_size_mb = os.path.getsize(filepath) / 1024 / 1024
    print(f"\nChecking [{filename}] ({file_size_mb:.2f} MB)...")
    
    try:
        with zipfile.ZipFile(filepath, 'r') as z:
            namelist = z.namelist()
            infolist = z.infolist()
            print(f"   Contents ({len(namelist)} items):")
            for info in infolist:
                size_str = f"{info.file_size / 1024:.1f} KB" if info.file_size < 1024 * 1024 else f"{info.file_size / 1024 / 1024:.2f} MB"
                print(f"     - {info.filename} ({size_str})")
            
            # Validation rules
            is_valid = True
            reasons = []

            # 0. Naming convention check
            if "xcframework-static" in filename or "-libvosk.xcframework" in filename:
                is_valid = False
                reasons.append(f"Invalid / malformed package name: {filename}")

            # 1. Integrity check: reject 0-byte corrupted files
            for info in infolist:
                if not info.filename.endswith("/") and info.file_size == 0:
                    is_valid = False
                    reasons.append(f"Empty 0-byte file found: {info.filename}")

            is_windows = "win" in filename.lower()

            if filename.endswith(".zip"):
                if "-shared.zip" in filename:
                    has_dyn = any(name.endswith(('.so', '.dylib', '.dll')) for name in namelist)
                    has_hdr = any("vosk_api.h" in name for name in namelist)
                    if not has_dyn:
                        is_valid = False
                        reasons.append("Missing dynamic library (.so/.dylib/.dll)")
                    if not has_hdr:
                        is_valid = False
                        reasons.append("Missing header (vosk_api.h)")
                    
                    # Windows shared package rule: must include import library
                    if is_windows:
                        has_implib = any(name.endswith((".lib", ".dll.a")) for name in namelist)
                        if not has_implib:
                            is_valid = False
                            reasons.append("Missing Windows import library (.lib / .dll.a)")

                elif "-static.zip" in filename:
                    has_stat = any(name.endswith(('.a', '.lib')) for name in namelist)
                    has_hdr = any("vosk_api.h" in name for name in namelist)
                    if not has_stat:
                        is_valid = False
                        reasons.append("Missing static library (.a/.lib)")
                    if not has_hdr:
                        is_valid = False
                        reasons.append("Missing header (vosk_api.h)")

                elif "-xcframework.zip" in filename:
                    has_xcf = any(".xcframework" in name for name in namelist)
                    has_plist = any("Info.plist" in name for name in namelist)
                    if not has_xcf:
                        is_valid = False
                        reasons.append("Missing .xcframework bundle")
                    if not has_plist:
                        is_valid = False
                        reasons.append("Missing Info.plist in XCFramework")

            elif filename.endswith(".whl"):
                has_init = any("vosk/__init__.py" in name for name in namelist)
                has_lib = any(name.endswith(('.so', '.dylib', '.dll')) for name in namelist)
                if not has_init:
                    is_valid = False
                    reasons.append("Missing vosk/__init__.py")
                
                # py3-none-any.whl is a pure Python wrapper, skip dynamic library check
                is_any_wheel = filename.endswith("-py3-none-any.whl")
                if not has_lib and not is_any_wheel:
                    is_valid = False
                    reasons.append("Missing dynamic library in wheel")

            if is_valid:
                print(f"   [OK] VERIFIED: Valid")
                passed += 1
            else:
                print(f"   [ERROR] FAILED: {', '.join(reasons)}")
                failed += 1

    except Exception as e:
        print(f"   [ERROR] CORRUPTED: {e}")
        failed += 1

for f in zip_files + whl_files:
    check_file(f)

print("\n" + "=" * 80)
print(f"  VERIFICATION SUMMARY: {passed} PASSED, {failed} FAILED (TOTAL {passed + failed} PACKAGES)")
print("=" * 80)

if failed > 0:
    sys.exit(1)
