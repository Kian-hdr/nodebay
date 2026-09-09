#!/usr/bin/env python3
"""Prepare, validate and explicitly publish Nodebay's signed Sparkle feed.

Uses the pinned Sparkle 2.9.5 SPM tools (distribution SHA-256
34b9b2071f3de0012eca3faa3a9290bb94e62131e9a74f6dc91514a000097a6c).
See https://sparkle-project.org/documentation/publishing/ .
No signing key is generated, exported, logged, or uploaded by this script.
Run each subcommand with --help. Publication defaults to a read-only dry run.
"""

import argparse
import base64
import hashlib
import html
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = "Kian-hdr/nodebay"
REMOTE = "https://github.com/" + REPOSITORY + ".git"
BRANCH = "updates"
FEED_BASE = "https://raw.githubusercontent.com/" + REPOSITORY + "/" + BRANCH
SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
NODEBAY = "https://github.com/Kian-hdr/nodebay/xml-namespaces/releases"
ET.register_namespace("sparkle", SPARKLE)
ET.register_namespace("nodebay", NODEBAY)
TOOLS = {
    "sign_update": "bfb52400c3da18bb4c251ac4818c2c2e1e31c2e649a45b31c11109b6e57b34ad",
    "generate_appcast": "669a5ed0f90ce06fb1de3e36aba35c5da8b98f66928a185fd4029174071be700",
}
SIGNING_PREFIX = b"<!-- sparkle-signatures:\n"
MAX_FEED_BYTES = 2 * 1024 * 1024
MAX_ARCHIVE_BYTES = 1024 * 1024 * 1024


class FeedError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise FeedError(message)


def run(args, *, cwd=None, env=None, sensitive=False):
    result = subprocess.run([str(arg) for arg in args], cwd=cwd, env=env,
                            text=True, capture_output=True, timeout=300)
    if result.returncode:
        # Sparkle's malformed-key error can include the private input. Suppress it.
        detail = " (signer output withheld)" if sensitive else ": " + result.stderr[-2000:]
        raise FeedError(Path(str(args[0])).name + " failed" + detail)
    return result.stdout


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def b64(value, length):
    try:
        result = base64.b64decode(value, validate=True)
    except (ValueError, TypeError):
        raise FeedError("Invalid base64 signature or public key") from None
    require(len(result) == length, "Wrong signature or public-key length")
    return result


def feed_url(channel):
    require(channel in ("stable", "testing"), "Unknown update channel")
    return FEED_BASE + "/" + channel + "/appcast.xml"


def release_identity(version, build, channel):
    require(re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version) is not None,
            "Version must have three numeric components")
    require(isinstance(build, int) and 0 < build < 2**31, "Invalid build number")
    feed_url(channel)
    tag = "nodebay-v" + version if channel == "stable" else "nodebay-update-test-" + str(build)
    name = "Nodebay-" + version + "-arm64.zip"
    url = "https://github.com/" + REPOSITORY + "/releases/download/" + tag + "/" + name
    return tag, name, url


def signature_verifier():
    source = ROOT / "scripts/verify_sparkle_signature.swift"
    directory = Path.home() / "Library/Caches/Nodebay/sparkle-verifier" / sha256(source)
    binary = directory / "verify-signature"
    if not binary.exists():
        directory.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=directory) as temporary:
            staged = Path(temporary) / "verify-signature"
            run(["xcrun", "swiftc", "-O", source, "-o", staged])
            os.replace(staged, binary)
    return binary


def verify_signature(path, public_key, signature, length):
    b64(public_key, 32)
    b64(signature, 64)
    require(0 < length <= MAX_ARCHIVE_BYTES, "Invalid signed file length")
    require(Path(path).stat().st_size == length, "Signed file length mismatch")
    run([signature_verifier(), path, public_key, signature, str(length)])


