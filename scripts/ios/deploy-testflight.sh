#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-$REPO_ROOT/apps/ios/MagicMobileiOS.xcodeproj}"
SCHEME="${SCHEME:-MagicMobile}"
CONFIGURATION="${CONFIGURATION:-Release}"
BUNDLE_ID="${BUNDLE_ID:-com.calebfeliciano.magicmobile}"
TEAM_ID="${TEAM_ID:-82HPAY85M8}"
EXPORT_OPTIONS="${EXPORT_OPTIONS:-$REPO_ROOT/release/testflight/ExportOptions.plist}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$REPO_ROOT/build_output/testflight}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$OUTPUT_ROOT/MagicMobile.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$OUTPUT_ROOT/export}"
IPA_PATH="$EXPORT_PATH/MagicMobile.ipa"
UPLOAD_LOG="$OUTPUT_ROOT/altool-upload.log"
BUILD_NUMBER_SCRIPT="$REPO_ROOT/scripts/ios/testflight-build-number.mjs"

ASC_KEY_ID="${ASC_KEY_ID:-Z54BVK456U}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-0e7ba65b-f006-4c46-bb4d-dddf7303de16}"
ASC_KEY_PATH="${ASC_KEY_PATH:-/Users/calebfeliciano/.appstoreconnect/private_keys/AuthKey_Z54BVK456U.p8}"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if [[ ! -f "$ASC_KEY_PATH" ]]; then
  echo "App Store Connect API key file missing: $ASC_KEY_PATH" >&2
  exit 2
fi

if [[ "${PREPARE_TESTFLIGHT_BUILD_NUMBER:-1}" == "1" && -f "$BUILD_NUMBER_SCRIPT" ]]; then
  echo "Preparing next tracked TestFlight build number..."
  node "$BUILD_NUMBER_SCRIPT" prepare
fi

echo "Preparing TestFlight upload for $BUNDLE_ID"
echo "Version: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$REPO_ROOT/apps/ios/MagicMobile/Info.plist") ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$REPO_ROOT/apps/ios/MagicMobile/Info.plist"))"
echo "Project: $PROJECT_PATH"
echo "Scheme: $SCHEME"
echo "Configuration: $CONFIGURATION"
echo "Team: $TEAM_ID"
echo "Archive: $ARCHIVE_PATH"

rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"
mkdir -p "$OUTPUT_ROOT" "$EXPORT_PATH"

echo "Archiving..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  clean archive

echo "Exporting IPA..."
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

if [[ ! -f "$IPA_PATH" ]]; then
  echo "IPA was not created at $IPA_PATH" >&2
  exit 3
fi

echo "Validating IPA with App Store Connect..."
xcrun altool --validate-app "$IPA_PATH" \
  --api-key "$ASC_KEY_ID" \
  --api-issuer "$ASC_ISSUER_ID"

echo "Uploading IPA to App Store Connect..."
rm -f "$UPLOAD_LOG"
xcrun altool --upload-app -f "$IPA_PATH" \
  --api-key "$ASC_KEY_ID" \
  --api-issuer "$ASC_ISSUER_ID" 2>&1 | tee "$UPLOAD_LOG"

if [[ -f "$BUILD_NUMBER_SCRIPT" ]]; then
  node "$BUILD_NUMBER_SCRIPT" record --upload-log "$UPLOAD_LOG" --ipa "$IPA_PATH"
fi

echo "Uploaded $IPA_PATH to App Store Connect."
