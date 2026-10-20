#!/usr/bin/env bash
# SDK/archive/header check only. No XMage classes, engine backend, or installation.
# MM_FORCE_TRAMPOLINES=1 builds the probe with GraalVM's -H:+UseDirectCallTrampolinesALot (a 1 KiB
# direct-call range) and requires AArch64 trampolines in the archive (upstream replacement for the
# retired 22.1 far-call backport).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
export GRAALVM_HOME="${MM_GRAALVM_HOME:-$ROOT/build/toolchains/graalvm-java23-darwin-aarch64-gluon-23+25.1-dev/Contents/Home}"
STATIC_LIBS="${MM_JAVA_STATIC_LIBS:-$ROOT/build/toolchains/vmone-ios-macos-aarch64/lib}"
[[ -s "$STATIC_LIBS/libvmone.a" ]]
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
POM=native/gluon/pom.xml
if [[ "${MM_FORCE_TRAMPOLINES:-0}" == 1 ]]; then
  POM="$PROBE_BUILD/trampolines-pom.xml"
  python3 - native/gluon/pom.xml "$POM" <<'PY'
import sys, xml.etree.ElementTree as E
ns = 'http://maven.apache.org/POM/4.0.0'; E.register_namespace('', ns)
tree = E.parse(sys.argv[1])
E.SubElement(tree.find('.//{%s}nativeImageArgs' % ns), '{%s}arg' % ns).text = '-H:+UseDirectCallTrampolinesALot'
tree.write(sys.argv[2], encoding='utf-8', xml_declaration=True)
PY
fi
mvn --batch-mode --no-transfer-progress -f "$POM" \
  "-Dmaven.repo.local=$ROOT/build/ios-native-maven" "-Dengine.root=$ROOT" \
  "-Dnative.build=$PROBE_BUILD" "-Dnative.classpath=$PROBE_BUILD/native-java" \
  "-Dnative.reflection.config=$ROOT/native/gluon/probes/empty-reflect-config.json" \
  "-Djavalibspath=$STATIC_LIBS" \
  -Dnative.max.heap=1g com.gluonhq:gluonfx-maven-plugin:1.0.25:staticlib
[[ -s "$PROBE_BUILD/builder-gc.log" ]]
grep -q 'gc,init' "$PROBE_BUILD/builder-gc.log"
grep -q 'Using G1' "$PROBE_BUILD/builder-gc.log"
GVM="$PROBE_BUILD/gluonfx/arm64-ios/gvm"
xcrun lipo "$GVM/libmmengine.a" -verify_arch arm64
xcrun ar -t "$GVM/libmmengine.a" | tee "$PROBE_BUILD/archive-members.txt"
xcrun nm -g "$GVM/libmmengine.a" > "$PROBE_BUILD/symbols.txt"
grep -E '[[:space:]]T[[:space:]]_mm_toolchain_probe$' "$PROBE_BUILD/symbols.txt"
grep -E '[[:space:]]T[[:space:]]_graal_create_isolate$' "$PROBE_BUILD/symbols.txt"
if [[ "${MM_FORCE_TRAMPOLINES:-0}" == 1 ]]; then
  python3 "$ROOT/scripts/count_direct_call_trampolines.py" --minimum 100 "$GVM/libmmengine.a"
fi
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
