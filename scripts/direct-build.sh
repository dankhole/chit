#!/bin/bash
# Local compiler fallback for Xcode installations whose first-launch components are missing.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
OUT="$ROOT/build/direct"
mkdir -p "$OUT" "$OUT/ModuleCache"
TARGET="$(uname -m)-apple-macosx14.0"
COMMON=(-sdk "$SDK" -target "$TARGET" -swift-version 5 -g -Onone -enable-testing -module-cache-path "$OUT/ModuleCache")
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
xcrun swiftc "${COMMON[@]}" -I "$OUT" -L "$OUT" -lTodoCore -lChitYAML "${SOURCES[@]}" -module-name ChitCLI -o "$ROOT/build/chit"
# Compatibility command for existing local automation.
cp "$ROOT/build/chit" "$ROOT/build/todo"
collect_sources "$ROOT/Sources/Chit"
APP="$ROOT/build/Chit.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin"
xcrun swiftc "${COMMON[@]}" -I "$OUT" -L "$OUT" -lTodoCore -lChitYAML -module-name Chit "${SOURCES[@]}" -o "$APP/Contents/MacOS/Chit"
cp "$ROOT/Vendor/libyaml/LICENSE" "$APP/Contents/Resources/libyaml-LICENSE"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
plutil -replace CFBundleExecutable -string Chit "$APP/Contents/Info.plist"
# Keep the legacy identity for existing settings and unfinished drafts.
plutil -replace CFBundleIdentifier -string local.dcole.TotTodo "$APP/Contents/Info.plist"
plutil -replace LSMinimumSystemVersion -string 14.0 "$APP/Contents/Info.plist"
cp "$ROOT/build/chit" "$APP/Contents/Resources/bin/chit"
cp "$ROOT/build/todo" "$APP/Contents/MacOS/todo"
codesign --force --sign - "$APP/Contents/Resources/bin/chit"
codesign --force --sign - "$APP/Contents/MacOS/todo"
codesign --force --sign - "$APP"
printf 'Built %s and %s with installed Swift compiler\n' "$APP" "$ROOT/build/chit"
