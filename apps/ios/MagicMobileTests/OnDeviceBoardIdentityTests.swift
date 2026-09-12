import XCTest
import SwiftUI
@testable import MagicMobile

final class OnDeviceBoardIdentityTests: XCTestCase {
    func testLegacySnapshotDefaultsToHumanViewer() throws {
        let snapshot = try decode(GameSnapshot.self, [
            "id": "legacy-match", "phase": "main", "turn": 1, "log": [],
            "players": [playerPayload(id: "human", name: "Local"), playerPayload(id: "ai", name: "Opponent")]
        ])
        XCTAssertEqual(snapshot.viewerID, "human")
        XCTAssertEqual(snapshot.human?.playerId, "human")
        XCTAssertEqual(snapshot.opponent?.playerId, "ai")
    }

    func testViewerUsesAuthenticatedSeatInsteadOfFirstPlayer() throws {
        let snapshot = try makeSnapshot()
        XCTAssertEqual(snapshot.human?.playerId, "seat-b")
        XCTAssertTrue(snapshot.isViewer("seat-b"))
        XCTAssertFalse(snapshot.isViewer(nil))
    }

    func testLabelsDistinguishHumanOpponents() throws {
        let snapshot = try makeSnapshot()
        XCTAssertEqual(snapshot.playerLabel("seat-b"), "You")
        XCTAssertEqual(snapshot.playerLabel("seat-c"), "Cora")
        XCTAssertEqual(snapshot.playerLabel("seat-d"), "Drew")
        XCTAssertEqual(snapshot.playerLabel(nil), "Waiting")
    }

    func testOpponentMenuExcludesViewerSeat() throws {
        XCTAssertEqual(BoardOpponentFocus.opponents(in: try makeSnapshot()).map(\.playerId), ["seat-a", "seat-c", "seat-d"])
    }

    func testOpponentFocusChangesBoardWithoutChangingViewerOrPlayerOrder() throws {
        let original = try makeSnapshot()
        let selected = BoardOpponentFocus.snapshot(original, selecting: "seat-d")
        XCTAssertEqual(selected.opponent?.playerId, "seat-d")
        XCTAssertEqual(selected.viewerPlayerId, original.viewerPlayerId)
        XCTAssertEqual(selected.players.map(\.playerId), original.players.map(\.playerId))
        XCTAssertNil(original.selectedOpponentId)
    }

    func testOpponentFocusRejectsViewerSelection() throws {
        let selected = BoardOpponentFocus.snapshot(try makeSnapshot(selected: "seat-c"), selecting: "seat-b")
        XCTAssertEqual(selected.opponent?.playerId, "seat-c")
    }

    func testOpponentFocusIgnoresDepartedSeat() throws {
        let selected = BoardOpponentFocus.snapshot(try makeSnapshot(selected: "seat-c"), selecting: "departed-seat")
        XCTAssertEqual(selected.opponent?.playerId, "seat-c")
    }

    func testReportedPrivateCountsDoNotRequireHiddenCards() throws {
        let player = try XCTUnwrap(makeSnapshot().opponent)
        let summary = CommanderHudSummary(player: player, opponentId: "seat-b")
        XCTAssertEqual(summary.handCount, 7)
        XCTAssertEqual(summary.libraryCount, 91)
        XCTAssertTrue(player.zones.hand.isEmpty)
        XCTAssertTrue(player.zones.library.isEmpty)
    }

    func testLegacyCountsFallBackToAuthorizedCardArrays() throws {
        var zones = emptyZones
        zones["hand"] = [cardPayload]
        zones["library"] = [cardPayload, cardPayload]
        let decoded = try decode(PlayerZones.self, zones)
        XCTAssertEqual(decoded.visibleHandCount, 1)
        XCTAssertEqual(decoded.visibleLibraryCount, 2)
    }

    func testExplicitZeroCountIsNotReplacedByArrayCount() throws {
        var zones = emptyZones
        zones["hand"] = [cardPayload]
        zones["handCount"] = 0
        XCTAssertEqual(try decode(PlayerZones.self, zones).visibleHandCount, 0)
    }

