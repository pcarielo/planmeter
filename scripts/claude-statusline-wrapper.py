#!/usr/bin/env python3
"""Preserve the user's trusted statusline command, then cache sanitized observations."""
import json
from pathlib import Path
import subprocess
import sys


def main():
    directory = Path(__file__).resolve().parent
    config = directory/'config.json'
    try:
        if config.is_symlink(): return 1
        settings = json.loads(config.read_text())
        command = settings.get('originalCommand')
        if command is not None and not isinstance(command, str): return 1
    except (OSError, ValueError, AttributeError):
        return 1
    raw = sys.stdin.buffer.read()
    code = 0
    if command:
        # This is the user's existing trusted shell command, never payload content.
        code = subprocess.run(command, shell=True, input=raw).returncode
    try:
        subprocess.run([sys.executable, str(directory/'claude-statusline-cache.py')],
                       input=raw, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
    except (OSError, subprocess.SubprocessError):
        pass
    return code if code >= 0 else 128 - code

if __name__ == '__main__':
    sys.exit(main())
