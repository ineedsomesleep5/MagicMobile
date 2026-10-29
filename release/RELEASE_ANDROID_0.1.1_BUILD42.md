# Android 0.1.1 build 42: tables play on when a player leaves, the stack tab, Archidekt names, leaderboard and profile upgrades

Published October 26, 2026 as the latest public release,
[android-v0.1.1-build.42](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.42), from
PR #249 (TestFlight 64 from the same source on `codex/ios-build-64`).

## Signed artifact
- **Source:** `codex/android-build-42` (`dfdb5d63`) = `claude/table-fixes` at `010a0794` merged with
  `codex/android-build-41` (calibration tooling at engine release C) + `PROTOCOL.md` at release C, versionCode
  `2026102701`, `RELEASE_BUILD` 42.
- **Native engine:** unchanged from build 31 (release C, `21a82eb7`).
- **APK SHA-256:** `505c37b42eeae32ccd30f51216d3540d9c98c25eb9e88339e371cd1e3e278abb` (136459105 bytes), with a copy in
  `~/Documents/MagicMobile-releases/android-42/`. The public download was re-hashed and matches.

## What changed
Same as TestFlight 64 (`release/RELEASE_0.1.1_BUILD64.md`): players who leave are conceded and an away player can be voted
out, the false freeze prompt fixed, the opening hand after the roll, the stack card's eye and auto-tuck, Join table on a
friend's profile, Archidekt names, the leaderboard and profile upgrades, and the server's app config.

## Verification
- **`build_release.sh`:** native guard, contracts, release lint, alignment and apksigner.
- **Emulator (API 35, headless):** in-place update `2026102602` → `2026102701`; 6/6 packaged-engine device tests,
  including a 17-turn native Commander game and a seeded game record.
- **Unit:** core JVM tests (413), including the table-leave, card-name, profile-insight and app-config cases.
- **The Mac:** the first attempt ran into a watchdog kernel panic (8 GB Mac starved under memory pressure). This run waited
  for the Mac to idle, capped the Kotlin compiler at 1.5 GB, stopped Gradle before the emulator, gave the emulator 1.5 GB
  and ran a guard that stops both at critical pressure; pressure stayed normal.
- **Not verified on a phone:** a table where a player leaves or is voted out, the stack tab, joining from a profile.
