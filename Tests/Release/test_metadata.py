#!/usr/bin/env python3
"""Check release metadata with disposable synthetic archives, never app data."""

import base64
import hashlib
import importlib.util
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile


SCRIPT = Path(__file__).resolve().parents[2] / "scripts/release-metadata.py"
SPEC = importlib.util.spec_from_file_location("chit_release_metadata", SCRIPT)
metadata = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(metadata)
SIGNATURE = base64.b64encode(bytes(range(64))).decode("ascii")
PUBLISHED_AT = "2026-10-01T12:34:56Z"
NAMESPACES = {"sparkle": metadata.SPARKLE_NAMESPACE, "atom": metadata.ATOM_NAMESPACE}


class ReleaseMetadata(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="chit-release-metadata-")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.archive = self.root / "Chit-1.2.3.zip"
        self.output = self.root / "metadata"
        self.make_archive()

    def make_archive(self, payload=b"synthetic command"):
        with zipfile.ZipFile(self.archive, "w") as archive:
            archive.writestr("Chit.app/Contents/Resources/bin/chit", payload)

    def generate(self, **overrides):
        args = {
            "version": "1.2.3", "archive": self.archive, "signature": SIGNATURE,
            "repository": "dankhole/chit", "output_directory": self.output,
            "published_at": PUBLISHED_AT,
        }
        args.update(overrides)
        return metadata.generate(**args)

    def test_appcast_has_exact_archive_signature_version_and_release_links(self):
        appcast_path, _ = self.generate()
        root = ET.parse(appcast_path).getroot()
        self.assertEqual(root.attrib, {"version": "2.0"})
        self.assertEqual(len(root.findall("channel/item")), 1)
        item = root.find("channel/item")
        self.assertEqual(item.findtext("sparkle:version", namespaces=NAMESPACES), "1.2.3")
        self.assertEqual(item.findtext("sparkle:shortVersionString", namespaces=NAMESPACES), "1.2.3")
        self.assertEqual(item.findtext("sparkle:minimumSystemVersion", namespaces=NAMESPACES), "14.0.0")
        self.assertEqual(item.findtext("sparkle:releaseNotesLink", namespaces=NAMESPACES),
                         "https://github.com/dankhole/chit/releases/tag/v1.2.3")
        self.assertEqual(item.findtext("pubDate"), "Thu, 01 Oct 2026 12:34:56 GMT")
        enclosure = item.find("enclosure")
        self.assertEqual(enclosure.get("url"),
                         "https://github.com/dankhole/chit/releases/download/v1.2.3/Chit-1.2.3.zip")
        self.assertEqual(enclosure.get("length"), str(self.archive.stat().st_size))
        self.assertEqual(enclosure.get(f"{{{metadata.SPARKLE_NAMESPACE}}}edSignature"), SIGNATURE)
        self.assertEqual(enclosure.get(f"{{{metadata.SPARKLE_NAMESPACE}}}os"), "macos")
        self.assertEqual(enclosure.get("type"), "application/octet-stream")
        feed = root.find("channel/atom:link", NAMESPACES)
        self.assertEqual(feed.get("href"), "https://github.com/dankhole/chit/releases/latest/download/appcast.xml")
        self.assertIsNone(item.find("sparkle:deltas", NAMESPACES))

    def test_cask_pins_actual_checksum_and_installs_app_and_cli(self):
        _, cask_path = self.generate()
        cask = cask_path.read_text()
        checksum = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        self.assertIn('version "1.2.3"', cask)
        self.assertIn(f'sha256 "{checksum}"', cask)
        self.assertIn('url "https://github.com/dankhole/chit/releases/download/v1.2.3/Chit-1.2.3.zip"', cask)
        self.assertIn('app "Chit.app"', cask)
        self.assertIn('binary "#{appdir}/Chit.app/Contents/Resources/bin/chit"', cask)
        self.assertIn("auto_updates true", cask)
        self.assertIn("depends_on macos: :sonoma", cask)
        self.assertNotIn("@VERSION@", cask)
        self.assertNotIn("@SHA256@", cask)
        self.assertNotIn(":no_check", cask)
        self.assertNotIn(":latest", cask)
        self.assertNotIn("zap", cask)

    def test_repacked_archive_recomputes_checksum_and_length(self):
        first_appcast, first_cask = self.generate()
        first_checksum = first_cask.read_text()
        first_length = ET.parse(first_appcast).find("channel/item/enclosure").get("length")
        self.make_archive(b"synthetic stapled and repacked payload with changed bytes")
        second_appcast, second_cask = self.generate()
        self.assertNotEqual(second_cask.read_text(), first_checksum)
        self.assertIn(hashlib.sha256(self.archive.read_bytes()).hexdigest(), second_cask.read_text())
        second_length = ET.parse(second_appcast).find("channel/item/enclosure").get("length")
        self.assertNotEqual(second_length, first_length)
        self.assertEqual(second_length, str(self.archive.stat().st_size))

    def test_distribution_repository_controls_every_external_link(self):
        appcast_path, cask_path = self.generate(repository="dankhole/chit-releases")
        for path in (appcast_path, cask_path):
            text = path.read_text()
            self.assertIn("https://github.com/dankhole/chit-releases", text)
            self.assertNotIn("https://github.com/dankhole/chit/", text)

    def test_timestamp_offset_normalizes_to_utc(self):
        appcast_path, _ = self.generate(published_at="2026-10-01T08:34:56-04:00")
        self.assertEqual(ET.parse(appcast_path).findtext("channel/item/pubDate"),
                         "Thu, 01 Oct 2026 12:34:56 GMT")

    def test_invalid_versions_cannot_inject_xml_or_ruby(self):
        for version in ("v1.2.3", "1.2", "01.2.3", "1.02.3", "1.2.03", "1.2.3-beta.1",
                        "1.2.3+4", "1.2.3\n", '1.2.3"><evil/>', '1.2.3"; system("id")'):
            with self.subTest(version=version), self.assertRaisesRegex(ValueError, "version"):
                self.generate(version=version)
        self.assertFalse(self.output.exists())

    def test_invalid_repositories_cannot_inject_urls_xml_or_ruby(self):
        for repository in ("https://github.com/dankhole/chit", "dankhole", "dankhole/chit/extra",
                           "dankhole/chit?x=y&z=1", "dankhole/chit#fragment", 'dankhole/chit"',
                           "dankhole/#{system('id')}", "dankhole/chit\n", "-dankhole/chit",
                           "dank--hole/chit", "dankhole/../chit", "dankhole/chit\\evil"):
            with self.subTest(repository=repository), self.assertRaisesRegex(ValueError, "repository"):
                self.generate(repository=repository)
        self.assertFalse(self.output.exists())

    def test_invalid_signatures_are_rejected_before_writing(self):
        invalid = ("", "not base64", SIGNATURE + "\n", SIGNATURE[:-2],
                   base64.b64encode(b"short").decode("ascii"), SIGNATURE + "==",
                   SIGNATURE[:-3] + "x==", '"/><evil/>', "é")
        for signature in invalid:
            with self.subTest(signature=signature), self.assertRaisesRegex(ValueError, "signature"):
                self.generate(signature=signature)
        self.assertFalse(self.output.exists())

    def test_invalid_dates_are_rejected_before_writing(self):
        for published_at in ("2026-10-01", "2026-10-01T12:34:56", "2026-13-01T12:34:56Z",
                             "2026-10-01T12:34:56Z\n", "Thu, 01 Oct 2026 12:34:56 GMT"):
            with self.subTest(published_at=published_at), self.assertRaisesRegex(ValueError, "published-at"):
                self.generate(published_at=published_at)
        self.assertFalse(self.output.exists())

    def test_missing_empty_and_mismatched_archives_are_rejected(self):
        for archive in (self.root / "missing/Chit-1.2.3.zip", self.root / "Chit-2.0.0.zip", self.root):
            with self.subTest(archive=archive), self.assertRaisesRegex(ValueError, "archive"):
                self.generate(archive=archive)
        self.archive.write_bytes(b"")
        with self.assertRaisesRegex(ValueError, "empty"):
            self.generate()
        self.assertFalse(self.output.exists())

    def test_cli_generates_expected_output_files(self):
        result = subprocess.run([
            sys.executable, str(SCRIPT), "--version", "1.2.3", "--archive", str(self.archive),
            "--signature", SIGNATURE, "--repository", "dankhole/chit", "--output-directory",
            str(self.output), "--published-at", PUBLISHED_AT,
        ], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), [str(self.output / "appcast.xml"), str(self.output / "chit.rb")])

    def test_cli_failure_is_actionable_and_does_not_create_metadata(self):
        result = subprocess.run([
            sys.executable, str(SCRIPT), "--version", "1.2.3-beta", "--archive", str(self.archive),
            "--signature", SIGNATURE, "--repository", "dankhole/chit", "--output-directory", str(self.output),
        ], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("stable X.Y.Z", result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertFalse(self.output.exists())

    @unittest.skipUnless(shutil.which("ruby"), "Ruby is unavailable")
    def test_generated_cask_parses_as_ruby(self):
        _, cask_path = self.generate()
        result = subprocess.run(["ruby", "-c", str(cask_path)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Syntax OK", result.stdout)


if __name__ == "__main__":
    unittest.main()
