#!/bin/bash
set -euo pipefail
exec python3 - "$@" <<'PY'
import argparse, os, pathlib, plistlib, subprocess, tempfile
p=argparse.ArgumentParser(description='Manage the optional PlanMeter login agent for one exact installation.')
p.add_argument('action',choices=['enable','disable','status'])
p.add_argument('--destination',default=str(pathlib.Path.home()/'Applications/PlanMeter.app'))
p.add_argument('--if-matching',action='store_true',help=argparse.SUPPRESS)
a=p.parse_args(); label='io.github.pcarielo.planmeter'; domain='gui/'+str(os.getuid())
path=pathlib.Path.home()/'Library/LaunchAgents'/ (label+'.plist')
app=pathlib.Path(a.destination).expanduser().absolute(); exe=app/'Contents/MacOS/PlanMeter'
def call(*args): return subprocess.run(['launchctl',*args],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
def ownership():
    if path.is_symlink() or path.parent.is_symlink(): return 'unmanaged'
    if not path.exists(): return 'absent'
    try:
        with path.open('rb') as f: data=plistlib.load(f)
    except (OSError,ValueError,TypeError): return 'unmanaged'
    if not isinstance(data,dict) or data.get('Label')!=label or data.get('ProgramArguments')!=[str(exe)]: return 'unmanaged'
    return 'matching'
state=ownership()
if a.action=='status':
    print({'matching':'enabled for this installation','unmanaged':'unmanaged login item preserved','absent':'disabled'}[state])
    raise SystemExit(0)
if state=='unmanaged':
    if a.action=='disable' and a.if_matching:
        print('Preserved login item: it is not a regular matching PlanMeter plist.')
        raise SystemExit(0)
    raise SystemExit('Refusing to change an unrecognized, different-installation or symlink login item.')
if a.action=='disable':
    if state=='matching':
        result=call('bootout',domain+'/'+label)
        if result.returncode not in (0,3,113): raise SystemExit('launchctl bootout failed; login item preserved.')
        if ownership()!='matching': raise SystemExit('Login item changed during removal; preserved.')
        path.unlink()
else:
    with (app/'Contents/Info.plist').open('rb') as f: info=plistlib.load(f)
    if info.get('CFBundleIdentifier')!=label or not os.access(exe,os.X_OK): raise SystemExit('Invalid PlanMeter installation.')
    if state=='matching' and call('print',domain+'/'+label).returncode==0:
        if call('bootout',domain+'/'+label).returncode!=0: raise SystemExit('Could not unload existing login item.')
    path.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent,delete=False) as f:
        temporary=pathlib.Path(f.name)
        plistlib.dump({'Label':label,'ProgramArguments':[str(exe)],'RunAtLoad':True},f)
    if ownership()!=state:
        temporary.unlink()
        raise SystemExit('Login item changed during configuration; preserved.')
    temporary.replace(path)
    if call('bootstrap',domain,str(path)).returncode!=0: raise SystemExit('Could not enable login item; inspect '+str(path))
    print('Login item enabled.')
PY
