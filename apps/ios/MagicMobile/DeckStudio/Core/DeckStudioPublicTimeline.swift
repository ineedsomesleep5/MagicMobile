import Foundation

/// A bounded review of seat-scoped public observations, not an engine replay.
/// No raw poll, log message, prompt, card instance ID, hand or deck is persisted.
struct DeckStudioPublicTimeline: Codable, Equatable, Sendable {
    static let maximumSamples = 1_500
    static let maximumEvents = 2_000
    static let publicPhases: Set<String> = [
        "UNTAP", "UPKEEP", "DRAW", "PRECOMBAT_MAIN", "BEGIN_COMBAT", "DECLARE_ATTACKERS",
        "DECLARE_BLOCKERS", "FIRST_COMBAT_DAMAGE", "COMBAT_DAMAGE", "END_COMBAT",
        "POSTCOMBAT_MAIN", "END_TURN", "CLEANUP"
    ]

    struct Player: Codable, Equatable, Sendable {
        let id: String
        let name: String
        let life: Int
        let battlefieldCount: Int
    }
    struct Sample: Codable, Equatable, Sendable {
        let revision: Int
        let turn: Int
        let observedAt: Date
        let players: [Player]
    }
    struct Event: Codable, Equatable, Sendable {
        enum Kind: String, Codable, Sendable {
            case battlefieldAppearance, spellOnStack, cast, damage, lifeChange, turnStarted, phase, outcome
        }
        let revision: Int
        let turn: Int
        let kind: Kind
        let playerID: String?
        let cardName: String?
        let typeLine: String?
        let outcome: String?
        var amount: Int? = nil
        var phaseName: String? = nil
        var sourceEventRevision: Int? = nil
    }

    var samples: [Sample] = []
    var events: [Event] = []
    var samplesTruncated = false
    var eventsTruncated = false

    func validate(game: DeckStudioRecordedGame) throws {
        guard samples.count <= Self.maximumSamples, events.count <= Self.maximumEvents else { throw Failure.invalid }
        if samples.isEmpty {
            guard events.isEmpty else { throw Failure.invalid }
            return
        }
        guard game.viewerPlayerID != nil else { throw Failure.invalid }
        var previousRevision = -1
        var previousTurn = -1
        var previousDate = game.startedAt
        var knownPlayers: Set<String> = []
        for sample in samples {
            let ids = sample.players.map(\.id)
            guard sample.revision > previousRevision, sample.revision <= game.lastRevision,
                  (0...1_000_000).contains(sample.turn), sample.turn >= previousTurn,
                  sample.turn <= game.observedTurn,
                  sample.observedAt >= previousDate, sample.observedAt <= game.observedAt,
                  sample.players.count == game.aiOpponents + 1, Set(ids).count == ids.count,
                  ids.contains(game.viewerPlayerID!),
                  sample.players.allSatisfy({ player in
                      UUID(uuidString: player.id) != nil && Self.validText(player.name, maximum: 128) &&
                      (-1_000_000...1_000_000).contains(player.life) && (0...2_000).contains(player.battlefieldCount)
                  }) else { throw Failure.invalid }
            if !knownPlayers.isEmpty && Set(ids) != knownPlayers { throw Failure.invalid }
            knownPlayers = Set(ids)
            previousRevision = sample.revision
            previousTurn = sample.turn
            previousDate = sample.observedAt
        }
        previousRevision = -1
        previousTurn = -1
        var previousSourceRevision = -1
        var sawOutcome = false
        for event in events {
            guard event.revision >= previousRevision,
                  event.revision >= samples[0].revision,
                  event.revision <= game.lastRevision,
                  event.turn >= previousTurn, event.turn <= game.observedTurn,
                  event.playerID.map({ knownPlayers.contains($0) }) ?? true,
                  event.sourceEventRevision.map({ $0 >= 0 && $0 <= event.revision }) ?? true else { throw Failure.invalid }
            if let source = event.sourceEventRevision {
                guard source > previousSourceRevision else { throw Failure.invalid }
                previousSourceRevision = source
            }
            switch event.kind {
            case .battlefieldAppearance, .spellOnStack:
                guard let name = event.cardName, Self.validText(name, maximum: 200),
                      event.typeLine.map({ Self.validText($0, maximum: 200) }) ?? true,
                      event.outcome == nil, event.amount == nil, event.phaseName == nil else { throw Failure.invalid }
            case .cast:
                guard event.playerID != nil, let name = event.cardName, Self.validText(name, maximum: 200),
                      event.outcome == nil, event.amount == nil, event.phaseName == nil,
                      event.sourceEventRevision != nil else { throw Failure.invalid }
            case .damage:
                guard event.playerID != nil, let name = event.cardName, Self.validText(name, maximum: 200),
                      let amount = event.amount, (1...1_000_000).contains(amount), event.outcome == nil,
                      event.phaseName == nil, event.sourceEventRevision != nil else { throw Failure.invalid }
            case .lifeChange:
                guard event.playerID != nil, event.cardName == nil, event.typeLine == nil,
                      let amount = event.amount, amount != 0, (-1_000_000...1_000_000).contains(amount),
                      event.outcome == nil, event.phaseName == nil, event.sourceEventRevision != nil else { throw Failure.invalid }
            case .turnStarted:
                guard event.playerID == nil, event.cardName == nil, event.typeLine == nil,
                      event.outcome == nil, event.amount == nil, event.phaseName == nil,
                      event.sourceEventRevision != nil else { throw Failure.invalid }
            case .phase:
                guard event.playerID == nil, event.cardName == nil, event.typeLine == nil,
                      event.outcome == nil, event.amount == nil,
                      event.phaseName.map({ Self.publicPhases.contains($0) }) ?? false,
                      event.sourceEventRevision != nil else { throw Failure.invalid }
            case .outcome:
                guard game.end == .completed, !sawOutcome,
                      event.cardName == nil, event.typeLine == nil,
                      event.amount == nil, event.phaseName == nil,
                      ["won", "notWon", "unknown"].contains(event.outcome ?? "") else { throw Failure.invalid }
                sawOutcome = true
            }
            previousRevision = event.revision
            previousTurn = event.turn
        }
    }

