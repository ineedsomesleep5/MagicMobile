import XCTest
@testable import MagicMobile

final class BoardEventTimelineTests: XCTestCase {
    private func card(_ id: String, _ name: String = "Grizzly Bears", cost: String? = "{1}{G}", type: String = "Creature — Bear",
                      damage: Int? = nil, counters: [String: Int]? = nil, attacking: Bool? = nil,
                      blocking: [String]? = nil) -> ZoneCard {
        var identity = CardIdentity(name: name, typeLine: type, oracleText: nil)
        identity.manaCost = cost
        return ZoneCard(instanceId: id, card: identity, tapped: nil, summoningSickness: nil, cardIcons: nil,
                        counters: counters, power: 2, toughness: 2, isCreaturePermanent: true, damage: damage,
                        isAttacking: attacking, blocking: blocking, attachedToInstanceId: nil)
    }

    private func player(_ id: String, life: Int = 40, hand: [ZoneCard] = [], battlefield: [ZoneCard] = [],
                        graveyard: [ZoneCard] = [], exile: [ZoneCard] = [], command: [ZoneCard] = []) -> PlayerGameState {
        PlayerGameState(playerId: id, displayName: id, life: life, poison: 0, commanderTax: 0, manaPool: nil,
                        zones: PlayerZones(library: [], hand: hand, battlefield: battlefield, graveyard: graveyard,
                                           exile: exile, command: command, stack: []),
                        commanderDamage: nil)
    }

    private func snapshot(_ players: [PlayerGameState], id: String = "match", revision: Int = 1,
                          step: String? = nil) -> GameSnapshot {
        GameSnapshot(id: id, source: "xmage-ondevice", activePlayerId: "a", phase: "main", step: step, turn: 3,
                     priorityPlayerId: "a", waitingOnPlayerId: nil, promptText: nil, players: players, log: [],
                     legalActions: nil, choicePrompt: nil, promptEnvelope: nil, promptEnvelopeV2: nil,
                     startupOpeningPrompts: nil, xmage: nil, engineHealth: nil, bridgeRevision: revision,
                     xmageCycle: nil, pendingStatus: nil, manaPayment: nil, gameStatus: nil,
                     winnerPlayerIds: nil, endReason: nil, viewerPlayerId: "a")
    }

    private func events(_ old: GameSnapshot, _ new: GameSnapshot) -> [BoardFXEvent] {
        BoardEventDiffer.events(from: BoardFXState(snapshot: old), to: BoardFXState(snapshot: new))
    }

