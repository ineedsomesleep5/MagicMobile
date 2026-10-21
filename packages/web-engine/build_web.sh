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
#   build_web.sh wasm      native-image --tool:svm-wasm -> build/wasm (Oracle GraalVM 25.4.4.1.1, which the builder
#                          patch in builder-patch/ is pinned to, and binaryen's wasm-as). The full engine needs a
#                          builder heap of several GB: GitHub Actions, never the 8 GB Mac.
#   build_web.sh bundle    build/web for apps/web-play: engine-<hash>.js and engine-<hash>.wasm, named by their
#                          content so browsers cache them for good, decks, and manifest.json (fetched uncached) naming
#                          them
#   build_web.sh all       every stage in order
#
# Environment: GRAALVM_HOME (wasm stage; Oracle GraalVM 25.4), MM_WEB_HEAP (builder heap, default 10g),
# MM_WEB_OPT (native-image optimization level: 2 default, 1, or b for a quick build that needs less memory),
# MM_WEB_BUILDER_THREADS (default 4; fewer threads compile fewer methods at once, so peak memory is lower),
# MM_WEB_BUILDER_PATCH (default 0, Oracle's builder unmodified; 1: the builder patch, an experiment whose output is
# not for players, see docs/WEB_ENGINE_M1.md "The licence question"), MM_WEB_GC (parallel default, or g1),
# MM_WEB_DEFER_ASSEMBLY (default 1: wasm-as runs after the builder exits), MM_WEB_EXTRA_OPTIONS (more
# native-image options, e.g. diagnostics), JAVA_HOME for the other stages (JDK 17+).
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
  # The builder patch (builder-patch/build_patch.sh), opt-in: compiled methods release their compiler graphs, no
  # comments are kept for the .wat, and engine fields get no unsafe access dispatch entries (nothing reaches them
  # through Unsafe; check_skip_packages.py checks it). It modifies Oracle's builder: experiments only.
  local patch=()
  if [[ ${MM_WEB_BUILDER_PATCH:-0} == 1 ]]; then
    python3 "$HERE/builder-patch/check_skip_packages.py" "$out/classes:$CP" mage. io.magicmobile.
    patch=("$(bash "$HERE/builder-patch/build_patch.sh" "$BUILD/builder-patch" | tail -1)"
      -J-Dmagicmobile.webimage.dispatchSkipPackages=mage.,io.magicmobile.)
  fi
  # Web Image prints the module as text (engine.js.wat) and assembles it with wasm-as while the builder JVM still
  # holds its heap. wasm_as_deferred.sh records that one command instead, and it runs below once the builder has
  # exited, so the two never need memory at once. MM_WEB_DEFER_ASSEMBLY=0: the builder assembles it itself.
  local assembler=()
  if [[ ${MM_WEB_DEFER_ASSEMBLY:-1} != 0 ]]; then
    assembler=(-H:WasmAsPath="$HERE/wasm_as_deferred.sh" -EMM_WASM_AS_DEFER -EMM_WASM_AS) # -E: the builder's environment
    export MM_WASM_AS_DEFER="$out/engine.js.wat" MM_WASM_AS; MM_WASM_AS=$(command -v wasm-as)
  fi
  # The driver gives the builder ParallelGC, whose young generation takes up to a third of the heap. MM_WEB_GC=g1 lets
  # the long-lived compiled code and image heap use nearly all of it (the patched build's 12 GB fits only so); the
  # stock build over swap is faster on ParallelGC (docs/WEB_ENGINE_M1.md, runs A and E).
  local gc=()
  if [[ ${MM_WEB_GC:-parallel} == g1 ]]; then gc=(-J-XX:-UseParallelGC -J-XX:+UseG1GC); fi
  local started=$SECONDS
  # --tool:svm-wasm must come first. Options mirror the phone build (native/gluon/pom.xml) where they apply.
  # V8 refuses Wasm functions over 7,654,321 bytes, hence 4,000 image-heap objects per initializer function; the
  # .wat comments (on by default) are never read, and the JS wrapper is small enough to skip Closure.
  "$GRAALVM_HOME/bin/native-image" --tool:svm-wasm \
    -J-Xmx"$heap" ${gc[@]+"${gc[@]}"} --parallelism="${MM_WEB_BUILDER_THREADS:-4}" \
    -O"${MM_WEB_OPT:-2}" \
    -H:+UnlockExperimentalVMOptions \
    -H:WasmComments=NONE -H:ImageHeapObjectsPerFunction=4000 -H:-ClosureCompiler \
    ${patch[@]+"${patch[@]}"} ${assembler[@]+"${assembler[@]}"} \
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
  if [[ -s "$out/engine.js.wat.args" ]]; then
    local args=() arg assembled=$SECONDS timed=()
    while IFS= read -r arg; do args+=("$arg"); done < "$out/engine.js.wat.args"
    # GNU time (CI) records the assembler's own peak memory.
    if /usr/bin/time -v true >/dev/null 2>&1; then timed=(/usr/bin/time -v -o "$out/wasm-as-time.txt"); fi
    ${timed[@]+"${timed[@]}"} "$MM_WASM_AS" "${args[@]}" 2>&1 | tee -a "$out/native-image.log"
    echo "wasm-as after the builder: $((SECONDS - assembled)) s" | tee -a "$out/native-image.log"
  fi
  [[ -s "$out/engine.js.wasm" ]] || { echo "No engine.js.wasm" >&2; exit 1; }
  echo "wasm build: $((SECONDS - started)) s" | tee -a "$out/native-image.log"
}

