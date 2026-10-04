# iOS 0.1.1 build 27: the Walnut Tavern everywhere, spell moments, How to Play, iPad

Apple reports build `0b565a3f-489b-4c75-9cd8-7074d6323624` as `VALID`, with Beta App Review `APPROVED`, in the Internal (all builds) and External (added) groups, on October 4, 2026 UTC. The External invitation remains https://testflight.apple.com/join/2mSHE8rZ. This is the first build that installs on iPad. None of this proves anything on a physical iPhone or iPad.

## Changes ([#105](https://github.com/ineedsomesleep5/MagicMobile/pull/105))
- **Spell moment:** every cast on the tavern table is the framed card in its colour's light with a parchment ribbon; an opponent's ribbon names the caster. Instants and sorceries wear a new parchment scroll frame. The commander keeps its larger moment. The turn banner and a cast take turns, and the tavern flashes its phase plate instead of a pill.
- **Menus and sheets:** Updates, Friends, Downloads and chat in leather and parchment; What's new covers builds 23–27; wax-seal close buttons carry a gold X; the lobby and Deck Studio tiles mention the deck check only when a deck needs fixes; tavern menus near the bottom of the screen open upward.
- **Icon and launch:** the carved walnut frame icon (Caleb's pick of four) at every iPhone and iPad size; the launch screen is the M in a brass ring on walnut.
- **How to Play:** a chooser and two animated tutorials built from the table's pieces: *How MagicMobile works* (12 pages) and *Commander basics* (9 pages). The first visit opens the first.
- **Board:** stack tray picture of the top card, leather opponent hand backs, no status bar during a tavern game, and crowded creature rows that share both rows instead of running off the edge.
- **iPad:** landscape only, full screen, on its own rendered table (`tavern_layout.json` "pad", `TavernSockets.pad`), with controls 1.3× and cards a third larger.
- **Accessibility:** the drawn board layers no longer sit over every card for VoiceOver.

## Verification
- **Signed source:** `codex/ios-build-27` at `63ce186`: #105's branch plus the build-27 bump and the iPad icon sizes.
- **`ios-fast` preflight:** passed 14/14. The native decision is `equivalent-source` with `ad2e8c3`.
- **Engine:** the build 21 engine, re-staged from `verified-native-10945664948`; `libmmengine.a` SHA-256 `466597b2…9753`, unchanged.
- **Tests:** all 936 iOS unit and UI tests ran; the 36 failures (32 pre-dating this build, on build 26 code too) were fixed and every affected class re-ran green. iPad checked on the iPad mini simulator.
- **First attempt:** run `ios-0.1.1-27` failed Apple validation (90023, missing 152/167 px iPad icons) before upload; App Store Connect still listed 26. The fixed build ran as `ios-0.1.1-27b` with the same build number.