def signed_content(data):
    """Strict subset of Sparkle 2.9.5 SPUExtractAppcastContent's trailer format."""
    require(0 < len(data) <= MAX_FEED_BYTES, "Invalid feed size")
    require(data.count(SIGNING_PREFIX) == 1, "Missing or ambiguous feed signature")
    content, trailer = data.rsplit(SIGNING_PREFIX, 1)
    match = re.fullmatch(rb"edSignature: ([A-Za-z0-9+/=]+)\nlength: ([0-9]+)\n-->\n?", trailer)
    require(match is not None, "Malformed feed signature trailer or trailing data")
    signature = match[1].decode("ascii")
    b64(signature, 64)
    require(int(match[2]) == len(content), "Signed feed length mismatch")
    require(b"<!DOCTYPE" not in content.upper() and b"<!ENTITY" not in content.upper(),
            "DTD/entities are not allowed in an update feed")
    return content, signature


def one(element, tag):
    values = element.findall(tag)
    require(len(values) == 1, "Feed requires exactly one " + tag)
    return values[0]


def item_value(item, local_name):
    return one(item, "{" + SPARKLE + "}" + local_name).text or ""


def inspect_feed(path, public_key, channel):
    return inspect_feed_data(Path(path).read_bytes(), public_key, channel)


def inspect_feed_data(data, public_key, channel):
    content, signature = signed_content(data)
    with tempfile.TemporaryDirectory(prefix="nodebay-feed-verify-") as directory:
        unsigned = Path(directory) / "content"
        unsigned.write_bytes(content)
        verify_signature(unsigned, public_key, signature, len(content))
    try:
        root = ET.fromstring(content)
    except ET.ParseError:
        raise FeedError("Malformed signed XML") from None
    require(root.tag == "rss" and root.get("version") == "2.0", "Expected RSS 2.0")
    rss_channel = one(root, "channel")
    require(len(rss_channel.findall("item")) == 1, "Exactly one current full update is required")
    item = one(rss_channel, "item")
    allowed_item_tags = {"title", "link", "description", "pubDate", "enclosure",
                         "{" + NODEBAY + "}release"}
    allowed_item_tags.update("{" + SPARKLE + "}" + name for name in
                             ("version", "shortVersionString", "minimumSystemVersion", "hardwareRequirements"))
    require(not item.attrib and all(child.tag in allowed_item_tags for child in item),
            "Unexpected update-item override; only the generated full-archive schema is supported")
    require(len(item) == len({child.tag for child in item}), "Duplicate update-item fields")
    version = item_value(item, "shortVersionString")
    build_text = item_value(item, "version")
    require(build_text.isascii() and build_text.isdecimal(), "Invalid feed build")
    build = int(build_text)
    tag, name, url = release_identity(version, build, channel)
    require(item_value(item, "minimumSystemVersion") == "15.0.0", "Expected macOS 15 floor")
    require(item_value(item, "hardwareRequirements") == "arm64", "Expected Apple Silicon update")
    require(not item.findall("{" + SPARKLE + "}deltas"), "Delta publication is not configured")
    require(not item.findall("{" + SPARKLE + "}releaseNotesLink"), "Release notes must be embedded")
    enclosure = one(item, "enclosure")
    require(set(enclosure.attrib) == {"url", "length", "type", "{" + SPARKLE + "}edSignature"}
            and len(enclosure) == 0,
            "Unexpected enclosure attributes: version/install/delta overrides are not allowed")
    require(enclosure.get("url") == url, "Update URL is not the exact Nodebay versioned asset")
    require(enclosure.get("type") == "application/octet-stream", "Invalid enclosure type")
    length_text = enclosure.get("length", "")
    require(length_text.isascii() and length_text.isdecimal(), "Invalid archive length")
    length = int(length_text)
    require(0 < length <= MAX_ARCHIVE_BYTES, "Archive size outside allowed range")
    archive_signature = enclosure.get("{" + SPARKLE + "}edSignature", "")
    b64(archive_signature, 64)
    metadata = one(item, "{" + NODEBAY + "}release")
    require(metadata.get("channel") == channel, "Feed channel mismatch")
    source_commit = metadata.get("sourceCommit", "")
    digest = metadata.get("sha256", "")
    require(re.fullmatch(r"[0-9a-f]{40}", source_commit) is not None, "Invalid source commit")
    require(re.fullmatch(r"[0-9a-f]{64}", digest) is not None, "Invalid archive SHA-256")
    return {"version": version, "build": build, "channel": channel,
            "tag": tag, "archive_name": name, "url": url, "length": length,
            "sha256": digest, "ed_signature": archive_signature,
            "source_commit": source_commit, "public_key": public_key,
            "feed_sha256": hashlib.sha256(data).hexdigest()}


