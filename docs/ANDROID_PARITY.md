# Android parity with iOS

Caleb resumed Android on 2026-09-24. The goal: the native Compose app matches the iOS app
screen for screen, and Android and iPhone players can play each other online.

This document is the handoff. Each iOS source maps to a Kotlin file with the same name, so an
iOS change has one obvious Android counterpart. Update the table and the log before stopping.

## How the port is organized

- **Game logic** (no Android dependencies, JVM-tested) lives in `apps/android/core/src/main/kotlin/io/magicmobile/android/game/`,
  and Deck Studio's logic in `core/.../studio/`.
- **Screens** (Compose) live in `apps/android/app/src/main/java/io/magicmobile/android/`: `ui/` (theme, icons,
  iOS-style controls), `board/` (the game, portrait and landscape), `ondevice/` (menu, setup, starting roll,
  downloads, the engine runtime, multiplayer and the relay), `studio/` (Deck Studio) and `session/` (the
  engine session).
- **Shared assets** come from the iOS app at build time: the card catalogue, printing index and precons
  (`prepare_assets.py`), artwork PNGs (`prepareBrandAssets`), audio (`prepare_audio.py`, which rewrites CAF
  as WAV) and ability icons (`svg_to_vector.py`, committed output).
- **Fonts:** Apple's fonts cannot ship on Android. Inter stands in for SF Pro, Source Serif 4 for New York
  (`design: .serif`) and Nunito for SF Rounded, with widths fitted to CoreText (`AppleFontMetrics`). OFL
  licences are in `assets/licenses/`.
- **Icons:** `ui/SfSymbols.kt` maps every SF Symbol the iOS app uses to a Material icon, and draws the few
  with no Material counterpart (crown, skull, sparkle).
- **Cross-play:** iPhone and Android tables go through the relay in `services/table-relay` (a Cloudflare
  Worker). Both apps speak the unchanged multiplayer protocol over it; see that README.

## Parity checks

- `ParityGoldenTests.swift` (iOS) writes what the iOS adapters produce for every real engine
  fixture in `apps/ios/MagicMobileTests/Fixtures/OnDevice` plus the synthetic prompt cases in
  `apps/android/core/src/test/resources/parity/prompt-cases.json`. `ParityGoldenTest.kt`
  requires the Android port to produce identical summaries. After an intended iOS change:
  `MAGICMOBILE_WRITE_PARITY_GOLDENS=1 swift test --package-path apps/ios --filter ParityGoldenTests`,
  commit the goldens, then port the change until `gradle -p apps/android :core:test` passes.
- Visual: the iOS DEBUG board fixtures (`MAGICMOBILE_DESIGN_PREVIEW=<state>`) are ported to
  Android with the same state names, so both apps can be screenshotted side by side.

## iOS → Android map

