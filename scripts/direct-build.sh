#!/bin/bash
# Local compiler fallback for Xcode installations whose first-launch components are missing.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
OUT="$ROOT/build/direct"
CLI="$ROOT/build/chit"
APP="$ROOT/build/Chit.app"
BUNDLE_NAME="Chit"
BUNDLE_ID="local.dcole.TotTodo"
LAB=0
if [[ "${1:-}" == --lab ]]; then
    if [[ $# -ne 1 ]]; then printf 'Usage: %s [--lab]\n' "$0" >&2; exit 64; fi
    LAB=1
    OUT="$ROOT/build/lab/direct"
    CLI="$ROOT/build/lab/template/chit"
    APP="$ROOT/build/lab/template/Chit Lab.app"
    BUNDLE_NAME="Chit Lab"
    BUNDLE_ID="local.dcole.ChitLab"
fi
LEGACY_CLI="$(dirname "$CLI")/todo"
mkdir -p "$OUT" "$OUT/ModuleCache"
mkdir -p "$(dirname "$CLI")"
TARGET="$(uname -m)-apple-macosx14.0"
COMMON=(-sdk "$SDK" -target "$TARGET" -swift-version 5 -g -Onone -enable-testing -module-cache-path "$OUT/ModuleCache")
if [[ $LAB == 1 ]]; then COMMON+=(-D CHIT_LAB); fi
collect_sources() {
    SOURCES=()
    while IFS= read -r -d '' source; do SOURCES+=("$source"); done < <(find "$1" -name '*.swift' -type f -print0)
    if [[ ${#SOURCES[@]} -eq 0 ]]; then printf 'No Swift sources in %s\n' "$1" >&2; exit 1; fi
}
source "$ROOT/scripts/build-yaml.sh"
build_yaml "$ROOT" "$OUT" "$SDK" "$TARGET"
COMMON+=(-I "$ROOT/Sources/CChitYAML")
collect_sources "$ROOT/Sources/TodoCore"
xcrun swiftc "${COMMON[@]}" -parse-as-library -emit-library -static -emit-module -module-name TodoCore -emit-module-path "$OUT/TodoCore.swiftmodule" "${SOURCES[@]}" -o "$OUT/libTodoCore.a"
collect_sources "$ROOT/Sources/ChitCLI"
xcrun swiftc "${COMMON[@]}" -I "$OUT" -L "$OUT" -lTodoCore -lChitYAML "${SOURCES[@]}" -module-name ChitCLI -o "$CLI"
# Compatibility command for existing local automation.
cp "$CLI" "$LEGACY_CLI"
collect_sources "$ROOT/Sources/Chit"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin"
xcrun swiftc "${COMMON[@]}" -I "$OUT" -L "$OUT" -lTodoCore -lChitYAML -module-name Chit "${SOURCES[@]}" -o "$APP/Contents/MacOS/Chit"
cp "$ROOT/Vendor/libyaml/LICENSE" "$APP/Contents/Resources/libyaml-LICENSE"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
plutil -replace CFBundleExecutable -string Chit "$APP/Contents/Info.plist"
# The normal profile retains its legacy preferences identity.
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP/Contents/Info.plist"
if [[ $LAB == 1 ]]; then
    plutil -replace CFBundleName -string "$BUNDLE_NAME" "$APP/Contents/Info.plist"
    plutil -insert CFBundleDisplayName -string "$BUNDLE_NAME" "$APP/Contents/Info.plist"
fi
plutil -replace LSMinimumSystemVersion -string 14.0 "$APP/Contents/Info.plist"
cp "$CLI" "$APP/Contents/Resources/bin/chit"
cp "$LEGACY_CLI" "$APP/Contents/MacOS/todo"
codesign --force --sign - "$APP/Contents/Resources/bin/chit"
codesign --force --sign - "$APP/Contents/MacOS/todo"
codesign --force --sign - "$APP"
printf 'Built %s and %s with installed Swift compiler\n' "$APP" "$CLI"
