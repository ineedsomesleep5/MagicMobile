#!/usr/bin/env bash
# Build an update-compatible, native-linked APK. Signing material stays outside git.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
: "${ANDROID_HOME:?Set ANDROID_HOME to the installed Android SDK}"
: "${JAVA_HOME:?Set JAVA_HOME to JDK 17}"
: "${MM_ANDROID_KEYSTORE:?Set MM_ANDROID_KEYSTORE to the private release keystore}"
: "${MM_ANDROID_PASSWORD_FILE:?Set MM_ANDROID_PASSWORD_FILE to the private password file}"
: "${MM_ANDROID_VERSION_CODE:?Set a new increasing Android version code}"
: "${MM_ANDROID_VERSION_NAME:?Set the user-visible version name}"
test -f "$MM_ANDROID_KEYSTORE"
test -f "$MM_ANDROID_PASSWORD_FILE"
export MM_ANDROID_STORE_PASSWORD
MM_ANDROID_STORE_PASSWORD="$(< "$MM_ANDROID_PASSWORD_FILE")"
export MM_ANDROID_KEY_PASSWORD="$MM_ANDROID_STORE_PASSWORD"
python3 "$ROOT/scripts/android/verify_native.py" "$ROOT"
gradle -p "$ROOT/apps/android" --no-daemon -PwithNative=true \
  -PandroidTestBuildType=release \
  -PandroidVersionCode="$MM_ANDROID_VERSION_CODE" -PandroidVersionName="$MM_ANDROID_VERSION_NAME" \
  :core:contractChecks :core:deckStudioChecks :core:providerChecks :core:insightChecks :app:assembleRelease :app:assembleReleaseAndroidTest :app:lintRelease
APK="$ROOT/apps/android/app/build/outputs/apk/release/app-release.apk"
"$ANDROID_HOME/build-tools/35.0.0/zipalign" -c -P 16 4 "$APK"
"$ANDROID_HOME/build-tools/35.0.0/apksigner" verify --verbose --print-certs "$APK"
echo "Signed native APK: $APK"
