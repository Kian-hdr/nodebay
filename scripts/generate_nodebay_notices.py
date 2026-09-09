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
OUTPUT = ROOT / "THIRD_PARTY_NOTICES.md"
CHECKSUM = ROOT / "third_party/nodebay-notices.sha256"
ADAPTER_VERSION = "v0.7.7"
ADAPTER_COMMIT = "e3ff5021eb0875858bd05f48d2e9ba2e962d1cf6"
ADAPTER_HASHES = {
    "MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter": "0296903d9f4217e1440bf7c6bf96e37a07bb37942fdb6188e4b968d29890f950",
    "MediaRemoteAdapterTestClient": "ebd4ba81b92127db4d3ff3e3af269a0280ae1ff1610030a68d02e4a1765cf6cf",
    "mediaremote-adapter.pl": "d97802e46db9535e2549e178c105ebf417a0254b3929fc32f08ecfd14d49a85f",
}
ADAPTER_NOTICE = (
    f"MediaRemoteAdapter {ADAPTER_VERSION} is a bundled BSD-3-Clause framework built from "
    f"https://github.com/ungive/mediaremote-adapter at commit `{ADAPTER_COMMIT}`; "
    "its license text is in `THIRD_PARTY_LICENSES`. Source and rebuild instructions are in "
    "`mediaremote-adapter/SOURCE.md`. The vendored framework SHA-256 before release re-signing is "
    f"`{ADAPTER_HASHES['MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter']}`."
)


def load_json(path: pathlib.Path):
    return json.loads(path.read_text(encoding="utf-8"))


def raw_license_url(component: dict) -> str:
    source = component["source"].removesuffix(".git").removesuffix("/")
    return f"{source}/raw/{component['revision']}/{component['licensePath']}"


def verify_lock(manifest: dict, resolved: dict) -> dict:
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


def verified_existing_text() -> str:
    if not OUTPUT.exists() or not CHECKSUM.exists():
        raise SystemExit("Generated notices or their checksum are missing")
    data = OUTPUT.read_bytes()
    expected_hash = CHECKSUM.read_text(encoding="utf-8").strip().split()[0]
    if hashlib.sha256(data).hexdigest() != expected_hash:
        raise SystemExit("Generated notices changed. Regenerate and review the full license texts")
    return data.decode("utf-8")


def verify_adapter() -> None:
    adapter = ROOT / "mediaremote-adapter"
    source = (adapter / "SOURCE.md").read_text(encoding="utf-8")
    if ADAPTER_VERSION not in source or ADAPTER_COMMIT not in source:
        raise SystemExit("MediaRemoteAdapter source/version does not match the notice generator")
    for filename, expected_hash in ADAPTER_HASHES.items():
        path = adapter / filename
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected_hash:
            raise SystemExit(f"MediaRemoteAdapter vendored file drift: {filename}")
        if expected_hash not in source:
            raise SystemExit(f"MediaRemoteAdapter source record omits the hash for {filename}")
    license_text = (adapter / "LICENSE").read_text(encoding="utf-8").strip()
    bundled_notices = (ROOT / "THIRD_PARTY_LICENSES").read_text(encoding="utf-8")
    # The foundation notice formats the heading and copyright as an applies-to
    # list. Require those exact texts plus the complete, unchanged license body.
    license_sections = license_text.split("\n\n", 2)
    if len(license_sections) != 3 or not all(section in bundled_notices for section in license_sections):
        raise SystemExit("MediaRemoteAdapter's full BSD license is missing from bundled notices")


