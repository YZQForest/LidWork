#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
stage="$(mktemp -d "${TMPDIR:-/tmp}/LidWork-verify.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/合盖工作开关.app"
ditto --norsrc --noextattr "$repo_root/build/合盖工作开关.app" "$app"
codesign --verify --deep --strict "$app"
python3 - "$app" "$(cat "$repo_root/VERSION")" <<'PY'
from pathlib import Path
import plistlib, subprocess, sys
app = Path(sys.argv[1])
extension = app/'Contents/PlugIns/LidWorkNativeWidget.appex'
host_info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
widget_info = plistlib.loads((extension/'Contents/Info.plist').read_bytes())
assert host_info['CFBundleShortVersionString'] == sys.argv[2]
assert widget_info['CFBundleShortVersionString'] == sys.argv[2]
assert host_info['CFBundleVersion'] == widget_info['CFBundleVersion']
assert host_info['CFBundleIdentifier'] == 'local.yzq.lidwork'
assert widget_info['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.widgetkit-extension'
assert (app/'Contents/Resources/LidWork.icns').stat().st_size > 0
for executable in [app/'Contents/MacOS/LidWork', app/'Contents/MacOS/LidWorkDisplay', extension/'Contents/MacOS/LidWorkNativeWidget']:
    architectures = subprocess.check_output(['/usr/bin/lipo', '-archs', str(executable)], text=True).strip()
    assert architectures == 'arm64', (executable, architectures)
symbols = subprocess.check_output(['/usr/bin/nm', '-u', str(extension/'Contents/MacOS/LidWorkNativeWidget')], text=True)
assert '_NSExtensionMain' in symbols
entitlements = subprocess.check_output(['/usr/bin/codesign', '-d', '--entitlements', ':-', str(extension)], stderr=subprocess.DEVNULL)
assert plistlib.loads(entitlements)['com.apple.security.app-sandbox'] is True
print('结构、版本、ARM64 架构、WidgetKit 入口及沙盒签名：通过')
PY
if [[ "${1:-}" == --live-status ]]; then
    # Read-only: these flags do not change sleep or display settings.
    "$app/Contents/MacOS/LidWork" --status
    "$app/Contents/MacOS/LidWork" --display-status
fi
