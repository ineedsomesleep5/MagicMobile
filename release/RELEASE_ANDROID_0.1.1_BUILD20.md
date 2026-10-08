# Android 0.1.1 build 20: keep your profile with Google sign-in

Published October 8, 2026 as [android-v0.1.1-build.20](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.20),
together with iPhone build 35 (`release/RELEASE_0.1.1_BUILD35.md`), on the same XMage `dac400b` engine as build 19.

## Scope
From PR [#129](https://github.com/ineedsomesleep5/MagicMobile/pull/129):
- **Keep your profile** card on the Profile screen: Continue with Google through Credential Manager
  (`GetSignInWithGoogleOption`, the Web client ID as server client ID, a hashed nonce).
  - Signed in, the card shows the account and Sign Out.
  - Apple sign-in is not offered on Android.
- **Server:** the first sign-in links the identity to the anonymous account, so the name, friends and rank stay. An
  account that already has a profile switches the phone to it. Sign out starts a fresh anonymous profile.
- **Dependencies:** `androidx.credentials` 1.3.0, `credentials-play-services-auth` 1.3.0 and `googleid` 1.1.1, with an R8
  keep rule for the Play Services provider.

## Signed artifact
- **Source:** `a03384e` (`codex/android-build-20`), which is `codex/ios-build-35` at `6e20ea6` plus versionCode
  `2026100801` and `RELEASE_BUILD` 20.
- **APK SHA-256:** `c1a52caac21b57e5ff2251eac3ea567c095961ddf324a6d739bc48aa92d3780f` (154163360 bytes). The public
  download re-hashes to the same value.
- **Signer:** SHA-1 `e81f749d…` (the release key, unchanged), so it updates in place.
- **Native engine:** unchanged from build 19 (`android-build19-engine-0546f91`). `packages/ondevice-engine` is identical
  between `0546f91` and the release source.

## Verification
- **`build_release.sh`:** the native guard, contract assertions, release lint, alignment and apksigner.
- **JVM:**
  - `:core:test`: 222 tests, 0 failures;
  - `LinkedIdentityTest` 1/1 (the shared `chat-cases.json` fixture);
  - `:app:compileDebugKotlin` succeeded.
- **Emulator (API 35, headless):**
  - an in-place update, `2026100703` → `2026100801`;
  - 6/6 packaged-engine device tests;
  - the release build's menu.
- **Not verified:**
  - a real Google sign-in. The Android OAuth client carries the release certificate, so only this signed build can
    sign in.
  - a physical phone.
