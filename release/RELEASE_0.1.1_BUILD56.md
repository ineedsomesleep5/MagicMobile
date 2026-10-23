# iOS 0.1.1 build 56: Arena menus, the brass logo, Archidekt share links, Hearth landscape fixes (internal + external)

Apple reports build `9ee7aee4-c514-4a66-8009-b880406c1a06` as `VALID` on October 22, 2026. It went to the Internal
and External groups; Beta App Review: APPROVED at once. Same native engine as builds 48–55 (release C, `21a82eb7`), so tables
seat Android 31–33. The work is in PR #221 (`claude/arena-mode`).

## Changes since build 55
- **Arena menus everywhere outside a game.** A strict judge compared them against MTG Arena's own screens, and all 23
  passed in both orientations. Rebuilt to match:
  - home with the 3D tavern room;
  - the Play panel and its deck boxes;
  - the queue and the custom table as an event page;
  - Decks and the deck builder (Done and Play at the foot), and the import screen;
  - Options with Gameplay, Sound Lab and phase stops;
  - the Inbox, Downloads, Profile, Ranked, Friends and How to Play.

  Panels open below the top bar, and edge drawers slide in from the side. The top bar lights the icon of the open
  panel. Taglines and helper text are cut, under the new AGENTS.md rule.
- **Logo:** the app icon and the launch screen use the borderless brass M mark (card and sparkle) from the Arena top
  bar. The ring is gone.
- **Deck links:** an Archidekt or Moxfield link with `?utm…` or other query strings, or with a `#fragment`, now imports
  (iOS and Android).
- **Hearth board (the original mode):**
  - in landscape, the zone pop-over scrolls to every row;
  - the TURN labels count rounds, not each player's turn (turn 9 was really round 5). The spectator line counts rounds
    too, and so do Android's labels on main (estimated from the players still in).
- **Deck Studio upright:** chapters fill the visible page above the Done/Play bar, so a short Ideas page no longer
  scrolls its source picker under the tabs.
- UI tests and scripted runs mute audio. A stalled host audio device blocked launch.

## Release
- **Source:** `codex/ios-build-56` at `fed9c5f3`: `claude/arena-mode` (main with build 55's records, plus `af74fd47`
  and `4f8b950e`) and the build-number prepare. Preflight native decision `equivalent-source`
  (`prepare_ios_app_native.py --verify-installed` exit 0). Xcode 27.1.
- **Run:** `ios-0.1.1-56`, fingerprint `c1fd09d1…`, delivery `9ee7aee4…`, IPA `61f13199…`. Two guarded resumes:
  upload, then distribution to Internal and External.

## Verification
- **Preflight `ios-fast`:** 14/14, no source drift. The first run caught the spectator golden, which still expected
  the engine's turn count. It was fixed on both platforms (`4f8b950e`) and rerun.
- **Unit tests:** iOS parity goldens 13/13; the link importer on iOS; Android `:core:test`; Android
  `:app:compileDebugKotlin`.
- **UI tests on the iPhone 17 Pro Max simulator:**
  - a broad run on the judged source: 57 pass;
  - its 4 failures were fixed and rerun: ArenaDecks card halves, invalid import, PinnedTabs Ideas/Analysis and the
    landscape deck builder;
  - then presentation-smoke, invalid import and the deck filter.
- The simulator cannot run the engine, and the menus don't touch it.
- **Still to check on Caleb's iPhone:** the new icon and launch mark, a share-link Archidekt import, the Hearth
  landscape pop-over and the round count, and the menus on a real device.
