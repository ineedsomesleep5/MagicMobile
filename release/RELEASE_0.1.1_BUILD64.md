# TestFlight 0.1.1 (64): tables play on when a player leaves, the freeze prompt fixed, the stack tab, Archidekt names, leaderboard and profile upgrades, server controls

Uploaded October 26, 2026 and distributed to Internal and External testers; Beta App Review `APPROVED`. Released with
Android build 42 (`release/RELEASE_ANDROID_0.1.1_BUILD42.md`) and the web deploy `dpl_7JaB4E1b5WMPN3DLFrNE1UdKXy7Q`, from
PR #249.

## What changed (PR #249)
- **Players who leave:** a guest who taps Leave or drops for good is conceded and the others play on; a guest who is away
  can be voted out after 15 s by everyone still at the table. The host leaving still ends the game.
- **Freeze prompt:** "The last game froze" no longer appears after games that never froze (Danny's TestFlight report);
  menu dialogs wear the Arena glass.
- **Starting roll:** the opening hand waits until every die has landed.
- **Stack card:** an eye at its lower left tucks it to the table's edge; it tucks itself while you pick a target.
- **Join table** from a friend's profile when they host an open table.
- **Archidekt links:** adventure, omen and prepare cards and accented names match; maybeboards are left out by default.
- **Leaderboard:** commander portraits, win rates, streak flames, tier dividers, a season countdown, a Champions tab.
- **Profile:** recent form, records by mode and tier, matchups, highlights; game cards show turn, length and crushing losses.
- **Server controls:** `mm_app_config` (menu notice, card-name fixes, the `leaveVote` and `stackAutoTuck` switches;
  docs/SERVER_CONTROLS.md).

## Release
- **Source:** `codex/ios-build-64` in `~/Documents/MagicMobile-release-40` = PR #249 at `010a0794` + merge of
  `codex/ios-build-63` (the release-only calibration-tooling restore) + `PROTOCOL.md` at engine release C + `prepare`,
  project generated from `native-engine.yml`. Never merge that branch.
- **Engine:** release C, unchanged; preflight `ios-fast` 14/14, `equivalent-source` (103 s).
- **Run:** `ios-0.1.1-64`, fingerprint `e6b4155e…`, delivery `44d44dab…`, VALID about 5 minutes after upload, then
  distributed to both groups.

## Verification
- iOS package tests (797; a freeze-log test updated for the new rule), the app and test bundle compile for the simulator,
  no board expression over the 200 ms type-check budget; Android core JVM tests (413) and the app compile; web 352 tests;
  PGlite suite including the leaderboard and app-config cases. CI on #249.
- **Not verified on a phone:** a table where a player leaves or is voted out, the stack tab, joining from a profile.
