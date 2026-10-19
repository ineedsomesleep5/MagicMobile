#!/usr/bin/env bash
# Download only the pinned official Intel Mac compiler and iOS static JDK, never signing material.
# Pins: native/gluon/toolchain.json. Writes build/toolchains/ios-toolchain.env (MM_GRAALVM_HOME,
# MM_JAVA_STATIC_LIBS) for the build and probe scripts.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
[[ "$(uname -s)" == Darwin && "$(uname -m)" == x86_64 ]] || {
  echo 'This installer is for the Intel macOS build host only.' >&2; exit 2;
}
pin() { python3 -c 'import json,sys;v=json.load(open(sys.argv[1]));[v:=v[k] for k in sys.argv[2:]];print(v)' "$ROOT/native/gluon/toolchain.json" "$@"; }
ARCHIVE_NAME=$(pin graalvm archives darwin-amd64 name)
TOOLCHAIN=${ARCHIVE_NAME%.tar.gz}
ARCHIVE="$ROOT/build/toolchains/$ARCHIVE_NAME"
STATIC_NAME=$(pin static_jdk archives ios-macos-aarch64 name)
STATIC_ARCHIVE="$ROOT/build/toolchains/$STATIC_NAME"
STATIC_HOME="$ROOT/build/toolchains/${STATIC_NAME%.zip}"
mkdir -p "$ROOT/build/toolchains"
if [[ ! -f "$ARCHIVE" ]]; then
  curl --fail --location --retry 3 "$(pin graalvm url)${ARCHIVE_NAME//+/%2B}" --output "$ARCHIVE"
fi
printf '%s  %s\n' "$(pin graalvm archives darwin-amd64 sha256)" "$ARCHIVE" | shasum -a 256 -c -
if [[ ! -f "$STATIC_ARCHIVE" ]]; then
  curl --fail --location --retry 3 "$(pin static_jdk url)$STATIC_NAME" --output "$STATIC_ARCHIVE"
fi
printf '%s  %s\n' "$(pin static_jdk archives ios-macos-aarch64 sha256)" "$STATIC_ARCHIVE" | shasum -a 256 -c -
if [[ ! -d "$ROOT/build/toolchains/$TOOLCHAIN" ]]; then
  tar -xzf "$ARCHIVE" -C "$ROOT/build/toolchains"
fi
if [[ ! -d "$STATIC_HOME" ]]; then
  [[ "$(unzip -Z1 "$STATIC_ARCHIVE" | grep -v '/$')" == lib/libvmone.a ]]
  unzip -q "$STATIC_ARCHIVE" lib/libvmone.a -d "$STATIC_HOME"
fi
PINNED_HOME="$ROOT/build/toolchains/$TOOLCHAIN/Contents/Home"
python3 - "$ROOT/native/gluon/toolchain.json" "$PINNED_HOME/release" <<'PY'
import json, sys
pins = json.load(open(sys.argv[1]))['graalvm']
release = open(sys.argv[2]).read()
for line in pins['release_lines'] + ['OS_ARCH="x86_64"', 'substratevm:' + pins['substratevm_commit']]:
    if line not in release:
        raise SystemExit('Unreviewed native toolchain release: missing ' + line)
PY
xcrun lipo -info "$STATIC_HOME/lib/libvmone.a" | grep -q 'arm64'
"$PINNED_HOME/bin/native-image" --version
printf 'MM_GRAALVM_HOME=%s\nMM_JAVA_STATIC_LIBS=%s\n' "$PINNED_HOME" "$STATIC_HOME/lib" > "$ROOT/build/toolchains/ios-toolchain.env"
cat "$ROOT/build/toolchains/ios-toolchain.env"
