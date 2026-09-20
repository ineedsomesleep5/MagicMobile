import XCTest
import MagicMobileOnDevice
@testable import MagicMobile

final class OnDeviceSnapshotAdapterTests: XCTestCase {
    func testNativePublicPhasingPlayerCountersAndAttachmentsPreserveExactIdentity() throws {
        let original = try fixture("2p-battlefield")
        var raw = try XCTUnwrap(original.raw.object)
        var root = try XCTUnwrap(original.snapshot?.object)
        var view = try XCTUnwrap(root["gameView"]?.object)
        var players = try XCTUnwrap(view["players"]?.array)
        let index = try XCTUnwrap(players.firstIndex { !($0["battlefield"]?.object?.isEmpty ?? true) })
        var player = try XCTUnwrap(players[index].object)
        let playerID = try XCTUnwrap(player["playerId"]?.string)
        player["counters"] = .array([.object(["name": .string("poison"), "count": .integer(3)]),
                                      .object(["name": .string("energy"), "count": .integer(5)])])
        player["monarch"] = .bool(true); player["initiative"] = .bool(true)
        var battlefield = try XCTUnwrap(player["battlefield"]?.object)
        let id = try XCTUnwrap(battlefield.keys.first)
        var card = try XCTUnwrap(battlefield[id]?.object)
        card["phasedIn"] = .bool(false); card["attachedTo"] = .string(playerID)
        battlefield[id] = .object(card); player["battlefield"] = .object(battlefield)
        players[index] = .object(player); view["players"] = .array(players)
        root["gameView"] = .object(view); raw["snapshot"] = .object(root)
        let shown = try OnDeviceSnapshotAdapter.snapshot(MatchPoll(.object(raw)), expectedSeatID: original.seatID)
        let mappedPlayer = try XCTUnwrap(shown.players.first { $0.id == playerID })
        XCTAssertEqual(mappedPlayer.poison, 3)
        XCTAssertEqual(mappedPlayer.counters, ["poison": 3, "energy": 5])
        XCTAssertEqual(mappedPlayer.monarch, true); XCTAssertEqual(mappedPlayer.initiative, true)
        let mapped = try XCTUnwrap(mappedPlayer.zones.battlefield.first { $0.id == id })
        XCTAssertTrue(mapped.isPhasedOut)
        XCTAssertEqual(mapped.attachedToInstanceId, playerID)
        XCTAssertEqual(BoardZoneReference.playerEnchantments(playerID: playerID).cards(in: shown).map(\.id), [id])
    }

