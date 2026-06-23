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

    func testPromptActionsFailClosedWhenRequiredValuesAreMissing() throws {
        let api = MagicMobileAPI(baseURL: URL(string: "http://localhost")!)
        for type in ["choose_pile", "choose_amount", "play_x_mana", "play_mana", "choose_mana", "answer_yes_no", "commander_replacement", "choose_ability"] {
            let action = try decodeAction(type: type)
            XCTAssertThrowsError(try api.command(for: action, gameId: "game-1"), "Expected \(type) to require explicit XMage prompt data")
        }
    }

    func testChooseAbilityUsesExplicitAbilityIdOnly() throws {
        let action = try decodeAction(
            type: "choose_ability",
            extra: #""abilityId": "ability-1""#
        )
        let command = try MagicMobileAPI(baseURL: URL(string: "http://localhost")!)
            .command(for: action, gameId: "game-1")
        let payload = try JSONSerialization.jsonObject(with: JSONEncoder.magicMobile.encode(command)) as? [String: Any]

        XCTAssertEqual(payload?["abilityId"] as? String, "ability-1")
    }

    func testBlockedCommanderFixtureResponseIsNotPlayable() throws {
        let data = """
        {
          "error": "xmage_fixture_state_seeding_unavailable",
          "enabled": true,
          "fixtureName": "commander-gauntlet",
          "productionDisabled": true,
          "directStateSeeded": false,
          "setupMethod": "bridge_fixture_without_real_seed_proof",
          "blockedReason": "Fixture endpoint did not return seed proof.",
          "nextImplementationStep": "Add an in-server fixture hook."
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.magicMobile.decode(CommanderFixtureResponse.self, from: data)

        XCTAssertNil(response.playableSnapshot)
        XCTAssertEqual(response.statusMessage, "Fixture blocked: Fixture endpoint did not return seed proof.")
        XCTAssertEqual(response.fixtureName, "commander-gauntlet")
        XCTAssertTrue(response.productionDisabled)
    }

    func testStackObjectWithoutSourceCardKeepsDisplayText() throws {
        let data = """
        {
          "id": "stack-1",
          "name": "Activated ability",
          "rulesText": "Draw a card.",
          "paid": false
        }
        """.data(using: .utf8)!

        let object = try JSONDecoder.magicMobile.decode(XmageStackObject.self, from: data)

        XCTAssertNil(object.sourceCard)
        XCTAssertEqual(object.displayName, "Activated ability")
        XCTAssertEqual(object.displaySourceName, "Source unavailable")
    }

    private func decodeAction(type: String, extra: String? = nil) throws -> LegalAction {
        let extraFields = extra.map { ",\n          \($0)" } ?? ""
        let data = """
        {
          "id": "\(type)-action",
          "type": "\(type)",
          "playerId": "human",
          "label": "\(type)",
          "promptId": "prompt-1",
          "messageId": 1\(extraFields)
        }
        """.data(using: .utf8)!
        return try JSONDecoder.magicMobile.decode(LegalAction.self, from: data)
    }
}