def retained_license(existing: str, item: dict, url: str, companion: bool) -> str:
    heading = f"## {item['name']} {item['version']}"
    if companion:
        heading += " (companion, not bundled)"
    marker = heading + "\n\n"
    if existing.count(marker) != 1:
        raise SystemExit(f"Cannot reuse a unique reviewed notice for {item['id']}")
    # Some upstream LICENSE files contain Markdown headings inside their fenced
    # text. Delimit by the license fence, not by those preserved headings.
    section = existing.split(marker, 1)[1]
    metadata, separator, body = section.partition("\n```text\n")
    required = [f"- Source: {item['source']}", f"- License: {item['license']}", f"- License source: {url}"]
    if not companion:
        required.append(f"- Revision: `{item['revision']}`")
    if not separator or "\n## " in metadata or not all(line in metadata.splitlines() for line in required):
        raise SystemExit(f"Cannot reuse license with changed provenance for {item['id']}")
    license_text, closing, _ = body.partition("\n```")
    if not closing or not license_text.strip():
        raise SystemExit(f"Cannot reuse an incomplete full license for {item['id']}")
    return license_text


def check_offline(manifest: dict, components: dict) -> None:
    if (ROOT / "scripts/stl_repair.py").exists():
        companion = next((c for c in manifest["companions"] if c["id"] == "stl-repair"), None)
        if not companion or companion.get("bundled") is not False or "5.0.1" not in companion["version"]:
            raise SystemExit("STL repair requires an exact Blender companion notice; bundled Blender is not approved")
        for directory in [ROOT / "boringNotch/vendor", ROOT / "boringNotch/Resources/engines"]:
            if directory.exists() and any("blender" in p.name.lower() for p in directory.rglob("*")):
                raise SystemExit("Bundled Blender requires a separate source-distribution/license review")
    text = verified_existing_text()
    actual_hash = hashlib.sha256(OUTPUT.read_bytes()).hexdigest()
    verify_adapter()
    if ADAPTER_NOTICE not in text:
        raise SystemExit("MediaRemoteAdapter notice does not match the vendored version, source and binary hash")
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
    parser.add_argument("--reuse-verified-licenses", action="store_true",
                        help="regenerate using unchanged full license blocks from checksum-verified notices; no network fetch")
    args = parser.parse_args()
    manifest = load_json(MANIFEST)
    resolved = load_json(RESOLVED)
    components = verify_lock(manifest, resolved)
    if args.check:
        check_offline(manifest, components)
        return
    verify_adapter()
    existing = verified_existing_text() if args.reuse_verified_licenses else None

    def license_for(item: dict, url: str, companion: bool) -> str:
        if existing is not None:
            return retained_license(existing, item, url, companion)
        with urllib.request.urlopen(url, timeout=30) as response:
            return response.read().decode("utf-8").strip()

    sections = [
        "# Nodebay Third-Party Notices",
        "",
        "Generated from `third_party/nodebay-components.json` and the exact SwiftPM lock. Do not edit manually.",
        "",
        "Nodebay is GPL-3.0 software based on Boring Notch. The project license is in `LICENSE`.",
        "The exact Boring Notch foundation is commit `44dd999f70493da48209c99e9f873c47f2e55c83`.",
        "The bundled Microsoft MarkItDown 0.1.7 runtime and its complete Python package notices are in `THIRD_PARTY_LICENSES_MARKITDOWN`.",
        ADAPTER_NOTICE,
        "",
        "Nodebay's equalizer uses Apple AVFoundation for local shelf audio and Core Audio process taps for Spotify, QuickTime Player and identified Chrome audio. The optional browser bridge also contains its separately enabled Web Audio path. It adds no third-party DSP library or redistributed binary. The optional setup interface can invoke a separately installed Homebrew only for the exact companion packages documented below. Homebrew is not bundled, modified, or redistributed by Nodebay.",
        "",
    ]
    for companion in manifest["companions"]:
        license_text = license_for(companion, companion["licenseURL"], True)
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
        license_text = license_for(component, url, False)
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
    provenance = "reused unchanged checksum-verified license blocks; no network fetch" if existing is not None else "fetched license sources"
    print(f"Wrote {OUTPUT.relative_to(ROOT)} with {len(components)} locked package notices ({provenance})")
    check_offline(manifest, components)


if __name__ == "__main__":
    main()
