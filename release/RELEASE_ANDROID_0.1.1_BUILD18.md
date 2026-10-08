# Android 0.1.1 build 18: see the top of your library, cast cues for every zone, day/night and storm, roomier dice

## Scope
The same changes as iPhone build 33 (`release/RELEASE_0.1.1_BUILD33.md` on `codex/ios-build-33`, commits `7d66bda` and
`4b450f5` on [#121](https://github.com/ineedsomesleep5/MagicMobile/pull/121)):
- The adapter keeps XMage's `topCard` as the library's visible card, so casting it resolves. Day/night and storm come
  from the helper emblems, and designations from the player view.
- The revealed top card sits beside your portrait, beside an opponent's, and next to your zones on the classic board.
- The portrait and the zones button glow for every castable zone, and the menu rows say which.
- A small sun or moon coin under the phase plate, a STORM tag, and a City's Blessing badge.
- The zone viewer in serif type with the tavern's own menu.
- A top-aligned starting roll with a larger table.

## Signed artifact
- **Source:** `2ef7e0d47c099bc33f8f69f8f272cd77d7a68e1e` (`codex/android-build-18`): `codex/android-build-17` merged
  with `codex/polish-studio` at `4b450f5`, plus versionCode `2026100702` and `RELEASE_BUILD` 18.
- **APK SHA-256:** `d0711bc7fd30c6cc29c5dba25e0b31c4fca0603d919905c417773177aade40ce` (153611934 bytes). The public
  download was re-hashed and matches.
- **Signer:** `b10ca2cdf5d184c2b264b56dae888d950f3ab52a40551b7f8eb634de0316d4bb`, unchanged.
- **Native engine:** unchanged from build 12. `libmmengine.so` comes from `ad2e8c3`, and the native guard passed.
- **Release:** https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.18

## Verification
- **`build_release.sh`:** the native guard, contract assertions, release lint, 16 KiB alignment and apksigner.
- **JVM (on `polish-studio`):**
  - `:core:test`, including the new `OnDeviceTopCardTest` for the top card, night, storm, City's Blessing and the
    castable library.
  - `:app:compileDebugKotlin`.
- **Emulator (API 35, arm64, `-gpu host`, headless):**
  - an in-place update, versionCode `2026100701` → `2026100702`;
  - 6/6 packaged-engine device tests;
  - the release build's menu.
- **Not verified:** a physical phone, the new board pieces on the emulator (the iOS UI tests covered the shared
  layout), and a live game with a real Conspicuous Snoop.
