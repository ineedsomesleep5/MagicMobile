# iOS 0.1.1 build 36: double-faced cards, commander-first import, a new game menu and a support banner

Apple reports build `f6edeb12-3dc1-410a-b082-87bb669ee921` as `VALID`, with Internal and External both
`IN_BETA_TESTING`, on October 12, 2026. The External invitation remains https://testflight.apple.com/join/2mSHE8rZ.
It shipped together with Android build 21, on the same XMage `dac400b` engine and catalogue as build 34, so tables still
seat both platforms. None of this proves anything on a physical iPhone or iPad.

## Changes
- [#133](https://github.com/ineedsomesleep5/MagicMobile/pull/133): the combat freeze fix, a softer Bronze rank, a
  restyled recovery banner.
- [#134](https://github.com/ineedsomesleep5/MagicMobile/pull/134): double-faced cards flip in Deck Studio and the card
  inspector; pick the commander before importing; import public decks from an Archidekt username.
- [#135](https://github.com/ineedsomesleep5/MagicMobile/pull/135): table skins removed (Walnut Tavern only); Concede,
  Start New and Quit at the top of the game menu.
- [#136](https://github.com/ineedsomesleep5/MagicMobile/pull/136): the opponent's status badges curve around their
  portrait, with details in its pop-over.
- [#141](https://github.com/ineedsomesleep5/MagicMobile/pull/141): a dismissible support banner on the main menu and a
  support panel in Settings and Updates.
- Release branch only: the Deck Studio import UI tests scroll the decklist box into view, because the new commander
  panel pushes it below the fold.

## Release
- **Source:** `codex/ios-build-36` at `a025bfc` (main `479cd55` + the build-35 records + build number 36 + the UI test
  fix). The engine is unchanged: `packages/ondevice-engine` is identical to `0546f91`, staged from
  `verified-native-11516701556`.
- **Run:** `ios-0.1.1-36`, fingerprint `529f27e7…`, delivery `f6edeb12…`, IPA `e379b0e8…`.

## Verification
- Preflight `ios-fast`: 14/14, run again on the final source.
- `MagicMobileTests`: 914 tests, 0 unexpected failures (5 skipped).
- UI tests on the iPhone 17 Pro simulator (iOS 26.5):
  - BoardPolish, BoardScrollRotation and ProfileHistory: 53/59. 4 failures passed on a rerun. 2 fail the same way on
    `593a350`, before these changes: `testLandscapeCardBackedAbilityChoice` (sheet 375 > 360 pt) and
    `testTavernPlayerPopoverShowsStatusIconsAndSwapsOpponents` (no swap button in a pod's pop-over).
  - OnDeviceSetup, HowToPlay, NativeDownloads, Ranked and the two new game-menu tests: the 5 Deck Studio failures
    passed twice in a row after the import test fix.
- **Not verified:** a physical iPhone or iPad.
