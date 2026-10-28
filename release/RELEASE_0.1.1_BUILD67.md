# TestFlight 0.1.1 (67): your own card art, Gogo copies your triggers, chosen art without the swap

Uploaded October 27, 2026 and distributed to Internal and External testers (both `IN_BETA_TESTING`). Released with
Android build 45 (`release/RELEASE_ANDROID_0.1.1_BUILD45.md`) and the web deploy `dpl_2ArbW8nxMziUJCjBDzBqF9ozhVbV`, from
PR #255 (which carries #247).

## What changed (PR #255)
- **Your own card art:** Use my own picture in Deck Studio's artwork picker (web: the card's inspect). The picture is
  drawn over the real card's art box wherever the card shows, on this device only; opponents see the usual art.
- **Smart Auto-Pass and Gogo:** your own trigger now stops when a non-spell ability of yours can answer it (Gogo, Master of
  Mimicry copying Zur's attack trigger); a counterspell in hand still lets it resolve. iOS, Android and web.
- **Chosen art without the swap (iOS):** a chosen printing fetched online is saved like default art, the card waits for it
  instead of flashing the default art, and the playing deck's printings are prefetched. The web board now draws the art
  chosen in Deck Studio too.
- **The starting roll** says "You roll" on your roll (#247).

## Release
- **Source:** `codex/ios-build-67` in `~/Documents/MagicMobile-release-40` = PR #255's `claude/next-update` (merged as
  `bfb83adc`) + merge of `codex/ios-build-66` (calibration tooling and `PROTOCOL.md` at engine release C) + `prepare`,
  project generated from `native-engine.yml`. Never merge that branch.
- **Engine:** release C, unchanged; preflight `ios-fast` passed, `equivalent-source`. Its first run caught
  `NativeArtworkPreference` living in a view file the presentation-checks package doesn't build (fixed in `9f86a5bf`).
- **Run:** `ios-0.1.1-67`, fingerprint `77964cfe…`, delivery `6c1b1c5b…`, VALID about 6 minutes after upload, then
  distributed to both groups.

## Verification
- CI on #255 (swift, app, real-jvm, web); web 360 tests; Swift package tests for CardArtChoices (prefetch, art-box overlay),
  OnDeviceYieldPolicy (Gogo), ParityGolden and the starting roll; Android `:core:test` and emulator acceptance (build 45).
- **Web overlay** seen in a local browser: a test picture filled Sol Ring's art box with the name and rules still visible.
- **Not verified on a phone:** the photo picker and a custom picture on the board; Gogo copying Zur in a live game;
  the opening hand showing chosen lands from the first frame.
