#!/usr/bin/env bash
# AOT diagnostic only: device by default; optional full Intel simulator target.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NATIVE_TARGET=${MM_NATIVE_TARGET:-ios}
case "$NATIVE_TARGET" in
  ios) NATIVE_ARCH=arm64 ;;
  ios-sim)
    [[ "$(uname -s)" == Darwin && "$(uname -m)" == x86_64 ]] || {
      echo 'ios-sim requires an Intel macOS host' >&2; exit 2;
    }
    NATIVE_ARCH=x86_64
    ;;
  *) echo 'MM_NATIVE_TARGET must be ios or ios-sim' >&2; exit 2 ;;
esac
export GRAALVM_HOME="${MM_GRAALVM_HOME:-$ROOT/build/toolchains/graalvm-svm-java17-darwin-m1-gluon-22.1.0.1-Final/Contents/Home}"
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
NATIVE_NEW_RATIO=${MM_NATIVE_NEW_RATIO:-2}
case "$NATIVE_NEW_RATIO" in
  2|7) ;;
  *) printf 'MM_NATIVE_NEW_RATIO must be 2 (baseline) or 7 (retained-data diagnostic)\n' >&2; exit 2 ;;
esac
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
printf 'Builder heap: %s; Parallel GC NewRatio: %s\n' "$NATIVE_MAX_HEAP" "$NATIVE_NEW_RATIO"

[[ -x "$JAVA_HOME/bin/native-image" ]]
[[ -s "$ROOT/build/runtime-classpath.txt" ]]
[[ -s "$ROOT/build/generated/reflect-config.json" ]]
grep -qx 'GRAALVM_VERSION="22.1.0.1"' "$JAVA_HOME/release"
grep -qx 'JAVA_VERSION="17.0.3"' "$JAVA_HOME/release"
grep -qx 'VENDOR=Gluon' "$JAVA_HOME/release"
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
  find core engine -name '*.class' -type f -print | LC_ALL=C sort | while IFS= read -r native_class; do
    shasum -a 256 "$native_class"
  done
) > "$NATIVE_BUILD/class-snapshot.sha256"
printf 'JVM class snapshot captured: %s\n' "$NATIVE_BUILD"
shasum -a 256 "$NATIVE_BUILD/class-snapshot.sha256"
NATIVE_REFLECTION_PROFILE=${MM_NATIVE_REFLECTION_PROFILE:-broad}
NATIVE_REFLECTION_CONFIG="$ROOT/build/generated/reflect-config.json"
case "$NATIVE_REFLECTION_PROFILE" in
  broad) ;;
  targeted)
    mkdir -p "$ROOT/build/tools"
    "$JAVA_HOME/bin/javac" -J-Xmx512m --release 17 \
      -cp "$NATIVE_BUILD/core" -d "$ROOT/build/tools" \
      "$ROOT/engine/tools/NativeReflectionExporter.java"
    "$JAVA_HOME/bin/java" -Xmx512m -cp "$ROOT/build/tools:$NATIVE_CP" \
      NativeReflectionExporter "$ROOT/build/native-metadata" \
      "$ROOT/.upstream/mage/Mage/target/classes" \
      "$ROOT/.upstream/mage/Mage.Sets/target/classes" \
      "$ROOT/.upstream/mage/Mage.Common/target/classes"
    NATIVE_REFLECTION_CONFIG="$ROOT/build/native-metadata/reflect-config.json"
    ;;
  *) printf 'Unknown MM_NATIVE_REFLECTION_PROFILE: %s\n' "$NATIVE_REFLECTION_PROFILE" >&2; exit 2 ;;
esac
[[ -s "$NATIVE_REFLECTION_CONFIG" ]]
printf 'Reflection profile: %s\nConfiguration: %s\n' "$NATIVE_REFLECTION_PROFILE" "$NATIVE_REFLECTION_CONFIG"
shasum -a 256 "$NATIVE_REFLECTION_CONFIG" "$ROOT/build/generated/reflect-config.json" "$ROOT/build/runtime-classpath.txt"
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

# Keep Maven dependencies and Gluon downloads within the authorized build tree.
export MAVEN_OPTS="-Xmx512m -Duser.home=$ROOT/build/ios-native-home"
NATIVE_GOALS=(com.gluonhq:gluonfx-maven-plugin:1.0.29:compile com.gluonhq:gluonfx-maven-plugin:1.0.29:staticlib)
# The simulator's caller-owned C executable also needs the pinned static JDK,
# which Gluon's link goal downloads. Device behavior remains compile/staticlib.
if [[ "$NATIVE_TARGET" == ios-sim ]]; then
  NATIVE_GOALS+=(com.gluonhq:gluonfx-maven-plugin:1.0.29:link)
fi
mvn --batch-mode --no-transfer-progress \
  -f "$ROOT/native/gluon/pom.xml" \
  "-Dmaven.repo.local=$ROOT/build/ios-native-maven" \
  "-Dengine.root=$ROOT" "-Dnative.build=$NATIVE_BUILD" \
  "-Dnative.classpath=$NATIVE_CP" \
  "-Dnative.reflection.config=$NATIVE_REFLECTION_CONFIG" \
  "-Dnative.init.arg=$NATIVE_INIT_ARG" \
  "-Dnative.orm.arg=$NATIVE_ORM_ARG" \
  "-Dnative.new.ratio=$NATIVE_NEW_RATIO" \
  "-Dnative.max.heap=$NATIVE_MAX_HEAP" \
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