    private func state(step: String = "main", lives: [String: Int] = ["a": 40, "b": 40],
                       cards: [BoardFXState.Card], stack: [BoardFXState.StackItem] = [],
                       defenders: [String: String] = [:]) -> BoardFXState {
        BoardFXState(gameID: "match", step: step, lives: lives,
                     cards: Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) }), stack: stack, defenders: defenders)
    }

    private func fxCard(_ id: String, _ player: String, _ zone: BoardFXZone = .battlefield, name: String = "Bear",
                        attacking: Bool = false, blocking: [String] = [], damage: Int = 0,
                        land: Bool = false, token: Bool = false) -> BoardFXState.Card {
        BoardFXState.Card(id: id, playerID: player, zone: zone, name: name, tint: .green, damage: damage, counters: 0,
                          attacking: attacking, blocking: blocking, isLand: land, isToken: token)
    }

    func testCreaturePlayedStraightFromHandIsShowcasedButLandsAreNot() {
        let bear = card("bear")
        let forest = card("forest", "Forest", cost: nil, type: "Basic Land — Forest")
        let result = events(snapshot([player("a", hand: [bear, forest]), player("b")]),
                            snapshot([player("a", battlefield: [bear, forest]), player("b")], revision: 2))
        XCTAssertEqual(result, [
            .enteredBattlefield(cardID: "bear", playerID: "a", from: .hand, tint: .green, entrance: .showcase),
            .enteredBattlefield(cardID: "forest", playerID: "a", from: .hand, tint: .colorless, entrance: .plain),
        ])
    }

    func testDyingCreatureWithNewObjectIDIsMatchedToGraveyardByName() {
        let old = snapshot([player("a"), player("b", battlefield: [card("bear")])])
        let new = snapshot([player("a"), player("b", graveyard: [card("bear-2")])], revision: 2)
        XCTAssertEqual(events(old, new), [.leftBattlefield(cardID: "bear", playerID: "b", to: .graveyard, tint: .green)])
    }

    func testCombatOrdersDamageBeforeLifeAndReportsAttackers() {
        let old = snapshot([player("a", battlefield: [card("atk")]), player("b", battlefield: [card("blk")])])
        let new = snapshot([player("a", battlefield: [card("atk", attacking: true)]),
                            player("b", life: 37, battlefield: [card("blk", damage: 2)])], revision: 2)
        XCTAssertEqual(events(old, new), [
            .attackDeclared(cardID: "atk", tint: .green),
            .damageMarked(cardID: "blk", amount: 2),
            .lifeChanged(playerID: "b", delta: -3),
        ])
    }

    func testCountersAndLifeGainAreReported() {
        let old = snapshot([player("a", battlefield: [card("bear")]), player("b")])
        let new = snapshot([player("a", life: 43, battlefield: [card("bear", counters: ["+1/+1": 2])]), player("b")], revision: 2)
        XCTAssertEqual(events(old, new), [.countersAdded(cardID: "bear", amount: 2), .lifeChanged(playerID: "a", delta: 3)])
    }

    func testDifferentGameIsACutWithoutEvents() {
        let old = snapshot([player("a", battlefield: [card("bear")]), player("b")], id: "one")
        let new = snapshot([player("a", life: 10), player("b")], id: "two")
        XCTAssertEqual(events(old, new), [])
    }

    func testUnchangedBoardProducesNoEvents() {
        let board = snapshot([player("a", battlefield: [card("bear")]), player("b", life: 20)])
        XCTAssertEqual(events(board, board), [])
    }

    func testTintFromManaCostAndTokens() {
        XCTAssertEqual(BoardFXTint(card: CardIdentity(name: "x", typeLine: "Artifact", oracleText: nil, manaCost: "{3}")), .colorless)
        XCTAssertEqual(BoardFXTint(card: CardIdentity(name: "x", typeLine: "Instant", oracleText: nil, manaCost: "{R}")), .red)
        XCTAssertEqual(BoardFXTint(card: CardIdentity(name: "x", typeLine: "Instant", oracleText: nil, manaCost: "{U/R}")), .multicolor)
        XCTAssertEqual(BoardFXTint(card: CardIdentity(name: "x", typeLine: "Token", oracleText: nil, tokenColors: ["White"])), .white)
    }

    func testManaValue() {
        XCTAssertEqual(BoardFXManaValue.of("{3}{B}{B}"), 5)
        XCTAssertEqual(BoardFXManaValue.of("{X}{R}"), 1)
        XCTAssertEqual(BoardFXManaValue.of("{2/W}{G/P}{10}"), 13)
        XCTAssertEqual(BoardFXManaValue.of(nil), 0)
    }

    func testBoardWipeKeepsLifeAndCapsDecoration() {
        let many = (0..<30).map { card("c\($0)") }
        let old = snapshot([player("a", battlefield: many), player("b")])
        let new = snapshot([player("a", life: 35), player("b")], revision: 2)
        let planned = BoardFXScheduler.schedule(events(old, new), level: .full)
        XCTAssertEqual(planned.count, BoardFXScheduler.decorativeLimit + 1)
        XCTAssertEqual(planned.last?.event, .lifeChanged(playerID: "a", delta: -5))
        XCTAssertGreaterThan(planned.last!.delay, planned.first!.delay)
        XCTAssertEqual(Set(planned.map(\.id)).count, planned.count)
    }

    func testLevelsAndReduceMotion() {
        let event = BoardFXEvent.lifeChanged(playerID: "a", delta: -1)
        XCTAssertEqual(BoardFXScheduler.schedule([event], level: .off), [])
        XCTAssertEqual(BoardFXScheduler.schedule([event], level: .reduced).first?.usesMotion, false)
        XCTAssertEqual(BoardFXLevel.resolved(stored: "full", reduceMotion: true), .reduced)
        XCTAssertEqual(BoardFXLevel.resolved(stored: "off", reduceMotion: true), .off)
        XCTAssertEqual(BoardFXLevel.resolved(stored: "garbage", reduceMotion: false), .full)
    }
}

