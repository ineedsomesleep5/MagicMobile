#!/usr/bin/env bash
# Web engine (milestone M1, docs/WEB_ENGINE_M1.md): the real XMage adapter and pinned upstream, compiled with GraalVM
# Web Image into WebAssembly for a desktop browser's Web Worker, in a single-threaded "web threading mode".
#
# Reads packages/ondevice-engine and never writes to it: run its scripts/build_jvm.sh first (the prepared upstream
# checkout, compiled classes, generated registry and card resources). Everything this writes is under the git-ignored
# packages/web-engine/build/.
#
#   build_web.sh sources   rewrite copies of the engine sources for the web mode (web_sources.py) + web identity
#   build_web.sh jvm       compile the web mode for HotSpot (build/web-jvm): the JVM harness and the image's input
#   build_web.sh metadata  reflection metadata (the phone exporter, minus serialization), plus the tracing agent's
#                          output when build/agent/ exists (see the CI workflow)
#   build_web.sh wasm      native-image --tool:svm-wasm -> build/wasm (Oracle GraalVM 25.1+ and binaryen's wasm-as).
#                          The full engine needs a ~10 GB builder heap: GitHub Actions, never the 8 GB Mac.
#   build_web.sh bundle    build/web: engine.js, engine.js.wasm, decks and manifest.json for apps/web-play
#   build_web.sh all       every stage in order
#
# Environment: GRAALVM_HOME (wasm stage; Oracle GraalVM 25.4), MM_WEB_HEAP (builder heap, default 10g),
# JAVA_HOME for the other stages (JDK 17+).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
ENGINE="$REPO/packages/ondevice-engine"
U="$ENGINE/.upstream/mage"
BUILD="$HERE/build"
STAGE="${1:-all}"
JAVAC="${JAVA_HOME:+$JAVA_HOME/bin/}javac"
JAVA="${JAVA_HOME:+$JAVA_HOME/bin/}java"

need_jvm_build() {
  [[ -s "$ENGINE/build/runtime-classpath.txt" && -f "$U/.mobile-patch.json" ]] ||
    { echo "Run packages/ondevice-engine/scripts/build_jvm.sh first" >&2; exit 1; }
}
upstream_cp() {
  # The phone runtime classpath minus its own core and engine class folders: upstream classes and third-party jars.
  local cp; cp=$(<"$ENGINE/build/runtime-classpath.txt")
  local prefix="$ENGINE/build/core:$ENGINE/build/engine:"
  [[ "$cp" == "$prefix"* ]] || { echo "Unexpected phone runtime classpath" >&2; exit 1; }
  echo "${cp#"$prefix"}"
}
toolchain() {
  if [[ -n "${GRAALVM_HOME:-}" ]]; then "$GRAALVM_HOME/bin/native-image" --version | head -1
  else echo "${MM_WEB_TOOLCHAIN:?Set GRAALVM_HOME (or MM_WEB_TOOLCHAIN for a JVM-only build)}"; fi
}

stage_sources() {
  need_jvm_build
  python3 "$HERE/web_sources.py" "$ENGINE" "$U" "$BUILD/web-src"
  rm -rf "$BUILD/web-generated"
  python3 "$HERE/web_identity.py" --toolchain "$(toolchain)" --output "$BUILD/web-generated"
}

