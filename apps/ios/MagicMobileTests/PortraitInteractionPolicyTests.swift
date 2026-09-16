import XCTest
@testable import MagicMobile

final class PortraitInteractionPolicyTests: XCTestCase {
    func testCardChoiceRoutingUsesViewerAndPromptRevision() throws {
        func snapshot(viewer: String = "a", revision: Int = 1, type: String = "choose_target", hasCards: Bool = true) throws -> GameSnapshot {
            let prompt: [String: Any] = ["id": "same-id", "method": "GAME_PICK_TARGET", "messageId": revision, "playerId": viewer,
                "responseKind": "target", "message": "Choose", "maxChoices": 1,
                "responseCommand": ["type": type], "cards": hasCards ? [["instanceId": "card", "card": ["name": "Forest", "typeLine": "Land"]]] : []]
            return try makeSnapshot(active: "a", turn: 1, prompt: prompt)
        }
        XCTAssertNotNil(PortraitInteractionPolicy.cardChoiceKey(try snapshot()))
        XCTAssertNil(PortraitInteractionPolicy.cardChoiceKey(try snapshot(viewer: "b")))
        XCTAssertNil(PortraitInteractionPolicy.cardChoiceKey(try snapshot(hasCards: false)))
        XCTAssertNotEqual(PortraitInteractionPolicy.cardChoiceKey(try snapshot()), PortraitInteractionPolicy.cardChoiceKey(try snapshot(revision: 2)))
    }

