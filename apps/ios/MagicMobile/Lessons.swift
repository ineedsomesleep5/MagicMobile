import Foundation
import Combine
import MagicMobileOnDevice

/// The engine protocol's JSON (the app has a JSONValue of its own).
typealias LessonJSON = MagicMobileOnDevice.JSONValue

/// The lessons (docs/LESSONS_TUTORIAL.md): short scripted games recorded from the real engine
/// (scripts/lessons/record.py), played back on the real board. `LessonTransport` stands where the
/// engine would: it answers the board's polls with the recorded views and accepts only the move the
/// recording made, so every card, rule and animation is the engine's own. Maren's coaching rides on
/// the frames. Android's Lessons.kt and the web's lessons.ts read the same files the same way.
enum LessonText {
    static let title = "Lessons"
    static let start = "Start the lessons"
    static let coach = "Maren"
    static let gotIt = "Got it"
    static let next = "Next Lesson"
    static let done = "Done"
    static let complete = "Lesson complete"
    static let allComplete = "You know the basics. Play a guided game against an easy AI next, with tips as you go."
    static let nudge = "Not that one. Follow the glow."
    static let guided = "Guided game"
}

/// A move the lesson turned down: the coach card says so, so the board shows no error of its own.
extension Error {
    var isLessonNudge: Bool {
        if case .rejected(let code, _) = self as? MagicMobileOnDevice.EngineError { return code == "lesson_wrong_move" || code == "lesson_not_now" }
        return false
    }
}

/// What the board has open over the table, so Maren's card can get out of its way.
enum LessonBoardCover: Equatable {
    case none
    /// A player's card beside their portrait at the top: the coach drops below it.
    case playerCard
    /// A full panel the player opened (phase stops, the game menu, a card or zone up close): the coach tucks into a chip.
    case panel
}

/// Where Maren's card sits.
enum LessonCoachPlacement: Equatable { case top, low, tucked }

/// What the coach says on a frame: a title, a sentence or two, and what it points at.
struct LessonCoach: Equatable {
    let title: String?
    let text: String
    /// A card by name, `primary` (the corner button), `medallion` (your commander) or a player's name.
    let spot: String?
    let gesture: String?

    init?(_ value: LessonJSON?) {
        guard let value, let text = value["text"]?.string else { return nil }
        self.text = text; title = value["title"]?.string; spot = value["spot"]?.string; gesture = value["gesture"]?.string
    }
}

struct LessonInfo: Identifiable, Equatable {
    let id: String
    let title: String
}

enum LessonCatalog {
    static let all: [LessonInfo] = {
        guard let url = Bundle.main.url(forResource: "lessons", withExtension: "json"),
              let data = try? Data(contentsOf: url), let value = try? LessonJSON.decode(data),
              let rows = value["lessons"]?.array else { return [] }
        return rows.compactMap { row in
            guard let id = row["id"]?.string, let title = row["title"]?.string else { return nil }
            return LessonInfo(id: id, title: title)
        }
    }()

    static func next(after id: String) -> LessonInfo? {
        guard let index = all.firstIndex(where: { $0.id == id }), index + 1 < all.count else { return nil }
        return all[index + 1]
    }
}

/// Lessons finished on this device.
enum LessonProgress {
    static let key = "magicmobile.lessons.completed"
    static func completed(in defaults: UserDefaults) -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }
    static func complete(_ id: String, in defaults: UserDefaults) {
        defaults.set(Array(completed(in: defaults).union([id])).sorted(), forKey: key)
    }
}

/// One lesson file: the recorded learner's view after each change, and the moves it waits for.
struct LessonScript {
    struct Frame {
        var poll: LessonJSON
        var expect: LessonJSON?
        let note: Bool
        /// A note that waits for the board to show this player (by name) instead of for Got it.
        let focus: String?
        let complete: Bool
        let coach: LessonCoach?
        /// How long the board shows a frame that moves on by itself.
        let hold: TimeInterval
    }

    let id: String
    let title: String
    let capabilities: LessonJSON
    let create: LessonJSON
    let viewer: String
    var frames: [Frame]

