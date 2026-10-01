# Releasing Chit

Chit distributes an optimized universal macOS 14+ app through GitHub Releases.
Release builds include Sparkle 2.10.0 for in-app updates and the bundled `chit`
CLI. Chit shows **Update** beside its menu-bar checklist when a newer version is
available; **Update Available…** opens Sparkle's standard update window.
Automatic-check consent and installation use Sparkle's standard UI.
Normal app and Lab builds remain offline and separate from release output
in `build/release/`. Default releases are ad-hoc signed and unnotarized; every
release requires a verified Sparkle Ed25519 signature on the final ZIP.
Developer ID signing and notarization are an optional release mode.
This guide describes setup;
it does not mean a release has already been published. Updater startup is also
disabled for isolated harnesses and storage overrides (`CHIT_STORE`,
`TOT_TODO_STORE`, or `CHIT_FILE_STATE_DIRECTORY`).

## Public download location

The public source, release, and Homebrew tap repository is
[`dankhole/chit`](https://github.com/dankhole/chit).
`DISTRIBUTION_REPOSITORY` is configured as `dankhole/chit`.
No workflow changes repository visibility. The destination must be public because
installed apps and Homebrew download without GitHub credentials; GitHub only provides
unauthenticated API access to public resources.
[GitHub release API](https://docs.github.com/en/rest/releases/releases).

The stable feed is
`https://github.com/dankhole/chit/releases/latest/download/appcast.xml`.
Keep that location and signing keys stable after shipping an app.

## One-time setup

The default `ad-hoc` mode needs no Apple Developer membership or credentials.
It still requires the persistent Sparkle key, public download destination, and
GitHub permissions below. Choose `notarized` only after completing the optional
[Apple setup](#optional-apple-notarization).

Chit's persistent EdDSA key is already stored in the login Keychain under
`local.dcole.Chit.updates`, with its matching `SPARKLE_PRIVATE_KEY` secret and
`SPARKLE_PUBLIC_KEY` variable configured in GitHub Actions. From the pinned
Sparkle distribution, `bin/generate_keys --account local.dcole.Chit.updates`
reuses that key and displays its public key; do not replace it for a new release.
Use that same account to export a backup or restore it on another Mac.
Encrypt the exported backup before storing it:

```sh
bin/generate_keys --account local.dcole.Chit.updates -x /private/path/sparkle.key
# On another Mac, restore the same key:
bin/generate_keys --account local.dcole.Chit.updates -f /private/path/sparkle.key
```

Sparkle 2.10.0 exports newly generated keys as a base64 32-byte private seed;
the release pipeline also accepts older 64/96-byte exports. These commands match
the pinned tool's `--help`. Keep the same key for later releases. Ad-hoc apps
have no Developer ID trust fallback: if that key is lost or compromised,
establishing a new trusted key requires a manual or Homebrew reinstall.
Release builds verify archives before extraction
(`SUVerifyUpdateBeforeExtraction=true`). Even in notarized mode, the current
ZIP format cannot use Developer ID alone to rotate the Ed25519 key; Sparkle
requires a signed DMG for that fallback with this option.
[Sparkle key instructions](https://sparkle-project.org/documentation/#3-segue-for-security-concerns).

Configure these in the **source repository's** Settings → Secrets and variables
→ Actions. Secret values belong in GitHub settings or protected local files,
never in source control, issue text, or chat.

| Repository secret | Contents |
| --- | --- |
| `SPARKLE_PRIVATE_KEY` | Base64 private key from `generate_keys -x` (32-byte current seed or 64/96-byte legacy export), matching `SPARKLE_PUBLIC_KEY` |
| `DISTRIBUTION_TOKEN` | Not needed for `dankhole/chit`; only needed for an alternate repository, scoped there with Contents and Pull requests write permissions |

| Repository variable | Value |
| --- | --- |
| `SPARKLE_PUBLIC_KEY` | Matching base64 public EdDSA key |
| `DISTRIBUTION_REPOSITORY` | `dankhole/chit`, or unset to use the source repository |
| `RELEASE_SIGNING_MODE` | `ad-hoc` (default when unset), or `notarized` after Apple setup |

The Sparkle secret and public variable are already configured. To restore the
same secret from a protected backup, use file input with the GitHub CLI:

```sh
umask 077
gh secret set SPARKLE_PRIVATE_KEY --repo dankhole/chit < /private/path/sparkle.key
```

Set variables in GitHub settings or with `gh variable set`. See
[GitHub's secrets guide](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets).

GitHub Actions is configured to **Allow GitHub Actions to create and approve pull
requests** in Settings → Actions → General → Workflow permissions. The default
token permission remains read-only; publication and cask jobs request their
specific write permissions and use `GITHUB_TOKEN` for this destination.
[GitHub Actions settings](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository).

## Optional Apple notarization

To publish an Apple-notarized app later:

1. [Enroll in the Apple Developer Program](https://developer.apple.com/programs/enroll/).
2. [Create a Developer ID Application certificate](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)
   and export it with its private key as a password-protected `.p12`.
3. [Create a team App Store Connect API key](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api)
   for notarization, retaining its `.p8`, key ID, and issuer ID. The workflow uses
   issuer-based [notarytool API-key credentials](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool).

Preserve this key material outside the repository and CI. Configure the following
Actions values, then set `RELEASE_SIGNING_MODE=notarized`:

| Actions value | Kind | Contents |
| --- | --- | --- |
| `APPLE_DEVELOPER_ID_CERTIFICATE_P12` | Secret | Base64-encoded exported `.p12` |
| `APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD` | Secret | Export password |
| `APPLE_NOTARY_KEY_P8` | Secret | Raw notarization API private key file |
| `APPLE_NOTARY_KEY_ID` | Secret | Notarization API key ID |
| `APPLE_NOTARY_ISSUER_ID` | Secret | Notarization API issuer ID |
| `APPLE_TEAM_ID` | Variable | Developer team ID matching the certificate |

For example, upload protected files without printing their contents:

```sh
umask 077
base64 -i /private/path/DeveloperID.p12 -o /private/path/DeveloperID.p12.base64
gh secret set APPLE_DEVELOPER_ID_CERTIFICATE_P12 --repo dankhole/chit < /private/path/DeveloperID.p12.base64
gh secret set APPLE_NOTARY_KEY_P8 --repo dankhole/chit < /private/path/AuthKey.p8
```

Use protected file input for the remaining secrets. Apple's
[notarization guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
explains account requirements. A failed `notarized` release never falls back to
`ad-hoc`.

## Validate and publish

The workflow is `.github/workflows/release.yml`; signing and publication use
`scripts/release-signing.sh` and `scripts/release-publish.py`.

Pull requests and manual validation runs build without publication credentials
and cannot publish a release. Local ad-hoc release validation uses the same
isolated builder with the chosen HTTPS appcast URL and valid public key:

```sh
scripts/release-build.sh --version X.Y.Z \
  --feed-url https://github.com/dankhole/chit/releases/latest/download/appcast.xml \
  --public-ed-key BASE64_PUBLIC_KEY --ad-hoc
```

Replace `X.Y.Z` and the key before running. The builder
requires a real HTTPS appcast URL and a nonzero 32-byte base64 public key; it
rejects placeholder domains. This builder's output alone is not publication-ready:
the signing helper must sign and verify the final ZIP with the real Sparkle key.
For a Developer ID local build, replace
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

The workflow selects `RELEASE_SIGNING_MODE` and calls
`scripts/release-signing.sh --mode MODE VERSION FEED_URL PUBLIC_ED_KEY`.
In `ad-hoc` mode it builds and verifies the ad-hoc application signature without
Apple credentials. In `notarized` mode it imports the Developer ID certificate
into a temporary keychain, builds, notarizes, and staples the app. Both modes
produce a universal `Chit-X.Y.Z.zip`, sign that exact final archive with EdDSA,
verify it against the configured public key, compute its real SHA256,
and generate `Chit-X.Y.Z.zip.sha256`, `appcast.xml`, and `chit.rb`.
It uploads the complete asset set before
publishing the release as latest. Publication validates the selected mode and
verified release receipt. Missing mode-required credentials or failed signature/
notary steps fail publication; the workflow never downgrades its selected mode.

Confirm the public release contains all four assets and that the stable feed
points to its version and ZIP. Review and merge the generated cask PR before
announcing Homebrew installation or upgrades. Existing development-installed
Chit has no updater: replace it once with the first release. Subsequent
release versions can update through Sparkle. For the first live update test,
use two real published release versions; a development artifact does not prove
the full installed-app update path. [Sparkle testing guidance](https://sparkle-project.org/documentation/#6-test-sparkle-out).

## Homebrew

Chit's own tap is separate from Homebrew's official cask catalog. The distribution
repository acts as the tap, installed under the stable
`dankhole/chit` alias. Use the fully qualified `dankhole/chit/chit` cask name
to trust that item; tapping alone does not grant trust to the whole tap.
[Homebrew tap guidance](https://docs.brew.sh/Taps).
A release's `chit.rb` asset is copied to `Casks/chit.rb`
by a `homebrew/vX.Y.Z` bot PR; its checksum comes from the final release
ZIP. The first install cannot work until that PR is merged, and upgrades follow
the cask version on the default branch. Do not insert a placeholder checksum or
hand-edit it independently of the published archive.

After the first release and its cask PR are ready:

```sh
brew tap dankhole/chit https://github.com/dankhole/chit.git
brew install --cask dankhole/chit/chit
```

Homebrew retains macOS quarantine protection. An ad-hoc, unnotarized app may need
first-launch approval: try opening Chit, then choose **System Settings → Privacy
& Security → Open Anyway** and confirm **Open** if you trust the download.
[Apple's instructions](https://support.apple.com/en-us/102445),
[Homebrew's cask trust model](https://docs.brew.sh/Homebrew-Security-and-Supply-Chain#casks-have-a-different-trust-model).

The cask uses `auto_updates true` because Sparkle can update Chit. Default
`brew outdated` and bulk upgrades skip such casks. To use Homebrew for updates,
quit Chit, run `brew update`, then use the configured tap name:

```sh
brew outdated --cask --greedy dankhole/chit/chit
brew upgrade --cask --greedy dankhole/chit/chit
```

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