def archive_metadata(path, public_key, channel):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        require(names.count("Nodebay.app/Contents/Info.plist") == 1, "Missing/duplicate app metadata")
        require(all(not name.startswith("/") and ".." not in Path(name).parts for name in names),
                "Unsafe archive path")
        require(all(name.startswith("Nodebay.app/") for name in names), "Unexpected archive payload")
        member = archive.getinfo("Nodebay.app/Contents/Info.plist")
        require(member.file_size < 1024 * 1024, "App metadata too large")
        data = archive.read(member)
        info = plistlib.loads(data)
    require(info.get("CFBundleIdentifier") == "theboringteam.boringnotch", "Wrong application identity")
    require(info.get("SUPublicEDKey") == public_key, "App uses a different signing public key")
    allowed_feeds = {feed_url(channel)}
    if channel == "testing":
        # Test the exact production ZIP before stable publication, so acceptance
        # does not require changing/re-signing the application afterward.
        allowed_feeds.add(feed_url("stable"))
    require(info.get("SUFeedURL") in allowed_feeds, "App uses a different update feed")
    require(info.get("SURequireSignedFeed") is True, "App must require signed feeds")
    require(info.get("SUVerifyUpdateBeforeExtraction") is True, "App must verify before extraction")
    require(type(info.get("SUSignedFeedFailureExpirationInterval")) in (int, float) and
            info["SUSignedFeedFailureExpirationInterval"] == 0,
            "App must not fall back to unsigned feed content")
    require(info.get("SUEnableSystemProfiling") is False and info.get("SUEnableJavaScript") is False,
            "Updater profiling and release-note JavaScript must remain disabled")
    require(str(info.get("LSMinimumSystemVersion")) in ("15.0", "15.0.0"), "Unexpected app macOS floor")
    return info


def validate_archive(path, record, *, notarized=True):
    require(Path(path).name == record["archive_name"], "Wrong archive filename")
    require(sha256(path) == record["sha256"], "Archive SHA-256 mismatch")
    verify_signature(path, record["public_key"], record["ed_signature"], record["length"])
    info = archive_metadata(path, record["public_key"], record["channel"])
    require(info.get("CFBundleShortVersionString") == record["version"] and
            info.get("CFBundleVersion") == str(record["build"]), "App/feed version mismatch")
    if notarized:
        env = dict(os.environ, EXPECTED_VERSION=record["version"],
                   EXPECTED_BUILD=str(record["build"]), REQUIRE_NOTARIZED="1")
        run([ROOT / "scripts/verify_release_artifact.sh", Path(path).resolve()], env=env)


def signer_arguments(args):
    tools = Path(args.sparkle_bin).resolve()
    for name, digest in TOOLS.items():
        require((tools / name).is_file() and sha256(tools / name) == digest,
                "Sparkle tool does not match the pinned 2.9.5 SPM distribution: " + name)
    if args.key_file:
        key = Path(args.key_file).expanduser().resolve()
        require(key.is_file() and key.is_absolute(), "Private-key file is missing")
        require(ROOT != key and ROOT not in key.parents, "Private key must stay outside the repository")
        require(key.stat().st_mode & 0o077 == 0, "Private-key file must not be group/world accessible")
        return tools, ["--ed-key-file", str(key)]
    require(args.keychain_account and args.keychain_account.lower().startswith("nodebay"),
            "Use an explicit Nodebay-specific Keychain account")
    return tools, ["--account", args.keychain_account]


