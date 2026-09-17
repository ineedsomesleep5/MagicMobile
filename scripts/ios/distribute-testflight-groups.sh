#!/usr/bin/env bash
# Complete TestFlight distribution only after Apple's processing is complete.
set -euo pipefail
umask 077

APP_ID="com.calebfeliciano.magicmobile"
BUILD_NUMBER=""
RELEASE_ROOT=""
EXTERNAL_GROUP_ID="${TESTFLIGHT_EXTERNAL_GROUP_ID:-72b71a7a-bf62-43b5-8eda-b12a62e5c3eb}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-number) BUILD_NUMBER="$2"; shift 2 ;;
    --release-root) RELEASE_ROOT="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$BUILD_NUMBER" || -z "$RELEASE_ROOT" ]]; then
  echo "Usage: $0 --build-number NUMBER --release-root DIRECTORY" >&2; exit 2
fi
if [[ ! -d "$RELEASE_ROOT" ]]; then
  echo "Release evidence directory does not exist: $RELEASE_ROOT" >&2; exit 2
fi
command -v asc >/dev/null || { echo "Required desktop tool missing: asc" >&2; exit 2; }

# An external group assignment also keeps every Internal group enabled by default.
# Internal access is deliberately retained: both audiences are the release contract.
asc builds wait --app "$APP_ID" --build-number "$BUILD_NUMBER" --platform IOS \
  --timeout 30m --poll-interval 30s --output json > "$RELEASE_ROOT/apple-processing.json"
asc builds add-groups --app "$APP_ID" --build-number "$BUILD_NUMBER" --platform IOS \
  --group "$EXTERNAL_GROUP_ID" --submit --confirm --output json > "$RELEASE_ROOT/testflight-distribution.json"
BUILD_ID="$(asc builds list --app "$APP_ID" --build-number "$BUILD_NUMBER" --platform IOS --output json | \
  /usr/bin/python3 -c 'import json, sys; data=json.load(sys.stdin).get("data", []); print(data[0]["id"] if len(data) == 1 else "")')"
if [[ -z "$BUILD_ID" ]]; then
  echo "Apple processed build $BUILD_NUMBER but did not return one unique build id for membership verification." >&2; exit 1
fi
asc builds groups list --build-id "$BUILD_ID" --output json > "$RELEASE_ROOT/testflight-groups.json"
asc builds beta-app-review-submission view --build-id "$BUILD_ID" --output json > "$RELEASE_ROOT/beta-app-review.json"
echo "TestFlight build $BUILD_NUMBER is assigned to Internal and External groups; Beta App Review submission recorded."
