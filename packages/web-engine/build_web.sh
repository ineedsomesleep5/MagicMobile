#!/usr/bin/env bash
# SPIKE ONLY: build a browser (CheerpJ) bundle of the real XMage engine adapter.
#
# Reads packages/ondevice-engine (the guarded native-engine input) and never writes to it:
# the pinned upstream checkout, Maven output and every compiled class live under this
# package's git-ignored build/ directory. Output: build/web/ (jars + manifest.json + decks/).
#
# Usage: build_web.sh [all|upstream|engine|package]
#   upstream  fetch + patch the pinned XMage commit, Maven-package the needed modules
#   engine    compile core, generated registry, platform catalogue and adapter (+ WebEntryPoints)
#   package   jar everything into build/web with a manifest (sizes, SHA-256, upstream, catalogue)
# Heavy stages (upstream, engine) belong behind the machine-wide heavy-workload lock.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
ENGINE="$REPO/packages/ondevice-engine"
BUILD="$HERE/build"
U="${MM_WEB_UPSTREAM:-$BUILD/upstream/mage}"
OUT="$BUILD/web"
STAGE="${1:-all}"
# The adapter compiles with --release 17 and CheerpJ's newest runtime is Java 17.
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17}"
export PATH="$JAVA_HOME/bin:$PATH"
java -version 2>&1 | grep -q 'version "17' || { echo "JDK 17 required (set JAVA_HOME)" >&2; exit 1; }
SHA=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["commit"])' "$ENGINE/upstream.lock.json")
# Same module set as packages/ondevice-engine/scripts/build_jvm.sh.
MODULES="Mage.Sets,Mage.Common,Mage.Server.Plugins/Mage.Player.Human,Mage.Server.Plugins/Mage.Player.AI,Mage.Server.Plugins/Mage.Player.AI.MAD,Mage.Server.Plugins/Mage.Deck.Constructed,Mage.Server.Plugins/Mage.Game.CommanderFreeForAll"

stage_upstream() {
  if [[ ! -d "$U/.git" ]]; then
    mkdir -p "$U"; git -C "$U" init -q
    git -C "$U" remote add origin https://github.com/magefree/mage.git
  fi
  if ! git -C "$U" rev-parse --verify -q HEAD >/dev/null; then
    git -C "$U" fetch -q --depth 1 origin "$SHA"
    git -C "$U" checkout -q --detach FETCH_HEAD
  fi
  [[ "$(git -C "$U" rev-parse HEAD)" == "$SHA" ]] || { echo "Upstream checkout is not $SHA" >&2; exit 1; }
  # The repo's own checked patches (card factory, static set registry, human response hook).
  python3 "$ENGINE/scripts/prepare_upstream.py" "$U"
  # `package`, not `install`: never overwrite the shared ~/.m2 org/mage artifacts other checkouts use.
  (cd "$U" && MAVEN_OPTS="${MAVEN_OPTS:--Xmx3g}" mvn -B -pl "$MODULES" -am -Dmaven.test.skip=true \
     package dependency:build-classpath -Dmdep.outputFile=target/mobile-classpath.txt)
}

stage_engine() {
  [[ -f "$U/.mobile-patch.json" ]] || { echo "Run the upstream stage first" >&2; exit 1; }
  rm -rf "$BUILD/core" "$BUILD/engine" "$BUILD/tools" "$BUILD/generated" "$BUILD/card-metadata-export"
  mkdir -p "$BUILD/core" "$BUILD/engine" "$BUILD/tools" "$BUILD/generated"
  python3 "$ENGINE/scripts/classpath.py" "$U" "$BUILD/classpath.txt"
  CP=$(<"$BUILD/classpath.txt")
  find "$ENGINE/engine/core/src/main/java" -name '*.java' | sort > "$BUILD/core-sources.txt"
  javac --release 17 -d "$BUILD/core" @"$BUILD/core-sources.txt"
  javac --release 17 -cp "$BUILD/core" -d "$BUILD/tools" "$ENGINE/engine/tools/RegistryExporter.java"
  java -Xmx3g -cp "$BUILD/core:$BUILD/tools:$CP" RegistryExporter "$BUILD/generated" \
    "$U/Mage/target/classes" "$U/Mage.Sets/target/classes" "$U/Mage.Common/target/classes"
  python3 "$ENGINE/scripts/prepare_mobile_repository.py" --checkout "$U" --mode runtime --output "$BUILD/generated/platform"
  { find "$ENGINE/engine/xmage/src/main/java" "$BUILD/generated/java" "$BUILD/generated/platform" \
      "$ENGINE/platform/java" -name '*.java'; echo "$HERE/WebEntryPoints.java"; } | sort > "$BUILD/engine-sources.txt"
  javac -J-Xmx2g --release 17 -cp "$BUILD/core:$CP" -d "$BUILD/engine" @"$BUILD/engine-sources.txt"
  # Card metadata resources (/mage/mobile/*) read by MobileCardCatalogue, as build_card_metadata.sh.
  local X="$BUILD/card-metadata-export"
  python3 "$ENGINE/scripts/prepare_mobile_repository.py" --checkout "$U" --mode export --output "$X/source"
  find "$X/source" -name '*.java' | sort > "$X/sources.txt"
  javac -J-Xmx256m --release 17 -cp "$BUILD/core:$BUILD/engine:$CP" -d "$X/classes" \
    @"$X/sources.txt" "$ENGINE/engine/tools/CardMetadataExporter.java"
  mkdir -p "$BUILD/engine/mage/mobile"
  (cd "$X" && java -Xmx2g -Djava.awt.headless=true -cp "$X/classes:$BUILD/core:$BUILD/engine:$CP" \
     CardMetadataExporter "$BUILD/engine/mage/mobile")
  [[ -s "$BUILD/engine/mage/mobile/card-metadata-report.json" ]]
  echo "$BUILD/core:$BUILD/engine:$CP" > "$BUILD/runtime-classpath.txt"
}

