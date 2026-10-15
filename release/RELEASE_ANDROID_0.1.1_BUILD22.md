# Android 0.1.1 build 22: smart auto-pass that lets effects finish, the turn timer ring and a guided first game

Published October 14, 2026 as [android-v0.1.1-build.22](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.22),
together with iPhone build 38 (`release/RELEASE_0.1.1_BUILD38.md`), on the same XMage `dac400b` engine as build 19.
It carries everything iPhone builds 37 and 38 added.

## Scope
- PR #138: Arena-style smart auto-pass with phase stops.
- PR #139 and #144: the online turn timer, now a ring around the pass button and the opponent's medallion.
- PR #140: a guided first game with a coach.
- PR #145: Cormorant SC for titles and brand plaques.
- PR #148: smart pass waits for spell showcases, removal and combat hits to finish before passing (at most 4 s per
  prompt; triggers never wait), and automatic passes no longer flash the "Waiting for the table…" pop-up.

## Signed artifact
- **Source:** `d0d88cd` (`codex/android-build-22`): main `d6d7a2d` (#148) plus versionCode `2026101401` and
  `RELEASE_BUILD` 22. That branch also restores `packages/ondevice-engine/docs/PROTOCOL.md` to `0546f91` (docs only),
  so the native guard sees the package identical to the staged engine's source; this records branch doesn't carry that.
- **APK SHA-256:** `e997bd38e7a8d5a1b142bcd73d1cbd0b560d5130a945f0b6d4375b409127bc4a` (154446383 bytes). The public
  download re-hashes to the same value.
- **Signer:** SHA-256 `b10ca2cd…d4bb` (the release key, unchanged), so it updates in place.
- **Native engine:** unchanged from build 19 (`android-build19-engine-0546f91`).

## Verification
- **`build_release.sh`:** the native guard, contract assertions, release lint, alignment and apksigner.
- **JVM:** `:core:test` 244 tests, 0 failures, including the new smart-pass hold and automatic-pass tests.
- **Emulator (API 35, headless):** an in-place update `2026101101` → `2026101401`, 6/6 packaged-engine device tests, the
  release build's menu.
- **Not verified:** a physical phone, and the smart-pass changes in a played game on Android.
