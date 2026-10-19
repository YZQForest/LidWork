#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
build_root="$repo_root/build"
version="$(cat "$repo_root/VERSION")"
build_number="$(cat "$repo_root/BUILD_NUMBER")"

if [[ "$(uname -s)" != Darwin ]]; then
    echo '需要在 macOS 上构建。' >&2
    exit 1
fi
xcrun --find swiftc >/dev/null
xcrun --find clang >/dev/null
command -v python3 >/dev/null

mkdir -p "$build_root"
# Sign outside iCloud-managed Documents/Desktop; Finder metadata can otherwise
# be reattached to bundle directories while codesign is checking them.
stage="$(mktemp -d "${TMPDIR:-/tmp}/LidWork-build.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/合盖工作开关.app"
extension="$app/Contents/PlugIns/LidWorkNativeWidget.appex"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$extension/Contents/MacOS"
cp "$repo_root/resources/App/Info.plist" "$app/Contents/Info.plist"
cp "$repo_root/resources/App/LidWork.icns" "$app/Contents/Resources/LidWork.icns"
cp "$repo_root/resources/NativeWidget/Info.plist" "$extension/Contents/Info.plist"
python3 - "$app" "$version" "$build_number" <<'PY'
import pathlib, plistlib, sys
app = pathlib.Path(sys.argv[1])
for info in [app/'Contents/Info.plist', app/'Contents/PlugIns/LidWorkNativeWidget.appex/Contents/Info.plist']:
    data = plistlib.loads(info.read_bytes())
    data['CFBundleShortVersionString'] = sys.argv[2]
    data['CFBundleVersion'] = sys.argv[3]
    info.write_bytes(plistlib.dumps(data))
PY

xcrun --sdk macosx swiftc -O -target arm64-apple-macosx13.0 \
    "$repo_root/src/App/main.swift" \
    "$repo_root/src/App/MenuController.swift" \
    "$repo_root/src/App/Sidecar.swift" \
    -o "$app/Contents/MacOS/LidWork"

xcrun --sdk macosx clang -O2 -arch arm64 -fobjc-arc -mmacosx-version-min=13.0 \
    "$repo_root/src/DisplayHelper/VirtualCanvas.m" \
    -framework Foundation -framework CoreGraphics -framework IOKit \
    -o "$app/Contents/MacOS/LidWorkDisplay"

# WidgetKit's legacy macOS extension entry point is required when building
# with Command Line Tools. Swift's default @main entry traps in EXRunningExtension.
xcrun --sdk macosx swiftc -O -target arm64-apple-macosx14.0 \
    -application-extension -parse-as-library \
    "$repo_root/src/NativeWidget/LidWorkNativeWidget.swift" \
    -Xlinker -e -Xlinker _NSExtensionMain \
    -o "$extension/Contents/MacOS/LidWorkNativeWidget"

# Only strip Finder metadata from generated bundles, never quarantine settings.
xattr -r -d com.apple.FinderInfo "$app" 2>/dev/null || true
codesign --force --sign - "$app/Contents/MacOS/LidWorkDisplay"
codesign --force --sign - \
    --entitlements "$repo_root/resources/NativeWidget/Widget.entitlements" "$extension"
codesign --force --sign - "$app"
xattr -r -d com.apple.FinderInfo "$app" 2>/dev/null || true
codesign --verify --deep --strict "$app"
# This output is always a generated path inside the checkout.
rm -rf "$build_root/合盖工作开关.app"
ditto --norsrc --noextattr "$app" "$build_root/合盖工作开关.app"
echo "构建完成：$build_root/合盖工作开关.app"
