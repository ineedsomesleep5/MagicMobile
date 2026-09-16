import Foundation
import XCTest
@testable import MagicMobile

final class OnDeviceAppConfigurationTests: XCTestCase {
    func testLinkedBuildAlwaysSelectsEmbeddedEngine() {
        for debug in [true, false] {
            for args in [[], ["--ondevice-setup-ui-test"], ["--legacy-server"]] {
                XCTAssertEqual(OnDeviceAppConfiguration.select(engineLinked: true, debug: debug, arguments: args), .embedded)
            }
        }
    }

    func testUnlinkedReleaseNeverUsesRemoteClientOrTestArguments() {
        for args in [[], ["--ondevice-setup-ui-test"], ["--legacy-server"]] {
            XCTAssertEqual(OnDeviceAppConfiguration.select(engineLinked: false, debug: false, arguments: args), .engineMissing)
        }
        XCTAssertEqual(OnDeviceAppConfiguration.select(engineLinked: false, debug: true, arguments: []), .referencePreview)
        XCTAssertEqual(OnDeviceAppConfiguration.select(engineLinked: false, debug: true, arguments: ["--ondevice-setup-ui-test"]), .setupPreview)
    }

    func testSetupDefaultsAreValidIncludedDecks() {
        let ids = Set(PreconCatalog.all.map { "precon:\($0.id)" })
        let aiIDs = PreconCatalog.all.map(\.id)
        XCTAssertTrue(ids.contains(OnDeviceSetupPreferences.defaultDeckID))
        XCTAssertTrue(aiIDs.contains(OnDeviceSetupPreferences.defaultAIDeckID))
        let selection = OnDeviceSetupPreferences.normalize(.init(deckID: "", aiDeckID: "", aiOpponents: 1, humanPlayers: 2, friends: false), deckIDs: ids, aiDeckIDs: aiIDs)
        XCTAssertEqual(selection.deckID, OnDeviceSetupPreferences.defaultDeckID)
        XCTAssertEqual(selection.aiDeckID, OnDeviceSetupPreferences.defaultAIDeckID)
    }

    func testSelectedImportedDeckAndOpponentOptionsSurviveNewDefaultsInstance() throws {
        let suite = "MagicMobile.preferences.test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let expected = OnDeviceSetupPreferences.Selection(deckID: "local:saved-deck", aiDeckID: "ai-2", aiOpponents: 3, humanPlayers: 4, friends: true)
        OnDeviceSetupPreferences.save(expected, to: defaults)
        let reopened = try XCTUnwrap(UserDefaults(suiteName: suite))
        let actual = OnDeviceSetupPreferences.read(from: reopened, deckIDs: ["local:saved-deck"], aiDeckIDs: ["ai-1", "ai-2"])
        XCTAssertEqual(actual, expected)
        XCTAssertNil(defaults.object(forKey: "matchID"))
        XCTAssertNil(defaults.object(forKey: "nativeHandle"))
    }

    func testDeletedDecksAndOutOfRangePreferencesRecoverDeterministically() {
        let saved = OnDeviceSetupPreferences.Selection(deckID: "local:deleted", aiDeckID: "removed", aiOpponents: Int.max, humanPlayers: Int.min, friends: true)
        let normalized = OnDeviceSetupPreferences.normalize(saved, deckIDs: ["precon:z", "precon:a"], aiDeckIDs: ["ai-z", "ai-a"])
        XCTAssertEqual(normalized.deckID, "precon:a")
        XCTAssertEqual(normalized.aiDeckID, "ai-z")
        XCTAssertEqual(normalized.aiOpponents, 3)
        XCTAssertEqual(normalized.humanPlayers, 2)
        XCTAssertTrue(normalized.friends)
        let empty = OnDeviceSetupPreferences.normalize(saved, deckIDs: [], aiDeckIDs: [])
        XCTAssertEqual(empty.deckID, "")
        XCTAssertEqual(empty.aiDeckID, "")
    }
}
