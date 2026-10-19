#!/usr/bin/env python3
"""Prepare local icon resources, keeping provider artwork out of the repository."""
import argparse
import hashlib
import json
import os
import pathlib
import shutil
import urllib.request

ROOT=pathlib.Path(__file__).resolve().parent.parent

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=pathlib.Path,required=True)
    args=parser.parse_args()
    mode=os.environ.get('PLANMETER_ICON_MODE','provider')
    if mode not in ('provider','initials'):raise SystemExit('Invalid PLANMETER_ICON_MODE')
    args.output.mkdir(parents=True,exist_ok=True)
    for name in ('codex','claude','zai','kimi'):
        for ext in ('svg','ico','png'):(args.output/(name+'.'+ext)).unlink(missing_ok=True)
    if mode=='initials':
        for name,letter in [('codex','C'),('claude','A'),('zai','Z'),('kimi','K')]:
            (args.output/(name+'.svg')).write_text('<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><rect width="16" height="16" rx="3" fill="#e5e5e5"/><text x="8" y="12" text-anchor="middle" font-family="sans-serif" font-size="12" fill="#151515">'+letter+'</text></svg>')
        return
    manifest=json.loads((ROOT/'scripts/provider-icons.json').read_text())
    cache=ROOT/'build/provider-icons';cache.mkdir(parents=True,exist_ok=True)
    for name,entry in manifest.items():
        path=cache/name
        if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest()!=entry['sha256']:
            request=urllib.request.Request(entry['url'],headers={'User-Agent':'Mozilla/5.0'})
            with urllib.request.urlopen(request,timeout=15) as response:data=response.read(1048577)
            if len(data)>1048576 or hashlib.sha256(data).hexdigest()!=entry['sha256']:
                raise SystemExit('Provider icon changed: '+name+'. Review the source or build with PLANMETER_ICON_MODE=initials.')
            path.write_bytes(data)
        shutil.copyfile(path,args.output/name)

if __name__=='__main__':main()
