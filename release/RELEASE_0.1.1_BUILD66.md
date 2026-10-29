# TestFlight 0.1.1 (66): the mic under the gear, Push to Talk

Uploaded October 27, 2026 and distributed to Internal and External testers (both `IN_BETA_TESTING`). Released with
Android build 44 (`release/RELEASE_ANDROID_0.1.1_BUILD44.md`) and the web deploy `dpl_3ad5zfUU6PBm8N1YRdjSSkPTyLjx`, from
PR #252.

## What changed (PR #252)
- **The mic under the gear**, top right. In build 65 it sat by your portrait and was half off the iPhone's left edge.
- **Push to Talk** in the audio settings (Options → Audio and Game Settings), off by default: voice joins with the
  microphone off, and you hold the mic to talk. The web also takes a talk key (V by default, rebindable).
- **Android:** a drag from the spread hand carries the card under the finger (it carried one about two places right).

## Release
- **Source:** `codex/ios-build-66` in `~/Documents/MagicMobile-release-40` = PR #252's head `4732e33e` (merged as
  `4b595376`) + merge of `codex/ios-build-65` (calibration tooling and `PROTOCOL.md` at engine release C) + `prepare`,
  project generated from `native-engine.yml`. Never merge that branch.
- **Engine:** release C, unchanged; preflight `ios-fast` 14/14, `equivalent-source` (75 s).
- **Run:** `ios-0.1.1-66`, fingerprint `98bc7f61…`, delivery `d8d459cd…`, VALID within minutes of upload, then
  distributed to both groups.

## Verification
- CI on #252 (swift, app, real-jvm, web); web 358 tests including push to talk and the talk key; the iPhone simulator
  build with no board expression over the 200 ms type-check budget.
- **Board:** the mic under the gear seen on the iPhone simulator, the Android emulator and the web board (voice faked on
  in a local preview); Push to Talk in Android's game settings and the web's Options with a rebound key.
- **Not verified on a phone:** push to talk with real audio, two phones hearing each other.
