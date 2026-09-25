# Android 0.1.1 build 8

## Scope

- Caleb resumed Android on September 24, 2026. Build 8 is the parity port described in
  [ANDROID_PARITY.md](ANDROID_PARITY.md): the iPhone game board in portrait and landscape,
  Deck Studio, the Downloads screen, recorded audio and the Sound Lab, and tables that
  iPhone and Android players share through the relay in `services/table-relay`.
- iPhone players can join these tables only from the next iPhone TestFlight build.
  Build 17 (approved) predates the relay client.
- Android-only release: no iOS upload, engine update or server change was made.

## Signed artifact

- App source: `2e4d173575a17bcad61b158db490540872666c25` (branch `codex/android-parity`).
- Version `0.1.1`, versionCode `2026092501`, and the unchanged package
  `com.calebfeliciano.magicmobile.android`.
- APK SHA-256: `0530418df22719d0a163e4a50327a9d0d0bcc407f5b7cd2f8881f9ed429e1532`
  (222,687,450 bytes).
- Instrumentation APK SHA-256:
  `23b85b994cbb1e82622a659a4560feabf3cea902f614df2aeef657ee4c16c7c8`.
- The signer SHA-256 is unchanged:
  `b10ca2cdf5d184c2b264b56dae888d950f3ab52a40551b7f8eb634de0316d4bb` (APK Signature
  Scheme v2).
- Native engine:
  - `libmmengine.so` `10484c190e4788759546aca726bc9eea7ae8418b912b2aa0d1b3ae2236716f97`,
    built from `2c324825a8f6cff1a0a40ac38055dfe93683b960`.
  - XMage stays pinned to `4825513287ba6c42c32fd205d227f4a5fc44c2f3`.
  - The engine source matches iPhone build 17's; only `docs/PROTOCOL.md` differs.

## Verification

- `scripts/android/build_release.sh` passed:
  - the native source/input guard
  - the core contracts: 136 protocol/deck/privacy, 42 auto-yield, 71 Deck Studio,
    14 provider and 20 role/probability assertions
  - `:app:assembleRelease`, `:app:assembleReleaseAndroidTest` and `:app:lintRelease`
  - 16 KiB zipalign and apksigner verification
- The JVM tests (`:core:test`, `:app:testDebugUnitTest`) pass. They include the iOS/Android
  parity goldens (13 real engine fixtures, 12 synthetic prompts) and 37 Deck Studio tests
  ported from iOS.
- Emulator (API 35, arm64):
  - The release APK updated the existing build 7 install in place, with no uninstall.
    The first install time is unchanged.
  - All ten packaged-engine instrumentation tests passed in 38.2 s. They include completed
    Commander play, repeated engine reopen, deck persistence, offline OCR and
    disabled-online readiness.
  - A manual pass on the release app covered:
    - the menu and the Deck Studio library
    - hosting a table on the deployed relay, then leaving it
    - an AI game: starting player, opening hand, first turn, concede, result screen,
      and back to the menu
  - No crash was logged.
- Cross-play: an Android host (emulator) and an iPhone guest (simulator) played a real
  match through the deployed relay during development. Release builds are not minified,
  so this is the same code. The relay's three integration tests passed against the
  deployed Worker on September 25.
- Not verified:
  - a physical Android phone
  - an iPhone hosting Android guests on real hardware (the simulator has no engine)

## Known differences from iPhone

- Font glyph shapes: licensed stand-ins with matched widths.
- Tables instead of Game Center.
- Before the first turn, both apps show "Waiting on Waiting" in the top bar.

## Release

- [android-v0.1.1-build.8](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.8)
  targets `2e4d173` and includes `SHA256SUMS`.
- The download site links build 8 once this branch merges and Vercel deploys it.
