# Android 0.1.1 build 46: lessons with Maren, the Arena look on the board, Gogo's combat target

Published October 28, 2026 as the latest public release,
[android-v0.1.1-build.46](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.46), from
main `a263423a` (TestFlight 68 from the same source on `codex/ios-build-68`).

## Signed artifact
- **Source:** `codex/android-build-46` (`bdf949ef`) = main `a263423a` merged with `codex/android-build-45` (calibration
  tooling and `PROTOCOL.md` at engine release C), without the Mac-only `LessonCli.java`, versionCode `2026102801`,
  `RELEASE_BUILD` 46.
- **Native engine:** unchanged from build 31 (release C, `21a82eb7`).
- **APK SHA-256:** `a5ccdba40f2b7c3c2ee68d19bed1bf5b1341f99b46ee2e8773b7427468221bfd` (144286447 bytes), with a copy in
  `~/Documents/MagicMobile-releases/android-46/`. The public download was re-hashed and matches.

## What changed
Same as TestFlight 68 (`release/RELEASE_0.1.1_BUILD68.md`): the five lessons with Maren, the Arena look for the board's
leftover Tavern pieces (phase stops, decision tag, panel titles, close buttons), and Gogo's target in combat (#257).
Android-only fixes from the lessons work: a wrong move no longer opens the engine error panel, and an old nudge no longer
reappears on the lesson-complete card.

## Verification
- **Unit:** `:core:test` LessonsTest (6) and the Arena board model tests (#257); CI on #257 and #258.
- **`build_release.sh`:** native guard, contracts, release lint, alignment and apksigner.
- **Emulator (API 35, headless):** in-place update `2026102704` → `2026102801`; 6/6 packaged-engine device tests,
  including a 16-turn native Commander game and a seeded game record. Lessons 1 and 5 were played on the emulator during
  the lessons work.
- **Not verified on a phone:** the lessons on a real Android phone; Gogo copying Zur in a live game.
