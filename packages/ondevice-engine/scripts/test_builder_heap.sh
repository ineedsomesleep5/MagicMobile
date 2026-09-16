#!/usr/bin/env bash
# 256 MiB HotSpot retention regression; not a full compiler or phone-engine test.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export JAVA_HOME="${MM_GRAALVM_HOME:-$ROOT/build/toolchains/graalvm-svm-java17-darwin-m1-gluon-22.1.0.1-Final/Contents/Home}"
PROBE_BUILD=$(mktemp -d "$ROOT/build/builder-heap-XXXXXX")
grep -qx 'JAVA_VERSION="17.0.3"' "$JAVA_HOME/release"
"$JAVA_HOME/bin/javac" -J-Xmx128m -d "$PROBE_BUILD" "$ROOT/native/gluon/probes/BuilderHeapProbe.java"
python3 - "$ROOT" "$PROBE_BUILD" "$JAVA_HOME" <<'PY'
import pathlib, subprocess, sys, xml.etree.ElementTree as ET
root, output, java = map(pathlib.Path, sys.argv[1:])
args = [e.text for e in ET.parse(root / 'native/gluon/pom.xml').iter(
    '{http://maven.apache.org/POM/4.0.0}arg')]
policy = [a[2:] for a in args if a and a.startswith('-J-XX:')]
if policy != ['-XX:-UseParallelGC', '-XX:+UseG1GC']:
    raise SystemExit('Unexpected builder GC policy; review the retention regression')
base = [str(java / 'bin/java'), '-Xmx256m', '-XX:ActiveProcessorCount=2']
tail = ['-cp', str(output), 'BuilderHeapProbe', '245000']
baseline = subprocess.run(base + ['-XX:+UseParallelGC', '-XX:NewRatio=7'] + tail,
                          capture_output=True, text=True, timeout=30)
(output / 'baseline.log').write_text(baseline.stdout + baseline.stderr)
if baseline.returncode == 0 or 'OutOfMemoryError' not in baseline.stderr:
    raise SystemExit('Baseline did not reproduce retained-heap exhaustion; review before proceeding')
adapted = subprocess.run(base + policy + tail, capture_output=True, text=True, timeout=30)
(output / 'adapted.log').write_text(adapted.stdout + adapted.stderr)
if adapted.returncode != 0 or 'PASS retained=245000 checksum=-122468' not in adapted.stdout:
    raise SystemExit('Builder GC retention regression failed: ' + adapted.stderr)
print('PASS old builder policy exhausts the same bounded heap; production policy completes')
print(adapted.stdout.strip())
print('Evidence:', output)
PY
