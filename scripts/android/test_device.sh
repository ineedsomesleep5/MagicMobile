#!/usr/bin/env bash
# Test an already installed native debug build without touching player data.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
: "${ANDROID_HOME:?Set ANDROID_HOME to the Android SDK}"
: "${ANDROID_SERIAL:?Choose the existing Android device explicitly}"
: "${MM_ANDROID_TEST_PACKAGE:?Set the installed instrumentation package}"
[[ "$MM_ANDROID_TEST_PACKAGE" =~ ^com\.calebfeliciano\.magicmobile\.android\.[a-zA-Z0-9_]+\.test$ ]] || {
  echo "Expected the dedicated MagicMobile debug instrumentation package." >&2; exit 2;
}
mkdir -p "$ROOT/build_output/android-acceptance"
REPORT=$(mktemp "$ROOT/build_output/android-acceptance/instrumentation-XXXXXX")
"$ANDROID_HOME/platform-tools/adb" -s "$ANDROID_SERIAL" shell am instrument -w \
  -e package io.magicmobile.android \
  "$MM_ANDROID_TEST_PACKAGE/androidx.test.runner.AndroidJUnitRunner" | tee "$REPORT"
# adb can return zero even when the instrumentation process crashes.
if grep -Eq 'INSTRUMENTATION_FAILED|shortMsg=|FAILURES!!!' "$REPORT" ||
   ! grep -Eq '^OK \([1-9][0-9]* tests?\)' "$REPORT"; then
  echo "Android acceptance FAILED; see $REPORT" >&2; exit 1
fi
echo "Android device checks passed; report: $REPORT"
