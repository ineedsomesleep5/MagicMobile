import XCTest
@testable import MagicMobile

final class BoardEventTimelineTests: XCTestCase {
    private func card(_ id: String, _ name: String = "Grizzly Bears", cost: String? = "{1}{G}",
                      damage: Int? = nil, counters: [String: Int]? = nil, attacking: Bool? = nil) -> ZoneCard {
        var identity = CardIdentity(name: name, typeLine: "Creature — Bear", oracleText: nil)
        identity.manaCost = cost
        return ZoneCard(instanceId: id, card: identity, tapped: nil, summoningSickness: nil, cardIcons: nil,
                        counters: counters, power: 2, toughness: 2, isCreaturePermanent: true, damage: damage,
                        isAttacking: attacking, blocking: nil, attachedToInstanceId: nil)
    }

    private func player(_ id: String, life: Int = 40, hand: [ZoneCard] = [], battlefield: [ZoneCard] = [],
                        graveyard: [ZoneCard] = [], exile: [ZoneCard] = []) -> PlayerGameState {
        PlayerGameState(playerId: id, displayName: id, life: life, poison: 0, commanderTax: 0, manaPool: nil,
                        zones: PlayerZones(library: [], hand: hand, battlefield: battlefield, graveyard: graveyard,
                                           exile: exile, command: [], stack: []),
                        commanderDamage: nil)
    }

    private func snapshot(_ players: [PlayerGameState], id: String = "match", revision: Int = 1) -> GameSnapshot {
        GameSnapshot(id: id, source: "xmage-ondevice", activePlayerId: "a", phase: "main", step: nil, turn: 3,
                     priorityPlayerId: "a", waitingOnPlayerId: nil, promptText: nil, players: players, log: [],
                     legalActions: nil, choicePrompt: nil, promptEnvelope: nil, promptEnvelopeV2: nil,
                     startupOpeningPrompts: nil, xmage: nil, engineHealth: nil, bridgeRevision: revision,
                     xmageCycle: nil, pendingStatus: nil, manaPayment: nil, gameStatus: nil,
                     winnerPlayerIds: nil, endReason: nil, viewerPlayerId: "a")
    }

    private func events(_ old: GameSnapshot, _ new: GameSnapshot) -> [BoardFXEvent] {
        BoardEventDiffer.events(from: BoardFXState(snapshot: old), to: BoardFXState(snapshot: new))
    }

    func testCardPlayedFromHandEntersBattlefieldWithItsColor() {
        let bear = card("bear")
        let result = events(snapshot([player("a", hand: [bear]), player("b")]),
                            snapshot([player("a", battlefield: [bear]), player("b")], revision: 2))
        XCTAssertEqual(result, [.enteredBattlefield(cardID: "bear", playerID: "a", from: .hand, tint: .green)])
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
}
