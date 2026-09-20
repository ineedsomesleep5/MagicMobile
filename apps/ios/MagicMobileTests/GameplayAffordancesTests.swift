import XCTest
@testable import MagicMobile

final class GameplayAffordancesTests: XCTestCase {
    func testCommanderCueRequiresAnAuthorizedCastOfTheCurrentCommandZoneCard() throws {
        let current = try snapshot()
        let human = try XCTUnwrap(current.human)
        XCTAssertTrue(GameplayAffordances.commanderCastAvailable(player: human, snapshot: current, pendingActionID: nil))
        XCTAssertFalse(GameplayAffordances.commanderCastAvailable(player: human, snapshot: current, pendingActionID: "sending"))
        XCTAssertFalse(GameplayAffordances.commanderCastAvailable(player: try XCTUnwrap(current.opponent), snapshot: current, pendingActionID: nil))

        for action in [nil, Self.castAction(type: "activate_ability"), Self.castAction(card: "stale-commander"), Self.castAction(player: "opponent")] {
            let changed = try snapshot(action: action)
            XCTAssertFalse(GameplayAffordances.commanderCastAvailable(player: try XCTUnwrap(changed.human), snapshot: changed, pendingActionID: nil))
        }
        let emptyZone = try snapshot(hasCommander: false)
        XCTAssertFalse(GameplayAffordances.commanderCastAvailable(player: try XCTUnwrap(emptyZone.human), snapshot: emptyZone, pendingActionID: nil))
    }

    func testOnlyCastingDismissesTheZoneInspector() throws {
        for type in ["cast_spell", "activate_ability", "make_mana", "play_land", "pass_priority", "choose_target"] {
            let action = try decode(LegalAction.self, Self.castAction(type: type))
            XCTAssertEqual(GameplayAffordances.dismissesZone(action: action), type == "cast_spell", type)
        }
    }

    func testFloatingManaCueRequiresUsableLocalPoolAndCurrentPromptChoice() throws {
        let current = try snapshot()
        XCTAssertEqual(GameplayAffordances.floatingManaSymbols(in: current, pendingActionID: nil), ["U"])
        XCTAssertTrue(GameplayAffordances.floatingManaSymbols(in: current, pendingActionID: "sending").isEmpty)
        for changed in [
            try snapshot(poolSymbol: "U", poolAmount: 0),
            try snapshot(poolSymbol: "B"),
            try snapshot(choices: []),
            try snapshot(choices: [Self.manaChoice(symbol: "B")]),
            try snapshot(choices: [Self.manaChoice(amount: 0)]),
            try snapshot(choices: [["id": "U", "label": "Blue", "manaType": "U"]]),
            try snapshot(promptOwner: "opponent"),
            try snapshot(hasPrompt: false),
            try snapshot(promptKind: "target", promptMethod: "GAME_SELECT", responseType: "choose_target")
        ] {
            XCTAssertTrue(GameplayAffordances.floatingManaSymbols(in: changed, pendingActionID: nil).isEmpty)
            XCTAssertNil(GameplayAffordances.floatingManaCommand(symbol: "U", in: changed))
        }
    }

    func testFloatingManaCommandPreservesExactEngineIdentityAndRevision() throws {
        let current = try snapshot()
        let command = try XCTUnwrap(GameplayAffordances.floatingManaCommand(symbol: "U", in: current))
        XCTAssertEqual(command.type, "play_mana")
        XCTAssertEqual(command.gameId, "affordance-match")
        XCTAssertEqual(command.playerId, "viewer")
        XCTAssertEqual(command.promptId, "payment-current")
        XCTAssertEqual(command.messageId, 37)
        XCTAssertEqual(command.expectedBridgeRevision, 81)
        XCTAssertEqual(command.manaType, "U")
        XCTAssertNil(command.cardInstanceId)
        XCTAssertNil(command.targetIds)
        for symbol in ["B", "u", "Blue", "{U}", "", "X"] {
            XCTAssertNil(GameplayAffordances.floatingManaCommand(symbol: symbol, in: current), symbol)
        }
    }

    private static func castAction(type: String = "cast_spell", card: String = "commander", player: String = "viewer") -> [String: Any] {
        ["id": "cast-commander", "type": type, "playerId": player, "label": "Cast commander", "cardInstanceId": card, "sourceZone": "command"]
    }

    private static func manaChoice(symbol: String = "U", amount: Int = 1) -> [String: Any] {
        ["id": symbol, "label": "Pay \(symbol)", "manaType": symbol, "amount": amount]
    }

    private func snapshot(action: [String: Any]? = GameplayAffordancesTests.castAction(), hasCommander: Bool = true,
                          poolSymbol: String = "U", poolAmount: Int = 1,
                          choices: [[String: Any]] = [GameplayAffordancesTests.manaChoice()],
                          promptOwner: String = "viewer", hasPrompt: Bool = true,
                          promptKind: String = "mana", promptMethod: String = "GAME_PLAY_MANA",
                          responseType: String = "play_mana") throws -> GameSnapshot {
        let card: [String: Any] = ["instanceId": "commander", "card": ["name": "The Scarab God", "typeLine": "Legendary Creature"]]
        var zones = Dictionary(uniqueKeysWithValues: ["library", "hand", "battlefield", "graveyard", "exile", "command", "stack"].map { ($0, [] as [[String: Any]]) })
        zones["command"] = hasCommander ? [card] : []
        var pool = Dictionary(uniqueKeysWithValues: ["W", "U", "B", "R", "G", "C"].map { ($0, 0) })
        pool[poolSymbol] = poolAmount
        let players: [[String: Any]] = ["viewer", "opponent"].map {
            ["playerId": $0, "displayName": $0, "life": 40, "poison": 0, "commanderTax": 0, "zones": zones, "manaPool": pool]
        }
        var payload: [String: Any] = ["id": "affordance-match", "source": "xmage-ondevice", "viewerPlayerId": "viewer",
            "phase": "main", "turn": 1, "log": [], "players": players, "bridgeRevision": 81,
            "legalActions": action.map { [$0] } ?? []]
        if hasPrompt {
            payload["promptEnvelopeV2"] = ["id": "payment-current", "method": promptMethod, "messageId": 37,
                "playerId": promptOwner, "responseKind": promptKind, "message": "Pay {U}", "manaChoices": choices,
                "responseCommand": ["type": responseType, "promptId": "payment-current", "messageId": 37]]
        }
        return try decode(GameSnapshot.self, payload)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ payload: [String: Any]) throws -> T {
        try JSONDecoder.magicMobile.decode(type, from: JSONSerialization.data(withJSONObject: payload))
    }
}
