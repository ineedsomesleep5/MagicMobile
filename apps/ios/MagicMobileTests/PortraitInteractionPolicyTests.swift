import XCTest
@testable import MagicMobile

final class PortraitInteractionPolicyTests: XCTestCase {
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

    private func makeSnapshot(active: String, turn: Int, visibleZone: String? = nil) throws -> GameSnapshot {
        var zones: [String: Any] = ["library": [], "hand": [], "battlefield": [], "graveyard": [], "exile": [], "command": [], "stack": [], "handCount": 7, "libraryCount": 92]
        if let visibleZone {
            zones[visibleZone] = [["instanceId": "visible-card", "card": ["name": "Visible", "typeLine": "Creature"]]]
        }
        let players: [[String: Any]] = ["a", "b", "c", "d"].map {
            ["playerId": $0, "displayName": $0, "life": 40, "poison": 0, "commanderTax": 0, "zones": zones]
        }
        let json: [String: Any] = ["id": "match", "phase": "PRECOMBAT_MAIN", "turn": turn, "activePlayerId": active,
                                   "viewerPlayerId": "a", "priorityPlayerId": "a", "players": players, "log": []]
        return try JSONDecoder().decode(GameSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
    }
}
