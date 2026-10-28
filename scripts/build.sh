#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Darwin ]] || { echo 'PlanMeter requires macOS and Xcode Command Line Tools.' >&2; exit 1; }
xcrun --find swiftc >/dev/null
ARCH="${PLANMETER_ARCH:-$(uname -m)}"
case "$ARCH" in arm64|x86_64) ;; *) echo 'Unsupported architecture.' >&2; exit 2 ;; esac
APP="$ROOT/build/PlanMeter.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
SWIFT_FLAGS=(-swift-version 5)
if [[ "${PLANMETER_DEVELOPMENT:-0}" == 1 ]]; then SWIFT_FLAGS+=(-D PLANMETER_DEVELOPMENT); fi
xcrun swiftc "${SWIFT_FLAGS[@]}" -O -target "$ARCH-apple-macosx13.0" -framework AppKit -framework Security app/*.swift -o "$APP/Contents/MacOS/PlanMeter"
python3 - "$ROOT" "$APP" <<'PY'
import os, pathlib, plistlib, re, shutil, sys
root, app=map(pathlib.Path,sys.argv[1:])
resources=root/'app/Resources'
if resources.exists(): shutil.copytree(resources,app/'Contents/Resources',dirs_exist_ok=True)
integration=app/'Contents/Resources/Integration'; integration.mkdir(parents=True,exist_ok=True)
for name in ('configure-claude.py','claude-statusline-wrapper.py','claude-statusline-cache.py'):
    shutil.copy2(root/'scripts'/name,integration/name)
product_id=os.environ.get('PLANMETER_PRO_PRODUCT_ID','io.github.pcarielo.planmeter.pro')
if not re.fullmatch(r'[A-Za-z0-9._-]{1,255}',product_id): raise SystemExit('Invalid Pro product identifier.')
info={'CFBundleIdentifier' :'io.github.pcarielo.planmeter','CFBundleName':'PlanMeter','CFBundleDisplayName':'PlanMeter','CFBundleExecutable':'PlanMeter','CFBundlePackageType':'APPL','CFBundleShortVersionString':'1.6.1','CFBundleVersion':'14','LSMinimumSystemVersion':'13.0','LSUIElement':True,'NSHighResolutionCapable':True}
info['PlanMeterProProductID']=product_id
if (app/'Contents/Resources/AppIcon.icns').exists(): info['CFBundleIconFile']='AppIcon'
with (app/'Contents/Info.plist').open('wb') as f: plistlib.dump(info,f)
PY
python3 "$ROOT/scripts/fetch-icons.py" --output "$APP/Contents/Resources"
codesign --force --sign "${PLANMETER_SIGN_IDENTITY:--}" --identifier io.github.pcarielo.planmeter "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built %s (%s, macOS 13+)\n' "$APP" "$ARCH"
