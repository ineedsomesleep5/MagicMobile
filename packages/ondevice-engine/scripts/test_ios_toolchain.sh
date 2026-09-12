#!/usr/bin/env bash
# SDK/archive/header check only. No XMage classes, engine backend, or installation.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
export GRAALVM_HOME="${MM_GRAALVM_HOME:-$ROOT/build/toolchains/graalvm-svm-java17-darwin-m1-gluon-22.1.0.1-Final/Contents/Home}"
export JAVA_HOME="$GRAALVM_HOME"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="$JAVA_HOME/bin:$PATH"
export GRAALVM_COMPILER_BACKEND=lir
export MAVEN_OPTS="-Xmx256m -Duser.home=$ROOT/build/ios-native-home"
mkdir -p build evidence
PROBE_BUILD=$(mktemp -d "$ROOT/build/ios-abi-XXXXXX")
PROBE_LOG="$ROOT/evidence/$(basename "$PROBE_BUILD").log"
exec > >(tee "$PROBE_LOG") 2>&1
trap 'rc=$?; printf "\nToolchain-only probe exit: %s\nBuild: %s\n" "$rc" "$PROBE_BUILD"' EXIT
printf 'TOOLCHAIN ONLY: no XMage, no engine backend; UTC %s\n' "$(date -u +%FT%TZ)"
mkdir -p "$PROBE_BUILD/native-java"
"$JAVA_HOME/bin/javac" -J-Xmx128m -source 17 -target 17 --add-modules org.graalvm.sdk \
  -d "$PROBE_BUILD/native-java" native/gluon/src/main/java/io/magicmobile/nativebridge/IosLibraryMain.java \
  native/gluon/probes/IosToolchainProbe.java
mvn --batch-mode --no-transfer-progress -f native/gluon/pom.xml \
  "-Dmaven.repo.local=$ROOT/build/ios-native-maven" "-Dengine.root=$ROOT" \
  "-Dnative.build=$PROBE_BUILD" "-Dnative.classpath=$PROBE_BUILD/native-java" \
  "-Dnative.reflection.config=$ROOT/native/gluon/probes/empty-reflect-config.json" \
  -Dnative.max.heap=1g com.gluonhq:gluonfx-maven-plugin:1.0.29:compile \
  com.gluonhq:gluonfx-maven-plugin:1.0.29:staticlib
[[ -s "$PROBE_BUILD/builder-gc.log" ]]
grep -q 'gc,init' "$PROBE_BUILD/builder-gc.log"
GVM="$PROBE_BUILD/gluonfx/arm64-ios/gvm"
xcrun lipo "$GVM/libmmengine.a" -verify_arch arm64
xcrun ar -t "$GVM/libmmengine.a" | tee "$PROBE_BUILD/archive-members.txt"
xcrun nm -g "$GVM/libmmengine.a" > "$PROBE_BUILD/symbols.txt"
grep -E '[[:space:]]T[[:space:]]_mm_toolchain_probe$' "$PROBE_BUILD/symbols.txt"
grep -E '[[:space:]]T[[:space:]]_graal_create_isolate$' "$PROBE_BUILD/symbols.txt"
if grep -E '_mm_engine_|_mm_runtime_|runtime_swift_close' "$PROBE_BUILD/symbols.txt" "$PROBE_BUILD/archive-members.txt"; then
  echo 'Unexpected engine/runtime fixture symbols in toolchain-only archive' >&2; exit 1
fi
[[ ! -e "$GVM/mmengine/runtime_swift_close.o" ]]
xcrun --sdk iphoneos clang -target arm64-apple-ios17.0 \
  -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" -Wall -Wextra -Werror \
  -I"$GVM/mmengine" -c native/gluon/probes/ios_probe_header_check.c \
  -o "$PROBE_BUILD/ios_probe_header_check.o"
xcrun vtool -show-build "$PROBE_BUILD/ios_probe_header_check.o"
echo 'PASS: toolchain-only ARM64 archive, separate probe export, iOS header caller compilation.'
echo 'Gluon archive still includes AppDelegate/main; NOT an engine XCFramework or runnable app.'
bash "$ROOT/scripts/test_ios_link.sh" "$PROBE_BUILD"
