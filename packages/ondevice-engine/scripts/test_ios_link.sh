#!/usr/bin/env bash
# Link the non-engine probe with a caller-owned main; never install or execute.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
[[ $# == 1 ]] || { echo "Usage: $0 PROBE_BUILD_DIRECTORY" >&2; exit 2; }
PROBE_BUILD=$(cd "$1" && pwd)
[[ "$PROBE_BUILD" == "$ROOT/build/ios-abi-"* ]]
GVM="$PROBE_BUILD/gluonfx/arm64-ios/gvm"
[[ -s "$GVM/libmmengine.a" ]]
[[ -s "$PROBE_BUILD/color-patch/classes/java/awt/Color.class" ]]
export GRAALVM_HOME="${MM_GRAALVM_HOME:-$ROOT/build/toolchains/graalvm-svm-java17-darwin-m1-gluon-22.1.0.1-Final/Contents/Home}"
export JAVA_HOME="$GRAALVM_HOME"
export PATH="$JAVA_HOME/bin:$PATH"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export MAVEN_OPTS="-Xmx256m -Duser.home=$ROOT/build/ios-native-home"
mkdir -p "$ROOT/evidence"
exec > >(tee "$ROOT/evidence/$(basename "$PROBE_BUILD")-link.log") 2>&1
# The link goal downloads the pinned target runtime libraries, unlike staticlib.
# Deliberately do not call package/install/nativerun (no signing or app execution).
mvn --batch-mode --no-transfer-progress -f "$ROOT/native/gluon/pom.xml" \
  "-Dmaven.repo.local=$ROOT/build/ios-native-maven" "-Dengine.root=$ROOT" \
  "-Dnative.build=$PROBE_BUILD" "-Dnative.classpath=$PROBE_BUILD/native-java" \
  "-Dnative.reflection.config=$ROOT/native/gluon/probes/empty-reflect-config.json" \
  "-Dnative.color.patch=$PROBE_BUILD/color-patch/classes" \
  com.gluonhq:gluonfx-maven-plugin:1.0.29:link
CLIB="$JAVA_HOME/lib/svm/clibraries/27/ios-arm64"
JDKLIB="$ROOT/build/ios-native-home/.gluon/substrate/javaStaticSdk/18-ea+prep18-9/ios-arm64/staticjdk/lib/static"
[[ -s "$CLIB/liblibchelper.a" && -s "$JDKLIB/libjava.a" ]]
xcrun --sdk iphoneos clang -target arm64-apple-ios17.0 \
  -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" -Wall -Wextra -Werror \
  -I"$GVM/mmengine" "$ROOT/native/gluon/probes/ios_probe_link_check.c" "$GVM/libmmengine.a" \
  -L"$CLIB" -L"$JDKLIB" -ljava -lnio -lzip -lnet -lprefs -ljvm -lfdlibm \
  -lz -ldl -lj2pkcs11 -ljaas -lextnet -lc++ -lpthread -llibchelper -lffi -ldarwin \
  -framework Foundation -framework UIKit -framework CoreGraphics -framework Security \
  -o "$PROBE_BUILD/ios_probe_link_check"
xcrun vtool -show-build "$PROBE_BUILD/ios_probe_link_check" | tee "$PROBE_BUILD/linked-platform.txt"
grep -q 'platform IOS$' "$PROBE_BUILD/linked-platform.txt"
xcrun nm -g "$PROBE_BUILD/ios_probe_link_check" > "$PROBE_BUILD/linked-symbols.txt"
grep -E '[[:space:]]T[[:space:]]_mm_toolchain_probe$' "$PROBE_BUILD/linked-symbols.txt"
grep -E '[[:space:]]T[[:space:]]_graal_create_isolate$' "$PROBE_BUILD/linked-symbols.txt"
if grep -E '_mm_engine_|_OBJC_CLASS_.*AppDelegate' "$PROBE_BUILD/linked-symbols.txt"; then
  echo 'Unexpected engine or Gluon AppDelegate in caller-owned probe' >&2; exit 1
fi
echo 'PASS: independent caller linked for iOS; no native runtime execution or XMage.'
