"""Real Ed25519 and failure-path checks, using a public RFC 8032 test key only."""

import base64
import argparse
import copy
import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("nodebay_appcast", ROOT / "scripts/nodebay_appcast.py")
feed = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(feed)

# Deliberately public RFC 8032 section 7.1 test vector, never a release key.
TEST_SEED = bytes.fromhex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")
TEST_PUBLIC = base64.b64encode(bytes.fromhex(
    "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")).decode()


class ManifestTests(unittest.TestCase):
    def record(self, version="1.2.1", build=28, channel="stable"):
        tag, name, url = feed.release_identity(version, build, channel)
        return {"version": version, "build": build, "channel": channel, "tag": tag,
                "archive_name": name, "url": url, "public_key": TEST_PUBLIC}

    def test_first_release_and_strict_increase_preserve_history(self):
        old = feed.next_manifest(None, self.record())
        snapshot = copy.deepcopy(old)
        new = feed.next_manifest(old, self.record("1.2.2", 29))
        self.assertEqual(old, snapshot)
        self.assertEqual(new["releases"][:-1], old["releases"])
        self.assertEqual(len(new["releases"]), 2)

    def test_rollback_replacement_reused_url_and_key_rotation_rejected(self):
        previous = feed.next_manifest(None, self.record())
        candidates = [self.record("1.2.2", 28), self.record("1.2.2", 27),
                      self.record("1.2.0", 29), self.record("1.2.1", 29)]
        rotated = self.record("1.2.2", 29)
        rotated["public_key"] = "different"
        candidates.append(rotated)
        for record in candidates:
            with self.subTest(record=record), self.assertRaises(feed.FeedError):
                feed.next_manifest(previous, record)

    def test_test_asset_and_feed_addresses_cannot_match_stable(self):
        stable = self.record()
        testing = self.record(channel="testing")
        self.assertNotEqual(stable["url"], testing["url"])
        self.assertNotEqual(feed.feed_url("stable"), feed.feed_url("testing"))
        with self.assertRaises(feed.FeedError):
            feed.next_manifest(feed.next_manifest(None, stable), testing)

    def test_upstream_or_injected_version_is_rejected(self):
        for version in ("../main", "1.2.1-beta", "1.2.1/asset", "$(id)"):
            with self.subTest(version=version), self.assertRaises(feed.FeedError):
                self.record(version)


