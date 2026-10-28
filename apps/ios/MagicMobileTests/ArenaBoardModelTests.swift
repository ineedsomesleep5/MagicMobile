import CoreGraphics
import XCTest
import MagicMobileOnDevice
@testable import MagicMobile

final class ArenaBoardModelTests: XCTestCase {
    private func mana(_ id: String, source: String, label: String, produced: [String]? = nil, card: String? = nil) throws -> LegalAction {
        var json: [String: Any] = ["id": id, "type": "make_mana", "playerId": "p1", "label": label,
                                   "sourceInstanceId": source, "cardInstanceId": source]
        if let produced { json["producedMana"] = produced }
        if let card { json["cardName"] = card }
        return try JSONDecoder().decode(LegalAction.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testBoardModeDefaultsToArena() {
        XCTAssertEqual(BoardMode.resolved("arena"), .arena)
        XCTAssertEqual(BoardMode.resolved("hearth"), .hearth)
        XCTAssertEqual(BoardMode.resolved("tavern"), .arena)
        XCTAssertEqual(BoardMode.resolved(""), .arena)
        XCTAssertEqual(BoardMode.defaultValue, "arena")
        XCTAssertEqual(BoardMode.allCases.first, .arena)
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
        XCTAssertEqual(ArenaAutoPay.next(remainingText: "{G}", floating: [:], actions: [tower]), .tap(actionID: "tower", color: "G"))
    }

    /// Caleb's Squirrel Girl ({1}{G}{G}{G}): two green lands and a Treasure pay the green, a colourless land the rest; the
    /// Treasure is spent only because nothing else makes the third green.
    func testTreasurePaysTheColourNothingElseMakes() throws {
        let forest = try mana("forest", source: "f1", label: "{T}: Add {G}.")
        let oran = try mana("oran", source: "o1", label: "{T}: Add {G}.")
        let swarmyard = try mana("swarmyard", source: "y1", label: "{T}: Add {C}.")
        let swamp = try mana("swamp", source: "s1", label: "{T}: Add {B}.")
        let treasure = try mana("treasure", source: "t1", label: "{T}, Sacrifice this artifact: Add one mana of any color.")
        let actions = [treasure, swamp, swarmyard, oran, forest]
        let sources = ArenaAutoPay.sources(from: actions)
        let plan = try XCTUnwrap(ArenaAutoPay.plan(need: ArenaAutoPay.need(from: "{1}{G}{G}{G}"), sources: sources))
        XCTAssertEqual(Set(plan.map(\.key)), ["f1", "o1", "t1", "y1"])
        XCTAssertEqual(plan.first { $0.key == "t1" }?.color, "G")
        if case .tap = ArenaAutoPay.next(remainingText: "{1}{G}{G}{G}", floating: [:], actions: actions) {} else { XCTFail("pays") }
        // With a second green land the Treasure stays.
        let forest2 = try mana("forest2", source: "f2", label: "{T}: Add {G}.")
        let without = try XCTUnwrap(ArenaAutoPay.plan(need: ArenaAutoPay.need(from: "{G}{G}{G}"), sources: ArenaAutoPay.sources(from: actions + [forest2])))
        XCTAssertFalse(without.contains { $0.key == "t1" })
    }

    /// A tri-land makes one mana of three colours, not two at once; a land that can tap or sacrifice is only tapped
    /// when tapping is enough (Crystal Vein).
    func testTriLandsMakeOneManaAndLandsAreTappedBeforeSacrificed() throws {
        let triome = try mana("triome", source: "x1", label: "{T}: Add {W}, {B}, or {G}.")
        XCTAssertEqual(ArenaAutoPay.production(of: triome)?.options, [["W"], ["B"], ["G"]])
        XCTAssertNil(ArenaAutoPay.plan(need: ArenaAutoPay.need(from: "{W}{B}"), sources: ArenaAutoPay.sources(from: [triome])),
                     "one tap can't pay two pips")
        let veinTap = try mana("vein-tap", source: "v1", label: "{T}: Add {C}.")
        let veinSac = try mana("vein-sac", source: "v1", label: "{T}, Sacrifice Crystal Vein: Add {C}{C}.", card: "Crystal Vein")
        let plains = try mana("plains", source: "p1", label: "{T}: Add {W}.")
        let plan = try XCTUnwrap(ArenaAutoPay.plan(need: ArenaAutoPay.need(from: "{2}"),
                                                   sources: ArenaAutoPay.sources(from: [veinSac, veinTap, plains])))
        XCTAssertEqual(Set(plan.map(\.actionID)), ["vein-tap", "plains"])
        // With nothing else it still sacrifices when it has to.
        let alone = try XCTUnwrap(ArenaAutoPay.plan(need: ArenaAutoPay.need(from: "{2}"), sources: ArenaAutoPay.sources(from: [veinSac, veinTap])))
        XCTAssertEqual(alone.map(\.actionID), ["vein-sac"])
    }

    /// Colours are checked before the first tap: two white from one Plains can't be paid, so nothing is tapped.
    func testColourShortCostIsBlockedBeforeAnyTap() throws {
        let plains = try mana("plains", source: "p1", label: "{T}: Add {W}.")
        let swamp = try mana("swamp", source: "s1", label: "{T}: Add {B}.")
        let island = try mana("island", source: "i1", label: "{T}: Add {U}.")
        guard case .blocked = ArenaAutoPay.next(remainingText: "{W}{W}", floating: [:], actions: [plains, swamp, island]) else {
            return XCTFail("only one white source")
        }
        // A tri-land is spent after the lands that make one colour, and a bounce land pays both its colours.
        let triome = try mana("triome", source: "x1", label: "{T}: Add {W}, {B}, or {G}.")
        let triomeB = try mana("triome-b", source: "x1", label: "{T}: Add {B}.")
        XCTAssertEqual(ArenaAutoPay.next(remainingText: "{B}", floating: [:], actions: [triomeB, triome, swamp]), .tap(actionID: "swamp"))
        let bounce = try XCTUnwrap(ArenaAutoPay.plan(need: ArenaAutoPay.need(from: "{B}{R}"),
                                                     sources: [ArenaAutoPay.Source(key: "c1", yields: [.init(actionID: "carnarium", symbols: ["B", "R"], cost: 10)])]))
        XCTAssertEqual(bounce.map(\.key), ["c1"])
    }

    /// A sacrifice of anything but the source itself (Ashnod's Altar) or a life payment stays a manual choice.
    func testOnlySelfSacrificeCountsAsAManaSource() throws {
        XCTAssertNil(ArenaAutoPay.production(of: try mana("a", source: "x", label: "Sacrifice a creature: Add {C}{C}.")))
        XCTAssertEqual(ArenaAutoPay.production(of: try mana("a", source: "x", label: "Sacrifice this artifact: Add one mana of any color."))?.sacrifices, true)
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

    func testPlaneswalkersBattlesAndSagasTakeTheSideSection() {
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
        // Other artifacts and enchantments join the back row, as in the current reference.
        XCTAssertEqual(ArenaFrontSection.of(card("Artifact — Vehicle")), .support)
        XCTAssertEqual(ArenaFrontSection.of(card("Artifact — Equipment")), .support)
        XCTAssertEqual(ArenaFrontSection.of(card("Enchantment")), .support)
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
        guard case let .tap(actionID, _) = ArenaAutoPay.next(in: snapshot) else { return XCTFail("Auto Pay should tap a source") }
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

    /// Gogo copying Zur's attack trigger asks for a target in the declare attackers step: that question is a target
    /// to pick, not the attack declaration (it showed "Choose attackers." and 1 Attacker, and the game could not go on).
    /// A library search there is a search.
    func testOtherQuestionsDuringDeclareAttackersAreNotCombat() throws {
        let attackers = try poll("2p-attackers")
        var snapshot = try OnDeviceSnapshotAdapter.snapshot(attackers, expectedSeatID: attackers.seatID)
        let viewer = try XCTUnwrap(snapshot.promptEnvelopeV2?.playerId)
        func prompt(_ method: String, _ kind: String, _ command: String) throws -> PromptEnvelopeV2 {
            try JSONDecoder().decode(PromptEnvelopeV2.self, from: JSONSerialization.data(withJSONObject: [
                "id": "question", "method": method, "messageId": 9, "playerId": viewer, "responseKind": kind,
                "message": "Select target activated or triggered ability you control",
                "responseCommand": ["type": command, "promptId": "question", "messageId": 9]] as [String: Any]))
        }
        snapshot.legalActions = []
        snapshot.promptEnvelopeV2 = try prompt("GAME_PICK_TARGET", "target", "choose_target")
        XCTAssertNil(ArenaCombatPhase.current(in: snapshot))
        XCTAssertNotEqual(MobilePromptPresentation.make(snapshot: snapshot, legalActions: [])?.kind, .combat)
        snapshot.promptEnvelopeV2 = try prompt("GAME_CHOOSE_CARD", "choose_card", "choose_card")
        XCTAssertNil(ArenaCombatPhase.current(in: snapshot))
        XCTAssertNotEqual(MobilePromptPresentation.make(snapshot: snapshot, legalActions: [])?.kind, .combat)
    }

    /// Target questions recorded from the real engine (target-*.json): where each one's choices can be made.
    private func targetQuestion(_ name: String) throws -> (snapshot: GameSnapshot, targetable: Set<String>) {
        let poll = try poll(name)
        let snapshot = try OnDeviceSnapshotAdapter.snapshot(poll, expectedSeatID: poll.seatID)
        return (snapshot, Set(try XCTUnwrap(snapshot.promptEnvelopeV2?.targetIds)))
    }

    /// Gogo copying Zur's attack trigger: XMage offers the abilities on the stack (Zur's trigger and Gogo's own), which
    /// the table can't show, so they are chosen on the stack. They are named by their source, not "Card details unavailable".
    func testGogosChoicesAreTheAbilitiesOnTheStack() throws {
        let (snapshot, targetable) = try targetQuestion("target-stack-ability")
        let reach = ArenaTargetReach.of(snapshot, targetable: targetable)
        XCTAssertEqual(Set(reach.stack), targetable)
        XCTAssertFalse(reach.onTable)
        XCTAssertNil(reach.opponentToShow)
        XCTAssertEqual(Set((snapshot.promptEnvelopeV2?.targets ?? []).map(\.label)),
                       ["Zur the Enchanter’s ability", "Gogo, Master of Mimicry’s ability"])
    }

    /// Counterspell with two spells on the stack chooses on the stack too.
    func testACounterspellChoosesOnTheStack() throws {
        let (snapshot, targetable) = try targetQuestion("target-stack-spell")
        let reach = ArenaTargetReach.of(snapshot, targetable: targetable)
        XCTAssertEqual(reach.stack.compactMap { id in snapshot.stackTopFirst.first { $0.id == id }?.displayName }, ["Shock", "Lightning Bolt"])
        XCTAssertEqual(Set(reach.stack), targetable)
    }

    /// A card in a graveyard is neither on the stack nor the table: the card browser shows it (the prompt's cards).
    func testGraveyardChoicesAreTheBrowsersCards() throws {
        for name in ["target-graveyard", "target-any-graveyard"] {
            let (snapshot, targetable) = try targetQuestion(name)
            let reach = ArenaTargetReach.of(snapshot, targetable: targetable)
            XCTAssertTrue(reach.stack.isEmpty, name)
            XCTAssertFalse(reach.onTable, name)
            XCTAssertNil(reach.opponentToShow, name)
            XCTAssertEqual(Set((snapshot.promptEnvelopeV2?.cards ?? []).map(\.id)), targetable, name)
        }
    }

    /// Four players, Doom Blade: the creatures are Rook's and Bryn's while the board shows Wren. The board turns to the
    /// first of them for the question, and only once: a tap on another opponent afterwards sticks.
    func testFourPlayersTurnToAnOpponentWithChoices() throws {
        let (snapshot, targetable) = try targetQuestion("target-four-player-creature")
        XCTAssertEqual(snapshot.opponent?.displayName, "Wren")
        let reach = ArenaTargetReach.of(snapshot, targetable: targetable)
        XCTAssertFalse(reach.onTable)
        XCTAssertEqual(Set(reach.hiddenOpponents.compactMap { id in snapshot.players.first { $0.playerId == id }?.displayName }), ["Rook", "Bryn"])
        var tracker = BoardFocusTracker()
        tracker.observe(snapshot, followTurns: true)
        tracker.showTargets(BoardOpponentFocus.snapshot(snapshot, selecting: tracker.focusedID), targetable: targetable)
        let turned = BoardOpponentFocus.snapshot(snapshot, selecting: tracker.focusedID)
        XCTAssertEqual(tracker.focusedID, reach.opponentToShow)
        XCTAssertTrue(ArenaTargetReach.of(turned, targetable: targetable).onTable)
        let wren = try XCTUnwrap(snapshot.players.first { $0.displayName == "Wren" }?.playerId)
        tracker.select(wren)
        tracker.showTargets(BoardOpponentFocus.snapshot(snapshot, selecting: tracker.focusedID), targetable: targetable)
        XCTAssertEqual(tracker.focusedID, wren)
    }

    /// Shock in the same game can aim at you, so the table has a choice: the board stays, and the swap row marks the others.
    func testFourPlayersStayWhenTheTableHasAChoice() throws {
        let (snapshot, targetable) = try targetQuestion("target-four-player")
        let reach = ArenaTargetReach.of(snapshot, targetable: targetable)
        XCTAssertTrue(reach.onTable)
        XCTAssertNil(reach.opponentToShow)
        XCTAssertEqual(Set(reach.hiddenOpponents.compactMap { id in snapshot.players.first { $0.playerId == id }?.displayName }), ["Rook", "Bryn"])
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

    /// Caleb's replacement-effect question: two answers and their "Remember answer" twins become two cards and a toggle.
    func testChoiceListPairsRememberedAnswersAndNamesTheCard() {
        let options = ArenaChoiceList.options([
            ("a", "Doubling Season: If an effect would create one or more tokens, it creates twice that many instead."),
            ("b", "Chatterfang, Squirrel General: If one or more tokens would be created, those plus that many Squirrels are created."),
            ("c", "Remember answer: Doubling Season: If an effect would create one or more tokens, it creates twice that many instead."),
            ("d", "Remember answer: Chatterfang, Squirrel General: If one or more tokens would be created, those plus that many Squirrels are created."),
        ])
        XCTAssertEqual(options.map(\.id), ["a", "b"])
        XCTAssertEqual(options.map(\.rememberID), ["c", "d"])
        XCTAssertEqual(options.map(\.name), ["Doubling Season", "Chatterfang, Squirrel General"])
        XCTAssertTrue(options[0].text.hasPrefix("If an effect"))
        XCTAssertNil(ArenaChoiceList.options([("x", "Elf")]).first?.name, "a plain word names no card")
        XCTAssertEqual(ArenaChoiceList.options([("y", "Doubling Season [8f2]: If an effect would create tokens…")]).first?.name,
                       "Doubling Season", "XMage's id after the name")
        XCTAssertEqual(ArenaChoiceList.colorSymbol("Red"), "R")
        XCTAssertEqual(ArenaChoiceList.colorSymbol("Green mana"), "G")
        XCTAssertNil(ArenaChoiceList.colorSymbol("Goblin"))
    }

    func testLoyaltyCostsSplitFromPlaneswalkerAbilities() {
        XCTAssertEqual(ArenaLoyalty.split("+1: Create a 2/2 black Zombie.")?.cost, "+1")
        XCTAssertEqual(ArenaLoyalty.split("-4: Each player sacrifices two creatures.")?.cost, "−4")
        XCTAssertEqual(ArenaLoyalty.split("−9: Each opponent chooses…")?.text, "Each opponent chooses…")
        XCTAssertEqual(ArenaLoyalty.split("0: Draw a card.")?.cost, "0")
        XCTAssertNil(ArenaLoyalty.split("Whenever a creature dies, draw a card."))
    }

    /// The X pill steps through XMage's values and starts at the most your mana pays.
    func testAmountRangeStepsAndAffordableX() {
        let range = ArenaAmountRange(amounts: [0, 1, 2, 3, 4, 5, 6, 7], minimum: nil, maximum: nil)
        XCTAssertEqual(range.step(3, by: 5), 7)
        XCTAssertEqual(range.step(3, by: -5), 0)
        XCTAssertEqual(range.step(3, by: 1), 4)
        XCTAssertEqual(ArenaAmountRange(amounts: nil, minimum: 1, maximum: nil).maximum, 100, "an open maximum stops 99 above")
        XCTAssertEqual(ArenaAmountRange(amounts: nil, minimum: -3, maximum: -1).values, [-3, -2, -1], "XMage's own bounds, negative too")
        XCTAssertEqual(ArenaAmountRange(amounts: [0, 2, 4], minimum: nil, maximum: nil).clamp(3), 2)
        XCTAssertEqual(ArenaAmountRange.affordableX(cost: "{X}{R}", sources: 11), 10, "Devil's Play with eleven mana")
        XCTAssertEqual(ArenaAmountRange.affordableX(cost: "{X}{X}{G}{U}", sources: 8), 3, "Hydroid Krasis-style double X")
        XCTAssertEqual(ArenaAmountRange.affordableX(cost: "{X}{2}{R}", sources: 2), 0)
        XCTAssertNil(ArenaAmountRange.affordableX(cost: "{2}{R}", sources: 9))
    }

    func testSplitRowsNameTheirCardAndLethalDamage() {
        XCTAssertEqual(ArenaSplit.name(of: "Grizzly Bears, P/T: 2/2"), "Grizzly Bears")
        XCTAssertEqual(ArenaSplit.name(of: "Serra Angel [4cb]"), "Serra Angel")
        XCTAssertEqual(ArenaSplit.lethal(toughness: 4, damage: 1, deathtouch: false), 3)
        XCTAssertEqual(ArenaSplit.lethal(toughness: 4, damage: 0, deathtouch: true), 1)
        XCTAssertEqual(ArenaSplit.lethal(toughness: 2, damage: 5, deathtouch: false), 1)
    }

    func testGlossaryExplainsTheKeywordsACardHas() {
        let entries = ArenaKeywordGlossary.entries(rules: "Flying, vigilance\nFlashback {1}{G}")
        XCTAssertEqual(entries.map(\.keyword), ["Flying", "Vigilance", "Flashback"])
        XCTAssertTrue(ArenaKeywordGlossary.entries(rules: "Flashback {2}").allSatisfy { $0.keyword != "Flash" }, "flashback isn't flash")
        XCTAssertTrue(ArenaKeywordGlossary.entries(rules: "Equipped creature gets +1/+1.").isEmpty, "equipped isn't equip")
    }

    /// A carried card plays anywhere on the table above the hand, your land row and the table's right side included,
    /// but not over the controls corner, back in the hand, or after a wiggle or a short slide (Caleb, 2026-10-21).
    func testDropsCountOverTheWholeTableOutOfTheCorner() {
        let landscape = ArenaLayout.landscapeLayout
        XCTAssertTrue(landscape.drops(at: CGPoint(x: 240, y: 320), from: CGPoint(x: 330, y: 300)), "your land row, from a popped card")
        XCTAssertTrue(landscape.drops(at: CGPoint(x: 820, y: 150), from: CGPoint(x: 500, y: 330)), "the table's right side")
        XCTAssertFalse(landscape.drops(at: CGPoint(x: 780, y: 330), from: CGPoint(x: 500, y: 330)), "the controls corner")
        XCTAssertFalse(landscape.drops(at: CGPoint(x: 500, y: 400), from: CGPoint(x: 500, y: 300)), "back in the hand")
        XCTAssertFalse(landscape.drops(at: CGPoint(x: 330, y: 280), from: CGPoint(x: 330, y: 300)), "a wiggle")
        XCTAssertFalse(landscape.drops(at: CGPoint(x: 380, y: 300), from: CGPoint(x: 330, y: 300)), "a short slide sideways")
        let portrait = ArenaLayout.portraitLayout
        XCTAssertTrue(portrait.drops(at: CGPoint(x: 100, y: 660), from: CGPoint(x: 150, y: 720)), "your land row")
        XCTAssertTrue(portrait.drops(at: CGPoint(x: 220, y: 120), from: CGPoint(x: 220, y: 720)), "the far side")
        XCTAssertFalse(portrait.drops(at: CGPoint(x: 100, y: 760), from: CGPoint(x: 150, y: 600)), "the hand")
    }

    /// Your piles leave room between them for their count badges, which hang 8 pt past a pile's right edge, and clear
    /// your medallion (Caleb, 2026-10-21: the badges ran over the next pile).
    func testViewerPilesLeaveRoomForTheirCounts() {
        for layout in [ArenaLayout.landscapeLayout, ArenaLayout.portraitLayout] {
            let half = layout.viewerPile.width / 2
            let row = [layout.viewerGraveyard, layout.viewerLibrary] + (layout.landscape ? [layout.viewerExile] : [])
            let piles = row.sorted { $0.x < $1.x }
            for (left, right) in zip(piles, piles.dropFirst()) where abs(left.y - right.y) < 1 {
                XCTAssertGreaterThanOrEqual((right.x - half) - (left.x + half), 10, "a count badge's room in \(layout.landscape ? "landscape" : "portrait")")
            }
            XCTAssertLessThan(layout.viewerMedallion.x + layout.viewerMedallionDiameter / 2, piles[0].x - half,
                              "the first pile clears your medallion")
        }
    }

    /// Your commander on an opponent's battlefield is noticed, with who has it (Caleb, 2026-10-21: Necromantic Selection).
    func testCommanderTakenByAnOpponentIsNoticed() throws {
        func snapshot(theirs: [[String: Any]]) throws -> GameSnapshot {
            func zones(_ field: [[String: Any]]) -> [String: Any] {
                ["library": [], "hand": [], "battlefield": field, "graveyard": [], "exile": [], "command": [], "stack": [], "handCount": 1, "libraryCount": 50]
            }
            let players: [[String: Any]] = [
                ["playerId": "a", "displayName": "You", "life": 40, "poison": 0, "commanderTax": 0, "zones": zones([]),
                 "commanders": [["id": "c1", "name": "Chatterfang, Squirrel General", "ownerPlayerId": "a"]]],
                ["playerId": "b", "displayName": "AI 1", "life": 32, "poison": 0, "commanderTax": 0, "zones": zones(theirs)]]
            let json: [String: Any] = ["id": "match", "phase": "PRECOMBAT_MAIN", "turn": 9, "activePlayerId": "b", "viewerPlayerId": "a",
                                       "priorityPlayerId": "b", "players": players, "log": []]
            return try JSONDecoder().decode(GameSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        }
        XCTAssertEqual(ArenaCommanderSteal.taken(in: try snapshot(theirs: [])), [])
        let stolen = try snapshot(theirs: [["instanceId": "x", "card": ["name": "Chatterfang, Squirrel General", "typeLine": "Legendary Creature"]]])
        let taken = ArenaCommanderSteal.taken(in: stolen)
        XCTAssertEqual(taken, ["Chatterfang, Squirrel General|b"])
        let notice = ArenaCommanderSteal.notice(taken[0], snapshot: stolen)
        XCTAssertTrue(notice.hasPrefix("AI 1 took Chatterfang, Squirrel General."), notice)
    }

    /// The spread hand: one flat row of whole cards over the rail, never overlapping; four fit, more swipe sideways and
    /// the last swipe shows the last card whole; landscape has no spread (Caleb, 2026-10-21).
    func testSpreadHandIsOneFlatRowThatSwipes() {
        let hand = ArenaLayout.portraitLayout.hand
        func frames(_ count: Int, scroll: CGFloat = 0) -> [CGRect] {
            (0..<count).map { index in
                let slot = ArenaHandFanLayout.slot(index: index, count: count, posture: .spread, hand: hand, scroll: scroll)
                XCTAssertEqual(slot.rotation, 0)
                let size = CGSize(width: hand.card.width * slot.scale, height: hand.card.height * slot.scale)
                return CGRect(x: slot.center.x - size.width / 2, y: slot.center.y - size.height / 2, width: size.width, height: size.height)
            }
        }
        for count in [1, 4, 9] {
            let row = frames(count)
            XCTAssertEqual(Set(row.map(\.midY)).count, 1, "one row")
            for (a, b) in zip(row, row.dropFirst()) { XCTAssertGreaterThan(b.minX, a.maxX, "\(count) cards don't overlap") }
            XCTAssertLessThanOrEqual(row[0].maxY, hand.spreadBottom! + 0.5)
        }
        XCTAssertTrue(frames(4).allSatisfy { $0.minX >= 0 && $0.maxX <= 440 }, "four fit whole")
        let grid = ArenaHandFanLayout.spread(count: 9, hand: hand)!
        XCTAssertGreaterThan(grid.maxScroll, 0)
        XCTAssertGreaterThanOrEqual(frames(9)[0].minX, 0, "the first card shows whole")
        XCTAssertLessThanOrEqual(frames(9, scroll: grid.maxScroll)[8].maxX, 440, "a full swipe shows the last card whole")
        XCTAssertEqual(frames(9, scroll: 10_000)[8].maxX, frames(9, scroll: grid.maxScroll)[8].maxX, "the swipe stops at the end")
        XCTAssertNil(ArenaHandFanLayout.spread(count: 5, hand: ArenaLayout.landscapeLayout.hand))
        XCTAssertEqual(ArenaHandPosture.resolve(.init(spread: true)), .spread)
        XCTAssertEqual(ArenaHandPosture.resolve(.init(spread: true, boardDecision: true)), .resting, "it steps aside for a decision")
    }

    func testBoardWipeRecapNamesTheSpellAndWhatWent() {
        let deaths = (1...4).map { BoardFXEvent.leftBattlefield(cardID: "c\($0)", playerID: "a", to: .graveyard, tint: .green) }
            + [BoardFXEvent.leftBattlefield(cardID: "e", playerID: "b", to: .exile, tint: .blue)]
        XCTAssertEqual(ArenaSweepRecap.text(spell: "Necromantic Selection", events: deaths),
                       "Necromantic Selection: 4 to the graveyard, 1 exiled")
        XCTAssertNil(ArenaSweepRecap.text(spell: "Murder", events: Array(deaths.prefix(1))), "one removal needs no recap")
    }

    /// The landscape stack card sits under the opponent's piles and above the raised phase strip and its pills.
    func testLandscapeStackCardClearsThePilesAndTheCorner() {
        let layout = ArenaLayout.landscapeLayout
        XCTAssertGreaterThanOrEqual(layout.stack.minY, layout.opponentLibrary.y + layout.opponentPile.height / 2)
        XCTAssertLessThan(layout.stack.maxY, layout.phaseStripRaisedY - 24)
    }

    /// The stack card steps aside for the object the player tucked and while they pick on the table; brought back, it stays.
    func testTheStackTucksForItsTopObjectAndWhilePicking() {
        XCTAssertFalse(ArenaStackTuck.isTucked(top: "a", tuckedTop: nil, peekTop: nil, picking: false))
        XCTAssertTrue(ArenaStackTuck.isTucked(top: "a", tuckedTop: "a", peekTop: nil, picking: false))
        // The next spell or ability shows again.
        XCTAssertFalse(ArenaStackTuck.isTucked(top: "b", tuckedTop: "a", peekTop: nil, picking: false))
        // Picking a target tucks it; the tab brings it back for that object.
        XCTAssertTrue(ArenaStackTuck.isTucked(top: "b", tuckedTop: nil, peekTop: nil, picking: true))
        XCTAssertFalse(ArenaStackTuck.isTucked(top: "b", tuckedTop: nil, peekTop: "b", picking: true))
        XCTAssertTrue(ArenaStackTuck.isTucked(top: "c", tuckedTop: nil, peekTop: "b", picking: true))
    }
}
