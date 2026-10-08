# iOS 0.1.1 build 33: see the top of your library, cast cues for every zone, day/night and storm, roomier dice

Apple reports build `d1634b35-9432-4732-84cb-d9cab08d88b3` as `VALID`, with internal and external state `IN_BETA_TESTING`
(Beta App Review `APPROVED`), in the Internal (all builds) and External (added) groups, on October 7, 2026. The External
invitation remains https://testflight.apple.com/join/2mSHE8rZ. None of this proves anything on a physical iPhone or iPad.

## Changes ([#121](https://github.com/ineedsomesleep5/MagicMobile/pull/121), commits `7d66bda` and `4b450f5`)
- **The revealed top of your library** (Conspicuous Snoop, Future Sight, Courser of Kruphix, an opponent's Oracle of
  Mul Daya) leans beside your portrait, or beside your zones on the classic board, with an eye coin. It glows ember when
  playable and opens large with Cast. The adapter now keeps XMage's `topCard` as the library's one visible card, so a
  cast offered for it resolves; before, it was dropped as an unknown card. No engine change.
- **Cast cues for every zone:** your portrait and the zones button glow for the commander, a graveyard or exile cast,
  or the top card, and the menu rows say which ("Graveyard · Cast available", "Library · Top card playable").
- **Day or night** is a small sun or moon coin under the turn plate, and **the storm count** is a tag beside it. Both
  come from XMage's helper emblems and show only once they matter. **City's Blessing** is a status badge.
- **The zone viewer** uses the tavern's serif type and its own pop-over. An empty library says it is face down.
- **The starting roll:** the header sits at the top and the dice table takes the rest of the screen.

## Verification
- **Signed source:** `codex/ios-build-33` at `9b9312a`: `codex/ios-build-32` merged with `codex/polish-studio` at
  `4b450f5`, plus the build-33 bump.
- **`ios-fast` preflight:** passed 14/14, native decision `equivalent-source`.
- **Engine:** the build 21 engine already staged in this worktree from `verified-native-10945664948`; `libmmengine.a`
  SHA-256 `466597b2…9753`.
- **Tests (on `polish-studio`):**
  - `swift test`: 616 tests, 0 failures, including the new adapter test for the top card, night, storm and City's Blessing.
  - `MagicMobileTests`: 871 tests, 0 failures.
  - 7 board UI tests, all passing on the first run: zone inspection in portrait and landscape, now with a revealed
    castable top card; the shared d20 in both orientations; the starting roll; tavern menus; tavern popovers; tavern
    landscape. Screenshots were checked.
  - The 52-test UI suite from build 32 was not rerun; Deck Studio and the profile are unchanged.
- **Run:** `ios-0.1.1-33`, fingerprint `cc6c164b…352c`, IPA SHA-256 `12f7f23d…ef90f`, delivery `d1634b35…`. VALID about
  11 minutes after upload.
- **Not verified:** a physical iPhone or iPad, and a live game with a real Conspicuous Snoop. The fixture and the
  adapter test cover the mapping; the engine path is XMage's own `topCard`.