def prepare(args):
    output = Path(args.output).resolve()
    require(not output.exists(), "Candidate output must be a new directory")
    archive = Path(args.archive).resolve()
    b64(args.public_key, 32)
    tag, name, url = release_identity(args.version, args.build, args.channel)
    require(archive.name == name, "Archive filename does not match version")
    require(re.fullmatch(r"[0-9a-f]{40}", args.source_commit) is not None, "Use an exact source commit")
    tools, key_args = signer_arguments(args)
    info = archive_metadata(archive, args.public_key, args.channel)
    require(info.get("CFBundleShortVersionString") == args.version and
            info.get("CFBundleVersion") == str(args.build), "App version differs from requested release")
    env = dict(os.environ, EXPECTED_VERSION=args.version, EXPECTED_BUILD=str(args.build),
               REQUIRE_NOTARIZED="1")
    run([ROOT / "scripts/verify_release_artifact.sh", archive], env=env)
    digest = sha256(archive)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="nodebay-appcast-", dir=output.parent) as directory:
        staging = Path(directory)
        archives = staging / "archives"
        archives.mkdir()
        shutil.copy2(archive, archives / name)
        if args.notes:
            notes = Path(args.notes).read_text()
            require(len(notes) <= 100000, "Release notes too large")
            paragraphs = ["<p>" + html.escape(p).replace("\n", "<br>") + "</p>"
                          for p in notes.split("\n\n")]
            (archives / (Path(name).stem + ".html")).write_text("\n".join(paragraphs))
        feed = staging / "appcast.xml"
        run([tools / "generate_appcast", *key_args, "--maximum-deltas", "0",
             "--maximum-versions", "1", "--versions", str(args.build),
             "--download-url-prefix", url.rsplit("/", 1)[0] + "/",
             "--link", "https://github.com/" + REPOSITORY + "/releases/tag/" + tag,
             "--embed-release-notes", "-o", feed, archives], sensitive=True)
        # Sparkle derives application metadata and signs the archive. Add the
        # byte/source/channel record, then use its supported feed re-signing API.
        root = ET.fromstring(feed.read_bytes())
        item = one(one(root, "channel"), "item")
        minimum = one(item, "{" + SPARKLE + "}minimumSystemVersion")
        require(minimum.text in ("15.0", "15.0.0"), "Generated minimum OS mismatch")
        minimum.text = "15.0.0"
        ET.SubElement(item, "{" + NODEBAY + "}release", {
            "sha256": digest, "sourceCommit": args.source_commit, "channel": args.channel})
        ET.ElementTree(root).write(feed, encoding="utf-8", xml_declaration=True)
        run([tools / "sign_update", *key_args, feed], sensitive=True)
        record = inspect_feed(feed, args.public_key, args.channel)
        validate_archive(archive, record, notarized=False)
        require(sha256(archive) == digest, "Archive changed during preparation")
        candidate = staging / "candidate"
        candidate.mkdir()
        shutil.copy2(feed, candidate / "appcast.xml")
        (candidate / "release.json").write_text(json.dumps(record, indent=2) + "\n")
        os.rename(candidate, output)
    print("Signed candidate prepared and publicly verified: " + str(output))


class HTTPSOnlyRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        require(urllib.parse.urlparse(newurl).scheme == "https", "Refusing non-HTTPS redirect")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def download_archive(record, destination, *, opener=None):
    """Only rename a complete, hash- and signature-verified anonymous download."""
    destination = Path(destination)
    require(not destination.exists(), "Download destination already exists")
    parsed = urllib.parse.urlparse(record["url"])
    require(parsed.scheme == "https" and parsed.netloc == "github.com", "Unexpected download host")
    expected = release_identity(record["version"], record["build"], record["channel"])[2]
    require(record["url"] == expected, "Mutable or foreign release URL")
    opener = opener or urllib.request.build_opener(HTTPSOnlyRedirect())
    request = urllib.request.Request(record["url"], headers={"User-Agent": "Nodebay-release-verifier"})
    with tempfile.TemporaryDirectory(prefix="nodebay-download-", dir=destination.parent) as directory:
        partial = Path(directory) / "download.partial"
        with opener.open(request, timeout=60) as response, partial.open("xb") as stream:
            require(response.status == 200, "Download did not return HTTP 200")
            advertised = response.headers.get("Content-Length")
            require(advertised is None or advertised == str(record["length"]), "HTTP length mismatch")
            count = 0
            while True:
                block = response.read(min(1024 * 1024, record["length"] - count + 1))
                if not block:
                    break
                count += len(block)
                require(count <= record["length"], "Download exceeds signed length")
                stream.write(block)
        require(count == record["length"], "Interrupted or truncated download")
        require(sha256(partial) == record["sha256"], "Hosted archive differs from signed candidate")
        verify_signature(partial, record["public_key"], record["ed_signature"], count)
        os.rename(partial, destination)


def next_manifest(previous, record):
    if previous is None:
        return {"schema": 1, "channel": record["channel"], "releases": [record]}
    require(previous.get("schema") == 1 and previous.get("channel") == record["channel"],
            "Unsupported or wrong-channel publication manifest")
    history = previous.get("releases")
    require(isinstance(history, list) and history, "Invalid publication history")
    builds = [entry["build"] for entry in history]
    require(builds == sorted(set(builds)), "Publication history is not strictly increasing")
    urls = [entry["url"] for entry in history]
    require(len(urls) == len(set(urls)), "Publication history reuses an immutable asset URL")
    require(record["build"] > builds[-1], "Build must strictly increase; no same-build replacement")
    last_version = tuple(map(int, history[-1]["version"].split(".")))
    require(tuple(map(int, record["version"].split("."))) >= last_version, "Version downgrade rejected")
    require(all(entry["url"] != record["url"] for entry in history), "Versioned asset URL is immutable")
    require(all(entry["public_key"] == record["public_key"] for entry in history),
            "Key rotation requires a separately reviewed migration")
    return dict(previous, releases=history + [record])


def load_candidate(path, public_key, channel):
    return load_candidate_snapshot(path, public_key, channel)[0]


def load_candidate_snapshot(path, public_key, channel):
    directory = Path(path)
    data = (directory / "appcast.xml").read_bytes()
    record = inspect_feed_data(data, public_key, channel)
    require(json.loads((directory / "release.json").read_text()) == record,
            "Candidate manifest differs from signed feed")
    return record, data


def github_release(record):
    release = json.loads(run(["gh", "api", "repos/" + REPOSITORY + "/releases/tags/" + record["tag"]]))
    require(release.get("draft") is False, "Publish release assets before the feed")
    require(release.get("prerelease") is (record["channel"] == "testing"),
            "Stable/test GitHub release classification mismatch")
    require(release.get("tag_name") == record["tag"], "Release tag mismatch")
    assets = [asset for asset in release.get("assets", []) if asset.get("name") == record["archive_name"]]
    require(len(assets) == 1, "Expected one immutable ZIP release asset")
    asset = assets[0]
    require(asset.get("state") == "uploaded" and asset.get("size") == record["length"] and
            asset.get("browser_download_url") == record["url"], "Release asset metadata mismatch")
    if asset.get("digest"):
        require(asset["digest"] == "sha256:" + record["sha256"], "GitHub asset digest mismatch")
    comparison = json.loads(run(["gh", "api", "repos/" + REPOSITORY + "/compare/" +
                                 record["source_commit"] + "..." + record["tag"]]))
    require(comparison.get("status") in ("identical", "ahead") and comparison.get("behind_by") == 0,
            "Release tag does not contain the recorded build source")
    files = comparison.get("files")
    require(isinstance(files, list) and len(files) < 300, "Cannot fully inspect release-tag source changes")
    allowed_roots = ("docs/", "Casks/", ".github/", "tests/")
    allowed_files = {"README.md", "SETUP-PROMPT.md", "CHANGELOG.md"}
    for changed in files:
        for name in (changed.get("filename", ""), changed.get("previous_filename", changed.get("filename", ""))):
            require(name in allowed_files or name.startswith(allowed_roots),
                    "Release tag changes compiled source or bundled payload after the recorded build")
    return release


