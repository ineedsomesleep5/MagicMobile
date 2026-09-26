# Android 0.1.1 build 9

## Scope

- The same changes as iPhone build 18 (`release/RELEASE_0.1.1_BUILD18.md`), from
  [PR #51](https://github.com/ineedsomesleep5/MagicMobile/pull/51):
  - follow turns and the spectator seat
  - token-copy frames, the fitted inspector and the ability banner
  - combat keyword badges, the first-strike beat and log reasons
  - clipped-row "+N" badges, and the fan-content notice with the Scryfall credit
  - guest retry and host revision notices, and local crash and hang reports (ApplicationExitInfo)
  - removal of the unreachable build 7 UI (#50)
- iPhone players join these tables from iPhone build 18.

## Signed artifact

- App source: `35b3cf85ea0c90b0b32dd0b2833f8ea7a5074cdc` (`codex/build18-integration`, contained
  in `main` through #51).
- Version `0.1.1`, versionCode `2026092601`, `RELEASE_BUILD` 9, and the unchanged package
  `com.calebfeliciano.magicmobile.android`.
- APK SHA-256: `5b9320f25ff1950bd01058b45c867bc65692b735ccc85aa07485d2539d1a10ab`
  (222,354,018 bytes).
- Instrumentation APK SHA-256:
  `d296551b6d4eef4433dd138c737e240866bf05b647f0c403e81e67c1de25e3eb`.
- The signer SHA-256 is unchanged:
  `b10ca2cdf5d184c2b264b56dae888d950f3ab52a40551b7f8eb634de0316d4bb` (APK Signature
  Scheme v2).
- The native engine is the same as build 8's: `libmmengine.so` from
  `2c324825a8f6cff1a0a40ac38055dfe93683b960`, XMage
  `4825513287ba6c42c32fd205d227f4a5fc44c2f3`.

## Verification

- `scripts/android/build_release.sh` passed:
  - the native source/input guard
  - 283 core contract assertions (136 protocol/deck/privacy, 42 auto-yield, 71 Deck Studio,
    14 provider and 20 role)
  - `:app:assembleRelease`, `:app:assembleReleaseAndroidTest` and `:app:lintRelease`
  - 16 KiB zipalign and apksigner verification
- JVM tests on the same source: `:core:test` (91) and `:app:testDebugUnitTest` (34), including
  the iOS/Android parity goldens and the shared focus, spectator and combat cases.
- Emulator (API 35, arm64):
  - The APK updated build 8 in place. The first install time is unchanged, so data was kept.
  - All 5 packaged-engine instrumentation tests passed, including completed Commander play and
    repeated engine reopen. #50 removed the three test classes for the deleted build 7 UI.
- Not verified:
  - a physical Android phone
  - a live Android-host / iPhone-guest match on phones: this 8 GB Mac can't run the emulator
    and a simulator together

## Release

- [android-v0.1.1-build.9](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.9)
  targets `35b3cf8`, with `SHA256SUMS`.
- The public download was streamed without authentication and hashed: it matches the tested
  APK and GitHub's digest.
- The download site (https://magicmobile-downloads.vercel.app) links build 9, via #52.
