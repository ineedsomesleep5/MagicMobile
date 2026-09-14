#!/usr/bin/env bash
# Regression proof only: original session + new tests must fail for all six known bugs.
# Other sources remain the audit candidate. No native engine, signing or phone claim.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
BASE=7992311b4a41720f9a37858e44dbd5122ae5bdb2
SESSION=apps/ios/MagicMobile/OnDeviceSession.swift
LOG=packages/ondevice-engine/evidence/session-recovery-before.log
mkdir -p "$(dirname "$LOG")"
SAVED=$(mktemp)
cp "$SESSION" "$SAVED"
restore() { cp "$SAVED" "$SESSION"; rm -f "$SAVED"; }
trap restore EXIT
git show "$BASE:$SESSION" > "$SESSION"
status=0
swift test --package-path apps/ios --filter OnDeviceReleaseRecoveryTests > "$LOG" 2>&1 || status=$?
if [[ "$status" == 0 ]]; then
  echo "ERROR: original session unexpectedly passed the regression suite" >&2
  exit 1
fi
python3 - "$LOG" <<'PY'
import pathlib, sys
lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
expected = [
    'testAcknowledgedAnswerSurvivesRejectedFollowupPoll',
    'testBackgroundDiscardsOutstandingPoll',
    'testResumeDoesNotAcceptAPreSuspensionPoll',
    'testBusyCloseRejectsNewWorkUntilCloseSucceeds',
    'testUnexpectedTransportCancellationCanResumePolling',
    'testOldRefreshErrorDoesNotEscapeIntoReplacementSession',
]
missing = [name for name in expected if not any(
    'Test Case ' in line and name in line and ' failed ' in line for line in lines)]
if missing:
    print('\n'.join(lines[-100:]))
    raise SystemExit('Expected executed failing regression cases are missing: ' + ', '.join(missing))
print('PASS: all six session recovery regressions fail against the original session source.')
print('Scope: Swift presentation/transport fixtures, not XMage/native/iPhone gameplay.')
PY
