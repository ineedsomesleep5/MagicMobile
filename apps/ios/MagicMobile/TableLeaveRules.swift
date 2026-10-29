import Foundation
import MagicMobileOnDevice

/// When a player leaves a table with people, the others play on (Caleb, 2026-10-26: one player had to go and the game
/// couldn't continue for the other two). A guest who taps Leave, or whose connection the table gives up on, is conceded
/// at once. A guest who is away (dropped or in the background) is waited for; after `voteAfterSeconds` everyone still at
/// the table may vote to go on without them, and when they all agree the host concedes the seat. Only the host's phone
/// runs the game, so the host leaving still ends it. Android's TableLeaveRules matches; parity/table-leave-cases.json.
enum TableLeaveRules {
    static let voteAfterSeconds: TimeInterval = 15

    /// Everyone still at the table agrees.
    static func passes(yes: Int, eligible: Int) -> Bool { eligible > 0 && yes >= eligible }

    static func leftNotice(_ name: String) -> String { String(localized: "\(name) left. The game goes on.") }

    static let leftBehindMessage = String(localized: "The others went on without you after you left the table.")

    /// "Continue without Jed (1/2)".
    static func buttonTitle(_ vote: TableContinueVote) -> String {
        String(localized: "Continue without \(vote.name) (\(vote.voters.count)/\(vote.needed))")
    }
}

/// The vote to go on without one away player: the seats that said yes and how many must. The host sends it to the
/// guests in a `vote` packet whenever it changes; seat "" with needed 0 means no vote is open.
struct TableContinueVote: Equatable {
    static let none = TableContinueVote(seatID: "", name: "", voters: [], needed: 0, voted: false)

    let seatID: String
    let name: String
    let voters: [String]
    let needed: Int
    /// This phone already voted yes.
    let voted: Bool

    func with(voted: Bool) -> TableContinueVote {
        TableContinueVote(seatID: seatID, name: name, voters: voters, needed: needed, voted: voted)
    }

    func packet(epoch: String) -> MagicMobileOnDevice.JSONValue {
        .object(["type": .string("vote"), "epoch": .string(epoch), "seat": .string(seatID),
                 "voters": .array(voters.map(MagicMobileOnDevice.JSONValue.string)), "needed": .integer(Int64(needed))])
    }

    /// A host's `vote` packet; nil when no vote is open.
    static func parse(_ value: MagicMobileOnDevice.JSONValue, names: [String: String], localSeat: String?) throws -> TableContinueVote? {
        guard let fields = value.object, Set(fields.keys) == ["type", "epoch", "seat", "voters", "needed"],
              let seat = fields["seat"]?.string, let raw = fields["voters"]?.array, raw.count <= 4,
              let needed = fields["needed"]?.integer, (0...4).contains(needed) else {
            throw EngineError.invalidMessage("Invalid table vote.")
        }
        let voters = raw.compactMap(\.string)
        guard voters.count == raw.count, voters.allSatisfy(isSeat), seat.isEmpty || isSeat(seat), seat.isEmpty == (needed == 0) else {
            throw EngineError.invalidMessage("Invalid table vote.")
        }
        guard !seat.isEmpty else { return nil }
        return TableContinueVote(seatID: seat, name: names[seat] ?? String(localized: "A player"), voters: voters, needed: Int(needed),
                                 voted: localSeat.map(voters.contains) ?? false)
    }

    private static func isSeat(_ text: String) -> Bool { ["player1", "player2", "player3", "player4"].contains(text) }
}
