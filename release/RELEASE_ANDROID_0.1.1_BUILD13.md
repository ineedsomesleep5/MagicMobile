# Android 0.1.1 build 13: friends, table chat, invite links

## Scope
The same changes as iPhone build 22 (`release/RELEASE_0.1.1_BUILD22.md`, [#90](https://github.com/ineedsomesleep5/MagicMobile/pull/90)). Android-specific pieces:
- **Invite links:** verified app links for `magicmobile-downloads.vercel.app/join/*`, served by `/.well-known/assetlinks.json` with signer `B1:0C:…:D4:BB`, plus `magicmobile://join/CODE`.
- **Single app instance:** `MainActivity` is `singleTask`, so a link opens the running app instead of a second copy with its own engine.

## Signed artifact
- **Source:** `70dde596e136bb0522a6c44dd278857fe4409748` (`codex/android-build13`), which is `main` at #90 (`de70d46`) plus versionCode `2026092801` and `RELEASE_BUILD` 13.
- **APK SHA-256:** `cfb70d3f9f893f41433a5aec2066fe6e88a3e08575a331202d77df69f1aec44c` (138,721,391 bytes).
- **Signer:** `b10ca2cdf5d184c2b264b56dae888d950f3ab52a40551b7f8eb634de0316d4bb`, unchanged.
- **Native engine:** unchanged from build 12. `libmmengine.so` comes from `ad2e8c3`, linked from `~/Documents/MagicMobile-releases/engines/android-build12-engine-ad2e8c3`, and `verify_native.py` verified it.

## Verification
- **`build_release.sh`:** the native guard, contract assertions, release lint, 16 KiB alignment and apksigner.
- **JVM:** 237 tests, including `TableChatParityTest`.
- **Emulator (API 35, arm64, `-gpu host`):**
  - an in-place update over build 12; the first install date is unchanged;
  - 6/6 packaged-engine device tests;
  - `pm get-app-links` reports `magicmobile-downloads.vercel.app: verified`, and an https invite link opened the app.
- **Before release**, two native debug builds of this code ran in split screen on the live relay:
  1. host a table, then join it through `magicmobile://` and `https://` links;
  2. one D20 round;
  3. the game log reads "HostA chooses that GuestB take the first turn", the roll winner, with no manual prompt;
  4. chat arrived with an unread badge, and "shit" was shown as "s***".
- **Not verified:**
  - a physical Android phone;
  - the versus intro's seats on screen (split screen clipped them);
  - profiles live: anonymous sign-ins are off in Supabase until Caleb enables them.

## Release
- [android-v0.1.1-build.13](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.13) targets `70dde59`, with `SHA256SUMS`, and is marked latest.
- The public download was hashed and matches the tested APK.
- Obtainium users get it as an update.
