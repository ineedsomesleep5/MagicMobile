# Android 0.1.1 build 12: save on exit, smaller engine, How to play

## Scope
The same changes as iPhone build 21 (`release/RELEASE_0.1.1_BUILD21.md`), plus two Android-only fixes:
- the turn banner can no longer get stuck ([#85](https://github.com/ineedsomesleep5/MagicMobile/pull/85));
- a 12 s budget for the leave-the-app save ([#87](https://github.com/ineedsomesleep5/MagicMobile/pull/87)).

## Signed artifact
- **Source:** `0dbbf41af97c10a30b87230d05a33193a760e0f3` (`codex/android-build12`), which is `main` at #88 (`67c9005`) plus versionCode `2026092703` and `RELEASE_BUILD` 12.
- **APK SHA-256:** `248890c07eb3977ed04306f2fb41d1c4b1983d5d29eeedb7cb660c430385c6da` (138,653,023 bytes, down from 228.5 MB).
- **Signer:** `b10ca2cdf5d184c2b264b56dae888d950f3ab52a40551b7f8eb634de0316d4bb`, unchanged.
- **Native engine:**
  - `libmmengine.so` from `ad2e8c3fd434a691514c1c4e2517293e0d60628c` (run [36353994622](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/36353994622)), 380.7 MB stripped, down from 795.5 MB.
  - The relocations are packed, and the unstripped copy is in the run's `android-native-symbols` artifact.
  - `verify_native.py` verified it, and a local copy is in `~/Documents/MagicMobile-releases/engines/android-build12-engine-ad2e8c3/`.

## Verification
- **`build_release.sh`:** the native guard, 283 contract assertions, release lint, 16 KiB alignment and apksigner.
- **Emulator (API 35, arm64, `-gpu host`):**
  - An in-place update over build 11; the first install date is unchanged.
  - 6/6 packaged-engine tests, including `packagedEngineSavesOnRequestAndRestoresThePriorityDecision`, with no assumption skips.
  - **App flow on the pre-tutorial build 12 candidate:**
    1. Start a game, choose to start, keep the hand, then priority.
    2. Home: "Game saved on leaving: 163,566 bytes in 5,290 ms".
    3. Force-stop and relaunch: "Resume your game? Turn 1 against AI 1 · saved just now".
    4. Resume restored the board at MAIN 1.
  - **Final APK:** the How to play walkthrough opens on first launch.
- **Not verified:**
  - a physical Android phone;
  - the full app resume flow on the final APK (the app flow above ran on the pre-tutorial candidate; the engine is the same);
  - checkpoint write time on a phone.

## Release
- [android-v0.1.1-build.12](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.12) targets `0dbbf41`, with `SHA256SUMS`, and is marked latest.
- The public download was hashed and matches the tested APK.
