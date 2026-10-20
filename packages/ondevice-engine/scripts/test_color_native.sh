#!/usr/bin/env bash
# Native dependency regression only; does not execute an iPhone or complete game.
# JDK 17's java.awt.Color initializer loaded the desktop AWT library (Toolkit.loadLibraries(),
# initIDs()), which failed natively, so 22.1 builds patched it. JDK 23's Color has no such
# initializer, so release D builds the JDK's own class: this checks that the reason still holds,
# that the pom keeps the runtime Color/Toolkit policy without a patch, and that native values
# match the JVM. docs/NATIVE_COLOR_COMPATIBILITY.md
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export JAVA_HOME="${MM_GRAALVM_HOME:-$ROOT/build/toolchains/graalvm-java23-darwin-aarch64-gluon-23+25.1-dev/Contents/Home}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
PROBE_BUILD=$(mktemp -d "$ROOT/build/color-native-XXXXXX")
MAGE_CLASSES="$ROOT/.upstream/mage/Mage/target/classes"
[[ -s "$MAGE_CLASSES/mage/abilities/hint/HintUtils.class" ]]
COLOR_ARG=$(python3 - "$JAVA_HOME/lib/src.zip" "$ROOT/native/gluon/pom.xml" <<'PY'
import hashlib, sys, zipfile, xml.etree.ElementTree as ET
source = zipfile.ZipFile(sys.argv[1]).read('java.desktop/java/awt/Color.java')
text = source.decode('utf-8')
for desktop in ('Toolkit.loadLibraries()', 'initIDs()', 'static {'):
    if desktop in text:
        raise SystemExit(f'JDK Color again contains {desktop!r}; restore the native Color adaptation')
print('JDK Color source sha256 ' + hashlib.sha256(source).hexdigest() + ': no desktop JNI initializer', file=sys.stderr)
args = [e.text or '' for e in ET.parse(sys.argv[2]).iter('{http://maven.apache.org/POM/4.0.0}arg')]
runtime = '--initialize-at-run-time=java.awt.Color,java.awt.Toolkit'
if runtime not in args or any('java.desktop' in a for a in args) \
        or any(a.startswith('--initialize-at-build-time=') and 'java.awt' in a for a in args):
    raise SystemExit('Require runtime Color/Toolkit and no java.desktop patch in the pom')
print(runtime)
PY
)
mkdir -p "$PROBE_BUILD/classes"
"$JAVA_HOME/bin/javac" -J-Xmx128m -cp "$MAGE_CLASSES" -d "$PROBE_BUILD/classes" \
  "$ROOT/native/gluon/probes/ColorValueProbe.java"
CP="$PROBE_BUILD/classes:$MAGE_CLASSES"
ARGS=(--no-fallback -J-Xmx1g -H:NumberOfThreads=2 "-H:Path=$PROBE_BUILD" --initialize-at-run-time=mage)
printf 'Native color regression: %s\n' "$PROBE_BUILD"
"$JAVA_HOME/bin/native-image" "${ARGS[@]}" "$COLOR_ARG" \
  -cp "$CP" -H:Name=production ColorValueProbe > "$PROBE_BUILD/production-build.log" 2>&1
for headless in true false; do
  expected=$("$JAVA_HOME/bin/java" -Xmx128m "-Djava.awt.headless=$headless" -cp "$CP" ColorValueProbe)
  actual=$("$PROBE_BUILD/production" "-Djava.awt.headless=$headless")
  [[ "$actual" == "$expected" ]] || { echo 'Native Color/XMage values differ from the JVM' >&2; exit 1; }
  printf '%s (headless=%s)\n' "$actual" "$headless"
done
"$PROBE_BUILD/production" --desktop-guard | tee "$PROBE_BUILD/desktop-guard.log"
grep 'PASS desktop Toolkit still fails explicitly without AWT' "$PROBE_BUILD/desktop-guard.log"
printf 'PASS native dependency regression; iPhone/full-engine acceptance remains separate. Evidence: %s\n' "$PROBE_BUILD"
