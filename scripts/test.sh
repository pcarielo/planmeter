#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLANMETER_ICON_MODE=initials "$ROOT/scripts/build.sh"
python3 "$ROOT/tests/test_install.py"
python3 "$ROOT/tests/test_claude_integration.py"
node "$ROOT/tests/test_connect_proxy.js"
python3 - "$ROOT" <<'PYTEST'
import os, pathlib, subprocess, sys, tempfile
with tempfile.TemporaryDirectory(prefix='planmeter-self-tests-') as home:
    executable=pathlib.Path(sys.argv[1])/'build/PlanMeter.app/Contents/MacOS/PlanMeter'
    probe=pathlib.Path(home)/'containment-probe'
    subprocess.run(['xcrun','clang',str(pathlib.Path(sys.argv[1])/'tests/fixtures/containment-probe.c'),'-o',str(probe)],check=True)
    subprocess.run(['node',str(pathlib.Path(sys.argv[1])/'tests/run-contained-network.js'),str(executable)],env=dict(os.environ,HOME=home,PLANMETER_TEST_NET_PROBE=str(probe)),check=True,timeout=70)
PYTEST
python3 "$ROOT/tests/run-ui-tests.py"

python3 "$ROOT/tests/test_ui_isolation.py"