| iOS source | Android | Status |
| --- | --- | --- |
| MagicMobileOnDevice/EngineClient.swift, JSONValue.swift | core `game/EngineClient.kt`, `game/Json.kt` | Ported |
| MagicMobileOnDevice/HostRouter.swift, PacketChunks.swift | core `game/HostRouter.kt` | Ported (same wire format) |
| Models.swift | core `game/Models.kt` | Ported (server-only types omitted) |
| OnDeviceSnapshotAdapter.swift, OnDevicePromptAdapter.swift | core `game/` same names | Ported, parity goldens pass |
| OnDeviceMessageLog.swift, OnDeviceYieldPolicy.swift | core `game/` same names | Ported |
| GameBoardInteractionState.swift, PortraitInteractionPolicy.swift, PromptCommandBuilder.swift | core `game/BoardInteraction.kt` | Ported |
| BattlefieldViewportMetrics.swift, ArenaBoardPresentation.swift (logic) | core `game/BoardLayout.kt` | Ported |
| ContentView.swift (rules: compact prompt, payment, guidance, combat, row planners, hand fan) | core `game/BoardPresentation.kt` | Ported |
| GameBoardTheme.swift, GameBoardDesignTokens.swift, MagicPalette, BrandTheme | app `ui/Theme.kt` | Ported |
| OnDeviceSession.swift | app `session/OnDeviceSession.kt` | Ported |
| ContentView.swift NativeGameView (portrait board) | app `board/NativeGameView.kt`, `board/PortraitBoard.kt` and siblings | Ported |
| ContentView.swift NativeGameView (landscape board) | app `board/LandscapeBoard.kt` | Ported |
| BoardFXOverlay.swift, BoardEventTimeline.swift | app `board/BoardFXOverlay.kt`, core `game/BoardEventTimeline.kt` | Ported |
| BoardCardChoiceView.swift, CardChoicePlan.swift | app `board/CardChoiceView.kt`, core `game/CardChoicePlan.kt` | Ported |
| OpeningHandOverlay.swift, GameStats.swift, GameEmotes.swift, PlayerPortrait.swift | app `board/` | Ported |
| GameLogPresentation.swift | core `game/GameLogPresentation.kt` | Ported |
| GameAudio.swift, SoundLabView.swift | app `ui/GameAudio.kt`, `board/SettingsViews.kt` | Ported |
| OnDeviceRootView.swift, BrandUI.swift, BrandMarkPaths.swift, MultiplayerD20View.swift, OnDeviceStartingRoll.swift | app `ondevice/`, `ui/BrandUI.kt` | Ported |
| StartingRollDice.swift, StartingRollTableView.swift (the 3D starting roll, docs/STARTING_ROLL.md) | `ondevice/StartingRollDice.kt`, `ondevice/StartingRollTable.kt` (Filament instead of SceneKit), `ui/D20Math.kt` | Ported |
| OnDeviceMultiplayer.swift, RelayTransport.swift (GameKitTransport has no Android counterpart) | app `ondevice/OnDeviceMultiplayer.kt`, `ondevice/RelayTransport.kt` | Ported; relay tables only |
| DeckStudio/*, DeckLibrary.swift, OnDeviceDeckEditing.swift, NativeDeckMetadataCatalogue.swift, OnDeviceDeckResolver.swift, OnDeviceDeckLinkImporter.swift | core `studio/`, app `studio/` | Ported (37 iOS tests ported) |
| NativeDownloadsView.swift | app `ondevice/NativeDownloadsView.kt` (Android's download engine and service) | Ported |
| BoardChrome.swift Tavern* views, BrandUI.swift tavern controls and TavernAppearance | app `ui/TavernKit.kt` (new), `ui/BrandUI.kt`, `ui/IosControls.kt`, `ui/Theme.kt` | Ported (Walnut Tavern) |
| TavernDesign, TavernSockets, TavernFrameKind, TavernCardParts, BattlefieldTokenStack, PlayerStatusSummary | core `game/TavernSockets.kt` (new) | Ported, same numbers as `scripts/brand/tavern_layout.json` |
| PortraitBoardViews.swift and GameplayActionDock.swift tavern pieces (medallions, phase plate, card-back fan, mana gems, pass disc, rings, stack tray, status pop-over) | app `board/TavernBoardViews.kt` (new), `board/HudViews.kt`, `board/CommandBar.kt` | Ported |
| NativeGameView.tavernLandscapeContent | app `board/LandscapeBoard.kt` (`LandscapeCenterColumn`) | Ported |
| GuidedGame.swift, GuidedGameViews.swift (the guided first game: coach notes, first-launch welcome) | core `game/GuidedGame.kt`, app `ui/GuidedGameViews.kt` | Ported; rules and words checked by `guided-game-cases.json` |
| Menus/ArenaMenuKit.swift (ArenaMenuStyle, ArenaButtonFace and its styles, ArenaTopBar, controls, backdrops) | app `menus/ArenaMenuKit.kt`; rules in core `game/ArenaMenus.kt` | Ported (phase A) |
| Menus/ArenaPanels.swift (arenaPanel, ArenaPanelHeader, ArenaOptionsView, ArenaPromptPanel) | app `menus/ArenaPanels.kt` | Ported (phase A); Options pages reuse the Android settings pieces |
| Menus/ArenaHomeView.swift, OnDeviceRootView.swift `arenaMenu`/`homeContent` | app `menus/ArenaHomeView.kt`, `ondevice/OnDeviceRootView.kt` | Ported (phase A) |
| Menus/ArenaPlayPanel.swift, Menus/ArenaDeckBox.swift | app `menus/ArenaPlayPanel.kt`, `menus/ArenaDeckBox.kt` | Ported (phase A); no Game Center rows |
| OnDeviceRootView.swift `setupContent`/`setupSeat`/`setupTable`/`setupSeats`/`setupStartBar`, RelayTablePanel, RelayWaitingRoomView, MatchRoomView (the custom table as Arena's event page) | app `ondevice/CustomTableViews.kt`; rules in core `game/ArenaCustomTable.kt` | Ported (phase B); AI and Online tiles only (no Game Center) |
| DeckStudio/Library/DeckStudioRootView.swift, DeckStudioPlayViews.swift, Builder/DeckStudioWorkspaceScreen.swift (`arenaBuilder`), DeckStudioEditorTools.swift, Import/DeckStudioImportScreen.swift, Grimoire/* | app `studio/` same names, `board/BoardMenu.kt`; rules in core `studio/ArenaDecksPage.kt` | Ported (phase B): the Decks tab inside the shell, glass binder parts, curl off |
| Ranked/ProfileView.swift, ProfileVisuals.swift, ProfileHistory.swift, PublicProfileView.swift, RankCeremonyView.swift, RankedHallViews.swift | app `ranked/` (ProfileView.kt new, RankedHallScreen.kt, ProfileVisuals.kt, PublicProfileScreen.kt); rules in core `game/ArenaProfile.kt` | Ported (phase B) |
| FriendsView.swift, Ranked/FriendConversationView.swift, SocialComponents.swift, FriendChallengeViews.swift, AccountSignInCard.swift | app `social/FriendsSheet.kt`, `social/FriendConversation.kt`, `ranked/` | Ported (phase B) |
| NativeUpdateNewsView.swift | app `ondevice/NativeUpdateNewsView.kt`; core `game/UpdateNews.kt` | Ported (Arena inbox, phase B) |
| NativeDownloadsView.swift (Arena readout) | app `ondevice/NativeDownloadsView.kt`; core `game/DownloadReadout.kt` | Ported (phase B) |
| HowToPlayView.swift (Arena pieces), SoundLabView.swift, Menus/ArenaPanels.swift ArenaOptionsView pages | app `ui/HowToPlayView.kt`, `board/SettingsViews.kt`, `menus/ArenaPanels.kt` | Ported (phase B); lesson text unchanged; Board's Table picker, Card Frames and Stop for Removal wait for the Arena board |

## Walnut Tavern (iOS builds 23–26)

Caleb (2026-10-02): once iOS build 25 ships, Android follows this update. Ported on 2026-10-03 on
`codex/android-walnut-tavern` (from `codex/walnut-build-26`), in the order below; Walnut Tavern is the
Android default board. Not yet checked on an emulator or a phone (see the log for the list). Still classic
or system-styled on Android: the game log drawer's contents, the Friends and relay table sheets beyond
their shared controls, How to Play, Deck Studio screens beyond the palette, buttons and toggles, and the
remaining `IosAlert` dialogs. The steps as planned, for reference against iOS previews
(`MAGICMOBILE_DESIGN_PREVIEW`, both orientations, `-magicmobile.boardAppearance tavern`):

1. **Assets** (no code): extend `prepareBrandAssets` to stage from `apps/ios/MagicMobile/Assets.xcassets`:
   `battlefield-tavern-portrait.jpg`, `battlefield-tavern-landscape.jpg`, `menu-backdrop-tavern`, the UI kit
   (`tavern-ui-*`, rendered at 3 px per pt with cap insets in points), the pass button (`tavern-pass-ring`,
   `tavern-pass-flip-00…`, `tavern-hourglass-button`), mana gems (`tavern-mana-*`), card frames
   (`tavern-frame-creature|token|artifact|enchantment|land`), `tavern-card-ribbon`, `tavern-gem-power|toughness`.
   Sources and renderers: `scripts/brand/` (`tavern_table.py` + `tavern_layout.json`, `card_frames.sh`,
   `install_tavern_assets.sh`).
2. **Theme and kit:** `BoardChrome.swift` Tavern* views (TavernFill, TavernBrassFrame, TavernButtonStyle,
   TavernPanelChrome, TavernMenu/TavernMenuItem pop-overs, tavernConfirmation, TavernTag, TavernCoin,
   TavernPhasePlate, TavernStackTray, glows) and `BrandUI.swift` (TavernToggle with subtitle, TavernStepper,
   TavernPicker, TavernSlider, Walnut & Ember palette) → app `ui/TavernKit.kt` (new) and `ui/BrandUI.kt`.
   Serif = Source Serif 4 (already bundled).
3. **Board default and sockets:** Walnut Tavern is the default (`BoardAppearancePreference.defaultValue`).
   `TavernDesign` / `TavernSockets` (portrait and landscape socket points, design canvases 440×956 and
   956×440, orientation-aware mapping) → core `game/TavernSockets.kt`. Keep the numbers identical to
   `tavern_layout.json`.
4. **Portrait tavern board:** `PortraitBoardViews.swift` (opponent nameplate, medallion with zones pop-over,
   card-back fan, phase plate, status glance), `GameplayActionDock.swift` (commander medallion with the
   commander-ready glow, mana gems, flipping pass disc, Skip and controls rings, stack tray),
   `BattlefieldViewportMetrics.swift` (lanes inset to the mat), resting hand fan.
5. **Battlefield tiles:** `ArenaBoardPresentation.swift` — `TavernFrameKind` (gold creature, walnut token,
   silver artifact, rose-gold enchantment, stone land; a current creature of any type is gold),
   `framedFace` (art window per kind, ribbon at 72% height, hex gems), glow-only highlights
   (`TavernTileGlow`), brass coin badges, keyword icons stay icons in combat, attachments as parchment
   ribbons above a full-size creature (`BattlefieldRow.attachmentGroupTile`, `AttachmentNameTab`).
6. **Player status pop-over:** `PlayerStatusSummary`, `TavernStatusBadge` (Phyrexian glyph for poison,
   icons, no words on the board), `TavernPlayerStatusPanel` (a facts line, then each badge with its label in
   words), `TavernOpponentSwap`, `TavernStatusGlance` (your own medallion), and `TavernEffectOrbit` /
   `TavernEffectOrbitBadges`: the opponent's badges curve around their medallion, commander damage first,
   right under the portrait (2026-10-11).
7. **Combat:** blockers stay selectable to take a block back — `OnDevicePromptAdapter.swift` adds the
   viewer's blocking creatures to the blockers SELECT targets (port to core `OnDevicePromptAdapter.kt` and
   add a parity case; test `testDeclaredBlockerRemainsSelectableSoTheBlockCanBeTakenBack`), and the
   banner's Back button (`PromptPill.back`, `NativeGameView.combatBackAction`). Attack arrows end at the
   medallions (`TavernSeatAnchor`).
8. **Board FX:** the tavern commander moment (`BoardFXPainter` tableDim, fireRing, emberStream, fireHalo,
   ribbonBanner with wax seal; framed showcase via `BoardFXFlight.showcaseSize`), brass cast plate, turn band.
9. **Landscape tavern board:** `NativeGameView.tavernLandscapeContent` — the centre column on the landscape
   plate's mat, opponent bar and command bar as full-screen layers on `TavernSockets.landscape`.
10. **Menus and lobby:** Walnut & Ember menus, setup lobby controls, game menu panels, Deck Studio palette.

Parity checks for this work: the existing goldens (adapter change above needs a new case), plus side-by-side
screenshots of `normal-battlefield`, `crowded-battlefield`, `attached-permanents`, `four-player-focus`,
`combat-arrows`, `card-target-prompt` and `board-fx` in both orientations.

## Build 27: the whole table in one style (iOS `codex/walnut-build-27`)

Caleb's brainstorm of 2026-10-03 (docs/BOARD_FX_ROADMAP.md, phase 13). Ported on the same branch on
2026-10-03 (items 1–5 below; item 6, iPad, has no Android tablet counterpart yet). Checked on the
emulator: the spell moment (`board-fx` steps 1–5), the tavern menu sheets, the chooser and both
tutorials, the Updates sheet. `:core:test` 173 and `:app:testDebugUnitTest` 72 pass. The pieces, each
in the same-named Kotlin file:

1. **Spell moment:** `BoardFXOverlay.swift` — on the tavern every `spellCast` (and a showcased
   `enteredBattlefield`) is the framed tile (`BoardFXFlight.showcaseSize` framed for every weight:
   ability 80×86, spell 150×162, big 166×180, commander 180×194), `tableDim(strength:)` at 0.55 (0.75 big,
   none for abilities), `spellHalo` in the tint's colour, and the ribbon banner with the caster's name
   (`BoardFXAnchors.playerLabels`, `casterCaption`) on an opponent's spell. `TavernFrameKind.spell`
   (instants and sorceries, `tavern-frame-spell`, window 0.093/0.164/0.814/0.736). The turn banner waits for
   `BoardFXDirector.centreBusyUntil` and `ingest(holdUntil:)` holds showcases while the banner shows; the
   tavern shows no phase pill (`hudPulse` flashes the plate instead).
2. **Sheets:** `tavernList()` (`TavernListChrome`, `TavernListRow`, `TavernToggleStyle`) on Updates,
   Friends, Downloads and chat; the What's new text for builds 23–27 (`NativeUpdateNewsView.swift`).
3. **Launch screen:** the M in a brass ring on walnut `#1b120b` (LaunchMark 100 pt, `windowSplashScreen*`).
4. **Board polish:** the stack tray's `topCard` thumbnail with the count on a 16 pt coin; the opponent's hand
   backs in leather with an ember spark (`TavernCardBackFan`); no status bar on the tavern board.
5. **How to play:** two tutorials (`HowToPlayText.tutorials`, core `HowToPlay.kt` already carries the words and
   `CONTENT_VERSION` 2; `tutorial-cases.json` has the structure). `HowToPlayView.swift`: the chooser (two
   parchment books, `howToPlay.tutorial.<id>`, `howToPlay.close`), the book (engraved title bar, Skip,
   `howToPlay.chooser` back, brass progress coins, Back/Next/Done plaques) and the scenes
   (`HowToPlayScene` keyed `<tutorial>/<page>`, built from `HowToPlayTile` frames, medallions, the hourglass,
   gems, ribbons, tags and plaques on a shared 30 fps clock; stills with reduced motion). The first visit opens
   the table's tutorial; the menu opens the chooser.
6. **iPad:** `TavernSockets.pad` (1180×860, `tavern_layout.json` "pad", plate `battlefield-tavern-pad` stretched
   to the screen), `CGSize.isTavernPad` (short side ≥ 700). Android tablets: the same map once a tablet is
   in hand.

## Arena board mode (iOS 2026-10-20, Android pending)

The Arena board (`BoardMode.arena`, key `magicmobile.boardMode`, Settings → Board) is iOS only so far. Android still shows Hearth whatever the key says. Port as one piece: `ArenaBoardModel.swift` (layout, hand posture, Auto Pay, combat phase, extra hand; its tests are portable) into core, the views (`Board/ArenaBoardViews.swift`, `ArenaHandFan.swift`, `NativeGameView+Arena*.swift`) into same-named Kotlin files, and the plates come over by name (`tavern-arena-*`).

## Arena menus (iOS 2026-10-22, Android phase A 2026-10-22)

The menus are Arena's on both platforms whatever the board (docs/ARENA_STYLE.md, "Menus"). Android phase A ported the kit,
the panels, the shell (top bar with Home, Profile, Decks, Ranked, Learn over the room), the home page and the Play panel with
its deck boxes. `menus.LocalArenaBoard` is iOS's `\.arenaBoard`: true over the menu shell, the setup screen, Deck Studio and
every panel, so the tavern kit's `TavernButton`, `TavernToggle`, `TavernSlider`, `TavernStepper`, `tavernPanelChrome`,
`TavernSheetBackground` and `TavernMenu` draw Arena's face there; the game never sets it, so the Hearth board is unchanged.
The seven home images come from `home-art-*.imageset` through `prepareBrandAssets` (`R.drawable.home_art_*`).

Phase B (2026-10-22) ported every other page outside a game: the custom table as Arena's event page, Deck Studio as the Decks
tab with Arena's builder, Profile, Ranked and the leaderboard, Friends and Messages, the Updates inbox, Downloads' readout, How
to Play, the Sound Lab and the Options pages. Still to port: the Arena board itself (the home feature "The Arena board" points
at it), and the engine error report, which still opens as a bottom sheet.

## Log

- 2026-09-24 (Claude): Started. Engine client, model, adapters, message log, yield policy and
  board rules ported; iOS/Android parity goldens pass for all 13 real engine fixtures and 12
  synthetic prompt cases. Theme, fonts, icons, shared artwork and audio staging added. Android
  native engine rebuilt from main (run 36091168558) with the build 19 engine (concede).
- 2026-09-25 (Claude): Cross-play relay (services/table-relay, deployed to workers.dev) and both apps'
  relay clients; an Android host and an iPhone simulator guest played a real match through it.
  Deck Studio ported (library, workspace, import, ideas, analysis, playtest history) with its core
  logic and tests; the landscape board and the Downloads sheet ported. Build 7 decks keep their files;
  favourites, tags and notes migrate once to Deck Studio's stores. Remaining differences: font glyph
  shapes (licensed stand-ins), a few borderline text wraps, and no Game Center (relay tables instead).
- 2026-09-26 (Claude): Build 18 / build 9 work, integrated on `codex/build18-integration`.
  Every change landed on both platforms:
  - relay backlog fix (#39)
  - playtest focus (#41) and cards (#43)
  - multiplayer hardening (#42): guest retry, host revision notices, and local crash and hang
    reports, including a new Android `OnDeviceDiagnostics.kt` that ports the iOS export
  - fan-content notice and row overflow badges (#45)
  - combat clarity (#46)
  - an iOS 27 card-choice accessibility fix (#49; Android needed no change)

  New shared JSON cases under `core/src/test/resources/parity/` are read by both platforms'
  tests: `focus-cases`, `spectator-cases` and `combat-cases`.
- 2026-09-26 (Claude): Removed the unreachable build 7 UI: `MagicApp`, `AppModel`, `GameScreen`, the
  dedicated Online client and screen with its `onlineServerUrl` switch, and the editor dialogs, stores and
  helpers only they used. Kept: `DeckStore` (the Deck Studio library and build 7 migration), `CardArtwork`,
  the artwork download engine and service, and `NativeBridge`. Build 7 draft, receipt and playtest files
  stay on the device unread, as in build 8.
- 2026-09-27 (Claude): Build 19 / build 10. Every change landed on both platforms:
  - Deck Studio Play this deck and the builder improvements (#65), with a new shared fixture `parity/deck-studio-cases.json` read by both platforms' parity tests
  - the save/resume app side (#63), with `parity/resume-cases.json`
  - relay extras (#48)
  - singular card counts (#56)

  Android build 10 ships with the engine package restored to `2c32482` (the native library's source), because `verify_native.py` compares the whole package, including the iOS-only Swift wrapper.
- 2026-09-27 (Claude): Android build 11 (versionCode 2026092702) ships resume on a native engine built from `79de39c`. iOS build 20 gets the same engine once its far-calls build finishes; the app-side rules already match through `parity/resume-cases.json`.
- 2026-09-27 (Claude): iOS removed its retired hosted-server client (`ContentView`, `MagicMobileAPI`, the
  cloud deck library and the dead-URL card image fallback), the dormant online client and the engine-less
  DEBUG reference entry point. This matches Android's 2026-09-26 removal; no Android change.
- 2026-09-28 (Claude): Android build 12 ships the same features as iOS build 21, and the shared parity fixtures cover them: resume, deck-studio, token, game-summary and tutorial cases. Android-only fixes: the stuck turn banner (#85) and the save budget (#87).

- 2026-09-28 (Claude): Android build 13 matches iOS build 22: chat, invite links, friends and profiles, and the roll fix. The shared cases are in `parity/chat-cases.json`. Android adds verified app links and a `singleTask` main activity.

- 2026-10-03 (Claude): Walnut Tavern ported to Android on `codex/android-walnut-tavern` (iOS builds 23–26,
  no engine or iOS changes):
  - `prepareBrandAssets` stages the tavern plates, UI kit, pass ring and flip frames, mana gems, card frames,
    ribbon, hex gems, tile glow and menu backdrop into `drawable-nodpi`. The adaptive launcher icon is the iOS
    `AppIcon-1024.png` on walnut.
  - New `ui/TavernKit.kt` and core `game/TavernSockets.kt`. Walnut Tavern is the default board. The portrait and
    landscape plates are drawn to fill the screen, and controls sit on the plate's sockets on any phone shape.
  - Board pieces: framed tiles by type, token piles of 8+, attachment ribbons, glow-only highlights, brass
    coins, the medallion status pop-over with the swap row, the commander-ready glow, combat Back, the
    tavern commander moment and ribbon banners. Menus, settings, the lobby, the fixed landscape main menu and
    Deck Studio's parchment palette are also styled.
  - Adapter: the viewer's blocking creatures stay in the blockers SELECT targets, as on iOS. This adds the
    parity case `blockers-take-back` and Wall of Spears to the `blockers` case. The golden entries were written by hand in
    the iOS format; regenerating them on iOS (`MAGICMOBILE_WRITE_PARITY_GOLDENS=1 swift test --package-path
    apps/ios --filter ParityGoldenTests`) gave no diff.
  - New JVM tests: `TavernSocketsTest`, `declaredBlockerRemainsSelectableSoTheBlockCanBeTakenBack` and
    `commanderCastIsItsOnlyCeremony`. `:core:test` (173) and `:app:testDebugUnitTest` (72) pass.
  - Emulator check (MagicMobile_API35, debug build, design previews): the portrait and landscape boards,
    framed tiles with real art, and the four-player pop-over with its swap row all match iOS.
  - Breathing glows (playable hand cards, floating mana, the commander-ready ring) step on one shared
    20-a-second clock (`rememberBoardBreath` in `BoardSupport.kt`) and are read at draw time where possible.
    The mana gem's blur stays a fixed size. A quiet board used about 105% CPU on the emulator because it
    redrew every frame; it now uses about 45%. With animations off it uses 0.6%.
  - Still to check on a phone:
    - glow feel, the adaptive icon, pop-up menus and the pass-disc flip
    - launch speed (slow on the 8 GB Mac's emulator) and idle battery use
    - landscape status-bar hiding, the hand drop zone, and real display cutouts and insets
    - an online game against an iPhone

## Brackets, Quick Match, Ranked and profiles (2026-10-04, unshipped)

- Same feature as iOS (docs/RANKED.md). Logic in `core/.../game/Ranked.kt` (brackets, ladder, seasons, AI pool,
  stats, achievements, the profile file, the ranked matchmaker); screens in `app/.../ranked/` (`RankedViews.kt`,
  `PlayerRecordStore.kt`). `commander-brackets.json` and `ai-decks.json` reach the assets through
  `scripts/android/prepare_assets.py`; the rank badges and spin frames arrive as `tavern_rank_*` drawables.
- `RankedParityTest` checks `parity/ranked-cases.json` (shared with iOS `RankedParityTests.swift`), the AI decks,
  the record file round trip and the matchmaker. Play now opens the mode chooser; Custom Table is the old setup.
  (2026-10-22: the Arena Play panel replaced the mode chooser, the Quick Match and Ranked screens and the search and
  challenge overlays, as on iOS.)

- 2026-10-22 (Claude): Arena menus, phase A, on top of `claude/arena-mode` (e3b81255). New `menus/` package (ArenaMenuKit,
  ArenaPanels, ArenaHomeView, ArenaPlayPanel, ArenaDeckBox, each named after its iOS file) and core `game/ArenaMenus.kt`
  (tabs, play modes, the plaque's word and action, recently played, deck grid, box geometry, deck colours, home art crop,
  feature turning) with `ArenaMenusTest` (14 tests). The root shows the Arena shell instead of `TavernMainMenu`, and
  Options, Updates, Friends, Downloads, How to Play, the welcome, the bracket and the offline-art question open as glass
  panels (`ArenaPanel`) instead of bottom sheets and dialogs. Removed with their iOS counterparts: `TavernMainMenu`,
  `PlayModeChooser`, `PlayDeckSection`, `QuickMatchScreen`, `RankedLobbyScreen`, `RankedSearchOverlay`,
  `ChallengeWaitingOverlay`, `SupportBanner` and the old Settings sheet. Not yet checked on an emulator: the top bar on a
  360 dp phone, the deck boxes opening (3D lid), the feature panel's swipe, the blade's seam, and every panel's height.
- 2026-10-22 (Claude): Arena menus, phase B, on iOS `claude/arena-mode` 769769a5. Phase A's screens follow that commit (no home
  kicker, "Ranked · <season>", a plain Ranked tile, the countdown on "Play the AI now", "Opponent · <bracket>" or "Opponent ·
  Match my deck", no Friends delete paragraph, progression emblems without a coin ring) and `LocalArenaSafeArea` mirrors
  `\.arenaSafeArea`. New pages: the custom table as an event page inside the shell (`CustomTableViews.kt`, two plates and the
  Start strip, seats as deck boxes with × and "+", `ArenaCustomTableTest`); Deck Studio as the Decks tab with deck boxes and
  the strip, Arena's builder and glass binder parts (`ArenaDecksPageTest`); Profile, Ranked Hall, leaderboard, Friends and
  Messages in glass (`ArenaProfileTest`); the Updates inbox, Downloads' readout, How to Play, the Sound Lab and the Options
  pages (`ArenaInboxTest`). `TavernPicker` and `TavernTextField` draw Arena's glass slot under `LocalArenaBoard`.
  `:core:test`, `:app:compileDebugKotlin` and `:app:testDebugUnitTest` pass (411 tests). Nothing checked on an emulator yet:
  the custom table on a 360 dp phone both ways (plates, × on the seats, the strip over the gesture bar), Deck Studio's box
  lids and scroll offsets, the editor covering the top bar, the 330 dp deck column on a short landscape phone, the profile's
  title/portrait panel (it may sit about 46 dp low), Friends' panel height, the conversation composer with the keyboard,
  the inbox and How to Play heights, and the dark-glass drop-downs.
