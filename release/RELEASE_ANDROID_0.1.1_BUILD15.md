# Android 0.1.1 build 15: brackets, Quick Match, Ranked and profiles

## Scope
The same changes as iPhone build 28 (`release/RELEASE_0.1.1_BUILD28.md`,
[#110](https://github.com/ineedsomesleep5/MagicMobile/pull/110)): Commander brackets, Quick Match, Ranked 1v1 with
monthly seasons and deranking, profiles with friends' badges, 3D rank badges and rank moments, and 21 included
decks for brackets 1–4. Android pieces: `core/.../game/Ranked.kt`, `app/.../ranked/`, and the rank badges as
`tavern_rank_*` drawables from the iOS asset catalogue.

## Signed artifact
- **Source:** `7727635428a3a0b1d5eb2be7294eb0ccd8d4ede7` (`codex/android-build-15`), which is #110's branch at
  `ba01cc5` plus versionCode `2026100401` and `RELEASE_BUILD` 15.
- **APK SHA-256:** `3d41df07eeac2aaa6bf83720bae0e4461b5dc526117807fa9eeccfa6a29566c7` (152,242,232 bytes).
- **Signer:** `b10ca2cdf5d184c2b264b56dae888d950f3ab52a40551b7f8eb634de0316d4bb`, unchanged.
- **Native engine:** unchanged from build 12. `libmmengine.so` comes from `ad2e8c3`, linked from
  `~/Documents/MagicMobile-releases/engines/android-build12-engine-ad2e8c3`; `packages/ondevice-engine` is
  unchanged since `ad2e8c3`.

## Verification
- **`build_release.sh`:** the native guard, contract assertions, release lint, 16 KiB alignment and apksigner.
- **JVM:** `:core:test` (with `RankedParityTest`, shared `ranked-cases.json`) and `:app:testDebugUnitTest`.
- **Emulator (API 35, arm64, `-gpu host`):**
  - an in-place update over build 14: versionCode `2026100301` → `2026100401`, first install date unchanged;
  - 6/6 packaged-engine device tests;
  - debug build screens: the mode chooser, Quick Match, Ranked, Profile and the rank-up moment.
- **Server:** the Supabase `ranked_ladder` migration is live.
- **Not verified:** a physical Android phone; a ranked match between two phones.

## Release
- [android-v0.1.1-build.15](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.15)
  targets `7727635`, with `SHA256SUMS`, and is marked latest.
- The public download was hashed and matches the tested APK.
- Obtainium users get it as an update; earlier builds stay downloadable.
