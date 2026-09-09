#!/usr/bin/env python3
"""Extract the pinned, signed Python.org runtime without installing it globally."""

from __future__ import annotations

import hashlib
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile


VERSION = "3.13.15"
PACKAGE = f"python-{VERSION}-macos11.pkg"
URL = f"https://www.python.org/ftp/python/{VERSION}/{PACKAGE}"
# Published at https://www.python.org/downloads/release/python-31315/.
SHA256 = "3b7eaf7f29825f796e8267024435540ddf1f17fc9a97ad58095daa7a75bfdcd3"
LICENSE_SHA256 = "78b12c3a81360b357002334f0e70ea0e92eebf7a9b358805c03c48484945f3bb"
SIGNER = "Developer ID Installer: Python Software Foundation (BMM5U3QVKW)"
FRAMEWORK_PREFIX = "/Library/Frameworks/Python.framework/"
MACHO_MAGIC = {bytes.fromhex(value) for value in (
    "cafebabe", "bebafeca", "cafebabf", "bfbafeca", "cffaedfe", "feedfacf", "cefaedfe", "feedface",
)}


def run(*args: str) -> str:
    try:
        return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.output) from error


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare() -> Path:
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise SystemExit("The pinned Nodebay release runtime requires Apple Silicon macOS.")
    cache = Path(os.environ.get("NODEBAY_PYTHON_CACHE", str(Path.home() / "Library/Caches/Nodebay/python-runtime"))) / VERSION
    cache.mkdir(parents=True, exist_ok=True)
    package = cache / PACKAGE
    if not package.exists():
        with tempfile.TemporaryDirectory(prefix="download-", dir=cache) as temporary:
            downloaded = Path(temporary) / PACKAGE
            run("/usr/bin/curl", "--fail", "--location", "--silent", "--show-error", URL, "--output", str(downloaded))
            if digest(downloaded) != SHA256:
                raise SystemExit("Python.org installer checksum did not match the reviewed release.")
            downloaded.replace(package)
    if digest(package) != SHA256:
        raise SystemExit("Cached Python.org installer checksum does not match. Preserve and inspect the cache.")
    signature = run("/usr/sbin/pkgutil", "--check-signature", str(package))
    if SIGNER not in signature or "signed by a developer certificate issued by Apple for distribution" not in signature:
        raise SystemExit("Python.org installer does not have the expected trusted PSF signature.")
    run("/usr/sbin/spctl", "--assess", "--type", "install", "--verbose=4", str(package))

    # A recipe-specific directory avoids reusing a previously built Homebrew or
    # differently relocated interpreter and never overwrites a meaningful cache.
    recipe = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()[:16]
    destination = cache / f"prepared-{recipe}"
    interpreter = destination / "Python.framework/Versions/3.13/bin/python3.13"
    if not interpreter.exists():
        with tempfile.TemporaryDirectory(prefix="prepare-", dir=cache) as temporary:
            stage = Path(temporary)
            expanded = stage / "expanded"
            run("/usr/sbin/pkgutil", "--expand-full", str(package), str(expanded))
            framework = stage / "prepared/Python.framework"
            shutil.copytree(expanded / "Python_Framework.pkg/Payload", framework, symlinks=True)
            # The converter is headless. Do not carry the vendor's optional
            # Tcl/Tk GUI frameworks or their extension into its build runtime.
            optional_frameworks = framework / "Versions/3.13/Frameworks"
            if optional_frameworks.is_dir():
                shutil.rmtree(optional_frameworks)
            for extension in (framework / "Versions/3.13/lib/python3.13/lib-dynload").glob("_tkinter.*.so"):
                extension.unlink()
            binaries = []
            for path in framework.rglob("*"):
                if not path.is_file() or path.is_symlink():
                    continue
                with path.open("rb") as stream:
                    if stream.read(4) not in MACHO_MAGIC:
                        continue
                binaries.append(path)
            for binary in binaries:
                binary.chmod(binary.stat().st_mode | 0o200)
                run("/usr/bin/xattr", "-c", str(binary))
                arches = run("/usr/bin/lipo", "-archs", str(binary)).split()
                if binary.name == "python3.13-intel64" and "arm64" not in arches:
                    # The vendor includes an optional Intel-only launcher.
                    # It is not part of this arm64 build interpreter.
                    binary.unlink()
                    continue
                if "arm64" not in arches:
                    raise SystemExit(f"Python.org payload lacks arm64: {binary.relative_to(framework)}")
                if len(arches) > 1:
                    thinned = binary.with_name(binary.name + ".arm64")
                    run("/usr/bin/lipo", str(binary), "-thin", "arm64", "-output", str(thinned))
                    thinned.replace(binary)
                # Relocate this build interpreter inside its private framework.
                # PyInstaller relocates the final distribution independently.
                for line in run("/usr/bin/otool", "-L", str(binary)).splitlines():
                    if not line.startswith("\t"):
                        continue
                    dependency = line.strip().split(" (")[0]
                    if dependency.startswith(FRAMEWORK_PREFIX):
                        target = framework / dependency[len(FRAMEWORK_PREFIX):]
                        relative = "@loader_path/" + os.path.relpath(target, binary.parent)
                        run("/usr/bin/install_name_tool", "-change", dependency, relative, str(binary))
            for binary in binaries:
                if binary.exists():
                    run("/usr/bin/codesign", "--force", "--sign", "-", str(binary))
            license_path = framework / "Versions/3.13/lib/python3.13/LICENSE.txt"
            if digest(license_path) != LICENSE_SHA256:
                raise SystemExit("Extracted CPython license does not match the reviewed notice.")
            (stage / "prepared").rename(destination)
    version = run(str(interpreter), "-c", "import platform, ssl, sqlite3; print(platform.python_version())").strip()
    if version != VERSION:
        raise SystemExit(f"Unexpected extracted Python version: {version}")
    return interpreter


if __name__ == "__main__":
    print(prepare())
