// swift-tools-version: 6.0
import PackageDescription

// Portable presentation checks only. This is not the signed iOS app target.
let package = Package(
    name: "MagicMobilePresentationChecks",
    platforms: [.macOS(.v14), .iOS(.v17)],
    dependencies: [.package(path: "../../packages/ondevice-engine/swift")],
    targets: [
        .target(
            name: "MagicMobile",
            dependencies: [.product(name: "MagicMobileOnDevice", package: "swift")],
            path: "MagicMobile",
            exclude: ["Assets.xcassets", "Info.plist", "PrivacyInfo.xcprivacy", "MagicMobile.entitlements", "Board", "Menus",
                      "GameBoardDesignTokens.swift", "GameBoardInteractionState.swift",
                      "GameBoardLayoutMetrics.swift", "BattlefieldViewportMetrics.swift", "GameBoardPreviewFixtures.swift", "HandCardPan.swift", "BoardCardChoiceView.swift",
                      "GameBoardScreen.swift", "GameBoardTheme.swift", "GameBoardZones.swift",
                      "MagicMobileApp.swift", "BoardFXOverlay.swift", "BoardFXShaders.metal", "Grimoire/PageCurl.metal", "Resources/BoardFX", "Resources/Grimoire", "OnDeviceRootView.swift", "MultiplayerD20View.swift", "StartingRollTableView.swift", "Resources/D20", "NativeDeckComponents.swift", "NativeEngine-Bridging-Header.h",
                      "DeckStudio/Builder", "DeckStudio/Ideas", "DeckStudio/Import", "DeckStudio/Library", "DeckStudio/DeckStudioDesignTokens.swift"],
            sources: ["ArenaBoardModel.swift", "DeckLibrary.swift", "CardChoicePlan.swift", "CardPrinting.swift", "CardArtChoices.swift", "CustomCardArt.swift", "NativeArtworkBackgroundQueue.swift", "NativeArtworkCatalogue.swift", "DeckStudio/Core", "DeckStudio/Services", "GameLogPresentation.swift", "BattlefieldAdaptiveSizing.swift", "NativeDeckEDHREC.swift", "NativeDeckMetadataCatalogue.swift", "OnDeviceAppConfiguration.swift", "Models.swift", "PromptCommandBuilder.swift", "PreconCatalog.swift", "OnDeviceDeckResolver.swift", "OnDeviceDeckEditing.swift", "OnDeviceDeckLinkImporter.swift", "NativeDeckArtwork.swift", "NativeAssetDownloads.swift", "OnDeviceSnapshotAdapter.swift", "OnDevicePromptAdapter.swift", "OnDeviceMultiplayer.swift", "OnDeviceStartingRoll.swift", "StartingRollDice.swift", "OnDeviceStartingPlayerChoice.swift", "OnDeviceSession.swift", "OnDeviceRuntimeManager.swift", "OnDeviceBackendRegistration.swift", "OnDeviceMessageLog.swift", "OnDeviceDiagnostics.swift", "FreezeLog.swift", "PortraitInteractionPolicy.swift", "OnDeviceYieldPolicy.swift", "BoardZoneReference.swift", "BoardEventTimeline.swift", "BoardCardPresentation.swift", "GameResume.swift", "GameStats.swift", "HowToPlay.swift", "GuidedGame.swift", "Lessons.swift", "TableChat.swift", "TableLeaveRules.swift", "AppConfig.swift", "VoiceChatRules.swift", "TurnClock.swift", "ComboLoop.swift", "PlayerAccount.swift", "PerformanceAwareness.swift", "Ranked/CommanderBrackets.swift", "Ranked/RankLadder.swift", "Ranked/AIDeckPool.swift", "Ranked/PlayerRecord.swift", "Ranked/ProfileAnalytics.swift", "Ranked/GameUploader.swift", "Ranked/SocialFixtures.swift", "Ranked/RankedQueue.swift", "Ranked/FriendChallenges.swift", "Ranked/FriendMessages.swift"],
            resources: [.copy("Resources/ondevice-catalogue.json")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "OnDevicePresentationTests",
            dependencies: ["MagicMobile"],
            path: "MagicMobileTests",
            exclude: ["DeckStudioEditorModelTests.swift", "EngineChecks", "MagicMobileTests.swift", "OnDeviceBoardIdentityTests.swift", "OnDeviceDeckPersistenceTests.swift", "NativeDeckPresentationTests.swift", "PortraitPolishTests.swift"],
            sources: ["ArenaBoardModelTests.swift", "CardChoicePlanTests.swift", "ComboLoopTests.swift", "FriendMessagesTests.swift", "PerformanceAwarenessTests.swift", "CardPrintingTests.swift", "CardArtChoicesTests.swift", "TokenDownloadCoverageTests.swift", "NativeArtworkBackgroundQueueTests.swift", "NativeArtworkCatalogueTests.swift", "DeckStudioCompletionTests.swift", "DeckStudioCoreTests.swift", "DeckStudioPlaySelectionTests.swift", "DeckStudioPreflightTests.swift", "DeckStudioReplayTests.swift", "GameLogPresentationTests.swift", "BattlefieldAdaptiveSizingTests.swift", "NativeDeckEDHRECTests.swift", "NativeDeckMetadataCatalogueTests.swift", "OnDeviceAppConfigurationTests.swift", "OnDeviceModelTests.swift", "OnDeviceSnapshotAdapterTests.swift", "OnDevicePromptAdapterTests.swift", "OnDeviceMultiplayerTests.swift", "OnDeviceStartingRollTests.swift", "StartingRollDiceTests.swift", "OnDeviceStartingPlayerChoiceTests.swift", "OnDeviceSessionTests.swift", "OnDeviceReadinessRegressionTests.swift", "OnDeviceSessionLifecycleTests.swift", "OnDeviceDeckResolverTests.swift", "OnDeviceDeckEditingTests.swift", "OnDeviceDeckLinkImporterTests.swift", "NativeDeckArtworkTests.swift", "NativeAssetDownloadsTests.swift", "OnDeviceBackendRegistrationTests.swift", "OnDeviceMessageLogTests.swift", "OnDeviceMessageSessionTests.swift", "OnDeviceDiagnosticsTests.swift", "FreezeLogTests.swift", "PortraitInteractionPolicyTests.swift", "OnDeviceYieldPolicyTests.swift", "RankedStandingTests.swift", "BoardZoneReferenceTests.swift", "BoardEventTimelineTests.swift", "ParityGoldenTests.swift", "BoardCardPresentationTests.swift", "GameResumeTests.swift", "HowToPlayTests.swift", "GuidedGameTests.swift", "LessonsTests.swift", "TableChatTests.swift", "TableLeaveRulesTests.swift", "AppConfigTests.swift", "VoiceChatRulesTests.swift", "TurnClockTests.swift", "ProfileAnalyticsTests.swift", "GameUploaderTests.swift", "PrivacyManifestTests.swift", "DeckSyncTests.swift", "LawsTests.swift"],
            resources: [.copy("Fixtures/OnDevice")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