def validate(args):
    record = load_candidate(args.candidate, args.public_key, args.channel)
    if args.archive:
        validate_archive(args.archive, record)
    if args.online:
        github_release(record)
        with tempfile.TemporaryDirectory(prefix="nodebay-hosted-check-") as directory:
            downloaded = Path(directory) / record["archive_name"]
            download_archive(record, downloaded)
            validate_archive(downloaded, record)
    if args.hosted_feed:
        request = urllib.request.Request(feed_url(args.channel), headers={
            "User-Agent": "Nodebay-release-verifier", "Cache-Control": "no-cache"})
        opener = urllib.request.build_opener(HTTPSOnlyRedirect())
        with opener.open(request, timeout=60) as response:
            require(response.status == 200, "Hosted feed did not return HTTP 200")
            data = response.read(MAX_FEED_BYTES + 1)
        require(0 < len(data) <= MAX_FEED_BYTES, "Hosted feed size outside allowed range")
        with tempfile.TemporaryDirectory(prefix="nodebay-hosted-feed-") as directory:
            hosted = Path(directory) / "appcast.xml"
            hosted.write_bytes(data)
            require(inspect_feed(hosted, args.public_key, args.channel) == record,
                    "Hosted feed is different or still cached; publication verification is incomplete")
    print("Signed feed and requested archive checks passed")


def publish(args):
    candidate = Path(args.candidate).resolve()
    record, feed_bytes = load_candidate_snapshot(candidate, args.public_key, args.channel)
    github_release(record)
    with tempfile.TemporaryDirectory(prefix="nodebay-feed-publish-") as directory:
        temporary = Path(directory)
        downloaded = temporary / record["archive_name"]
        download_archive(record, downloaded)
        validate_archive(downloaded, record)
        checkout = temporary / "updates"
        checkout.mkdir()
        run(["git", "init", "--quiet", checkout])
        run(["git", "remote", "add", "origin", REMOTE], cwd=checkout)
        ref = "refs/heads/" + BRANCH
        remote_ref = run(["git", "ls-remote", "--heads", "origin", ref], cwd=checkout).strip()
        if remote_ref:
            run(["git", "fetch", "--quiet", "origin", ref], cwd=checkout)
            run(["git", "checkout", "--quiet", "-b", BRANCH, "FETCH_HEAD"], cwd=checkout)
        else:
            require(args.bootstrap, "Feed branch is absent; explicit --bootstrap required")
            run(["git", "checkout", "--quiet", "--orphan", BRANCH], cwd=checkout)
        channel_dir = checkout / args.channel
        manifest_path = channel_dir / "manifest.json"
        require(not channel_dir.is_symlink() and not manifest_path.is_symlink() and
                not (channel_dir / "appcast.xml").is_symlink(), "Feed paths must not be symlinks")
        require(not manifest_path.exists() or manifest_path.stat().st_size <= MAX_FEED_BYTES,
                "Publication history exceeds the supported size")
        previous = json.loads(manifest_path.read_text()) if manifest_path.exists() else None
        if previous:
            old_record = inspect_feed(channel_dir / "appcast.xml", args.public_key, args.channel)
            require(previous.get("releases", [None])[-1] == old_record,
                    "Published feed/history do not agree")
        else:
            require(not (channel_dir / "appcast.xml").exists(), "Existing feed has no release history")
        current = previous["releases"][-1]["build"] if previous else 0
        require(current == args.expected_current_build, "Published build changed; review before retry")
        manifest = next_manifest(previous, record)
        if not args.publish:
            print("Publication dry run passed; no Git commit or push performed")
            return
        channel_dir.mkdir(exist_ok=True)
        # Recheck the release metadata immediately before publication. The archive
        # bytes themselves were authenticated above; no credentials reach the CDN.
        github_release(record)
        # Publish exactly the bytes authenticated before the network operations,
        # even if the caller edits/replaces the candidate while those run.
        (channel_dir / "appcast.xml").write_bytes(feed_bytes)
        require(inspect_feed(channel_dir / "appcast.xml", args.public_key, args.channel) == record,
                "Staged publication differs from authenticated candidate")
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
        for setting in ("user.name", "user.email"):
            identity = run(["git", "config", "--get", setting], cwd=ROOT).strip()
            require(bool(identity), "Configure the release repository Git identity before publishing")
            run(["git", "config", setting, identity], cwd=checkout)
        run(["git", "add", "--", args.channel + "/appcast.xml", args.channel + "/manifest.json"], cwd=checkout)
        run(["git", "commit", "--quiet", "-m", "Publish Nodebay " + record["version"] +
             " (" + str(record["build"]) + ") " + args.channel + " update"], cwd=checkout)
        commit = run(["git", "rev-parse", "HEAD"], cwd=checkout).strip()
        # This normal fast-forward push atomically publishes both files. A race
        # is rejected rather than force-overwriting another release's feed.
        run(["git", "push", "origin", "HEAD:" + ref], cwd=checkout)
        print("Published signed feed commit " + commit + ": " + feed_url(args.channel))
        print("Allow raw GitHub cache propagation, then independently fetch/verify the hosted feed.")


