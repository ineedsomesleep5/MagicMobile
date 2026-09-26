#!/usr/bin/env bash
# SPIKE ONLY: build a browser (CheerpJ) bundle of the real XMage engine adapter.
#
# Reads packages/ondevice-engine (the guarded native-engine input) and never writes to it:
# the pinned upstream checkout, Maven output and every compiled class live under this
# package's git-ignored build/ directory. Output: build/web/ (jars + manifest.json + decks/).
#
# Usage: build_web.sh [--java 17|11] [all|upstream|engine|shadow|package]
#   --java 11 builds the variant for CheerpJ's Java 11 runtime into build/web-java11/ (classes in
#             build/java11/). Its engine stage copies the adapter sources into build/java11/src,
#             rewrites their six Java 16+ lines there (java11_sources.py) and compiles with
#             --release 11. It reuses the Java 17 build's upstream jars (Java 8 bytecode), generated
#             registry sources and card metadata, so run the Java 17 upstream + engine stages first.
#   upstream  fetch + patch the pinned XMage commit, Maven-package the needed modules
#   engine    compile core, generated registry, platform catalogue and adapter (+ WebEntryPoints)
#   shadow    compile web-only classes: replacements of upstream classes (shadow/) and the
#             WebUnsafe helper behind the worker's Unsafe natives (CheerpJ workarounds)
#   package   jar everything into build/web with a manifest (sizes, SHA-256, upstream, catalogue)
# Heavy stages (upstream, engine) belong behind the machine-wide heavy-workload lock.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
ENGINE="$REPO/packages/ondevice-engine"
BUILD="$HERE/build"
U="${MM_WEB_UPSTREAM:-$BUILD/upstream/mage}"
JAVA_RELEASE=17
if [[ "${1:-}" == --java ]]; then JAVA_RELEASE="${2:?--java needs 17 or 11}"; shift 2; fi
case "$JAVA_RELEASE" in
  17) CLS="$BUILD"; OUT="$BUILD/web" ;;
  11) CLS="$BUILD/java11"; OUT="$BUILD/web-java11" ;;
  *) echo "--java must be 17 or 11" >&2; exit 2 ;;
esac
STAGE="${1:-all}"
# The build JDK is 17 for both variants (build-time tools use Java 17 APIs); the runtime classes
# are compiled with --release $JAVA_RELEASE, matching the CheerpJ runtime the worker selects.
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

stage_engine_java11() {
  [[ -s "$BUILD/classpath.txt" && -s "$BUILD/engine/mage/mobile/card-metadata-report.json" ]] ||
    { echo "Run the Java 17 upstream and engine stages first (generated sources, card metadata)" >&2; exit 1; }
  rm -rf "$CLS"; mkdir -p "$CLS/core" "$CLS/engine"
  # Copies only: packages/ondevice-engine is never written.
  python3 "$HERE/java11_sources.py" "$ENGINE" "$CLS/src"
  CP=$(<"$BUILD/classpath.txt")
  find "$CLS/src/core" -name '*.java' | sort > "$CLS/core-sources.txt"
  javac --release 11 -d "$CLS/core" @"$CLS/core-sources.txt"
  { find "$CLS/src/xmage" "$BUILD/generated/java" "$BUILD/generated/platform" "$CLS/src/platform" \
      -name '*.java'; echo "$HERE/WebEntryPoints.java"; } | sort > "$CLS/engine-sources.txt"
  javac -J-Xmx2g --release 11 -cp "$CLS/core:$CP" -d "$CLS/engine" @"$CLS/engine-sources.txt"
  # Card metadata resources are data produced by the Java 17 build's exporter.
  mkdir -p "$CLS/engine/mage"; cp -R "$BUILD/engine/mage/mobile" "$CLS/engine/mage/"
  echo "$CLS/core:$CLS/engine:$CP" > "$CLS/runtime-classpath.txt"
}

