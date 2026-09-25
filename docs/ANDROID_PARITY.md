# Android parity with iOS

Caleb resumed Android on 2026-09-24. The goal: the native Compose app matches the iOS app
screen for screen, and Android and iPhone players can play each other online.

This document is the handoff. Each iOS source maps to a Kotlin file with the same name, so an
iOS change has one obvious Android counterpart. Update the table and the log before stopping.

## How the port is organized

- **Game logic** (no Android dependencies, JVM-tested) lives in `apps/android/core/src/main/kotlin/io/magicmobile/android/game/`.
- **Screens** (Compose) live in `apps/android/app/src/main/java/io/magicmobile/android/`,
  under `ui/` (theme, icons, shared controls), `board/` (the game), `menu/` (home, setup,
  settings, Sound Lab, downloads), `studio/` (deck library and Deck Studio) and `session/`
  (engine session, runtime, multiplayer).
- **Shared assets** come from the iOS app at build time: the card catalogue and precons
  (`prepare_assets.py`), artwork PNGs (`prepareBrandAssets`), audio (`prepare_audio.py`, which
  rewrites CAF as WAV) and ability icons (`svg_to_vector.py`, committed output).
- **Fonts:** Apple's fonts cannot ship on Android. Inter stands in for SF Pro, Source Serif 4
  for New York (`design: .serif`) and Nunito for SF Rounded. OFL licences are in `assets/licenses/`.
- **Icons:** `ui/SfSymbols.kt` maps every SF Symbol the iOS app uses to a Material icon, and draws
  the three with no Material counterpart (crown, skull, sparkle).

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
| OnDeviceSnapshotAdapter.swift | core `game/OnDeviceSnapshotAdapter.kt` | Ported, parity goldens pass |
| OnDevicePromptAdapter.swift | core `game/OnDevicePromptAdapter.kt` | Ported, parity goldens pass |
| OnDeviceMessageLog.swift, OnDeviceYieldPolicy.swift | core `game/` same names | Ported |
| GameBoardInteractionState.swift, PortraitInteractionPolicy.swift, PromptCommandBuilder.swift | core `game/BoardInteraction.kt` | Ported |
| BattlefieldViewportMetrics.swift, ArenaBoardPresentation.swift (logic) | core `game/BoardLayout.kt` | Ported |
| ContentView.swift (rules: compact prompt, payment, guidance, combat, row planners, hand fan) | core `game/BoardPresentation.kt` | Ported |
| GameBoardTheme.swift, GameBoardDesignTokens.swift, MagicPalette, BrandTheme | app `ui/Theme.kt` | Ported |
| OnDeviceSession.swift | app `session/OnDeviceSession.kt` | Next |
| ContentView.swift (NativeGameView and board views) | app `board/` | Next |
| BoardFXOverlay.swift, BoardEventTimeline.swift | app `board/BoardFXOverlay.kt`, core `game/BoardEventTimeline.kt` | To do |
| BoardCardChoiceView.swift, CardChoicePlan.swift | app `board/BoardCardChoiceView.kt`, core `game/CardChoicePlan.kt` | To do |
| OpeningHandOverlay.swift, GameStats.swift, GameEmotes.swift, PlayerPortrait.swift | app `board/` | To do |
| GameLogPresentation.swift | core `game/GameLogPresentation.kt` | To do |
| GameAudio.swift, SoundLabView.swift | app `ui/GameAudio.kt`, `menu/SoundLabView.kt` | To do |
| OnDeviceRootView.swift, BrandUI.swift, BrandMarkPaths.swift, MultiplayerD20View.swift, OnDeviceStartingRoll.swift | app `menu/` | To do |
| OnDeviceMultiplayer.swift, GameKitTransport.swift | app `session/OnDeviceMultiplayer.kt` plus the relay transport | To do |
| NativeDeckLibraryView.swift, DeckLibrary.swift, DeckStudio/* | app `studio/` | To do |
| NativeDownloadsView.swift, NativeAssetDownloads.swift | app `menu/` (existing Android artwork store) | To do |

## Log

- 2026-09-24 (Claude): Started. Engine client, model, adapters, message log, yield policy and
  board rules ported; iOS/Android parity goldens pass for all 13 real engine fixtures and 12
  synthetic prompt cases. Theme, fonts, icons, shared artwork and audio staging added. Android
  native engine rebuilt from main (run 36091168558) with the build 19 engine (concede).
