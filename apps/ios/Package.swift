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
            exclude: ["Assets.xcassets", "Info.plist", "PrivacyInfo.xcprivacy", "MagicMobile.entitlements", "ContentView.swift", "DeckLibrary.swift",
                      "GameBoardDesignTokens.swift", "GameBoardInteractionState.swift",
                      "GameBoardLayoutMetrics.swift", "BattlefieldViewportMetrics.swift", "GameBoardPreviewFixtures.swift", "HandCardPan.swift", "BoardCardChoiceView.swift",
                      "GameBoardScreen.swift", "GameBoardTheme.swift", "GameBoardZones.swift",
                      "MagicMobileApp.swift", "OnDeviceRootView.swift", "NativeDeckLibraryView.swift", "NativeDeckComponents.swift", "NativeEngine-Bridging-Header.h",
                      "DeckStudio/Builder", "DeckStudio/Ideas", "DeckStudio/Import", "DeckStudio/Library", "DeckStudio/DeckStudioDesignTokens.swift"],
            sources: ["CardChoicePlan.swift", "NativeArtworkBackgroundQueue.swift", "NativeArtworkCatalogue.swift", "DeckStudio/Core", "DeckStudio/Services", "GameLogPresentation.swift", "BattlefieldAdaptiveSizing.swift", "NativeDeckEDHREC.swift", "NativeDeckMetadataCatalogue.swift", "OnDeviceAppConfiguration.swift", "Models.swift", "MagicMobileAPI.swift", "PromptCommandBuilder.swift", "PreconCatalog.swift", "OnDeviceDeckResolver.swift", "OnDeviceDeckEditing.swift", "OnDeviceDeckLinkImporter.swift", "NativeDeckArtwork.swift", "NativeAssetDownloads.swift", "OnDeviceSnapshotAdapter.swift", "OnDevicePromptAdapter.swift", "OnDeviceMultiplayer.swift", "OnDeviceSession.swift", "OnDeviceRuntimeManager.swift", "OnDeviceBackendRegistration.swift", "OnDeviceMessageLog.swift", "OnDeviceDiagnostics.swift", "PortraitInteractionPolicy.swift", "OnDeviceYieldPolicy.swift", "BoardZoneReference.swift"],
            resources: [.copy("Resources/ondevice-catalogue.json")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "OnDevicePresentationTests",
            dependencies: ["MagicMobile"],
            path: "MagicMobileTests",
            exclude: ["DeckStudioEditorModelTests.swift", "EngineChecks", "MagicMobileTests.swift", "OnDeviceBoardIdentityTests.swift", "OnDeviceDeckPersistenceTests.swift", "NativeDeckPresentationTests.swift", "PortraitPolishTests.swift"],
            sources: ["CardChoicePlanTests.swift", "NativeArtworkBackgroundQueueTests.swift", "NativeArtworkCatalogueTests.swift", "DeckStudioCompletionTests.swift", "DeckStudioCoreTests.swift", "DeckStudioReplayTests.swift", "GameLogPresentationTests.swift", "BattlefieldAdaptiveSizingTests.swift", "NativeDeckEDHRECTests.swift", "NativeDeckMetadataCatalogueTests.swift", "OnDeviceAppConfigurationTests.swift", "OnDeviceModelTests.swift", "OnDeviceSnapshotAdapterTests.swift", "OnDevicePromptAdapterTests.swift", "OnDeviceMultiplayerTests.swift", "OnDeviceSessionTests.swift", "OnDeviceReadinessRegressionTests.swift", "OnDeviceSessionLifecycleTests.swift", "OnDeviceDeckResolverTests.swift", "OnDeviceDeckEditingTests.swift", "OnDeviceDeckLinkImporterTests.swift", "NativeDeckArtworkTests.swift", "NativeAssetDownloadsTests.swift", "OnDeviceBackendRegistrationTests.swift", "OnDeviceMessageLogTests.swift", "OnDeviceMessageSessionTests.swift", "OnDeviceDiagnosticsTests.swift", "PortraitInteractionPolicyTests.swift", "OnDeviceYieldPolicyTests.swift", "BoardZoneReferenceTests.swift"],
            resources: [.copy("Fixtures/OnDevice")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
