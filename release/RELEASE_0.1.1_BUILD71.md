# TestFlight 0.1.1 (71): engine release D, pay for Propaganda when it isn't your priority

Uploaded October 28, 2026 and distributed to Internal and External testers (both `IN_BETA_TESTING`). Released with
Android build 49 (`release/RELEASE_ANDROID_0.1.1_BUILD49.md`) and the web engine deploy `dpl_CdYBXNU1htkUYQkXVygh52h9jZxF`
(web engine identity `web-1:sha256:baf510e5…`), from PR #264.

## What changed (engine release D, PR #264)
- **Paying while someone else holds priority:** Propaganda's attack tax (a TestFlight report on October 28: "won't let me
  tap mana to pay propaganda cost"), Ghostly Prison, Rhystic Study, ward and Mana Leak now offer the payer's mana sources.
  Upstream XMage lists playables for the priority player only, and none at all while attackers are declared; the
  projector now takes the question being published and, for a mana payment, lists the paying seat's activatable mana
  abilities. Opponents keep upstream's list.
- `ccd1365a` (from the web engine, 2026-10-20): an AI simulation's ended game copy no longer closes the live player's
  input channel ("Too many errors" after a block decision).
- Saves from older builds are refused: new engine identity
  `sha256:7c241814528f8ff01504ea277204144913ed700ec103c43a68f9ccdfe0ef1394`, registered in `ranked_engine_builds` before
  upload.

## Release
- **Engine:** candidate `a98b4b63` (engine package identical to `1674f060`): gate `magicmobile-issue4-nonsimulator.yml`
  run 40793445939 (run 40792590121 failed on an ArenaBoardModel.swift expression Xcode 26.6 could not type-check in
  time, rewritten as a loop); far-calls run 40797503215. Staged with `controller.py stage-native`; the release-C engine
  is kept in `packages/ondevice-engine/build/NativeEngine-build70-releaseC` in the release worktree.
- **Source:** `codex/ios-build-71` in `~/Documents/MagicMobile-release-40` = `codex/ios-build-70` + merge of the
  candidate + the engine package set to the candidate's + `prepare`, project generated from `native-engine.yml`.
  Never merge that branch.
- **Run:** `ios-0.1.1-71`, fingerprint `aa5c37b9…`, delivery `a0b9075e…`, VALID about 12 minutes after upload, then
  distributed to both groups. Preflight `ios-fast` passed, `equivalent-source`.

## Verification
- `RealStackResponseTests attack-tax` and the suite, RealPortraitProjectionTests, RealQueryTests, RealControlledTurnTests
  and RealControlPrivacyTests on a local JVM build of the candidate; a replay of an attack into Propaganda on the real
  engine before (nothing to tap) and after (the untapped lands offered, fewer as each is tapped); CI on #264.
- Android 49 on the same engine source: 6/6 emulator device tests, game record engine identity `7c241814…`.
- **Not verified on a phone:** a live Propaganda payment.
