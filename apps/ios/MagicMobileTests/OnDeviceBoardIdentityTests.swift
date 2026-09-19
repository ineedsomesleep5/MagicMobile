import XCTest
import SwiftUI
@testable import MagicMobile

final class OnDeviceBoardIdentityTests: XCTestCase {
    func testAbilityPickerDoesNotRepeatItsChoicesInCompactTextControls() throws {
        let fields: [String: Any] = ["responseKind": "ability",
            "responseCommand": ["type": "choose_ability", "promptId": "prompt", "messageId": 7],
            "abilities": [["id": "ability", "label": "Draw a card", "sourceCard": cardPayload]]]
        let action: [String: Any] = ["id": "ability-action", "type": "choose_ability", "label": "Draw a card",
            "playerId": "viewer", "promptId": "prompt", "messageId": 7, "abilityId": "ability"]
        let snapshot = try promptSnapshot(fields: fields, actions: [action])
        XCTAssertTrue(CompactPromptPopup.compactLegalPromptActions(in: snapshot).isEmpty)
        XCTAssertTrue(CompactPromptPopup.needsDetails(snapshot))
        XCTAssertTrue(CompactPromptPopup.shouldShow(for: snapshot, pendingActionId: nil))
        XCTAssertEqual(snapshot.legalActions?.first?.abilityId, "ability", "Presentation must not remove engine choices")
        let cancel: [String: Any] = ["id": "cancel", "type": "answer_yes_no", "label": "Cancel",
            "playerId": "viewer", "promptId": "prompt", "messageId": 7, "confirmed": false]
        XCTAssertEqual(CompactPromptPopup.compactLegalPromptActions(in:
            try promptSnapshot(fields: fields, actions: [action, cancel])).map(\.id), ["cancel"])
        var withoutCards = fields
        withoutCards["abilities"] = [] as [Any]
        XCTAssertEqual(CompactPromptPopup.compactLegalPromptActions(in:
            try promptSnapshot(fields: withoutCards, actions: [action])).map(\.id), ["ability-action"])

        let followup = try promptSnapshot(fields: ["responseKind": "confirmation"], actions: [
            ["id": "optional", "type": "answer_yes_no", "label": "Use the ability?", "playerId": "viewer",
             "promptId": "prompt", "messageId": 8, "confirmed": true]])
        XCTAssertEqual(CompactPromptPopup.compactLegalPromptActions(in: followup).map(\.id), ["optional"])
    }

    func testNativeDetailChoicesRemainReachableWithCompactActions() throws {
        let controls: [[String: Any]] = [
            ["targets": [["id": "target", "label": "Target"]]],
            ["cards": [cardPayload]],
            ["players": [["id": "other", "playerId": "other", "label": "Other player"]]],
            ["piles": [["id": "1", "label": "Pile one", "cards": []]]],
            ["abilities": [["id": "ability", "label": "Ability"]]],
            ["modes": [["id": "mode", "label": "Mode"]]],
            ["amounts": [0, 1]],
            ["multiAmounts": [["id": "0", "label": "Damage", "min": 0, "max": 3]]],
            ["orderedItems": [["id": "item", "label": "Item"]]],
            ["choices": (1...4).map { ["id": "\($0)", "label": "Choice \($0)"] }],
            ["responseKind": "amount", "responseCommand": ["type": "choose_amount", "promptId": "prompt", "messageId": 7], "minChoices": -100, "maxChoices": 100]
        ]
        let done: [String: Any] = ["id": "done", "type": "answer_yes_no", "label": "Done", "playerId": "viewer", "promptId": "prompt", "messageId": 7, "confirmed": true]
        for fields in controls {
            let native = try promptSnapshot(fields: fields, actions: [done])
            XCTAssertEqual(CompactPromptPopup.compactLegalPromptActions(in: native).map(\.id), ["done"])
            XCTAssertTrue(CompactPromptPopup.needsDetails(native), "Lost controls: \(fields.keys)")
            let legacy = try promptSnapshot(fields: fields, actions: [done], source: "xmage-java-bridge")
            XCTAssertFalse(CompactPromptPopup.needsDetails(legacy), "Legacy compact action policy changed")
        }
    }

