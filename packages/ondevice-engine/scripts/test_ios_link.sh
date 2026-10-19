#!/usr/bin/env bash
# Link the non-engine probe with a caller-owned main; never install or execute.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
[[ $# == 1 ]] || { echo "Usage: $0 PROBE_BUILD_DIRECTORY" >&2; exit 2; }
PROBE_BUILD=$(cd "$1" && pwd)
[[ "$PROBE_BUILD" == "$ROOT/build/ios-abi-"* ]]
GVM="$PROBE_BUILD/gluonfx/arm64-ios/gvm"
[[ -s "$GVM/libmmengine.a" ]]
# libvmone.a: the JDK static libraries and GraalVM's C helpers (native/gluon/toolchain.json).
STATIC_LIBS="${MM_JAVA_STATIC_LIBS:-$ROOT/build/toolchains/vmone-ios-macos-aarch64/lib}"
[[ -s "$STATIC_LIBS/libvmone.a" ]]
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p "$ROOT/evidence"
exec > >(tee "$ROOT/evidence/$(basename "$PROBE_BUILD")-link.log") 2>&1
# Deliberately do not call package/install/nativerun (no signing or app execution). The caller
# links the same libraries the product does (apps/ios/native-engine.yml).
xcrun --sdk iphoneos clang -target arm64-apple-ios17.0 \
  -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" -Wall -Wextra -Werror \
  -I"$GVM/mmengine" "$ROOT/native/gluon/probes/ios_probe_link_check.c" "$GVM/libmmengine.a" \
  -L"$STATIC_LIBS" -lvmone -lz -ldl -lc++ -lpthread \
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
