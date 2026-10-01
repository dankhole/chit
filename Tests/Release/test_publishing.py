"""Focused publication guards using an in-memory API; never contacts GitHub."""
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('release_publish', ROOT / 'scripts/release-publish.py')
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class FakeGitHub:
    repository = 'owner/public-releases'

    def __init__(self):
        self.private = False
        self.rows = []
        self.uploaded = []
        self.mutations = []
        self.bad_digest = False

    def releases(self):
        yield from self.rows

    def request(self, route, *, method='GET', data=None, missing_ok=False, upload_url=None, **kwargs):
        if method != 'GET':
            self.mutations.append((method, route, data))
        if route == '':
            return {'private': self.private, 'default_branch': 'main'}
        if route == '/git/ref/heads/main':
            return {'object': {'sha': 'abc'}}
        if method == 'POST' and route == '/releases':
            release = dict(data, id=10, html_url='https://github.com/owner/public-releases/releases/tag/v1.0.1',
                           upload_url='https://uploads.github.com/repos/owner/public-releases/releases/10/assets{?name,label}')
            self.rows.append(release)
            return release
        if upload_url:
            from urllib.parse import parse_qs, urlparse
            name = parse_qs(urlparse(upload_url).query)['name'][0]
            asset = {'name': name, 'size': len(data), 'state': 'uploaded',
                     'digest': 'sha256:' + ('0' * 64 if self.bad_digest else hashlib.sha256(data).hexdigest())}
            self.uploaded.append(asset)
            return asset
        if route == '/releases/10/assets?per_page=100':
            return self.uploaded
        if method == 'PATCH' and route == '/releases/10':
            self.rows[0].update(data)
            return self.rows[0]
        if route == '/releases/latest':
            return self.rows[0]
        raise AssertionError(f'Unexpected fake API request: {method} {route}')


