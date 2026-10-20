#!/usr/bin/env python3
"""Update only LidWork and its widget; keep system daemons and display keeper alive."""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import tempfile
import time

BUNDLE_ID = 'local.yzq.lidwork'
REGISTER = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
EXTENSION = Path('Contents/PlugIns/LidWorkNativeWidget.appex')


def owned_processes(rows: str, app: Path) -> list[int]:
    paths = {str(app/'Contents/MacOS/LidWork'), str(app/EXTENSION/'Contents/MacOS/LidWorkNativeWidget')}
    return [int(parts[0]) for line in rows.splitlines() if len(parts := line.strip().split(None, 1)) == 2 and parts[1] in paths]


def read_info(app: Path) -> dict:
    return plistlib.loads((app/'Contents/Info.plist').read_bytes())


def validate_versions(app: Path) -> None:
    host = read_info(app)
    widget = read_info(app/EXTENSION)
    if host.get('CFBundleIdentifier') != BUNDLE_ID or widget.get('CFBundleIdentifier') != BUNDLE_ID+'.nativewidget':
        raise ValueError('应用或小组件标识不匹配')
    for key in ['CFBundleVersion', 'CFBundleShortVersionString']:
        if not host.get(key) or host[key] != widget.get(key):
            raise ValueError(f'宿主和小组件的 {key} 不一致')


def run(*args: str) -> None:
    subprocess.run(list(args), check=True)


def copy_app(source: Path, target: Path) -> None:
    run('/usr/bin/ditto', '--norsrc', '--noextattr', str(source), str(target))


def stop_owned(app: Path) -> None:
    rows = subprocess.check_output(['/bin/ps', '-axo', 'pid=,comm='], text=True)
    for pid in owned_processes(rows, app):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic()+4
    while time.monotonic() < deadline:
        rows = subprocess.check_output(['/bin/ps', '-axo', 'pid=,comm='], text=True)
        if not owned_processes(rows, app):
            return
        time.sleep(0.1)
    # Suspended extensions can defer SIGTERM. Recheck identity before SIGKILL.
    rows = subprocess.check_output(['/bin/ps', '-axo', 'pid=,comm='], text=True)
    for pid in owned_processes(rows, app):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def register(app: Path) -> None:
    run(REGISTER, '-f', str(app))
    run('/usr/bin/pluginkit', '-a', str(app/EXTENSION))


def install(source: Path, target: Path, show: bool) -> None:
    source, target = source.resolve(), target.expanduser().resolve()
    if source == target or target.suffix != '.app':
        raise ValueError('安装位置必须是与构建目录不同的 .app 路径')
    validate_versions(source)
    if target.exists() and read_info(target).get('CFBundleIdentifier') != BUNDLE_ID:
        raise ValueError('目标位置不是本项目应用，拒绝覆盖')
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='LidWork-install-') as scratch:
        temp = Path(scratch)
        candidate = temp/'incoming.app'
        copy_app(source, candidate)
        run('/usr/bin/codesign', '--verify', '--deep', '--strict', str(candidate))
        backup = temp/'previous.app'
        existed = target.exists()
        if existed:
            copy_app(target, backup)
        stop_owned(target)
        try:
            copy_app(candidate, target)
            validate_versions(target)
            # Check a metadata-free snapshot: iCloud may add FinderInfo on Desktop.
            check = temp/'installed.app'
            copy_app(target, check)
            run('/usr/bin/codesign', '--verify', '--deep', '--strict', str(check))
            json.loads(subprocess.check_output([str(target/'Contents/MacOS/LidWork'), '--snapshot-json'], text=True))
            register(target)
        except Exception:
            if existed:
                copy_app(backup, target)
                register(target)
                run('/usr/bin/open', '-g', str(target))
            raise
        run('/usr/bin/open', '-g', str(target))
        if show:
            run('/usr/bin/open', '-a', str(target), 'lidwork://show')
    print('已安装并重新注册主程序与小组件；显示器后台任务和现有开关未改动。')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1]/'build/合盖工作开关.app')
    parser.add_argument('--target', type=Path, default=Path.home()/'Desktop/合盖工作开关.app')
    parser.add_argument('--show', action='store_true')
    args = parser.parse_args()
    install(args.source, args.target, args.show)


if __name__ == '__main__':
    main()
