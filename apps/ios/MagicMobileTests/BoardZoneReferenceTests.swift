import XCTest
@testable import MagicMobile

final class BoardZoneReferenceTests: XCTestCase {
    func testMembershipTracksMovesAndNewArrivals() throws {
        let grave = BoardZoneReference.player(playerID: "a", zone: .graveyard)
        let before = try snapshot(zonesA: ["graveyard": [card("old")]])
        let after = try snapshot(zonesA: ["battlefield": [card("old")], "graveyard": [card("new")]])
        XCTAssertEqual(grave.cards(in: before).map(\.instanceId), ["old"])
        XCTAssertEqual(grave.cards(in: after).map(\.instanceId), ["new"])
        XCTAssertEqual(BoardZoneReference.player(playerID: "a", zone: .battlefield).cards(in: after).map(\.instanceId), ["old"])
    }

    func testEmptyReferenceRemainsUsableAndCountsNeverFabricateCards() throws {
        let empty = try snapshot()
        for zone in BoardZoneReference.PlayerZone.allCases {
            let reference = BoardZoneReference.player(playerID: "a", zone: zone)
            XCTAssertTrue(reference.cards(in: empty).isEmpty)
            let populated = try snapshot(zonesA: [zone.rawValue: [card("arrived")]])
            XCTAssertEqual(reference.cards(in: populated).map(\.instanceId), ["arrived"])
        }
        XCTAssertEqual(empty.players[0].zones.visibleHandCount, 7)
        XCTAssertEqual(empty.players[0].zones.visibleLibraryCount, 92)
        for zone in [BoardZoneReference.PlayerZone.hand, .library] {
            XCTAssertTrue(BoardZoneReference.player(playerID: "a", zone: zone).title(in: empty).contains("visible cards"))
            XCTAssertTrue(BoardZoneReference.player(playerID: "missing", zone: zone).title(in: empty).contains("visible cards"))
        }
        XCTAssertTrue(BoardZoneReference.player(playerID: "missing", zone: .hand).cards(in: empty).isEmpty)
    }

    func testDuplicateDisplayNamesDoNotIdentifySeats() throws {
        let state = try snapshot(zonesA: ["hand": [card("a-card")]], zonesB: ["hand": [card("b-card")]])
        let a = BoardZoneReference.player(playerID: "a", zone: .hand)
        let b = BoardZoneReference.player(playerID: "b", zone: .hand)
        XCTAssertEqual(a.title(in: state), b.title(in: state))
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(Set([a, b]).count, 2)
        XCTAssertEqual(a.cards(in: state).map(\.instanceId), ["a-card"])
        XCTAssertEqual(b.cards(in: state).map(\.instanceId), ["b-card"])
    }

    func testNamedGroupsUseKindAndIDNotTitleAndRetainEmptyGroups() throws {
        let keys: [BoardZoneReference.NamedKind: String] = [.exile: "exileZones", .companion: "companion", .revealed: "revealed", .lookedAt: "lookedAt"]
        for kind in BoardZoneReference.NamedKind.allCases {
            let state = try snapshot(groups: [keys[kind]!: [group("one", cards: [card("visible")]), group("two", cards: [])]])
            let one = BoardZoneReference.named(kind: kind, id: "one")
            let two = BoardZoneReference.named(kind: kind, id: "two")
            XCTAssertEqual(BoardZoneReference.namedReferences(in: state), [one, two])
            XCTAssertEqual(one.title(in: state), "Shared group")
            XCTAssertEqual(two.title(in: state), one.title(in: state))
            XCTAssertEqual(one.cards(in: state).map(\.instanceId), ["visible"])
            XCTAssertTrue(two.cards(in: state).isEmpty)
            XCTAssertTrue(BoardZoneReference.named(kind: kind, id: "missing").cards(in: state).isEmpty)
            XCTAssertEqual(BoardZoneReference.collection(kind).cards(in: state).map(\.instanceId), ["visible"])
        }
    }

    func testRevokedLookedAtDoesNotResolveCardFromAnotherAuthorizedZone() throws {
        let reference = BoardZoneReference.named(kind: .lookedAt, id: "one")
        let before = try snapshot(groups: ["lookedAt": [group("one", cards: [card("seen")])]])
        let after = try snapshot(zonesA: ["battlefield": [card("seen")]])
        XCTAssertEqual(reference.cards(in: before).map(\.instanceId), ["seen"])
        XCTAssertTrue(reference.cards(in: after).isEmpty)
        XCTAssertTrue(BoardZoneReference.collection(.lookedAt).cards(in: after).isEmpty)
        XCTAssertTrue(BoardZoneReference.namedReferences(in: after).isEmpty)
    }

    private func card(_ id: String) -> [String: Any] {
        ["instanceId": id, "card": ["name": "Visible", "typeLine": "Creature"]]
    }

    private func group(_ id: String, cards: [[String: Any]]) -> [String: Any] {
        ["id": id, "name": "<b>Shared group</b>", "cards": cards]
    }

    private func snapshot(zonesA: [String: Any] = [:], zonesB: [String: Any] = [:], groups: [String: Any] = [:]) throws -> GameSnapshot {
        func player(_ id: String, overrides: [String: Any]) -> [String: Any] {
            var zones: [String: Any] = ["handCount": 7, "libraryCount": 92]
            for zone in BoardZoneReference.PlayerZone.allCases { zones[zone.rawValue] = [] as [Any] }
            zones.merge(overrides) { _, new in new }
            return ["playerId": id, "displayName": "Same name", "life": 40, "poison": 0, "commanderTax": 0, "zones": zones]
        }
        var xmage: [String: Any] = [
            "schemaVersion": 1, "gameId": "match", "bridgeRevision": 1,
            "callbackCoverage": [], "stack": [], "combat": [], "players": [],
            "exileZones": [], "revealed": [], "lookedAt": [], "companion": [], "playableObjects": [],
            "panels": Dictionary(uniqueKeysWithValues: ["stack", "command", "graveyard", "exile", "revealed", "lookedAt", "search"].map { ($0, false) })
        ]
        xmage.merge(groups) { _, new in new }
        let json: [String: Any] = [
            "id": "match", "phase": "main", "turn": 1, "activePlayerId": "a", "viewerPlayerId": "a",
            "players": [player("a", overrides: zonesA), player("b", overrides: zonesB)], "log": [], "xmage": xmage
        ]
        return try JSONDecoder().decode(GameSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
    }
}
