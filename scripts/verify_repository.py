#!/usr/bin/env python3
"""Validate publishable Nodebay repository structure without network access."""

from __future__ import annotations

import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REQUIRED = {
    "README.md", "LICENSE", "ACKNOWLEDGEMENTS.md", "THIRD_PARTY_NOTICES.md",
    "PRIVACY.md", "SECURITY.md", "CONTRIBUTING.md", "CHANGELOG.md",
    "docs/installation.md", "docs/homebrew.md", "docs/permissions.md",
    "docs/privacy-and-security.md", "docs/building-from-source.md",
    "docs/release-process.md", "docs/architecture.md", "docs/troubleshooting.md",
    "docs/migration-from-boring-notch.md", "docs/features/file-shelf.md",
    "docs/features/file-stacks.md", "docs/features/markdown-conversion.md",
    "docs/features/media-downloader.md", "docs/features/image-compression.md",
    "docs/features/media-sources.md", "docs/features/system-hud.md",
    "docs/features/external-displays.md", "docs/engines/markitdown.md",
    "docs/engines/yt-dlp.md", "docs/engines/ffmpeg.md",
    "docs/engines/imageoptim.md", "docs/engines/browser-bridge.md",
}
ARTIFACT_PATTERN = re.compile(
    r"(^|/)(build|dist|DerivedData|__pycache__|markitdown-runtime)(/|$)"
    r"|\.(app|dmg|pkg|zip|pyc|xcarchive|xcresult|dSYM)(/|$)", re.I
)
LINK_PATTERN = re.compile(r"(?<!!)\[[^]]*]\(([^)]+)\)")


def tracked_files() -> list[str]:
    output = subprocess.check_output(["git", "ls-files"], cwd=ROOT, text=True)
    return output.splitlines()


def validate_required() -> None:
    missing = sorted(path for path in REQUIRED if not (ROOT / path).is_file())
    if missing:
        raise SystemExit(f"Missing required public documentation: {missing}")


def validate_artifacts(files: list[str]) -> None:
    allowed = {"boringNotch/vendor/markitdown-runtime/.gitkeep"}
    invalid = sorted(path for path in files if path not in allowed and ARTIFACT_PATTERN.search(path))
    if invalid:
        raise SystemExit(f"Generated or packaged artifacts are tracked: {invalid}")


def validate_local_links() -> None:
    failures: list[str] = []
    for markdown in sorted(ROOT.rglob("*.md")):
        if ".git" in markdown.parts or any(part in {"build", "DerivedData"} for part in markdown.parts):
            continue
        for target in LINK_PATTERN.findall(markdown.read_text(encoding="utf-8")):
            target = target.strip().strip("<>").split("#", 1)[0]
            if not target or target.startswith(("https://", "http://", "mailto:")):
                continue
            if not (markdown.parent / target).resolve().exists():
                failures.append(f"{markdown.relative_to(ROOT)} -> {target}")
    if failures:
        raise SystemExit("Broken local Markdown links:\n" + "\n".join(failures))


def validate_identity() -> None:
    required_text = {
        "README.md": ["The utility bay in your Mac's notch.", "Kian Konrad Tajbakhsh", "44dd999f70493da48209c99e9f873c47f2e55c83"],
        "ACKNOWLEDGEMENTS.md": ["based on", "Boring Notch"],
        "THIRD_PARTY_NOTICES.md": ["Microsoft MarkItDown 0.1.7", "MediaRemoteAdapter"],
    }
    for path, needles in required_text.items():
        text = (ROOT / path).read_text(encoding="utf-8")
        for needle in needles:
            if needle not in text:
                raise SystemExit(f"{path} is missing required text: {needle}")


def main() -> None:
    files = tracked_files()
    validate_required()
    validate_artifacts(files)
    validate_local_links()
    validate_identity()
    print(f"Repository verification passed: {len(REQUIRED)} required files, no tracked release artifacts, local links valid")


if __name__ == "__main__":
    main()
