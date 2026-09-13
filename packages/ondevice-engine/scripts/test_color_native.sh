#!/usr/bin/env bash
# Native dependency regression only; does not execute an iPhone or complete game.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export JAVA_HOME="${MM_GRAALVM_HOME:-$ROOT/build/toolchains/graalvm-svm-java17-darwin-m1-gluon-22.1.0.1-Final/Contents/Home}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
PROBE_BUILD=$(mktemp -d "$ROOT/build/color-native-XXXXXX")
MAGE_CLASSES="$ROOT/.upstream/mage/Mage/target/classes"
[[ -s "$MAGE_CLASSES/mage/abilities/hint/HintUtils.class" ]]
mkdir -p "$PROBE_BUILD/classes"
"$JAVA_HOME/bin/javac" -J-Xmx128m -cp "$MAGE_CLASSES" -d "$PROBE_BUILD/classes" \
  "$ROOT/native/gluon/probes/ColorValueProbe.java"
CP="$PROBE_BUILD/classes:$MAGE_CLASSES"
ARGS=(--no-fallback -J-Xmx1g -H:NumberOfThreads=2 "-H:Path=$PROBE_BUILD" --initialize-at-run-time=mage)
printf 'Native color regression: %s\n' "$PROBE_BUILD"
"$JAVA_HOME/bin/native-image" "${ARGS[@]}" --initialize-at-run-time=java.awt.Color,java.awt.Toolkit \
  -cp "$CP" -H:Name=baseline ColorValueProbe > "$PROBE_BUILD/baseline-build.log" 2>&1
if "$PROBE_BUILD/baseline" > "$PROBE_BUILD/baseline-run.log" 2>&1; then
  echo 'Baseline unexpectedly passed; re-evaluate the native AWT reproduction' >&2; exit 1
fi
grep 'UnsatisfiedLinkError: no awt in java.library.path' "$PROBE_BUILD/baseline-run.log"
grep 'java.awt.Color.<clinit>' "$PROBE_BUILD/baseline-run.log"
echo 'PASS baseline reproduces the reported Color/Toolkit native failure'
COLOR_ARG=$(python3 - "$ROOT/native/gluon/pom.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
args = [e.text for e in ET.parse(sys.argv[1]).iter('{http://maven.apache.org/POM/4.0.0}arg')]
selected = [a for a in args if a and a.startswith('--initialize-at-build-time=') and 'java.awt' in a]
if selected != ['--initialize-at-build-time=java.awt.Color']:
    raise SystemExit('Require the exact reviewed Color-only native initialization policy')
print(selected[0])
PY
)
"$JAVA_HOME/bin/native-image" "${ARGS[@]}" "$COLOR_ARG" \
  -cp "$CP" -H:Name=adapted ColorValueProbe > "$PROBE_BUILD/adapted-build.log" 2>&1
for headless in true false; do
  expected=$("$JAVA_HOME/bin/java" -Xmx128m "-Djava.awt.headless=$headless" -cp "$CP" ColorValueProbe)
  actual=$("$PROBE_BUILD/adapted" "-Djava.awt.headless=$headless")
  [[ "$actual" == "$expected" ]] || { echo 'Native Color/XMage values differ from the JVM' >&2; exit 1; }
  printf '%s (headless=%s)\n' "$actual" "$headless"
done
printf 'PASS native dependency regression; iPhone/full-engine acceptance remains separate. Evidence: %s\n' "$PROBE_BUILD"
