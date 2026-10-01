#!/usr/bin/env python3
"""Publish validated assets and open the Homebrew cask PR without overwrites.

Only CI invokes the network operations. Importing this module is safe for focused
tests; the API token is read only when a command runs, and is never logged.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import urllib.error
import urllib.parse
import urllib.request


VERSION = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\Z")
REPOSITORY = re.compile(r"[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9][A-Za-z0-9_.-]*\Z")


def version_tuple(value: str) -> tuple[int, int, int]:
    if not VERSION.fullmatch(value):
        raise ValueError(f"Expected a stable MAJOR.MINOR.PATCH version, got {value!r}.")
    return tuple(int(part) for part in value.split('.'))


class GitHub:
    def __init__(self, repository: str):
        if not REPOSITORY.fullmatch(repository):
            raise ValueError('Distribution repository must be owner/name on github.com.')
        self.repository = repository
        self.root = f'/repos/{repository}'
        self.token = os.environ.get('GH_TOKEN', '')
        if not self.token:
            raise ValueError('GH_TOKEN is required; set DISTRIBUTION_TOKEN for a separate public repository.')

    def request(self, route: str, *, method='GET', data=None, missing_ok=False,
                upload_url=None, content_type='application/json'):
        url = f'https://api.github.com{self.root}{route}'
        if upload_url:
            parsed = urllib.parse.urlparse(upload_url)
            if parsed.scheme != 'https' or parsed.netloc != 'uploads.github.com' or not parsed.path.startswith(self.root + '/releases/'):
                raise ValueError('GitHub returned an unexpected release upload URL.')
            url = upload_url
        body = data if isinstance(data, bytes) else json.dumps(data).encode() if data is not None else None
        headers = {'Accept': 'application/vnd.github+json',
                   'Authorization': f'Bearer {self.token}',
                   'X-GitHub-Api-Version': '2022-11-28',
                   'User-Agent': 'chit-release', 'Content-Type': content_type}
        request = urllib.request.Request(url, body, headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                content = response.read()
                return json.loads(content) if content else None
        except urllib.error.HTTPError as error:
            if missing_ok and error.code == 404:
                return None
            # GitHub responses can echo request information. Do not print the
            # token, request headers, or full response/body on error.
            raise RuntimeError(f'GitHub {method} {route or "/"} failed (HTTP {error.code}); check destination/token permissions.') from None
        except urllib.error.URLError:
            raise RuntimeError(f'GitHub {method} {route or "/"} could not connect; no retries or overwrites were attempted.') from None

    def releases(self):
        page = 1
        while True:
            rows = self.request(f'/releases?per_page=100&page={page}')
            yield from rows
            if len(rows) < 100:
                break
            page += 1


def preflight(api: GitHub, version: str, *, own_draft_id=None):
    requested = version_tuple(version)
    # Existing app installations carry 1.0/build 1. Start the public channel at
    # a higher version so every stable published build advances Sparkle.
    if requested <= (1, 0, 0):
        raise ValueError('The first public release must be newer than 1.0.0 (for example v1.0.1).')
    repository = api.request('')
    if repository.get('private') is not False:
        raise ValueError('Distribution repository is private. Choose a public DISTRIBUTION_REPOSITORY or make the source public yourself; this workflow never changes visibility.')
    if not repository.get('default_branch'):
        raise ValueError('Distribution repository needs an initialized default branch before releasing.')
    default_ref = urllib.parse.quote(repository['default_branch'], safe='')
    if api.request(f'/git/ref/heads/{default_ref}', missing_ok=True) is None:
        raise ValueError('Initialize the public distribution repository with a commit before releasing.')
    tag = 'v' + version
    for release in api.releases():
        if release['tag_name'] == tag and release['id'] != own_draft_id:
            state = 'draft' if release['draft'] else 'published'
            raise ValueError(f'{tag} already has a {state} release. Assets and published versions are never overwritten; inspect and delete an unfinished draft before retrying.')
        if release['id'] == own_draft_id or release['draft'] or release['prerelease']:
            continue
        released = release['tag_name']
        if not released.startswith('v') or not VERSION.fullmatch(released[1:]):
            raise ValueError(f'Existing stable release {released!r} is not vMAJOR.MINOR.PATCH; reconcile the distribution channel before continuing.')
        if version_tuple(released[1:]) >= requested:
            raise ValueError(f'Refusing {tag}: stable release {released} is the same version or newer.')
    return repository


def check_asset(asset, path: Path):
    expected_digest = 'sha256:' + hashlib.sha256(path.read_bytes()).hexdigest()
    if asset.get('name') != path.name or asset.get('state') != 'uploaded' or asset.get('size') != path.stat().st_size or asset.get('digest') != expected_digest:
        raise ValueError(f'GitHub asset verification failed for {path.name}; the release remains a draft.')


def publish(api: GitHub, version: str, directory: Path, *, mode: str):
    if mode not in ('ad-hoc', 'notarized'):
        raise ValueError('An explicit ad-hoc or notarized publication mode is required; no fallback is permitted.')
    preflight(api, version)
    archive = directory / f'Chit-{version}.zip'
    assets = [archive, archive.with_suffix('.zip.sha256'), directory / 'metadata/appcast.xml', directory / 'metadata/chit.rb']
    for path in assets:
        if not path.is_file() or path.is_symlink() or not path.stat().st_size:
            raise ValueError(f'Missing or invalid release asset: {path}')
    receipt = json.loads((directory / 'build.json').read_text())
    if any(receipt.get(field) is not True for field in ('release_ready', 'code_signature_verified', 'sparkle_verified')):
        raise ValueError('Release receipt lacks completed code/archive verification; development artifacts cannot be published.')
    expected_apple_trust = mode == 'notarized'
    if receipt.get('signing_mode') != mode or any(receipt.get(field) is not expected_apple_trust for field in ('signed', 'notarized', 'stapled')):
        raise ValueError('Release receipt does not match the explicitly requested signing mode; no downgrade or fallback is permitted.')
    expected_feed = f'https://github.com/{api.repository}/releases/latest/download/appcast.xml'
    if receipt.get('version') != version or receipt.get('architectures') != ['arm64', 'x86_64'] or receipt.get('feed_url') != expected_feed:
        raise ValueError('Build receipt version, universal architectures, or stable feed differs from this release.')
    checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
    if receipt.get('archive_sha256') != checksum:
        raise ValueError('Archive checksum differs from the exact Sparkle-verified archive in the release receipt.')
    if assets[1].read_text() != f'{checksum}  {archive.name}\n':
        raise ValueError('Final archive checksum does not match the checksum asset.')
    trust_description = (
        'The application is ad-hoc signed and is not Apple notarized. '
        'For the first launch, macOS may require approval in System Settings → Privacy & Security → Open Anyway. '
        'Updates are authenticated by Sparkle EdDSA signatures against the public key embedded in Chit.'
        if mode == 'ad-hoc' else
        'The application is Developer ID signed, notarized, and stapled; updates are signed with Sparkle EdDSA.'
    )
    body = ('Universal macOS application for Apple silicon and Intel. Requires macOS 14 or later.\n\n'
            'Download the ZIP below, extract Chit.app, and move it to Applications. '
            + trust_description + '\n\n'
            'The checksum file identifies the exact published ZIP. Homebrew availability follows the cask pull request.')
    release = api.request('/releases', method='POST', data={
        'tag_name': 'v' + version, 'name': 'Chit ' + version,
        'body': body, 'draft': True, 'prerelease': False,
        # No automatic notes: the source can be private, and commit messages
        # must not be exposed in a separate public distribution repository.
        'generate_release_notes': False,
    })
    print(f'Draft release created: {release["html_url"]}')
    try:
        upload_base = release['upload_url'].split('{', 1)[0]
        for path in assets:
            content_type = 'application/zip' if path.suffix == '.zip' else 'application/xml' if path.suffix == '.xml' else 'text/plain'
            asset = api.request('/releases/assets', method='POST', data=path.read_bytes(),
                                upload_url=upload_base + '?' + urllib.parse.urlencode({'name': path.name}),
                                content_type=content_type)
            check_asset(asset, path)
        uploaded = api.request(f'/releases/{release["id"]}/assets?per_page=100')
        if {row['name'] for row in uploaded} != {path.name for path in assets} or len(uploaded) != len(assets):
            raise ValueError('Draft does not contain exactly the four expected release assets.')
        by_name = {row['name']: row for row in uploaded}
        for path in assets:
            check_asset(by_name[path.name], path)
        # Recheck immediately before latest is changed. Workflow concurrency
        # serializes all release and cask publication for this destination.
        preflight(api, version, own_draft_id=release['id'])
        published = api.request(f'/releases/{release["id"]}', method='PATCH', data={'draft': False, 'make_latest': 'true'})
        if published['draft'] or published['prerelease']:
            raise ValueError('GitHub did not publish a stable release.')
        latest = api.request('/releases/latest')
        if latest['id'] != release['id']:
            raise ValueError('Published release is not latest; another publisher changed the channel. Inspect the releases before proceeding.')
    except Exception:
        print('Release failed. Inspect its draft/assets before retrying; this script never deletes or replaces assets.', file=sys.stderr)
        raise
    print(f'Published {mode} release with Sparkle-verified archive: {published["html_url"]}')


def public_asset(api: GitHub, release, name: str) -> bytes:
    matches = [asset for asset in release['assets'] if asset['name'] == name]
    if len(matches) != 1 or matches[0].get('state') != 'uploaded':
        raise ValueError(f'Published release is missing {name}.')
    asset = matches[0]
    url = asset['browser_download_url']
    expected_prefix = f'https://github.com/{api.repository}/releases/download/{release["tag_name"]}/'
    if not url.startswith(expected_prefix):
        raise ValueError('Unexpected public release asset URL.')
    # Deliberately omit authentication on public asset downloads, including
    # redirects to GitHub's release CDN.
    with urllib.request.urlopen(url, timeout=120) as response:
        content = response.read()
    if len(content) != asset['size'] or 'sha256:' + hashlib.sha256(content).hexdigest() != asset.get('digest'):
        raise ValueError(f'Published {name} does not match GitHub size/checksum.')
    return content


def cask_version(content: str):
    matches = re.findall(r'^\s*version "([^"]+)"\s*$', content, re.MULTILINE)
    if len(matches) != 1:
        raise ValueError('Cask has no unambiguous version field.')
    return version_tuple(matches[0])


def tap_pr(api: GitHub, version: str):
    version_tuple(version)
    repository = api.request('')
    if repository.get('private') is not False:
        raise ValueError('Homebrew distribution requires a public destination repository.')
    release = api.request('/releases/latest')
    if release['tag_name'] != 'v' + version:
        if release['tag_name'].startswith('v') and version_tuple(release['tag_name'][1:]) > version_tuple(version):
            print('A newer release is already latest; skipping an obsolete cask PR.')
            return
        raise ValueError('Requested release is not the current stable latest release.')
    content = public_asset(api, release, 'chit.rb').decode('utf-8')
    if cask_version(content) != version_tuple(version):
        raise ValueError('Published cask version differs from the release.')
    archives = [asset for asset in release['assets'] if asset['name'] == f'Chit-{version}.zip']
    checksum = re.search(r'^\s*sha256 "([a-f0-9]{64})"\s*$', content, re.MULTILINE)
    if len(archives) != 1 or not checksum or archives[0].get('digest') != 'sha256:' + checksum[1]:
        raise ValueError('Published cask checksum differs from the published archive.')
    default = repository['default_branch']
    default_ref = urllib.parse.quote(default, safe='')
    previous = api.request('/contents/Casks/chit.rb?' + urllib.parse.urlencode({'ref': default}), missing_ok=True)
    if previous:
        previous_content = base64.b64decode(previous['content']).decode('utf-8')
        previous_version = cask_version(previous_content)
        if previous_version >= version_tuple(version):
            if previous_version == version_tuple(version) and previous_content != content:
                raise ValueError('Default branch already has this cask version with different contents; refusing to overwrite it.')
            print('Default branch cask is already current or newer; no PR needed.')
            return
    branch = 'homebrew/v' + version
    branch_ref = urllib.parse.quote(branch, safe='')
    existing = api.request(f'/git/ref/heads/{branch_ref}', missing_ok=True)
    if existing:
        branch_file = api.request('/contents/Casks/chit.rb?' + urllib.parse.urlencode({'ref': branch}))
        if base64.b64decode(branch_file['content']).decode('utf-8') != content:
            raise ValueError('The release cask branch already exists with different contents; inspect it before retrying.')
        comparison = api.request(f'/compare/{default_ref}...{branch_ref}')
        if {file['filename'] for file in comparison.get('files', [])} != {'Casks/chit.rb'}:
            raise ValueError('The release cask branch contains unexpected changes; refusing to open a PR.')
    else:
        head = api.request(f'/git/ref/heads/{default_ref}')['object']['sha']
        base_tree = api.request(f'/git/commits/{head}')['tree']['sha']
        blob = api.request('/git/blobs', method='POST', data={'content': base64.b64encode(content.encode()).decode(), 'encoding': 'base64'})
        tree = api.request('/git/trees', method='POST', data={'base_tree': base_tree, 'tree': [{'path': 'Casks/chit.rb', 'mode': '100644', 'type': 'blob', 'sha': blob['sha']}]})
        commit = api.request('/git/commits', method='POST', data={'message': f'Update Chit cask to {version}', 'tree': tree['sha'], 'parents': [head]})
        # The only branch mutation creates a new version-specific branch. No
        # default-branch writes, force pushes, or existing ref updates.
        api.request('/git/refs', method='POST', data={'ref': 'refs/heads/' + branch, 'sha': commit['sha']})
    query = urllib.parse.urlencode({'state': 'open', 'head': api.repository.split('/')[0] + ':' + branch, 'base': default})
    pulls = api.request('/pulls?' + query)
    if pulls:
        if len(pulls) != 1:
            raise ValueError('Multiple cask PRs unexpectedly match the release branch.')
        print(f'Cask PR already open: {pulls[0]["html_url"]}')
        return
    body = (f'Updates `Casks/chit.rb` to the published Chit {version} ZIP and its verified SHA-256.\n\n'
            f'Release: https://github.com/{api.repository}/releases/tag/v{version}\n\n'
            'The release workflow verified code-signature integrity, the exact archive\'s Sparkle signature, '
            'and its checksum before publication. Merge after reviewing the version, checksum, and first-launch caveat; '
            'this PR makes the version available through the tap.')
    pull = api.request('/pulls', method='POST', data={'title': f'Update Chit cask to {version}', 'head': branch, 'base': default, 'body': body, 'maintainer_can_modify': True})
    print(f'Cask PR created: {pull["html_url"]}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('preflight', 'publish', 'tap-pr'))
    parser.add_argument('--repository', required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--directory', type=Path, default=Path('build/release'))
    parser.add_argument('--mode', choices=('ad-hoc', 'notarized'), help='Required for publish; must match the completed release receipt')
    args = parser.parse_args()
    if args.command == 'publish' and args.mode is None:
        parser.error('--mode is required for publish; mode is never inferred from credentials or artifacts')
    try:
        api = GitHub(args.repository)
        if args.command == 'preflight':
            preflight(api, args.version)
            print('Public distribution destination and strictly increasing stable version verified.')
        elif args.command == 'publish':
            publish(api, args.version, args.directory, mode=args.mode)
        else:
            tap_pr(api, args.version)
    except (ValueError, RuntimeError, KeyError, OSError, urllib.error.URLError) as error:
        sys.exit(f'Release publication: {error}')


if __name__ == '__main__':
    main()
