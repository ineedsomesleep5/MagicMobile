# Android 0.1.1 build 14: the Walnut Tavern everywhere, spell moments, How to Play

## Scope
The same changes as iPhone build 27 (`release/RELEASE_0.1.1_BUILD27.md`, [#105](https://github.com/ineedsomesleep5/MagicMobile/pull/105)), except iPad. Android-specific pieces:
- **Splash:** Android 12+ launches on walnut `#1B120B` with the brass-ring M, inset so the ring survives the launcher's circle mask.
- **Launcher icon:** the carved walnut frame on the adaptive icon, inset 22% so the whole frame sits inside the mask.
- **Sheets:** the shared list components (`IosSheetHeader`, `IosListSection`, `IosListRow`, `IosTextButton`) draw the tavern style, so every bottom sheet wears it.
- **Idle cost:** breathing glows share one 20-a-second clock (`rememberBoardBreath`).

## Signed artifact
- **Source:** `3234675578460212e29c6a69a718b855e86cca99` (`codex/android-build-14`), which is #105's branch at `e7d05f5` plus versionCode `2026100301` and `RELEASE_BUILD` 14.
- **APK SHA-256:** `9e603d8d4c1ac1cf14902b18c22bfbca686f6628197f52c4792638a3f215b8fe` (147,545,946 bytes).
- **Signer:** `b10ca2cdf5d184c2b264b56dae888d950f3ab52a40551b7f8eb634de0316d4bb`, unchanged.
- **Native engine:** unchanged from build 12. `libmmengine.so` comes from `ad2e8c3`, linked from `~/Documents/MagicMobile-releases/engines/android-build12-engine-ad2e8c3`; `packages/ondevice-engine` is unchanged since `ad2e8c3`.

## Verification
- **`build_release.sh`:** the native guard, contract assertions, release lint, 16 KiB alignment and apksigner.
- **JVM:** `:core:test` 173 and `:app:testDebugUnitTest` 72.
- **Emulator (API 35, arm64, `-gpu host`):**
  - an in-place update over the installed build; the first install date is unchanged and the versionCode reads `2026100301`;
  - 6/6 packaged-engine device tests;
  - debug design previews: the spell moment (`board-fx`), the tavern sheets, the How to Play chooser and both tutorials, the Updates sheet and the splash.
- **Not verified:** a physical Android phone; an online game against an iPhone on build 27.

## Release
- [android-v0.1.1-build.14](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.14) targets `3234675`, with `SHA256SUMS`, and is marked latest.
- The public download was hashed and matches the tested APK.
- Obtainium users get it as an update; earlier builds stay downloadable.
