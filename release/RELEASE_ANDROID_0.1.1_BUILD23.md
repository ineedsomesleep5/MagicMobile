# Android 0.1.1 build 23: fair, friendlier ranked and smart pass v2 (Release 1 of the improvement program)

Published October 15, 2026 as [android-v0.1.1-build.23](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.23),
together with iPhone build 39 (`release/RELEASE_0.1.1_BUILD39.md`), on the same XMage `dac400b` engine as build 19.

## Scope
Same features as iPhone build 39: the server keeps ranked score, ladder option B, server-side rank history, Bronze
faces the three gentlest precons, smart pass v2 (full-control hold, auto-pass log lines), photo import and Google ML Kit
removed, unused art trimmed, and Android builds through the Gradle 8.14.3 wrapper.

## Signed artifact
- **Source:** `1e4be77` (`codex/android-build-23`): main `c89bafc` plus versionCode `2026101501` and `RELEASE_BUILD` 23.
  That branch also restores `packages/ondevice-engine/docs/PROTOCOL.md` to `0546f91` (docs only) for the native guard.
  This records branch doesn't carry that.
- **APK SHA-256:** `d9b2ff515c9b5a5990e1ac683dfff07cf44c5720b10c538e83fb7f1a86f00164` (144786686 bytes, down from
  154446383 in build 22). The public download re-hashes to the same value.
- **Signer:** SHA-256 `b10ca2cd…d4bb`, unchanged, so it updates in place.
- **Native engine:** unchanged (`android-build19-engine-0546f91`).

## Verification
- **`build_release.sh`** (now through `apps/android/gradlew`): the native guard, contract assertions, release lint,
  alignment and apksigner.
- **Emulator (API 35, headless):** an in-place update `2026101401` → `2026101501`, and 5/5 packaged-engine device tests.
  Build 22 had 6; the photo-import device test was removed with the feature in #159.
- **Not verified:** a physical phone.
