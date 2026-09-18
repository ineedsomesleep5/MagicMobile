#!/usr/bin/env bash
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
ROOT="$REPO/packages/ondevice-engine"
OUT="$REPO/build_output/android"
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]]
: "${ANDROID_SDK:?Set ANDROID_SDK to the installed SDK}"
: "${ANDROID_NDK:?Set ANDROID_NDK to the installed NDK}"
[[ -s "$ROOT/build/runtime-classpath.txt" ]]
python3 -m unittest discover -s "$REPO/scripts/android/tests" -v
mkdir -p "$OUT"
[[ -f "$OUT/JAVA_HOME.txt" ]] || python3 "$REPO/scripts/android/prepare_toolchain.py" --result-file "$OUT/JAVA_HOME.txt"
export GRAALVM_HOME=$(cat "$OUT/JAVA_HOME.txt")
export JAVA_HOME="$GRAALVM_HOME"
export PATH="$JAVA_HOME/bin:$PATH"
export GRAALVM_COMPILER_BACKEND=lir
"$JAVA_HOME/bin/native-image" --version
BUILD=$(mktemp -d "$OUT/native-XXXXXXXX")
printf '%s\n' "$BUILD" > "$OUT/NATIVE_BUILD.txt"
CP=$(cat "$ROOT/build/runtime-classpath.txt")
PREFIX="$ROOT/build/core:$ROOT/build/engine:"
[[ "$CP" == "$PREFIX"* ]]
cp -R "$ROOT/build/core" "$BUILD/core"
cp -R "$ROOT/build/engine" "$BUILD/engine"
CP="$BUILD/core:$BUILD/engine:${CP#"$PREFIX"}"
(cd "$BUILD"; find core engine -type f -print0 | sort -z | xargs -0 sha256sum) > "$BUILD/class-snapshot.sha256"
mkdir -p "$BUILD/tools"
"$JAVA_HOME/bin/javac" -J-Xmx512m --release 17 -cp "$BUILD/core" -d "$BUILD/tools" "$ROOT/engine/tools/NativeReflectionExporter.java"
"$JAVA_HOME/bin/java" -Xmx512m -cp "$BUILD/tools:$CP" NativeReflectionExporter "$BUILD/metadata" \
  "$ROOT/.upstream/mage/Mage/target/classes" "$ROOT/.upstream/mage/Mage.Sets/target/classes" "$ROOT/.upstream/mage/Mage.Common/target/classes"
"$JAVA_HOME/bin/javac" -J-Xmx512m -source 17 -target 17 --add-modules org.graalvm.sdk \
  -cp "$JAVA_HOME/lib/svm/builder/svm.jar:$CP" -d "$BUILD/native-java" \
  "$ROOT/engine/native/src/main/java/io/magicmobile/nativebridge/NativeEntryPoints.java" \
  "$ROOT/native/gluon/src/main/java/io/magicmobile/nativebridge/IosLibraryMain.java" \
  "$ROOT/native/gluon/src/main/java/io/magicmobile/nativebridge/OrmLiteDateFormatSubstitutions.java"
python3 "$ROOT/scripts/prepare_native_color.py" --graalvm-home "$JAVA_HOME" --output "$BUILD/color-patch"
INIT_TYPES=$(paste -sd, "$ROOT/native/gluon/buildtime-enums.txt")
[[ "$INIT_TYPES" == mage.constants.* ]]
HEAP=${MM_ANDROID_NATIVE_HEAP:-10g}
[[ "$HEAP" == 10g || "$HEAP" == 5g ]]
if [[ "$HEAP" == 10g ]]; then
  [[ $(awk '/MemTotal/ {print $2}' /proc/meminfo) -ge 12582912 ]]
fi
export MAVEN_OPTS="-Xmx512m -Duser.home=$OUT/home"
# staticlib performs its own compilation; do not compile the huge image twice.
mvn --batch-mode --no-transfer-progress -f "$ROOT/native/gluon/pom.xml" \
  "-Dmaven.repo.local=$OUT/maven" "-Dengine.root=$ROOT" "-Dnative.build=$BUILD" \
  "-Dnative.classpath=$CP" "-Dnative.reflection.config=$BUILD/metadata/reflect-config.json" \
  "-Dnative.init.arg=--initialize-at-build-time=$INIT_TYPES" \
  '-Dnative.orm.arg=--initialize-at-build-time=com.j256.ormlite.field.types' \
  "-Dnative.max.heap=$HEAP" "-Dnative.color.patch=$BUILD/color-patch/classes" \
  -Dnative.target=android \
  com.gluonhq:gluonfx-maven-plugin:1.0.29:staticlib \
  2>&1 | tee "$OUT/full-native.log"
find "$BUILD/gluonfx" -type f \( -name '*.a' -o -name '*.h' \) -print | tee "$OUT/native-output-files.txt"
python3 "$REPO/scripts/android/stage_native.py" "$REPO" "$BUILD"
