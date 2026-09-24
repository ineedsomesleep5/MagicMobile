import XCTest
@testable import MagicMobile

/// Game summary, spectating, the opening hand, quick chat and rules reminders (build 19).
@MainActor
final class Build19LogicTests: XCTestCase {
    private func creature(_ id: String, _ name: String, power: Int) -> [String: Any] {
        ["instanceId": id, "card": ["name": name, "typeLine": "Creature — Bear", "oracleText": ""],
         "power": power, "toughness": power, "isCreaturePermanent": true, "tapped": false]
    }

    private func snapshot(game: String = "g", turn: Int = 3, lives: [String: Int],
                          battlefield: [String: [[String: Any]]], graveyard: [String: [[String: Any]]] = [:],
                          combat: [[String: Any]] = []) throws -> GameSnapshot {
        let players = ["me", "them"].map { id -> [String: Any] in
            ["playerId": id, "displayName": id == "me" ? "Me" : "Them", "life": lives[id] ?? 40, "poison": 0, "commanderTax": 0,
             "zones": ["hand": [], "battlefield": battlefield[id] ?? [], "graveyard": graveyard[id] ?? [], "exile": [],
                       "library": [], "command": [], "stack": []]]
        }
        let xmage: [String: Any] = [
            "schemaVersion": 1, "gameId": game, "bridgeRevision": 1, "callbackCoverage": [], "stack": [], "combat": combat,
            "players": [], "exileZones": [], "revealed": [], "lookedAt": [], "companion": [], "playableObjects": [],
            "panels": ["stack": false, "command": true, "graveyard": true, "exile": true, "revealed": false, "lookedAt": false, "search": false]
        ]
        let root: [String: Any] = ["id": game, "phase": "COMBAT", "turn": turn, "log": [], "legalActions": [],
                                   "viewerPlayerId": "me", "players": players, "xmage": xmage]
        return try JSONDecoder().decode(GameSnapshot.self, from: JSONSerialization.data(withJSONObject: root))
    }

    func testSummaryCreditsUnblockedAttackersAndCountsDeaths() throws {
        let bear = creature("bear", "Grizzly Bears", power: 3), cub = creature("cub", "Bear Cub", power: 2)
        let wall = creature("wall", "Wall of Wood", power: 0)
        let board = ["me": [bear, cub], "them": [wall]]
        let attack: [[String: Any]] = [["defenderId": "them", "defenderName": "Them", "blocked": false,
                                        "attackers": [bear, cub], "blockers": []]]
        var stats = GameStats()
        stats.record(try snapshot(lives: ["me": 40, "them": 40], battlefield: board))
        stats.record(try snapshot(lives: ["me": 40, "them": 40], battlefield: board, combat: attack))
        stats.record(try snapshot(lives: ["me": 40, "them": 35], battlefield: board, combat: attack))
        XCTAssertEqual(stats.combatDamage, 5)
        XCTAssertEqual(stats.biggestHit, 5)
        XCTAssertEqual(stats.topCard?.name, "Grizzly Bears")
        XCTAssertEqual(stats.topCard?.damage, 3)
        // The same combat staying on screen is not credited twice.
        stats.record(try snapshot(lives: ["me": 40, "them": 35], battlefield: board, combat: attack))
        XCTAssertEqual(stats.combatDamage, 5)
        stats.record(try snapshot(turn: 4, lives: ["me": 38, "them": 35], battlefield: ["me": [bear], "them": []],
                                  graveyard: ["me": [cub], "them": [wall]]))
        XCTAssertEqual(stats.creaturesDestroyed, 1)
        XCTAssertEqual(stats.creaturesLost, 1)
        XCTAssertEqual(stats.turns, 4)
        XCTAssertEqual(stats.finalLife, 38)
        stats.record(try snapshot(game: "next", turn: 1, lives: ["me": 40, "them": 40], battlefield: [:]))
        XCTAssertEqual(stats.combatDamage, 0, "a new game starts a new summary")
        XCTAssertNil(stats.topCard)
    }

