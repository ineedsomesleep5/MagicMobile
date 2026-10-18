# Android 0.1.1 build 29: Ranked Hall, friend messages and the combo loop (releases A and B)

Published October 17, 2026 as [android-v0.1.1-build.29](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.29),
first as a test prerelease and then as the latest release once Caleb said ship, together with iPhone build 46
(`release/RELEASE_0.1.1_BUILD46.md`), on the same native engine as builds 24–25. Test builds 26–28 stay available as
prereleases.

## Scope
Same changes as iPhone build 46: the Ranked Hall and live leaderboard, the Stack chip, heat and memory awareness with
Settings → Game Performance, messages between friends inside and outside games, and the reworked combo loop (#193).

## Signed artifact
- **Source:** `c3797634` (`codex/android-build-29`): `claude/combo-loop-2` `495579c1` (main `428ab6e9`) plus versionCode
  `2026101703` and `RELEASE_BUILD` 29. The engine package is unchanged since the engine's source commit `160e250`.
- **Native engine:** unchanged (`android-build24-engine-160e250`).
- **APK SHA-256:** `1321db8a29de012bd6c9e2e3cb664c5dad5eb4def92ae6fd5f09bcf1bbdebb47` (143258892 bytes). The public
  download re-hashes to the same value.
- **Signer:** unchanged, so it updates in place.

## Verification
- **`build_release.sh`:** the native guard, contract assertions, release lint, alignment and apksigner.
- **Emulator (API 35, headless):** an in-place update `2026101702` → `2026101703`; 6/6 packaged-engine device tests,
  including a 17-turn native Commander game and a seeded game record (53 entries by turn 3, engine build
  `sha256:225ee7de…9869`).
- Android core tests 270/0 and app unit tests 92/0; `:app:compileDebugKotlin` on the merged source.
- **Not verified:** a physical phone, and the reworked combo loop with a real loop.
