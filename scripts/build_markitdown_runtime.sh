#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
requirements_file="$project_root/requirements/markitdown-runtime.txt"
build_root="$project_root/build/markitdown-runtime"
venv_root="$build_root/venv"
dist_root="$build_root/dist"
vendor_parent="$project_root/boringNotch/vendor"
vendor_root="$vendor_parent/markitdown-runtime"
required_python_version="3.13.15"
required_pip_version="26.2.1"
if [[ -n "${PYTHON_COMMAND:-}" ]]; then
    python_command="$PYTHON_COMMAND"
else
    python_command=$(python3 "$script_dir/prepare_python_runtime.py")
fi
if [[ -n "${PYTHON_LICENSE:-}" ]]; then
    python_license="$PYTHON_LICENSE"
else
    python_license=$($python_command -c 'import pathlib, sys; print(pathlib.Path(sys.base_prefix) / "lib/python3.13/LICENSE.txt")')
fi

if [[ ! -x "$python_command" ]]; then
    print -u2 "CPython $required_python_version is required at $python_command."
    print -u2 "Run scripts/prepare_python_runtime.py for the compatible Python.org interpreter."
    print -u2 "An explicit PYTHON_COMMAND must preserve the macOS 15 deployment floor."
    exit 1
fi

python_version=$($python_command -c 'import platform; print(platform.python_version())')
if [[ "$python_version" != "$required_python_version" && "${ALLOW_UNPINNED_PYTHON:-0}" != "1" ]]; then
    print -u2 "Expected CPython $required_python_version; found $python_version."
    print -u2 "Set ALLOW_UNPINNED_PYTHON=1 only for an intentional lock refresh."
    exit 1
fi

if [[ ! -f "$requirements_file" ]]; then
    print -u2 "Missing dependency lock: $requirements_file"
    exit 1
fi

if [[ ! -f "$python_license" ]]; then
    print -u2 "Missing Python license file: $python_license"
    print -u2 "Set PYTHON_LICENSE to the CPython LICENSE file."
    exit 1
fi

mkdir -p "$build_root" "$vendor_parent"

lock_digest=$(shasum -a 256 "$requirements_file" | awk '{print $1}')
interpreter_digest=$("$python_command" -c 'import hashlib, pathlib, sys; p=pathlib.Path(sys.base_prefix); print(hashlib.sha256((str(p)+sys.version).encode()).hexdigest())')
venv_stamp="$venv_root/.boring-notch-lock-$lock_digest-$interpreter_digest"
if [[ ! -f "$venv_stamp" ]]; then
    if [[ -d "$venv_root" ]]; then
        rm -rf "$venv_root"
    fi
    "$python_command" -m venv "$venv_root"
    "$venv_root/bin/python" -m pip install --disable-pip-version-check "pip==$required_pip_version"
    "$venv_root/bin/python" -m pip install \
        --disable-pip-version-check \
        --no-deps \
        --requirement "$requirements_file"
    "$venv_root/bin/python" -m pip check
    : > "$venv_stamp"
fi

"$venv_root/bin/python" "$script_dir/generate_markitdown_notices.py" \
    --requirements "$requirements_file" \
    --python-license "$python_license" \
    --output "$project_root/THIRD_PARTY_LICENSES_MARKITDOWN"

rm -rf "$dist_root" "$build_root/work" "$build_root/markitdown-local.spec"

"$venv_root/bin/pyinstaller" \
    --noconfirm \
    --clean \
    --onedir \
    --target-architecture arm64 \
    --exclude-module tkinter \
    --name markitdown-local \
    --distpath "$dist_root" \
    --workpath "$build_root/work" \
    --specpath "$build_root" \
    --collect-all markitdown \
    --collect-all magika \
    --collect-all mammoth \
    --collect-all charset_normalizer \
    --hidden-import openpyxl \
    --hidden-import xlrd \
    --hidden-import olefile \
    "$script_dir/markitdown_local.py"

staged_runtime=$(mktemp -d "$build_root/staged-runtime.XXXXXX")
trap 'rm -rf "$staged_runtime"' EXIT
ditto "$dist_root/markitdown-local" "$staged_runtime"
cp "$project_root/THIRD_PARTY_LICENSES_MARKITDOWN" "$staged_runtime/THIRD_PARTY_LICENSES"
print '# Generated runtime contents are intentionally excluded from Git.' > "$staged_runtime/.gitkeep"
chmod 755 "$staged_runtime/markitdown-local"
xattr -cr "$staged_runtime"
python3 "$script_dir/verify_runtime_compatibility.py" "$staged_runtime" --maximum-macos 15.0

while IFS= read -r binary; do
    codesign --force --sign - "$binary"
done < <(find "$staged_runtime" -type f -print0 | xargs -0 file | awk -F: '/Mach-O/ { print $1 }')
codesign --force --sign - "$staged_runtime/markitdown-local"

if [[ -d "$vendor_root" ]]; then
    rm -rf "$vendor_root"
fi
mv "$staged_runtime" "$vendor_root"
trap - EXIT

# File Provider-managed workspaces can restore stale conflict copies with a
# " 2" suffix after the generated directory is replaced. They are never part
# of the runtime and must not reach Xcode resources or a release archive.
find "$vendor_root" -depth \
    \( -name '* 2' -o -name '__pycache__' -o -name '*.pyc' \) \
    -exec rm -rf {} +

print "Local MarkItDown runtime created at $vendor_root"
print "Architecture: $(uname -m); Python: $python_version; lock: $lock_digest"
