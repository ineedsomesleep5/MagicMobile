# Android 0.1.1 build 52: blockers that make sense

Published October 31, 2026 as the latest public release,
[android-v0.1.1-build.52](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.52), from
PRs #273, #274 and #275 (TestFlight 74 from the same source).

## Signed artifact
- **Source:** `codex/android-build-52` (`c4533e46`) = main `453b8d1c` + bump, versionCode `2026103101`, `RELEASE_BUILD` 52.
- **Native engine:** new, `magicmobile-android.yml` run 41234796303 on `88bfdbe2`, identity `sha256:caaa30a0…1be1`, in `~/Documents/MagicMobile-releases/engines/android-build52-engine-88bfdbe`.
- **APK SHA-256:** `34b9b15240e1e245622f98966c69e89e1cf67c4b8aa78927888d9c25f2664824` (144277127 bytes), with a copy in `~/Documents/MagicMobile-releases/android-52/`. The public download was re-hashed and matches.

## What changed
Blockers and the Fear note as in TestFlight 74 (`release/RELEASE_0.1.1_BUILD74.md`), plus the game report's new fields. The animation caps and the profile's shadow change are iPhone only.

## Verification
- `build_release.sh`; emulator API 35: in-place update `2026103001` → `2026103101`, 6 of 6 device tests with an 18-turn native game on the new engine.
- **Not verified on a phone.**
