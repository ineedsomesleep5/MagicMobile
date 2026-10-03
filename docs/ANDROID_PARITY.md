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
| OnDeviceRootView.swift, BrandUI.swift, BrandMarkPaths.swift, MultiplayerD20View.swift, OnDeviceStartingRoll.swift | app `ondevice/`, `ui/BrandUI.kt`, `ui/D20Die.kt` | Ported |
| OnDeviceMultiplayer.swift, RelayTransport.swift (GameKitTransport has no Android counterpart) | app `ondevice/OnDeviceMultiplayer.kt`, `ondevice/RelayTransport.kt` | Ported; relay tables only |
| DeckStudio/*, DeckLibrary.swift, OnDeviceDeckEditing.swift, NativeDeckMetadataCatalogue.swift, OnDeviceDeckResolver.swift, OnDeviceDeckLinkImporter.swift | core `studio/`, app `studio/` | Ported (37 iOS tests ported) |
| NativeDownloadsView.swift | app `ondevice/NativeDownloadsView.kt` (Android's download engine and service) | Ported |

## Next: Walnut Tavern (iOS builds 23–25)

Caleb (2026-10-02): once iOS build 25 ships, Android follows this update. Nothing below is ported yet;
Android is on the classic board. Port in this order so each step can be checked against iOS previews
(`MAGICMOBILE_DESIGN_PREVIEW`, both orientations, `-magicmobile.boardAppearance tavern`).

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
   icons, no words), `TavernPlayerStatusPanel`, `TavernOpponentSwap`, `TavernStatusGlance`.
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
