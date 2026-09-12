#!/usr/bin/env bash
# Full PRODUCT device link only, after staging genuine matching AOT + SDK inputs.
# No simulator destination, no codesign, no TestFlight upload, no runtime claim.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$ROOT/../.." && pwd)
[[ "$(uname -s)" == Darwin ]] || { echo 'An Xcode macOS host is required' >&2; exit 2; }
command -v xcodegen >/dev/null || { echo 'Install reviewed XcodeGen on this build host first' >&2; exit 2; }
python3 -B "$ROOT/scripts/prepare_ios_app_native.py" --verify-installed > /dev/null
OUT=$(mktemp -d "$ROOT/build/issue4-device-link.XXXXXX")
mkdir -p "$ROOT/evidence"
exec > >(tee "$ROOT/evidence/$(basename "$OUT").log") 2>&1
printf 'Source commit: '; git -C "$REPO" rev-parse HEAD
# Fail on tracked changes: a link receipt must refer to a committed source tree.
git -C "$REPO" diff --quiet HEAD -- || { echo 'Commit reviewed tracked changes before recording this link' >&2; exit 2; }
(cd "$REPO/apps/ios" && xcodegen generate --spec native-engine.yml)
PROJECT="$REPO/apps/ios/MagicMobileiOS.xcodeproj"
BUILD_ARGS=(-project "$PROJECT" -scheme MagicMobile -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' -derivedDataPath "$OUT/DerivedData" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -jobs 2)
xcodebuild "${BUILD_ARGS[@]}" -showBuildSettings -json > "$OUT/settings.json"
python3 - "$OUT/settings.json" <<'PY'
import json,sys
rows=json.load(open(sys.argv[1]))
settings=[r['buildSettings'] for r in rows if r.get('target')=='MagicMobile']
if len(settings)!=1: raise SystemExit('Expected exactly one product target')
s=settings[0]
if s.get('PRODUCT_BUNDLE_IDENTIFIER')!='com.calebfeliciano.magicmobile': raise SystemExit('Wrong app identity')
if s.get('PLATFORM_NAME')!='iphoneos': raise SystemExit('Not a device build')
if 'XMAGE_NATIVE_LINKED' not in s.get('SWIFT_ACTIVE_COMPILATION_CONDITIONS','').split(): raise SystemExit('Refusing legacy/remote product entrypoint')
if s.get('CODE_SIGNING_ALLOWED')!='NO': raise SystemExit('Signing unexpectedly enabled')
print('PASS product identity, native entrypoint flag, iphoneos destination, signing disabled')
PY
xcodebuild "${BUILD_ARGS[@]}" build
APP="$OUT/DerivedData/Build/Products/Release-iphoneos/MagicMobile.app"
python3 "$ROOT/scripts/verify_issue4_unsigned_product.py" --app "$APP" --repo "$REPO" --output "$OUT/product-receipt.json"
cp "$OUT/product-receipt.json" "$ROOT/evidence/$(basename "$OUT")-receipt.json"
printf '\nUnsigned product: %s\nNo iPhone execution, signing, or upload performed.\n' "$APP"
