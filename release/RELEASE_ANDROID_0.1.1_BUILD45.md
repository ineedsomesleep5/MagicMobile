# Android 0.1.1 build 45: your own card art, Gogo copies your triggers, "You roll"

Published October 27, 2026 as the latest public release,
[android-v0.1.1-build.45](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.45), from
PR #255 (TestFlight 67 from the same source on `codex/ios-build-67`).

## Signed artifact
- **Source:** `codex/android-build-45` (`bd41c0fc`) = PR #255's `claude/next-update` merged with `codex/android-build-44`
  (calibration tooling and `PROTOCOL.md` at engine release C), versionCode `2026102704`, `RELEASE_BUILD` 45.
- **Native engine:** unchanged from build 31 (release C, `21a82eb7`).
- **APK SHA-256:** `55d096c1296e9a81af979bb122e8d0c2f68c77adbff52819b45a460d5ed7e524` (144087780 bytes), with a copy in
  `~/Documents/MagicMobile-releases/android-45/`. The public download was re-hashed and matches.

## What changed
Same as TestFlight 67 (`release/RELEASE_0.1.1_BUILD67.md`): Use my own picture in the artwork picker (CustomCardArt.kt,
drawn over the card's art box, this device only), smart pass stopping on your own trigger for an ability that can use it
(Gogo), and the roll's "You roll" title. Android never had iOS's default-art swap.

## Verification
- **Unit:** `:core:test` OnDeviceSmartPassTest (Gogo case), `:app:compileDebugKotlin`; CI on #255.
- **`build_release.sh`:** native guard, contracts, release lint, alignment and apksigner.
- **Emulator (API 35, headless):** in-place update `2026102703` → `2026102704`; 6/6 packaged-engine device tests,
  including a 16-turn native Commander game and a seeded game record.
- **Not verified on a phone:** the photo picker and a custom picture on the board; Gogo copying Zur in a live game.
