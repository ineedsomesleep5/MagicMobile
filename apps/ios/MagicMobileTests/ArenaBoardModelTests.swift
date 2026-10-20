import CoreGraphics
import XCTest
import MagicMobileOnDevice
@testable import MagicMobile

final class ArenaBoardModelTests: XCTestCase {
    private func mana(_ id: String, source: String, label: String, produced: [String]? = nil) throws -> LegalAction {
        var json: [String: Any] = ["id": id, "type": "make_mana", "playerId": "p1", "label": label,
                                   "sourceInstanceId": source, "cardInstanceId": source]
        if let produced { json["producedMana"] = produced }
        return try JSONDecoder().decode(LegalAction.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testBoardModeFallsBackToHearth() {
        XCTAssertEqual(BoardMode.resolved("arena"), .arena)
        XCTAssertEqual(BoardMode.resolved("hearth"), .hearth)
        XCTAssertEqual(BoardMode.resolved("tavern"), .hearth)
        XCTAssertEqual(BoardMode.resolved(""), .hearth)
        XCTAssertEqual(BoardMode.defaultValue, "hearth")
    }

    func testNeedReadsXMagePaymentText() {
        let need = ArenaAutoPay.need(from: "Pay {2}{R}{R}")
        XCTAssertEqual(need.generic, 2)
        XCTAssertEqual(need.symbols["R"], 2)
        XCTAssertTrue(ArenaAutoPay.need(from: "Pay {X}{R}").symbols == ["R": 1])
        XCTAssertEqual(ArenaAutoPay.need(from: "{R/P}").symbols["R"], 1)
        XCTAssertEqual(ArenaAutoPay.need(from: "{W/U}").hybrids, [["W", "U"]])
        XCTAssertEqual(ArenaAutoPay.need(from: "{C}").symbols["C"], 1)
        XCTAssertTrue(ArenaAutoPay.need(from: "Paid").isEmpty)
    }

    func testProductionReadsManaAbilityLabels() throws {
        XCTAssertEqual(ArenaAutoPay.production(of: try mana("a", source: "m", label: "{T}: Add {R}."))?.options, [["R"]])
        XCTAssertEqual(ArenaAutoPay.production(of: try mana("a", source: "d", label: "{T}: Add {W} or {U}."))?.options, [["W"], ["U"]])
        let ring = try XCTUnwrap(ArenaAutoPay.production(of: try mana("a", source: "s", label: "{T}: Add {C}{C}.")))
        XCTAssertEqual(ring.amount, 2)
        XCTAssertTrue(ring.colorlessOnly)
        XCTAssertTrue(try XCTUnwrap(ArenaAutoPay.production(of: try mana("a", source: "t",
            label: "{T}: Add one mana of any color in your commander's color identity."))).anyColor)
        XCTAssertNil(ArenaAutoPay.production(of: try mana("a", source: "x", label: "{1}, {T}: Add {G}{G}.")))
        XCTAssertNil(ArenaAutoPay.production(of: try mana("a", source: "x", label: "{T}, Pay 1 life: Add {B}.")))
        XCTAssertEqual(ArenaAutoPay.production(of: try mana("a", source: "x", label: "Basic", produced: ["g"]))?.options, [["G"]])
        XCTAssertEqual(ArenaAutoPay.production(of: try mana("a", source: "x", label: "Tap Sol Ring", produced: ["C", "C"]))?.amount, 2)
        XCTAssertEqual(ArenaAutoPay.production(of: try mana("a", source: "x", label: "Tap", produced: ["W", "U"]))?.options, [["W"], ["U"]])
        // A painland's damage rider never reads as mana.
        XCTAssertEqual(ArenaAutoPay.production(of: try mana("a", source: "p", label: "{T}: Add {R} or {W}. Battlefield Forge deals 1 damage to you."))?.options,
                       [["R"], ["W"]])
    }

    func testColouredPipsComeFirstAndGenericTakesTheRest() throws {
        let mountain = try mana("mountain", source: "m1", label: "{T}: Add {R}.")
        let island = try mana("island", source: "i1", label: "{T}: Add {U}.")
        XCTAssertEqual(ArenaAutoPay.next(remainingText: "Pay {1}{R}", floating: [:], actions: [island, mountain]), .tap(actionID: "mountain"))
        XCTAssertEqual(ArenaAutoPay.next(remainingText: "Pay {1}", floating: [:], actions: [island]), .tap(actionID: "island"))
        XCTAssertEqual(ArenaAutoPay.next(remainingText: "Paid", floating: [:], actions: [island]), .done)
    }

    func testSingleColourSourcesBeforeDualsAndRocksThatFit() throws {
        let mountain = try mana("mountain", source: "m1", label: "{T}: Add {R}.")
        let ventsU = try mana("vents-u", source: "v1", label: "{T}: Add {U}.")
        let ventsR = try mana("vents-r", source: "v1", label: "{T}: Add {R}.")
        XCTAssertEqual(ArenaAutoPay.next(remainingText: "{R}", floating: [:], actions: [ventsU, ventsR, mountain]), .tap(actionID: "mountain"))
        let ring = try mana("ring", source: "s1", label: "{T}: Add {C}{C}.")
        // {1}: a basic, so the two-mana rock isn't half wasted; {2}: the rock.
        XCTAssertEqual(ArenaAutoPay.next(remainingText: "{1}", floating: [:], actions: [ring, mountain]), .tap(actionID: "mountain"))
        XCTAssertEqual(ArenaAutoPay.next(remainingText: "{2}", floating: [:], actions: [ring, mountain]), .tap(actionID: "ring"))
    }

    func testAnyColourSourcesWaitUntilNeeded() throws {
        let tower = try mana("tower", source: "t1", label: "{T}: Add one mana of any color in your commander's color identity.")
        let forest = try mana("forest", source: "f1", label: "{T}: Add {G}.")
        XCTAssertEqual(ArenaAutoPay.next(remainingText: "{G}", floating: [:], actions: [tower, forest]), .tap(actionID: "forest"))
        XCTAssertEqual(ArenaAutoPay.next(remainingText: "{G}", floating: [:], actions: [tower]), .tap(actionID: "tower"))
    }

    func testFloatingManaIsSpentFirst() throws {
        let mountain = try mana("mountain", source: "m1", label: "{T}: Add {R}.")
        XCTAssertEqual(ArenaAutoPay.next(remainingText: "{R}", floating: ["R": 1], actions: [mountain]), .spend(symbol: "R"))
        XCTAssertEqual(ArenaAutoPay.next(remainingText: "{1}{R}", floating: ["G": 2], actions: [mountain]), .spend(symbol: "G"))
    }

    func testNeverStartsACostItCannotFinish() throws {
        let mountain = try mana("mountain", source: "m1", label: "{T}: Add {R}.")
        let ventsU = try mana("vents-u", source: "v1", label: "{T}: Add {U}.")
        let ventsR = try mana("vents-r", source: "v1", label: "{T}: Add {R}.")
        guard case .blocked = ArenaAutoPay.next(remainingText: "{G}", floating: [:], actions: [mountain]) else { return XCTFail("needs green") }
        // A dual land counts once however many abilities it has.
        guard case .blocked = ArenaAutoPay.next(remainingText: "{3}", floating: [:], actions: [mountain, ventsU, ventsR]) else {
            return XCTFail("three owed, two sources")
        }
    }

    /// The reference game's hand: tucked until touched, open while the player keeps it open, and out of the way for any
    /// decision on the board.
    func testHandRestsTuckedUntilOpened() {
        XCTAssertEqual(ArenaHandPosture.resolve(.init()), .resting)
        var situation = ArenaHandPosture.Situation(opened: true)
        XCTAssertEqual(ArenaHandPosture.resolve(situation), .raised)
        situation.boardDecision = true
        XCTAssertEqual(ArenaHandPosture.resolve(situation), .resting)
        XCTAssertEqual(ArenaHandPosture.resolve(.init(opened: true, dragging: true)), .resting)
        XCTAssertEqual(ArenaHandPosture.resolve(.init(opened: true, spectating: true)), .resting)
    }

    func testFanSlotsCentreAndSpread() {
        let hand = ArenaLayout.landscapeLayout.hand
        let only = ArenaHandFanLayout.slot(index: 0, count: 1, posture: .raised, hand: hand)
        XCTAssertEqual(only.center.x, hand.centerX)
        XCTAssertEqual(only.rotation, 0)
        let left = ArenaHandFanLayout.slot(index: 0, count: 7, posture: .raised, hand: hand)
        let right = ArenaHandFanLayout.slot(index: 6, count: 7, posture: .raised, hand: hand)
        XCTAssertEqual(left.center.x + right.center.x, hand.centerX * 2, accuracy: 0.001)
        XCTAssertLessThan(left.rotation, 0)
        XCTAssertGreaterThan(left.center.y, ArenaHandFanLayout.slot(index: 3, count: 7, posture: .raised, hand: hand).center.y)
        let resting = ArenaHandFanLayout.slot(index: 0, count: 7, posture: .resting, hand: hand)
        XCTAssertEqual(resting.scale, hand.downScale)
        XCTAssertGreaterThan(resting.center.y, left.center.y)
    }

    /// A full raised hand stays whole on the landscape screen: the arc flattens and the fan rises until the outermost
    /// card's lowest corner clears the floor.
    func testRaisedLandscapeHandNeverRunsOffTheScreen() {
        let hand = ArenaLayout.landscapeLayout.hand
        for count in 1...12 {
            for index in 0..<count {
                let slot = ArenaHandFanLayout.slot(index: index, count: count, posture: .raised, hand: hand)
                let tilt = abs(slot.rotation) * .pi / 180
                let corner = slot.center.y + hand.card.height / 2 * CGFloat(cos(tilt)) + hand.card.width / 2 * CGFloat(sin(tilt))
                XCTAssertLessThanOrEqual(corner, hand.upFloor + 0.001, "card \(index) of \(count)")
            }
        }
        // One card keeps its place.
        XCTAssertEqual(ArenaHandFanLayout.slot(index: 0, count: 1, posture: .raised, hand: hand).center.y, hand.upY)
    }

    func testCanvasScalesEachAxisAndSizesByTheSmaller() {
        let max = ArenaCanvas(screen: CGSize(width: 956, height: 440))
        XCTAssertTrue(max.layout.landscape)
        XCTAssertEqual(max.point(CGPoint(x: 478, y: 220)), CGPoint(x: 478, y: 220))
        let small = ArenaCanvas(screen: CGSize(width: 375, height: 667))
        XCTAssertFalse(small.layout.landscape)
        XCTAssertEqual(small.scale, small.scaleY)
        XCTAssertEqual(small.length(100), 100 * 667 / 956, accuracy: 0.001)
    }

    func testCreatureLanesGrowTowardTheirOwner() {
        let layout = ArenaLayout.portraitLayout
        XCTAssertEqual(layout.maxCreatureRows, 2)
        XCTAssertEqual(ArenaLayout.landscapeLayout.maxCreatureRows, 1)
        let mine = layout.creatureLane(viewer: true, rows: 2), mineOne = layout.creatureLane(viewer: true, rows: 1)
        XCTAssertEqual(mine.minY, mineOne.minY)
        XCTAssertGreaterThan(mine.maxY, mineOne.maxY)
        let theirs = layout.creatureLane(viewer: false, rows: 2), theirsOne = layout.creatureLane(viewer: false, rows: 1)
        XCTAssertEqual(theirs.maxY, theirsOne.maxY)
        XCTAssertLessThan(theirs.minY, theirsOne.minY)
    }

    /// Landscape's front row is the table's full width (788 pt): eight cards at full size, then they shrink, and only a
    /// thirteenth scrolls.
    func testLandscapeFrontRowFitsTwelveCardsBeforeScrolling() {
        let layout = ArenaLayout.landscapeLayout
        let width = layout.creatureLane(viewer: true, rows: 1).width
        let card = layout.tiles(frames: false).tile.width
        func fit(_ count: Int, side: Int = 0) -> ArenaRowFit {
            ArenaRowFit.fit(leading: Array(repeating: 1, count: count), trailing: Array(repeating: 1, count: side),
                            width: width, maxCard: card, maxRows: layout.maxCreatureRows)
        }
        XCTAssertEqual(width, 788)
        XCTAssertEqual(fit(8).cardWidth, card)
        XCTAssertLessThan(fit(9).cardWidth, card)
        XCTAssertFalse(fit(12).overflows)
        XCTAssertGreaterThanOrEqual(fit(12).cardWidth, card * ArenaRowFit.minimumScale)
        XCTAssertTrue(fit(13).overflows)
        XCTAssertEqual(fit(13).rows, 1)
        // A planeswalker's section takes its share of the same row at the same card size.
        let walker = fit(8, side: 1)
        XCTAssertLessThan(walker.cardWidth, card)
        XCTAssertEqual(walker.trailingWidth, ArenaRowFit.sectionWidth([1], card: walker.cardWidth))
        XCTAssertEqual(fit(0, side: 2).trailingWidth, ArenaRowFit.sectionWidth([1, 1], card: card))
    }

    /// Portrait opens a second front row before cards get much smaller, and holds twelve before scrolling.
    func testPortraitFrontRowOpensASecondRowThenShrinks() {
        let layout = ArenaLayout.portraitLayout
        let width = layout.creatureLane(viewer: true, rows: 1).width
        let card = layout.tiles(frames: false).tile.width
        func fit(_ count: Int) -> ArenaRowFit {
            ArenaRowFit.fit(leading: Array(repeating: 1, count: count), trailing: [], width: width, maxCard: card,
                            maxRows: layout.maxCreatureRows, secondRowBelow: card * 0.85)
        }
        XCTAssertEqual(fit(5).rows, 1)
        XCTAssertEqual(fit(6).rows, 2)
        XCTAssertEqual(fit(6).cardWidth, card)
        XCTAssertFalse(fit(12).overflows)
        XCTAssertTrue(fit(13).overflows)
        // Two planeswalkers stack into the two rows beside ten creatures.
        let walkers = ArenaRowFit.fit(leading: Array(repeating: 1, count: 10), trailing: [1, 1], width: width, maxCard: card,
                                      maxRows: layout.maxCreatureRows, secondRowBelow: card * 0.85)
        XCTAssertFalse(walkers.overflows)
        XCTAssertEqual(walkers.rows, 2)
        XCTAssertEqual(walkers.trailingWidth, ArenaRowFit.sectionWidth([1], card: walkers.cardWidth))
        // One pile never needs two rows, however wide.
        XCTAssertEqual(ArenaRowFit.fit(leading: [4], trailing: [], width: 200, maxCard: card, maxRows: 2).rows, 1)
    }

    func testPlaneswalkersAndOtherNonCreaturesTakeTheSideSection() {
        func card(_ type: String, creature: Bool? = nil) -> ZoneCard {
            ZoneCard(instanceId: type, card: CardIdentity(name: type, typeLine: type, oracleText: nil), tapped: nil,
                     summoningSickness: nil, cardIcons: nil, counters: nil, power: nil, toughness: nil, isCreaturePermanent: creature,
                     damage: nil, isAttacking: nil, blocking: nil, attachedToInstanceId: nil)
        }
        XCTAssertEqual(ArenaFrontSection.of(card("Creature — Bear")), .creatures)
        XCTAssertEqual(ArenaFrontSection.of(card("Legendary Planeswalker — Liliana")), .side)
        XCTAssertEqual(ArenaFrontSection.of(card("Battle — Siege")), .side)
        XCTAssertEqual(ArenaFrontSection.of(card("Enchantment — Saga")), .side)
        // A crewed Vehicle is a creature while it is one.
        XCTAssertEqual(ArenaFrontSection.of(card("Artifact — Vehicle", creature: true)), .creatures)
        XCTAssertEqual(ArenaFrontSection.of(card("Artifact — Vehicle")), .side)
        XCTAssertGreaterThan(ArenaFrontSection.sideRank(card("Legendary Planeswalker — Liliana")),
                             ArenaFrontSection.sideRank(card("Enchantment — Saga")))
    }

    // MARK: Real XMage polls (Fixtures/OnDevice: the production engine, recorded on the JVM)

    private func poll(_ name: String) throws -> MatchPoll {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json", subdirectory: "OnDevice"))
        return try MatchPoll(MagicMobileOnDevice.JSONValue.decode(Data(contentsOf: url)))
    }

    /// XMage's real PLAY_MANA while casting Isamaru ({W}): Auto Pay taps a Plains with the same make_mana a tap on the
    /// land sends, and the prompt adapter accepts it as the land's UUID.
    func testAutoPayTapsALandXMageOffersForTheRealCost() throws {
        let poll = try poll("2p-mana")
        let snapshot = try OnDeviceSnapshotAdapter.snapshot(poll, expectedSeatID: poll.seatID)
        XCTAssertEqual(snapshot.manaPayment?.active, true)
        XCTAssertEqual(ArenaAutoPay.need(from: try XCTUnwrap(snapshot.manaPayment?.remainingText)).symbols, ["W": 1])
        guard case let .tap(actionID) = ArenaAutoPay.next(in: snapshot) else { return XCTFail("Auto Pay should tap a source") }
        let action = try XCTUnwrap(snapshot.legalActions?.first { $0.id == actionID })
        XCTAssertEqual(action.type, "make_mana")
        let source = try XCTUnwrap(action.sourceInstanceId)
        let land = try XCTUnwrap(snapshot.human?.zones.battlefield.first { $0.instanceId == source })
        XCTAssertTrue(land.card.typeLine.contains("Plains"))
        let command = GameCommand(type: action.type, gameId: snapshot.id, playerId: action.playerId, sourceInstanceId: source,
                                  promptId: action.promptId, messageId: action.messageId)
        XCTAssertEqual(try OnDevicePromptAdapter.answer(for: command, prompt: XCTUnwrap(poll.prompt), viewerPlayerID: snapshot.viewerID),
                       EnginePrompt.answer("uuid", .string(source)))
    }

    /// The real attacker selection: the Arena board reads it as declaring attackers (its All Attack and Done buttons)
    /// from the on-device target prompt; the priority poll before it isn't combat.
    func testCombatPhaseReadsTheRealAttackerPrompt() throws {
        let attackers = try poll("2p-attackers")
        let snapshot = try OnDeviceSnapshotAdapter.snapshot(attackers, expectedSeatID: attackers.seatID)
        XCTAssertEqual(ArenaCombatPhase.current(in: snapshot), .attackers)
        XCTAssertFalse(snapshot.promptEnvelopeV2?.targets?.isEmpty ?? true)
        XCTAssertTrue(snapshot.legalActions?.contains { $0.type == "answer_yes_no" && $0.confirmed != false } == true)
        let priority = try poll("2p-priority")
        XCTAssertNil(ArenaCombatPhase.current(in: try OnDeviceSnapshotAdapter.snapshot(priority, expectedSeatID: priority.seatID)))
        let stack = try poll("2p-stack")
        let resolving = try OnDeviceSnapshotAdapter.snapshot(stack, expectedSeatID: stack.seatID)
        XCTAssertNil(ArenaCombatPhase.current(in: resolving))
        XCTAssertEqual(ArenaAutoPay.next(in: resolving), .done)
    }

    func testExtraHandHoldsOnlyCardsPlayableFromGraveyardOrExile() throws {
        func card(_ id: String, _ name: String) -> ZoneCard {
            ZoneCard(instanceId: id, card: CardIdentity(name: name, typeLine: "Sorcery", oracleText: nil), tapped: nil,
                     summoningSickness: nil, cardIcons: nil, counters: nil, power: nil, toughness: nil, isCreaturePermanent: nil,
                     damage: nil, isAttacking: nil, blocking: nil, attachedToInstanceId: nil)
        }
        let zones = PlayerZones(library: [], hand: [card("h1", "Shock")], battlefield: [],
                                graveyard: [card("g1", "Think Twice"), card("g2", "Lava Spike")], exile: [card("e1", "Light Up the Stage"), card("e2", "Gone")],
                                command: [], stack: [])
        let player = PlayerGameState(playerId: "p1", displayName: "You", life: 40, poison: 0, commanderTax: 0, manaPool: nil,
                                     zones: zones, commanderDamage: nil)
        let actions: [LegalAction] = try ["g1", "e1", "h1"].map { id in
            try JSONDecoder().decode(LegalAction.self, from: JSONSerialization.data(withJSONObject:
                ["id": "cast-\(id)", "type": "cast_spell", "playerId": "p1", "label": "Cast", "cardInstanceId": id]))
        }
        XCTAssertEqual(ArenaExtraHand.cards(for: player, actions: actions).map(\.instanceId), ["g1", "e1"])
        XCTAssertTrue(ArenaExtraHand.cards(for: player, actions: []).isEmpty)
    }
}
