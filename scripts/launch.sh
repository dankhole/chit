#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ ! -d "$ROOT/build/Chit.app" ]]; then "$ROOT/scripts/build.sh"; fi
if [[ $# -gt 0 ]]; then
    open -n "$ROOT/build/Chit.app" --args "$@"
else
    open "$ROOT/build/Chit.app"
fi
