#!/usr/bin/env bash
# AOT diagnostic only: the iOS device library. Pins: native/gluon/toolchain.json.
# The static JDK release (vmone gvm-24-2.1) has no iOS simulator library, so ios-sim is gone.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NATIVE_TARGET=${MM_NATIVE_TARGET:-ios}
[[ "$NATIVE_TARGET" == ios ]] || { echo 'MM_NATIVE_TARGET must be ios' >&2; exit 2; }
NATIVE_ARCH=arm64
export GRAALVM_HOME="${MM_GRAALVM_HOME:-$ROOT/build/toolchains/graalvm-java23-darwin-aarch64-gluon-23+25.1-dev/Contents/Home}"
# Checksum-verified libvmone.a (JDK static libraries and GraalVM's C helpers); setup_gluon_intel.sh.
NATIVE_STATIC_LIBS="${MM_JAVA_STATIC_LIBS:-$ROOT/build/toolchains/vmone-ios-macos-aarch64/lib}"
export JAVA_HOME="$GRAALVM_HOME"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="$JAVA_HOME/bin:$PATH"
export GRAALVM_COMPILER_BACKEND=lir

mkdir -p "$ROOT/evidence" "$ROOT/build/ios-native-home"
NATIVE_BUILD=$(mktemp -d "$ROOT/build/ios-native-XXXXXX")
mkdir -p "$NATIVE_BUILD/native-java"
NATIVE_LOG="$ROOT/evidence/$(basename "$NATIVE_BUILD").log"
exec > >(tee "$NATIVE_LOG") 2>&1
trap 'rc=$?; printf "\nDiagnostic exit code: %s\nBuild directory: %s\nLog: %s\n" "$rc" "$NATIVE_BUILD" "$NATIVE_LOG"' EXIT
printf 'AOT diagnostic target=%s, UTC %s\n' "$NATIVE_TARGET" "$(date -u +%FT%TZ)"
NATIVE_MAX_HEAP=${MM_NATIVE_MAX_HEAP:-4g}
case "$NATIVE_MAX_HEAP" in
  4g|5g) ;;
  10g)
    # Hosted-build setting: never apply it to the 8 GB development Mac.
    [[ $(sysctl -n hw.memsize) -ge 12884901888 ]] || {
      echo 'The 10g builder requires at least 12 GiB physical memory' >&2; exit 2;
    }
    ;;
  *) printf 'MM_NATIVE_MAX_HEAP must be 4g, 5g, or guarded 10g\n' >&2; exit 2 ;;
esac
printf 'Builder heap: %s; builder GC: G1 (iOS runtime collector unchanged)\n' "$NATIVE_MAX_HEAP"

[[ -x "$JAVA_HOME/bin/native-image" ]]
[[ -s "$ROOT/build/runtime-classpath.txt" ]]
[[ -s "$ROOT/build/generated/reflect-config.json" ]]
for line in $(python3 -c 'import json,sys;print(" ".join(json.load(open(sys.argv[1]))["graalvm"]["release_lines"]))' "$ROOT/native/gluon/toolchain.json"); do
  grep -qx "$line" "$JAVA_HOME/release"
done
[[ -s "$NATIVE_STATIC_LIBS/libvmone.a" ]]
shasum -a 256 "$NATIVE_STATIC_LIBS/libvmone.a"
NATIVE_OPTIMIZE=${MM_NATIVE_OPTIMIZE:-2}
[[ "$NATIVE_OPTIMIZE" == 2 || "$NATIVE_OPTIMIZE" == s ]]
printf 'Optimization level: -O%s\n' "$NATIVE_OPTIMIZE"
"$JAVA_HOME/bin/native-image" --version
xcodebuild -version

NATIVE_CP=$(<"$ROOT/build/runtime-classpath.txt")
[[ -n "$NATIVE_CP" ]]
NATIVE_BASELINE_PREFIX="$ROOT/build/core:$ROOT/build/engine:"
[[ "$NATIVE_CP" == "$NATIVE_BASELINE_PREFIX"* ]]
cp -R "$ROOT/build/core" "$NATIVE_BUILD/core"
cp -R "$ROOT/build/engine" "$NATIVE_BUILD/engine"
NATIVE_CP="$NATIVE_BUILD/core:$NATIVE_BUILD/engine:${NATIVE_CP#"$NATIVE_BASELINE_PREFIX"}"
(
  cd "$NATIVE_BUILD"
  # Include generated catalogue resources as well as bytecode in the frozen input receipt.
  find core engine -type f -print | LC_ALL=C sort | while IFS= read -r native_class; do
    shasum -a 256 "$native_class"
  done
) > "$NATIVE_BUILD/class-snapshot.sha256"
printf 'JVM class/resource snapshot captured: %s\n' "$NATIVE_BUILD"
shasum -a 256 "$NATIVE_BUILD/class-snapshot.sha256"
NATIVE_REFLECTION_PROFILE=${MM_NATIVE_REFLECTION_PROFILE:-broad}
NATIVE_REFLECTION_CONFIG="$ROOT/build/generated/reflect-config.json"
# Every profile also emits serialization metadata for save/resume checkpoints: the Serializable
# engine, card and plugin classes plus the checkpoint JDK allowlist (docs/PROTOCOL.md).
mkdir -p "$ROOT/build/tools"
"$JAVA_HOME/bin/javac" -J-Xmx512m --release 17 \
  -cp "$NATIVE_BUILD/core" -d "$ROOT/build/tools" \
  "$ROOT/engine/tools/NativeReflectionExporter.java"
