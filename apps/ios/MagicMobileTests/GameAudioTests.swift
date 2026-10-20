import AVFoundation
import XCTest
@testable import MagicMobile

@MainActor
final class GameAudioTests: XCTestCase {
    private func url(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "caf") ?? Bundle.main.url(forResource: name, withExtension: "m4a")
    }

    /// Every cue (and each numbered variant) and every playlist track ships in the app and decodes.
    func testEverySoundAndTrackIsBundledAndPlayable() throws {
        let names = GameSound.allCases.flatMap { sound in
            sound.variants > 1 ? (1...sound.variants).map { "\(sound.rawValue)-\($0)" } : [sound.rawValue]
        }
        for name in names {
            let file = try XCTUnwrap(url(name), "missing bundled audio \(name)")
            let player = try AVAudioPlayer(contentsOf: file)
            XCTAssertGreaterThan(player.duration, 0.05, name)
            XCTAssertLessThan(player.duration, ["victory", "defeat"].contains(name) ? 10 : 3, name)
        }
        for scene in GameMusic.allCases {
            XCTAssertEqual(scene.tracks.count, 4, "\(scene) playlist")
            for track in scene.tracks {
                let player = try AVAudioPlayer(contentsOf: try XCTUnwrap(url(track.file), "missing \(track.file)"))
                XCTAssertGreaterThan(player.duration, 120, "\(track.title) plays whole")
            }
        }
    }

    func testEverySoundHasAGroupAndAName() {
        for category in GameSoundCategory.allCases {
            XCTAssertFalse(GameSound.sounds(in: category).isEmpty, "\(category) is empty")
        }
        XCTAssertEqual(Set(GameSound.allCases.map(\.title)).count, GameSound.allCases.count, "Sound Lab names are distinct")
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
            fx(.spellCast(stackID: "s4", name: "Their trigger", controllerID: "them", tint: .green, weight: .ability)),
            fx(.enteredBattlefield(cardID: "land", playerID: viewer, from: .hand, tint: .green, entrance: .plain)),
            fx(.enteredBattlefield(cardID: "token", playerID: viewer, from: nil, tint: .green, entrance: .plain)),
            fx(.enteredBattlefield(cardID: "bear", playerID: viewer, from: .stack, tint: .green, entrance: .plain)),
            fx(.enteredBattlefield(cardID: "ring", playerID: viewer, from: .stack, tint: .colorless, entrance: .plain)),
            fx(.leftBattlefield(cardID: "a", playerID: viewer, to: .exile, tint: .white)),
            fx(.leftBattlefield(cardID: "b", playerID: viewer, to: .graveyard, tint: .black)),
            fx(.leftBattlefield(cardID: "c", playerID: viewer, to: .hand, tint: .blue)),
            fx(.countersChanged(cardID: "bear", kind: .plusOne, delta: 1)),
            fx(.controlChanged(cardID: "ogre", from: "them", to: viewer)),
            fx(.lifeChanged(playerID: viewer, delta: 3)),
        ], viewerID: viewer, arrivals: [
            "land": .init(card: CardIdentity(name: "Forest", typeLine: "Basic Land — Forest", oracleText: nil)),
            "token": .init(card: CardIdentity(name: "Squirrel", typeLine: "Token Creature — Squirrel", oracleText: nil,
                                              tokenColors: ["Green"]), isToken: true),
            "bear": .init(card: CardIdentity(name: "Grizzly Bears", typeLine: "Creature — Bear", oracleText: nil, manaCost: "{1}{G}")),
            "ring": .init(card: CardIdentity(name: "Sol Ring", typeLine: "Artifact", oracleText: nil, manaCost: "{1}")),
        ], casts: [
            "s1": CardIdentity(name: "Lightning Bolt", typeLine: "Instant", oracleText: nil, manaCost: "{R}"),
            "s2": CardIdentity(name: "Ultimatum", typeLine: "Sorcery", oracleText: nil, manaCost: "{7}{U}{U}{U}"),
        ], hasStrike: false)
        let sounds = cues.map(\.sound)
        XCTAssertEqual(sounds, [.castInstant, .castSorcery, .spellBig, .ability, .landForest, .creatureSquirrel, .creatureBear,
                                .arriveArtifact, .exile, .death, .cardPickup, .counter, .steal, .lifeGain])
    }

    func testACreaturesVoicePlaysAsItsCardComesInAndEndsAsItLands() {
        let viewer = "me"
        let entering = fx(.enteredBattlefield(cardID: "elf", playerID: viewer, from: .hand, tint: .green, entrance: .showcase), delay: 0.3)
        let landing = fx(.enteredBattlefield(cardID: "bear", playerID: viewer, from: .hand, tint: .green, entrance: .showcase), delay: 0.3)
        let cues = BoardFXSound.cues([entering, landing], viewerID: viewer, arrivals: [
            "elf": .init(card: CardIdentity(name: "Llanowar Elves", typeLine: "Creature — Elf Druid", oracleText: nil, manaCost: "{G}")),
            "bear": .init(card: CardIdentity(name: "Coral Merfolk", typeLine: "Creature — Merfolk", oracleText: nil, manaCost: "{1}{U}")),
        ], hasStrike: false)
        XCTAssertEqual(cues.first?.sound, .creatureElf)
        XCTAssertEqual(cues.first?.at, entering.delay, "the voice starts as the card starts entering")
        XCTAssertEqual(cues.first?.endsBy, entering.landing, "and is timed to finish as it lands")
        XCTAssertEqual(cues.last?.sound, .arriveCreature)
        XCTAssertEqual(cues.last?.at, landing.landing, "a card with no voice lands with the card sound")
        XCTAssertNil(cues.last?.endsBy)
    }

    func testEveryCreatureVoiceSlotHasItsSoundAndFiles() {
        for slot in Set(BoardFXArrivalSound.creatureVoices.values) {
            guard let sound = GameSound.voice(slot) else { return XCTFail("no GameSound for \(slot)") }
            for n in 1...sound.variants {
                let file = sound.variants > 1 ? "\(sound.fileBase)-\(n)" : sound.fileBase
                XCTAssertTrue(Bundle.main.url(forResource: file, withExtension: "m4a") != nil
                              || Bundle.main.url(forResource: file, withExtension: "caf") != nil, "missing \(file)")
            }
        }
        XCTAssertEqual(GameSound.creatureGiant.fileBase, "creature-orc", "giants share the first two orc voices")
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

    func testOnlyYourDrawsComeFromSnapshotChanges() throws {
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
                       [.cardDraw, .cardDraw], "an opening hand is at most two draws")
        XCTAssertEqual(GameSoundSignature.cues(from: start, to: try sig(hand: 7, tapped: 2, stack: 0)), [],
                       "tapping lands and resolving the stack stay quiet")
        XCTAssertEqual(GameSoundSignature.cues(from: start, to: try sig(game: "other", hand: 9, tapped: 3, stack: 0)), [],
                       "a different game is a cut, not a transition")
    }

    func testCastSoundFollowsTheCardType() {
        XCTAssertEqual(GameSound.cast(.instant), .castInstant)
        XCTAssertEqual(GameSound.cast(.sorcery), .castSorcery)
        XCTAssertEqual(GameSound.cast(.permanent), .castPermanent)
    }
}
