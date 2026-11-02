# Android 0.1.1 build 56: heat reports and badges on the phone

Published November 2, 2026 as the latest public release,
[android-v0.1.1-build.56](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.56), from
PR #286 (TestFlight 79 from the same source).

## Signed artifact
- **Source:** `codex/android-build-56` (`43578676`) = PR head `49ee5fb2` + bump, versionCode `2026110201`, `RELEASE_BUILD` 56.
- **Native engine:** unchanged from build 52, identity `sha256:caaa30a0…1be1`.
- **APK SHA-256:** `ab8621cee1189acbc247ae3b910ad8bba1c3f353dd1fdcb7a008d5da5860a9d1` (144310775 bytes), with a copy in `~/Documents/MagicMobile-releases/android-56/`. The public download re-hashes the same.
- **Signer:** `b10ca2cd…d4bb`, the existing release key.

## What changed
Heat reports and badges on the phone as in TestFlight 79 (`release/RELEASE_0.1.1_BUILD79.md`). Android also reports the battery's temperature. It has no moving worlds, so it sends no table or motion.

## Verification
- `build_release.sh`; emulator API 35: in-place update `2026110103` → `2026110201`, 6 of 6 device tests with a 13-turn native game. `:core` tests, contract checks, and CI on #286.
- **On the emulator, debug build:** a lesson's record held its label, build, CPU, frames, battery and temperature; a force-quit game came back cut short and went through the send path with fixture data; 13 badges saved, using the big-file fallback from before the small files were on `main`. No crashes.
- **Not verified:** a real phone, a report reaching the live server, and the coins drawn on screen on Android.
