#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
version="$(cat "$repo_root/VERSION")"
app="$repo_root/build/合盖工作开关.app"
dist="$repo_root/dist"
stem="LidWork-$version-macos-arm64"

if [[ ! -x "$app/Contents/MacOS/LidWork" ]]; then
    echo '请先运行 ./scripts/build.sh。' >&2
    exit 1
fi
mkdir -p "$dist"
stage="$(mktemp -d "${TMPDIR:-/tmp}/LidWork-package.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
ditto --norsrc --noextattr "$app" "$stage/合盖工作开关.app"
app="$stage/合盖工作开关.app"
codesign --verify --deep --strict "$app"
ln -s /Applications "$stage/Applications"
cp "$repo_root/docs/INSTALL.zh-CN.txt" "$stage/安装说明.txt"

# ZIP stores Unicode names with UTF-8 flags and no Finder/resource-fork metadata.
python3 - "$app" "$dist/$stem.zip" <<'PY'
from pathlib import Path
import stat, sys, zipfile
app = Path(sys.argv[1])
with zipfile.ZipFile(sys.argv[2], 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for path in sorted(app.rglob('*')):
        if not path.is_file():
            continue
        item = zipfile.ZipInfo.from_file(path, path.relative_to(app.parent).as_posix())
        item.create_system = 3
        item.compress_type = zipfile.ZIP_DEFLATED
        item.external_attr = (stat.S_IFREG | stat.S_IMODE(path.stat().st_mode)) << 16
        archive.writestr(item, path.read_bytes())
PY
hdiutil create -quiet -ov -format UDZO -volname "合盖工作开关 $version" \
    -srcfolder "$stage" "$dist/$stem.dmg"
cp "$repo_root/docs/INSTALL.zh-CN.txt" "$dist/INSTALL.zh-CN.txt"
(
    cd "$dist"
    shasum -a 256 "$stem.zip" "$stem.dmg" INSTALL.zh-CN.txt > SHA256SUMS.txt
    shasum -a 256 -c SHA256SUMS.txt
)
echo "发布文件：$dist"