stage_package() {
  [[ -s "$BUILD/runtime-classpath.txt" ]] || { echo "Run the engine stage first" >&2; exit 1; }
  rm -rf "$OUT"; mkdir -p "$OUT/jars" "$OUT/decks"
  CP=$(<"$BUILD/classpath.txt")
  # Adapter + platform catalogue + generated registry + web entry point first: the platform
  # mage.cards.repository classes must shadow the upstream (H2-backed) ones.
  jar --create --file "$OUT/jars/magicmobile-engine.jar" -C "$BUILD/core" . -C "$BUILD/engine" .
  local order=("magicmobile-engine.jar") entry name
  IFS=':' read -r -a entries <<< "$CP"
  for entry in "${entries[@]}"; do
    case "$entry" in
      */target/classes)
        # Reactor module: jar the compiled (patched) classes. Module dir name → jar name.
        name=$(basename "$(dirname "$(dirname "$entry")")" | tr 'A-Z.' 'a-z-').jar
        jar --create --file "$OUT/jars/$name" -C "$entry" . ;;
      */target/*.jar) continue ;;  # the same reactor module's packaged jar; classes already added
      *junit*|*hamcrest*|*opentest4j*|*apiguardian*|*assertj*) continue ;;  # test-only libraries
      *.jar) name=$(basename "$entry"); cp "$entry" "$OUT/jars/$name" ;;
      *) echo "Unexpected classpath entry: $entry" >&2; exit 1 ;;
    esac
    [[ " ${order[*]} " == *" $name "* ]] || order+=("$name")
  done
  # Bench decks: the bundled iOS precons, resolved against this build's catalogue.
  python3 "$HERE/export_precons.py" --catalogue "$BUILD/generated/catalogue.jsonl" \
    --swift "$REPO/apps/ios/MagicMobile/PreconCatalog.swift" --output "$OUT/decks"
  python3 - "$OUT" "$SHA" "$BUILD/generated/java/io/magicmobile/generated/GeneratedCardFactory.java" "${order[@]}" <<'PY'
import hashlib, json, re, sys, time
from pathlib import Path
out, sha, factory, order = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3]), sys.argv[4:]
catalogue = re.search(r'CATALOGUE_HASH="([0-9a-f]{64})"', factory.read_text()).group(1)
jars = []
for name in order:
    data = (out / 'jars' / name).read_bytes()
    jars.append({'name': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
manifest = {'spike': True, 'upstream': sha, 'catalogueHash': catalogue, 'javaRelease': 17,
            'builtAt': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
            'totalBytes': sum(j['bytes'] for j in jars),
            # Classpath order: the worker joins these (relative to jars/) in this order.
            'jars': jars, 'decks': sorted(p.stem for p in (out / 'decks').glob('*.json'))}
(out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(f"build/web: {len(jars)} jars, {manifest['totalBytes']/1e6:.1f} MB, catalogue {catalogue[:12]}")
PY
}

case "$STAGE" in
  upstream) stage_upstream ;;
  engine) stage_engine ;;
  package) stage_package ;;
  all) stage_upstream; stage_engine; stage_package ;;
  *) echo "Unknown stage: $STAGE" >&2; exit 2 ;;
esac
