# Android 0.1.1 build 19: XMage dac400b, Don't ask again, Resolve all, card artwork, every token offline

## Scope
The same changes as iPhone build 34 (`release/RELEASE_0.1.1_BUILD34.md`), from PR
[#126](https://github.com/ineedsomesleep5/MagicMobile/pull/126):
- **Engine update:** XMage `4825513` → `dac400b`, plus answer actions and the AI repeat-pass rule (`docs/ENGINE_UPDATE_dac400b.md`).
- **Prompts:**
  - "Don't ask again this game" and "Always put my pick first".
  - Pass After Casting, on by default.
  - Any-number card picks with Select all and Clear.
- **The stack:**
  - "Resolve all" under the stack tray and in the stack sheet.
  - The stack drawn as parchment slips.
- **Card art:** a card's chosen artwork in Deck Studio, exact-printing online images, and export and import that keep the printing.
- **Offline download:** includes every token and emblem.

## Signed artifact
- **Source:** `6d081a0` (`codex/android-build-19`), which is `codex/engine-qol` at `1fb077a` plus versionCode `2026100703`
  and `RELEASE_BUILD` 19.
- **APK SHA-256:** `232b34ef89b53a954c4656ef484198c15f7410a1578838a0f5bb72dcdd62742e` (154000102 bytes).
- **Signer:** `b10ca2cdf5d184c2b264b56dae888d950f3ab52a40551b7f8eb634de0316d4bb`, unchanged.
- **Native engine:**
  - new, from [run 37683328246](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/37683328246) on `0546f91`;
  - `libmmengine.so` SHA-256 `bf6e0333…3d34`;
  - `packages/ondevice-engine` is identical between `0546f91` and the release source;
  - saved in `~/Documents/MagicMobile-releases/engines/android-build19-engine-0546f91`.

## Verification
- **`build_release.sh`:** the native guard, contract assertions, release lint, 16 KiB alignment and apksigner.
- **JVM and debug:**
  - `:core:test`: 222 tests, 0 failures;
  - `:app:compileDebugKotlin` succeeded;
  - the art agent's `:app:artworkCatalogueChecks` passed.
- **Emulator (API 35, arm64, `-gpu host`, headless):**
  - an in-place update, versionCode `2026100702` → `2026100703`;
  - 6/6 packaged-engine device tests on the new XMage engine;
  - the release build's menu.
- **Not verified:**
  - a physical phone;
  - the new prompt controls and the art picker on the emulator (the iOS UI tests covered the shared behavior);
  - a live iPhone-to-Android table on the new engine.
