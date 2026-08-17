#!/usr/bin/env python3
"""Generate and verify Nodebay's exact Swift package license notices."""

from __future__ import annotations

import json
import argparse
import hashlib
import pathlib
import urllib.request


ROOT = pathlib.Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "third_party/nodebay-components.json"
RESOLVED = ROOT / "boringNotch.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
OUTPUT = ROOT / "THIRD_PARTY_NOTICES_NODEBAY.md"
CHECKSUM = ROOT / "third_party/nodebay-notices.sha256"


def load_json(path: pathlib.Path):
    return json.loads(path.read_text(encoding="utf-8"))


def raw_license_url(component: dict) -> str:
    source = component["source"].removesuffix(".git").removesuffix("/")
    return f"{source}/raw/{component['revision']}/{component['licensePath']}"


def verify_lock(manifest: dict, resolved: dict) -> dict:
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
    return components


def check_offline(manifest: dict, components: dict) -> None:
    if not OUTPUT.exists() or not CHECKSUM.exists():
        raise SystemExit("Generated notices or their checksum are missing")
    data = OUTPUT.read_bytes()
    expected_hash = CHECKSUM.read_text(encoding="utf-8").strip().split()[0]
    actual_hash = hashlib.sha256(data).hexdigest()
    if actual_hash != expected_hash:
        raise SystemExit("Generated notices changed. Regenerate and review the full license texts")
    text = data.decode("utf-8")
    for companion in manifest["companions"]:
        heading = f"## {companion['name']} {companion['version']} (companion, not bundled)"
        if heading not in text or companion["licenseURL"] not in text:
            raise SystemExit(f"Missing companion notice for {companion['id']}")
    for component in components.values():
        heading = f"## {component['name']} {component['version']}"
        if heading not in text or raw_license_url(component) not in text:
            raise SystemExit(f"Missing locked package notice for {component['id']}")
    if text.count("```text") < len(manifest["companions"]) + len(components):
        raise SystemExit("One or more full license text blocks are missing")
    print(f"Verified {OUTPUT.relative_to(ROOT)} offline ({actual_hash})")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="verify checked-in notices without network access")
    args = parser.parse_args()
    manifest = load_json(MANIFEST)
    resolved = load_json(RESOLVED)
    components = verify_lock(manifest, resolved)
    if args.check:
        check_offline(manifest, components)
        return

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
    digest = hashlib.sha256(OUTPUT.read_bytes()).hexdigest()
    CHECKSUM.write_text(f"{digest}  {OUTPUT.name}\n", encoding="utf-8")
    print(f"Wrote {OUTPUT.relative_to(ROOT)} with {len(components)} locked package notices")


if __name__ == "__main__":
    main()