extension BoardEventTimelineTests {
    func testSpellShowcaseIsReadableAndItsPermanentLandsAfterIt() {
        let old = state(cards: [fxCard("spell", "b", .hand, name: "Serra Angel")])
        let cast = state(cards: [fxCard("spell", "b", .stack, name: "Serra Angel")],
                         stack: [.init(id: "s1", name: "Serra Angel", controllerID: "b", tint: .white, manaValue: 5)])
        let castEvents = BoardEventDiffer.events(from: old, to: cast)
        XCTAssertEqual(castEvents, [.spellCast(stackID: "s1", name: "Serra Angel", controllerID: "b", tint: .white, weight: .spell)])
        let showcase = BoardFXScheduler.schedule(castEvents, level: .full)[0]
        XCTAssertGreaterThanOrEqual(showcase.duration, 2.4, "the card holds long enough to read")

        // Resolved with a new object ID: it flies from the stack, without a second showcase.
        let resolved = state(cards: [fxCard("angel-2", "b", name: "Serra Angel")])
        XCTAssertEqual(BoardEventDiffer.events(from: cast, to: resolved), [
            .enteredBattlefield(cardID: "angel-2", playerID: "b", from: .stack, tint: .green, entrance: .plain),
        ])

        // Cast and resolved inside one transition batch: the arrival waits for the showcase.
        let both = BoardFXScheduler.schedule([
            .spellCast(stackID: "s2", name: "Shock", controllerID: "b", tint: .red, weight: .spell),
            .enteredBattlefield(cardID: "bear", playerID: "b", from: .stack, tint: .green, entrance: .plain),
        ], level: .full)
        XCTAssertGreaterThanOrEqual(both[1].delay, both[0].end - 0.31)
    }

    func testLaterSnapshotWaitsForAShowcaseStillPlaying() {
        let start = Date(timeIntervalSince1970: 5_000)
        var director = BoardFXDirector()
        let bear = card("bear")
        director.ingest(snapshot([player("a"), player("b", hand: [bear])]), level: .full, now: start)
        let first = director.ingest(snapshot([player("a"), player("b", battlefield: [bear])], revision: 2), level: .full, now: start)
        XCTAssertEqual(first.first?.event, .enteredBattlefield(cardID: "bear", playerID: "b", from: .hand, tint: .green, entrance: .showcase))
        let later = start.addingTimeInterval(0.5)
        let second = director.ingest(snapshot([player("a", life: 38), player("b", battlefield: [bear])], revision: 3), level: .full, now: later)
        let landed = start.addingTimeInterval(first[0].handoff)
        XCTAssertEqual(later.addingTimeInterval(second[0].delay).timeIntervalSince1970, landed.timeIntervalSince1970, accuracy: 0.001)
    }

    func testCombatDamageStrikesTheBlockerThenDamageLandsOnImpact() {
        let blockers = state(step: "declare-blockers", cards: [
            fxCard("atk", "a", attacking: true), fxCard("blk", "b", blocking: ["atk"]),
            fxCard("free", "a", name: "Wolf", attacking: true),
        ], defenders: ["atk": "b", "free": "b"])
        let damage = state(step: "combat-damage", lives: ["a": 40, "b": 38], cards: [
            fxCard("atk", "a", attacking: true, damage: 2), fxCard("blk", "b", blocking: ["atk"], damage: 2),
            fxCard("free", "a", name: "Wolf", attacking: true),
        ], defenders: ["atk": "b", "free": "b"])
        let result = BoardEventDiffer.events(from: blockers, to: damage)
        XCTAssertEqual(result, [
            .combatStrike(attackerID: "atk", target: .card("blk"), tint: .green),
            .combatStrike(attackerID: "free", target: .player("b"), tint: .green),
            .damageMarked(cardID: "atk", amount: 2),
            .damageMarked(cardID: "blk", amount: 2),
            .lifeChanged(playerID: "b", delta: -2),
        ])
        let planned = BoardFXScheduler.schedule(result, level: .full)
        let impact = planned.filter { if case .combatStrike = $0.event { return true }; return false }.map(\.handoff).max()!
        for fx in planned where fx.event.order > planned[0].event.order {
            if case .combatStrike = fx.event { continue }
            XCTAssertGreaterThanOrEqual(fx.delay, impact, "\(fx.event) waits for the hit")
        }
        // The next snapshot inside combat damage does not strike again.
        XCTAssertFalse(BoardEventDiffer.events(from: damage, to: state(step: "end-combat", cards: [])).contains {
            if case .combatStrike = $0 { return true }; return false
        })
    }

