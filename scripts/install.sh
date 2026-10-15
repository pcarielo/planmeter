#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 - "$ROOT" "$@" <<'PY'
import argparse, os, pathlib, plistlib, shutil, subprocess, sys, tempfile
root = pathlib.Path(sys.argv.pop(1))
p = argparse.ArgumentParser(description='Build and install PlanMeter for the current user.')
p.add_argument('--destination', default=str(pathlib.Path.home()/'Applications/PlanMeter.app'))
p.add_argument('--no-build', action='store_true'); p.add_argument('--no-launch', action='store_true')
p.add_argument('--login', action='store_true'); p.add_argument('--uninstall', action='store_true', help=argparse.SUPPRESS)
p.add_argument('--confirm-path', help=argparse.SUPPRESS)
a=p.parse_args()
def fail(message): sys.exit(message)
dest=pathlib.Path(a.destination).expanduser().absolute()
if dest.name != 'PlanMeter.app' or dest.is_symlink(): fail('Destination must be a non-symlink path ending in PlanMeter.app.')
def identity(bundle):
    try:
        with (bundle/'Contents/Info.plist').open('rb') as f: info=plistlib.load(f)
    except (OSError, ValueError): fail('Invalid app bundle: '+str(bundle))
    if info.get('CFBundleIdentifier')!='io.github.pcarielo.planmeter' or info.get('CFBundleExecutable')!='PlanMeter': fail('Refusing a bundle with another identity: '+str(bundle))
def running():
    output=subprocess.check_output(['ps','-axo','pid=,comm='],text=True)
    exe=str((dest/'Contents/MacOS/PlanMeter').resolve())
    for line in output.splitlines():
        parts=line.strip().split(None,1)
        if len(parts)==2 and os.path.realpath(parts[1])==exe: fail('Close PlanMeter before replacing or removing it (PID '+parts[0]+').')
if dest.exists(): identity(dest)
running()
if a.uninstall:
    if a.confirm_path != str(dest): fail('Confirmation must exactly match: '+str(dest))
    subprocess.run([str(root/'scripts/login-item.sh'),'disable','--destination',str(dest),'--if-matching'],check=True)
    if dest.exists(): shutil.rmtree(dest)
    print('Removed '+str(dest)+'. Cache, preferences and Keychain preserved.'); sys.exit(0)
if not a.no_build: subprocess.run([str(root/'scripts/build.sh')],check=True)
source=root/'build/PlanMeter.app'; identity(source)
if source.resolve()==dest.resolve(): fail('Destination cannot be the build source.')
subprocess.run(['codesign','--verify','--deep','--strict',str(source)],check=True)
dest.parent.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='.planmeter-install-',dir=dest.parent) as tmp:
    staged=pathlib.Path(tmp)/'PlanMeter.app'; shutil.copytree(source,staged,symlinks=True)
    subprocess.run(['codesign','--verify','--deep','--strict',str(staged)],check=True)
    running()
    backup=pathlib.Path(tmp)/'previous.app'
    if dest.exists(): dest.rename(backup)
    try: staged.rename(dest)
    except OSError:
        if backup.exists(): backup.rename(dest)
        raise
if a.login: subprocess.run([str(root/'scripts/login-item.sh'),'enable','--destination',str(dest)],check=True)
if not a.no_launch: subprocess.run(['open',str(dest)],check=True)
print('Installed '+str(dest))
PY