    func testUnknownTaxIsNotPresentedAsZero() throws {
        let player = try XCTUnwrap(makeSnapshot().human)
        let summary = CommanderHudSummary(player: player, opponentId: "seat-a")
        XCTAssertNil(summary.commanderTax)
        XCTAssertEqual(summary.commanderTaxLabel, "—")
        XCTAssertEqual(summary.commandZoneLabel, "Command")
    }

    func testLegacyTaxRemainsVisibleWhenKnownFlagIsAbsent() throws {
        var payload = playerPayload(id: "human", name: "Legacy")
        payload.removeValue(forKey: "commanderTaxKnown")
        payload["commanderTax"] = 2
        let summary = CommanderHudSummary(player: try decode(PlayerGameState.self, payload), opponentId: "ai")
        XCTAssertEqual(summary.commanderTax, 2)
        XCTAssertEqual(summary.commandZoneLabel, "Command (2)")
    }

    func testUnreportedCommanderDamageStaysUnknown() throws {
        let player = try XCTUnwrap(makeSnapshot().human)
        let summary = CommanderHudSummary(player: player, opponentId: "seat-a")
        XCTAssertNil(summary.commanderDamage)
        XCTAssertEqual(summary.commanderDamageLabel, "—")
    }

    func testReportedCommanderDamageRemainsVisible() throws {
        var payload = playerPayload(id: "human", name: "Legacy")
        payload["commanderDamage"] = ["ai": 4]
        let summary = CommanderHudSummary(player: try decode(PlayerGameState.self, payload), opponentId: "ai")
        XCTAssertEqual(summary.commanderDamage, 4)
    }

    func testCombatTargetUsesEngineUUIDExposedByLegalAction() throws {
        let snapshot = try makeSnapshot(selected: "seat-d")
        XCTAssertEqual(CombatPlayerIdentity.targetID(for: "seat-d", in: snapshot, candidates: [engineIDs[3]]), engineIDs[3])
        XCTAssertNil(CombatPlayerIdentity.targetID(for: "seat-c", in: snapshot, candidates: [engineIDs[3]]))
    }

    func testPortraitViewerEngineUUIDRoutesToBottomHUD() throws {
        let anchor = try XCTUnwrap(PortraitCombatAnchorResolver.defenderAnchor(for: engineIDs[1], kind: "player", metrics: portraitMetrics, snapshot: makeSnapshot()))
        XCTAssertEqual(anchor.y, portraitMetrics.bottomHUDRect.midY, accuracy: 0.1)
    }

    func testPortraitFocusedOpponentEngineUUIDRoutesToTopHUD() throws {
        let anchor = try XCTUnwrap(PortraitCombatAnchorResolver.defenderAnchor(for: engineIDs[3], kind: "PLAYER", metrics: portraitMetrics, snapshot: makeSnapshot(selected: "seat-d")))
        XCTAssertEqual(anchor.y, portraitMetrics.topHUDRect.midY, accuracy: 0.1)
    }

    func testLandscapeViewerRoutesToLocalBattlefield() throws {
        let metrics = BattlefieldLayoutMetrics(size: CGSize(width: 932, height: 430))
        let anchor = try XCTUnwrap(CombatPlayerIdentity.defenderAnchor(for: engineIDs[1], kind: "player", metrics: metrics, snapshot: makeSnapshot()))
        XCTAssertEqual(anchor.y, metrics.playerBattlefieldRect.midY, accuracy: 0.1)
    }

    func testUnfocusedOpponentDoesNotRouteToWrongHUD() throws {
        XCTAssertNil(PortraitCombatAnchorResolver.defenderAnchor(for: engineIDs[2], kind: "player", metrics: portraitMetrics, snapshot: try makeSnapshot(selected: "seat-d")))
    }

    func testSubstringInUnknownIDDoesNotCreatePlayerAnchor() throws {
        let snapshot = try makeSnapshot()
        XCTAssertNil(CombatPlayerIdentity.side(for: "human-shaped-permanent", kind: nil, in: snapshot))
        XCTAssertNil(CombatPlayerIdentity.side(for: "ai-shaped-permanent", kind: "player", in: snapshot))
    }