    func testTokenIdentityPreservesVisibleFalseTrueAndRedactsHidden() throws {
        let original = try fixture("2p-priority")
        for (flag, hidden, complete, faceDown) in [(true as Bool?, false, true, false), (false, false, true, false), (nil, false, true, false), (true, true, true, false), (true, false, false, false), (true, false, true, true)] {
            var raw = try XCTUnwrap(original.raw.object)
            var root = try XCTUnwrap(original.snapshot?.object)
            var view = try XCTUnwrap(root["gameView"]?.object)
            var hand = try XCTUnwrap(view["myHand"]?.object)
            let id = try XCTUnwrap(hand.keys.sorted().first)
            var card = try XCTUnwrap(hand[id]?.object)
            card["isToken"] = flag.map { .bool($0) }
            card["hideInfo"] = .bool(hidden)
            card["faceDown"] = .bool(faceDown)
            card["color"] = .object(complete
                ? ["white": .bool(true), "blue": .bool(false), "black": .bool(false), "red": .bool(false), "green": .bool(false)]
                : ["white": .bool(true)])
            hand[id] = .object(card); view["myHand"] = .object(hand)
            root["gameView"] = .object(view); raw["snapshot"] = .object(root)
            let snapshot = try OnDeviceSnapshotAdapter.snapshot(MatchPoll(.object(raw)), expectedSeatID: original.seatID)
            XCTAssertEqual(snapshot.human?.zones.hand.first { $0.id == id }?.card.isToken, hidden || faceDown ? nil : flag)
            XCTAssertEqual(snapshot.human?.zones.hand.first { $0.id == id }?.card.tokenColors,
                           !hidden && !faceDown && flag == true && complete ? ["W"] : nil)
        }
    }
    func testPrintedManaCostUsesNativeSymbolArraysAndNeverPaymentOrHiddenIdentity() throws {
        let original = try fixture("2p-priority")
        for (left, right, hidden, expected) in [
            (["{3}", "{W}"], [], false, "{3}{W}" as String?),
            (["{X}", "{2/U}", "{G/P}"], [], false, "{X}{2/U}{G/P}"),
            (["{R}"], ["{1}", "{U}"], false, "{R} // {1}{U}"),
            (["{0}"], [], false, "{0}"), ([], [], false, nil),
            (["{3}", "{W}"], [], true, nil)
        ] {
            var raw = try XCTUnwrap(original.raw.object)
            var root = try XCTUnwrap(original.snapshot?.object)
            var view = try XCTUnwrap(root["gameView"]?.object)
            var hand = try XCTUnwrap(view["myHand"]?.object)
            let id = try XCTUnwrap(hand.keys.sorted().first)
            var card = try XCTUnwrap(hand[id]?.object)
            card["manaCostLeftStr"] = .array(left.map { .string($0) })
            card["manaCostRightStr"] = .array(right.map { .string($0) })
            card["hideInfo"] = .bool(hidden)
            card["rules"] = .array([.string("Pay {9} instead; commander tax {2}.")])
            hand[id] = .object(card); view["myHand"] = .object(hand)
            root["gameView"] = .object(view); raw["snapshot"] = .object(root)
            let snapshot = try OnDeviceSnapshotAdapter.snapshot(MatchPoll(.object(raw)), expectedSeatID: original.seatID)
            XCTAssertEqual(snapshot.human?.zones.hand.first { $0.id == id }?.card.manaCost, expected)
        }
        XCTAssertNil(CardIdentity(name: "Legacy", typeLine: "Creature", oracleText: nil).manaCost)
        let legacy = try JSONDecoder().decode(CardIdentity.self, from: Data(#"{"name":"Legacy","typeLine":"Land"}"#.utf8))
        XCTAssertNil(legacy.manaCost)
    }

    func testNativeIconCategoriesSurviveAndMenaceRequiresAnExplicitEngineIcon() throws {
        let original = try fixture("2p-priority")
        var raw = try XCTUnwrap(original.raw.object)
        var root = try XCTUnwrap(original.snapshot?.object)
        var view = try XCTUnwrap(root["gameView"]?.object)
        var hand = try XCTUnwrap(view["myHand"]?.object)
        let id = try XCTUnwrap(hand.keys.sorted().first)
        var card = try XCTUnwrap(hand[id]?.object)
        card["rules"] = .array([.string("Menace")])
        for explicitMenace in [false, true] {
            let names = ["ABILITY_FLYING", "COMMANDER", "PLAYABLE_COUNT", "SYSTEM_COMBINED", "UNKNOWN"] + (explicitMenace ? ["ABILITY_MENACE"] : [])
            card["cardIcons"] = .array(names.map { .object(["cardIconType": .string($0)]) })
            hand[id] = .object(card); view["myHand"] = .object(hand)
            root["gameView"] = .object(view); raw["snapshot"] = .object(root)
            let snapshot = try OnDeviceSnapshotAdapter.snapshot(MatchPoll(.object(raw)), expectedSeatID: original.seatID)
            let mapped = try XCTUnwrap(snapshot.human?.zones.hand.first { $0.id == id })
            XCTAssertEqual(mapped.visibleXmageIcons.map(\.iconType), ["ABILITY_FLYING", "COMMANDER"] + (explicitMenace ? ["ABILITY_MENACE"] : []))
            XCTAssertEqual(mapped.visibleXmageIcons.compactMap(\.textBadge), explicitMenace ? ["Menace"] : [])
        }
    }

    func testNonbasicManaRowsUseSourceUUIDWithoutEnablingNonmanaAbilitiesDuringPayment() throws {
        let original = try fixture("2p-mana")
        for manaType in [true, false, nil] as [Bool?] {
            var raw = try XCTUnwrap(original.raw.object)
            var root = try XCTUnwrap(original.snapshot?.object)
            var view = try XCTUnwrap(root["gameView"]?.object)
            var playable = try XCTUnwrap(view["canPlayObjects"]?.object)
            let entries = try XCTUnwrap(playable["objects"]?.object)
            let source = try XCTUnwrap(entries.keys.sorted().first)
            var row = try XCTUnwrap(entries[source]?["basicManaAbilities"]?.array?.first?.object)
            row["manaAbility"] = manaType.map { .bool($0) }
            row["value"] = .string("{T}: Add {C}{C}.") // Same label must never determine legality.
            playable["objects"] = .object([source: .object(["other": .array([.object(row)])])])
            view["canPlayObjects"] = .object(playable); root["gameView"] = .object(view); raw["snapshot"] = .object(root)
            let poll = try MatchPoll(.object(raw))
            let snapshot = try OnDeviceSnapshotAdapter.snapshot(poll, expectedSeatID: poll.seatID)
            let actions = snapshot.legalActions?.filter { $0.sourceInstanceId == source } ?? []
            XCTAssertEqual(actions.count, manaType == true ? 1 : 0)
            if let action = actions.first {
                XCTAssertEqual(action.type, "make_mana")
                let command = GameCommand(type: action.type, gameId: snapshot.id, playerId: action.playerId,
                    sourceInstanceId: source, promptId: action.promptId, messageId: action.messageId)
                XCTAssertEqual(try OnDevicePromptAdapter.answer(for: command, prompt: XCTUnwrap(poll.prompt), viewerPlayerID: snapshot.viewerID), EnginePrompt.answer("uuid", .string(source)))
                XCTAssertNotEqual(source, row["id"]?.string)
            }
        }
    }

    func testLocalAndAuthorizedControlledAttackersRemainSelectableWithViewerCommands() throws {
        for controlled in [false, true] {
            let poll = try attackerPoll(controlled: controlled)
            let snapshot = try OnDeviceSnapshotAdapter.snapshot(poll, expectedSeatID: poll.seatID)
            let active = try XCTUnwrap(snapshot.activePlayerId)
            let attacker = try XCTUnwrap(snapshot.players.first { $0.playerId == active }?.zones.battlefield.first { $0.isAttacking == true })
            let envelope = try XCTUnwrap(snapshot.promptEnvelopeV2)
            XCTAssertEqual(envelope.targets?.map(\.id), [attacker.id])
            XCTAssertEqual(envelope.playerId, snapshot.viewerID)
            XCTAssertEqual(snapshot.viewerID == active, !controlled)
            let command = try XCTUnwrap(PromptCommandBuilder.command(gameId: snapshot.id, promptEnvelope: envelope,
                type: "choose_target", promptId: envelope.id, playerId: snapshot.viewerID, ids: [attacker.id]))
            let prompt = try XCTUnwrap(poll.prompt)
            XCTAssertEqual(command.messageId, Int(prompt.revision))
            XCTAssertEqual(try OnDevicePromptAdapter.answer(for: command, prompt: prompt, viewerPlayerID: snapshot.viewerID),
                           EnginePrompt.answer("uuid", .string(attacker.id)))
            let stale = GameCommand(type: "choose_target", gameId: snapshot.id, playerId: snapshot.viewerID,
                                   promptId: envelope.id, messageId: Int(prompt.revision) - 1, targetIds: [attacker.id])
            XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: stale, prompt: prompt, viewerPlayerID: snapshot.viewerID))
            if controlled {
                let impersonated = GameCommand(type: "choose_target", gameId: snapshot.id, playerId: active,
                                               promptId: envelope.id, messageId: Int(prompt.revision), targetIds: [attacker.id])
                XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: impersonated, prompt: prompt, viewerPlayerID: snapshot.viewerID))
            }
            XCTAssertThrowsError(try OnDeviceSnapshotAdapter.snapshot(poll, expectedSeatID: "unbound-seat"))
        }
    }

    func testUnauthorizedOrMismatchedControlledAttackerIdentityFailsClosed() throws {
        let original = try attackerPoll(controlled: true)
        let active = try XCTUnwrap(original.snapshot?["gameView"]?["activePlayerId"]?.string)
        let viewer = try XCTUnwrap(original.snapshot?["enginePlayerId"]?.string)
        for mutation in ["missing-control", "wrong-key", "wrong-viewer", "missing-viewer", "wrong-active", "missing-controlled-active", "missing-active", "unknown-active"] {
            var raw = try XCTUnwrap(original.raw.object)
            var root = try XCTUnwrap(original.snapshot?.object)
            var view = try XCTUnwrap(root["gameView"]?.object)
            var control = try XCTUnwrap(root["controlledPlayerViews"]?[active]?.object)
            switch mutation {
            case "wrong-viewer": control["myPlayerId"] = .string(viewer)
            case "missing-viewer": control["myPlayerId"] = nil
            case "wrong-active": control["activePlayerId"] = .string(viewer)
            case "missing-controlled-active": control["activePlayerId"] = nil
            case "missing-active": view["activePlayerId"] = nil
            case "unknown-active": view["activePlayerId"] = .string("00000000-0000-0000-0000-000000000099")
            default: break
            }
            root["controlledPlayerViews"] = mutation == "missing-control" ? .object([:]) : .object([mutation == "wrong-key" ? viewer : active: .object(control)])
            root["gameView"] = .object(view); raw["snapshot"] = .object(root)
            XCTAssertThrowsError(try OnDeviceSnapshotAdapter.snapshot(MatchPoll(.object(raw)), expectedSeatID: original.seatID), mutation)
        }
    }

    private func attackerPoll(controlled: Bool) throws -> MatchPoll {
        let original = try fixture("2p-combat")
        var raw = try XCTUnwrap(original.raw.object)
        var root = try XCTUnwrap(original.snapshot?.object)
        var view = try XCTUnwrap(root["gameView"]?.object)
        let active = try XCTUnwrap(view["activePlayerId"]?.string)
        if controlled {
            let viewer = try XCTUnwrap(view["players"]?.array?.first { $0["playerId"]?.string != active }?["playerId"]?.string)
            root["controlledPlayerViews"] = .object([active: .object(view)])
            root["enginePlayerId"] = .string(viewer); view["myPlayerId"] = .string(viewer)
            view["myHand"] = .object([:])
        }
        var prompt = try XCTUnwrap(raw["prompt"]?.object)
        prompt["payload"] = .object(["selectMode": .string("attackers"), "options": .object(["possibleAttackers": .array([])])])
        root["gameView"] = .object(view); raw["snapshot"] = .object(root); raw["prompt"] = .object(prompt)
        return try MatchPoll(.object(raw))
    }

    func testActualFourSeatPollPreservesViewerAndHiddenZoneCounts() throws {
        let poll = try fixture("4p-initial-player-3")
        let snapshot = try OnDeviceSnapshotAdapter.snapshot(poll, expectedSeatID: "player-3")
        XCTAssertEqual(snapshot.players.count, 4)
        XCTAssertEqual(snapshot.viewerID, poll.snapshot?["enginePlayerId"]?.string)
        XCTAssertEqual(snapshot.human?.displayName, "Fixture Player 3")
        XCTAssertEqual(snapshot.human?.zones.hand.count, 7)
        for other in snapshot.players where !snapshot.isViewer(other.playerId) {
            XCTAssertTrue(other.zones.hand.isEmpty)
            XCTAssertEqual(other.zones.visibleHandCount, 7)
            XCTAssertTrue(other.zones.library.isEmpty)
        }
    }

    func testActualStackAndCombatRetainObjectsAndPlayerUUIDs() throws {
        let stackPoll = try fixture("2p-stack")
        let stack = try OnDeviceSnapshotAdapter.snapshot(stackPoll, expectedSeatID: stackPoll.seatID)
        XCTAssertEqual(stack.xmage?.stack.count, 1)
        XCTAssertEqual(stack.xmage?.stack.first?.name, "Isamaru, Hound of Konda")
        XCTAssertEqual(stack.xmage?.stack.first?.paid, true)
        let combatPoll = try fixture("2p-combat")
        let combat = try OnDeviceSnapshotAdapter.snapshot(combatPoll, expectedSeatID: combatPoll.seatID)
        let group = try XCTUnwrap(combat.xmage?.combat.first)
        XCTAssertEqual(group.defenderKind, "player")
        XCTAssertTrue(combat.players.contains { $0.playerId == group.defenderId })
        XCTAssertEqual(group.attackers.first?.card.name, "Isamaru, Hound of Konda")
    }

    func testCardActionsComeOnlyFromCurrentEnginePlayability() throws {
        let poll = try fixture("2p-priority")
        let snapshot = try OnDeviceSnapshotAdapter.snapshot(poll, expectedSeatID: poll.seatID)
        let allowed = Set(poll.snapshot?["gameView"]?["canPlayObjects"]?["objects"]?.object?.keys.map { $0 } ?? [])
        let actions = snapshot.legalActions?.filter { $0.cardInstanceId != nil } ?? []
        XCTAssertFalse(actions.isEmpty)
        XCTAssertEqual(Set(actions.compactMap(\.cardInstanceId)), allowed)
        XCTAssertTrue(actions.allSatisfy { $0.promptId == poll.prompt?.id && $0.messageId == Int(poll.prompt!.revision) })
        XCTAssertFalse(actions.contains { $0.type == "cast_spell" })
    }

    func testNativeManaSourcesUseTheBoardsDirectManaAction() throws {
        let poll = try fixture("2p-mana")
        let snapshot = try OnDeviceSnapshotAdapter.snapshot(poll, expectedSeatID: poll.seatID)
        let action = try XCTUnwrap(snapshot.legalActions?.first { $0.type == "make_mana" })
        let source = try XCTUnwrap(action.sourceInstanceId)
        XCTAssertNotNil(poll.snapshot?["gameView"]?["canPlayObjects"]?["objects"]?[source]?["basicManaAbilities"]?.array?.first)
        let command = GameCommand(type: action.type, gameId: snapshot.id, playerId: action.playerId,
                                  sourceInstanceId: source, promptId: action.promptId, messageId: action.messageId)
        XCTAssertEqual(try OnDevicePromptAdapter.answer(for: command, prompt: XCTUnwrap(poll.prompt), viewerPlayerID: snapshot.viewerID),
                       EnginePrompt.answer("uuid", .string(source)))
    }

    func testActualOpeningPromptUsesPromptRevisionNotPollRevision() throws {
        let poll = try fixture("2p-initial-player-1")
        let snapshot = try OnDeviceSnapshotAdapter.snapshot(poll, expectedSeatID: poll.seatID)
        XCTAssertEqual(snapshot.promptEnvelopeV2?.id, poll.prompt?.id)
        XCTAssertEqual(snapshot.promptEnvelopeV2?.messageId, Int(poll.prompt!.revision))
        XCTAssertEqual(snapshot.promptEnvelopeV2?.playerId, snapshot.viewerID)
        XCTAssertNotNil(snapshot.promptEnvelopeV2?.confirmation)
        XCTAssertEqual(snapshot.waitingOnPlayerId, snapshot.viewerID)
    }

    func testPublicZonesAndAuthorizedInspectionsAreMappedWithoutHiddenHandLookup() throws {
        let original = try fixture("2p-initial-player-1")
        var raw = try XCTUnwrap(original.raw.object)
        var root = try XCTUnwrap(original.snapshot?.object)
        var view = try XCTUnwrap(root["gameView"]?.object)
        let card = try XCTUnwrap(view["myHand"]?.object?.values.first)
        let cardID = try XCTUnwrap(card["id"]?.string)
        root["namedExiles"] = .array([.object(["id": .string("exile-public"), "name": .string("Exiled with an ability"), "cards": .object([cardID: card])])])
        root["authorizedLookedAt"] = .object(["Search your library": .object([cardID: card])])
        root["authorizedOpponentHands"] = .object(["Controlled player": .object([cardID: card])])
        view["revealed"] = .array([.object(["name": .string("Revealed cards"), "cards": .object([cardID: card])])])
        view["companion"] = .array([.object(["name": .string("Companion"), "cards": .object([cardID: card])])])
        root["gameView"] = .object(view); raw["snapshot"] = .object(root)
        let snapshot = try OnDeviceSnapshotAdapter.snapshot(MatchPoll(.object(raw)), expectedSeatID: original.seatID)
        XCTAssertEqual(snapshot.xmage?.exileZones.first?.name, "Exiled with an ability")
        XCTAssertEqual(snapshot.xmage?.revealed.first?.cards.first?.instanceId, cardID)
        XCTAssertEqual(snapshot.xmage?.companion.first?.cards.count, 1)
        XCTAssertEqual(snapshot.xmage?.lookedAt.count, 2)
        XCTAssertTrue(snapshot.xmage?.panels.search == true)
        XCTAssertTrue(snapshot.players.filter { !snapshot.isViewer($0.playerId) }.allSatisfy { $0.zones.hand.isEmpty })
    }

    func testPartnerTaxAndDamageStayIndependent() throws {
        let original = try fixture("2p-initial-player-1")
        var raw = try XCTUnwrap(original.raw.object)
        var root = try XCTUnwrap(original.snapshot?.object)
        let owner = try XCTUnwrap(root["enginePlayerId"]?.string)
        let first = UUID().uuidString, second = UUID().uuidString
        root["commanders"] = .object([
            first: .object(["ownerPlayerId": .string(owner), "castsFromCommandZone": .integer(1), "commanderTax": .integer(2), "damageToPlayers": .object([owner: .integer(7)])]),
            second: .object(["ownerPlayerId": .string(owner), "castsFromCommandZone": .integer(3), "commanderTax": .integer(6), "damageToPlayers": .object([:])])
        ])
        raw["snapshot"] = .object(root)
        let snapshot = try OnDeviceSnapshotAdapter.snapshot(MatchPoll(.object(raw)), expectedSeatID: original.seatID)
        XCTAssertFalse(try XCTUnwrap(snapshot.human).hasKnownCommanderTax)
        XCTAssertNil(snapshot.human?.commanderDamage)
        let commanders = try XCTUnwrap(snapshot.human?.commanders)
        XCTAssertEqual(commanders.first { $0.id == first }?.commanderTax, 2)
        XCTAssertEqual(commanders.first { $0.id == second }?.commanderTax, 6)
        XCTAssertEqual(commanders.first { $0.id == first }?.damageToPlayers?[owner], 7)
    }

    func testWrongAuthenticatedSeatIsRejected() throws {
        let poll = try fixture("4p-initial-player-3")
        XCTAssertThrowsError(try OnDeviceSnapshotAdapter.snapshot(poll, expectedSeatID: "player-1"))
    }

    func testNamedExileSourceRetainsOnlyItsEngineReportedPlayableAction() throws {
        // Mapping-shape regression, not a rules assertion: relocate an existing
        // engine-reported playable object to the public exile representation.
        let original = try fixture("2p-priority")
        var raw = try XCTUnwrap(original.raw.object)
        var root = try XCTUnwrap(original.snapshot?.object)
        var view = try XCTUnwrap(root["gameView"]?.object)
        var hand = try XCTUnwrap(view["myHand"]?.object)
        let id = try XCTUnwrap(view["canPlayObjects"]?["objects"]?.object?.keys.first)
        let card = try XCTUnwrap(hand.removeValue(forKey: id))
        view["myHand"] = .object(hand)
        root["gameView"] = .object(view)
        root["namedExiles"] = .array([.object(["id": .string("public-exile"), "name": .string("Playable exile"), "cards": .object([id: card])])])
        raw["snapshot"] = .object(root)
        let snapshot = try OnDeviceSnapshotAdapter.snapshot(MatchPoll(.object(raw)), expectedSeatID: original.seatID)
        let action = try XCTUnwrap(snapshot.legalActions?.first { $0.cardInstanceId == id })
        XCTAssertEqual(action.sourceZone, "exile")
        XCTAssertEqual(action.promptId, original.prompt?.id)
        XCTAssertEqual(action.messageId, Int(original.prompt!.revision))
    }

    func testPublicCombatMarksBattlefieldAttackers() throws {
        let poll = try fixture("2p-combat")
        let snapshot = try OnDeviceSnapshotAdapter.snapshot(poll, expectedSeatID: poll.seatID)
        let attacker = try XCTUnwrap(snapshot.xmage?.combat.first?.attackers.first)
        let battlefield = snapshot.players.flatMap { $0.zones.battlefield }
        XCTAssertEqual(battlefield.first { $0.id == attacker.id }?.isAttacking, true)
        XCTAssertTrue(attacker.accessibilityLabel().contains("attacking"))
    }

    func testSignedAndVariableStatsRemainExactAndHiddenDetailsAreNotRebuilt() throws {
        let original = try fixture("2p-battlefield")
        var raw = try XCTUnwrap(original.raw.object)
        var root = try XCTUnwrap(original.snapshot?.object)
        var view = try XCTUnwrap(root["gameView"]?.object)
        var players = try XCTUnwrap(view["players"]?.array)
        let index = try XCTUnwrap(players.firstIndex { !($0["battlefield"]?.object?.isEmpty ?? true) })
        var player = try XCTUnwrap(players[index].object)
        var battlefield = try XCTUnwrap(player["battlefield"]?.object)
        let id = try XCTUnwrap(battlefield.keys.first)
        var card = try XCTUnwrap(battlefield[id]?.object)
        card["power"] = .string("-2"); card["toughness"] = .string("*")
        battlefield[id] = .object(card); player["battlefield"] = .object(battlefield)
        players[index] = .object(player); view["players"] = .array(players)
        root["gameView"] = .object(view); raw["snapshot"] = .object(root)
        let shown = try OnDeviceSnapshotAdapter.snapshot(MatchPoll(.object(raw)), expectedSeatID: original.seatID)
        let mapped = try XCTUnwrap(shown.players.flatMap { $0.zones.battlefield }.first { $0.id == id })
        XCTAssertEqual(mapped.displayPower, "-2"); XCTAssertEqual(mapped.displayToughness, "*")
        card["hideInfo"] = .bool(true); card["name"] = .string("Do not reveal")
        battlefield[id] = .object(card); player["battlefield"] = .object(battlefield)
        players[index] = .object(player); view["players"] = .array(players)
        root["gameView"] = .object(view); raw["snapshot"] = .object(root)
        let hidden = try OnDeviceSnapshotAdapter.snapshot(MatchPoll(.object(raw)), expectedSeatID: original.seatID)
        let redacted = try XCTUnwrap(hidden.players.flatMap { $0.zones.battlefield }.first { $0.id == id })
        XCTAssertEqual(redacted.card.name, "Face-down card")
        XCTAssertNil(redacted.displayPower); XCTAssertNil(redacted.displayToughness)
        XCTAssertEqual(redacted.card.oracleText, "")
    }

    private func fixture(_ name: String) throws -> MatchPoll {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json", subdirectory: "OnDevice"))
        return try MatchPoll(MagicMobileOnDevice.JSONValue.decode(Data(contentsOf: url)))
    }
}
