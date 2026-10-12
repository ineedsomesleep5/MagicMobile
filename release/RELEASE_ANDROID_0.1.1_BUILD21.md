# Android 0.1.1 build 21: double-faced cards, commander-first import, a new game menu and a support banner

Published October 12, 2026 as [android-v0.1.1-build.21](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.21),
together with iPhone build 36 (`release/RELEASE_0.1.1_BUILD36.md`), on the same XMage `dac400b` engine as build 19.

## Scope
- PR #133: the combat freeze fix, a softer Bronze rank, a restyled recovery banner.
- PR #134: double-faced cards flip in Deck Studio and the card inspector; pick the commander before importing; import
  public decks from an Archidekt username.
- PR #135: table skins removed (Walnut Tavern only); Concede, Start New and Quit at the top of the game menu.
- PR #136: the opponent's status badges curve around their portrait, with details in its pop-over.
- PR #141: a dismissible support banner on the main menu and a support panel in Settings.

## Signed artifact
- **Source:** `16d0f55` (`codex/android-build-21`): `codex/ios-build-36` plus versionCode `2026101101` and `RELEASE_BUILD` 21.
- **APK SHA-256:** `5195358933e8d3d90c8ad9c864e104c41769c916b9c00cbbebf25516340061fc` (154193564 bytes). The public
  download re-hashes to the same value.
- **Signer:** SHA-1 `e81f749d…` (the release key, unchanged), so it updates in place.
- **Native engine:** unchanged from build 19 (`android-build19-engine-0546f91`); `packages/ondevice-engine` is identical
  to `0546f91`.

## Verification
- **`build_release.sh`:** the native guard, contract assertions, release lint, alignment and apksigner.
- **JVM:** `:core:test` 229 tests, 0 failures.
- **Emulator (API 35, headless):** an in-place update `2026100801` → `2026101101`, 6/6 packaged-engine device tests, the
  release build's menu.
- **Not verified:** a physical phone.