    func testPermanentDefenderKindNeverUsesPlayerHUD() throws {
        XCTAssertNil(CombatPlayerIdentity.side(for: engineIDs[1], kind: "planeswalker", in: try makeSnapshot()))
    }

    func testTextPowerAndToughnessRemainAvailableForRendering() throws {
        var payload = cardPayload
        payload["reportedPower"] = "*"
        payload["reportedToughness"] = "1+*"
        let card = try decode(ZoneCard.self, payload)
        XCTAssertEqual(card.displayPower, "*")
        XCTAssertEqual(card.displayToughness, "1+*")
        XCTAssertTrue(card.showsPowerToughness)
    }

    private let engineIDs = [
        "00000000-0000-0000-0000-000000000001", "00000000-0000-0000-0000-000000000002",
        "00000000-0000-0000-0000-000000000003", "00000000-0000-0000-0000-000000000004"
    ]

    private var portraitMetrics: PortraitBattlefieldLayoutMetrics {
        PortraitBattlefieldLayoutMetrics(size: CGSize(width: 430, height: 932), safeArea: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0))
    }

    private var emptyZones: [String: Any] {
        Dictionary(uniqueKeysWithValues: ["library", "hand", "battlefield", "graveyard", "exile", "command", "stack"].map { ($0, [] as [Any]) })
    }

    private var cardPayload: [String: Any] {
        ["instanceId": "known-card", "card": ["name": "Known Creature", "typeLine": "Creature", "oracleText": "Full authorized rules text"]]
    }

    private func playerPayload(id: String, name: String) -> [String: Any] {
        var zones = emptyZones
        zones["handCount"] = 7
        zones["libraryCount"] = 91
        return ["playerId": id, "displayName": name, "life": 40, "poison": 0,
                "commanderTax": 0, "commanderTaxKnown": false, "zones": zones]
    }

    private func makeSnapshot(selected: String? = nil) throws -> GameSnapshot {
        let seats = ["seat-a", "seat-b", "seat-c", "seat-d"]
        let names = ["Alex", "Blair", "Cora", "Drew"]
        let skip = Dictionary(uniqueKeysWithValues: ["passedTurn", "passedUntilEndOfTurn", "passedUntilNextMain", "passedUntilStackResolved", "passedAllTurns", "passedUntilEndStepBeforeMyTurn"].map { ($0, false) })
        let mana = Dictionary(uniqueKeysWithValues: ["W", "U", "B", "R", "G", "C"].map { ($0, 0) })
        let enginePlayers: [[String: Any]] = seats.enumerated().map { index, seat in
            ["playerId": seat, "xmagePlayerId": engineIDs[index], "name": names[index],
             "active": index == 1, "hasPriority": index == 1, "timerActive": false,
             "skipState": skip, "manaPool": mana, "command": [],
             "zones": ["battlefield": [], "graveyard": [], "exile": [], "sideboard": []]]
        }
        var payload: [String: Any] = [
            "id": "four-human-match", "viewerPlayerId": "seat-b", "activePlayerId": "seat-b",
            "priorityPlayerId": "seat-b", "phase": "main", "turn": 1, "log": [],
            "players": seats.enumerated().map { playerPayload(id: $0.element, name: names[$0.offset]) },
            "xmage": ["schemaVersion": 1, "gameId": "four-human-match", "bridgeRevision": 1,
                      "callbackCoverage": [], "stack": [], "combat": [], "players": enginePlayers,
                      "exileZones": [], "revealed": [], "lookedAt": [], "companion": [], "playableObjects": [],
                      "panels": Dictionary(uniqueKeysWithValues: ["stack", "command", "graveyard", "exile", "revealed", "lookedAt", "search"].map { ($0, false) })]
        ]
        if let selected { payload["selectedOpponentId"] = selected }
        return try decode(GameSnapshot.self, payload)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ payload: [String: Any]) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: payload))
    }
}
