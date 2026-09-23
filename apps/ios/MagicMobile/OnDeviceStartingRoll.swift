import Foundation
import MagicMobileOnDevice

/// A complete, host-recorded D20 result. Every device animates these same values;
/// animation timing never determines who starts the game.
struct OnDeviceStartingRoll: Equatable {
    struct Round: Equatable {
        let rolls: [String: Int]
    }

    struct Step: Equatable {
        let roundIndex: Int
        let seatID: String
        let value: Int
    }

    let rounds: [Round]
    let winnerSeatID: String
    let seatOrder: [String]

    var steps: [Step] {
        rounds.enumerated().flatMap { roundIndex, round in
            seatOrder.compactMap { seatID in
                round.rolls[seatID].map { Step(roundIndex: roundIndex, seatID: seatID, value: $0) }
            }
        }
    }

    private init(rounds: [Round], winnerSeatID: String, seatOrder: [String]) {
        self.rounds = rounds
        self.winnerSeatID = winnerSeatID
        self.seatOrder = seatOrder
    }

    static func generate(seatIDs: [String], draw: () -> Int = { Int.random(in: 1...20) }) throws -> Self {
        guard (2...4).contains(seatIDs.count), Set(seatIDs).count == seatIDs.count,
              seatIDs.allSatisfy({ !$0.isEmpty }) else {
            throw EngineError.invalidMessage("A starting roll needs 2–4 distinct seats.")
        }
        var contenders = seatIDs
        var rounds: [Round] = []
        // An extremely unlikely run of ties must fail visibly, not loop forever.
        for _ in 0..<32 {
            var rolls: [String: Int] = [:]
            for seat in contenders {
                let value = draw()
                guard (1...20).contains(value) else { throw EngineError.invalidMessage("Invalid D20 value.") }
                rolls[seat] = value
            }
            rounds.append(Round(rolls: rolls))
            let high = rolls.values.max()!
            contenders = contenders.filter { rolls[$0] == high }
            if contenders.count == 1 { return Self(rounds: rounds, winnerSeatID: contenders[0], seatOrder: seatIDs) }
        }
        throw EngineError.invalidMessage("The starting roll tied too many times. Try the match again.")
    }

    func encoded(seatIDs: [String]) throws -> MagicMobileOnDevice.JSONValue {
        try validate(seatIDs: seatIDs)
        return .object([
            "rounds": .array(rounds.map { round in
                .array(seatIDs.compactMap { seat in
                    round.rolls[seat].map { value in
                        .object(["seatId": .string(seat), "value": .integer(Int64(value))])
                    }
                })
            }),
            "winnerSeatId": .string(winnerSeatID)
        ])
    }

    init(_ value: MagicMobileOnDevice.JSONValue, seatIDs: [String]) throws {
        guard let fields = value.object, Set(fields.keys) == ["rounds", "winnerSeatId"],
              let rows = fields["rounds"]?.array, !rows.isEmpty, rows.count <= 32,
              let winner = fields["winnerSeatId"]?.string else {
            throw EngineError.invalidMessage("Invalid shared starting roll.")
        }
        var rounds: [Round] = []
        for row in rows {
            guard let entries = row.array, entries.count <= 4 else {
                throw EngineError.invalidMessage("Invalid shared starting roll round.")
            }
            var result: [String: Int] = [:]
            for entry in entries {
                guard let object = entry.object, Set(object.keys) == ["seatId", "value"],
                      let seat = object["seatId"]?.string, let value = object["value"]?.integer,
                      (1...20).contains(value), result[seat] == nil else {
                    throw EngineError.invalidMessage("Invalid shared D20 value.")
                }
                result[seat] = Int(value)
            }
            rounds.append(Round(rolls: result))
        }
        self.rounds = rounds
        winnerSeatID = winner
        seatOrder = seatIDs
        try validate(seatIDs: seatIDs)
    }

    private func validate(seatIDs: [String]) throws {
        guard seatIDs == seatOrder, (2...4).contains(seatIDs.count), Set(seatIDs).count == seatIDs.count,
              !rounds.isEmpty, rounds.count <= 32 else {
            throw EngineError.invalidMessage("Invalid starting-roll roster.")
        }
        var contenders = Set(seatIDs)
        for (index, round) in rounds.enumerated() {
            guard Set(round.rolls.keys) == contenders,
                  round.rolls.values.allSatisfy({ (1...20).contains($0) }),
                  let highest = round.rolls.values.max() else {
                throw EngineError.invalidMessage("Starting-roll round does not match the roster.")
            }
            contenders = Set(round.rolls.filter { $0.value == highest }.map(\.key))
            guard contenders.count > 1 || index == rounds.count - 1 else {
                throw EngineError.invalidMessage("Starting roll continues after a winner.")
            }
        }
        guard contenders == [winnerSeatID] else {
            throw EngineError.invalidMessage("Starting-roll winner does not match the dice.")
        }
    }
}

/// One shared cursor through the host's result. Humans can advance only their own
/// turn; AI turns are advanced by the host, never by a guest or an animation.
struct OnDeviceStartingRollProgress: Equatable {
    let roll: OnDeviceStartingRoll
    let humanSeatIDs: Set<String>
    private(set) var revealedCount = 0

    var nextSeatID: String? {
        roll.steps.indices.contains(revealedCount) ? roll.steps[revealedCount].seatID : nil
    }

    var isComplete: Bool { revealedCount == roll.steps.count }

    mutating func advance(seatID: String, automated: Bool) throws -> Int {
        guard nextSeatID == seatID, humanSeatIDs.contains(seatID) != automated else {
            throw EngineError.invalidMessage("It is not this player's turn to roll.")
        }
        let index = revealedCount
        revealedCount += 1
        return index
    }

    mutating func acceptHostAdvance(index: Int) throws {
        guard index == revealedCount, nextSeatID != nil else {
            throw EngineError.replayedMessage
        }
        revealedCount += 1
    }
}