    func testBlockDeclarationIsReported() {
        let old = state(step: "declare-attackers", cards: [fxCard("atk", "a", attacking: true), fxCard("blk", "b")])
        let new = state(step: "declare-blockers", cards: [fxCard("atk", "a", attacking: true), fxCard("blk", "b", blocking: ["atk"])])
        XCTAssertEqual(BoardEventDiffer.events(from: old, to: new), [.blockDeclared(cardID: "blk", attackerID: "atk")])
    }

    func testCommanderCastAndEntranceAreCeremonial() {
        let inCommand = state(cards: [fxCard("cmd", "a", .command, name: "Atraxa")])
        let cast = state(cards: [], stack: [.init(id: "s", name: "Atraxa", controllerID: "a", tint: .multicolor, manaValue: 4)])
        XCTAssertEqual(BoardEventDiffer.events(from: inCommand, to: cast, commanders: ["Atraxa"]),
                       [.spellCast(stackID: "s", name: "Atraxa", controllerID: "a", tint: .multicolor, weight: .commander)])
        let entered = state(cards: [fxCard("cmd-2", "a", name: "Atraxa")])
        XCTAssertEqual(BoardEventDiffer.events(from: cast, to: entered, commanders: ["Atraxa"]),
                       [.enteredBattlefield(cardID: "cmd-2", playerID: "a", from: .stack, tint: .green, entrance: .commander)])
        let big = state(cards: [], stack: [.init(id: "e", name: "Eldrazi", controllerID: "a", tint: .colorless, manaValue: 10)])
        XCTAssertEqual(BoardEventDiffer.events(from: state(cards: []), to: big).first,
                       .spellCast(stackID: "e", name: "Eldrazi", controllerID: "a", tint: .colorless, weight: .big))
    }

    func testDirectorStartsQuietThenPlaysAndExpiresTransitions() {
        let start = Date(timeIntervalSince1970: 1_000)
        var director = BoardFXDirector()
        XCTAssertEqual(director.ingest(snapshot([player("a"), player("b")]), level: .full, now: start), [])
        let played = director.ingest(snapshot([player("a", life: 38), player("b")], revision: 2), level: .full, now: start)
        XCTAssertEqual(played.map(\.event), [.lifeChanged(playerID: "a", delta: -2)])
        XCTAssertEqual(director.active.count, 1)
        director.prune(now: start.addingTimeInterval(5))
        XCTAssertEqual(director.active, [])
        director.ingest(snapshot([player("a", life: 1), player("b")], id: "other"), level: .full, now: start)
        XCTAssertEqual(director.active, [], "a different game never animates from the old board")
    }

    func testArrivalHidesTileUntilFlightLandsAndDepartureKeepsItsFace() {
        let start = Date(timeIntervalSince1970: 2_000)
        let bear = card("bear")
        var director = BoardFXDirector()
        director.ingest(snapshot([player("a", hand: [bear]), player("b", battlefield: [card("wolf", "Wolf")])]), level: .full, now: start)
        director.ingest(snapshot([player("a", battlefield: [bear]), player("b")], revision: 2), level: .full, now: start)
        XCTAssertEqual(director.subjects["bear"]?.card.name, "Grizzly Bears")
        XCTAssertEqual(director.subjects["wolf"]?.card.name, "Wolf", "departed card face comes from the previous board")
        let hidden = try? XCTUnwrap(director.cardMotion(viewerID: "a").hidden["bear"])
        let arrival = director.active.first { $0.scheduled.event.subjectID == "bear" }!.scheduled
        XCTAssertEqual(hidden, [BoardFXCardMotion.Hidden(batch: start, from: 0, until: arrival.landing)])
        XCTAssertEqual(arrival.landing, arrival.delay + arrival.duration * BoardFXScheduler.landingFraction(.showcase))
        director.prune(now: start.addingTimeInterval(10))
        XCTAssertEqual(director.subjects, [:])
        XCTAssertEqual(director.cardMotion(viewerID: "a"), BoardFXCardMotion())
    }

