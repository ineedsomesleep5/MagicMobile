# iOS 0.1.1 build 57: the Arena crash fix, the Arena look pass, the judge's in-game fixes (internal + external)

Apple reports build `4105e435-a0e0-4874-bb9a-4dc8127b084c` as `VALID` on October 22, 2026. It went to the Internal and
External groups, and Beta App Review approved it at once. Same native engine as builds 48–56 (release C, `21a82eb7`).
The source is PR #224 (merged), which also carried build 56's records (#222).

## Changes since build 56
- **Crash fix:** build 56 crashed when switching to the Arena board on iOS 26.6.2 (TestFlight reports
  `AKHDnQF9…` and `AKVIE0kx…`): EXC_BAD_ACCESS in the main thread's stack guard while the Swift runtime instantiated
  the Arena table's nested view type. The table's layers and the board are now type-erased (`ArenaLayer`).
- **Arena buttons (Caleb's option A):**
  - an orange pill with a warm rim and glow;
  - dark glass for the second choice, blue for Mulligan and Decline, deep red for danger;
  - no brass, rivets or leather on the Arena board or in the menus.
- **Type:** serif titles with sans labels.
- **Home:**
  - commander art at 1252 px with a focus point per image (Scryfall crops upscaled 2×);
  - the panel follows a swipe;
  - no kicker or detail lines.
- **Game screens rebuilt against real Arena references** (`build_output/arena-game-reference/`):
  - the D20 rolls on the board;
  - the mulligan reads "You Go First" with a blue Mulligan and orange Keep;
  - Victory/Defeat/Draw is a banner on a flare, then the medallion, rank and numbers;
  - optional triggers get orange Do-it and blue Decline;
  - life medallions show a portrait in a thin gold ring with a life plaque;
  - player and mode choices wrap upright;
  - scry and library lose their helper lines and repeated names;
  - Arena count badges replace the coins.
- **Safe-area rule:** every full-table layer keeps its titles below the camera cutout and the opponent's plaque, and in
  landscape keeps its rows clear of the cutout and View Battlefield/Skip clear of the gear (`\.arenaSafeArea`).
- **Menus:** the copy cuts (duplicate rank lines, the queue's countdown moved onto its pill, the delete paragraph) and
  Deck Studio's binder plaques and dialogs now use Arena's buttons.

## Release
- **Source:** `codex/ios-build-57` at `68497255`: `claude/arena-mode` (= main after #224) plus the build-number prepare.
  Preflight native decision `equivalent-source` (`prepare_ios_app_native.py --verify-installed` exit 0). Xcode 27.1.
- **Run:** `ios-0.1.1-57b`, fingerprint `89fb2719…`, delivery `4105e435…`, IPA `58c07c76…`.
  - The first run, `ios-0.1.1-57`, stopped before archiving when the disk filled up (ENOSPC writing its third event).
    Apple still showed 56 as the latest build, so the release re-ran with the same build number.

## Verification
- **Design judge:** all 20 screens (9 menus, 11 in game) pass in both orientations, after 4 rounds.
- **Preflight `ios-fast`:** 14/14. CI on #224: green, including the Board 200 ms type-check budget (CardTile's body
  split).
- **UI tests on the iPhone 17 Pro Max simulator, exact final source:** 35 pass (board and roll, mulligan, concede, card
  choices, Ranked, Social, How to Play, presentation-smoke).
- **Not proven here:** the crash fix. The simulator never showed the crash (it has a larger stack and ran Debug builds).
- **Still to check on Caleb's iPhone:** switching to the Arena board, plus the new screens on device.
