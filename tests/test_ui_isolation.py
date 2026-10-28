"""Integration regression: runs a disposable bundle, never the live identity."""
import pathlib
import plistlib
import subprocess
import tempfile
import unittest
import uuid

ROOT = pathlib.Path(__file__).resolve().parent
SOURCE = ROOT.parent / 'build/PlanMeter.app'
KEY = 'NSStatusItem VisibleCC Item-0'


class IsolationTests(unittest.TestCase):
    def test_unisolated_ui_entrypoint_refuses_before_changing_preferences(self):
        domain = 'io.github.pcarielo.planmeter.regression.' + uuid.uuid4().hex
        with tempfile.TemporaryDirectory(prefix='balance-guard-') as directory:
            app = pathlib.Path(directory) / 'Probe.app'
            subprocess.run(['/usr/bin/ditto', '--noextattr', str(SOURCE), str(app)], check=True)
            info = app / 'Contents/Info.plist'
            data = plistlib.loads(info.read_bytes())
            data['CFBundleIdentifier'] = domain
            info.write_bytes(plistlib.dumps(data))
            subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', str(app)], check=True, capture_output=True)
            try:
                subprocess.run(['/usr/bin/defaults', 'write', domain, KEY, '-bool', 'true'], check=True)
                result = subprocess.run([str(app / 'Contents/MacOS/PlanMeter'), '--x-self-test'], capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 2)
                self.assertIn('desconhecido', result.stderr)
                for mode in ('ui', 'confetti', 'loop'):
                    with self.subTest(mode=mode):
                        result = subprocess.run([str(app / 'Contents/MacOS/PlanMeter'), '--' + mode + '-self-test', '--codex', str(ROOT / 'fake-codex.py')], capture_output=True, text=True, timeout=30)
                        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                        self.assertIn('run-ui-tests.py', result.stderr)
                        value = subprocess.check_output(['/usr/bin/defaults', 'read', domain, KEY], text=True).strip()
                        self.assertEqual(value, '1')
            finally:
                subprocess.run(['/usr/bin/defaults', 'delete', domain], capture_output=True)


if __name__ == '__main__':
    unittest.main()