    static func validText(_ text: String, maximum: Int) -> Bool {
        !text.isEmpty && text.utf8.count <= maximum &&
        !text.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0) ||
            (0x202A...0x202E).contains($0.value) || (0x2066...0x2069).contains($0.value)
        })
    }
    enum Failure: Error { case invalid }
}

/// Keeps object IDs only in memory for deduplication; the saved timeline holds names and counts.
struct DeckStudioPublicTimelineRecorder {
    private var battlefieldIDs: Set<String>?
    private var stackIDs: Set<String>?
    private var lastMessageRevision = -1
    private var knownPublicCards: Set<String> = []

    mutating func observe(result: [String: Any], game: inout DeckStudioRecordedGame, now: Date,
                          sanitizeLog: ((String) -> String)? = nil) {
        guard var timeline = game.timeline,
              let root = result["snapshot"] as? [String: Any], root["schema"] as? String == "xmage-gameview-v1",
              let viewer = root["enginePlayerId"] as? String, viewer == game.viewerPlayerID,
              let view = root["gameView"] as? [String: Any], view["myPlayerId"] as? String == viewer,
              let turn = DeckStudioJSON.integer(view["turn"]), (0...1_000_000).contains(turn),
              let rawPlayers = view["players"] as? [[String: Any]], rawPlayers.count == game.aiOpponents + 1,
              let revision = DeckStudioJSON.integer(result["revision"]), revision >= 0 else { return }

        var players: [DeckStudioPublicTimeline.Player] = []
        var currentBoard = Set<String>()
        var appearances: [(String, String, String?)] = []
        var visibleNames = knownPublicCards
        let resync = DeckStudioJSON.boolean(result["resyncRequired"]) == true
        if resync { timeline.eventsTruncated = true }
        for player in rawPlayers {
            guard let id = player["playerId"] as? String, UUID(uuidString: id) != nil,
                  let name = player["name"] as? String, DeckStudioPublicTimeline.validText(name, maximum: 128),
                  let life = DeckStudioJSON.integer(player["life"]), (-1_000_000...1_000_000).contains(life),
                  let board = publicObjects(player["battlefield"]), board.count <= 2_000 else { return }
            players.append(.init(id: id, name: name, life: life, battlefieldCount: board.count))
            for (objectID, object) in board {
                currentBoard.insert(objectID)
                if !resync, battlefieldIDs != nil, battlefieldIDs?.contains(objectID) == false,
                   let card = visibleCard(object) {
                    appearances.append((id, card.name, card.typeLine))
                }
                if let card = visibleCard(object) { visibleNames.insert(card.name) }
            }
        }
        guard Set(players.map(\.id)).count == players.count, players.contains(where: { $0.id == viewer }),
              timeline.samples.isEmpty || Set(players.map(\.id)) == Set(timeline.samples[0].players.map(\.id)) else { return }

        // XMage publishes stack objects separately. A SPELL object is evidence of
        // a spell on the public stack, but not evidence of who cast it.
        guard let stackObjects = publicObjects(view["stack"]), stackObjects.count <= 128 else { return }
        var currentStack = Set<String>()
        var stackAppearances: [(String, String?)] = []
        for (id, object) in stackObjects {
            currentStack.insert(id)
            if !resync, stackIDs != nil, stackIDs?.contains(id) == false,
               object["mageObjectType"] as? String == "SPELL",
               let source = object["sourceCard"] as? [String: Any], let card = visibleCard(source) {
                stackAppearances.append((card.name, card.typeLine))
            }
            if let source = object["sourceCard"] as? [String: Any], let card = visibleCard(source) {
                visibleNames.insert(card.name)
            }
        }
        // Commander definitions are public even when their physical cards are
        // not on the board. Other deck names are never used as disclosure proof.
        visibleNames.formUnion(game.opponents?.flatMap(\.commanders) ?? [])
        if let commanders = root["commanders"] as? [String: [String: Any]] {
            for info in commanders.values {
                if let name = info["name"] as? String,
                   DeckStudioPublicTimeline.validText(name, maximum: 200) { visibleNames.insert(name) }
            }
        }
        let notices = sanitizeLog.map { publicNotices(result: result, turn: turn, revision: revision,
                                                       players: players, knownCards: visibleNames, sanitize: $0) } ?? []
        let hasNewEvents = !appearances.isEmpty || !stackAppearances.isEmpty || !notices.isEmpty
        if timeline.samples.last?.players != players || timeline.samples.last?.turn != turn || hasNewEvents {
            timeline.samples.append(.init(revision: revision, turn: turn, observedAt: now, players: players))
            if timeline.samples.count > DeckStudioPublicTimeline.maximumSamples {
                timeline.samples.removeFirst(); timeline.samplesTruncated = true
            }
        }
        for (id, name, type) in appearances.sorted(by: { $0.1 < $1.1 }) {
            timeline.events.append(.init(revision: revision, turn: turn, kind: .battlefieldAppearance,
                                         playerID: id, cardName: name, typeLine: type, outcome: nil))
        }
        for (name, type) in stackAppearances.sorted(by: { $0.0 < $1.0 }) {
            timeline.events.append(.init(revision: revision, turn: turn, kind: .spellOnStack,
                                         playerID: nil, cardName: name, typeLine: type, outcome: nil))
        }
        timeline.events.append(contentsOf: notices)
        trim(&timeline)
        if let oldest = timeline.samples.first?.revision {
            let before = timeline.events.count
            timeline.events.removeAll { $0.revision < oldest }
            if timeline.events.count < before { timeline.eventsTruncated = true }
        }
        battlefieldIDs = currentBoard
        stackIDs = currentStack
        knownPublicCards = visibleNames
        game.timeline = timeline
    }

