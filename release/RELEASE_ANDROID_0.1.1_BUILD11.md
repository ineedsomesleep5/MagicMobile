# Android 0.1.1 build 11: resume solo games

## Scope

- **Save/resume for games against the AI.** The engine checkpoints the match at each human priority decision. After the app process dies (Android closing it, or a force-quit), a relaunch within 10 minutes offers **Resume your game?** with Resume and Abandon.
  - The engine and app code were already in `main`: #63 (the app side), #64 (the engine), #68 (native metadata without serializable lambdas) and #73 (the complete native metadata).
  - The app side and 10-minute rules are the same as iOS (`parity/resume-cases.json`).
- Everything else matches build 10 (`release/RELEASE_ANDROID_0.1.1_BUILD10.md`).

## Signed artifact

- **Source:** `321084aade1a1131478bfa329f952fd06e207503` (`codex/android-build11`), which is `main` at #73 (`79de39c`) plus versionCode `2026092702` and `RELEASE_BUILD` 11.
- **Version:** `0.1.1`, versionCode `2026092702`, unchanged package `com.calebfeliciano.magicmobile.android`.
- **APK SHA-256:** `fcb8e5ee0e3053af47afbacdd9448df9b29568c508f1124f70b4a1c67ff3850a`.
- **Instrumentation APK SHA-256:** `412738dba8028afab93b403b6c811734050e2c29563102e02fb543af22a9241c`.
- **Signer SHA-256:** `b10ca2cdf5d184c2b264b56dae888d950f3ab52a40551b7f8eb634de0316d4bb`, unchanged.
- **Native engine (new):**
  - `libmmengine.so` from `79de39c1ee847176afa8f325c43b77294d61240a`: run [36310535888](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/36310535888), artifact `android-full-native-79de39c…`.
  - XMage is at `4825513287ba6c42c32fd205d227f4a5fc44c2f3` with the reviewed checkpoint patches from `prepare_upstream.py`.
  - The serialization metadata registers 50,684 names, of which 1,957 are array types. The builder heap peaked near 9.6 GB of the 10 GB limit.
  - `verify_native.py` verified the exact native files and equivalent source.

## Verification

- **`scripts/android/build_release.sh` passed:**
  - the native guard
  - 283 core contract assertions
  - release compilation and lint
  - 16 KiB alignment and apksigner
- **Real-engine JVM suite:**
  - fresh-process restores matched the saved game exactly, including tokens, exile, copies, a control change and the stack
  - rejection cases
  - RNG continuity
  - a check that every class the checkpoints write or read (about 930) is listed in the exported native metadata
- **Emulator (API 35, arm64):**
  - The APK updated build 10 in place; the first install time is unchanged.
  - All 6 packaged-engine device tests passed. `NativeCheckpointTest` ran with no assumption skip: the packaged engine reported `saveResume: true`, checkpointed a priority decision and restored it with the same decision.
  - **App-level resume**, done by the #73 delegate on the same engine code (`e83eb15`): start a solo game, press Home, `am force-stop`, relaunch.
    - "Resume your game?" appeared, for example "Turn 2 against AI 1 · saved 7 min ago".
    - Resume restored the board, including the AI's Wayfarer's Bauble on the stack, and play continued.
    - This was done twice.
- **Not verified:**
  - a physical Android phone
  - long games with large boards in the native engine
  - checkpoint write time on a phone

## Release

- [android-v0.1.1-build.11](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.11) targets `321084a`, with `SHA256SUMS`, and is marked latest.
- The public download was streamed without authentication and hashed. It matches the tested APK.
- The download site links build 11.
