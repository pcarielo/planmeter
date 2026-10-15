#!/usr/bin/env python3
"""Run AppKit fixture tests with a fresh bundle/preferences identity per invocation."""
import argparse
import pathlib
import plistlib
import subprocess
import tempfile
import uuid

ROOT = pathlib.Path(__file__).resolve().parent
MODES = ('ui', 'confetti', 'loop')


def preferences(domain):
    result = subprocess.run(['/usr/bin/defaults', 'export', domain, '-'], capture_output=True)
    if result.returncode:
        # Distinguish a missing domain from an unreadable existing preferences file.
        path = pathlib.Path.home() / 'Library/Preferences' / (domain + '.plist')
        if path.exists():
            raise RuntimeError('Could not read preferences: ' + domain)
        return None
    return plistlib.loads(result.stdout)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=pathlib.Path, default=ROOT.parent / 'build/PlanMeter.app')
    parser.add_argument('--mode', choices=MODES, default='ui')
    args = parser.parse_args()
    source = args.app.resolve(strict=True)
    domain = 'io.github.pcarielo.planmeter.tests.' + str(uuid.uuid4())
    before = preferences('io.github.pcarielo.planmeter')
    try:
        with tempfile.TemporaryDirectory(prefix='planmeter-ui-') as directory:
            app = pathlib.Path(directory) / 'PlanMeter Tests.app'
            subprocess.run(['/usr/bin/ditto', '--noextattr', str(source), str(app)], check=True)
            info = app / 'Contents/Info.plist'
            data = plistlib.loads(info.read_bytes())
            data['CFBundleIdentifier'] = domain
            data['CFBundleName'] = 'PlanMeter Tests'
            data['CFBundleDisplayName'] = 'PlanMeter Tests'
            info.write_bytes(plistlib.dumps(data))
            subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', str(app)], check=True, capture_output=True)
            subprocess.run(['/usr/bin/codesign', '--verify', '--strict', str(app)], check=True)
            command = [str(app / 'Contents/MacOS/PlanMeter'), '--' + args.mode + '-self-test']
            if args.mode == 'ui':
                command += ['--codex', str(ROOT / 'fake-codex.py')]
            subprocess.run(command, check=True, timeout=120)
    finally:
        # Delete only the unique synthetic domain, never the user's preferences.
        subprocess.run(['/usr/bin/defaults', 'delete', domain], capture_output=True)
        if preferences('io.github.pcarielo.planmeter') != before:
            raise RuntimeError('Monitor preferences changed during test; investigate before continuing.')
    print('PASS isolation: unique test identity; monitor preferences unchanged')


if __name__ == '__main__':
    main()