    var matchID: String { create["matchId"]?.string ?? "" }

    static func load(id: String, bundle: Bundle = .main) throws -> LessonScript {
        guard let url = bundle.url(forResource: "lesson-\(id)", withExtension: "json") else {
            throw EngineError.invalidMessage("This lesson is missing from the app.")
        }
        return try LessonScript(LessonJSON.decode(Data(contentsOf: url)))
    }

    init(_ value: LessonJSON) throws {
        guard value["format"]?.string == "magicmobile-lesson", value["version"]?.integer == 1,
              let id = value["id"]?.string, let title = value["title"]?.string, let capabilities = value["capabilities"],
              let create = value["create"], let viewer = value["viewer"]?.string, let rows = value["frames"]?.array, !rows.isEmpty else {
            throw EngineError.invalidMessage("This lesson file can't be read.")
        }
        self.id = id; self.title = title; self.capabilities = capabilities; self.create = create; self.viewer = viewer
        var previous: LessonJSON?
        frames = rows.compactMap { row in
            guard let poll = row["poll"] else { return nil }
            defer { previous = poll }
            return Frame(poll: poll, expect: row["expect"], note: row["note"]?.bool == true, focus: row["focus"]?.string,
                         complete: row["complete"]?.bool == true,
                         coach: LessonCoach(row["coach"]), hold: Self.hold(poll, after: previous))
        }
    }

    /// Something happened on the table (a spell, an attack, a life change): long enough to see it. A step passing: brief.
    static func hold(_ poll: LessonJSON, after previous: LessonJSON?) -> TimeInterval {
        guard let previous else { return 0.4 }
        func table(_ poll: LessonJSON) -> [LessonJSON?] {
            let view = poll["snapshot"]?["gameView"]
            let players = view?["players"]?.array ?? []
            return [view?["stack"], view?["combat"], .array(players.map { $0["life"] ?? .null }),
                    .array(players.map { $0["battlefield"] ?? .null }), .array(players.map { $0["graveyard"] ?? .null })]
        }
        if poll["phase"]?.string == "ended" { return 0.4 }
        return table(poll) == table(previous) ? 0.35 : 1.1
    }
}

/// The coach's state for the board: the frame's note, a nudge after a wrong move, the finish.
@MainActor
final class LessonRun: ObservableObject {
    let script: LessonInfo
    @Published private(set) var coach: LessonCoach?
    /// The coach card waits for Got it before the lesson goes on.
    @Published private(set) var waitsForGotIt = false
    /// The player the board must switch to before the lesson goes on (a swap step), by engine ID.
    @Published private(set) var waitsForFocus: String?
    @Published private(set) var complete = false
    /// Counts wrong moves, so the coach card can shake each time.
    @Published private(set) var nudges = 0
    /// Card and player IDs the coach points at on this frame.
    @Published private(set) var spotIDs: Set<String> = []
    @Published private(set) var spotControl: String?
    /// The coach points at something on the opponent's side of the table (their portrait or their cards).
    @Published private(set) var spotIsAcross = false
    /// What the board has open (LessonBoardCover), reported by the board.
    @Published private(set) var boardCover: LessonBoardCover = .none

    /// Top, unless that covers what she points at or a panel the board opened.
    var placement: LessonCoachPlacement {
        switch boardCover {
        case .panel: return complete || waitsForGotIt ? .low : .tucked
        case .playerCard: return .low
        case .none: return spotIsAcross ? .low : .top
        }
    }

    func boardCovered(_ cover: LessonBoardCover) { if boardCover != cover { boardCover = cover } }
    fileprivate weak var transport: LessonTransport?
    private let defaults: UserDefaults
    /// The board's refresh, so Got it shows the next frame without waiting for the next poll.
    var refresh: (() -> Void)?

    init(script: LessonInfo, defaults: UserDefaults) { self.script = script; self.defaults = defaults }

    func gotIt() {
        guard waitsForGotIt else { return }
        waitsForGotIt = false
        Task { await transport?.release(); refresh?() }
    }

