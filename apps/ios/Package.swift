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
                      "GameBoardLayoutMetrics.swift", "GameBoardPreviewFixtures.swift",
                      "GameBoardScreen.swift", "GameBoardTheme.swift", "GameBoardZones.swift",
                      "MagicMobileApp.swift", "OnDeviceRootView.swift", "NativeEngine-Bridging-Header.h"],
            sources: ["OnDeviceAppConfiguration.swift", "Models.swift", "MagicMobileAPI.swift", "PromptCommandBuilder.swift", "PreconCatalog.swift", "OnDeviceDeckResolver.swift", "OnDeviceSnapshotAdapter.swift", "OnDevicePromptAdapter.swift", "OnDeviceMultiplayer.swift", "OnDeviceSession.swift", "OnDeviceRuntimeManager.swift", "OnDeviceBackendRegistration.swift", "OnDeviceMessageLog.swift", "OnDeviceDiagnostics.swift"],
            resources: [.copy("Resources/ondevice-catalogue.json")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "OnDevicePresentationTests",
            dependencies: ["MagicMobile"],
            path: "MagicMobileTests",
            exclude: ["MagicMobileTests.swift", "OnDeviceBoardIdentityTests.swift", "OnDeviceDeckPersistenceTests.swift"],
            sources: ["OnDeviceAppConfigurationTests.swift", "OnDeviceModelTests.swift", "OnDeviceSnapshotAdapterTests.swift", "OnDevicePromptAdapterTests.swift", "OnDeviceMultiplayerTests.swift", "OnDeviceSessionTests.swift", "OnDeviceDeckResolverTests.swift", "OnDeviceBackendRegistrationTests.swift", "OnDeviceMessageLogTests.swift", "OnDeviceMessageSessionTests.swift", "OnDeviceDiagnosticsTests.swift"],
            resources: [.copy("Fixtures/OnDevice")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
