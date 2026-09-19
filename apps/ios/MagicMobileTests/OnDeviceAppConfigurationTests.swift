import Foundation
import XCTest
import MagicMobileOnDevice
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
        XCTAssertEqual(selection.aiSkill, 2)
    }

    func testSelectedImportedDeckAndOpponentOptionsSurviveNewDefaultsInstance() throws {
        let suite = "MagicMobile.preferences.test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let expected = OnDeviceSetupPreferences.Selection(deckID: "local:saved-deck", aiDeckID: "ai-2", aiOpponents: 3, humanPlayers: 4, friends: true, aiSkill: 9)
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

    func testAISkillDefaultsCorruptionAndRangeNormalization() throws {
        let suite = "MagicMobile.aiSkill.test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(OnDeviceSetupPreferences.read(from: defaults, deckIDs: [], aiDeckIDs: []).aiSkill, 2)
        for corrupt: Any in ["invalid", true, 2.5, ["skill": 8]] {
            defaults.set(corrupt, forKey: OnDeviceSetupPreferences.aiSkillKey)
            XCTAssertEqual(OnDeviceSetupPreferences.readAISkill(from: defaults), 2)
        }
        for (input, expected) in [(Int.min, 1), (0, 1), (1, 1), (2, 2), (10, 10), (11, 10), (Int.max, 10)] {
            let selection = OnDeviceSetupPreferences.Selection(deckID: "", aiDeckID: "", aiOpponents: 1, humanPlayers: 2, friends: false, aiSkill: input)
            XCTAssertEqual(OnDeviceSetupPreferences.normalize(selection, deckIDs: [], aiDeckIDs: []).aiSkill, expected)
            defaults.set(input, forKey: OnDeviceSetupPreferences.aiSkillKey)
            XCTAssertEqual(OnDeviceSetupPreferences.readAISkill(from: defaults), expected)
            OnDeviceSetupPreferences.save(selection, to: defaults)
            XCTAssertEqual(defaults.integer(forKey: OnDeviceSetupPreferences.aiSkillKey), expected)
        }
    }

    func testEveryAISeatCarriesExactNumericSkillAndHumanNeverDoes() throws {
        let humanDeck = MagicMobileOnDevice.JSONValue.object(["human": .bool(true)])
        let aiDeck = MagicMobileOnDevice.JSONValue.object(["ai": .bool(true)])
        for skill in 1...10 {
            for opponents in 1...3 {
                let seats = try OnDeviceAppConfiguration.aiGameSeats(name: "Player", humanDeck: humanDeck, aiDeck: aiDeck, opponents: opponents, aiSkill: skill)
                XCTAssertEqual(seats.count, opponents + 1)
                XCTAssertEqual(seats[0]["controller"], .string("human"))
                XCTAssertEqual(seats[0]["deck"], humanDeck)
                XCTAssertNil(seats[0]["aiSkill"])
                for (index, seat) in seats.dropFirst().enumerated() {
                    XCTAssertEqual(seat["seatId"], .string("player\(index + 2)"))
                    XCTAssertEqual(seat["controller"], .string("ai"))
                    XCTAssertEqual(seat["deck"], aiDeck)
                    XCTAssertEqual(seat["aiSkill"], .number(Double(skill)))
                    let encoded = try XCTUnwrap(String(data: seat.encoded(), encoding: .utf8))
                    XCTAssertTrue(encoded.contains("\"aiSkill\":\(skill),"), encoded)
                }
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(seats)) as? [[String: Any]])
                XCTAssertNil(json[0]["aiSkill"])
                for seat in json.dropFirst() { XCTAssertEqual(seat["aiSkill"] as? Int, skill) }
            }
        }
        for skill in [Int.min, 0, 11, Int.max] {
            XCTAssertThrowsError(try OnDeviceAppConfiguration.aiGameSeats(name: "Player", humanDeck: humanDeck, aiDeck: aiDeck, opponents: 1, aiSkill: skill))
        }
        for opponents in [0, 4] {
            XCTAssertThrowsError(try OnDeviceAppConfiguration.aiGameSeats(name: "Player", humanDeck: humanDeck, aiDeck: aiDeck, opponents: opponents, aiSkill: 2))
        }
    }
}
