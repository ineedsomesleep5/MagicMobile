# TestFlight 0.1.1 (65): voice chat at online tables

Uploaded October 27, 2026 and distributed to Internal and External testers (both `IN_BETA_TESTING`). Released with
Android build 43 (`release/RELEASE_ANDROID_0.1.1_BUILD43.md`) and the web deploy `dpl_F2mkVtEy96juVChN9woevMCbrkex`, from
PR #250.

## What changed (PR #250)
- **Voice chat** at online tables with people (docs/VOICE_CHAT.md), on Agora: a mic by your portrait joins voice and then
  turns your microphone off and on; a green ring shows who is talking; a mic badge on opponents in voice; Mute Voice on a
  player card; Leave Voice Chat in the gear menu. Tokens come from the `agora-token` edge function; the server's
  `voiceChat` switch shows the mic.
- Agora `AgoraAudio_iOS` 4.6.4 (`RtcBasic`), about 13 MB; a microphone permission prompt on the first tap.

## Release
- **Source:** `codex/ios-build-65` in `~/Documents/MagicMobile-release-40` = main at `888adeab` (PR #250 merged) + merge of
  `codex/ios-build-64` (calibration tooling and `PROTOCOL.md` at engine release C) + `prepare`, project generated from
  `native-engine.yml`. Never merge that branch.
- **Engine:** release C, unchanged; preflight `ios-fast` 14/14, `equivalent-source` (84 s).
- **Run:** `ios-0.1.1-65`, fingerprint `3cfb614e…`, delivery `3dee27b5…`, VALID about 5 minutes after upload, then
  distributed to both groups.

## Verification
- `VoiceChatRulesTests` and `AppConfigTests`, the app compiles for the simulator with Agora, no board expression over the
  200 ms type-check budget; Android `VoiceChatRulesTest` and the app compile; web 356 tests (including the voice room
  against a stand-in for Agora); CI on #250.
- **Live server:** with `AGORA_APP_CERTIFICATE` set, the function gave a guest an AccessToken2 and the Agora web SDK joined
  a test channel with it.
- **Board:** the mic, the talking ring and the badge seen on the web Arena board (a local preview with voice faked on).
- **Not verified on a phone:** two phones hearing each other, the game's sounds while voice is on, the mic's spot on the
  iPhone board.
