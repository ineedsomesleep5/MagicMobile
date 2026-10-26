# Android 0.1.1 build 39: drag straight off the spread hand, full trigger text, tidy big hands

Published October 25, 2026 as the latest public release,
[android-v0.1.1-build.39](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.39), together
with iPhone build 62 (`release/RELEASE_0.1.1_BUILD62.md`), from PR #244.

## Signed artifact
- **Source:** `codex/android-build-39` = main `6f7d21e1` with versionCode `2026102502`, `RELEASE_BUILD` 39, and the
  calibration tooling at build 37's version (release branch only; never merged).
- **Native engine:** unchanged from build 31 (release C, `21a82eb7`).
- **APK SHA-256:** `ec436b5851dd528ad83b7db0d2f7c0e2f145547650105f5415ea2b6b776040e1` (136403737 bytes), with a copy in
  `~/Documents/MagicMobile-releases/android-39/`. The public download was re-hashed and matches.

## Verification
- **`build_release.sh`:** native guard, contracts, release lint, alignment and apksigner.
- **Emulator (API 35, headless):** in-place update `2026102501` → `2026102502`; 6/6 packaged-engine device tests,
  including an 18-turn native Commander game and a seeded game record (56 entries by turn 3).
- **Not verified on a phone:** the drag from the spread hand, the trigger screen and a big hand.
