#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$ROOT" <<'PY'
import json, pathlib, platform, plistlib, shutil, sys
root=pathlib.Path(sys.argv[1])
print('PlanMeter local metadata only; no provider, authentication or Keychain calls.')
print('platform: '+platform.system()+' '+platform.release()+' / '+platform.machine())
for name in ('swiftc','python3','codesign','codex','claude'):
    print(name+': '+('available' if shutil.which(name) else 'not found'))
info=root/'build/PlanMeter.app/Contents/Info.plist'
try:
    data=plistlib.loads(info.read_bytes())
    print('build: '+str(data.get('CFBundleShortVersionString','unknown'))+' ('+str(data.get('CFBundleVersion','unknown'))+')')
except (OSError,ValueError): print('build: absent or invalid')
settings=pathlib.Path.home()/'.claude/settings.json'
print('Claude settings: '+('present' if settings.is_file() else 'absent'))
print('Claude integration: '+('present' if (pathlib.Path.home()/'Library/Application Support/PlanMeter/integration/config.json').is_file() else 'absent'))
PY
