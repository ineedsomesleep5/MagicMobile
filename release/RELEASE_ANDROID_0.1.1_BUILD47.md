# Android 0.1.1 build 47: choose targets on the stack, turn to the opponent with choices

Published October 28, 2026 as the latest public release,
[android-v0.1.1-build.47](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.47), from
PR #261 (TestFlight 69 from the same source on `codex/ios-build-69`).

## Signed artifact
- **Source:** `codex/android-build-47` (`683e624c`) = PR #261's head `591a474f` merged with `codex/android-build-46`
  (calibration tooling and `PROTOCOL.md` at engine release C, no `LessonCli.java`), versionCode `2026102802`,
  `RELEASE_BUILD` 47.
- **Native engine:** unchanged from build 31 (release C, `21a82eb7`).
- **APK SHA-256:** `a2efca15325ee492dc6d88310812c1baf59295987190e0d911c183ce7bf91125` (144292407 bytes), with a copy in
  `~/Documents/MagicMobile-releases/android-47/`. The public download was re-hashed and matches.

## What changed
Same as TestFlight 69 (`release/RELEASE_0.1.1_BUILD69.md`): targets on the stack chosen in the stack browser, stack
abilities named by their source, and the four-player board turning to the opponent with choices. Also: the stack
browser's glow (a choice's, and the existing "Resolves next" ring) no longer paints over the card.

## Verification
- **Unit:** `:core:test` (428, including ArenaBoardModelTest's five recorded target questions and the parity goldens).
- **`build_release.sh`:** native guard, contracts, release lint, alignment and apksigner.
- **Emulator (API 35, headless):** in-place update `2026102801` → `2026102802`; 6/6 packaged-engine device tests,
  including a 21-turn native Commander game and a seeded game record. The recorded Gogo question was played on the
  emulator's board in a debug build (Zur's trigger chosen, answer accepted).
- **Not verified on a phone:** a live game with Gogo and Zur.
