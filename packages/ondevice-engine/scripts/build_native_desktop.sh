#!/usr/bin/env bash
# Desktop AOT is a diagnostic gate. This does NOT build an iOS binary.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
: "${GRAALVM_HOME:?Set GRAALVM_HOME to an installed GraalVM JDK with native-image}"
[[ -s "$ROOT/build/runtime-classpath.txt" ]] || { echo "Run build_jvm.sh first" >&2; exit 1; }
NI="$GRAALVM_HOME/bin/native-image"
[[ -x "$NI" ]] || { echo "Missing native-image" >&2;exit 1; }
CP=$(cat "$ROOT/build/runtime-classpath.txt")
SDK="${GRAAL_SDK_CP:-}"
mkdir -p "$ROOT/build/native-java" "$ROOT/build/native-desktop" "$ROOT/evidence"
# Some distributions expose the SDK by default; otherwise supply its explicit classpath.
find "$ROOT/engine/native/src/main/java" -name '*.java' > "$ROOT/build/native-sources.txt"
"$GRAALVM_HOME/bin/javac" -cp "$CP${SDK:+:$SDK}" -d "$ROOT/build/native-java" @"$ROOT/build/native-sources.txt"
cd "$ROOT/build/native-desktop"
"$NI" --shared --no-fallback -o libmmengine \
  -cp "$ROOT/build/native-java:$CP${SDK:+:$SDK}" \
  --initialize-at-run-time=io.magicmobile,mage \
  -H:ReflectionConfigurationFiles="$ROOT/build/generated/reflect-config.json" \
  -H:ResourceConfigurationFiles="$ROOT/native/resource-config.json" \
  2>&1 | tee "$ROOT/evidence/native-desktop-build.txt"
[[ -f libmmengine.h ]] || { echo "No generated native header" >&2;exit 1; }
clang -std=c11 -D_POSIX_C_SOURCE=200809L -I. -I"$ROOT/native" \
  -I"$ROOT/swift/Sources/CMagicEngine/include" \
  "$ROOT/native/real_backend_probe.c" "$ROOT/native/mm_graal_backend.c" \
  "$ROOT/swift/Sources/CMagicEngine/mm_runtime.c" \
  -L. -lmmengine -Wl,-rpath,"$PWD" -lpthread -o real_backend_probe
./real_backend_probe | tee "$ROOT/evidence/native-desktop-probe.txt"
