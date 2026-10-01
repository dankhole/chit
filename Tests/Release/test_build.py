#!/usr/bin/env python3
"""Release preflight checks; never compile, sign, download, or launch an app."""

import argparse
import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


REPO = Path(__file__).resolve().parents[2]


def load_script(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), REPO / "scripts" / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


builder = load_script("release-build")
fetcher = load_script("fetch-sparkle")
PUBLIC_KEY = base64.b64encode(bytes(range(1, 33))).decode("ascii")  # Synthetic public-key fixture only.
FEED = "https://github.com/dankhole/chit/releases/latest/download/appcast.xml"
CERTIFICATE = "A" * 40
IDENTITY = "Developer ID Application: Test Publisher (TEST123456)"


def options(**changes):
    values = dict(version="1.2.3", feed_url=FEED, public_ed_key=PUBLIC_KEY,
                  signing_identity=None, ad_hoc=True, sparkle_archive=None)
    values.update(changes)
    return argparse.Namespace(**values)


class ReleasePreflightTests(unittest.TestCase):
    def test_ad_hoc_preflight_does_not_require_an_apple_identity(self):
        with patch.object(builder, "run") as command:
            builder.validate_options(options())
            command.assert_not_called()

    def test_distribution_info_verifies_archives_before_extraction_in_both_signing_modes(self):
        for identity in (None, CERTIFICATE):
            with self.subTest(identity=identity):
                info = builder.distribution_info(options(signing_identity=identity, ad_hoc=identity is None))
                self.assertIs(info["SUVerifyUpdateBeforeExtraction"], True)
                self.assertEqual(info["SUPublicEDKey"], PUBLIC_KEY)
                self.assertEqual(info["SUFeedURL"], FEED)
                self.assertEqual(info["CFBundleIdentifier"], "local.dcole.TotTodo")
                self.assertEqual(info["CFBundleVersion"], "1.2.3")
                self.assertEqual(info["CFBundleShortVersionString"], "1.2.3")
                self.assertNotIn("SUEnableAutomaticChecks", info)
                self.assertNotIn("SUAutomaticallyUpdate", info)

    def test_invalid_public_inputs_fail_before_build_outputs_or_commands(self):
        invalid = [
            dict(version="v1.2.3"), dict(version="1.2.3-beta.1"), dict(version="01.2.3"),
            dict(feed_url="http://github.com/dankhole/chit/releases/latest/download/appcast.xml"),
            dict(feed_url="https://account:password@github.com/appcast.xml"),
            dict(feed_url="https://example.com/appcast.xml"),
            dict(feed_url="https://127.0.0.1/appcast.xml"),
            dict(public_ed_key="not a key"), dict(public_ed_key=base64.b64encode(bytes(32)).decode()),
            dict(public_ed_key=base64.b64encode(bytes(31)).decode()),
        ]
        with tempfile.TemporaryDirectory(prefix="chit-release-preflight-") as temporary:
            output = Path(temporary) / "release"
            for changes in invalid:
                with self.subTest(changes=changes), patch.object(builder, "OUT", output), patch.object(builder, "run") as command:
                    with self.assertRaises(ValueError):
                        builder.build(options(**changes))
                    command.assert_not_called()
                    self.assertFalse(output.exists())

    def test_signing_mode_must_be_explicit(self):
        arguments = ["release-build.py", "--version", "1.2.3", "--feed-url", FEED, "--public-ed-key", PUBLIC_KEY]
        with patch.object(sys, "argv", arguments), patch.object(builder, "build") as build:
            with self.assertRaises(SystemExit) as failure:
                builder.main()
            self.assertEqual(failure.exception.code, 2)
            build.assert_not_called()

    def test_certificate_must_be_a_valid_developer_id_identity(self):
        identities = f'  1) {CERTIFICATE} "Apple Development: Test Publisher (TEST123456)"\n'
        with patch.object(builder, "run", return_value=subprocess.CompletedProcess([], 0, stdout=identities)):
            with self.assertRaisesRegex(ValueError, "Developer ID"):
                builder.validate_options(options(signing_identity=CERTIFICATE, ad_hoc=False))

    def test_developer_id_accepts_certificate_hash_or_full_name(self):
        identities = f'  1) {CERTIFICATE} "{IDENTITY}"\n'
        with patch.object(builder, "run", return_value=subprocess.CompletedProcess([], 0, stdout=identities)):
            for identity in (CERTIFICATE.lower(), IDENTITY):
                builder.validate_options(options(signing_identity=identity, ad_hoc=False))

    def test_developer_id_signature_requires_runtime_timestamp_and_authority(self):
        complete = "Authority=Developer ID Application: Test Publisher\nflags=0x10000(runtime)\nTimestamp=Oct 1 2026\nTeamIdentifier=TEST123456\n"
        failures = [complete.replace("Developer ID Application", "Apple Development"),
                    complete.replace("flags=0x10000(runtime)\n", ""),
                    complete.replace("Timestamp=Oct 1 2026\n", "")]
        for details in failures:
            with self.subTest(details=details), patch.object(builder, "run", return_value=subprocess.CompletedProcess([], 0, stderr=details)):
                with self.assertRaisesRegex(ValueError, "signature"):
                    builder.sign(Path("validation.app"), options(signing_identity=CERTIFICATE, ad_hoc=False))


