#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
bash "$ROOT/scripts/test_core.sh"
python3 -m unittest discover -s "$ROOT/tests" -p 'test_*.py' -v 2>&1 | tee "$ROOT/evidence/tooling-tests.txt"