stage_jvm() {
  need_jvm_build
  [[ -s "$BUILD/web-src/web-sources.json" ]] || { echo "Run the sources stage first" >&2; exit 1; }
  local CP out="$BUILD/web-jvm"; CP=$(upstream_cp)
  rm -rf "$out"; mkdir -p "$out/upstream" "$out/core" "$out/engine"
  # Upstream overrides (ComputerPlayer6, GameImpl, PlayerImpl and the stop flag) go before the upstream classes.
  { find "$BUILD/web-src/upstream" -name '*.java'; find "$HERE/src/mage" -name '*.java'; } | sort > "$out/upstream-sources.txt"
  "$JAVAC" -J-Xmx1g --release 17 -nowarn -cp "$CP" -d "$out/upstream" @"$out/upstream-sources.txt"
  { find "$BUILD/web-src/core" -name '*.java'; find "$HERE/src/io/magicmobile/core" -name '*.java'; } | sort > "$out/core-sources.txt"
  "$JAVAC" -J-Xmx512m --release 17 -d "$out/core" @"$out/core-sources.txt"
  # The phone's generated registry, except its engine identity: the web build has its own (web_identity.py).
  { find "$BUILD/web-src/xmage/src/main/java" "$BUILD/web-src/platform" "$ENGINE/build/generated/platform" -name '*.java'
    find "$ENGINE/build/generated/java" -name '*.java' ! -name EngineBuildIdentity.java
    find "$BUILD/web-generated" -name '*.java'
    find "$HERE/src/io/magicmobile/web" -name '*.java' ! -name WebMain.java; } | sort > "$out/engine-sources.txt"
  "$JAVAC" -J-Xmx2g --release 17 -nowarn -cp "$out/upstream:$out/core:$CP" -d "$out/engine" @"$out/engine-sources.txt"
  # Engine resources (card catalogues, set catalogue), as the phone build bundles them.
  rsync -a --exclude '*.class' "$ENGINE/build/engine/" "$out/engine/"
  echo "$out/upstream:$out/core:$out/engine:$CP" > "$out/runtime-classpath.txt"
  echo "Web mode compiled for the JVM: $out/runtime-classpath.txt"
}

stage_metadata() {
  [[ -s "$BUILD/web-jvm/runtime-classpath.txt" ]] || { echo "Run the jvm stage first" >&2; exit 1; }
  local out="$BUILD/metadata"; rm -rf "$out"; mkdir -p "$out/tools"
  "$JAVAC" -J-Xmx512m --release 17 -cp "$BUILD/web-jvm/core" -d "$out/tools" "$ENGINE/engine/tools/NativeReflectionExporter.java"
  # Reflection only: the web build has no save/resume, so no checkpoint serialization metadata (50,816 classes).
  "$JAVA" -Xmx768m -cp "$out/tools:$(<"$BUILD/web-jvm/runtime-classpath.txt")" NativeReflectionExporter "$out/exporter" \
    "$U/Mage/target/classes" "$U/Mage.Sets/target/classes" "$U/Mage.Common/target/classes"
  [[ -s "$out/exporter/reflect-config.json" ]]
}

stage_wasm() {
  : "${GRAALVM_HOME:?Set GRAALVM_HOME to Oracle GraalVM 25.1 or later}"
  command -v wasm-as >/dev/null || { echo "binaryen's wasm-as (119+) must be on PATH" >&2; exit 1; }
  [[ -s "$BUILD/metadata/exporter/reflect-config.json" ]] || { echo "Run the metadata stage first" >&2; exit 1; }
  local out="$BUILD/wasm" heap="${MM_WEB_HEAP:-10g}"; rm -rf "$out"; mkdir -p "$out/classes"
  local CP; CP=$(<"$BUILD/web-jvm/runtime-classpath.txt")
  # The Web Image entry point and the Thread.start substitution, which need GraalVM's own APIs.
  "$GRAALVM_HOME/bin/javac" -J-Xmx512m -nowarn --add-modules org.graalvm.webimage.api \
    -cp "$GRAALVM_HOME/lib/svm/builder/svm.jar:$CP" -d "$out/classes" \
    "$HERE/src/io/magicmobile/web/WebMain.java" $(find "$HERE/src-svm" -name '*.java')
  local configs=(-H:ReflectionConfigurationFiles="$BUILD/metadata/exporter/reflect-config.json")
  if [[ -d "$BUILD/agent" ]]; then configs+=(-H:ConfigurationFileDirectories="$BUILD/agent"); fi
  local init; init=$(paste -sd, "$ENGINE/native/gluon/buildtime-enums.txt")
  local started=$SECONDS
  # --tool:svm-wasm must come first. Options mirror the phone build (native/gluon/pom.xml) where they apply.
  "$GRAALVM_HOME/bin/native-image" --tool:svm-wasm \
    -J-Xmx"$heap" --parallelism="${MM_WEB_BUILDER_THREADS:-4}" \
    -H:+UnlockExperimentalVMOptions \
    -cp "$out/classes:$CP" \
    --initialize-at-run-time=io.magicmobile,mage \
    --initialize-at-build-time="$init" \
    --initialize-at-build-time=com.j256.ormlite.field.types \
    "${configs[@]}" \
    -H:ResourceConfigurationFiles="$ENGINE/native/resource-config.json" \
    -H:ServiceLoaderFeatureExcludeServices=java.sql.Driver \
    -H:ReportAnalysisForbiddenType=org.h2.Driver:Reachable \
    -H:ReportAnalysisForbiddenType=com.j256.ormlite.jdbc.JdbcConnectionSource:Reachable \
    -H:ReportAnalysisForbiddenType=com.google.protobuf.GeneratedMessageV3:Reachable \
    -H:ReportAnalysisForbiddenType=mage.sets.MagicOnlinePromos:Reachable \
    ${MM_WEB_EXTRA_OPTIONS:-} \
    -o "$out/engine" io.magicmobile.web.WebMain 2>&1 | tee "$out/native-image.log"
  [[ -s "$out/engine.js.wasm" ]] || { echo "No engine.js.wasm" >&2; exit 1; }
  echo "wasm build: $((SECONDS - started)) s" | tee -a "$out/native-image.log"
}

