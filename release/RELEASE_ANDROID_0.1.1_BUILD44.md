# Android 0.1.1 build 44: the mic under the gear, Push to Talk, spread-hand drag

Published October 27, 2026 as the latest public release,
[android-v0.1.1-build.44](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.44), from
PR #252 (TestFlight 66 from the same source on `codex/ios-build-66`).

## Signed artifact
- **Source:** `codex/android-build-44` (`c764740d`) = PR #252's head `4732e33e` merged with `codex/android-build-43`
  (calibration tooling and `PROTOCOL.md` at engine release C), versionCode `2026102703`, `RELEASE_BUILD` 44.
- **Native engine:** unchanged from build 31 (release C, `21a82eb7`).
- **APK SHA-256:** `0c380ffeb33f5c9bda358f4dd92b5e9285a125760ff8a20b42f153199b5c51bb` (144082824 bytes), with a copy in
  `~/Documents/MagicMobile-releases/android-44/`. The public download was re-hashed and matches.

## What changed
Same as TestFlight 66 (`release/RELEASE_0.1.1_BUILD66.md`): the mic under the gear, Push to Talk (hold the mic), and a
drag from the spread hand carrying the card under the finger (Compose's remembered `::localFun` handlers and an
off-screen touch surface had shifted it about two cards right).

## Verification
- **`build_release.sh`:** native guard, contracts, release lint, alignment and apksigner.
- **Emulator (API 35, headless):** in-place update `2026102702` → `2026102703`; 6/6 packaged-engine device tests,
  including a 19-turn native Commander game and a seeded game record.
- **Design preview on the emulator:** spread-hand flick (Sol Ring cast), press-and-hold (Swords to Plowshares) and a drag
  after swiping the row each carried the card under the finger; Push to Talk shown in Game Settings.
- **Not verified on a phone:** push to talk with real audio.