class PublicationGuards(unittest.TestCase):
    def setUp(self):
        self.api = FakeGitHub()
        self.quiet = contextlib.redirect_stdout(io.StringIO())
        self.quiet.__enter__()

    def tearDown(self):
        self.quiet.__exit__(None, None, None)

    def fixture(self, root, **receipt_changes):
        archive = root / 'Chit-1.0.1.zip'
        archive.write_bytes(b'synthetic verified archive')
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        archive.with_suffix('.zip.sha256').write_text(f'{digest}  {archive.name}\n')
        (root / 'metadata').mkdir()
        (root / 'metadata/appcast.xml').write_text('<rss/>\n')
        (root / 'metadata/chit.rb').write_text('cask "chit" do\nend\n')
        receipt = {'signed': True, 'notarized': True, 'stapled': True,
                   'version': '1.0.1', 'architectures': ['arm64', 'x86_64'],
                   'feed_url': 'https://github.com/owner/public-releases/releases/latest/download/appcast.xml'}
        receipt.update(receipt_changes)
        (root / 'build.json').write_text(json.dumps(receipt))

    def release(self, tag='v1.0.1', *, draft=False, prerelease=False):
        return {'tag_name': tag, 'id': 1, 'draft': draft, 'prerelease': prerelease}

    def test_private_destination_fails_without_mutations(self):
        self.api.private = True
        with self.assertRaisesRegex(ValueError, 'private'):
            publisher.preflight(self.api, '1.0.1')
        self.assertEqual(self.api.mutations, [])

    def test_first_version_must_advance_existing_install(self):
        with self.assertRaisesRegex(ValueError, 'newer than 1.0.0'):
            publisher.preflight(self.api, '1.0.0')

    def test_existing_draft_and_published_version_refused(self):
        for draft in (False, True):
            with self.subTest(draft=draft):
                self.api.rows = [self.release(draft=draft)]
                with self.assertRaisesRegex(ValueError, 'already has'):
                    publisher.preflight(self.api, '1.0.1')

    def test_newer_release_blocks_latest_regression(self):
        self.api.rows = [self.release('v1.1.0')]
        with self.assertRaisesRegex(ValueError, 'newer'):
            publisher.preflight(self.api, '1.0.1')

    def test_stable_nonsemver_release_requires_reconciliation(self):
        self.api.rows = [self.release('preview')]
        with self.assertRaisesRegex(ValueError, 'not vMAJOR'):
            publisher.preflight(self.api, '1.0.1')

    def test_own_draft_is_allowed_during_final_guard(self):
        self.api.rows = [dict(self.release(draft=True), id=10)]
        publisher.preflight(self.api, '1.0.1', own_draft_id=10)

    def test_development_receipt_cannot_create_release(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root, signed=False, notarized=False)
            with self.assertRaisesRegex(ValueError, 'development artifacts'):
                publisher.publish(self.api, '1.0.1', root)
        self.assertEqual(self.api.mutations, [])

    def test_wrong_feed_cannot_create_release(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root, feed_url='https://private.invalid/feed')
            with self.assertRaisesRegex(ValueError, 'stable feed'):
                publisher.publish(self.api, '1.0.1', root)
        self.assertEqual(self.api.mutations, [])

    def test_wrong_checksum_cannot_create_release(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            (root / 'Chit-1.0.1.zip.sha256').write_text('incorrect\n')
            with self.assertRaisesRegex(ValueError, 'checksum'):
                publisher.publish(self.api, '1.0.1', root)
        self.assertEqual(self.api.mutations, [])

    def test_asset_digest_failure_preserves_unpublished_draft(self):
        self.api.bad_digest = True
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            with contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaisesRegex(ValueError, 'asset verification'):
                    publisher.publish(self.api, '1.0.1', root)
        self.assertTrue(self.api.rows[0]['draft'])
        self.assertFalse(any(method == 'PATCH' for method, _, _ in self.api.mutations))

    def test_all_four_assets_verified_before_publication(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            publisher.publish(self.api, '1.0.1', root)
        self.assertEqual(len(self.api.uploaded), 4)
        self.assertEqual(self.api.mutations[-1][0:2], ('PATCH', '/releases/10'))
        self.assertFalse(self.api.rows[0]['draft'])
        self.assertEqual(self.api.rows[0]['make_latest'], 'true')
        self.assertFalse(self.api.rows[0]['generate_release_notes'])

    def test_versions_are_strict_numeric_stable(self):
        for invalid in ('1.0', '01.0.1', '1.0.1-beta', '1.0.1\n', 'v1.0.1'):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                publisher.version_tuple(invalid)

    def test_cask_version_must_be_unambiguous(self):
        with self.assertRaisesRegex(ValueError, 'unambiguous'):
            publisher.cask_version('version "1.0.1"\nversion "1.0.2"\n')


class FakeTapGitHub(FakeGitHub):
    def __init__(self):
        super().__init__()
        self.previous_content = None
        self.cask_content = 'cask "chit" do\n  version "1.0.1"\n  sha256 "' + 'a' * 64 + '"\nend\n'
        self.rows = [{'tag_name': 'v1.0.1', 'id': 10, 'draft': False, 'prerelease': False,
                      'assets': [{'name': 'Chit-1.0.1.zip', 'digest': 'sha256:' + 'a' * 64}]}]

    def request(self, route, *, method='GET', data=None, **kwargs):
        import base64
        if route == '/contents/Casks/chit.rb?ref=main':
            return {'content': base64.b64encode(self.previous_content.encode()).decode()} if self.previous_content else None
        if route == '/git/ref/heads/homebrew%2Fv1.0.1':
            return None
        if route == '/git/commits/abc':
            return {'tree': {'sha': 'base-tree'}}
        if route.startswith('/pulls?'):
            return []
        if method == 'POST' and route in ('/git/blobs', '/git/trees', '/git/commits', '/git/refs', '/pulls'):
            self.mutations.append((method, route, data))
            if route == '/pulls':
                return {'html_url': 'https://github.com/owner/public-releases/pull/1'}
            return {'sha': 'synthetic-sha'}
        return super().request(route, method=method, data=data, **kwargs)


class CaskPRGuards(unittest.TestCase):
    def setUp(self):
        self.api = FakeTapGitHub()

    def invoke(self):
        with patch.object(publisher, 'public_asset', return_value=self.api.cask_content.encode()), contextlib.redirect_stdout(io.StringIO()):
            publisher.tap_pr(self.api, '1.0.1')

    def test_new_cask_only_creates_release_branch_and_pr(self):
        self.invoke()
        mutations = self.api.mutations
        self.assertEqual([row[1] for row in mutations], ['/git/blobs', '/git/trees', '/git/commits', '/git/refs', '/pulls'])
        self.assertEqual(mutations[3][2]['ref'], 'refs/heads/homebrew/v1.0.1')
        self.assertEqual(mutations[4][2]['base'], 'main')
        self.assertEqual(mutations[1][2]['tree'][0]['path'], 'Casks/chit.rb')

    def test_cask_checksum_mismatch_makes_no_changes(self):
        self.api.cask_content = self.api.cask_content.replace('a' * 64, 'b' * 64)
        with self.assertRaisesRegex(ValueError, 'checksum differs'):
            self.invoke()
        self.assertEqual(self.api.mutations, [])

    def test_current_default_cask_is_skipped(self):
        self.api.previous_content = self.api.cask_content
        self.invoke()
        self.assertEqual(self.api.mutations, [])

    def test_same_default_version_with_different_contents_is_refused(self):
        self.api.previous_content = self.api.cask_content + '# Unexpected change\n'
        with self.assertRaisesRegex(ValueError, 'different contents'):
            self.invoke()
        self.assertEqual(self.api.mutations, [])


if __name__ == '__main__':
    unittest.main()
