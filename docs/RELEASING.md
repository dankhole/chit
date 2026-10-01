# Releasing Chit

Chit distributes an optimized universal macOS 14+ app through GitHub Releases.
Release builds include Sparkle 2.10.0 for in-app updates and the bundled `chit`
CLI. The update menu and automatic-check consent use Sparkle's standard UI.
Normal app and Lab builds remain offline and separate from release output
in `build/release/`. A release is usable only after signing, notarization,
stapling, archive signing, and publication succeed. This guide describes setup;
it does not mean a release has already been published. Updater startup is also
disabled for isolated harnesses and storage overrides (`CHIT_STORE`,
`TOT_TODO_STORE`, or `CHIT_FILE_STATE_DIRECTORY`).

## Public download location

The source repository, `dankhole/chit`, is currently private, and no public
destination has been selected. The release workflow supports two modes:

- **Public source and distribution:** publish releases and the Homebrew cask in
  `dankhole/chit`. Leave `DISTRIBUTION_REPOSITORY` unset, or set it to that name.
- **Private source, public distribution:** create a public repository such as
  `dankhole/chit-releases`, initialize its default branch, and set the source
  repository's `DISTRIBUTION_REPOSITORY` variable to that name. Release assets
  and cask PRs go there; the source stays private.

Choose the destination explicitly before first publication. No workflow changes
repository visibility. The destination must be public because installed apps
and Homebrew download without GitHub credentials; GitHub only provides
unauthenticated API access to public resources.
[GitHub release API](https://docs.github.com/en/rest/releases/releases).

The stable feed is
`https://github.com/OWNER/REPOSITORY/releases/latest/download/appcast.xml`, using
the chosen distribution repository. For same-repository distribution it is
`https://github.com/dankhole/chit/releases/latest/download/appcast.xml`.
Keep that location and signing keys stable after shipping an app.

## One-time setup

Use an Apple Developer ID Application certificate and its private key, plus an
App Store Connect API key authorized for notarization. Export the certificate
and private key together as a password-protected `.p12`. Preserve the original
key material outside the repository and CI. Apple's
[notarization guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
explains account requirements and API-key authentication.

From the pinned Sparkle distribution, generate the app's EdDSA key once with
`bin/generate_keys --account local.dcole.Chit.updates`. It stores the private key
in your login Keychain and prints the public key used as `SUPublicEDKey`.
Use that same app-specific account when exporting for CI or importing on another
Mac, keeping an encrypted backup of the export:

```sh
bin/generate_keys --account local.dcole.Chit.updates -x /private/path/sparkle.key
# On another Mac, restore the same key:
bin/generate_keys --account local.dcole.Chit.updates -f /private/path/sparkle.key
```

Sparkle 2.10.0 exports newly generated keys as a base64 32-byte private seed;
the release pipeline also accepts older 64/96-byte exports. These commands match
the pinned tool's `--help`. Keep the same key for later releases; losing or
rotating it requires an update compatibility plan.
[Sparkle key instructions](https://sparkle-project.org/documentation/#3-segue-for-security-concerns).

Configure these in the **source repository's** Settings → Secrets and variables
→ Actions. Secret values belong in GitHub settings or protected local files,
never in source control, issue text, or chat.

| Repository secret | Contents |
| --- | --- |
| `APPLE_DEVELOPER_ID_CERTIFICATE_P12` | Base64-encoded exported `.p12` |
| `APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD` | Export password |
| `APPLE_NOTARY_KEY_P8` | Raw notarization API private key file |
| `APPLE_NOTARY_KEY_ID` | Notarization API key ID |
| `APPLE_NOTARY_ISSUER_ID` | Notarization API issuer ID |
| `SPARKLE_PRIVATE_KEY` | Base64 private key from `generate_keys -x` (32-byte current seed or 64/96-byte legacy export), matching `SPARKLE_PUBLIC_KEY` |
| `DISTRIBUTION_TOKEN` | Required for a separate distribution repository; fine-grained token scoped to that repository with Contents and Pull requests write permissions |

| Repository variable | Value |
| --- | --- |
| `SPARKLE_PUBLIC_KEY` | Matching base64 public EdDSA key |
| `APPLE_TEAM_ID` | Developer team ID matching the certificate |
| `DISTRIBUTION_REPOSITORY` | Public `OWNER/REPOSITORY`; defaults to the source repository |

For example, encode the `.p12` into a protected file, then upload files with the
GitHub CLI. These commands do not print their contents:

```sh
umask 077
base64 -i /private/path/DeveloperID.p12 -o /private/path/DeveloperID.p12.base64
gh secret set APPLE_DEVELOPER_ID_CERTIFICATE_P12 --repo dankhole/chit < /private/path/DeveloperID.p12.base64
gh secret set APPLE_NOTARY_KEY_P8 --repo dankhole/chit < /private/path/AuthKey.p8
gh secret set SPARKLE_PRIVATE_KEY --repo dankhole/chit < /private/path/sparkle.key
```

Use the same file-input approach for the remaining secrets. Set variables in
GitHub settings or with `gh variable set`. See
[GitHub's secrets guide](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets).

Enable GitHub Actions in the source repository. For same-repository cask PRs,
enable **Allow GitHub Actions to create and approve pull requests** in Settings
→ Actions → General → Workflow permissions. Separate-repository publication uses `DISTRIBUTION_TOKEN`; initialize
that repository's default branch before creating its first cask PR.
[GitHub Actions settings](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository).

## Validate and publish

The workflow is `.github/workflows/release.yml`; signing and publication use
`scripts/release-signing.sh` and `scripts/release-publish.py`.

Pull requests and manual validation runs build without publication credentials
and cannot publish a release. Local unsigned release validation uses the same
isolated builder with the chosen HTTPS appcast URL and valid public key:

```sh
scripts/release-build.sh --version X.Y.Z \
  --feed-url https://github.com/dankhole/chit/releases/latest/download/appcast.xml \
  --public-ed-key BASE64_PUBLIC_KEY --ad-hoc
```

Replace `X.Y.Z`, the key, and the destination URL before running. The builder
requires a real HTTPS appcast URL and a nonzero 32-byte base64 public key; it
rejects placeholder domains. Ad-hoc output is for validation and cannot be
published. For a signed local build, replace
`--ad-hoc` with `--signing-identity 'Developer ID Application: NAME (TEAMID)'`.
This builder alone does not notarize or publish. Keep release validation separate
from the personal app; follow [Chit Lab](CHIT_LAB.md) for ordinary development.

After the chosen revision passes CI and the setup above is complete, create and
push a stable `vX.Y.Z` tag in the source repository. The tag starts publication.
Only stable three-component versions are supported; no prerelease suffixes.
The first public release must be newer than `1.0.0`, for example `v1.0.1`;
publication enforces this and strictly increasing versions afterward.
Both `CFBundleShortVersionString` and `CFBundleVersion`
are `X.Y.Z`, which Sparkle uses to compare updates.

The release workflow imports the Developer ID certificate into a temporary
keychain, builds both architectures, notarizes and staples the app, and creates
`Chit-X.Y.Z.zip`. It signs that exact archive with EdDSA, computes its real SHA256,
and generates `Chit-X.Y.Z.zip.sha256`, `appcast.xml`, and `chit.rb`.
It uploads the complete asset set before
publishing the release as latest. Missing credentials or failed signing/notary
steps fail publication; unsigned builds are not published as a fallback.

Confirm the public release contains all four assets and that the stable feed
points to its version and ZIP. Review and merge the generated cask PR before
announcing Homebrew installation or upgrades. Existing development-installed
Chit has no updater: replace it once with the first signed release. Subsequent
release versions can update through Sparkle. For the first live update test,
use two real signed/notarized release versions; ad-hoc validation does not prove
the full installed-app update path. [Sparkle testing guidance](https://sparkle-project.org/documentation/#6-test-sparkle-out).

## Homebrew

The distribution repository also acts as the tap, installed under the stable
`dankhole/chit` alias. Use the fully qualified `dankhole/chit/chit` cask name
to trust that item; tapping alone does not grant trust to the whole tap.
[Homebrew tap guidance](https://docs.brew.sh/Taps).
A release's `chit.rb` asset is copied to `Casks/chit.rb`
by a `homebrew/vX.Y.Z` bot PR; its checksum comes from the final release
ZIP. The first install cannot work until that PR is merged, and upgrades follow
the cask version on the default branch. Do not insert a placeholder checksum or
hand-edit it independently of the published archive.

For public same-repository distribution:

```sh
brew tap dankhole/chit https://github.com/dankhole/chit.git
brew install --cask dankhole/chit/chit
```

For a separate public `dankhole/chit-releases` destination:

```sh
brew tap dankhole/chit https://github.com/dankhole/chit-releases.git
brew install --cask dankhole/chit/chit
```

The cask uses `auto_updates true` because Sparkle can update Chit. Default
`brew outdated` and bulk upgrades skip such casks. To use Homebrew for updates,
quit Chit, run `brew update`, then use the configured tap name:

```sh
brew outdated --cask --greedy dankhole/chit/chit
brew upgrade --cask --greedy dankhole/chit/chit
```

Use only the tap URL for your chosen destination. If an existing `dankhole/chit`
tap points elsewhere, untap it before tapping the chosen URL.
[Homebrew manual](https://docs.brew.sh/Manpage).

## Failed or incorrect releases

A failure before publication can leave a draft release; inspect the failed step
and staged assets, then remove the unpublished draft before rerunning. Existing
releases and assets are not overwritten or reused. A published release is an
update channel for installed apps. Correct code with a higher version rather than replacing a
published ZIP under the same version, which would invalidate signatures and
checksums. If cask PR creation fails after publication, the app release can
already be live; rerun only the cask job after fixing its permissions or other
failure before directing Homebrew users to upgrade.
