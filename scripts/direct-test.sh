#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [[ -z "${CHIT_FILE_STATE_DIRECTORY:-}" ]]; then
    CHIT_TEST_STATE_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/chit-test-file-state.XXXXXX")"
    export CHIT_FILE_STATE_DIRECTORY="$CHIT_TEST_STATE_TEMP"
    trap 'rm -rf "$CHIT_TEST_STATE_TEMP"' EXIT
fi
SDK="$(xcrun --sdk macosx --show-sdk-path)"
OUT="$ROOT/build/direct-tests"
mkdir -p "$OUT/ModuleCache"
FRAMEWORKS="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/Library/Frameworks"
TEST_LIBS="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/usr/lib"
COMMON=(-I "$TEST_LIBS" -L "$TEST_LIBS" -sdk "$SDK" -target "$(uname -m)-apple-macosx14.0" -swift-version 5 -g -Onone -enable-testing -module-cache-path "$OUT/ModuleCache" -I "$OUT" -L "$OUT" -F "$FRAMEWORKS")
source "$ROOT/scripts/build-yaml.sh"
build_yaml "$ROOT" "$OUT" "$SDK" "$(uname -m)-apple-macosx14.0"
COMMON+=(-I "$ROOT/Sources/CChitYAML")
CORE_SOURCES=()
while IFS= read -r -d '' source; do CORE_SOURCES+=("$source"); done < <(find "$ROOT/Sources/TodoCore" -name '*.swift' -type f -print0)
xcrun swiftc "${COMMON[@]}" -parse-as-library -emit-library -emit-module -module-name TodoCore -emit-module-path "$OUT/TodoCore.swiftmodule" "${CORE_SOURCES[@]}" -lChitYAML -o "$OUT/libTodoCore.dylib"
SUITES=(TodoCoreTests ChitTests)
if [[ $# -gt 0 ]]; then SUITES=("$@"); fi
# A test-only module exposes AppModel only when its suite is requested.
if [[ " ${SUITES[*]} " == *" ChitTests "* ]]; then
xcrun swiftc "${COMMON[@]}" -parse-as-library -emit-library -emit-module -module-name Chit -emit-module-path "$OUT/Chit.swiftmodule" -lTodoCore "$ROOT/Sources/Chit/AppModel.swift" -o "$OUT/libChit.dylib"
fi
for SUITE in "${SUITES[@]}"; do
    case "$SUITE" in TodoCoreTests|ChitTests) ;; *) printf 'Unknown test suite: %s\n' "$SUITE" >&2; exit 2 ;; esac
    BUNDLE="$OUT/$SUITE.xctest"
    mkdir -p "$BUNDLE/Contents/MacOS"
    SOURCES=()
    while IFS= read -r -d '' source; do SOURCES+=("$source"); done < <(find "$ROOT/Tests/$SUITE" -name '*.swift' -type f -print0)
    if [[ ${#SOURCES[@]} -eq 0 ]]; then printf 'No tests in %s\n' "$SUITE" >&2; exit 1; fi
    LINKS=(-lTodoCore)
    if [[ "$SUITE" == ChitTests ]]; then LINKS+=(-lChit); fi
    xcrun swiftc "${COMMON[@]}" -parse-as-library -emit-library -module-name "$SUITE" "${SOURCES[@]}" "${LINKS[@]}" -Xlinker -rpath -Xlinker "$OUT" -Xlinker -rpath -Xlinker "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$TEST_LIBS" -o "$BUNDLE/Contents/MacOS/$SUITE"
    cat > "$BUNDLE/Contents/Info.plist" <<EOF_PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleExecutable</key><string>$SUITE</string><key>CFBundleIdentifier</key><string>local.dcole.$SUITE</string><key>CFBundlePackageType</key><string>BNDL</string></dict></plist>
EOF_PLIST
    TEST_ENV=(HOME="$HOME" PATH="$PATH" DEVELOPER_DIR="$DEVELOPER_DIR")
    if [[ -n "${TMPDIR:-}" ]]; then TEST_ENV+=(TMPDIR="$TMPDIR"); fi
    if [[ -n "${CHIT_FILE_STATE_DIRECTORY:-}" ]]; then TEST_ENV+=(CHIT_FILE_STATE_DIRECTORY="$CHIT_FILE_STATE_DIRECTORY"); fi
    if [[ -n "${CHIT_TEST_FILTER:-}" ]]; then
        env -i "${TEST_ENV[@]}" /usr/bin/xcrun xctest -XCTest "$CHIT_TEST_FILTER" "$BUNDLE"
    else
        env -i "${TEST_ENV[@]}" /usr/bin/xcrun xctest "$BUNDLE"
    fi
done