    func testBlockedAttacksAndOtherLifeLossAreNotCombatCredit() throws {
        let bear = creature("bear", "Grizzly Bears", power: 3)
        let blocked: [[String: Any]] = [["defenderId": "them", "defenderName": "Them", "blocked": true,
                                         "attackers": [bear], "blockers": []]]
        var stats = GameStats()
        stats.record(try snapshot(lives: ["me": 40, "them": 40], battlefield: ["me": [bear]], combat: blocked))
        stats.record(try snapshot(lives: ["me": 40, "them": 37], battlefield: ["me": [bear]], combat: blocked))
        stats.record(try snapshot(lives: ["me": 40, "them": 30], battlefield: ["me": [bear]]))
        XCTAssertEqual(stats.combatDamage, 0)
        XCTAssertNil(stats.topCard)
    }

    func testSpectatingAndThinkingComeFromThePlayers() {
        let watching = GameBoardPreviewFixtures.snapshot(.spectating)
        XCTAssertTrue(watching.isSpectating)
        XCTAssertEqual(watching.remainingOpponents.count, 2, "one of three opponents is out as well")
        let thinking = GameBoardPreviewFixtures.snapshot(.aiThinking)
        XCTAssertFalse(thinking.isSpectating)
        XCTAssertNotNil(thinking.thinkingPlayerID)
        XCTAssertNil(GameBoardPreviewFixtures.snapshot(.normalBattlefield).thinkingPlayerID, "your own priority is not the AI thinking")
    }

    func testOpeningHandAnswersXMagesOwnMulliganQuestion() throws {
        let choice = try XCTUnwrap(OpeningHandChoice(GameBoardPreviewFixtures.snapshot(.openingHand)))
        XCTAssertEqual(choice.message, "Mulligan to 6 cards?")
        XCTAssertEqual(choice.keepLabel, "Keep")
        XCTAssertEqual(choice.mulliganLabel, "Mulligan")
        XCTAssertEqual(choice.keep.promptId, "preview-mulligan")
        XCTAssertEqual(choice.mulligan.promptId, "preview-mulligan")
        XCTAssertNil(OpeningHandChoice(GameBoardPreviewFixtures.snapshot(.commanderReplacementPrompt)), "other yes/no questions keep their own panel")
        XCTAssertNil(OpeningHandChoice(GameBoardPreviewFixtures.snapshot(.normalBattlefield)))
    }

    func testRulesReminderExplainsWhatTriggerDoublersCopy() throws {
        func card(_ rules: String) throws -> ZoneCard {
            try JSONDecoder().decode(ZoneCard.self, from: JSONSerialization.data(withJSONObject: [
                "instanceId": "x", "card": ["name": "Card", "typeLine": "Artifact", "oracleText": rules]]))
        }
        let throne = try card("As Roaming Throne enters, choose a creature type.\nIf a triggered ability of another creature you control of the chosen type triggers, it triggers an additional time.")
        XCTAssertNotNil(CardRulesReminder.text(for: throne))
        XCTAssertTrue(CardRulesReminder.text(for: throne)?.contains("instead") == true, "names the replacement-effect case")
        XCTAssertNil(CardRulesReminder.text(for: try card("Flying")))
    }

    func testQuickChatShowsTheRightSeatAndIgnoresFloods() {
        let table = GameBoardPreviewFixtures.snapshot(.fourPlayerFocus)
        let aurelia = table.players.first { $0.displayName == "Aurelia" }!
        let center = EmoteCenter()
        center.receive(.wow, fromName: "Aurelia", in: table)
        let first = center.bubbles[aurelia.playerId]
        XCTAssertEqual(first?.emote, .wow)
        center.receive(.oops, fromName: "Aurelia", in: table)
        XCTAssertEqual(center.bubbles[aurelia.playerId], first, "a second line inside 1.5 s is dropped")
        center.receive(.hello, fromName: "Nobody", in: table)
        XCTAssertEqual(center.bubbles.count, 1, "unknown names never land on a seat")
        var sent: [GameEmote] = []
        center.send = { sent.append($0) }
        center.say(.wellPlayed, in: table)
        XCTAssertEqual(center.bubbles[table.viewerID]?.emote, .wellPlayed)
        XCTAssertEqual(sent, [.wellPlayed])
        XCTAssertFalse(center.canSend, "a short cooldown between your own lines")
        center.say(.hello, in: table)
        XCTAssertEqual(sent, [.wellPlayed])
    }
}
