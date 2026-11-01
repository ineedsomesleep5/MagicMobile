# TestFlight 0.1.1 (75): living worlds, drawn at random

Uploaded November 1, 2026 and distributed to Internal and External testers, from PR #277. iOS only: Android and web still draw Walnut.

## What changed
- **Four worlds:** Volcano, Utopia, Halloween and Radio Night join Walnut as Arena tables. They move, answer the game and rest with the board.
- **Tables are drawn:** each game draws its table from its match ID. Quick Match's Advanced and a Custom Table can pick one, pinned to that match. The Theme picker left Options and the game menu.
- **Sound:** a quiet loop per world, a World Sounds switch under Audio, and rows in Sound Lab. Caleb hasn't heard them yet.

## Release
- **Source:** `codex/ios-build-75` in `~/Documents/MagicMobile-release-40` = `claude/living-worlds` + `prepare` + xcodegen. No engine change: the package is identical to build 74's and that engine stayed staged.
- **Run:** `ios-0.1.1-75`, fingerprint `0c862ff2…`, delivery `819f18df…`, VALID about 5 minutes after upload, Beta App Review APPROVED. Preflight `ios-fast` passed 14 of 14, equivalent-source.
- **Built with:** Xcode 27.2, iOS 27.2 SDK.

## Verification
- On the iOS 27.2 simulator: `ArenaBoardModelTests`, `BattlefieldBackdropTests`, `presentation-smoke` and `testTheTableIsPickedOnlyUnderAdvanced`.
- Recordings showed rest, a tap waking a resting world, the low-life edge, and flows unchanged with the clock at 50 minutes.
- CI on #277: every functional step passed. The `swift` job's type-check budget failed at 208-212 ms on `NativeGameView.swift:1349`, a line this PR doesn't change and a known slow-runner failure (`docs/LESSONS.md`), so the job was rerun.
- **Not verified on a phone:** heat, a live game's reactions, Low Power Mode, and the sounds by ear.
