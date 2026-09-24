import AVFoundation
import XCTest
@testable import MagicMobile

@MainActor
final class GameAudioTests: XCTestCase {
    private func url(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "caf") ?? Bundle.main.url(forResource: name, withExtension: "m4a")
    }

    /// Every cue (and each numbered variant) ships in the app and decodes.
    func testEverySoundAndTrackIsBundledAndPlayable() throws {
        var names = GameSound.allCases.flatMap { sound in
            sound.variants > 1 ? (1...sound.variants).map { "\(sound.rawValue)-\($0)" } : [sound.rawValue]
        }
        names += [GameMusic.menu.rawValue, GameMusic.game.rawValue]
        for name in names {
            let file = try XCTUnwrap(url(name), "missing bundled audio \(name)")
            let player = try AVAudioPlayer(contentsOf: file)
            XCTAssertGreaterThan(player.duration, 0.02, name)
            XCTAssertLessThan(player.duration, name.hasPrefix("music-") ? 70 : 7, name)
        }
        for track in [GameMusic.menu, .game] {
            let player = try AVAudioPlayer(contentsOf: try XCTUnwrap(url(track.rawValue)))
            XCTAssertEqual(player.duration, 64, accuracy: 0.5, "music loops are 64 seconds")
        }
    }

    private func fx(_ event: BoardFXEvent, delay: TimeInterval = 0.1) -> ScheduledBoardFX {
        ScheduledBoardFX(id: Int.random(in: 0..<1_000_000), event: event, delay: delay, duration: 0.5, usesMotion: true)
    }

    func testBoardEventsMapToTheirSounds() {
        let viewer = "me"
        let cues = BoardFXSound.cues([
            fx(.spellCast(stackID: "s1", name: "Bolt", controllerID: viewer, tint: .red, weight: .spell)),
            fx(.spellCast(stackID: "s2", name: "Ultimatum", controllerID: viewer, tint: .blue, weight: .big)),
            fx(.spellCast(stackID: "s3", name: "Trigger", controllerID: viewer, tint: .green, weight: .ability)),
            fx(.enteredBattlefield(cardID: "land", playerID: viewer, from: .hand, tint: .green, entrance: .plain)),
            fx(.enteredBattlefield(cardID: "token", playerID: viewer, from: nil, tint: .green, entrance: .plain)),
            fx(.enteredBattlefield(cardID: "bear", playerID: viewer, from: .stack, tint: .green, entrance: .plain)),
            fx(.leftBattlefield(cardID: "a", playerID: viewer, to: .exile, tint: .white)),
            fx(.leftBattlefield(cardID: "b", playerID: viewer, to: .graveyard, tint: .black)),
            fx(.leftBattlefield(cardID: "c", playerID: viewer, to: .hand, tint: .blue)),
            fx(.countersAdded(cardID: "bear", amount: 1)),
            fx(.lifeChanged(playerID: viewer, delta: 3)),
        ], viewerID: viewer, arrivals: ["land": .init(isLand: true), "token": .init(isToken: true)], hasStrike: false)
        let sounds = cues.map(\.sound)
        XCTAssertEqual(sounds, [.castRed, .castBlue, .spellBig, .ability, .landDrop, .tokenCreate, .creatureEnter,
                                .exile, .death, .cardPickup, .counter, .lifeGain])
    }

    func testCombatHitsYouHarderThanACreatureAndLifeLossIsNotDoubled() {
        let viewer = "me"
        let scheduled = [
            fx(.attackDeclared(cardID: "x", tint: .red)),
            fx(.blockDeclared(cardID: "y", attackerID: "x")),
            fx(.combatStrike(attackerID: "x", target: .player(viewer), tint: .red)),
            fx(.combatStrike(attackerID: "z", target: .card("y"), tint: .red)),
            fx(.damageMarked(cardID: "y", amount: 2)),
            fx(.lifeChanged(playerID: viewer, delta: -3)),
        ]
        let sounds = BoardFXSound.cues(scheduled, viewerID: viewer, hasStrike: true).map(\.sound)
        XCTAssertEqual(sounds, [.attack, .block, .playerHit, .strike])
        // Outside combat, losing life has its own cue and marked damage still lands.
        let drain = BoardFXSound.cues([fx(.lifeChanged(playerID: viewer, delta: -2)), fx(.damageMarked(cardID: "y", amount: 1))],
                                      viewerID: viewer, hasStrike: false).map(\.sound)
        XCTAssertEqual(drain, [.lifeLoss, .strike])
        // Another player's loss is theirs to hear; their gain is a quieter chime.
        let other = BoardFXSound.cues([fx(.lifeChanged(playerID: "them", delta: -2)), fx(.lifeChanged(playerID: "them", delta: 2))],
                                      viewerID: viewer, hasStrike: false)
        XCTAssertEqual(other.map(\.sound), [.lifeGain])
        XCTAssertLessThan(other[0].volume, 1)
    }

    func testDrawsTapsAndResolutionsComeFromSnapshotChanges() throws {
        func sig(game: String = "g", hand: Int, tapped: Int, stack: Int) throws -> GameSoundSignature {
            let lands = (0..<3).map { i -> [String: Any] in
                ["instanceId": "land\(i)", "tapped": i < tapped, "card": ["name": "Forest", "typeLine": "Basic Land — Forest"]]
            }
            let hands = (0..<hand).map { i -> [String: Any] in ["instanceId": "h\(i)", "card": ["name": "Card", "typeLine": "Instant"]] }
            let stackCards = (0..<stack).map { i -> [String: Any] in ["instanceId": "s\(i)", "card": ["name": "Spell", "typeLine": "Instant"]] }
            let root: [String: Any] = [
                "id": game, "phase": "MAIN", "turn": 3, "log": [], "legalActions": [], "viewerPlayerId": "me",
                "players": [["playerId": "me", "displayName": "Me", "life": 40, "poison": 0, "commanderTax": 0,
                             "zones": ["hand": hands, "battlefield": lands, "graveyard": [], "exile": [], "library": [],
                                       "command": [], "stack": stackCards]]]
            ]
            let snapshot = try JSONDecoder().decode(GameSnapshot.self, from: JSONSerialization.data(withJSONObject: root))
            return GameSoundSignature(snapshot)
        }
        let start = try sig(hand: 7, tapped: 0, stack: 1)
        XCTAssertEqual(GameSoundSignature.cues(from: start, to: try sig(hand: 8, tapped: 0, stack: 1)), [.cardDraw])
        XCTAssertEqual(GameSoundSignature.cues(from: try sig(hand: 0, tapped: 0, stack: 1), to: start),
                       [.cardDraw, .cardDraw, .cardDraw], "an opening hand is at most three draws")
        XCTAssertEqual(GameSoundSignature.cues(from: start, to: try sig(hand: 7, tapped: 2, stack: 0)), [.manaTap, .stackResolve])
        XCTAssertEqual(GameSoundSignature.cues(from: start, to: try sig(game: "other", hand: 9, tapped: 3, stack: 0)), [],
                       "a different game is a cut, not a transition")
    }

    func testCastSoundFollowsColorIdentity() {
        XCTAssertEqual(GameSound.cast(for: .white), .castWhite)
        XCTAssertEqual(GameSound.cast(for: .black), .castBlack)
        XCTAssertEqual(GameSound.cast(for: .multicolor), .castMulti)
        XCTAssertEqual(GameSound.cast(for: .colorless), .castColorless)
    }
}
