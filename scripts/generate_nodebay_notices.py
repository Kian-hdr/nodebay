#!/usr/bin/env python3
"""Generate and verify Nodebay's exact Swift package license notices."""

from __future__ import annotations

import json
import pathlib
import urllib.request


ROOT = pathlib.Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "third_party/nodebay-components.json"
RESOLVED = ROOT / "boringNotch.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
OUTPUT = ROOT / "THIRD_PARTY_NOTICES_NODEBAY.md"


def load_json(path: pathlib.Path):
    return json.loads(path.read_text(encoding="utf-8"))


def raw_license_url(component: dict) -> str:
    source = component["source"].removesuffix(".git").removesuffix("/")
    return f"{source}/raw/{component['revision']}/{component['licensePath']}"


def main() -> None:
    manifest = load_json(MANIFEST)
    resolved = load_json(RESOLVED)
    components = {item["id"]: item for item in manifest["components"]}
    pins = {item["identity"]: item for item in resolved["pins"]}

    missing = sorted(set(pins) - set(components))
    extra = sorted(set(components) - set(pins))
    if missing or extra:
        raise SystemExit(f"Notice manifest mismatch. Missing={missing}; extra={extra}")
    for identity, pin in pins.items():
        expected = components[identity]
        state = pin["state"]
        if state.get("version") != expected["version"] or state.get("revision") != expected["revision"]:
            raise SystemExit(f"Pinned dependency drift for {identity}")

    sections = [
        "# Nodebay Third-Party Notices",
        "",
        "Generated from `third_party/nodebay-components.json` and the exact SwiftPM lock. Do not edit manually.",
        "",
        "Nodebay is GPL-3.0 software based on Boring Notch. The project license is in `LICENSE`.",
        "The exact Boring Notch foundation is commit `44dd999f70493da48209c99e9f873c47f2e55c83`.",
        "The bundled Microsoft MarkItDown 0.1.7 runtime and its complete Python package notices are in `THIRD_PARTY_LICENSES_MARKITDOWN`.",
        "MediaRemoteAdapter 0.1.0 is a bundled BSD-3-Clause framework from https://github.com/ungive/mediaremote-adapter; its license text is in `THIRD_PARTY_LICENSES`. The bundled binary SHA-256 is `91eb19837ca9f2779e476dc8e67d12bc28331dd557c87a19b0e45463c739c2fc`.",
        "",
    ]
    for companion in manifest["companions"]:
        with urllib.request.urlopen(companion["licenseURL"], timeout=30) as response:
            license_text = response.read().decode("utf-8").strip()
        sections.extend([
            f"## {companion['name']} {companion['version']} (companion, not bundled)",
            "",
            f"- Source: {companion['source']}",
            f"- License: {companion['license']}",
            "- Distribution status: Detected separately on the development Mac. Nodebay does not redistribute this tool.",
            f"- License source: {companion['licenseURL']}",
            "",
            "```text",
            license_text,
            "```",
            "",
        ])
    for component in manifest["components"]:
        url = raw_license_url(component)
        with urllib.request.urlopen(url, timeout=30) as response:
            license_text = response.read().decode("utf-8").strip()
        sections.extend([
            f"## {component['name']} {component['version']}",
            "",
            f"- Source: {component['source']}",
            f"- Revision: `{component['revision']}`",
            f"- License: {component['license']}",
            f"- License source: {url}",
            "",
            "```text",
            license_text,
            "```",
            "",
        ])
    OUTPUT.write_text("\n".join(sections), encoding="utf-8")
    print(f"Wrote {OUTPUT.relative_to(ROOT)} with {len(components)} locked package notices")


if __name__ == "__main__":
    main()
