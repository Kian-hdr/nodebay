#!/usr/bin/env python3
"""Reject binaries whose architecture, deployment floor or dylibs break the app contract."""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import subprocess


MACHO_MAGIC = {bytes.fromhex(value) for value in (
    "cafebabe", "bebafeca", "cafebabf", "bfbafeca", "cffaedfe", "feedfacf", "cefaedfe", "feedface",
)}


def version_tuple(value: str) -> tuple[int, int, int]:
    parts = [int(part) for part in value.split(".")]
    return tuple((parts + [0, 0, 0])[:3])


def minimum_versions(load_commands: str) -> list[str]:
    """Read both modern LC_BUILD_VERSION and older LC_VERSION_MIN_MACOSX."""
    result = []
    for command in re.split(r"Load command \d+", load_commands):
        if "cmd LC_BUILD_VERSION" in command:
            match = re.search(r"\bminos\s+(\d+(?:\.\d+){0,2})", command)
        elif "cmd LC_VERSION_MIN_MACOSX" in command:
            match = re.search(r"\bversion\s+(\d+(?:\.\d+){0,2})", command)
        else:
            continue
        if match:
            result.append(match.group(1))
    return result


def dependencies(output: str) -> list[str]:
    return [line.strip().split(" (")[0] for line in output.splitlines() if line.startswith("\t")]


def inspect_binary(path: Path, maximum: str, architecture: str) -> list[str]:
    errors = []
    arches = subprocess.check_output(["/usr/bin/lipo", "-archs", str(path)], text=True).split()
    if architecture not in arches:
        return [f"missing {architecture} architecture"]
    commands = subprocess.check_output(["/usr/bin/otool", "-arch", architecture, "-l", str(path)], text=True)
    floors = minimum_versions(commands)
    if not floors:
        errors.append("missing macOS deployment metadata")
    for floor in floors:
        if version_tuple(floor) > version_tuple(maximum):
            errors.append(f"requires macOS {floor}, above supported {maximum}")
    links = subprocess.check_output(["/usr/bin/otool", "-arch", architecture, "-L", str(path)], text=True)
    for dependency in dependencies(links):
        if not dependency.startswith(("/System/Library/", "/usr/lib/", "@rpath/", "@loader_path/", "@executable_path/")):
            errors.append(f"external dependency: {dependency}")
    return errors


def verify(root: Path, maximum: str, architecture: str) -> tuple[int, list[str]]:
    count = 0
    errors = []
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.is_symlink():
            continue
        with path.open("rb") as stream:
            if stream.read(4) not in MACHO_MAGIC:
                continue
        count += 1
        errors.extend(f"{path.relative_to(root)}: {error}" for error in inspect_binary(path, maximum, architecture))
    if count == 0:
        errors.append("No Mach-O binaries were found.")
    return count, errors


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("--maximum-macos", default="15.0")
    parser.add_argument("--architecture", default="arm64")
    args = parser.parse_args()
    count, errors = verify(args.root, args.maximum_macos, args.architecture)
    if errors:
        raise SystemExit("Binary compatibility failed:\n" + "\n".join(errors))
    print(f"Binary compatibility passed: {count} Mach-O files, {args.architecture}, macOS <= {args.maximum_macos}, no external absolute dependencies")


if __name__ == "__main__":
    main()