    mutating func finish(game: inout DeckStudioRecordedGame) {
        guard game.end == .completed, var timeline = game.timeline, !timeline.samples.isEmpty,
              !timeline.events.contains(where: { $0.kind == .outcome }) else { return }
        timeline.events.append(.init(revision: game.lastRevision, turn: game.observedTurn,
                                     kind: .outcome, playerID: nil, cardName: nil, typeLine: nil,
                                     outcome: game.won.map { $0 ? "won" : "notWon" } ?? "unknown"))
        trim(&timeline)
        game.timeline = timeline
    }

    private func trim(_ timeline: inout DeckStudioPublicTimeline) {
        if timeline.events.count > DeckStudioPublicTimeline.maximumEvents {
            timeline.events.removeFirst(timeline.events.count - DeckStudioPublicTimeline.maximumEvents)
            timeline.eventsTruncated = true
        }
    }

    private mutating func publicNotices(result: [String: Any], turn: Int, revision: Int,
                                        players: [DeckStudioPublicTimeline.Player], knownCards: Set<String>,
                                        sanitize: (String) -> String) -> [DeckStudioPublicTimeline.Event] {
        guard let raw = result["events"] else { return [] }
        guard let events = raw as? [[String: Any]], events.count <= 128 else { return [] }
        var previous = -1
        var pending: [(Int, String)] = []
        for event in events {
            guard let eventRevision = DeckStudioJSON.integer(event["revision"]),
                  eventRevision > previous, eventRevision <= revision,
                  let kind = event["kind"] as? String else { return [] }
            previous = eventRevision
            guard kind == "message", eventRevision > lastMessageRevision else { continue }
            guard let body = event["body"] as? [String: Any],
                  let message = body["message"] as? String, message.utf8.count <= 4_096 else { return [] }
            pending.append((eventRevision, message))
        }
        lastMessageRevision = max(lastMessageRevision, previous)
        let names = Dictionary(grouping: players, by: \.name).compactMapValues { $0.count == 1 ? $0[0].id : nil }
        let phase = (result["snapshot"] as? [String: Any])?["gameView"] as? [String: Any]
        return pending.compactMap { eventRevision, message in
            let sanitized = sanitize(message)
            let clean = sanitized.hasSuffix(".") ? String(sanitized.dropLast()) : sanitized
            guard !clean.isEmpty, clean.utf8.count <= 512, !clean.contains("\n") else { return nil }
            func make(_ kind: DeckStudioPublicTimeline.Event.Kind, playerID: String? = nil,
                      cardName: String? = nil, amount: Int? = nil, phaseName: String? = nil) -> DeckStudioPublicTimeline.Event {
                var value = DeckStudioPublicTimeline.Event(revision: revision, turn: turn, kind: kind,
                    playerID: playerID, cardName: cardName, typeLine: nil, outcome: nil)
                value.amount = amount; value.phaseName = phaseName; value.sourceEventRevision = eventRevision
                return value
            }
            if let fields = Self.capture(Self.castPattern, in: clean),
               let playerID = names[fields[0]], knownCards.contains(fields[1]) {
                return make(.cast, playerID: playerID, cardName: fields[1])
            }
            if let fields = Self.capture(Self.damagePattern, in: clean),
               knownCards.contains(fields[0]), let targetID = names[fields[2]],
               let amount = Int(fields[1]), (1...1_000_000).contains(amount) {
                return make(.damage, playerID: targetID, cardName: fields[0], amount: amount)
            }
            if let fields = Self.capture(Self.lifePattern, in: clean),
               let playerID = names[fields[0]], let magnitude = Int(fields[2]),
               (1...1_000_000).contains(magnitude) {
                return make(.lifeChange, playerID: playerID,
                            amount: fields[1] == "loses" ? -magnitude : magnitude)
            }
            if let fields = Self.capture(Self.turnPattern, in: clean), Int(fields[0]) == turn {
                return make(.turnStarted)
            }
            if let fields = Self.capture(Self.phasePattern, in: clean),
               DeckStudioPublicTimeline.publicPhases.contains(fields[0]),
               fields[0] == phase?["step"] as? String || fields[0] == phase?["phase"] as? String {
                return make(.phase, phaseName: fields[0])
            }
            return nil
        }
    }

