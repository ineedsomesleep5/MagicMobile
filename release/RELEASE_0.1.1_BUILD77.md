# TestFlight 0.1.1 (77): trophies from the server

Uploaded November 1, 2026 and distributed to Internal and External testers, from PR #281. Released with Android build 54
(`release/RELEASE_ANDROID_0.1.1_BUILD54.md`) and web deploy `dpl_9F84NSmfoCQNB3Jj819CDZKReX9L`. The migration `trophies` went live right after the merge, once the art was on `main`.

## What changed
- **Trophies:** an award with `shelf` set stands on the profile's Trophies shelf, dark until earned, so a new one needs only a row (`docs/SERVER_CONTROLS.md`). Twelve new coins with art, and rules that run after every game.
- **Season badge glow:** no longer clipped by the shelf's scroller.
- **Piles:** they lean away from the point under the camera, so the opponent's deck leans the right way, and a full far deck stays on the screen.
- **Awards card:** gone for a player who has only trophies.
- **News:** an Inbox note covers placements and trophies.

## Release
- **Source:** `codex/ios-build-77` in `~/Documents/MagicMobile-release-40` = PR head `c57f1c6b` + `prepare` + xcodegen. No engine change: build 74's engine stays staged.
- **Run:** `ios-0.1.1-77`, fingerprint `a433eff5…`, delivery `9646357b…`, VALID at the first check after upload. Preflight `ios-fast` passed, equivalent-source.
- **Built with:** Xcode 27.2, iOS 27.2 SDK.

## Verification
- SQL suite in PGlite, including `trophies.sql`. A rolled-back dry run on the live database, then the migration: 15 trophies given across 5 players, 0 unseen.
- iOS: `swift test` (825), board and profile tests, and on the simulator the trophy shelf, season badges and a 92-card deck in both orientations. CI on #281 passed.
- **Seen on Caleb's phone:** the shelf with his real account, 16 of 25, the new art loading and his five backfilled trophies lit.
- **Not verified on a phone:** a trophy earned after a real game.