@unittest.skipUnless(sys.platform == "darwin" and shutil.which("xcrun"), "Requires macOS CryptoKit")
class SignatureAndDownloadTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="nodebay-feed-tests-")
        cls.root = Path(cls.temporary.name)
        source = cls.root / "FixtureSigner.swift"
        source.write_text('''import CryptoKit
import Foundation
let hex = "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
let chars = Array(hex)
let seed = Data(stride(from: 0, to: chars.count, by: 2).map {
    UInt8(String(chars[$0...($0+1)]), radix: 16)!
})
let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
print(try key.signature(for: data).base64EncodedString())
''')
        cls.signer = cls.root / "sign-fixture"
        subprocess.run(["xcrun", "swiftc", str(source), "-o", str(cls.signer)],
                       check=True, capture_output=True)
        feed.signature_verifier()

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def setUp(self):
        self.temporary_case = tempfile.TemporaryDirectory(dir=self.root)
        self.addCleanup(self.temporary_case.cleanup)
        self.directory = Path(self.temporary_case.name)
        self.payload = self.directory / "Nodebay-1.2.1-arm64.zip"
        self.payload.write_bytes(b"Non-executable signed update fixture\n")
        self.record = {"version": "1.2.1", "build": 28, "channel": "stable",
                       "length": self.payload.stat().st_size, "sha256": feed.sha256(self.payload),
                       "public_key": TEST_PUBLIC, "ed_signature": self.sign(self.payload),
                       "source_commit": "a" * 40}
        tag, name, url = feed.release_identity("1.2.1", 28, "stable")
        self.record.update(tag=tag, archive_name=name, url=url)

    def sign(self, path):
        return subprocess.check_output([str(self.signer), str(path)], text=True).strip()

    def xml(self, mutate=None):
        root = ET.Element("rss", {"version": "2.0"})
        channel = ET.SubElement(root, "channel")
        item = ET.SubElement(channel, "item")
        for name, value in (("version", str(self.record["build"])), ("shortVersionString", self.record["version"]),
                            ("minimumSystemVersion", "15.0.0"), ("hardwareRequirements", "arm64")):
            ET.SubElement(item, "{" + feed.SPARKLE + "}" + name).text = value
        ET.SubElement(item, "enclosure", {"url": self.record["url"],
            "length": str(self.record["length"]), "type": "application/octet-stream",
            "{" + feed.SPARKLE + "}edSignature": self.record["ed_signature"]})
        ET.SubElement(item, "{" + feed.NODEBAY + "}release", {
            "sha256": self.record["sha256"], "sourceCommit": "a" * 40, "channel": "stable"})
        if mutate:
            mutate(root, item)
        return ET.tostring(root, encoding="utf-8", xml_declaration=True)

    def signed_feed(self, content=None):
        path = self.directory / "appcast.xml"
        data = self.xml() if content is None else content
        path.write_bytes(data)
        signature = self.sign(path)
        path.write_bytes(data + feed.SIGNING_PREFIX +
                         f"edSignature: {signature}\nlength: {len(data)}\n-->\n".encode())
        return path

    def test_real_public_key_verification_and_tamper_rejection(self):
        path = self.signed_feed()
        record = feed.inspect_feed(path, TEST_PUBLIC, "stable")
        self.assertEqual(record["build"], 28)
        feed.verify_signature(self.payload, TEST_PUBLIC, record["ed_signature"], record["length"])
        self.payload.write_bytes(self.payload.read_bytes().replace(b"fixture", b"mutated"))
        with self.assertRaises(feed.FeedError):
            feed.verify_signature(self.payload, TEST_PUBLIC, record["ed_signature"], record["length"])
        path.write_bytes(path.read_bytes().replace(b"1.2.1", b"1.2.2"))
        with self.assertRaises(feed.FeedError):
            feed.inspect_feed(path, TEST_PUBLIC, "stable")

    def test_signature_trailer_truncation_append_and_ambiguity_rejected(self):
        path = self.signed_feed()
        data = path.read_bytes()
        for invalid in (data[:-8], data + b"unsigned content", data + feed.SIGNING_PREFIX,
                        data.replace(b"length:", b"badlength:")):
            path.write_bytes(invalid)
            with self.subTest(invalid=invalid[-60:]), self.assertRaises(feed.FeedError):
                feed.inspect_feed(path, TEST_PUBLIC, "stable")

    def test_correctly_signed_but_unsafe_feed_fields_rejected(self):
        cases = [
            lambda root, item: item.find("enclosure").set("url", "https://github.com/upstream/latest.zip"),
            lambda root, item: item.find("enclosure").set("url", self.record["url"].replace("https:", "http:")),
            lambda root, item: item.find("{" + feed.SPARKLE + "}hardwareRequirements").__setattr__("text", "x86_64"),
            lambda root, item: item.find("{" + feed.NODEBAY + "}release").set("channel", "testing"),
            lambda root, item: root.find("channel").append(copy.deepcopy(item)),
            lambda root, item: ET.SubElement(item, "{" + feed.SPARKLE + "}releaseNotesLink"),
        ]
        for mutate in cases:
            with self.subTest(mutation=mutate), self.assertRaises(feed.FeedError):
                feed.inspect_feed(self.signed_feed(self.xml(mutate)), TEST_PUBLIC, "stable")

    def test_enclosure_version_and_installation_overrides_are_rejected(self):
        # Actual Sparkle prioritizes enclosure version over the item child, so
        # accepting these would let a validated build28 be interpreted as27.
        for attribute, value in (("version", "27"), ("shortVersionString", "1.0.0"),
                                 ("installationType", "package"), ("deltaFrom", "27")):
            def mutate(root, item):
                item.find("enclosure").set("{" + feed.SPARKLE + "}" + attribute, value)
            with self.subTest(attribute=attribute), self.assertRaises(feed.FeedError):
                feed.inspect_feed(self.signed_feed(self.xml(mutate)), TEST_PUBLIC, "stable")

    def test_unknown_item_control_and_duplicate_fields_are_rejected(self):
        for name in ("installationType", "criticalUpdate", "minimumAutoupdateVersion", "version"):
            def mutate(root, item):
                ET.SubElement(item, "{" + feed.SPARKLE + "}" + name).text = "27"
            with self.subTest(name=name), self.assertRaises(feed.FeedError):
                feed.inspect_feed(self.signed_feed(self.xml(mutate)), TEST_PUBLIC, "stable")

    def test_manifest_must_match_signed_feed(self):
        path = self.signed_feed()
        record = feed.inspect_feed(path, TEST_PUBLIC, "stable")
        (self.directory / "release.json").write_text(json.dumps(record))
        self.assertEqual(feed.load_candidate(self.directory, TEST_PUBLIC, "stable"), record)
        record["build"] = 999
        (self.directory / "release.json").write_text(json.dumps(record))
        with self.assertRaises(feed.FeedError):
            feed.load_candidate(self.directory, TEST_PUBLIC, "stable")

    def opener(self, data, *, fail=False, advertised=None):
        class Response(io.BytesIO):
            status = 200
            headers = {} if advertised is None else {"Content-Length": advertised}

            def read(self, amount=-1):
                if fail and self.tell():
                    raise ConnectionResetError("fixture interrupted transfer")
                return super().read(min(amount, 5) if fail else amount)

        class Opener:
            def open(self, request, timeout):
                return Response(data)

        return Opener()

    def test_only_complete_authenticated_download_becomes_destination(self):
        destination = self.directory / "verified.zip"
        feed.download_archive(self.record, destination, opener=self.opener(self.payload.read_bytes()))
        self.assertEqual(destination.read_bytes(), self.payload.read_bytes())

    def test_interrupted_truncated_oversized_and_changed_downloads_leave_no_destination(self):
        original = self.payload.read_bytes()
        cases = [self.opener(original, fail=True), self.opener(original[:-1]),
                 self.opener(original + b"x"), self.opener(b"x" * len(original)),
                 self.opener(original, advertised="1")]
        for index, opener in enumerate(cases):
            destination = self.directory / f"invalid-{index}.zip"
            with self.subTest(index=index), self.assertRaises((feed.FeedError, ConnectionResetError)):
                feed.download_archive(self.record, destination, opener=opener)
            self.assertFalse(destination.exists())
        self.assertFalse(list(self.directory.glob("nodebay-download-*")))

    def test_redirect_to_http_rejected(self):
        with self.assertRaises(feed.FeedError):
            feed.HTTPSOnlyRedirect().redirect_request(None, None, 302, "", {}, "http://example.org/file")

    def test_bundle_must_embed_matching_key_feed_and_strict_verification(self):
        info = {"CFBundleIdentifier": "theboringteam.boringnotch", "SUPublicEDKey": TEST_PUBLIC,
                "SUFeedURL": feed.feed_url("stable"), "SURequireSignedFeed": True,
                "SUVerifyUpdateBeforeExtraction": True, "LSMinimumSystemVersion": "15.0",
                "SUSignedFeedFailureExpirationInterval": 0, "SUEnableSystemProfiling": False,
                "SUEnableJavaScript": False}
        for field, wrong in ((None, None), ("SUFeedURL", feed.feed_url("testing")),
                             ("SUPublicEDKey", "another key"), ("SURequireSignedFeed", False),
                             ("SUVerifyUpdateBeforeExtraction", False),
                             ("SUSignedFeedFailureExpirationInterval", 86400),
                             ("SUEnableSystemProfiling", True), ("SUEnableJavaScript", True)):
            candidate = dict(info)
            if field:
                candidate[field] = wrong
            with zipfile.ZipFile(self.payload, "w") as archive:
                archive.writestr("Nodebay.app/Contents/Info.plist", plistlib.dumps(candidate))
            if field:
                with self.subTest(field=field), self.assertRaises(feed.FeedError):
                    feed.archive_metadata(self.payload, TEST_PUBLIC, "stable")
            else:
                self.assertEqual(feed.archive_metadata(self.payload, TEST_PUBLIC, "stable"), info)
                self.assertEqual(feed.archive_metadata(self.payload, TEST_PUBLIC, "testing"), info)

    def test_publication_dry_run_atomic_commit_and_nonfastforward_race(self):
        remote = self.directory / "remote.git"
        subprocess.run(["git", "init", "--quiet", "--bare", str(remote)], check=True, capture_output=True)

        def candidate(name):
            directory = self.directory / name
            directory.mkdir()
            path = self.signed_feed()
            record = feed.inspect_feed(path, TEST_PUBLIC, "stable")
            shutil.copy2(path, directory / "appcast.xml")
            (directory / "release.json").write_text(json.dumps(record))
            return directory

        args = argparse.Namespace(candidate=candidate("candidate-28"), public_key=TEST_PUBLIC,
                                  channel="stable", bootstrap=True, expected_current_build=0, publish=False)
        original_run = feed.run
        inject_race = False
        replace_candidate = False

        def run_fixture(command, **kwargs):
            nonlocal inject_race
            if list(command[:3]) == ["git", "config", "--get"]:
                return "Nodebay Test" if command[3] == "user.name" else "test@example.invalid"
            if inject_race and list(command[:3]) == ["git", "push", "origin"]:
                inject_race = False
                competitor = self.directory / "competitor"
                subprocess.run(["git", "clone", "--quiet", "--branch", "updates", str(remote), str(competitor)],
                               check=True, capture_output=True)
                (competitor / "parallel-change.txt").write_text("Simultaneous publisher fixture\n")
                subprocess.run(["git", "add", "."], cwd=competitor, check=True, capture_output=True)
                subprocess.run(["git", "-c", "user.name=Nodebay Test", "-c", "user.email=test@example.invalid",
                                "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "Concurrent fixture"],
                               cwd=competitor, check=True, capture_output=True)
                subprocess.run(["git", "push", "--quiet", "origin", "updates"], cwd=competitor,
                               check=True, capture_output=True)
            return original_run(command, **kwargs)

        def download_fixture(record, destination):
            shutil.copyfile(self.payload, destination)
            if replace_candidate:
                (args.candidate / "appcast.xml").write_bytes(b"Candidate replaced during download")

        # Only hosting/notarization are substituted. Feed cryptography and the
        # real Git clone/commit/push paths execute against a disposable bare repo.
        with contextlib.redirect_stdout(io.StringIO()), patch.object(feed, "REMOTE", str(remote)), \
             patch.object(feed, "github_release"), patch.object(feed, "download_archive", side_effect=download_fixture), \
             patch.object(feed, "validate_archive"), patch.object(feed, "run", side_effect=run_fixture):
            feed.publish(args)
            refs = subprocess.run(["git", "show-ref"], cwd=remote, capture_output=True)
            self.assertNotEqual(refs.returncode, 0, "Dry run must not create a remote branch")
            args.publish = True
            authenticated_bytes = (args.candidate / "appcast.xml").read_bytes()
            replace_candidate = True
            feed.publish(args)
            replace_candidate = False
            tree = subprocess.check_output(["git", "ls-tree", "-r", "--name-only", "updates"], cwd=remote, text=True)
            self.assertEqual(tree.splitlines(), ["stable/appcast.xml", "stable/manifest.json"])
            published = subprocess.check_output(["git", "show", "updates:stable/appcast.xml"], cwd=remote)
            self.assertEqual(published, authenticated_bytes)
            self.assertNotEqual(published, (args.candidate / "appcast.xml").read_bytes())
            self.record.update(version="1.2.2", build=29)
            tag, name, url = feed.release_identity("1.2.2", 29, "stable")
            self.record.update(tag=tag, archive_name=name, url=url)
            args.candidate = candidate("candidate-29")
            args.expected_current_build = 28
            inject_race = True
            with self.assertRaises(feed.FeedError):
                feed.publish(args)
            after = subprocess.check_output(["git", "show", "updates:stable/appcast.xml"], cwd=remote)
            self.assertEqual(after, published, "Race must preserve previously published feed")

    def test_github_draft_prerelease_and_changed_asset_rejected(self):
        release = {"draft": False, "prerelease": False, "tag_name": self.record["tag"],
                   "assets": [{"name": self.record["archive_name"], "state": "uploaded",
                               "size": self.record["length"], "browser_download_url": self.record["url"],
                               "digest": "sha256:" + self.record["sha256"]}]}
        identical = {"status": "identical", "behind_by": 0, "files": []}
        with patch.object(feed, "run", side_effect=[json.dumps(release), json.dumps(identical)]):
            feed.github_release(self.record)
        for field in ("draft", "prerelease"):
            invalid = dict(release, **{field: True})
            with patch.object(feed, "run", return_value=json.dumps(invalid)), self.assertRaises(feed.FeedError):
                feed.github_release(self.record)
        release["assets"][0]["digest"] = "sha256:" + "0" * 64
        with patch.object(feed, "run", return_value=json.dumps(release)), self.assertRaises(feed.FeedError):
            feed.github_release(self.record)

    def test_release_tag_may_add_docs_but_not_change_compiled_source(self):
        release = {"draft": False, "prerelease": False, "tag_name": self.record["tag"],
                   "assets": [{"name": self.record["archive_name"], "state": "uploaded",
                               "size": self.record["length"], "browser_download_url": self.record["url"]}]}
        for path, accepted in (("docs/release-notes-1.2.1.md", True),
                               ("boringNotch/boringNotchApp.swift", False),
                               ("third_party/runtime.lock", False)):
            comparison = {"status": "ahead", "behind_by": 0, "files": [{"filename": path}]}
            with patch.object(feed, "run", side_effect=[json.dumps(release), json.dumps(comparison)]):
                if accepted:
                    feed.github_release(self.record)
                else:
                    with self.assertRaises(feed.FeedError):
                        feed.github_release(self.record)

    @unittest.skipUnless(os.environ.get("NODEBAY_SPARKLE_BIN"), "Set NODEBAY_SPARKLE_BIN for pinned Sparkle interoperability")
    def test_actual_sparkle_signer_and_public_verifier_agree(self):
        tool = Path(os.environ["NODEBAY_SPARKLE_BIN"]) / "sign_update"
        self.assertEqual(feed.sha256(tool), feed.TOOLS["sign_update"])
        key_file = self.directory / "public-rfc8032-test-key"
        key_file.write_text(base64.b64encode(TEST_SEED).decode())
        key_file.chmod(0o600)
        path = self.directory / "appcast.xml"
        path.write_bytes(self.xml())
        subprocess.run([str(tool), "--ed-key-file", str(key_file), str(path)],
                       check=True, capture_output=True)
        feed.inspect_feed(path, TEST_PUBLIC, "stable")
        subprocess.run([str(tool), "--ed-key-file", str(key_file), "--verify", str(path)],
                       check=True, capture_output=True)
        signature = subprocess.check_output([str(tool), "--ed-key-file", str(key_file),
                                             "-p", str(self.payload)], text=True).strip()
        feed.verify_signature(self.payload, TEST_PUBLIC, signature, self.payload.stat().st_size)
        path.write_bytes(path.read_bytes().replace(b"1.2.1", b"1.2.2"))
        invalid = subprocess.run([str(tool), "--ed-key-file", str(key_file), "--verify", str(path)],
                                 capture_output=True)
        self.assertNotEqual(invalid.returncode, 0)
        with self.assertRaises(feed.FeedError):
            feed.inspect_feed(path, TEST_PUBLIC, "stable")

    @unittest.skipUnless(os.environ.get("NODEBAY_SPARKLE_BIN"), "Set NODEBAY_SPARKLE_BIN for actual appcast generator")
    def test_actual_generator_prepares_signed_feed_from_bundle_metadata(self):
        # This disposable application only returns zero. Its local ad-hoc
        # signature is intentionally not a production notarization acceptance.
        app = self.directory / "Nodebay.app"
        (app / "Contents/MacOS").mkdir(parents=True)
        source = self.directory / "main.c"
        source.write_text("int main(void) { return 0; }\n")
        subprocess.run(["xcrun", "clang", "-arch", "arm64", "-mmacosx-version-min=15.0",
                        str(source), "-o", str(app / "Contents/MacOS/Nodebay")],
                       check=True, capture_output=True)
        info = {"CFBundleIdentifier": "theboringteam.boringnotch", "CFBundleExecutable": "Nodebay",
                "CFBundleName": "Nodebay", "CFBundlePackageType": "APPL", "CFBundleVersion": "28",
                "CFBundleShortVersionString": "1.2.1", "SUPublicEDKey": TEST_PUBLIC,
                "SUFeedURL": feed.feed_url("stable"), "SURequireSignedFeed": True,
                "SUVerifyUpdateBeforeExtraction": True, "LSMinimumSystemVersion": "15.0",
                "SUSignedFeedFailureExpirationInterval": 0, "SUEnableSystemProfiling": False,
                "SUEnableJavaScript": False}
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True, capture_output=True)
        self.payload.unlink()  # Disposable test fixture, not user material.
        subprocess.run(["ditto", "-c", "-k", "--keepParent", str(app), str(self.payload)],
                       check=True, capture_output=True)
        key = self.directory / "public-rfc8032-test-key"
        key.write_text(base64.b64encode(TEST_SEED).decode())
        key.chmod(0o600)
        output = self.directory / "prepared"
        args = argparse.Namespace(output=output, archive=self.payload, version="1.2.1", build=28,
                                  source_commit="a" * 40, public_key=TEST_PUBLIC, channel="stable",
                                  sparkle_bin=os.environ["NODEBAY_SPARKLE_BIN"], key_file=key,
                                  keychain_account=None, notes=None)
        original_run = feed.run

        def run_fixture(command, **kwargs):
            if Path(command[0]).name == "verify_release_artifact.sh":
                return "Notarization deliberately outside this generator fixture"
            return original_run(command, **kwargs)

        with contextlib.redirect_stdout(io.StringIO()), patch.object(feed, "run", side_effect=run_fixture):
            feed.prepare(args)
        record = feed.load_candidate(output, TEST_PUBLIC, "stable")
        feed.validate_archive(self.payload, record, notarized=False)
        self.assertEqual(record["build"], 28)
        self.assertEqual(record["sha256"], feed.sha256(self.payload))


if __name__ == "__main__":
    unittest.main()
