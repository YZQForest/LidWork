#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
stage="$(mktemp -d "${TMPDIR:-/tmp}/LidWork-tests.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
xcrun swiftc "$repo_root/src/Shared/DeviceSnapshot.swift" "$repo_root/src/Shared/OwnedWidgetProcess.swift" "$repo_root/tests/main.swift" -o "$stage/tests"
"$stage/tests"
python3 "$repo_root/tests/test_installer.py"
