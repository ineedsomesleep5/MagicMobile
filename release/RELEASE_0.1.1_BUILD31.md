# iOS 0.1.1 build 31: Deck Studio as a collector's binder

Apple reports build `15d9e590-f66d-4181-b8b2-91b0dffc0be4` as `VALID`, with internal and external state `IN_BETA_TESTING` (Beta App Review passed), in the Internal (all
builds) and External (added) groups, on October 6, 2026 UTC. The External invitation remains
https://testflight.apple.com/join/2mSHE8rZ. None of this proves anything on a physical iPhone or iPad.

## Changes ([#119](https://github.com/ineedsomesleep5/MagicMobile/pull/119) at `61b3f4b`, on [#118](https://github.com/ineedsomesleep5/MagicMobile/pull/118))
- **The binder (concept B):** oxblood leather holds Deck Studio's parchment pages. Done is a leather strap with a
  buckle; Save, tags and ⋯ are brass plaques. No system navigation bar, tabs or controls are left in Deck Studio.
- **Index tabs:** Cards, Ideas, Analysis and Playtest are 3D stitched leather tabs (a Meshy model) tucked under the
  page's edge; the chosen one is red and stands furthest out.
- **Rail and shelves:** *My deck* or *All cards*, the search, brass tools and mana value coins 0–7+. The coins and
  the colour filter work on both shelves; All cards keeps to the commander's colours unless turned off.
- **Sleeves:** every card sits in a translucent sleeve with brass L-shaped corners and a minus, count and plus.
- **Our style on every mark:** the Playing tag is ember glass with Play's jewel, the same height as the bracket tag;
  the favourite star and ⋯ are brass coins; notices and empty shelves are written on the page.
- **Corners:** Meshy image-to-3D corner pieces from painted references (ornate L for pages, slim L for cards,
  acanthus leaves for plates, book protectors for library decks).
- **Fix:** the first tap after scrolling a deck page is no longer swallowed by the chapter swipe.

## Verification
- **Signed source:** `codex/ios-build-31` at `3263b20`: the build-30 release branch (`0a0cc7c`) merged with unmerged
  `codex/spellbook` at `61b3f4b`, plus the build-31 bump.
- **`ios-fast` preflight:** passed 14/14, native decision `equivalent-source`.
- **Engine:** the build 21 engine re-staged from `verified-native-10945664948`; `libmmengine.a` SHA-256
  `466597b2…9753`, unchanged.
- **Tests (on #119):** `GrimoireUITests` green; earlier binder runs of `DeckStudioPinnedTabsUITests`,
  `DeckStudioReadabilityUITests`, `DeckStudioReleaseUITests` and the `OnDeviceSetupUITests` deck flows green;
  `testIncludedDeckEditingCopyDoesNotMutateBundledDeck` failed 3/3 on simulator timing in its Rename step (Rename
  works by hand). Android compile, lint, core tests and an emulator walkthrough.
- **Run:** `ios-0.1.1-31`, fingerprint `c55e665f…7904`, IPA SHA-256 `3d76e417…a242`, delivery `15d9e590…`, Xcode 27.0 (27A266a).
- **Not verified:** a physical iPhone or iPad.