    private static let castPattern = try! NSRegularExpression(pattern: #"^(.{1,128}) casts (.{1,200})$"#)
    private static let damagePattern = try! NSRegularExpression(pattern: #"^(.{1,200}) deals ([0-9]{1,7}) damage to (.{1,128})$"#)
    private static let lifePattern = try! NSRegularExpression(pattern: #"^(.{1,128}) (loses|gains) ([0-9]{1,7}) life$"#)
    private static let turnPattern = try! NSRegularExpression(pattern: #"^TURN ([0-9]{1,7})$"#)
    private static let phasePattern = try! NSRegularExpression(pattern: #"^PHASE: ([A-Z_]{3,32})$"#)
    private static func capture(_ regex: NSRegularExpression, in text: String) -> [String]? {
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.range.location == 0, match.range.length == (text as NSString).length else { return nil }
        let ns = text as NSString
        return (1..<match.numberOfRanges).map { ns.substring(with: match.range(at: $0)) }
    }

    private func publicObjects(_ value: Any?) -> [(String, [String: Any])]? {
        let objects: [[String: Any]]
        if let map = value as? [String: [String: Any]] { objects = Array(map.values) }
        else if let list = value as? [[String: Any]] { objects = list }
        else { return nil }
        var ids = Set<String>()
        var rows: [(String, [String: Any])] = []
        for object in objects {
            guard let id = object["id"] as? String, UUID(uuidString: id) != nil, ids.insert(id).inserted else { return nil }
            rows.append((id, object))
        }
        return rows
    }

    private func visibleCard(_ object: [String: Any]) -> (name: String, typeLine: String?)? {
        guard DeckStudioJSON.boolean(object["hideInfo"]) != true,
              DeckStudioJSON.boolean(object["faceDown"]) != true,
              let name = (object["displayName"] ?? object["name"]) as? String,
              DeckStudioPublicTimeline.validText(name, maximum: 200) else { return nil }
        let types = (object["cardTypes"] as? [String] ?? []).prefix(4)
        let type = types.isEmpty ? nil : types.joined(separator: " ").capitalized
        return (name, type.flatMap { DeckStudioPublicTimeline.validText($0, maximum: 200) ? $0 : nil })
    }
}
