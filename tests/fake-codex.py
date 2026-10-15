#!/usr/bin/env python3
# Deterministic local transport fixture; never contacts a service.
import json, os, sys, time
mode = os.environ.get('QUOTA_FIXTURE', 'success')
for line in sys.stdin:
    msg = json.loads(line)
    method = msg.get('method')
    if method == 'initialized':
        continue
    if mode == 'timeout':
        time.sleep(30)
        break
    if mode == 'malformed':
        print('invalid-json', flush=True)
        break
    if method == 'initialize':
        result = {}
    elif method == 'account/read':
        result = {'account': {'type': 'apiKey' if mode == 'wrong-account' else 'chatgpt'}}
    elif method == 'account/rateLimits/read':
        if mode == 'rpc-error':
            print(json.dumps({'id': msg['id'], 'error': {'code': -1, 'message': 'not forwarded'}}), flush=True)
            continue
        result = {'rateLimitsByLimitId': {'codex': {'primary': {'usedPercent': 37, 'windowDurationMins': 120, 'resetsAt': 0}, 'secondary': None}}}
    else:
        raise SystemExit('Unexpected RPC')
    print(json.dumps({'id': msg['id'], 'result': result}), flush=True)
