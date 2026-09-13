#!/usr/bin/env bash
# Non-XMage probe only. CI owns the one simulator this script creates.
# Pinned route: gluonfx-maven-plugin 1.0.29 -> Substrate 0.0.69:
# model/Triplet.java IOS_SIM = x86_64-apple-ios; target/IosTargetConfiguration.java
# isSimulator() selects IPHONESIMULATOR for AMD64 (x86_64).
# https://docs.gluonhq.com/#_ios_simulator
# https://github.com/gluonhq/substrate/blob/0.0.69/src/main/java/com/gluonhq/substrate/target/IosTargetConfiguration.java
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
[[ "$(uname -s)" == Darwin && "$(uname -m)" == x86_64 ]] || {
  echo 'ERROR: pinned ios-sim probe requires an Intel macOS host.' >&2; exit 2;
}
[[ "${GITHUB_ACTIONS:-}" == true && "${RUNNER_ARCH:-}" == X64 ]] || {
  echo 'ERROR: simulator creation/execution is restricted to Intel GitHub CI.' >&2; exit 2;
}
mkdir -p "$ROOT/build" "$ROOT/evidence/ios-simulator-probe-only"
PROBE_BUILD=$(mktemp -d "$ROOT/build/ios-sim-probe-XXXXXX")
exec > >(tee "$ROOT/evidence/ios-simulator-probe-only/$(basename "$PROBE_BUILD").log") 2>&1

# External wall-clock bound, including subprocesses; Python is present on CI.
bounded() {
  python3 - "$@" <<'PY'
import os, signal, subprocess, sys
seconds = int(sys.argv[1])
process = subprocess.Popen(sys.argv[2:], start_new_session=True)
def stop(signum, frame):
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait()
    raise SystemExit(128 + signum)
signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)
try:
    code = process.wait(timeout=seconds)
except subprocess.TimeoutExpired:
    print(f'ERROR: command exceeded {seconds}s: {sys.argv[2:]}', file=sys.stderr)
    stop(signal.SIGALRM, None)
