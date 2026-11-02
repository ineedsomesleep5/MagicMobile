# TestFlight 0.1.1 (79): heat reports, world motion switches and badges on the phone

Uploaded November 2, 2026 and distributed to Internal and External testers, from PR #286. Released with Android build 56
(`release/RELEASE_ANDROID_0.1.1_BUILD56.md`) and web deploy `dpl_HT9BwbgMDABaexApiwbch71UmaV3`. The migration `game_heat` went live right after the merge.

## What changed
- **Heat reports:** each game of a minute or more sends heat over time, CPU by board, updates and AI, slow frames, battery, table and phone model to `game_heat` once it ends. A game the app never ended still reports. `docs/SERVER_CONTROLS.md` "Heat reports".
- **World motion:** `worldMotion`, `worldMotionHalf` and `worldMotionTest` still or slow worlds with no build. All three are unset, so worlds run as before.
- **Badges:** 192 px copies in `design/awards/small/`, about 25 KB each, saved on the phone by `BadgeArtStore` and rechecked every six hours.
- **Privacy:** the privacy page and manifest describe the reports. Apple's App Store privacy answers will need the same before any public App Store release.

## Release
- **Source:** `codex/ios-build-79` in `~/Documents/MagicMobile-release-40` = PR head `49ee5fb2` + `prepare` + xcodegen. No engine change: build 74's engine stays staged.
- **Run:** `ios-0.1.1-79`, fingerprint `318c543c…`, delivery `2a818ac9…`, VALID about 6 minutes after the upload finished. Preflight `ios-fast` passed, equivalent-source.
- **Built with:** Xcode 27.2, iOS 27.2 SDK.

## Verification
- `swift test` (844), SQL suite, 5 UI smoke tests (`testLandscapeLibraryChoices` failed on keyboard focus under load and passed alone). CI on #286 passed on the third `swift` run: only `NativeGameView.swift:1349`, the known borderline line, was over budget, in a file this PR didn't touch.
- **On the simulator:** a lesson's record held its table, CPU and frames; a force-quit game came back cut short and went through the send path with fixture data; the world was pixel-identical with motion off and changing with it on.
- All 31 small files answered 200 after the merge. The live table takes no player reads.
- **Not verified:** a report arriving from a real phone, small badges on a phone, and the first real heat numbers.
