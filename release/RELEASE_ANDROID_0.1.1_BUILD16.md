# Android 0.1.1 build 16: friend challenges, the 3D tavern room, art profile pictures

## Scope
The same changes as iPhone build 29 (`release/RELEASE_0.1.1_BUILD29.md`,
[#114](https://github.com/ineedsomesleep5/MagicMobile/pull/114)): friend challenges (Quick Match, or Ranked in the
same tier, counting for both), the 3D tavern room behind the menu with tilt parallax and flickering flames, a
non-scrolling main menu, the favorite commander's art as the profile picture, 32-frame rank badge turns, the
tavern Downloads screen, and menu animations read in the draw phase. Android pieces:
`core/.../game/FriendChallenges.kt`, `app/.../ranked/FriendChallengeViews.kt`, `ui/TavernRoomBackdrop.kt`, the
room layers as `tavern_room_*` drawables from the iOS asset catalogue and `tavern-room.json` as an asset.

## Signed artifact
- **Source:** `a7bbd68050e8f917b5a899e8ab987a0265906912` (`codex/android-build-16`), which is `main` at `7bf463a`
  (#114 merged) plus versionCode `2026100501` and `RELEASE_BUILD` 16.
- **APK SHA-256:** `8521d89fe3c406b202baf1fe7bdb49d5d192a41fbeafbcde5d3707c9cba32149` (156885702 bytes).
- **Signer:** `b10ca2cdf5d184c2b264b56dae888d950f3ab52a40551b7f8eb634de0316d4bb`, unchanged.
- **Native engine:** unchanged from build 12. `libmmengine.so` comes from `ad2e8c3`, linked from
  `~/Documents/MagicMobile-releases/engines/android-build12-engine-ad2e8c3`; `packages/ondevice-engine` is
  unchanged since `ad2e8c3`.

## Verification
- **`build_release.sh`:** the native guard, contract assertions, release lint, 16 KiB alignment and apksigner.
- **JVM:** `:core:test` (with `RankedParityTest` and the new `FriendChallengesTest`).
- **Emulator (API 35, arm64, `-gpu host`):**
  - an in-place update over build 15: versionCode `2026100401` → `2026100501`;
  - 6/6 packaged-engine device tests;
  - the release build's menu over the 3D room (Friends and Profile in one row) and the tavern Downloads screen.
- **Server:** the Supabase `friend_challenges` migration is live.
- **Not verified:** a physical Android phone; a friend challenge between two phones.

## Release
- [android-v0.1.1-build.16](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.16)
  targets `a7bbd68`, with `SHA256SUMS`, and is marked latest.
- The public download was hashed and matches the tested APK.
- Obtainium users get it as an update; earlier builds stay downloadable.