sys.exit(code if code >= 0 else 128 - code)
PY
}
SIM_UUID=''
cleanup() {
  rc=$?
  trap - EXIT
  # This file contains ONLY the stdout of our fresh simctl create operation.
  if [[ -z "$SIM_UUID" && -s "$PROBE_BUILD/created-uuid.txt" ]]; then
    SIM_UUID=$(<"$PROBE_BUILD/created-uuid.txt")
  fi
  if [[ "$SIM_UUID" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
    bounded 30 xcrun simctl shutdown "$SIM_UUID" || true
    bounded 30 xcrun simctl delete "$SIM_UUID" || rc=1
  fi
  printf '\nPROBE ONLY exit=%s build=%s; no XMage or physical-device proof.\n' "$rc" "$PROBE_BUILD"
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
printf 'TOOLCHAIN ONLY: no XMage; UTC %s\n' "$(date -u +%FT%TZ)"
export GRAALVM_HOME="${MM_GRAALVM_HOME:-$ROOT/build/toolchains/graalvm-svm-java17-darwin-gluon-22.1.0.1-Final/Contents/Home}"
export JAVA_HOME="$GRAALVM_HOME"
export PATH="$JAVA_HOME/bin:$PATH"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode_26.6.app/Contents/Developer}"
export GRAALVM_COMPILER_BACKEND=lir
export MAVEN_OPTS="-Xmx256m -Duser.home=$PROBE_BUILD/home"
grep -qx 'GRAALVM_VERSION="22.1.0.1"' "$JAVA_HOME/release"
grep -qx 'JAVA_VERSION="17.0.3"' "$JAVA_HOME/release"
grep -qx 'VENDOR=Gluon' "$JAVA_HOME/release"
grep -qx 'OS_ARCH="x86_64"' "$JAVA_HOME/release"
xcodebuild -version | tee "$PROBE_BUILD/xcode-version.txt"
grep -qx 'Xcode 26.6' "$PROBE_BUILD/xcode-version.txt"
"$JAVA_HOME/bin/native-image" --version
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
SDK_VERSION=$(xcrun --sdk iphonesimulator --show-sdk-version)
# The first CoreSimulator query can initialize the service on a fresh CI host.
# Run 34665870814 exhausted 30s before compilation; keep a finite discovery bound.
bounded 120 xcrun simctl list --json > "$PROBE_BUILD/simctl-before.json"
# Use runtime-supported device types, not a guessed iPhone model or existing UDID.
# Require the selected runtime to match the SDK major/minor explicitly.
python3 - "$PROBE_BUILD/simctl-before.json" "$SDK_VERSION" > "$PROBE_BUILD/selection.txt" <<'PY'
import json, sys
with open(sys.argv[1]) as source:
    inventory = json.load(source)
def version(value):
    return tuple(int(x) for x in value.split('.'))
sdk = version(sys.argv[2])
types = {d['identifier']: d for d in inventory['devicetypes']}
choices = []
for runtime in inventory['runtimes']:
    if not runtime.get('isAvailable') or not runtime['identifier'].startswith('com.apple.CoreSimulator.SimRuntime.iOS-'):
        continue
    rv = version(runtime['version'])
    if rv[:2] != sdk[:2] or rv < (17, 0):
        continue
    if 'supportedArchitectures' in runtime and 'x86_64' not in runtime['supportedArchitectures']:
        continue
    for supported in runtime.get('supportedDeviceTypes', []):
        device = types.get(supported['identifier'])
        if device and device.get('productFamily') == 'iPhone':
            choices.append((rv, runtime['identifier'], device['identifier']))
if not choices:
    raise SystemExit('ERROR: no available iOS runtime with supported iPhone type matches simulator SDK '
                     + sys.argv[2] + '; runtime/version/Intel support is unavailable, not device execution.')
rv, runtime_id, device_id = sorted(choices)[-1]
print(runtime_id)
print(device_id)
print('.'.join(map(str, rv)))
PY
RUNTIME=$(sed -n '1p' "$PROBE_BUILD/selection.txt")
DEVICE_TYPE=$(sed -n '2p' "$PROBE_BUILD/selection.txt")
printf 'SDK=%s version=%s\nRuntime/type/version:\n' "$SDK" "$SDK_VERSION"
sed -n '1,3p' "$PROBE_BUILD/selection.txt"
mkdir -p "$PROBE_BUILD/native-java" "$PROBE_BUILD/home"
bounded 60 "$JAVA_HOME/bin/javac" -J-Xmx128m -source 17 -target 17 --add-modules org.graalvm.sdk \
  -d "$PROBE_BUILD/native-java" \
  "$ROOT/native/gluon/src/main/java/io/magicmobile/nativebridge/IosLibraryMain.java" \
  "$ROOT/native/gluon/probes/IosToolchainProbe.java"
python3 "$ROOT/scripts/prepare_native_color.py" --graalvm-home "$JAVA_HOME" \
  --output "$PROBE_BUILD/color-patch"
# The link goal obtains the target static JDK libraries; no Gluon package/install/run.
bounded 1200 mvn --batch-mode --no-transfer-progress -f "$ROOT/native/gluon/pom.xml" \
  "-Dmaven.repo.local=$PROBE_BUILD/maven" "-Dengine.root=$ROOT" \
  "-Dnative.build=$PROBE_BUILD" "-Dnative.classpath=$PROBE_BUILD/native-java" \
  "-Dnative.reflection.config=$ROOT/native/gluon/probes/empty-reflect-config.json" \
  "-Dnative.color.patch=$PROBE_BUILD/color-patch/classes" \
  -Dnative.target=ios-sim -Dnative.max.heap=1g \
  com.gluonhq:gluonfx-maven-plugin:1.0.29:compile \
  com.gluonhq:gluonfx-maven-plugin:1.0.29:staticlib \
  com.gluonhq:gluonfx-maven-plugin:1.0.29:link
GVM="$PROBE_BUILD/gluonfx/x86_64-ios/gvm"
# Substrate getCLibPath uses Triplet.getOsArch2 (amd64); static JDK uses
# getOsArch (x86_64). These intentionally have different directory names.
CLIB="$JAVA_HOME/lib/svm/clibraries/27/ios-amd64"
JDKLIB="$PROBE_BUILD/home/.gluon/substrate/javaStaticSdk/18-ea+prep18-9/ios-x86_64/staticjdk/lib/static"
[[ -s "$GVM/libmmengine.a" && -s "$CLIB/liblibchelper.a" && -s "$JDKLIB/libjava.a" ]]
grep -q 'gc,init' "$PROBE_BUILD/builder-gc.log"
[[ "$(xcrun lipo -archs "$GVM/libmmengine.a")" == x86_64 ]]
xcrun nm -g "$GVM/libmmengine.a" > "$PROBE_BUILD/archive-symbols.txt"
grep -E '[[:space:]]T[[:space:]]_mm_toolchain_probe$' "$PROBE_BUILD/archive-symbols.txt"
if grep -E '_mm_engine_|_mm_runtime_|runtime_swift_close' "$PROBE_BUILD/archive-symbols.txt"; then
  echo 'ERROR: unexpected engine/fixture in probe archive.' >&2; exit 1
fi
HEADER="$GVM/mmengine/io.magicmobile.nativebridge.ioslibrarymain.h"
[[ -s "$HEADER" ]]
grep -q 'mm_toolchain_probe' "$HEADER"
bounded 60 xcrun --sdk iphonesimulator clang -target x86_64-apple-ios17.0-simulator \
  -isysroot "$SDK" -Wall -Wextra -Werror -I"$GVM/mmengine" \
  -c "$ROOT/native/gluon/probes/ios_probe_header_check.c" -o "$PROBE_BUILD/header-check.o"
APP="$PROBE_BUILD/ToolchainOnlyProbe.app"
mkdir -p "$APP"
cp "$ROOT/native/gluon/probes/ios_sim_probe_Info.plist" "$APP/Info.plist"
plutil -lint "$APP/Info.plist"
# Reuse the device helper's caller-owned main/library order, WITHOUT -ObjC.
bounded 60 xcrun --sdk iphonesimulator clang -target x86_64-apple-ios17.0-simulator \
  -isysroot "$SDK" -Wall -Wextra -Werror -I"$GVM/mmengine" \
  "$ROOT/native/gluon/probes/ios_probe_link_check.c" "$GVM/libmmengine.a" \
  -L"$CLIB" -L"$JDKLIB" -ljava -lnio -lzip -lnet -lprefs -ljvm -lfdlibm \
  -lz -ldl -lj2pkcs11 -ljaas -lextnet -lc++ -lpthread -llibchelper -lffi -ldarwin \
  -framework Foundation -framework UIKit -framework CoreGraphics -framework Security \
  -o "$APP/ios_probe_link_check"
xcrun vtool -show-build "$APP/ios_probe_link_check" | tee "$PROBE_BUILD/linked-platform.txt"
grep -Eq 'platform IOSSIMULATOR$' "$PROBE_BUILD/linked-platform.txt"
[[ "$(xcrun lipo -archs "$APP/ios_probe_link_check")" == x86_64 ]]
xcrun nm -g "$APP/ios_probe_link_check" > "$PROBE_BUILD/linked-symbols.txt"
grep -E '[[:space:]]T[[:space:]]_mm_toolchain_probe$' "$PROBE_BUILD/linked-symbols.txt"
grep -E '[[:space:]]T[[:space:]]_graal_create_isolate$' "$PROBE_BUILD/linked-symbols.txt"
grep -E '[[:space:]]T[[:space:]]_graal_tear_down_isolate$' "$PROBE_BUILD/linked-symbols.txt"
if grep -E '_mm_engine_|_mm_runtime_|runtime_swift_close|_OBJC_CLASS_.*AppDelegate' "$PROBE_BUILD/linked-symbols.txt"; then
  echo 'ERROR: unexpected engine/fixture/AppDelegate in linked probe.' >&2; exit 1
fi
bounded 30 xcrun simctl create "ToolchainOnly-$(basename "$PROBE_BUILD")" "$DEVICE_TYPE" "$RUNTIME" > "$PROBE_BUILD/created-uuid.txt"
SIM_UUID=$(<"$PROBE_BUILD/created-uuid.txt")
[[ "$SIM_UUID" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] || {
  echo 'ERROR: simctl create did not return one valid owned UUID.' >&2; exit 1;
}
bounded 30 xcrun simctl boot "$SIM_UUID"
# Fresh iOS 26.5 migration exceeded 180s in run 34666118749 while plugins progressed.
bounded 600 xcrun simctl bootstatus "$SIM_UUID" -b
# This caller is a C executable, not a UIKit application (no UIApplicationMain).
# Execute it in the booted simulator, rather than asking SpringBoard to launch it.
# This tests the native runtime only, not app installation or lifecycle.
bounded 60 xcrun simctl spawn --arch=x86_64 "$SIM_UUID" "$APP/ios_probe_link_check" \
  | tee "$PROBE_BUILD/simulator-run.txt"
grep -qx 'TOOLCHAIN_ONLY entered_main' "$PROBE_BUILD/simulator-run.txt"
grep -qx 'TOOLCHAIN_ONLY isolate_create=0' "$PROBE_BUILD/simulator-run.txt"
grep -qx 'TOOLCHAIN_ONLY result=42 isolate_teardown=0' "$PROBE_BUILD/simulator-run.txt"
echo 'PASS: non-XMage x86_64 iOS SIMULATOR probe executed isolate_create=0 result=42 isolate_teardown=0.'