stage_bundle() {
  [[ -s "$BUILD/wasm/engine.js.wasm" ]] || { echo "Run the wasm stage first" >&2; exit 1; }
  local out="$BUILD/web"; rm -rf "$out"; mkdir -p "$out/decks"
  python3 "$HERE/patch_wrapper.py" "$BUILD/wasm/engine.js" "$out/engine.js"
  cp "$BUILD/wasm/engine.js.wasm" "$out/engine.js.wasm"
  python3 "$HERE/export_precons.py" --catalogue "$ENGINE/build/generated/catalogue.jsonl" \
    --swift "$REPO/apps/ios/MagicMobile/PreconCatalog.swift" --output "$out/decks"
  python3 - "$out" "$ENGINE" "$BUILD" <<'PY'
import gzip, hashlib, json, re, sys, time
from pathlib import Path
out, engine, build = (Path(a) for a in sys.argv[1:])
wasm = (out / 'engine.js.wasm').read_bytes()
factory = (engine / 'build/generated/java/io/magicmobile/generated/GeneratedCardFactory.java').read_text()
identity = re.search(r'VALUE="([^"]+)"', next((build / 'web-generated').rglob('EngineBuildIdentity.java')).read_text()).group(1)
log = (build / 'wasm/native-image.log').read_text(errors='replace')
manifest = {
    'engine': 'xmage', 'runtime': 'graalvm-web-image',
    'upstream': json.loads((engine / 'upstream.lock.json').read_text())['commit'],
    'catalogueHash': re.search(r'CATALOGUE_HASH="([0-9a-f]{64})"', factory).group(1),
    'engineBuild': identity,
    'toolchain': next((l.strip() for l in log.splitlines() if 'GraalVM' in l and 'Version info' in l), None),
    'builtAt': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
    'wasm': {'bytes': len(wasm), 'gzip9Bytes': len(gzip.compress(wasm, 9)), 'sha256': hashlib.sha256(wasm).hexdigest()},
    'decks': sorted(p.stem for p in (out / 'decks').glob('*.json')),
    'webSources': json.loads((build / 'web-src/web-sources.json').read_text())['rewrites'],
}
(out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(f"bundle: wasm {len(wasm)/1e6:.1f} MB raw, {manifest['wasm']['gzip9Bytes']/1e6:.1f} MB gzip -9, {identity}")
PY
}

case "$STAGE" in
  sources) stage_sources ;;
  jvm) stage_jvm ;;
  metadata) stage_metadata ;;
  wasm) stage_wasm ;;
  bundle) stage_bundle ;;
  all) stage_sources; stage_jvm; stage_metadata; stage_wasm; stage_bundle ;;
  *) echo "Unknown stage: $STAGE" >&2; exit 2 ;;
esac
