# Android 0.1.1 build 43: voice chat at online tables

Published October 27, 2026 as the latest public release,
[android-v0.1.1-build.43](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.43), from
PR #250 (TestFlight 65 from the same source on `codex/ios-build-65`).

## Signed artifact
- **Source:** `codex/android-build-43` (`2510a382`) = main at `888adeab` (PR #250 merged) merged with
  `codex/android-build-42` (calibration tooling and `PROTOCOL.md` at engine release C), versionCode `2026102702`,
  `RELEASE_BUILD` 43.
- **Native engine:** unchanged from build 31 (release C, `21a82eb7`).
- **APK SHA-256:** `2243fa8c5b98ce0cad0085df5b5f9ae7c35a9be1472d82cc2d5e20fcc1210027` (144085540 bytes; Agora's
  `voice-rtc-basic` adds about 7.6 MB), with a copy in `~/Documents/MagicMobile-releases/android-43/`. The public download
  was re-hashed and matches.

## What changed
Same as TestFlight 65 (`release/RELEASE_0.1.1_BUILD65.md`): voice chat at online tables (mic by your portrait, talking
ring, mic badges, Mute Voice, Leave Voice Chat), on Agora 4.6.4 with `RECORD_AUDIO` asked on the first tap.

## Verification
- **`build_release.sh`:** native guard, contracts, release lint, alignment and apksigner.
- **Emulator (API 35, headless):** in-place update `2026102701` → `2026102702`; 6/6 packaged-engine device tests,
  including a 17-turn native Commander game and a seeded game record.
- **Unit:** `VoiceChatRulesTest` and `AppConfigTest`; CI on #250.
- **The Mac:** the guarded script from build 42 (idle wait, 1.5 GB Kotlin daemon, Gradle stopped before a 1.5 GB emulator,
  critical-pressure guard); pressure never went critical.
- **Not verified on a phone:** voice between two devices, Bluetooth headsets (no `BLUETOOTH_CONNECT`).
