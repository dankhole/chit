#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
# Use the ordinary Xcode route unless this installation cannot load its required plugins.
mkdir -p "$ROOT/build"
if [[ "${CHIT_DIRECT_BUILD:-${TOT_TODO_DIRECT_BUILD:-0}}" == 1 ]]; then
    exec "$ROOT/scripts/direct-test.sh" "$@"
fi
if ! xcodebuild -list -project "$ROOT/Chit.xcodeproj" >"$ROOT/build/xcode-check.log" 2>&1; then
    if grep -qE 'CoreSimulator|failed to load a required plug-in' "$ROOT/build/xcode-check.log"; then
        printf 'Xcode first-launch components are unavailable; using the installed compiler fallback.\n' >&2
        exec "$ROOT/scripts/direct-test.sh" "$@"
    fi
    cat "$ROOT/build/xcode-check.log" >&2
    exit 1
fi
xcodebuild -project "$ROOT/Chit.xcodeproj" -scheme Chit -configuration Debug -derivedDataPath "$ROOT/build/DerivedData" -destination 'platform=macOS' test "$@"