    func testNativeSmallChoicesRetainEmptySpecialWithoutDuplicatingRawChoice() throws {
        let fields: [String: Any] = ["responseKind": "choice", "choices": [["id": "a", "label": "Normal"]]]
        let special: [String: Any] = ["id": "empty", "type": "choose_empty_special", "label": "Choose no item", "playerId": "viewer", "promptId": "prompt", "messageId": 7]
        var normal = special
        normal["id"] = "normal"; normal["type"] = "resolve_choice"; normal["choiceIds"] = ["a"]
        var stale = special
        stale["id"] = "stale"; stale["messageId"] = 6
        let actions = [special, normal, stale]
        XCTAssertEqual(CompactPromptPopup.supplementalChoiceActions(in: try promptSnapshot(fields: fields, actions: actions)).map(\.id), ["empty"])
        XCTAssertTrue(CompactPromptPopup.supplementalChoiceActions(in: try promptSnapshot(fields: fields, actions: actions, source: "xmage-java-bridge")).isEmpty)
    }

    func testNativePaymentRetainsCancelAndExactCurrentSpecialWithOriginalLabel() throws {
        let fields: [String: Any] = ["method": "GAME_PLAY_MANA", "responseKind": "mana",
                                   "responseCommand": ["type": "play_mana", "promptId": "prompt", "messageId": 7]]
        let cancel: [String: Any] = ["id": "cancel", "type": "cancel_payment", "label": "Cancel", "playerId": "viewer", "promptId": "prompt", "messageId": 7]
        var special = cancel
        special["id"] = "special"; special["type"] = "resolve_choice"; special["choiceIds"] = ["special"]
        special["label"] = "Use special payment"; special["shortLabel"] = "Undo"
        var stale = special
        stale["id"] = "stale"; stale["messageId"] = 6
        var foreign = special
        foreign["id"] = "foreign"; foreign["playerId"] = "other"
        var wrongToken = special
        wrongToken["id"] = "wrong"; wrongToken["choiceIds"] = ["other"]
        let actions = [cancel, stale, foreign, wrongToken, special]
        let native = try promptSnapshot(fields: fields, actions: actions)
        XCTAssertEqual(ManaPaymentTray.manaUndoActions(in: native).map(\.id), ["cancel", "special"])
        XCTAssertEqual(ManaPaymentTray.compactPaymentActions(in: native).map(\.id), ["cancel", "special"])
        XCTAssertEqual(ManaPaymentTray.paymentCancelTitle(for: try decode(LegalAction.self, special)), "Use special payment")
        let legacy = try promptSnapshot(fields: fields, actions: actions, source: "xmage-java-bridge")
        XCTAssertEqual(ManaPaymentTray.compactPaymentActions(in: legacy).map(\.id), ["cancel"])
        XCTAssertEqual(ManaPaymentTray.manaUndoActions(in: try promptSnapshot(fields: [:], actions: actions)).map(\.id), ["cancel"])
    }

    private func promptSnapshot(fields: [String: Any], actions: [[String: Any]], source: String = "xmage-ondevice") throws -> GameSnapshot {
        var prompt: [String: Any] = ["id": "prompt", "method": "GAME_SELECT", "messageId": 7,
                                   "playerId": "viewer", "responseKind": "target", "message": "Choose", "required": false,
                                   "responseCommand": ["type": "choose_target", "promptId": "prompt", "messageId": 7]]
        prompt.merge(fields) { _, new in new }
        return try decode(GameSnapshot.self, ["id": "match", "source": source, "viewerPlayerId": "viewer",
                                              "phase": "combat", "turn": 1, "log": [], "players": [],
                                              "legalActions": actions, "promptEnvelopeV2": prompt])
    }

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
