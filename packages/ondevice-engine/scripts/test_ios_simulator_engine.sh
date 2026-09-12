#!/usr/bin/env bash
# Full XMage native runtime diagnostic. CI owns the one simulator it creates.
# Gluon 1.0.29/Substrate 0.0.69: ios-sim, ios-amd64 C support, ios-x86_64 static JDK.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
[[ "$(uname -s)" == Darwin && "$(uname -m)" == x86_64 ]] || {
  echo 'ERROR: full ios-sim engine check requires an Intel macOS host.' >&2; exit 2;
}
[[ "${GITHUB_ACTIONS:-}" == true && "${RUNNER_ARCH:-}" == X64 ]] || {
  echo 'ERROR: simulator creation/execution is restricted to Intel GitHub CI.' >&2; exit 2;
}
[[ $# == 1 ]] || { echo "Usage: $0 FULL_NATIVE_BUILD_DIRECTORY" >&2; exit 2; }
NATIVE_BUILD=$(cd "$1" && pwd)
[[ "$NATIVE_BUILD" == "$ROOT/build/ios-native-"* ]] || exit 2
mkdir -p "$ROOT/build" "$ROOT/evidence/ios-simulator-engine"
ENGINE_BUILD=$(mktemp -d "$ROOT/build/ios-sim-engine-XXXXXX")
exec > >(tee "$ROOT/evidence/ios-simulator-engine/$(basename "$ENGINE_BUILD").log") 2>&1

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
  if [[ -z "$SIM_UUID" && -s "$ENGINE_BUILD/created-uuid.txt" ]]; then
    SIM_UUID=$(<"$ENGINE_BUILD/created-uuid.txt")
  fi
  if [[ "$SIM_UUID" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
    bounded 30 xcrun simctl shutdown "$SIM_UUID" || true
    bounded 30 xcrun simctl delete "$SIM_UUID" || rc=1
  fi
  printf '\nSIMULATOR ENGINE exit=%s build=%s; no physical-device or completed-game proof.\n' "$rc" "$ENGINE_BUILD"
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
printf 'FULL XMAGE SIMULATOR RUNTIME CHECK; UTC %s\n' "$(date -u +%FT%TZ)"
export GRAALVM_HOME="${MM_GRAALVM_HOME:-$ROOT/build/toolchains/graalvm-svm-java17-darwin-gluon-22.1.0.1-Final/Contents/Home}"
export JAVA_HOME="$GRAALVM_HOME"
export PATH="$JAVA_HOME/bin:$PATH"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode_26.6.app/Contents/Developer}"
export GRAALVM_COMPILER_BACKEND=lir
grep -qx 'GRAALVM_VERSION="22.1.0.1"' "$JAVA_HOME/release"
grep -qx 'JAVA_VERSION="17.0.3"' "$JAVA_HOME/release"
grep -qx 'VENDOR=Gluon' "$JAVA_HOME/release"
grep -qx 'OS_ARCH="x86_64"' "$JAVA_HOME/release"
xcodebuild -version | tee "$ENGINE_BUILD/xcode-version.txt"
grep -qx 'Xcode 26.6' "$ENGINE_BUILD/xcode-version.txt"
"$JAVA_HOME/bin/native-image" --version
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
SDK_VERSION=$(xcrun --sdk iphonesimulator --show-sdk-version)
# The first CoreSimulator query can initialize the service on a fresh CI host.
# Run 34665870814 exhausted 30s before compilation; keep a finite discovery bound.
bounded 120 xcrun simctl list --json > "$ENGINE_BUILD/simctl-before.json"
# Use runtime-supported device types, not a guessed iPhone model or existing UDID.
# Require the selected runtime to match the SDK major/minor explicitly.
python3 - "$ENGINE_BUILD/simctl-before.json" "$SDK_VERSION" > "$ENGINE_BUILD/selection.txt" <<'PY'
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
RUNTIME=$(sed -n '1p' "$ENGINE_BUILD/selection.txt")
DEVICE_TYPE=$(sed -n '2p' "$ENGINE_BUILD/selection.txt")
printf 'SDK=%s version=%s\nRuntime/type/version:\n' "$SDK" "$SDK_VERSION"
sed -n '1,3p' "$ENGINE_BUILD/selection.txt"

GVM="$NATIVE_BUILD/gluonfx/x86_64-ios/gvm"
CLIB="$JAVA_HOME/lib/svm/clibraries/27/ios-amd64"
JDKLIB="$ROOT/build/ios-native-home/.gluon/substrate/javaStaticSdk/18-ea+prep18-9/ios-x86_64/staticjdk/lib/static"
[[ -s "$GVM/libmmengine.a" && -s "$CLIB/liblibchelper.a" && -s "$JDKLIB/libjava.a" ]]
[[ "$(xcrun lipo -archs "$GVM/libmmengine.a")" == x86_64 ]]
xcrun nm -g "$GVM/libmmengine.a" > "$ENGINE_BUILD/archive-symbols.txt"
for symbol in mm_engine_request mm_engine_free mm_engine_shutdown_v2 graal_create_isolate; do
  grep -E "[[:space:]]T[[:space:]]_${symbol}$" "$ENGINE_BUILD/archive-symbols.txt"
done
if grep -E '_mm_toolchain_probe$' "$ENGINE_BUILD/archive-symbols.txt"; then
  echo 'ERROR: toy toolchain archive is not a full engine.' >&2; exit 1
fi
HEADER="$GVM/mmengine/io.magicmobile.nativebridge.ioslibrarymain.h"
[[ -s "$HEADER" ]]
for symbol in mm_engine_request mm_engine_free mm_engine_shutdown_v2; do
  grep -q "$symbol" "$HEADER"
done
# Adapt only the filename; declarations come from the real generated ABI header.
printf '#include "%s"\n' "$HEADER" > "$ENGINE_BUILD/libmmengine.h"

# JSON-lines transport only. All rules and lifecycle operations enter NativeEntryPoints.
cat > "$ENGINE_BUILD/engine_cli.c" <<'C'
#include "mm_runtime.h"
#include "mm_graal_backend.h"
#include <stdio.h>
#include <stdlib.h>
int main(void) {
    if (mm_install_graal_backend() != MM_OK) return 1;
    mm_runtime *runtime = NULL;
    if (mm_runtime_create(&runtime) != MM_OK) return 2;
    char *line = NULL;
    size_t capacity = 0;
    ssize_t size;
    int result = 0;
    while ((size = getline(&line, &capacity, stdin)) >= 0) {
        unsigned char *output = NULL;
        size_t count = 0;
        if (mm_runtime_request(runtime, (unsigned char *)line, (size_t)size,
                               &output, &count) != MM_OK) { result = 3; break; }
        int written = fwrite(output, 1, count, stdout) == count;
        mm_response_free(output);
        if (!written || putchar('\n') == EOF || fflush(stdout) != 0) { result = 4; break; }
    }
    if (ferror(stdin)) result = 5;
    free(line);
    mm_status status = mm_runtime_destroy(runtime);
    fprintf(stderr, "SIMULATOR_ENGINE runtime_destroy=%d\n", status);
    return status == MM_OK ? result : 6;
}
C
for caller in real_backend_probe engine_cli; do
  SOURCE="$ROOT/native/real_backend_probe.c"
  [[ "$caller" != engine_cli ]] || SOURCE="$ENGINE_BUILD/engine_cli.c"
  bounded 120 xcrun --sdk iphonesimulator clang -target x86_64-apple-ios17.0-simulator \
    -isysroot "$SDK" -std=c11 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Werror \
    -I"$ENGINE_BUILD" -I"$GVM/mmengine" -I"$ROOT/native" \
    -I"$ROOT/swift/Sources/CMagicEngine/include" \
    "$SOURCE" "$ROOT/native/mm_graal_backend.c" "$ROOT/swift/Sources/CMagicEngine/mm_runtime.c" \
    "$GVM/libmmengine.a" \
    -L"$CLIB" -L"$JDKLIB" -ljava -lnio -lzip -lnet -lprefs -ljvm -lfdlibm \
    -lz -ldl -lj2pkcs11 -ljaas -lextnet -lc++ -lpthread -llibchelper -lffi -ldarwin \
    -framework Foundation -framework UIKit -framework CoreGraphics -framework Security \
    -o "$ENGINE_BUILD/$caller"
  xcrun vtool -show-build "$ENGINE_BUILD/$caller" | tee "$ENGINE_BUILD/$caller-platform.txt"
  grep -Eq 'platform IOSSIMULATOR$' "$ENGINE_BUILD/$caller-platform.txt"
  [[ "$(xcrun lipo -archs "$ENGINE_BUILD/$caller")" == x86_64 ]]
  xcrun nm -g "$ENGINE_BUILD/$caller" > "$ENGINE_BUILD/$caller-symbols.txt"
  for symbol in mm_engine_request mm_engine_free mm_engine_shutdown_v2 graal_create_isolate graal_tear_down_isolate; do
    grep -E "[[:space:]]T[[:space:]]_${symbol}$" "$ENGINE_BUILD/$caller-symbols.txt"
  done
  if grep -E '_mm_toolchain_probe$|_OBJC_CLASS_.*AppDelegate' "$ENGINE_BUILD/$caller-symbols.txt"; then
    echo 'ERROR: unexpected toy entry point or Gluon AppDelegate.' >&2; exit 1
  fi
done

# Resolve legal Commander lists from the complete catalogue of this build.
bounded 60 python3 "$ROOT/scripts/resolve_deck.py" --catalogue "$ROOT/build/generated/catalogue.jsonl" \
  --input "$ROOT/tests/decks/isamaru.txt" --commander 'Isamaru, Hound of Konda' --output "$ENGINE_BUILD/isamaru.json"
bounded 60 python3 "$ROOT/scripts/resolve_deck.py" --catalogue "$ROOT/build/generated/catalogue.jsonl" \
  --input "$ROOT/tests/decks/yargle.txt" --commander 'Yargle, Glutton of Urborg' --output "$ENGINE_BUILD/yargle.json"
python3 "$ROOT/scripts/make_match.py" "$ENGINE_BUILD/isamaru.json" "$ENGINE_BUILD/yargle.json" --output "$ENGINE_BUILD/match.json"
cat > "$ENGINE_BUILD/check_runtime.py" <<'PY_RUNTIME'
import json, sys, time, uuid
from pathlib import Path
from jvm_client import EngineProcess

def check_runtime(command, configuration, expected_hash, diagnostics):
    engine = EngineProcess(timeout=90, command=command, diagnostics=diagnostics)
    try:
        cap = engine.call('capabilities')
        if cap.get('engine') != 'xmage' or cap.get('execution') != 'native-aot':
            raise RuntimeError('Not the real native XMage backend')
        if cap.get('catalogueHash') != expected_hash:
            raise RuntimeError('Native archive does not match the full generated registry')
        created = engine.call('create', configuration=configuration)
        match, seats = created['matchId'], created['seats']
        if len(seats) != 2:
            raise RuntimeError('Expected two real human seats')
        deadline = time.monotonic() + 90
        prompt = None
        while time.monotonic() < deadline and prompt is None:
            for owner in seats:
                state = engine.call('poll', matchId=match, viewerId=owner, after=0)
                if state['phase'] == 'failed':
                    raise RuntimeError(str(state.get('failure')))
                if state.get('prompt'):
                    prompt = state['prompt']
                    break
            if prompt is None:
                time.sleep(.05)
        # The real Commander game's first prompt chooses a starting player.
        if not prompt or not prompt['payload'].get('candidates'):
            raise RuntimeError('No real starting-player prompt with legal UUID candidates')
        request_id = str(uuid.uuid4())
        receipt = engine.call('respond', matchId=match, viewerId=owner, command={
            'requestId': request_id, 'promptId': prompt['promptId'],
            'promptRevision': prompt['revision'],
            'answer': {'kind': 'uuid', 'value': prompt['payload']['candidates'][0]},
        })
        if receipt.get('status') != 'queued' or receipt.get('requestId') != request_id:
            raise RuntimeError('Invalid native response receipt')
        deadline = time.monotonic() + 90
        advanced = False
        while time.monotonic() < deadline and not advanced:
            for seat in seats:
                state = engine.call('poll', matchId=match, viewerId=seat, after=0)
                if state['phase'] == 'failed':
                    raise RuntimeError(str(state.get('failure')))
                next_prompt = state.get('prompt')
                if next_prompt and next_prompt['promptId'] != prompt['promptId']:
                    advanced = True
            if not advanced:
                time.sleep(.05)
        if not advanced:
            raise RuntimeError('Native engine did not apply the queued response')
        engine.call('destroy', matchId=match)
        rejected = engine.request('poll', matchId=match, viewerId=owner, after=0)
        if rejected.get('ok') or rejected.get('error', {}).get('code') != 'unknown_match':
            raise RuntimeError('Destroyed match remains accessible')
        # A zero protocol result without native teardown is not a runtime pass.
        engine.process.stdin.close()
        if engine.process.wait(timeout=60) != 0:
            raise RuntimeError('Native C runtime or isolate shutdown failed')
        if 'SIMULATOR_ENGINE runtime_destroy=0' not in Path(diagnostics).read_text():
            raise RuntimeError('No successful native teardown evidence')
        return {'result': 'passed', 'scope': 'full-XMage-x86_64-iOS-simulator',
                'operations': ['capabilities', 'create', 'poll', 'respond', 'destroy'],
                'catalogueHash': cap['catalogueHash'], 'upstream': cap['upstream'],
                'responseReceipt': receipt, 'responseApplied': True, 'runtimeDestroyed': True,
                'completedGame': False, 'physicalDevice': False, 'testFlight': False}
    finally:
        engine.__exit__(None, None, None)

if __name__ == '__main__':
    build = Path(sys.argv[1])
    registry = json.loads(Path(sys.argv[2]).read_text())
    report = check_runtime(
        ['xcrun', 'simctl', 'spawn', '--arch=x86_64', sys.argv[3], str(build / 'engine_cli')],
        json.loads((build / 'match.json').read_text()), registry['registryHash'],
        build / 'native-stderr.txt')
    (build / 'runtime-result.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
PY_RUNTIME
bounded 30 xcrun simctl create "FullXMage-$(basename "$ENGINE_BUILD")" "$DEVICE_TYPE" "$RUNTIME" > "$ENGINE_BUILD/created-uuid.txt"
SIM_UUID=$(<"$ENGINE_BUILD/created-uuid.txt")
[[ "$SIM_UUID" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] || {
  echo 'ERROR: simctl create did not return one valid owned UUID.' >&2; exit 1;
}
bounded 30 xcrun simctl boot "$SIM_UUID"
# Fresh iOS 26.5 migration needed more than 180s while plugins advanced.
bounded 600 xcrun simctl bootstatus "$SIM_UUID" -b
bounded 180 xcrun simctl spawn --arch=x86_64 "$SIM_UUID" "$ENGINE_BUILD/real_backend_probe" \
  | tee "$ENGINE_BUILD/capabilities-probe.txt"
PYTHONPATH="$ROOT/scripts${PYTHONPATH:+:$PYTHONPATH}" \
  bounded 600 python3 "$ENGINE_BUILD/check_runtime.py" "$ENGINE_BUILD" \
  "$ROOT/build/generated/registry-report.json" "$SIM_UUID" | tee "$ENGINE_BUILD/runtime-run.txt"
[[ -s "$ENGINE_BUILD/runtime-result.json" ]]
echo 'PASS: full native XMage simulator capabilities/create/poll/respond/destroy and isolate teardown; no device, completed-game or TestFlight claim.'