stage_shadow() {
  # Web-only replacements for upstream classes that hit CheerpJ runtime gaps (see each file's
  # header), plus WebUnsafe. They go into magicmobile-engine.jar, first on the browser
  # classpath; no other platform uses them.
  [[ -s "$BUILD/classpath.txt" ]] || { echo "Run the engine stage first" >&2; exit 1; }
  rm -rf "$CLS/shadow"; mkdir -p "$CLS/shadow"
  (cd "$HERE/shadow" && find . -name '*.java' | sort) > "$CLS/shadow-sources.txt"
  # Java 17: no --release, it can hide jdk.unsupported (sun.misc.Unsafe); the build JDK is 17.
  local release=(); [[ "$JAVA_RELEASE" == 17 ]] || release=(--release "$JAVA_RELEASE")
  (cd "$HERE/shadow" && javac -nowarn ${release[@]+"${release[@]}"} -cp "$(<"$BUILD/classpath.txt")" -d "$CLS/shadow" @"$CLS/shadow-sources.txt" "$HERE/WebUnsafe.java")
}

stage_package() {
  [[ -s "$CLS/runtime-classpath.txt" ]] || { echo "Run the engine stage first" >&2; exit 1; }
  [[ -s "$CLS/shadow-sources.txt" ]] || { echo "Run the shadow stage first" >&2; exit 1; }
  rm -rf "$OUT"; mkdir -p "$OUT/jars" "$OUT/decks"
  CP=$(<"$BUILD/classpath.txt")
  # Adapter + platform catalogue + generated registry + web entry point first: the platform
  # mage.cards.repository classes must shadow the upstream (H2-backed) ones.
  jar --create --file "$OUT/jars/magicmobile-engine.jar" -C "$CLS/core" . -C "$CLS/engine" . -C "$CLS/shadow" .
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
  python3 - "$OUT" "$SHA" "$BUILD/generated/java/io/magicmobile/generated/GeneratedCardFactory.java" "$CLS/shadow-sources.txt" "$JAVA_RELEASE" "$CLS/src/java11-patch.json" "${order[@]}" <<'PY'
import hashlib, json, re, sys, time
from pathlib import Path
out, sha, factory, shadows, release, patch, order = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3]), Path(sys.argv[4]), int(sys.argv[5]), Path(sys.argv[6]), sys.argv[7:]
catalogue = re.search(r'CATALOGUE_HASH="([0-9a-f]{64})"', factory.read_text()).group(1)
jars = []
for name in order:
    data = (out / 'jars' / name).read_bytes()
    jars.append({'name': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
manifest = {'spike': True, 'upstream': sha, 'catalogueHash': catalogue,
            # The worker passes this to cheerpjInit({version}); the adapter is compiled for it.
            'javaRelease': release,
            'builtAt': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
            'totalBytes': sum(j['bytes'] for j in jars),
            # Upstream classes replaced in this bundle only (packages/web-engine/shadow).
            'webShadows': [line.strip().removeprefix('./') for line in shadows.read_text().splitlines() if line.strip()],
            # Classpath order: the worker joins these (relative to jars/) in this order.
            'jars': jars, 'decks': sorted(p.stem for p in (out / 'decks').glob('*.json'))}
if release != 17:
    # Adapter lines rewritten on the build-folder copies (java11_sources.py), not in the repo.
    manifest['sourceRewrites'] = json.loads(patch.read_text())['patches']
(out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(f"{out.name}: Java {release}, {len(jars)} jars, {manifest['totalBytes']/1e6:.1f} MB, catalogue {catalogue[:12]}")
PY
}

case "$STAGE" in
  upstream) stage_upstream ;;
  engine) if [[ "$JAVA_RELEASE" == 11 ]]; then stage_engine_java11; else stage_engine; fi ;;
  package) stage_package ;;
  shadow) stage_shadow ;;
  all)
    if [[ "$JAVA_RELEASE" == 11 ]]; then stage_engine_java11
    else stage_upstream; stage_engine; fi
    stage_shadow; stage_package ;;
  *) echo "Unknown stage: $STAGE" >&2; exit 2 ;;
esac
