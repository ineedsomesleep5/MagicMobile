# Android 0.1.1 build 50: every player picks a name first

Published October 29, 2026 as the latest public release,
[android-v0.1.1-build.50](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.50), from
PR #267 (TestFlight 72 from the same source).

## Signed artifact
- **Source:** `codex/android-build-50` (`80a41288`) = `codex/android-build-49` + merge of PR #267's head, engine package as
  candidate `a98b4b63`, versionCode `2026102901`, `RELEASE_BUILD` 50.
- **Native engine:** release D, unchanged from build 49.
- **APK SHA-256:** `8078a62c5a5e3d19e87d4ae6e644acc8759e5d8d564ec37968f91a9d96631512` (144242891 bytes), with a copy in
  `~/Documents/MagicMobile-releases/android-50/`. The public download was re-hashed and matches.

## What changed
Same as TestFlight 72 (`release/RELEASE_0.1.1_BUILD72.md`): the name screen before the menus (Google sign-in on Android).

## Verification
- `build_release.sh` (native guard, contracts, release lint, alignment, apksigner); emulator API 35: in-place update
  `2026102804` → `2026102901`, 6/6 packaged-engine device tests (20-turn native game).
- **Not verified on a phone:** the gate itself (the emulator's device tests run without a profile).
