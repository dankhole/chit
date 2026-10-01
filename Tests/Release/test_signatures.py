"""Verify the helper with RFC 8032's public test vector; no personal keys."""
import base64
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SEED = bytes.fromhex('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60')
PUBLIC = bytes.fromhex('d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a')
SIGNATURE = bytes.fromhex(
    'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155'
    '5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b')
ENCODED_PUBLIC = base64.b64encode(PUBLIC).decode()
ENCODED_SIGNATURE = base64.b64encode(SIGNATURE).decode()


@unittest.skipUnless(sys.platform == 'darwin' and shutil.which('xcrun'), 'CryptoKit helper requires macOS Swift')
class SparkleMaterialVerification(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix='chit-signature-tests-')
        cls.root = Path(cls.directory.name)
        cls.tool = cls.root / 'verify'
        result = subprocess.run(['xcrun', 'swiftc', str(ROOT / 'scripts/release-verify.swift'),
                                 '-o', str(cls.tool), '-module-cache-path', str(cls.root / 'cache')],
                                capture_output=True, text=True, timeout=120)
        if result.returncode:
            cls.directory.cleanup()
            raise RuntimeError('CryptoKit fixture helper compilation failed: ' + result.stderr)

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def check_key(self, secret, public=ENCODED_PUBLIC):
        key = self.root / 'fixture.key'
        key.write_text(base64.b64encode(secret).decode() + '\n')
        return subprocess.run([str(self.tool), 'key', str(key), public], capture_output=True, text=True)

    def check_archive(self, content, signature=ENCODED_SIGNATURE, public=ENCODED_PUBLIC):
        archive = self.root / 'fixture.zip'
        archive.write_bytes(content)
        return subprocess.run([str(self.tool), 'archive', str(archive), signature, public], capture_output=True, text=True)

    def test_current_seed_derives_configured_public_key(self):
        self.assertEqual(self.check_key(SEED).returncode, 0)

    def test_current_seed_mismatch_fails_without_printing_seed(self):
        result = self.check_key(SEED, base64.b64encode(bytes(32)).decode())
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(base64.b64encode(SEED).decode(), result.stdout + result.stderr)

    def test_legacy_key_public_halves_are_checked(self):
        # These test the legacy public-half precheck, not Sparkle's private-half
        # parsing. Final signature verification proves the actual signing key.
        for exported in (SEED + PUBLIC, bytes(64) + PUBLIC):
            with self.subTest(length=len(exported)):
                self.assertEqual(self.check_key(exported).returncode, 0)
                self.assertNotEqual(self.check_key(exported, base64.b64encode(bytes(32)).decode()).returncode, 0)

    def test_rfc_archive_signature_verifies_with_configured_public(self):
        self.assertEqual(self.check_archive(b'').returncode, 0)

    def test_modified_archive_signature_fails(self):
        self.assertNotEqual(self.check_archive(b'changed bytes').returncode, 0)

    def test_signature_for_different_public_key_fails(self):
        self.assertNotEqual(self.check_archive(b'', public=base64.b64encode(bytes(32)).decode()).returncode, 0)

    def test_malformed_signature_fails(self):
        self.assertNotEqual(self.check_archive(b'', signature='invalid').returncode, 0)


if __name__ == '__main__':
    unittest.main()
