#!/bin/bash
# CI release only. Keep signing material in a private temporary directory and
# package only the application, never this directory or the tool cache.
set +x
set -euo pipefail
umask 077

fail() { printf 'Release signing: %s\n' "$*" >&2; exit 1; }
if [[ $# != 5 || $1 != --mode ]]; then
  fail 'usage: release-signing.sh --mode {ad-hoc|notarized} VERSION FEED_URL PUBLIC_ED_KEY'
fi
mode=$2
version=$3
feed_url=$4
public_ed_key=$5
[[ $mode == ad-hoc || $mode == notarized ]] || fail 'Mode must be ad-hoc or notarized; no fallback is permitted.'
[[ $(uname -s) == Darwin ]] || fail 'macOS is required.'
[[ $version =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || fail 'VERSION must be MAJOR.MINOR.PATCH.'

required=(SPARKLE_PRIVATE_KEY DISTRIBUTION_REPOSITORY)
if [[ $mode == notarized ]]; then
  required+=(APPLE_DEVELOPER_ID_CERTIFICATE_P12 APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD
    APPLE_NOTARY_KEY_P8 APPLE_NOTARY_KEY_ID APPLE_NOTARY_ISSUER_ID APPLE_TEAM_ID)
fi
for name in "${required[@]}"; do
  [[ -n ${!name:-} ]] || fail "Missing required secret or variable: $name"
done
if [[ $mode == notarized ]]; then
  [[ $APPLE_TEAM_ID =~ ^[A-Z0-9]{10}$ ]] || fail 'APPLE_TEAM_ID must be a ten-character team identifier.'
  [[ $APPLE_NOTARY_KEY_ID =~ ^[A-Za-z0-9]{10,}$ ]] || fail 'APPLE_NOTARY_KEY_ID must be an alphanumeric API key identifier of at least ten characters.'
  [[ $APPLE_NOTARY_ISSUER_ID =~ ^[0-9a-fA-F-]{36}$ ]] || fail 'APPLE_NOTARY_ISSUER_ID must be a UUID.'
fi

repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"
private_dir=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/chit-signing.XXXXXX")
keychain="$private_dir/release.keychain-db"
original_keychains=()
keychain_created=false
search_list_changed=false
cleanup() {
  local status=$?
  trap - EXIT INT TERM
  if [[ $search_list_changed == true ]]; then
    security list-keychains -d user -s "${original_keychains[@]}" >/dev/null 2>&1 || status=1
  fi
  if [[ $keychain_created == true ]]; then
    security delete-keychain "$keychain" >/dev/null 2>&1 || status=1
  fi
  rm -rf "$private_dir"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Reject malformed Sparkle material before invoking sign_update, whose own
# malformed-key error messages can contain its input. The exported key's public
# half must match the key embedded in the distributed app.
export CHIT_SIGNING_DIRECTORY="$private_dir" CHIT_PUBLIC_ED_KEY="$public_ed_key" CHIT_SIGNING_MODE="$mode"
python3 - <<'PY'
import base64, os, pathlib, sys, uuid
root = pathlib.Path(os.environ['CHIT_SIGNING_DIRECTORY'])
try:
    public = base64.b64decode(os.environ['CHIT_PUBLIC_ED_KEY'], validate=True)
    secret_text = os.environ['SPARKLE_PRIVATE_KEY'].strip()
    secret = base64.b64decode(secret_text, validate=True)
    if len(public) != 32 or len(secret) not in (32, 64, 96):
        raise ValueError('key mismatch')
    if os.environ['CHIT_SIGNING_MODE'] == 'notarized':
        certificate = base64.b64decode(os.environ['APPLE_DEVELOPER_ID_CERTIFICATE_P12'], validate=True)
        uuid.UUID(os.environ['APPLE_NOTARY_ISSUER_ID'])
        if not certificate:
            raise ValueError('empty certificate')
        notary_key = os.environ['APPLE_NOTARY_KEY_P8'].strip() + '\n'
        if not notary_key.startswith('-----BEGIN PRIVATE KEY-----\n') or not notary_key.endswith('-----END PRIVATE KEY-----\n'):
            raise ValueError('invalid API key')
        (root / 'certificate.p12').write_bytes(certificate)
        (root / 'AuthKey.p8').write_text(notary_key)
except (ValueError, KeyError):
    sys.exit('Release signing: invalid certificate/API key or Sparkle private/public key configuration (values withheld).')
(root / 'sparkle.key').write_text(secret_text + '\n')
PY
unset APPLE_DEVELOPER_ID_CERTIFICATE_P12 APPLE_NOTARY_KEY_P8 SPARKLE_PRIVATE_KEY
xcrun swiftc -O scripts/release-verify.swift -o "$private_dir/release-verify" \
  -module-cache-path "$private_dir/swift-cache"
"$private_dir/release-verify" key "$private_dir/sparkle.key" "$public_ed_key"

if [[ $mode == notarized ]]; then
security list-keychains -d user > "$private_dir/keychains.txt"
while IFS= read -r item; do original_keychains+=("$item"); done < <(
  python3 - "$private_dir/keychains.txt" <<'PY'
import pathlib, shlex, sys
for item in shlex.split(pathlib.Path(sys.argv[1]).read_text()):
    print(item)
PY
)
keychain_password=$(openssl rand -base64 32)
security create-keychain -p "$keychain_password" "$keychain" >/dev/null
keychain_created=true
security set-keychain-settings -lut 3600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
if ! security import "$private_dir/certificate.p12" -k "$keychain" \
  -P "$APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security \
  > "$private_dir/import.log" 2>&1; then
  fail 'Developer ID certificate import failed (diagnostic withheld to protect credentials).'
fi
unset APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
unset keychain_password
security list-keychains -d user -s "$keychain" "${original_keychains[@]}"
search_list_changed=true
security find-identity -v -p codesigning "$keychain" > "$private_dir/identities.txt"
identity=$(python3 - "$private_dir/identities.txt" <<'PY'
import os, pathlib, re, sys
identities = []
for line in pathlib.Path(sys.argv[1]).read_text().splitlines():
    match = re.search(r'\b([A-Fa-f0-9]{40}) "Developer ID Application: .* \(([A-Z0-9]{10})\)"', line)
    if match and match[2] == os.environ['APPLE_TEAM_ID']:
        identities.append(match[1])
if len(identities) != 1:
    sys.exit('Release signing: expected exactly one valid Developer ID Application identity for APPLE_TEAM_ID.')
print(identities[0])
PY
)

scripts/release-build.sh --version "$version" --feed-url "$feed_url" \
  --public-ed-key "$public_ed_key" --signing-identity "$identity"
else
  # Ad-hoc code signing ensures bundle integrity without Apple credentials.
  # Sparkle's pinned Ed25519 key authenticates the update archive separately.
  unset APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD
  scripts/release-build.sh --version "$version" --feed-url "$feed_url" \
    --public-ed-key "$public_ed_key" --ad-hoc
fi
app="$repo_root/build/release/Chit.app"
archive="$repo_root/build/release/Chit-$version.zip"
[[ -d $app && ! -e $archive ]] || fail 'Expected built application and an unused final archive path.'
codesign --verify --deep --strict --verbose=2 "$app"
if [[ $mode == notarized ]]; then
# Apple accepts ZIP submissions, but the ticket is stapled to the app. Recreate
# the final archive after stapling, then sign those exact published bytes.
ditto -c -k --sequesterRsrc --keepParent "$app" "$private_dir/notary-submission.zip"
if ! xcrun notarytool submit "$private_dir/notary-submission.zip" \
  --key "$private_dir/AuthKey.p8" --key-id "$APPLE_NOTARY_KEY_ID" \
  --issuer "$APPLE_NOTARY_ISSUER_ID" --wait --timeout 30m --output-format json \
  > "$private_dir/notary-result.json" 2> "$private_dir/notary-error.log"; then
  fail 'Notarization submission failed; no release archive was produced.'
fi
python3 - "$private_dir/notary-result.json" <<'PY'
import json, pathlib, sys
result = json.loads(pathlib.Path(sys.argv[1]).read_text())
if result.get('status') != 'Accepted':
    sys.exit('Release signing: Apple did not accept notarization; no release will be published.')
print('Apple notarization accepted.')
PY
xcrun stapler staple "$app"
xcrun stapler validate "$app"
codesign --verify --deep --strict --verbose=2 "$app"
spctl --assess --type execute --verbose=2 "$app"
else
  codesign --display --verbose=4 "$app" > "$private_dir/codesign.txt" 2>&1
  python3 - "$private_dir/codesign.txt" <<'PY'
import pathlib, sys
if 'Signature=adhoc' not in pathlib.Path(sys.argv[1]).read_text().splitlines():
    sys.exit('Release signing: ad-hoc mode did not produce an ad-hoc application signature.')
PY
fi
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"

sign_update="$repo_root/build/release/dependencies/sparkle/bin/sign_update"
[[ -x $sign_update ]] || fail 'Pinned Sparkle sign_update tool is unavailable.'
if ! "$sign_update" --ed-key-file - -p "$archive" < "$private_dir/sparkle.key" \
  > "$private_dir/signature.txt" 2> "$private_dir/sparkle-error.log"; then
  fail 'Sparkle archive signing failed (diagnostic withheld to protect the key).'
fi
signature=$(cat "$private_dir/signature.txt")
if ! "$sign_update" --ed-key-file - --verify "$archive" "$signature" \
  < "$private_dir/sparkle.key" > "$private_dir/verify.log" 2>&1; then
  fail 'Sparkle archive signature verification failed.'
fi
"$private_dir/release-verify" archive "$archive" "$signature" "$public_ed_key"
python3 scripts/release-metadata.py --version "$version" --archive "$archive" \
  --signature "$signature" --repository "$DISTRIBUTION_REPOSITORY" \
  --mode "$mode" --output-directory build/release/metadata
python3 - "$repo_root/build/release/build.json" "$archive" "$mode" <<'PY'
import hashlib, json, pathlib, sys
path = pathlib.Path(sys.argv[1])
archive = pathlib.Path(sys.argv[2])
mode = sys.argv[3]
receipt = json.loads(path.read_text())
if receipt.get('signed') is not (mode == 'notarized'):
    sys.exit('Release signing: builder receipt does not match the requested signing mode.')
digest = hashlib.sha256(archive.read_bytes()).hexdigest()
archive.with_suffix('.zip.sha256').write_text(f'{digest}  {archive.name}\n')
receipt.update(signing_mode=mode, code_signature_verified=True,
               sparkle_verified=True, release_ready=True, archive_sha256=digest,
               notarized=mode == 'notarized', stapled=mode == 'notarized')
path.write_text(json.dumps(receipt, indent=2) + '\n')
PY
printf '%s application with Sparkle-verified archive ready: %s\n' "$mode" "${archive##*/}"
