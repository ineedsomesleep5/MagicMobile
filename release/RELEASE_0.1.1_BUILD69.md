# TestFlight 0.1.1 (69): choose targets on the stack, turn to the opponent with choices

Uploaded October 28, 2026 and distributed to Internal and External testers (both `IN_BETA_TESTING`). Released with
Android build 47 (`release/RELEASE_ANDROID_0.1.1_BUILD47.md`) and the web deploy `dpl_9ZPd6ScXHQBArDM3a5cHmREbTwT5` (which also carries #238, the web card tilt), from
PR #261 (merged as `80a80457`).

## What changed (PR #261)
- **Targets on the stack:** a target question whose choices are spells or abilities on the stack (Gogo copying Zur's
  attack trigger; a Counterspell with two spells on the stack) opens the stack browser to choose: the question is the
  title, the choices glow, a tap chooses, Cancel and View Battlefield below. The stack card no longer tucks itself for
  it. Before, the game sat on "Select an activated or triggered ability you control" with nothing to tap.
- **Names:** stack abilities in target lists read "Zur the Enchanter’s ability", not "Card details unavailable".
- **Four players:** when every choice is on opponents the board isn't showing, the board turns to the first of them;
  the swap row marks opponents with choices.

## Release
- **Source:** `codex/ios-build-69` in `~/Documents/MagicMobile-release-40` = PR #261's head `591a474f` + merge of
  `codex/ios-build-68` (calibration tooling and `PROTOCOL.md` at engine release C, no `engine/tools/LessonCli.java`) +
  `prepare`, project generated from `native-engine.yml`. Never merge that branch.
- **Engine:** release C, unchanged; preflight `ios-fast` passed 14/14, `equivalent-source`.
- **Run:** `ios-0.1.1-69`, fingerprint `1db54cf8…`, delivery `586b75cc…`, VALID about 8 minutes after upload, then
  distributed to both groups. Uploaded before #261's CI finished, from the same commit; CI then passed and it merged.

## Verification
- Six real target questions recorded from the JVM engine (`scripts/lessons/capture_targets.py`): iOS ArenaBoardModelTests,
  Android ArenaBoardModelTest, web `stackTargets.test.ts`, parity goldens for all six; CI on #261.
- The recorded Gogo question played on the real board in the iPhone simulator, the Android emulator and the browser
  (Zur's trigger chosen, answer accepted); the four-player Doom Blade question on iPhone (board turned to Rook).
- **Not verified on a phone:** a live game with Gogo and Zur.
