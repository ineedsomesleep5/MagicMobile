#!/usr/bin/env bash
# Measurement only (docs/LIGHTER_ENGINE_PLAN.md step 4): a host (Linux x86-64) native executable of
# tools/ai-calibration/SearchSpeed.java with the engine's production native-image options at -O2 or -Os, so
# AI search speed can be compared between optimization levels (`profile_long_games.py speed --native`). Not an
# app build: x86-64, no Substrate. Needs about 11 GB of memory and the pinned Gluon GraalVM for
# JDK 23 (native/gluon/toolchain.json, linux-amd64) in GRAALVM_HOME.
#   bash scripts/build_native_bench.sh 2|s   -> build/native-bench/searchspeed-O<level>
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OPTIMIZE=${1:-2}
[[ "$OPTIMIZE" == 2 || "$OPTIMIZE" == s ]] || { echo 'Usage: build_native_bench.sh 2|s' >&2; exit 2; }
: "${GRAALVM_HOME:?Set GRAALVM_HOME to the pinned Gluon GraalVM for JDK 23 (linux-amd64)}"
grep -qx 'JAVA_VERSION="23"' "$GRAALVM_HOME/release"
[[ -s "$ROOT/build/runtime-classpath.txt" ]] || { echo 'Run build_jvm.sh first' >&2; exit 1; }
[[ -d "$ROOT/build/ai-calibration/decks" ]] || { echo 'Run ai_calibration.py decks first' >&2; exit 1; }
OUT="$ROOT/build/native-bench"; WORK="$OUT/work-O$OPTIMIZE"
rm -rf "$WORK"; mkdir -p "$WORK"
CP=$(<"$ROOT/build/runtime-classpath.txt")
TOOL="$WORK/tools"
"$GRAALVM_HOME/bin/javac" -J-Xmx512m --release 17 -nowarn -cp "$CP" -d "$TOOL" \
  "$ROOT"/tools/ai-calibration/{AICalibration,SearchEquivalence,SearchSpeed}.java
# The engine's reflection metadata, as the phone builds export it.
"$GRAALVM_HOME/bin/javac" -J-Xmx512m --release 17 -cp "$ROOT/build/core" -d "$WORK/exporter" "$ROOT/engine/tools/NativeReflectionExporter.java"
"$GRAALVM_HOME/bin/java" -Xmx768m -cp "$WORK/exporter:$CP" NativeReflectionExporter "$WORK/metadata" \
  "$ROOT/.upstream/mage/Mage/target/classes" "$ROOT/.upstream/mage/Mage.Sets/target/classes" \
  "$ROOT/.upstream/mage/Mage.Common/target/classes" \
  --serialization "$ROOT"/.upstream/mage/Mage.Server.Plugins/*/target/classes "$ROOT/build/engine" > "$WORK/exporter.log"
# Save/resume checkpoints as the phone builds register them (the tool prints the self-test result).
"$GRAALVM_HOME/bin/javac" -J-Xmx512m -source 17 -target 17 -nowarn --add-modules org.graalvm.sdk \
  -cp "$GRAALVM_HOME/lib/svm/builder/svm.jar:$CP" -d "$WORK/native-java" \
  "$ROOT/native/gluon/src/main/java/io/magicmobile/nativebridge/CheckpointSerializationFeature.java"
"$GRAALVM_HOME/bin/javac" -J-Xmx256m -source 17 -target 17 -nowarn --patch-module "java.base=$ROOT/native/gluon/src/main/java-base" \
  -d "$WORK/checkpoint-accessor" "$ROOT/native/gluon/src/main/java-base/jdk/internal/reflect/MobileCheckpointConstructorAccessor.java"
cp "$WORK/checkpoint-accessor/jdk/internal/reflect/MobileCheckpointConstructorAccessor.class" \
  "$WORK/native-java/io/magicmobile/nativebridge/checkpoint-constructor-accessor.bin"
# What the tool itself reaches by reflection (seat setup, search limits), from one short traced JVM run.
DECKS="$ROOT/build/ai-calibration/decks"
(cd "$WORK" && "$GRAALVM_HOME/bin/java" -Xmx2g -XX:+UseSerialGC -Djava.awt.headless=true \
  "-agentlib:native-image-agent=config-output-dir=$WORK/agent" \
  "-Dlog4j.configuration=file:$ROOT/tools/ai-calibration/log4j.properties" -cp "$TOOL:$CP" \
  io.magicmobile.xmage.SearchSpeed "$WORK/agent-run.csv" 1 4 4 1 "$DECKS/ai-krenko-mob-boss-upgraded.json" \
  "$DECKS/ai-edgar-markov-upgraded.json" 6 1 50 20) > "$WORK/agent-run.log" 2>&1
[[ -s "$WORK/agent/reflect-config.json" || -s "$WORK/agent/reachability-metadata.json" ]]
AGENT_REFLECTION=$(ls "$WORK"/agent/reflect-config.json 2>/dev/null || true)
INIT_TYPES=$(paste -sd, "$ROOT/native/gluon/buildtime-enums.txt")
ARGS=(-O"$OPTIMIZE" --no-fallback -J-Xmx10g -J-XX:-UseParallelGC -J-XX:+UseG1GC -H:+UnlockExperimentalVMOptions
  -H:NumberOfThreads="${MM_BENCH_THREADS:-4}" -cp "$TOOL:$WORK/native-java:$CP"
  --features=io.magicmobile.nativebridge.CheckpointSerializationFeature
  "-Dmagicmobile.checkpoint.serialization=$WORK/metadata/serialization-config.json"
  -J--add-opens=java.base/jdk.internal.reflect=ALL-UNNAMED
  -J--add-exports=org.graalvm.nativeimage/org.graalvm.nativeimage.impl=ALL-UNNAMED
  -J--add-opens=org.graalvm.nativeimage.builder/com.oracle.svm.hosted.reflect.serialize=ALL-UNNAMED
  -J--add-exports=org.graalvm.nativeimage.builder/com.oracle.svm.core.reflect.serialize=ALL-UNNAMED
  --initialize-at-run-time=io.magicmobile,mage --initialize-at-run-time=java.awt.Color,java.awt.Toolkit
  "--initialize-at-build-time=$INIT_TYPES" --initialize-at-build-time=com.j256.ormlite.field.types
  -H:+IncludeAllLocales "-H:ReflectionConfigurationFiles=$WORK/metadata/reflect-config.json${AGENT_REFLECTION:+,$AGENT_REFLECTION}"
  "-H:ResourceConfigurationFiles=$ROOT/native/resource-config.json" -H:DisableURLProtocols=http,https
  -H:ServiceLoaderFeatureExcludeServices=java.sql.Driver -o "$OUT/searchspeed-O$OPTIMIZE")
mkdir -p "$OUT"
"$GRAALVM_HOME/bin/native-image" "${ARGS[@]}" io.magicmobile.xmage.SearchSpeed 2>&1 | tee "$OUT/build-O$OPTIMIZE.log"
ls -la "$OUT/searchspeed-O$OPTIMIZE"
echo "Host x86-64 benchmark only; not an Android or iOS engine."
