import Foundation
import MagicMobileOnDevice

/// The online turn timer. Android's TurnClock.kt applies the same rules;
/// apps/android/core/src/test/resources/parity/turn-clock-cases.json checks both.
///
/// Phone-hosted tables only. The host runs one clock for every human seat: each decision the
/// engine asks a player gets `decision` seconds, and the rope burns through the last `rope`.
/// When a decision runs out, the host answers it the way passing would (pass priority, finish
/// declaring, cancel a payment or an optional target); a question with no such answer gets
/// `grace` more seconds instead. Each timeout is a strike, a decision the player answers
/// themselves clears them, and the `strikesToForfeit`-th straight timeout concedes the seat.
/// All times are seconds of the host's uptime clock.
struct TurnClockRules: Equatable {
    var decision: TimeInterval = 60
    var rope: TimeInterval = 20
    var grace: TimeInterval = 20
    var strikesToForfeit = 3
    /// A paused clock comes back with at least this long, so nobody returns to an instant timeout.
    var resumeFloor: TimeInterval = 10
    static let online = TurnClockRules()
}

struct TurnClockPrompt: Equatable {
    let id: String
    let revision: Int64
}

enum TurnClockTimeout: String, Equatable { case answer, grace, forfeit }

/// One seat's clock as shown on every phone.
struct TurnClockEntry: Equatable {
    let seat: String
    let remaining: TimeInterval
    let limit: TimeInterval
    let strikes: Int
}

struct TurnClock {
    private struct Running {
        let prompt: TurnClockPrompt
        var deadline: TimeInterval
        var limit: TimeInterval
        var frozen: TimeInterval?
        var handled = false
    }

    let rules: TurnClockRules
    private var running: [String: Running] = [:]
    private var strikeCounts: [String: Int] = [:]
    private var answeredByClock: [String: TurnClockPrompt] = [:]
    private(set) var paused = false

    init(rules: TurnClockRules = .online) { self.rules = rules }

    func strikes(_ seat: String) -> Int { strikeCounts[seat] ?? 0 }

    /// The seat's open question as the host's latest poll shows it, or nil (none, or already answered).
    /// Returns true when the clocks on screen changed.
    @discardableResult
    mutating func observe(seat: String, prompt: TurnClockPrompt?, now: TimeInterval) -> Bool {
        let current = running[seat]
        if let current, current.prompt == prompt { return false }
        if current == nil && prompt == nil { return false }
        if let current {
            // The player moved on by themselves: their timeouts no longer run in a row.
            if answeredByClock[seat] != current.prompt { strikeCounts[seat] = nil }
            answeredByClock[seat] = nil
        }
        if let prompt {
            running[seat] = Running(prompt: prompt, deadline: now + rules.decision, limit: rules.decision,
                                    frozen: paused ? rules.decision : nil)
        } else {
            running[seat] = nil
        }
        return true
    }

    /// Pauses while any phone is away or the table is still rolling for first player.
    @discardableResult
    mutating func setPaused(_ value: Bool, now: TimeInterval) -> Bool {
        guard value != paused else { return false }
        paused = value
        for seat in running.keys {
            guard var clock = running[seat] else { continue }
            if value { clock.frozen = max(0, clock.deadline - now) }
            else { clock.deadline = now + max(clock.frozen ?? 0, min(rules.resumeFloor, clock.limit)); clock.frozen = nil }
            running[seat] = clock
        }
        return true
    }

    /// Seats whose current decision ran out, in seat order.
    func expired(now: TimeInterval) -> [(seat: String, prompt: TurnClockPrompt)] {
        guard !paused else { return [] }
        return running.keys.sorted().compactMap { seat in
            guard let clock = running[seat], !clock.handled, now >= clock.deadline else { return nil }
            return (seat, clock.prompt)
        }
    }

    /// Records a timeout on `prompt` and says what the host does about it. Nil when the
    /// seat has moved on since. `hasDefault`: the question has a pass-like answer (`defaultAnswer`).
    mutating func timeout(seat: String, prompt: TurnClockPrompt, hasDefault: Bool, now: TimeInterval) -> TurnClockTimeout? {
        guard var clock = running[seat], clock.prompt == prompt, !clock.handled else { return nil }
        let count = strikes(seat) + 1
        strikeCounts[seat] = count
        let result: TurnClockTimeout
        if count >= rules.strikesToForfeit { clock.handled = true; result = .forfeit }
        else if hasDefault { clock.handled = true; answeredByClock[seat] = prompt; result = .answer }
        else { clock.deadline = now + rules.grace; clock.limit = rules.grace; result = .grace }
        running[seat] = clock
        return result
    }

    /// The host's answer did not land (the engine refused it): the decision gets a grace period instead.
    mutating func answerFailed(seat: String, prompt: TurnClockPrompt, now: TimeInterval) {
        guard var clock = running[seat], clock.prompt == prompt else { return }
        clock.handled = false; clock.deadline = now + rules.grace; clock.limit = rules.grace
        running[seat] = clock
        answeredByClock[seat] = nil
    }

    mutating func clear() { running = [:]; strikeCounts = [:]; answeredByClock = [:]; paused = false }

    func entries(now: TimeInterval) -> [TurnClockEntry] {
        running.keys.sorted().compactMap { seat in
            guard let clock = running[seat], !clock.handled else { return nil }
            return TurnClockEntry(seat: seat, remaining: clock.frozen ?? max(0, clock.deadline - now),
                                  limit: clock.limit, strikes: strikes(seat))
        }
    }

