import XCTest
@testable import MagicMobile

final class MagicMobileTests: XCTestCase {
    
    func testDeckImporter() {
        let deckText = """
        Commander
        1 Sol Ring
        Deck
        4 Island
        4 Forest
        """
        let list = DeckImporter.parse(text: deckText, source: "Test source")
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.commander?.cardName, "Sol Ring")
        XCTAssertEqual(list?.entries.count, 2)
    }
    
    func testCardIdentityHelpers() {
        let landCard = CardIdentity(name: "Island", typeLine: "Basic Land — Island", oracleText: "{T}: Add {U}.")
        XCTAssertTrue(landCard.isLand)
        XCTAssertFalse(landCard.isCreature)
        
        let creatureCard = CardIdentity(name: "Grizzly Bears", typeLine: "Creature — Bear", oracleText: nil)
        XCTAssertFalse(creatureCard.isLand)
        XCTAssertTrue(creatureCard.isCreature)
    }

    func testLegalActionPreservesCommandTemplateValues() throws {
        let data = """
        {
          "id": "mana-action",
          "type": "make_mana",
          "playerId": "human",
          "label": "Add {G}",
          "sourceInstanceId": "forest-instance",
          "commandTemplate": {
            "type": "make_mana",
            "sourceInstanceId": "forest-instance",
            "abilityId": "mana-ability",
            "expectedBridgeRevision": 42
          }
        }
        """.data(using: .utf8)!

        let action = try JSONDecoder.magicMobile.decode(LegalAction.self, from: data)

        XCTAssertEqual(action.commandTemplate?["sourceInstanceId"]?.stringValue, "forest-instance")
        XCTAssertEqual(action.commandTemplate?["abilityId"]?.stringValue, "mana-ability")
        XCTAssertEqual(action.commandTemplate?["expectedBridgeRevision"]?.stringValue, "42")
    }

    func testGameCommandEncodesExpectedBridgeRevision() throws {
        let command = GameCommand(
            type: "make_mana",
            gameId: "game-1",
            playerId: "human",
            sourceInstanceId: "forest-instance",
            abilityId: "mana-ability",
            expectedBridgeRevision: 42
        )

        let payload = try JSONSerialization.jsonObject(with: JSONEncoder.magicMobile.encode(command)) as? [String: Any]

        XCTAssertEqual(payload?["expectedBridgeRevision"] as? Int, 42)
        XCTAssertEqual(payload?["sourceInstanceId"] as? String, "forest-instance")
        XCTAssertEqual(payload?["abilityId"] as? String, "mana-ability")
    }

    func testPromptActionCommandPreservesMessageIdWithoutTemplate() throws {
        let data = """
        {
          "id": "target-action",
          "type": "choose_target",
          "playerId": "human",
          "label": "Choose target",
          "promptId": "xmage-prompt-77",
          "messageId": 77,
          "targetIds": ["target-1"]
        }
        """.data(using: .utf8)!

        let action = try JSONDecoder.magicMobile.decode(LegalAction.self, from: data)
        let command = try MagicMobileAPI(baseURL: URL(string: "http://localhost")!)
            .command(for: action, gameId: "game-1")
        let payload = try JSONSerialization.jsonObject(with: JSONEncoder.magicMobile.encode(command)) as? [String: Any]

        XCTAssertEqual(payload?["promptId"] as? String, "xmage-prompt-77")
        XCTAssertEqual(payload?["messageId"] as? Int, 77)
        XCTAssertEqual(payload?["targetIds"] as? [String], ["target-1"])
    }
}
