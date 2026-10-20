from pathlib import Path
import importlib.util
import plistlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('install_local', Path(__file__).resolve().parents[1]/'scripts/install_local.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallerRegressionTests(unittest.TestCase):
    def test_only_own_host_and_resident_widget_are_stopped(self):
        app = Path('/example/with spaces/合盖工作开关.app')
        rows = f'''12 {app}/Contents/MacOS/LidWork
13 {app}/{installer.EXTENSION}/Contents/MacOS/LidWorkNativeWidget
14 /Library/LidWorkDisplay
15 /different/合盖工作开关.app/Contents/MacOS/LidWork
16 {app}/Contents/MacOS/LidWorkExtra
17 /System/Library/CoreServices/NotificationCenter.app/Contents/MacOS/NotificationCenter
'''
        self.assertEqual(installer.owned_processes(rows, app), [12, 13])

    def test_version_mismatch_rejected_before_install(self):
        with tempfile.TemporaryDirectory() as scratch:
            app = Path(scratch)/'Example.app'
            for bundle, identifier, build in [(app, installer.BUNDLE_ID, '9'), (app/installer.EXTENSION, installer.BUNDLE_ID+'.nativewidget', '8')]:
                (bundle/'Contents').mkdir(parents=True)
                (bundle/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': identifier, 'CFBundleVersion': build, 'CFBundleShortVersionString': '1.5.0'}))
            with self.assertRaisesRegex(ValueError, 'CFBundleVersion'):
                installer.validate_versions(app)
            path = app/installer.EXTENSION/'Contents/Info.plist'
            data = plistlib.loads(path.read_bytes()); data['CFBundleVersion'] = '9'
            path.write_bytes(plistlib.dumps(data))
            installer.validate_versions(app)


if __name__ == '__main__':
    unittest.main()
