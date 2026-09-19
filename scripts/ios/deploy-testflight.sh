#!/usr/bin/env bash
# Native TestFlight release. Every normal release must serve both internal and external testers.
set -euo pipefail
umask 077

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-$REPO_ROOT/apps/ios/MagicMobileiOS.xcodeproj}"
SCHEME="${SCHEME:-MagicMobile}"
CONFIGURATION="${CONFIGURATION:-Release}"
BUNDLE_ID="${BUNDLE_ID:-com.calebfeliciano.magicmobile}"
TEAM_ID="${TEAM_ID:-82HPAY85M8}"
EXPORT_OPTIONS="${EXPORT_OPTIONS:-$REPO_ROOT/release/testflight/ExportOptionsExternal.plist}"
TESTFLIGHT_AUDIENCE="${TESTFLIGHT_AUDIENCE:-external}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$REPO_ROOT/build_output/testflight}"
BUILD_NUMBER_SCRIPT="$REPO_ROOT/scripts/ios/testflight-build-number.mjs"
GUARD="$REPO_ROOT/scripts/ios/testflight_native_guard.py"
DISTRIBUTION_SCRIPT="$REPO_ROOT/scripts/ios/distribute-testflight-groups.sh"
ASC_KEY_ID="${ASC_KEY_ID:-Z54BVK456U}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-0e7ba65b-f006-4c46-bb4d-dddf7303de16}"
ASC_KEY_PATH="${ASC_KEY_PATH:-/Users/calebfeliciano/.appstoreconnect/private_keys/AuthKey_Z54BVK456U.p8}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if [[ "$(uname -s)" != Darwin ]]; then
  echo "Native signing/export requires desktop macOS and Xcode." >&2; exit 2
fi
if [[ "$PROJECT_PATH" != "$REPO_ROOT/apps/ios/MagicMobileiOS.xcodeproj" || "$SCHEME" != MagicMobile ||
      "$CONFIGURATION" != Release || "$BUNDLE_ID" != com.calebfeliciano.magicmobile || "$TEAM_ID" != 82HPAY85M8 ]]; then
  echo "Refusing a different product, configuration, app identity, or team." >&2; exit 2
fi
if [[ -n "${ARCHIVE_PATH:-}" || -n "${EXPORT_PATH:-}" ]]; then
  echo "Use OUTPUT_ROOT; archive/export paths are now unique per release and never overwritten." >&2; exit 2
fi
if [[ "${PREPARE_TESTFLIGHT_BUILD_NUMBER:-0}" != 0 ]]; then
  echo "Run 'node scripts/ios/testflight-build-number.mjs prepare', check App Store Connect availability, and commit before releasing." >&2
  exit 2
fi
if [[ "$TESTFLIGHT_AUDIENCE" != external ]]; then
  echo "TestFlight releases must use the external-safe export so both tester groups can receive the build." >&2; exit 2
fi
if [[ ! -f "$ASC_KEY_PATH" ]]; then
  echo "The configured App Store Connect API key file is missing." >&2; exit 2
fi
for tool in python3 node xcodegen xcodebuild xcrun codesign security asc; do
  command -v "$tool" >/dev/null || { echo "Required desktop tool missing: $tool" >&2; exit 2; }
done

# Scope all generated data to this checkout. In particular, never rm -rf a caller path.
python3 - "$REPO_ROOT" "$OUTPUT_ROOT" <<'PY'
from pathlib import Path
import sys
repo, output = Path(sys.argv[1]), Path(sys.argv[2])
if not output.is_absolute() or not output.resolve().is_relative_to(repo / 'build_output/testflight'):
    raise SystemExit('OUTPUT_ROOT must be inside this checkout\'s build_output/testflight directory')
if any(p.is_symlink() for p in (output, *output.parents)):
    raise SystemExit('Refusing a symlinked release output directory')
PY
mkdir -p "$OUTPUT_ROOT"
RUN_ROOT="$(mktemp -d "$OUTPUT_ROOT/native-release.XXXXXX")"
ARCHIVE_PATH="$RUN_ROOT/MagicMobile.xcarchive"
EXPORT_PATH="$RUN_ROOT/export"
IPA_PATH="$EXPORT_PATH/MagicMobile.ipa"
UPLOAD_LOG="$RUN_ROOT/altool-upload.log"
echo "Release evidence: $RUN_ROOT"
echo "This script requires a committed, prepared build number. App Store Connect availability is a separate desktop check."

# Must be a clean, reviewed source tree paired with a verified complete engine.
python3 "$GUARD" source --repo "$REPO_ROOT" --export-options "$EXPORT_OPTIONS" \
  --audience "$TESTFLIGHT_AUDIENCE" \
  --output "$RUN_ROOT/source-receipt.json" > "$RUN_ROOT/source-check.log"

# SDK-only checks can leave the reference project generated. Always select the real product.
xcodegen generate --spec "$REPO_ROOT/apps/ios/native-engine.yml"
xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME" -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' -showBuildSettings -json > "$RUN_ROOT/settings.json"
python3 "$GUARD" settings --repo "$REPO_ROOT" --receipt "$RUN_ROOT/source-receipt.json" \
  --settings "$RUN_ROOT/settings.json" --output "$RUN_ROOT/configured-receipt.json" > "$RUN_ROOT/settings-check.log"

xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME" -configuration Release -sdk iphoneos -jobs 2 \
  -destination 'generic/platform=iOS' -derivedDataPath "$RUN_ROOT/DerivedData" \
  -archivePath "$ARCHIVE_PATH" -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" archive 2>&1 | tee "$RUN_ROOT/archive.log"
xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" 2>&1 | tee "$RUN_ROOT/export.log"

# Inspect the actual exported signed app, including its UUID-matched dSYM, code
# image, all long-call veneers, identity/build and Game Center profile/entitlements.
python3 "$GUARD" exported --repo "$REPO_ROOT" --receipt "$RUN_ROOT/configured-receipt.json" \
  --ipa "$IPA_PATH" --archive "$ARCHIVE_PATH" --output "$RUN_ROOT/signed-receipt.json" > "$RUN_ROOT/signed-check.log"
xcrun altool --validate-app "$IPA_PATH" --api-key "$ASC_KEY_ID" \
  --api-issuer "$ASC_ISSUER_ID" 2>&1 | tee "$RUN_ROOT/apple-validation.log"
python3 "$GUARD" upload-input --repo "$REPO_ROOT" --receipt "$RUN_ROOT/signed-receipt.json" \
  --ipa "$IPA_PATH" --output "$RUN_ROOT/upload-input-receipt.json" > "$RUN_ROOT/upload-input-check.log"
xcrun altool --upload-app -f "$IPA_PATH" --api-key "$ASC_KEY_ID" \
  --api-issuer "$ASC_ISSUER_ID" 2>&1 | tee "$UPLOAD_LOG"
node "$BUILD_NUMBER_SCRIPT" record --upload-log "$UPLOAD_LOG" --ipa "$IPA_PATH"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$REPO_ROOT/apps/ios/MagicMobile/Info.plist")"
"$DISTRIBUTION_SCRIPT" --build-number "$BUILD_NUMBER" --release-root "$RUN_ROOT"
echo "Upload, processing, Internal + External distribution, and Beta App Review submission completed. Phone gameplay is not verified by this script."
echo "Keep the archive, dSYM, paired engine and receipts in $RUN_ROOT."
