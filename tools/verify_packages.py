import os
import zipfile
import sys

# 优先获取相对于脚本根目录的 packages 路径，亦可覆盖传入
script_dir = os.path.dirname(os.path.abspath(__file__))
repo_root = os.path.dirname(script_dir)
pkg_dir = os.path.join(repo_root, "packages")

if len(sys.argv) > 1:
    pkg_dir = os.path.abspath(sys.argv[1])

if not os.path.exists(pkg_dir):
    print(f"❌ Error: Packages directory {pkg_dir} does not exist!")
    sys.exit(1)

files = sorted(os.listdir(pkg_dir))
zip_files = [f for f in files if f.endswith(".zip")]
whl_files = [f for f in files if f.endswith(".whl")]

print("=" * 80)
print(f"  📦 VERIFYING PACKAGES IN {pkg_dir}")
print(f"  Found {len(zip_files)} .zip packages and {len(whl_files)} .whl packages.")
print("=" * 80)

passed = 0
failed = 0

def check_file(filename):
    global passed, failed
    filepath = os.path.join(pkg_dir, filename)
    print(f"\n📄 Checking [{filename}] ({os.path.getsize(filepath) / 1024 / 1024:.2f} MB)...")
    
    try:
        with zipfile.ZipFile(filepath, 'r') as z:
            namelist = z.namelist()
            print(f"   Contents ({len(namelist)} items):")
            # 完整展示内部所有文件明细，不隐藏
            for name in namelist:
                print(f"     - {name}")
            
            # Validation rules
            is_valid = True
            reasons = []

            if filename.endswith(".zip"):
                if "-shared.zip" in filename:
                    has_dyn = any(name.endswith(('.so', '.dylib', '.dll', '.lib')) for name in namelist)
                    has_hdr = any("vosk_api.h" in name for name in namelist)
                    if not has_dyn:
                        is_valid = False
                        reasons.append("Missing dynamic library (.so/.dylib/.dll/.lib)")
                    if not has_hdr:
                        is_valid = False
                        reasons.append("Missing header (vosk_api.h)")

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
                    if not has_xcf:
                        is_valid = False
                        reasons.append("Missing .xcframework bundle")

            elif filename.endswith(".whl"):
                has_init = any("vosk/__init__.py" in name for name in namelist)
                has_lib = any(name.endswith(('.so', '.dylib', '.dll')) for name in namelist)
                if not has_init:
                    is_valid = False
                    reasons.append("Missing vosk/__init__.py")
                if not has_lib:
                    is_valid = False
                    reasons.append("Missing dynamic library in wheel")

            if is_valid:
                print(f"   ✅ VERIFIED: OK!")
                passed += 1
            else:
                print(f"   ❌ FAILED: {', '.join(reasons)}")
                failed += 1

    except Exception as e:
        print(f"   ❌ CORRUPTED: {e}")
        failed += 1

for f in zip_files + whl_files:
    check_file(f)

print("\n" + "=" * 80)
print(f"  🔍 VERIFICATION SUMMARY: {passed} PASSED, {failed} FAILED (TOTAL {passed + failed} PACKAGES)")
print("=" * 80)

if failed > 0:
    sys.exit(1)