"$JAVA_HOME/bin/java" -Xmx768m -cp "$ROOT/build/tools:$NATIVE_CP" \
  NativeReflectionExporter "$ROOT/build/native-metadata" \
  "$ROOT/.upstream/mage/Mage/target/classes" \
  "$ROOT/.upstream/mage/Mage.Sets/target/classes" \
  "$ROOT/.upstream/mage/Mage.Common/target/classes" \
  --serialization "$ROOT"/.upstream/mage/Mage.Server.Plugins/*/target/classes "$NATIVE_BUILD/engine"
NATIVE_SERIALIZATION_CONFIG="$ROOT/build/native-metadata/serialization-config.json"
case "$NATIVE_REFLECTION_PROFILE" in
  broad) ;;
  targeted) NATIVE_REFLECTION_CONFIG="$ROOT/build/native-metadata/reflect-config.json" ;;
  *) printf 'Unknown MM_NATIVE_REFLECTION_PROFILE: %s\n' "$NATIVE_REFLECTION_PROFILE" >&2; exit 2 ;;
esac
[[ -s "$NATIVE_REFLECTION_CONFIG" && -s "$NATIVE_SERIALIZATION_CONFIG" ]]
printf 'Reflection profile: %s\nConfiguration: %s\nSerialization: %s\n' "$NATIVE_REFLECTION_PROFILE" "$NATIVE_REFLECTION_CONFIG" "$NATIVE_SERIALIZATION_CONFIG"
shasum -a 256 "$NATIVE_REFLECTION_CONFIG" "$NATIVE_SERIALIZATION_CONFIG" "$ROOT/build/generated/reflect-config.json" "$ROOT/build/runtime-classpath.txt"
NATIVE_INIT_ARG='--initialize-at-run-time=io.magicmobile,mage'
case "${MM_NATIVE_INIT_PROFILE:-runtime}" in
  runtime) ;;
  reviewed-enums)
    # Explicitly reviewed pure enum initializers only, never a package-wide override.
    # In particular SubType, AffinityType, BeholdType and predicate-owning enums
    # remain runtime-initialized. See docs/NATIVE_METADATA.md.
    NATIVE_INIT_TYPES=$(paste -sd, "$ROOT/native/gluon/buildtime-enums.txt")
    [[ "$NATIVE_INIT_TYPES" == mage.constants.* ]]
    NATIVE_INIT_ARG="--initialize-at-build-time=$NATIVE_INIT_TYPES"
    shasum -a 256 "$ROOT/native/gluon/buildtime-enums.txt"
    ;;
  *) printf 'Unknown MM_NATIVE_INIT_PROFILE\n' >&2; exit 2 ;;
esac
printf 'Initialization profile: %s\n' "${MM_NATIVE_INIT_PROFILE:-runtime}"
NATIVE_ORM_ARG='--initialize-at-run-time=io.magicmobile'
NATIVE_SOURCES=(
  "$ROOT/engine/native/src/main/java/io/magicmobile/nativebridge/NativeEntryPoints.java"
  "$ROOT/native/gluon/src/main/java/io/magicmobile/nativebridge/IosLibraryMain.java"
  "$ROOT/native/gluon/src/main/java/io/magicmobile/nativebridge/CheckpointSerializationFeature.java"
)
case "${MM_NATIVE_ORM_PROFILE:-runtime}" in
  runtime) ;;
  runtime-defaults)
    # ORMLite annotation enum values retain converter instances in the image.
    # Preserve locale/timezone defaults through the tested native-only adaptation.
    ORM_JAR=$(printf '%s\n' "$NATIVE_CP" | tr ':' '\n' | grep '/ormlite-core/5.7/ormlite-core-5.7.jar$')
    [[ -s "$ORM_JAR" ]]
    shasum -a 256 "$ORM_JAR"
    NATIVE_ORM_ARG='--initialize-at-build-time=com.j256.ormlite.field.types'
    NATIVE_SOURCES+=("$ROOT/native/gluon/src/main/java/io/magicmobile/nativebridge/OrmLiteDateFormatSubstitutions.java")
    ;;
  *) printf 'Unknown MM_NATIVE_ORM_PROFILE\n' >&2; exit 2 ;;
esac
printf 'ORM profile: %s\n' "${MM_NATIVE_ORM_PROFILE:-runtime}"
# This distribution supplies the matching C ABI SDK as a JDK module.
"$JAVA_HOME/bin/javac" -J-Xmx512m -source 17 -target 17 \
  --add-modules org.graalvm.sdk \
  -cp "$JAVA_HOME/lib/svm/builder/svm.jar:$NATIVE_CP" -d "$NATIVE_BUILD/native-java" \
  "${NATIVE_SOURCES[@]}"
printf 'Real NativeEntryPoints compilation passed.\n'
# CheckpointSerializationFeature defines this java.base class while the image builds (see its source).
"$JAVA_HOME/bin/javac" -J-Xmx256m -source 17 -target 17 --patch-module "java.base=$ROOT/native/gluon/src/main/java-base" \
  -d "$NATIVE_BUILD/checkpoint-accessor" "$ROOT/native/gluon/src/main/java-base/jdk/internal/reflect/MobileCheckpointConstructorAccessor.java"
cp "$NATIVE_BUILD/checkpoint-accessor/jdk/internal/reflect/MobileCheckpointConstructorAccessor.class" \
  "$NATIVE_BUILD/native-java/io/magicmobile/nativebridge/checkpoint-constructor-accessor.bin"
# Refuse, before the long native build, a resource configuration that would embed .class files
# (or leave out a resource the engine reads). The report lists every embedded resource.
python3 "$ROOT/scripts/check_native_resources.py" --classpath "$NATIVE_BUILD/native-java:$NATIVE_CP" \
  --config "$ROOT/native/resource-config.json" --report "$NATIVE_BUILD/native-resources.json"

# Keep Maven dependencies and Gluon downloads within the authorized build tree.
export MAVEN_OPTS="-Xmx512m -Duser.home=$ROOT/build/ios-native-home"
# Substrate 0.0.65's staticlib compiles the image itself, then archives it (a separate compile
# goal would compile twice).
NATIVE_GOALS=(com.gluonhq:gluonfx-maven-plugin:1.0.25:staticlib)
mvn --batch-mode --no-transfer-progress \
  -f "$ROOT/native/gluon/pom.xml" \
  "-Dmaven.repo.local=$ROOT/build/ios-native-maven" \
  "-Dengine.root=$ROOT" "-Dnative.build=$NATIVE_BUILD" \
  "-Dnative.classpath=$NATIVE_CP" \
  "-Dnative.reflection.config=$NATIVE_REFLECTION_CONFIG" \
  "-Dnative.serialization.config=$NATIVE_SERIALIZATION_CONFIG" \
  -Dnative.checkpoint.feature=--features=io.magicmobile.nativebridge.CheckpointSerializationFeature \
  "-Dnative.init.arg=$NATIVE_INIT_ARG" \
  "-Dnative.orm.arg=$NATIVE_ORM_ARG" \
  "-Dnative.max.heap=$NATIVE_MAX_HEAP" \
  "-Dnative.optimize=$NATIVE_OPTIMIZE" "-Djavalibspath=$NATIVE_STATIC_LIBS" \
  "-Dnative.target=$NATIVE_TARGET" \
  "${NATIVE_GOALS[@]}"

NATIVE_ARCHIVE="$NATIVE_BUILD/gluonfx/$NATIVE_ARCH-ios/gvm/libmmengine.a"
[[ -s "$NATIVE_ARCHIVE" ]]
xcrun lipo -info "$NATIVE_ARCHIVE"
xcrun ar -t "$NATIVE_ARCHIVE"
NATIVE_SYMBOLS=$(xcrun nm -g "$NATIVE_ARCHIVE")
for symbol in mm_engine_request mm_engine_free mm_engine_shutdown_v2 graal_create_isolate; do
  printf '%s\n' "$NATIVE_SYMBOLS" | grep -E "[[:space:]]T[[:space:]]_${symbol}$"
done
if [[ -n "${MM_NATIVE_RESULT_FILE:-}" ]]; then
  printf '%s\n' "$NATIVE_BUILD" > "$MM_NATIVE_RESULT_FILE"
fi
printf '%s archive produced: %s\nNot linked into Swift or executed.\n' "$NATIVE_TARGET" "$NATIVE_ARCHIVE"