stage_bundle() {
  [[ -s "$BUILD/wasm/engine.js.wasm" ]] || { echo "Run the wasm stage first" >&2; exit 1; }
  local out="$BUILD/web"; rm -rf "$out"; mkdir -p "$out/decks"
  python3 "$HERE/patch_wrapper.py" "$BUILD/wasm/engine.js" "$out/engine.js"
  cp "$BUILD/wasm/engine.js.wasm" "$out/engine.wasm"
  python3 "$HERE/export_precons.py" --catalogue "$ENGINE/build/generated/catalogue.jsonl" \
    --swift "$REPO/apps/ios/MagicMobile/PreconCatalog.swift" --output "$out/decks"
  python3 - "$out" "$ENGINE" "$BUILD" <<'PY'
import gzip, hashlib, json, os, re, sys, time
from pathlib import Path
out, engine, build = (Path(a) for a in sys.argv[1:])
# Content-hashed names: an unchanged file keeps its name (and the browser's cached copy), a changed one gets a new
# name, so the engine is served immutable and manifest.json is the only file a page revalidates. Web Image builds
# are not byte-for-byte reproducible, so every rebuild gets new names: rebuild only when the engine changes.
files = {}
for kind, plain in (('js', 'engine.js'), ('wasm', 'engine.wasm')):
    data = (out / plain).read_bytes()
    files[kind] = f"engine-{hashlib.sha256(data).hexdigest()[:16]}.{kind}"
    (out / plain).rename(out / files[kind])
wasm = (out / files['wasm']).read_bytes()
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
    'buildKey': os.environ.get('MM_WEB_BUILD_KEY'),  # the CI workflow's key for the build's inputs
    'builderPatch': next((l.strip() for l in log.splitlines() if l.startswith('MagicMobile builder patch:')), None),
    'files': files,
    'wasm': {'bytes': len(wasm), 'gzip9Bytes': len(gzip.compress(wasm, 9)), 'sha256': hashlib.sha256(wasm).hexdigest()},
    'decks': sorted(p.stem for p in (out / 'decks').glob('*.json')),
    'webSources': json.loads((build / 'web-src/web-sources.json').read_text())['rewrites'],
}
(out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(f"bundle: {files['wasm']} {len(wasm)/1e6:.1f} MB raw, {manifest['wasm']['gzip9Bytes']/1e6:.1f} MB gzip -9, {identity}")
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
