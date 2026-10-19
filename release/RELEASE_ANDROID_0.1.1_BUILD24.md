# Android 0.1.1 build 24: the engine release (Release 2 of the improvement program)

Published October 15, 2026 as [android-v0.1.1-build.24](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.24),
together with iPhone build 40 (`release/RELEASE_0.1.1_BUILD40.md`), on a new native engine built from main `160e250`.
Release 3 (the game record) was folded into this release, so there is no Android build 25 for it.

## Scope (docs/GAME_IMPROVEMENT_PROGRAM.md, Phases 2 to 5)
- C2 engine release A (#163): stack controllers and a response signal; smart pass lets your own spells and triggers
  resolve and stops only for a play that answers (#175, Settings > Stop for My Own Spells).
- AI difficulty by tier: C2's depths, C3's mistake rates (#176: Bronze and Silver 15%, Gold 10%), C4's expert combat
  planner from Diamond (#170, integrated with the record in #178).
- C4's table-driven card factory: native code 202.0 → 191.1 MB, `libmmengine.so` 381.6 → 371.2 MB.
- C5's engine game record (#171) and ranked AI wins checked against it on the server (#177; migration
  `ranked_ai_records` applied live, this engine's build `sha256:225ee7de…9869` registered in `ranked_engine_builds`).

## Signed artifact
- **Source:** `94fbfe3` (`codex/android-build-24`): main `160e250` plus versionCode `2026101502` and `RELEASE_BUILD` 24.
  The engine package is identical to the engine's source commit, so no restore was needed for the native guard.
- **Native engine:** `magicmobile-android.yml` run 38771678260 on `160e250` (with `native_reports`), artifact
  `android-full-native-160e250…`, kept in `~/Documents/MagicMobile-releases/engines/android-build24-engine-160e250`.
  The library contains the registered engine build identity.
- **APK SHA-256:** `c5004061c13db50db4830b386406ccf60c6d26e3e1a77b066f0ff63ff5567b02` (143094706 bytes, down from
  144786686 in build 23). The public download re-hashes to the same value.
- **Signer:** unchanged, so it updates in place.

## Verification
- **CI on main:** the real-engine JVM suite, including C5's record and replay tests and two expert-AI record scenarios
  (skill 6 vs 6 over 21 turns, a human against skill 5), each replayed to the recorded end in a fresh JVM.
- **`build_release.sh`:** the native guard, contract assertions, release lint, alignment and apksigner.
- **Emulator (API 35, headless):** an in-place update `2026101501` → `2026101502`, 5/5 packaged-engine device tests, and
  the main menu reached in 2.3 s (the emulator's own system apps showed "not responding" under load on this 8 GB Mac).
- **Not verified:** a physical phone, a ranked AI game against the live server, and the game record on a native engine
  (the device tests do not fetch it).
