#!/usr/bin/env bash
# Real exported metadata and original CardInfo; never installs the card factories.
set -euo pipefail
[[ $# == 0 || ( $# == 1 && "$1" == --prepare-only ) ]] || { echo 'Usage: bash test_card_catalogue_native.sh [--prepare-only]' >&2; exit 2; }
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CATALOGUE_JDK="${MM_GRAALVM_HOME:-$ROOT/build/toolchains/graalvm-svm-java17-darwin-m1-gluon-22.1.0.1-Final/Contents/Home}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
PROBE_BUILD=$(mktemp -d "$ROOT/build/card-catalogue-native-XXXXXX")
printf 'Catalogue dependency evidence: %s\n' "$PROBE_BUILD"
CP=$(< "$ROOT/build/runtime-classpath.txt")
mkdir -p "$PROBE_BUILD/classes"
# Pin all runtime bytes, original CardInfo, the exporter and actual exported assets.
python3 - "$ROOT" "$PROBE_BUILD" "$CATALOGUE_JDK" <<'PY'
import gzip, hashlib, json, re, subprocess, sys, zipfile
from pathlib import Path
root, output, toolchain = map(Path, sys.argv[1:])
upstream = root / '.upstream/mage'
pin = json.loads((root / 'upstream.lock.json').read_text())['commit']
assert subprocess.check_output(['git', '-C', str(upstream), 'rev-parse', 'HEAD'], text=True).strip() == pin
source = 'Mage/src/main/java/mage/cards/repository/CardInfo.java'
assert (upstream / source).read_bytes() == subprocess.check_output(['git', '-C', str(upstream), 'show', f'{pin}:{source}'])
classpath = (root / 'build/runtime-classpath.txt').read_text().strip().split(':')
card_class = 'mage/cards/repository/CardInfo.class'
for entry in classpath:
    path = Path(entry)
    if path.is_dir() and (path / card_class).is_file():
        resolved = (path / card_class).read_bytes()
        break
    if path.is_file():
        with zipfile.ZipFile(path) as jar:
            if card_class in jar.namelist():
                resolved = jar.read(card_class)
                break
else:
    raise SystemExit('Original CardInfo absent from runtime classpath')
assert resolved == (upstream / 'Mage/target/classes' / card_class).read_bytes(), 'CardInfo shadowed by a replacement'
assets = root / 'build/engine/mage/mobile'
report = json.loads((assets / 'card-metadata-report.json').read_text())
assert report['upstream'] == pin
for name, digest in report['resources'].items():
    assert hashlib.sha256((assets / name).read_bytes()).hexdigest() == digest, name
with gzip.open(assets / 'card-names.json.gz', 'rt') as stream:
    names = json.load(stream)
assert names['format'] == 1 and len(names['names']) == 9
assert {k: len(v) for k, v in names['names'].items()} == report['nameCounts']
with gzip.open(assets / 'card-metadata.jsonl.gz', 'rt') as stream:
    header = json.loads(next(stream))
    rows = [json.loads(line) for line in stream]
assert header == {'format': 1, 'rows': len(rows)}
assert len(rows) == report['rowsIncludingSplitHalves']
# The export also carries app-only Commander identity. CardInfo deliberately
# remains the exact upstream model, which has no colorIdentity field. Validate
# that enrichment independently, then compare every original field unchanged.
for row in rows:
    if not row['splitCardHalf']:
        identity = row.pop('colorIdentity')
        assert isinstance(identity, list)
        assert identity == [color for color in 'WUBRG' if color in identity], 'Invalid exported color identity'
lookup = {name: [r for r in rows if r['name'] == name]
          for name in ('Pithing Needle', 'Brain Pry', 'Fire', 'Fire // Ice')}
assert all(lookup.values())
needle = lookup['Pithing Needle'][0]
printing = next(r for r in rows if r['setCode'] == needle['setCode'] and r['cardNumber'] == needle['cardNumber'] and not r['nightCard'])
eligible = [r for r in rows if not r['splitCardHalf'] and not r['nightCard']]
expected = dict(names=names['names'], rows=len(rows), lookups=lookup,
                needleOne=[needle], printing=printing,
                islands=[r for r in eligible if r['name'].lower() == 'island' and 'LAND' in r['types']],
                mythics=sorted((r for r in eligible if r['rarity'] == 'MYTHIC'), key=lambda r: r['name'].lower())[1:4])
(output / 'expected.json').write_text(json.dumps(expected))
includes = json.loads((root / 'native/resource-config.json').read_text())['resources']['includes']
resources = ['mage/mobile/card-names.json.gz', 'mage/mobile/card-metadata.jsonl.gz']
assert all(any(re.fullmatch(e['pattern'], name) for e in includes) for name in resources)
(output / 'resource-config.json').write_text(json.dumps({'resources': {'includes': [{'pattern': re.escape(n)} for n in resources]}}))
paths = [root / 'build/runtime-classpath.txt', root / 'native/resource-config.json', upstream / source,
         root / 'engine/tools/NativeReflectionExporter.java', assets / 'card-metadata-report.json']
paths += list((root / 'platform').rglob('*.java'))
paths += [root / 'native/gluon/probes/CardCatalogueProbe.java', root / 'scripts/test_card_catalogue_native.sh']
paths += [toolchain / name for name in ('release', 'bin/java', 'bin/javac', 'bin/native-image')]
for entry in (root / 'build/runtime-classpath.txt').read_text().strip().split(':'):
    path = Path(entry)
    assert path.exists(), path
    paths.extend(sorted(p for p in path.rglob('*') if p.is_file()) if path.is_dir() else [path])
hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
(output / 'inputs.json').write_text(json.dumps({'upstream': pin, 'sha256': hashes}, indent=2) + '\n')
PY
"$CATALOGUE_JDK/bin/javac" -J-Xmx256m --release 17 -cp "$CP" -d "$PROBE_BUILD/classes" \
  "$ROOT/engine/tools/NativeReflectionExporter.java" "$ROOT/native/gluon/probes/CardCatalogueProbe.java"
# Export the actual full production config, but never pass that full config to native-image.
"$CATALOGUE_JDK/bin/java" -Xmx256m -cp "$PROBE_BUILD/classes:$CP" NativeReflectionExporter \
  "$PROBE_BUILD/production" "$ROOT/.upstream/mage/Mage/target/classes" \
  "$ROOT/.upstream/mage/Mage.Sets/target/classes" > "$PROBE_BUILD/export.log" 2>&1
python3 - "$PROBE_BUILD" <<'PY'
import json, sys
from pathlib import Path
output = Path(sys.argv[1])
production = json.loads((output / 'production/reflect-config.json').read_text())
expected = [{'name': 'mage.cards.repository.CardInfo', 'allDeclaredFields': True,
             'methods': [{'name': '<init>', 'parameterTypes': []}]},
            {'name': 'mage.constants.Rarity', 'allDeclaredFields': True}]
selected = [entry for entry in production if entry['name'] in {e['name'] for e in expected}]
assert selected == expected, 'Production CardInfo/enum metadata changed; review the bounded scope'
(output / 'reflect-config.json').write_text(json.dumps(selected, indent=2) + '\n')
print('Exact production CardInfo fields and zero-argument Gson constructor selected; no card factories installed')
PY
(cd "$PROBE_BUILD" && "$CATALOGUE_JDK/bin/java" -Xmx256m -cp "$PROBE_BUILD/classes:$CP" \
  CardCatalogueProbe "$PROBE_BUILD/expected.json") > "$PROBE_BUILD/jvm-run.log" 2>&1 || {
  cat "$PROBE_BUILD/jvm-run.log" >&2
  exit 1
}
grep '^PASS ' "$PROBE_BUILD/jvm-run.log" > "$PROBE_BUILD/expected.txt"
if [[ ${1:-} == --prepare-only ]]; then
  cat "$PROBE_BUILD/expected.txt"
  echo 'PASS preparation and JVM only; native compilation/execution NOT RUN'
  exit 0
fi
# Refuse concurrent runtime/source changes between preparation and native analysis.
python3 - "$PROBE_BUILD/inputs.json" <<'PY'
import hashlib, json, sys
from pathlib import Path
for path, expected in json.loads(Path(sys.argv[1]).read_text())['sha256'].items():
    assert hashlib.sha256(Path(path).read_bytes()).hexdigest() == expected, f'Input changed: {path}'
PY
"$CATALOGUE_JDK/bin/native-image" --no-fallback -J-Xmx1g -H:NumberOfThreads=2 \
  --initialize-at-run-time=mage "-H:Path=$PROBE_BUILD" \
  "-H:ReflectionConfigurationFiles=$PROBE_BUILD/reflect-config.json" \
  "-H:ResourceConfigurationFiles=$PROBE_BUILD/resource-config.json" \
  -cp "$PROBE_BUILD/classes:$CP" -H:Name=catalogue CardCatalogueProbe > "$PROBE_BUILD/native-build.log" 2>&1
(cd "$PROBE_BUILD" && ./catalogue "$PROBE_BUILD/expected.json") > "$PROBE_BUILD/native-run.log" 2>&1
grep '^PASS ' "$PROBE_BUILD/native-run.log" > "$PROBE_BUILD/actual.txt"
diff -u "$PROBE_BUILD/expected.txt" "$PROBE_BUILD/actual.txt"
cat "$PROBE_BUILD/actual.txt"
echo 'PASS native host catalogue dependency regression; full engine and phone acceptance remain separate'
