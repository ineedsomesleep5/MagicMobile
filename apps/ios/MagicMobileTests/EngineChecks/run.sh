#!/usr/bin/env bash
# Run after building the pinned JVM adapter; this is not native gameplay proof.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../../.." && pwd)
ENGINE="$ROOT/packages/ondevice-engine"
CP=$(<"$ENGINE/build/runtime-classpath.txt")
OUT=$(mktemp -d "$ENGINE/build/card-choice-check.XXXXXX")
python3 - "$CP" "$OUT" "$ROOT/apps/ios/MagicMobileTests/EngineChecks" <<'PY'
import subprocess, sys
cp, output, source = sys.argv[1:]
suites = ['RealCardChoiceTests', 'RealPaymentInteractionTests']
subprocess.run(['javac', '-J-Xmx256m', '--release', '17', '-proc:none',
                '-sourcepath', output, '-cp', cp, '-d', output,
                *[source + '/' + suite + '.java' for suite in suites]], check=True, timeout=60)
for suite in suites:
    subprocess.run(['java', '-Xmx384m', '-Djava.awt.headless=true', '-cp', cp + ':' + output,
                    'io.magicmobile.xmage.' + suite], cwd=output, check=True, timeout=90)
PY