    /// The answer passing would give, or nil when the question has none: pass priority,
    /// finish declaring attackers or blockers, cancel a mana payment, or skip an optional
    /// target or ability. Everything else (mulligans, required targets, choices) gets grace.
    static func defaultAnswer(_ prompt: MagicMobileOnDevice.EnginePrompt) -> MagicMobileOnDevice.JSONValue? {
        guard prompt.responseTypes.contains("boolean") else { return nil }
        switch prompt.kind {
        case "SELECT":
            guard let mode = prompt.payload["selectMode"]?.string, ["priority", "attackers", "blockers"].contains(mode) else { return nil }
            return MagicMobileOnDevice.EnginePrompt.answer("boolean", .bool(true))
        case "PLAY_MANA":
            return MagicMobileOnDevice.EnginePrompt.answer("boolean", .bool(false))
        case "PICK_TARGET", "CHOOSE_ABILITY", "PICK_ABILITY":
            guard prompt.payload["required"]?.bool == false else { return nil }
            return MagicMobileOnDevice.EnginePrompt.answer("boolean", .bool(false))
        default:
            return nil
        }
    }

    /// The clock a seat's poll implies: an unanswered question, or none.
    static func prompt(_ poll: MagicMobileOnDevice.MatchPoll) -> TurnClockPrompt? {
        guard poll.phase == "running", let prompt = poll.prompt, !prompt.submitted else { return nil }
        return TurnClockPrompt(id: prompt.id, revision: prompt.revision)
    }
}

/// The host's `clock` packet: `{"type":"clock","epoch":…,"paused":bool,"clocks":[{"seat","remainingMillis","limitMillis","strikes"}]}`.
/// Remaining time travels instead of a deadline, so the phones' clocks never need to agree.
enum TurnClockWire {
    static let maxLimitMillis: Int64 = 120_000

    static func packet(epoch: String, paused: Bool, entries: [TurnClockEntry]) -> MagicMobileOnDevice.JSONValue {
        .object(["type": .string("clock"), "epoch": .string(epoch), "paused": .bool(paused),
                 "clocks": .array(entries.map { entry in
                     .object(["seat": .string(entry.seat), "remainingMillis": .integer(Int64((entry.remaining * 1000).rounded())),
                              "limitMillis": .integer(Int64((entry.limit * 1000).rounded())), "strikes": .integer(Int64(entry.strikes))])
                 })])
    }

    /// Strict: exactly these keys, at most four seats, each once, with sane times.
    static func parse(_ value: MagicMobileOnDevice.JSONValue) throws -> (paused: Bool, entries: [TurnClockEntry]) {
        let invalid = EngineError.invalidMessage("Invalid turn clock.")
        guard let fields = value.object, Set(fields.keys) == ["type", "epoch", "paused", "clocks"],
              fields["type"]?.string == "clock", let paused = fields["paused"]?.bool,
              let clocks = fields["clocks"]?.array, clocks.count <= 4 else { throw invalid }
        let seats = Set((1...4).map { "player\($0)" })
        let entries = try clocks.map { item -> TurnClockEntry in
            guard let entry = item.object, Set(entry.keys) == ["seat", "remainingMillis", "limitMillis", "strikes"],
                  let seat = entry["seat"]?.string, seats.contains(seat),
                  let limit = entry["limitMillis"]?.integer, (1...maxLimitMillis).contains(limit),
                  let remaining = entry["remainingMillis"]?.integer, (0...limit).contains(remaining),
                  let strikes = entry["strikes"]?.integer, (0...3).contains(strikes) else { throw invalid }
            return TurnClockEntry(seat: seat, remaining: Double(remaining) / 1000, limit: Double(limit) / 1000, strikes: Int(strikes))
        }
        guard Set(entries.map(\.seat)).count == entries.count else { throw invalid }
        return (paused, entries)
    }
}

/// What a phone shows: the clocks with deadlines on its own uptime clock.
struct TurnClockBoard: Equatable {
    struct Clock: Equatable {
        let seat: String
        let deadline: TimeInterval
        let limit: TimeInterval
        let strikes: Int
    }
    struct Rope: Equatable {
        let seat: String
        let isLocal: Bool
        let remaining: TimeInterval
        let fraction: Double
        let strikes: Int
    }

    var paused = false
    var clocks: [Clock] = []

    static func from(paused: Bool, entries: [TurnClockEntry], now: TimeInterval) -> TurnClockBoard {
        TurnClockBoard(paused: paused, clocks: entries.map {
            Clock(seat: $0.seat, deadline: now + $0.remaining, limit: $0.limit, strikes: $0.strikes)
        })
    }

    private func pick(_ localSeat: String?) -> Clock? {
        clocks.first { $0.seat == localSeat } ?? clocks.min { $0.deadline < $1.deadline }
    }

    /// The one rope to burn: the local seat's own decision first, otherwise the clock that runs out
    /// soonest. Nil while paused or until a clock is inside its last `rope` seconds.
    func rope(localSeat: String?, now: TimeInterval, rules: TurnClockRules = .online) -> Rope? {
        guard !paused, let pick = pick(localSeat) else { return nil }
        let remaining = max(0, pick.deadline - now)
        let window = min(rules.rope, pick.limit)
        guard remaining <= window, remaining > 0 else { return nil }
        return Rope(seat: pick.seat, isLocal: pick.seat == localSeat, remaining: remaining,
                    fraction: remaining / window, strikes: pick.strikes)
    }

    /// Seconds until `rope` could first return something, or nil when nothing will (paused, no clocks).
    func secondsUntilRope(localSeat: String?, now: TimeInterval, rules: TurnClockRules = .online) -> TimeInterval? {
        guard !paused, let pick = pick(localSeat) else { return nil }
        let remaining = pick.deadline - now
        guard remaining > 0 else { return nil }
        return max(0, remaining - min(rules.rope, pick.limit))
    }
}
