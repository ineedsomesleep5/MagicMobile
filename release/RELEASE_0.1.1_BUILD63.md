# TestFlight 0.1.1 (63): ranked tuned from the server, turn-judged wins, season badges, 3-button-navigation fixes

Uploaded October 26, 2026 and distributed to Internal and External testers; Beta App Review `APPROVED`. Released with
Android build 41 (`release/RELEASE_ANDROID_0.1.1_BUILD41.md`) and the web deploy of the fixed web engine, from PR #246.

## What changed (PR #246)
- **Ranked AI tuning from the server:** the ticket's skill, mistake chance and deck Power (`ranked_ai_tuning`) pick the
  AI's deck and difficulty, so balance changes need no build. Gold and Platinum are harder (docs/DECK_POWER.md).
- **Ranked wins judged by turns**, the reason shown when a win didn't count, held wins showing the right standing,
  quarterly seasons from November, season badges and the tier frame on the versus screen.
- Game records stay readable after first unlock (a locked phone sent wins without one: `no_record`).
- The yellow ability glow, your own face-down cards' art, attachment tabs in the inspector, `{this}` named in rules,
  sharper Learn and versus art, and the hand drag that carries the card it started on.
- Server-side and live for every build: no daily AI win cap, crushing losses cost two pips.

## Release
- **Source:** `codex/ios-build-63` in `~/Documents/MagicMobile-release-40` = PR #246 at `f4c6f625` + merge of
  `codex/ios-build-62` (its ledger and the release-only calibration-tooling restore) + `prepare`. Never merge that branch.
- **Engine:** release C, unchanged; preflight `ios-fast` 14/14, `equivalent-source`.
- **Run:** `ios-0.1.1-63`, fingerprint `a0bc3df6…`, delivery `a354fabc…`, VALID about 9 minutes after upload, then
  distributed to both groups.

## Verification
- CI on #246; web 342 tests; Android `RankedStandingTest` and the app compile; iOS app and test bundle compile for the
  simulator; PGlite ranked suite (tuning, no cap, crushing losses).
- **Not verified on a phone:** a ranked game with the server's tuning, the season badges, and a record sent while locked.
