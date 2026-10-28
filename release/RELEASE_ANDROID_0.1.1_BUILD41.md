# Android 0.1.1 build 41: ranked tuned from the server, harder Gold and Platinum

Published October 26, 2026 as the latest public release,
[android-v0.1.1-build.41](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.41), from
PR #246 (TestFlight 63 is prepared from the same source on `codex/ios-build-63`).

## Signed artifact
- **Source:** `codex/android-build-41` (`6965564b`) = `claude/ranked-turns-history` at `f4c6f625` merged with
  `codex/android-build-40` (calibration tooling at build 37's version), versionCode `2026102602`, `RELEASE_BUILD` 41.
- **Native engine:** unchanged from build 31 (release C, `21a82eb7`).
- **APK SHA-256:** `0c32f5fa608d2c6e43608ee23747b931b560b040e60ce2283b5f20327db97028` (136430269 bytes), with a copy in
  `~/Documents/MagicMobile-releases/android-41/`. The public download was re-hashed and matches.

## What changed
- The ranked ticket's AI tuning (`ranked_ai_tuning`): the AI deck's Power, the AI's skill and its mistake chance come from
  the server, so difficulty changes need no build. Gold is now Power 6–7 with 5% → 2% mistakes, Platinum 7–8.
- Server-side and already live for every build: no daily AI win cap, and a crushing loss (the AI kept 30+ life) costs
  two pips above Bronze.

## Verification
- **`build_release.sh`:** native guard, contracts, release lint, alignment and apksigner; debug lint passes.
- **Emulator (API 35, headless):** in-place update `2026102601` → `2026102602`; 6/6 packaged-engine device tests,
  including a 15-turn native Commander game and a seeded game record.
- **Unit:** `RankedStandingTest` (10) including the tuned ticket.
- **Not verified on a phone:** a ranked game with the server's tuning.