    func testAmbiguousCardTapDoesNotChooseAnAbilityForThePlayer() throws {
        let actions = try JSONDecoder().decode([LegalAction].self, from: Data(#"[{"id":"mana","type":"make_mana","playerId":"a","label":"Tap","sourceInstanceId":"card"},{"id":"other","type":"activate_ability","playerId":"a","label":"Sacrifice","sourceInstanceId":"card"}]"#.utf8))
        XCTAssertNil(PortraitInteractionPolicy.automaticCardAction(actions))
        XCTAssertNil(PortraitInteractionPolicy.automaticCardAction([]))
        XCTAssertEqual(PortraitInteractionPolicy.automaticCardAction([actions[0]])?.id, "mana")
    }

    func testPriorityChoiceDoesNotAutoOpenDetailsOverStack() throws {
        let prompt: [String: Any] = ["id": "priority", "method": "GAME_PRIORITY", "messageId": 1,
            "playerId": "a", "responseKind": "pass_priority", "message": "Respond",
            "choices": [["id": "pass", "label": "Pass priority"]], "responseCommand": ["type": "pass_priority"]]
        XCTAssertNil(PortraitInteractionPolicy.detailChoiceKey(try makeSnapshot(active: "a", turn: 1, prompt: prompt)))
    }

    func testZoneInspectionUsesOnlyCurrentSuppliedCards() throws {
        for zone in ["hand", "library", "battlefield", "graveyard", "exile", "command", "stack"] {
            let snapshot = try makeSnapshot(active: "a", turn: 1, visibleZone: zone)
            XCTAssertTrue(PortraitInteractionPolicy.authorizedCards(snapshot).contains { $0.id == "visible-card" })
            XCTAssertFalse(PortraitInteractionPolicy.authorizedCards(try makeSnapshot(active: "a", turn: 1))
                .contains { $0.id == "visible-card" })
        }
    }

    func testCardManaCannotBecomeGlobalDecision() throws {
        let actions = try JSONDecoder().decode([LegalAction].self, from: Data(#"[{"id":"mana","type":"make_mana","playerId":"a","label":"Tap","sourceInstanceId":"land","promptId":"p"},{"id":"pass","type":"pass_priority","playerId":"a","label":"Pass","promptId":"p"},{"id":"special","type":"resolve_choice","playerId":"a","label":"Special payment","promptId":"p"}]"#.utf8))
        XCTAssertEqual(PortraitInteractionPolicy.dockActions(actions).map(\.id), ["pass", "special"])
        XCTAssertEqual(actions.first?.sourceInstanceId, "land")
    }

    func testAbilitySourceInspectionExpiresWithItsAuthorizedPrompt() throws {
        let prompt: [String: Any] = ["id": "ability", "method": "PICK_ABILITY", "messageId": 1,
            "playerId": "a", "responseKind": "ability", "message": "Choose ability",
            "abilities": [["id": "choice", "label": "Draw", "sourceCard": ["instanceId": "source",
                "card": ["name": "Public source", "typeLine": "Artifact"]]]]]
        XCTAssertTrue(PortraitInteractionPolicy.authorizedCards(try makeSnapshot(active: "a", turn: 1, prompt: prompt))
            .contains { $0.id == "source" })
        XCTAssertFalse(PortraitInteractionPolicy.authorizedCards(try makeSnapshot(active: "a", turn: 1))
            .contains { $0.id == "source" })
    }

    func testEveryOpponentFocusPreservesViewerAndRouting() throws {
        let snapshot = try makeSnapshot(active: "a", turn: 1)
        for id in ["b", "c", "d"] {
            let focused = BoardOpponentFocus.snapshot(snapshot, selecting: id)
            XCTAssertEqual(focused.opponent?.playerId, id)
            XCTAssertEqual(focused.viewerID, "a")
            XCTAssertEqual(focused.activePlayerId, "a")
            XCTAssertEqual(focused.players.map(\.playerId), snapshot.players.map(\.playerId))
            XCTAssertTrue(focused.opponent!.zones.hand.isEmpty)
            XCTAssertEqual(focused.opponent!.zones.visibleHandCount, 7)
        }
        XCTAssertNotEqual(BoardOpponentFocus.snapshot(snapshot, selecting: "a").opponent?.playerId, "a")
        XCTAssertNotEqual(BoardOpponentFocus.snapshot(snapshot, selecting: "missing").opponent?.playerId, "missing")
    }

    func testTurnCueIgnoresRepeatedPollAndOpponentPriority() throws {
        XCTAssertEqual(PortraitInteractionPolicy.turnCueKey(try makeSnapshot(active: "a", turn: 1)),
                       PortraitInteractionPolicy.turnCueKey(try makeSnapshot(active: "a", turn: 1)))
        XCTAssertNotEqual(PortraitInteractionPolicy.turnCueKey(try makeSnapshot(active: "a", turn: 1)),
                          PortraitInteractionPolicy.turnCueKey(try makeSnapshot(active: "a", turn: 2)))
        XCTAssertNil(PortraitInteractionPolicy.turnCueKey(try makeSnapshot(active: "b", turn: 1)))
    }

    func testPhaseAnnouncementsFollowStepsIncludingOpponentsAndIgnorePriority() throws {
        let original = try makeSnapshot(active: "b", turn: 3)
        let first = try XCTUnwrap(BoardPhaseAnnouncement.make(original))
        XCTAssertEqual(first.title, "Main phase 1")
        XCTAssertEqual(first.owner, "b’s turn")
        XCTAssertEqual(first, BoardPhaseAnnouncement.make(original))
        func changed(step: String, priority: String) throws -> GameSnapshot {
            let data = #"{"id":"match","phase":"COMBAT","step":"\#(step)","turn":3,"activePlayerId":"b","viewerPlayerId":"a","priorityPlayerId":"\#(priority)","players":[],"log":[]}"#
            return try JSONDecoder().decode(GameSnapshot.self, from: Data(data.utf8))
        }
        let blocks = try XCTUnwrap(BoardPhaseAnnouncement.make(changed(step: "DECLARE_BLOCKERS", priority: "a")))
        XCTAssertEqual(blocks.title, "Declare blockers")
        XCTAssertNotEqual(blocks.key, first.key)
        XCTAssertEqual(blocks.key, try BoardPhaseAnnouncement.make(changed(step: "DECLARE_BLOCKERS", priority: "b"))?.key)
        for (step, title) in [("UNTAP", "Untap"), ("UPKEEP", "Upkeep"), ("DRAW", "Draw"),
                              ("DECLARE_ATTACKERS", "Declare attackers"), ("POSTCOMBAT_MAIN", "Main phase 2"),
                              ("FIRST_COMBAT_DAMAGE", "First-strike damage"), ("END_TURN", "End step"),
                              ("CLEANUP", "Cleanup")] {
            XCTAssertEqual(try BoardPhaseAnnouncement.make(changed(step: step, priority: "a"))?.title, title)
        }
        XCTAssertNil(try BoardPhaseAnnouncement.make(changed(step: "unknown-step", priority: "a")))
    }

    private func makeSnapshot(active: String, turn: Int, visibleZone: String? = nil, prompt: [String: Any]? = nil) throws -> GameSnapshot {
        var zones: [String: Any] = ["library": [], "hand": [], "battlefield": [], "graveyard": [], "exile": [], "command": [], "stack": [], "handCount": 7, "libraryCount": 92]
        if let visibleZone {
            zones[visibleZone] = [["instanceId": "visible-card", "card": ["name": "Visible", "typeLine": "Creature"]]]
        }
        let players: [[String: Any]] = ["a", "b", "c", "d"].map {
            ["playerId": $0, "displayName": $0, "life": 40, "poison": 0, "commanderTax": 0, "zones": zones]
        }
        var json: [String: Any] = ["id": "match", "phase": "PRECOMBAT_MAIN", "turn": turn, "activePlayerId": active,
                                   "viewerPlayerId": "a", "priorityPlayerId": "a", "players": players, "log": []]
        json["promptEnvelopeV2"] = prompt
        return try JSONDecoder().decode(GameSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
    }
}
