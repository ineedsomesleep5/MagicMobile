# TestFlight 0.1.1 (76): placement matches

Uploaded November 1, 2026 and distributed to Internal and External testers, from PR #279. Released with Android build 53
(`release/RELEASE_ANDROID_0.1.1_BUILD53.md`) and a web deploy. The migration `ranked_placements` went live first.

## What changed
- **Placements:** every season, and every new player, starts with five placement matches. A win climbs two divisions, up to Gold II, or Platinum IV after making Mythic. The rank stays hidden until the fifth game, which plays a PLACED moment.
- **This season:** games already played were replayed as placements (`mm_ranked_recount`).
- **Android builds:** `prepare_audio.py` skips the iOS worlds' IMA4 loops, which had broken Android builds from `main` since #277.

## Release
- **Source:** `codex/ios-build-76` in `~/Documents/MagicMobile-release-40` = `claude/ranked-placements` `296c7d34` + `prepare` + xcodegen. No engine change: build 74's engine stayed staged.
- **Run:** `ios-0.1.1-76`, fingerprint `94d61d28…`, delivery `6e660d76…`, VALID about 5 minutes after upload, Beta App Review APPROVED. Preflight `ios-fast` passed, equivalent-source.
- **Built with:** Xcode 27.2, iOS 27.2 SDK.

## Verification
- SQL suite in PGlite, including `ranked_placements.sql`. Live check after the migration: standings replayed as expected, and `mm_ranked_recount` isn't callable by players.
- iOS: `swift test` (823), rank parity, standing and store tests, and two UI tests on the simulator. CI on #279 passed; `Web tests` needed one rerun of an unrelated timing test (`soloFlow`).
- **Not verified on a phone:** a live placement game against the server, and the PLACED moment after a real game.
