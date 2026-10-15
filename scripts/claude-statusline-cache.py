#!/usr/bin/env python3
"""Passive, sanitized cache of Claude Code's official statusline input. No API calls."""
import hashlib
import json
import math
import os
from pathlib import Path
import sys
import tempfile
import time


def valid_number(value):
    return not isinstance(value, bool) and isinstance(value, (int, float)) and math.isfinite(value)


def selected_limits(payload):
    limits = payload.get('rate_limits')
    if not isinstance(limits, dict):
        return {}
    out = {}
    for name in ('five_hour', 'seven_day'):
        item = limits.get(name)
        if not isinstance(item, dict):
            continue
        used, reset = item.get('used_percentage'), item.get('resets_at')
        out[name] = {'used_percentage': used if valid_number(used) and 0 <= used <= 100 else None,
                     'resets_at': reset if valid_number(reset) and 0 <= reset <= 253402300799 else None}
    return out


def build_cache(payload, prior, now):
    limits = selected_limits(payload)
    cost = payload.get('cost') if isinstance(payload.get('cost'), dict) else {}
    context = payload.get('context_window') if isinstance(payload.get('context_window'), dict) else {}
    activity = {'session': payload.get('session_id'), 'apiDuration': cost.get('total_api_duration_ms'),
                'input': context.get('total_input_tokens'), 'output': context.get('total_output_tokens'), 'limits': limits}
    signature = hashlib.sha256(json.dumps(activity, sort_keys=True).encode()).hexdigest()
    observed = prior.get('providerObservedAt')
    same = prior.get('activitySignature') == signature and valid_number(observed)
    return {'source': 'claude-code-statusline', 'provider': 'claude', 'capturedAt': now,
            'providerObservedAt': observed if same else now, 'identityFingerprint': None,
            'activitySignature': signature, 'rateLimits': limits,
            'freshnessMeaning': 'passive statusline observation; account identity not verified'}


def main():
    try:
        raw = sys.stdin.buffer.read(262145)
        if len(raw) > 262144: return 0
        payload = json.loads(raw)
        if not isinstance(payload, dict): return 0
        directory = Path.home()/'Library/Application Support/PlanMeter'
        path = directory/'claude-statusline.json'
        if directory.is_symlink() or path.is_symlink(): return 0
        try:
            prior = json.loads(path.read_text())
            if not isinstance(prior, dict): prior = {}
        except (OSError, ValueError): prior = {}
        cache = build_cache(payload, prior, time.time())
        directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        fd, temporary = tempfile.mkstemp(prefix='.claude-statusline-', dir=directory)
        try:
            with os.fdopen(fd, 'w') as f: json.dump(cache, f, allow_nan=False)
            os.chmod(temporary, 0o600); os.replace(temporary, path)
        finally:
            if os.path.exists(temporary): os.unlink(temporary)
    except (OSError, ValueError, TypeError, OverflowError):
        pass
    return 0

if __name__ == '__main__':
    sys.exit(main())
