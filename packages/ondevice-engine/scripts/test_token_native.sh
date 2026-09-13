#!/usr/bin/env bash
# Small host-native dependency regression; run separately from the full engine build.
set -euo pipefail
[[ $# == 0 || ( $# == 1 && "$1" == --prepare-only ) ]] || { echo 'Usage: bash test_token_native.sh [--prepare-only]' >&2; exit 2; }
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TOKEN_JDK="${MM_GRAALVM_HOME:-$ROOT/build/toolchains/graalvm-svm-java17-darwin-m1-gluon-22.1.0.1-Final/Contents/Home}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
PROBE_BUILD=$(mktemp -d "$ROOT/build/token-native-XXXXXX")
UPSTREAM="$ROOT/.upstream/mage"
printf 'Token dependency regression evidence: %s\n' "$PROBE_BUILD"
# Refuse stale/modified inputs. Compile only the real repository and its small dependency closure.
python3 - "$ROOT" "$PROBE_BUILD" <<'PY'
import hashlib, json, re, subprocess, sys
from pathlib import Path
root, output = map(Path, sys.argv[1:])
upstream = root / '.upstream/mage'
pin = json.loads((root / 'upstream.lock.json').read_text())['commit']
if subprocess.check_output(['git', '-C', str(upstream), 'rev-parse', 'HEAD'], text=True).strip() != pin:
    raise SystemExit('Wrong upstream revision')
paths = [f'Mage/src/main/java/mage/cards/repository/{name}.java'
         for name in ('TokenRepository', 'TokenInfo', 'TokenType')]
paths += ['Mage/src/main/java/mage/util/RandomUtil.java', 'Mage/src/main/resources/tokens-database.txt']
hashes = {}
for path in paths:
    data = (upstream / path).read_bytes()
    original = subprocess.check_output(['git', '-C', str(upstream), 'show', f'{pin}:{path}'])
    if data != original:
        raise SystemExit(f'Unreviewed upstream change: {path}')
    hashes[path] = hashlib.sha256(data).hexdigest()
classpath = (root / 'build/runtime-classpath.txt').read_text().strip().split(':')
logging = sorted(set(p for p in classpath if p.endswith('/ch/qos/reload4j/reload4j/1.2.22/reload4j-1.2.22.jar')))
if len(logging) != 1 or not Path(logging[0]).is_file():
    raise SystemExit('Require the pinned runtime reload4j 1.2.22 dependency')
(output / 'logging-classpath.txt').write_text(logging[0])
config = json.loads((root / 'native/resource-config.json').read_text())
includes = config['resources']['includes']
token = {'pattern': r'tokens-database\.txt'}
if includes.count(token) != 1:
    raise SystemExit('Require one exact production token resource entry')
includes.remove(token)
if any(re.fullmatch(e['pattern'], 'tokens-database.txt') for e in includes):
    raise SystemExit('Baseline would still include the token resource')
(output / 'baseline-resource-config.json').write_text(json.dumps(config) + '\n')
hashes['reload4j'] = hashlib.sha256(Path(logging[0]).read_bytes()).hexdigest()
hashes['production-resource-config'] = hashlib.sha256((root / 'native/resource-config.json').read_bytes()).hexdigest()
(output / 'inputs.json').write_text(json.dumps({'upstream': pin, 'sha256': hashes}, indent=2) + '\n')
PY
LOGGING=$(< "$PROBE_BUILD/logging-classpath.txt")
mkdir -p "$PROBE_BUILD/classes"
"$TOKEN_JDK/bin/javac" -J-Xmx128m -cp "$LOGGING" -d "$PROBE_BUILD/classes" \
  "$UPSTREAM/Mage/src/main/java/mage/cards/repository/TokenRepository.java" \
  "$UPSTREAM/Mage/src/main/java/mage/cards/repository/TokenInfo.java" \
  "$UPSTREAM/Mage/src/main/java/mage/cards/repository/TokenType.java" \
  "$UPSTREAM/Mage/src/main/java/mage/util/RandomUtil.java" \
  "$ROOT/native/gluon/probes/TokenResourceProbe.java"
cp "$UPSTREAM/Mage/src/main/resources/tokens-database.txt" "$PROBE_BUILD/classes/"
if [[ ${1:-} == --prepare-only ]]; then
  echo 'PASS preparation and tiny Java compilation only; native execution NOT RUN'
  exit 0
fi
CP="$PROBE_BUILD/classes:$LOGGING"
ARGS=(--no-fallback -J-Xmx1g -H:NumberOfThreads=2 "-H:Path=$PROBE_BUILD" --initialize-at-run-time=mage)
"$TOKEN_JDK/bin/native-image" "${ARGS[@]}" \
  "-H:ResourceConfigurationFiles=$PROBE_BUILD/baseline-resource-config.json" \
  -cp "$CP" -H:Name=baseline TokenResourceProbe > "$PROBE_BUILD/baseline-build.log" 2>&1
if (cd "$PROBE_BUILD" && ./baseline) > "$PROBE_BUILD/baseline-run.log" 2>&1; then
  echo 'Baseline unexpectedly passed; re-evaluate resource inclusion' >&2; exit 1
fi
grep -F "Tokens database: can't load resource file tokens-database.txt" "$PROBE_BUILD/baseline-run.log"
grep -F 'mage.cards.repository.TokenRepository.loadMtgTokens' "$PROBE_BUILD/baseline-run.log"
"$TOKEN_JDK/bin/native-image" "${ARGS[@]}" \
  "-H:ResourceConfigurationFiles=$ROOT/native/resource-config.json" \
  -cp "$CP" -H:Name=adapted TokenResourceProbe > "$PROBE_BUILD/adapted-build.log" 2>&1
(cd "$PROBE_BUILD" && "$TOKEN_JDK/bin/java" -Xmx128m -cp "$CP" TokenResourceProbe) > "$PROBE_BUILD/jvm-run.log" 2>&1
(cd "$PROBE_BUILD" && ./adapted) > "$PROBE_BUILD/adapted-run.log" 2>&1
grep '^PASS SaprolingToken ' "$PROBE_BUILD/jvm-run.log" > "$PROBE_BUILD/expected.txt"
grep '^PASS SaprolingToken ' "$PROBE_BUILD/adapted-run.log" > "$PROBE_BUILD/actual.txt"
diff -u "$PROBE_BUILD/expected.txt" "$PROBE_BUILD/actual.txt"
cat "$PROBE_BUILD/actual.txt"
printf 'PASS native token dependency regression; iPhone/gameplay acceptance remains separate. Evidence: %s\n' "$PROBE_BUILD"
