# TestFlight 0.1.1 (68): lessons with Maren, the Arena look on the board, Gogo's combat target

Uploaded October 28, 2026 and distributed to Internal and External testers (both `IN_BETA_TESTING`). Released with
Android build 46 (`release/RELEASE_ANDROID_0.1.1_BUILD46.md`) and the web deploy `dpl_2L5Zqa1gXU6WSFCicmwUxF8acSqs`, from
main `a263423a` (PR #258, which carries #257).

## What changed
- **Lessons (PR #258):** five scripted lessons on the real Arena board (Lands and spells, Combat, Instants and the stack,
  Your commander, Around the table), recorded from the real engine and played back with no engine running. Maren rings
  what to touch, waits for the move and nudges a wrong one. Her card moves out of the way and tucks into a chip while a
  panel is open. The first-launch welcome starts the lessons, and the guided game follows the last one. Lessons never
  count toward stats, ranked or game records. See `docs/LESSONS_TUTORIAL.md`.
- **Arena look (PR #258):** the phase stops, the "Your decision" tag, panel titles, close buttons and dividers on the
  Arena board use the Arena look instead of the Tavern one.
- **Gogo's target in combat (PR #257):** a target prompt during declare attackers or blockers (Gogo copying Zur's attack
  trigger) is no longer read as the combat declaration, so the game no longer sticks on "Choose attackers".

## Release
- **Source:** `codex/ios-build-68` in `~/Documents/MagicMobile-release-40` = main `a263423a` + merge of
  `codex/ios-build-67` (calibration tooling and `PROTOCOL.md` at engine release C) + `prepare`, project generated from
  `native-engine.yml`. It also leaves out `packages/ondevice-engine/engine/tools/LessonCli.java`, the Mac-only lesson
  recorder, which the whole-package engine check otherwise counts as an engine change. Never merge that branch.
- **Engine:** release C, unchanged; preflight `ios-fast` passed 14/14, `equivalent-source` (`21a82eb7`).
- **Run:** `ios-0.1.1-68`, fingerprint `49c6c41c…`, delivery `11936853…`, VALID about 6 minutes after upload, then
  distributed to both groups. Scripts and logs in `~/Documents/MagicMobile-releases/ios-68/`.

## Verification
- CI on #257 and #258; iOS LessonsTests (7) and the related Swift suites; Android `:core:test`; web 366 tests.
- Lessons played on the iPhone simulator (lessons 1, 2, 4 and 5, the opponent swaps, the moving coach card).
- **Not verified on a phone:** the lessons on a real iPhone; the coach's tucked chip over phase stops (the simulator
  would not open that panel by tap).
