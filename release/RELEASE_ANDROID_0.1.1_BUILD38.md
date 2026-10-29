# Android 0.1.1 build 38: deck Power, more AI decks, spread-hand drag, one-step multi-card choices

Published October 25, 2026 as the latest public release,
[android-v0.1.1-build.38](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.38), together
with iPhone build 61 (`release/RELEASE_0.1.1_BUILD61.md`), from the same changes (PRs #241 and #242).

## Signed artifact
- **Source:** `codex/android-build-38` (`2bd785fb`) = main `d18fe1d5` with versionCode `2026102501`, `RELEASE_BUILD` 38,
  and the calibration tooling at build 37's version (release branch only; never merged).
- **Native engine:** unchanged from build 31 (release C, `21a82eb7`).
- **APK SHA-256:** `47f62da365735f09cdc3ef65e373789bda649edcf878e8c8421102048fb9108f` (136401073 bytes), with a copy in
  `~/Documents/MagicMobile-releases/android-38/`. The public download was re-hashed and matches.
- **Signer:** unchanged, so it updates in place.

## Verification
- **`build_release.sh`:** native guard, contracts, release lint, alignment and apksigner.
- **Emulator (API 35, headless):** in-place update `2026102401` → `2026102501`; 6/6 packaged-engine device tests,
  including a 34-turn native Commander game and a seeded game record (52 entries by turn 3, engine
  `sha256:9f06efbe…906f`); the menu renders.
- **Not verified on a phone:** Quick Match's levels, a ranked pick, the spread-hand drag and a multi-card discard.