class SparkleDependencyGuards(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="chit-release-dependency-")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name).resolve()
        self.repo = self.root / "checkout"
        (self.repo / "config").mkdir(parents=True)
        self.dependencies = self.repo / "build/release/dependencies"
        self.dependencies.mkdir(parents=True)
        self.outside = self.root / "untouched"
        self.outside.mkdir()
        self.sentinel = self.outside / "sentinel"
        self.sentinel.write_text("Keep this file")
        self.lock = {"version": "2.10.0", "sha256": hashlib.sha256(b"verified fixture bytes").hexdigest(),
                     "url": "https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz"}
        (self.repo / "config/sparkle.json").write_text(json.dumps(self.lock))
        for name, value in (("REPO", self.repo), ("DEPENDENCIES", self.dependencies)):
            override = patch.object(fetcher, name, value)
            override.start()
            self.addCleanup(override.stop)
        command = patch.object(fetcher.subprocess, "run", side_effect=AssertionError("Must not download"))
        command.start()
        self.addCleanup(command.stop)

    def test_checksum_failure_preserves_existing_dependency(self):
        cached = self.dependencies / "Sparkle-2.10.0.tar.xz"
        cached.write_bytes(b"corrupted archive")
        destination = self.dependencies / "sparkle"
        destination.mkdir()
        existing = destination / "installed-framework-sentinel"
        existing.write_text("Existing verified dependency")
        with self.assertRaisesRegex(ValueError, "checksum"):
            fetcher.fetch()
        self.assertEqual(existing.read_text(), "Existing verified dependency")

    def test_cached_archive_symlink_is_rejected_without_following_target(self):
        (self.dependencies / "Sparkle-2.10.0.tar.xz").symlink_to(self.sentinel)
        with self.assertRaisesRegex(ValueError, "symbolic link"):
            fetcher.fetch()
        self.assertEqual(self.sentinel.read_text(), "Keep this file")

    def test_dependency_symlink_is_rejected_before_extraction(self):
        (self.dependencies / "Sparkle-2.10.0.tar.xz").write_bytes(b"verified fixture bytes")
        (self.dependencies / "sparkle").symlink_to(self.outside, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symbolic link"):
            fetcher.fetch()
        self.assertEqual(list(self.outside.iterdir()), [self.sentinel])

    def test_redirected_output_directory_is_rejected(self):
        redirected = self.repo / "redirected"
        redirected.symlink_to(self.outside, target_is_directory=True)
        with patch.object(fetcher, "DEPENDENCIES", redirected / "dependencies"):
            with self.assertRaisesRegex(ValueError, "symbolic link"):
                fetcher.fetch()
        self.assertEqual(list(self.outside.iterdir()), [self.sentinel])


if __name__ == "__main__":
    unittest.main()