    /// The board now shows this opponent at the top: a swap step it was waiting for goes on.
    func boardFocused(_ playerID: String) {
        guard let waited = waitsForFocus, waited == playerID else { return }
        waitsForFocus = nil
        waitsForGotIt = true
        gotIt()
    }

    func show(_ frame: LessonScript.Frame) {
        if frame.complete || frame.poll["phase"]?.string == "ended" {
            if !complete { LessonProgress.complete(script.id, in: defaults) }
            complete = true
        }
        // A frame without a note of its own keeps the last one up while its move is still to make.
        if let coach = frame.coach { self.coach = coach } else if frame.expect == nil { self.coach = frame.note ? self.coach : nil }
        let focusID = frame.focus.flatMap { name in
            frame.poll["snapshot"]?["gameView"]?["players"]?.array?.first { $0["name"]?.string == name }?["playerId"]?.string
        }
        waitsForFocus = focusID
        waitsForGotIt = frame.note && focusID == nil
        let spot = LessonSpot.resolve(frame.coach?.spot, poll: frame.poll, expect: frame.expect)
        // A swap step also rings the opponent to switch to, in the player card's swap row.
        spotIDs = spot.ids.union(focusID.map { [$0] } ?? []); spotControl = spot.control
        let viewer = frame.poll["snapshot"]?["gameView"]?["myPlayerId"]?.string
        let across = (frame.poll["snapshot"]?["gameView"]?["players"]?.array ?? []).filter { $0["playerId"]?.string != viewer }
        spotIsAcross = spot.ids.contains { id in
            across.contains { $0["playerId"]?.string == id || $0["battlefield"]?[id] != nil }
        }
    }

    func nudge() { nudges += 1 }
}

/// What the coach's spot names on a frame: the expected card when it carries that name, else every card with it.
enum LessonSpot {
    static let controls: Set<String> = ["primary", "medallion", "yes"]

    static func resolve(_ spot: String?, poll: LessonJSON, expect: LessonJSON?) -> (ids: Set<String>, control: String?) {
        guard let spot else { return ([], nil) }
        if controls.contains(spot) { return ([], spot) }
        let view = poll["snapshot"]?["gameView"]
        var named: [String] = []
        for (id, card) in view?["myHand"]?.object ?? [:] where card["name"]?.string == spot { named.append(id) }
        for player in view?["players"]?.array ?? [] {
            if player["name"]?.string == spot, let id = player["playerId"]?.string { return ([id], nil) }
            for (id, card) in player["battlefield"]?.object ?? [:] where card["name"]?.string == spot && card["tapped"]?.bool != true {
                named.append(id)
            }
        }
        if let expected = expect?["value"]?.string, named.contains(expected) { return ([expected], nil) }
        return (Set(named), nil)
    }
}

