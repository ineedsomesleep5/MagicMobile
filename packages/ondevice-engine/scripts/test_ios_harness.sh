#!/usr/bin/env bash
# Apple SDK compile regression only: deliberately no native engine or signing.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP="$ROOT/../../apps/ios-ondevice"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
command -v xcodegen >/dev/null || { echo 'XcodeGen is required' >&2; exit 2; }
mkdir -p "$ROOT/evidence"
cd "$APP"
xcodegen generate --spec project.yml
# App target must differ from the MagicMobileOnDevice package target. Identical
# names produced duplicate compiler/AppIntents output paths in the actual build.
xcodebuild -project MagicMobileOnDevice.xcodeproj -scheme MagicMobileLab \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath "$ROOT/build/ios-harness-compile" \
  CODE_SIGNING_ALLOWED=NO -jobs 2 build 2>&1 | tee "$ROOT/evidence/ios-harness-build.log"
echo 'PASS: unsigned inspection harness compiled; not linked to native XMage or run.'