    func testAttackersLungeAndHoldTheirStanceTowardTheOpponent() {
        let start = Date(timeIntervalSince1970: 3_000)
        let old = snapshot([player("a", battlefield: [card("mine")]), player("b", battlefield: [card("theirs")])])
        let new = snapshot([player("a", battlefield: [card("mine", attacking: true)]),
                            player("b", battlefield: [card("theirs", blocking: ["mine"])])], revision: 2)
        var full = BoardFXDirector()
        full.ingest(old, level: .full, now: start)
        full.ingest(new, level: .full, now: start)
        let motion = full.cardMotion(viewerID: "a")
        XCTAssertEqual(motion.lunges["mine"]?.direction, -1)
        XCTAssertEqual(motion.stances["mine"], .init(kind: .attacking, direction: -1, moves: true))
        XCTAssertEqual(motion.stances["theirs"], .init(kind: .blocking, direction: 1, moves: true))
        var reduced = BoardFXDirector()
        reduced.ingest(old, level: .reduced, now: start)
        reduced.ingest(new, level: .reduced, now: start)
        XCTAssertEqual(reduced.cardMotion(viewerID: "a").lunges, [:])
        XCTAssertEqual(reduced.cardMotion(viewerID: "a").stances["mine"]?.moves, false, "reduced keeps the glow only")
        var off = BoardFXDirector()
        off.ingest(old, level: .off, now: start)
        off.ingest(new, level: .off, now: start)
        XCTAssertEqual(off.cardMotion(viewerID: "a"), BoardFXCardMotion())
    }
}

/// First strike as its own beat. Shared transition cases: combat-cases.json (ParityGoldenTests).
extension BoardEventTimelineTests {
    private func combatCard(_ id: String, _ name: String, icons: [String] = [], rules: String? = nil, attacking: Bool? = nil,
                            blocking: [String]? = nil) -> ZoneCard {
        ZoneCard(instanceId: id, card: CardIdentity(name: name, typeLine: "Creature", oracleText: rules, manaCost: "{R}"),
                 tapped: nil, summoningSickness: false,
                 cardIcons: icons.map { XmageCardIcon(iconType: $0, resourceName: nil, category: "ABILITY", text: nil, hint: nil) },
                 counters: nil, power: 6, toughness: 4, isCreaturePermanent: true, damage: nil,
                 isAttacking: attacking, blocking: blocking, attachedToInstanceId: nil)
    }

    private func combatSnapshot(step: String, revision: Int, lifeA: Int = 40, a: [ZoneCard], b: [ZoneCard],
                                graveyardA: [ZoneCard] = [], blocked: Bool) -> GameSnapshot {
        let base = snapshot([player("a", life: lifeA, battlefield: a, graveyard: graveyardA), player("b", battlefield: b)],
                            revision: revision, step: step)
        let attackers = b.filter { $0.isAttacking == true }
        let combat = XmageCombatGroup(defenderId: "a", defenderName: "a", defenderKind: "player", blocked: blocked,
                                      attackers: attackers, blockers: a.filter { !($0.blocking ?? []).isEmpty })
        let xmage = XmageMobileSnapshot(schemaVersion: 1, gameId: "match", bridgeRevision: revision, xmageCycle: nil, callbackCoverage: [],
                                        stack: [], combat: [combat], players: [], exileZones: [], revealed: [], lookedAt: [],
                                        companion: [], playableObjects: [],
                                        panels: XmagePanels(stack: false, command: true, graveyard: true, exile: true, revealed: false,
                                                            lookedAt: false, search: false))
        return GameSnapshot(id: base.id, source: base.source, activePlayerId: "b", phase: "combat", step: step, turn: 3,
                            priorityPlayerId: "a", waitingOnPlayerId: nil, promptText: nil, players: base.players, log: [],
                            legalActions: nil, choicePrompt: nil, promptEnvelope: nil, promptEnvelopeV2: nil,
                            startupOpeningPrompts: nil, xmage: xmage, engineHealth: nil, bridgeRevision: revision,
                            xmageCycle: nil, pendingStatus: nil, manaPayment: nil, gameStatus: nil,
                            winnerPlayerIds: nil, endReason: nil, viewerPlayerId: "a")
    }

    /// Atarka gains double strike when it attacks; a deathtouch Typhoid Rats blocks.
    private var atarkaCombat: (blocks: GameSnapshot, firstStrike: GameSnapshot, regular: GameSnapshot) {
        let atarka = combatCard("atarka", "Atarka, World Render", icons: ["ABILITY_FLYING", "ABILITY_TRAMPLE", "ABILITY_DOUBLE_STRIKE"],
                                rules: "Flying\nTrample", attacking: true)
        let rats = combatCard("rats", "Typhoid Rats", icons: ["ABILITY_DEATHTOUCH"], rules: "Deathtouch", blocking: ["atarka"])
        let dead = combatCard("rats", "Typhoid Rats", rules: "Deathtouch")
        return (combatSnapshot(step: "DECLARE_BLOCKERS", revision: 10, a: [rats], b: [atarka], blocked: true),
                combatSnapshot(step: "FIRST_COMBAT_DAMAGE", revision: 11, a: [], b: [atarka], graveyardA: [dead], blocked: true),
                combatSnapshot(step: "COMBAT_DAMAGE", revision: 12, lifeA: 34, a: [], b: [atarka], graveyardA: [dead], blocked: true))
    }