/// The engine's place for a lesson: recorded polls out, only the recorded move in.
actor LessonTransport: EngineTransport {
    private var script: LessonScript
    private var index = 0
    private var shownAt = Date()
    private var waitingForGotIt: Bool
    private var conceded = false
    private let run: LessonRun
    private let clock: @Sendable () -> Date

    init(script: LessonScript, run: LessonRun, clock: @escaping @Sendable () -> Date = Date.init) {
        self.script = script; self.run = run; self.clock = clock
        shownAt = clock()
        waitingForGotIt = script.frames[0].note
        let first = script.frames[0]
        Task { @MainActor in run.transport = self; run.show(first) }
    }

    func release() { waitingForGotIt = false; shownAt = .distantPast }

    /// Where the lesson stands, for tests: the frame, whether it waits on Got it, the move it waits for.
    var position: (index: Int, waitsForGotIt: Bool, expect: LessonJSON?, count: Int) {
        (index, waitingForGotIt, script.frames[index].expect, script.frames.count)
    }

    func request(_ data: Data) async throws -> Data {
        let request = try LessonJSON.decode(data)
        switch request["op"]?.string ?? "" {
        case "capabilities": return try reply(script.capabilities)
        case "create": return try reply(script.create)
        case "poll": return try reply(poll(after: request["after"]?.integer ?? 0))
        case "respond": return try respond(request["command"]?["answer"])
        case "concede": conceded = true; return try reply(.object([:]))
        case "destroy": return try reply(.object([:]))
        default: return try failure("unknown_operation", "Lessons don't support this.")
        }
    }

    /// The current frame, stepping past frames that move on by themselves once they've been seen.
    private func poll(after: Int64) -> LessonJSON {
        while index + 1 < script.frames.count, !waitingForGotIt, script.frames[index].expect == nil, !script.frames[index].complete,
              clock().timeIntervalSince(shownAt) >= script.frames[index].hold {
            advance()
        }
        let frame = script.frames[index]
        guard case .object(var poll) = frame.poll else { return frame.poll }
        // Every message the board hasn't seen yet: the frames' own events since the cursor.
        let events = script.frames[...index].flatMap { frame -> [LessonJSON] in
            (frame.poll["events"]?.array ?? []).filter { ($0["revision"]?.integer ?? 0) > after }
        }
        poll["events"] = .array(events)
        return .object(poll)
    }

    private func advance() {
        index += 1; shownAt = clock()
        let frame = script.frames[index]
        waitingForGotIt = frame.note
        Task { @MainActor [run] in run.show(frame) }
    }

    private func respond(_ answer: LessonJSON?) throws -> Data {
        let frame = script.frames[index]
        guard let expected = frame.expect, let answer, !conceded else {
            return try failure("lesson_not_now", LessonText.nudge)
        }
        let kind = answer["kind"], value = answer["value"]
        if kind == expected["kind"], value == expected["value"] {
            advance(); return try reply(.object(["accepted": .bool(true)]))
        }
        // Two cards of the same name in the same place play the same: the recording follows the one the player chose.
        if kind == expected["kind"], let chosen = value?.string, let recorded = expected["value"]?.string,
           Self.interchangeable(chosen, recorded, in: frame.poll) {
            for i in index..<script.frames.count {
                script.frames[i].poll = Self.swap(script.frames[i].poll, chosen, recorded)
                script.frames[i].expect = script.frames[i].expect.map { Self.swap($0, chosen, recorded) }
            }
            advance(); return try reply(.object(["accepted": .bool(true)]))
        }
        Task { @MainActor [run] in run.nudge() }
        return try failure("lesson_wrong_move", LessonText.nudge)
    }

    /// Same name, same zone, same tapped state: either card makes the same game.
    static func interchangeable(_ a: String, _ b: String, in poll: LessonJSON) -> Bool {
        func find(_ id: String) -> (name: String, zone: String, tapped: Bool)? {
            let view = poll["snapshot"]?["gameView"]
            if let card = view?["myHand"]?[id] { return (card["name"]?.string ?? "", "hand", false) }
            for player in view?["players"]?.array ?? [] {
                if let card = player["battlefield"]?[id] {
                    return (card["name"]?.string ?? "", "battlefield:" + (player["playerId"]?.string ?? ""), card["tapped"]?.bool == true)
                }
            }
            return nil
        }
        guard let first = find(a), let second = find(b) else { return false }
        return first == second
    }

    /// Every use of one ID as the other and back, in keys and values alike.
    static func swap(_ value: LessonJSON, _ a: String, _ b: String) -> LessonJSON {
        func flip(_ s: String) -> String { s == a ? b : s == b ? a : s }
        switch value {
        case .string(let s): return .string(flip(s))
        case .array(let items): return .array(items.map { swap($0, a, b) })
        case .object(let fields): return .object(Dictionary(uniqueKeysWithValues: fields.map { (flip($0.key), swap($0.value, a, b)) }))
        default: return value
        }
    }

    private func reply(_ result: LessonJSON) throws -> Data {
        try LessonJSON.object(["protocol": .integer(1), "ok": .bool(true), "result": result]).encoded()
    }

    private func failure(_ code: String, _ message: String) throws -> Data {
        try LessonJSON.object(["protocol": .integer(1), "ok": .bool(false),
                              "error": .object(["code": .string(code), "message": .string(message)])]).encoded()
    }
}
