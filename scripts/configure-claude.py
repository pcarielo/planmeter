#!/usr/bin/env python3
"""Explicit, reversible installation of PlanMeter's passive Claude statusline adapter."""
import argparse
import json
import os
from pathlib import Path
import shlex
import sys
import tempfile
import time


def write_private(path, raw):
    fd, temporary = tempfile.mkstemp(prefix='.planmeter-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as f: f.write(raw)
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--check', action='store_true'); mode.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    settings = Path.home()/'.claude/settings.json'
    integration = Path.home()/'Library/Application Support/PlanMeter/integration'
    config = integration/'config.json'
    for path in (settings.parent, settings, integration.parent, integration, config, integration/'claude-statusline-wrapper.py', integration/'claude-statusline-cache.py'):
        if path.is_symlink(): raise ValueError('Symlink configuration is unsupported; no settings changed.')
    raw = settings.read_bytes() if settings.exists() else b'{}'
    data = json.loads(raw)
    if not isinstance(data, dict): raise ValueError('Claude settings must be a JSON object.')
    line = data.get('statusLine')
    if line is not None and (not isinstance(line, dict) or line.get('type') != 'command' or not isinstance(line.get('command'), str)):
        raise ValueError('Unsupported statusLine; no settings changed.')
    wrapper = integration/'claude-statusline-wrapper.py'
    expected = shlex.join(['python3',str(wrapper)])
    installed = line is not None and line.get('command') == expected
    if installed:
        existing = json.loads(config.read_text())
        if not isinstance(existing, dict) or existing.get('version') != 1 or (existing.get('originalCommand') is not None and not isinstance(existing.get('originalCommand'), str)):
            raise ValueError('Invalid integration configuration; no settings changed.')
    elif line and 'claude-statusline-wrapper.py' in line['command']:
        raise ValueError('Another wrapper configuration exists; no settings changed.')
    if args.check:
        print('settings: '+('present' if settings.exists() else 'absent'))
        print('statusline: '+('PlanMeter' if installed else 'custom' if line else 'absent'))
        print('passive cache: '+('present' if (integration.parent/'claude-statusline.json').is_file() else 'absent'))
        return 0
    # Validate/read all source helpers before any configuration changes.
    helpers={name:(Path(__file__).parent/name).read_bytes() for name in ('claude-statusline-wrapper.py','claude-statusline-cache.py')}
    integration.mkdir(mode=0o700, parents=True, exist_ok=True)
    for name, content in helpers.items(): write_private(integration/name,content)
    if installed:
        print('PlanMeter integration already enabled; helpers refreshed.')
        return 0
    original = line.get('command') if line else None
    write_private(config,json.dumps({'version':1,'originalCommand':original}).encode())
    settings.parent.mkdir(mode=0o700,parents=True,exist_ok=True)
    if settings.exists():
        backup=settings.with_name('settings.json.planmeter-backup-'+str(time.time_ns()))
        descriptor=os.open(backup,os.O_WRONLY | os.O_CREAT | os.O_EXCL,0o600)
        with os.fdopen(descriptor,'wb') as f: f.write(raw)
    changed=dict(line) if line else {'type':'command'}
    changed['command']=expected; data['statusLine']=changed
    write_private(settings,(json.dumps(data,indent=2,ensure_ascii=False)+'\n').encode())
    print('PlanMeter integration enabled. Existing settings preserved; private backup created when applicable.')
    return 0

if __name__ == '__main__':
    try: sys.exit(main())
    except (OSError, ValueError, TypeError):
        print('Configuration unavailable or unsupported; no statusline replacement performed.',file=sys.stderr)
        sys.exit(1)
