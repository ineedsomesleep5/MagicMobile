# Android 0.1.1 build 51: more high-rank decks, awards, updates from the server

Published October 30, 2026 as the latest public release,
[android-v0.1.1-build.51](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.51), from
PRs #270 and #271 (TestFlight 73 from the same source).

## Signed artifact
- **Source:** `codex/android-build-51` (`b0b081da`) = #271's head `304c83bb` + merge of `codex/android-build-50` + bump, versionCode `2026103001`, `RELEASE_BUILD` 51.
- **Native engine:** release D, unchanged.
- **APK SHA-256:** `fe2b94479e694987d915928ce966249ed31f00dc0ec405b140939323d8762aee` (144270471 bytes), with a copy in `~/Documents/MagicMobile-releases/android-51/`. The public download was re-hashed and matches.

## What changed
Same as TestFlight 73 (`release/RELEASE_0.1.1_BUILD73.md`).

## Verification
- `build_release.sh` (native guard, contracts, release lint, alignment, apksigner); emulator API 35: in-place update `2026102901` → `2026103001`, 6/6 packaged-engine device tests (15-turn native game).
- **Not verified on a phone:** awards and a deck file downloading.
