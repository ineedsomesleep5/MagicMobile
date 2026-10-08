# Android 0.1.1 build 17: the card binder, paper page turns, dice on the table, player profiles

## Scope
The same changes as iPhone build 32 (`release/RELEASE_0.1.1_BUILD32.md` on `codex/ios-build-32`,
[#121](https://github.com/ineedsomesleep5/MagicMobile/pull/121) on [#119](https://github.com/ineedsomesleep5/MagicMobile/pull/119)):
- Deck Studio as a collector's binder: the head on the paper, equal-height spreads, a compact landscape title plate,
  floating Add cards, and the binder's own menus and confirmations.
- The draggable paper curl: AGSL on Android 13+, with the swing kept on older versions.
- The starting roll on the tavern table, using Filament 1.75.1 + gltfio and adding about 3.65 MB.
- The visual profile with game history, friend search as you type, public profiles, privacy, and game upload.
- No Playtest chapter.

## Signed artifact
- **Source:** `53b6315da580a21244b4353ea7f878b7ae6106c6` (`codex/android-build-17`), which is `codex/polish-studio` at
  `d6454c4` plus versionCode `2026100701` and `RELEASE_BUILD` 17.
- **APK SHA-256:** `710c6d022d752fe1a8f0057e142ccc40bafc0d1ac87f0abd795ef6afb9e36390` (153602214 bytes).
- **Signer:** `b10ca2cdf5d184c2b264b56dae888d950f3ab52a40551b7f8eb634de0316d4bb`, unchanged.
- **Native engine:** unchanged from build 12. `libmmengine.so` comes from `ad2e8c3`, and `packages/ondevice-engine`
  is unchanged since `ad2e8c3`.

## Verification
- **`build_release.sh`:** the native guard, contract assertions, release lint, 16 KiB alignment and apksigner.
- **JVM and debug builds (on #121):** `:app:compileDebugKotlin :app:lintDebug :core:test :app:testDebugUnitTest :app:assembleDebug`.
- **Emulator (API 35, arm64, `-gpu host`, headless):**
  - an in-place update, versionCode `2026100504` → `2026100701`;
  - 6/6 packaged-engine device tests;
  - the release build's menu and library.
- **Debug build on the emulator:** the dice preview, profile, friend search, library and deck with the head on the
  page, the parchment filter menu, a dragged curl, and the landscape spread.
- **Server:** the Supabase `public_profiles` migration is live.
- **Not verified:** a physical Android phone; the curl's feel; Filament's first-frame delay on a phone.

## Release
- [android-v0.1.1-build.17](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.17) targets
  `53b6315`, with `SHA256SUMS`, and is marked latest.
- The public download was hashed and matches the tested APK.
- Obtainium users get it as an update. Earlier builds stay downloadable.
