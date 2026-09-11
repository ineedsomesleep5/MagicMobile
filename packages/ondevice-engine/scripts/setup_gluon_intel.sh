#!/usr/bin/env bash
# Download only the pinned official Intel Mac compiler, never signing material.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
[[ "$(uname -s)" == Darwin && "$(uname -m)" == x86_64 ]] || {
  echo 'This installer is for the Intel macOS build host only.' >&2; exit 2;
}
TOOLCHAIN=graalvm-svm-java17-darwin-gluon-22.1.0.1-Final
ARCHIVE="$ROOT/build/toolchains/gluon-graal17-intel.tar.gz"
EXPECTED_SHA=61084c8e12a500e5019657d3160fa3394cd8230a0e780718a051d59028fbfb99
mkdir -p "$ROOT/build/toolchains"
if [[ ! -f "$ARCHIVE" ]]; then
  curl --fail --location --retry 3 \
    "https://github.com/gluonhq/graal/releases/download/gluon-22.1.0.1-Final/$TOOLCHAIN.tar.gz" \
    --output "$ARCHIVE"
fi
printf '%s  %s\n' "$EXPECTED_SHA" "$ARCHIVE" | shasum -a 256 -c -
if [[ ! -d "$ROOT/build/toolchains/$TOOLCHAIN" ]]; then
  tar -xzf "$ARCHIVE" -C "$ROOT/build/toolchains"
fi
PINNED_HOME="$ROOT/build/toolchains/$TOOLCHAIN/Contents/Home"
grep -qx 'GRAALVM_VERSION="22.1.0.1"' "$PINNED_HOME/release"
grep -qx 'JAVA_VERSION="17.0.3"' "$PINNED_HOME/release"
grep -qx 'VENDOR=Gluon' "$PINNED_HOME/release"
grep -qx 'OS_ARCH="x86_64"' "$PINNED_HOME/release"
"$PINNED_HOME/bin/native-image" --version