    func testSnapshotKeywordsOfCombatantsReachTheBoardState() {
        let state = BoardFXState(snapshot: atarkaCombat.blocks)
        XCTAssertEqual(state.cards["atarka"]?.keywords, [.doubleStrike, .trample, .flying])
        XCTAssertEqual(state.cards["rats"]?.keywords, [.deathtouch])
        XCTAssertEqual(state.blockedAttackers, ["atarka"])
        XCTAssertEqual(state.step, "declare-blockers")
        XCTAssertEqual(BoardFXState(snapshot: atarkaCombat.firstStrike).step, BoardEventDiffer.firstStrikeStep)
    }

    func testFirstStrikeStepPlaysItsOwnLabelledBeatBeforeTheRegularDamage() {
        let combat = atarkaCombat
        let start = Date(timeIntervalSince1970: 7_000)
        var director = BoardFXDirector()
        director.ingest(combat.blocks, level: .full, now: start)
        let first = director.ingest(combat.firstStrike, level: .full, now: start)
        XCTAssertEqual(first.map(\.event), [
            .firstStrikeBeat,
            .combatStrike(attackerID: "atarka", target: .card("rats"), tint: .red, firstStrike: true),
            .leftBattlefield(cardID: "rats", playerID: "a", to: .graveyard, tint: .red),
        ])
        let label = first[0]
        XCTAssertEqual(label.delay, 0)
        XCTAssertGreaterThanOrEqual(label.end, first.map(\.end).max()! , "the label spans the whole first-strike beat")
        // The regular damage arrives while the first-strike beat still plays: it waits for it.
        let later = start.addingTimeInterval(0.4)
        let second = director.ingest(combat.regular, level: .full, now: later)
        XCTAssertEqual(second.map(\.event), [
            .combatStrike(attackerID: "atarka", target: .player("a"), tint: .red, firstStrike: false),
            .lifeChanged(playerID: "a", delta: -6),
        ])
        XCTAssertEqual(later.addingTimeInterval(second[0].delay).timeIntervalSince1970,
                       start.addingTimeInterval(label.end).timeIntervalSince1970, accuracy: 0.001)
        // The double striker flies twice; its tile hides only while each strike flies.
        let windows = director.cardMotion(viewerID: "a").hidden["atarka"] ?? []
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0], BoardFXCardMotion.Hidden(batch: start, from: first[1].delay, until: first[1].end))
        XCTAssertEqual(windows[1], BoardFXCardMotion.Hidden(batch: later, from: second[0].delay, until: second[0].end))
        XCTAssertLessThan(start.addingTimeInterval(windows[0].until), later.addingTimeInterval(windows[1].from))
    }

    func testFirstStrikeBeatFollowsTheEffectLevels() {
        let combat = atarkaCombat
        let events = BoardEventDiffer.events(from: BoardFXState(snapshot: combat.blocks), to: BoardFXState(snapshot: combat.firstStrike))
        XCTAssertEqual(BoardFXScheduler.schedule(events, level: .off), [])
        let reduced = BoardFXScheduler.schedule(events, level: .reduced)
        XCTAssertEqual(reduced.first?.event, .firstStrikeBeat, "reduced keeps the label, without motion")
        XCTAssertFalse(reduced.contains(where: \.usesMotion))
        XCTAssertEqual(reduced.first?.holdsLaterBatchesUntil, reduced.first?.end)
        // The label is information, not decoration: a crowded batch never drops it.
        let crowded = [BoardFXEvent.firstStrikeBeat] + (0..<20).map { .damageMarked(cardID: "c\($0)", amount: 1) }
        let planned = BoardFXScheduler.schedule(crowded, level: .full)
        XCTAssertEqual(planned.first?.event, .firstStrikeBeat)
        XCTAssertEqual(planned.count, BoardFXScheduler.decorativeLimit + 1)
    }
}