def parser():
    main = argparse.ArgumentParser(description=__doc__)
    commands = main.add_subparsers(dest="command", required=True)
    create = commands.add_parser("prepare", help="Generate and sign a new local candidate; never publish")
    create.add_argument("--archive", required=True)
    create.add_argument("--version", required=True)
    create.add_argument("--build", required=True, type=int)
    create.add_argument("--source-commit", required=True)
    create.add_argument("--sparkle-bin", required=True)
    keys = create.add_mutually_exclusive_group(required=True)
    keys.add_argument("--key-file")
    keys.add_argument("--keychain-account")
    create.add_argument("--notes", help="Plain-text/Markdown notes to embed and sign")
    create.add_argument("--output", required=True, help="New directory for appcast.xml and release.json")
    check = commands.add_parser("validate", help="Public-key-only feed/archive validation")
    check.add_argument("--candidate", required=True)
    check.add_argument("--archive")
    check.add_argument("--online", action="store_true", help="Verify public GitHub release and anonymous bytes")
    check.add_argument("--hosted-feed", action="store_true", help="Require the stable/test HTTPS feed to match exactly")
    upload = commands.add_parser("publish", help="Validate online and optionally atomically publish feed")
    upload.add_argument("--candidate", required=True)
    upload.add_argument("--expected-current-build", required=True, type=int, help="0 for the first channel release")
    upload.add_argument("--bootstrap", action="store_true", help="Allow creating the absent updates branch")
    upload.add_argument("--publish", action="store_true", help="Actually commit/push; otherwise read-only dry run")
    for command in (create, check, upload):
        command.add_argument("--public-key", required=True, help="Pinned application public key, never a private key")
        command.add_argument("--channel", choices=("stable", "testing"), required=True)
    return main


def main():
    args = parser().parse_args()
    try:
        {"prepare": prepare, "validate": validate, "publish": publish}[args.command](args)
    except (FeedError, OSError, ValueError, zipfile.BadZipFile, subprocess.TimeoutExpired) as error:
        print("Nodebay appcast: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
