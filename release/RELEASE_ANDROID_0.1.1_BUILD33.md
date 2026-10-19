# Android 0.1.1 build 33: steal pull, longer dice throw, v2 tavern room, ranked roll

Published October 19, 2026 as a test prerelease,
[android-v0.1.1-build.33](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.33), together
with iPhone build 50 (`release/RELEASE_0.1.1_BUILD50.md`). Build 31 stays the latest public release. The app changes
match build 50: #212 (Ranked always rolls) and #213 (steal pull, longer dice throw, v2 tavern room).

Build 32 (test prerelease, October 19, versionCode `2026101901`, APK `98c08d14…`) added the card moments (#209) and the
art cleanup (#210); it had no record of its own.

## Signed artifact
- **Source:** `789be556` (`codex/android-build-33`): main after #212, `claude/steal-dice-room` (#213), and versionCode
  `2026101902` with `RELEASE_BUILD` 33.
- **Native engine:** unchanged from build 31 (release C, `21a82eb7`,
  `~/Documents/MagicMobile-releases/engines/android-build31-engine-21a82eb/artifact`).
- **APK SHA-256:** `0c171ad17927bee1d18fe862af4f8a4ae32c2059237379ce08370b0ce373e217` (133966864 bytes).
- **Signer:** unchanged, so it updates in place.

## Verification
- **`build_release.sh`:** the native guard, contract assertions, release lint, alignment and apksigner.
- **Emulator (API 35, headless):** in-place update `2026101901` → `2026101902`; 6/6 packaged-engine device tests,
  including a 16-turn native Commander game and a seeded game record (52 entries by turn 3, engine build
  `sha256:9f06efbe…906f`). The menu screenshot shows the v2 tavern room.
- JVM: BoardEventTimelineTest, StartingRollDiceTest and RankedParityTest.
- **Not verified:** the steal and the dice on the emulator or a physical phone.
