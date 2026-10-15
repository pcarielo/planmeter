#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLANMETER_ICON_MODE=initials "$ROOT/scripts/build.sh"
python3 "$ROOT/tests/test_install.py"
python3 "$ROOT/tests/test_claude_integration.py"
python3 - "$ROOT" <<'PYTEST'
import os, pathlib, subprocess, sys, tempfile
with tempfile.TemporaryDirectory(prefix='planmeter-self-tests-') as home:
    executable=pathlib.Path(sys.argv[1])/'build/PlanMeter.app/Contents/MacOS/PlanMeter'
    subprocess.run([str(executable),'--self-test'],env=dict(os.environ,HOME=home),check=True,timeout=60)
PYTEST
python3 "$ROOT/tests/run-ui-tests.py"

python3 "$ROOT/tests/test_ui_isolation.py"
