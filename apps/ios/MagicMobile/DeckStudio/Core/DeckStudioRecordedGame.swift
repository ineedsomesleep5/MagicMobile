import Foundation

/// Canonical *playing* cards, independent of title, row order and printings.
/// The engine identity is recorded separately; no telemetry is sent to a server.
struct DeckStudioDeckSignature: Codable, Equatable, Sendable {
    struct Row: Codable, Equatable, Sendable {
        let name: String
        let count: Int
        let section: String
    }
    let rows: [Row]
    init(rows: [Row]) throws {
        guard rows.count <= 2000 else { throw Failure.invalidDeck }
        var counts: [String: [String: Int]] = [:]
        var total = 0
        for row in rows {
            guard ["main", "commanders", "companions"].contains(row.section),
                  !row.name.isEmpty, row.name.utf8.count <= 2000,
                  !row.name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                  (1...2000).contains(row.count), row.count <= 2000 - total else { throw Failure.invalidDeck }
            total += row.count
            counts[row.section, default: [:]][row.name, default: 0] += row.count
        }
        self.rows = counts.keys.sorted().flatMap { section in
            counts[section]!.keys.sorted().map { Row(name: $0, count: counts[section]![$0]!, section: section) }
        }
    }
    static func native(_ value: [String: Any]) throws -> Self {
        var rows: [Row] = []
        for section in ["main", "commanders", "companions"] {
            guard let entries = value[section] as? [[String: Any]] else { throw Failure.invalidDeck }
            for entry in entries {
                guard let name = entry["name"] as? String, let count = DeckStudioJSON.integer(entry["count"]) else { throw Failure.invalidDeck }
                rows.append(.init(name: name, count: count, section: section))
            }
        }
        return try Self(rows: rows)
    }
    enum Failure: Error { case invalidDeck }
}

enum DeckStudioJSON {
    static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue,
              number.doubleValue >= Double(Int.min), number.doubleValue < Double(Int.max) else { return nil }
        return number.intValue
    }
    static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
    static func object(_ data: Data) -> [String: Any]? {
        guard data.count <= 16 * 1024 * 1024 else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

import CoreFoundation

struct DeckStudioRecordedGame: Codable, Equatable, Identifiable, Sendable {
    enum End: String, Codable, Sendable { case inProgress, completed, left, interrupted, engineFailed }
    struct Opponent: Codable, Equatable, Sendable {
        let playerID: String
        let name: String
        let commanders: [String]
    }
    let id: UUID
    let matchID: String
    let seatID: String
    let deck: DeckStudioDeckSignature
    let title: String
    let upstream: String
    let catalogue: String
    let appBuild: String
    let aiOpponents: Int
    let startedAt: Date
    var observedAt: Date
    var finishedAt: Date?
    var end: End = .inProgress
    var observedTurn = 0
    /// Native commander watcher counts; never inferred from hand/stack movements.
    var commandZoneCasts: [String: Int] = [:]
    var won: Bool?
    var lastRevision = -1
    var viewerPlayerID: String?
    /// Public, seat-scoped player names and public commander card names only.
    var opponents: [Opponent]?
    /// Present only for matches started with the separate detailed-history choice.
    var timeline: DeckStudioPublicTimeline?
    var elapsedSeconds: TimeInterval { max(0, (finishedAt ?? observedAt).timeIntervalSince(startedAt)) }

    func validate() throws {
        guard UUID(uuidString: matchID) != nil, !seatID.isEmpty, seatID.utf8.count <= 128,
              title.utf8.count <= 512, upstream.utf8.count <= 128, catalogue.utf8.count <= 256,
              appBuild.utf8.count <= 128, (1...3).contains(aiOpponents), (0...1_000_000).contains(observedTurn),
              startedAt.timeIntervalSince1970.isFinite, observedAt.timeIntervalSince1970.isFinite,
              observedAt >= startedAt, observedAt.timeIntervalSince(startedAt) <= 31_536_000,
              finishedAt.map({ $0.timeIntervalSince1970.isFinite && $0 >= startedAt && $0 <= observedAt }) ?? true,
              lastRevision >= -1, viewerPlayerID.map({ UUID(uuidString: $0) != nil }) ?? true,
              opponents.map({ $0.count <= aiOpponents && Set($0.map(\.playerID)).count == $0.count && $0.allSatisfy {
                  UUID(uuidString: $0.playerID) != nil && $0.playerID != viewerPlayerID &&
                  !$0.name.isEmpty && $0.name.utf8.count <= 128 &&
                  !$0.name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) &&
                  $0.commanders.count <= 12 && $0.commanders.allSatisfy { !$0.isEmpty && $0.utf8.count <= 200 &&
                      !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }
              } }) ?? true,
              !upstream.isEmpty, !catalogue.isEmpty, !appBuild.isEmpty,
              commandZoneCasts.count <= 12,
              commandZoneCasts.allSatisfy({ item in
                  deck.rows.contains { $0.section == "commanders" && $0.name == item.key } &&
                  (0...1_000_000).contains(item.value)
              }),
              deck == (try DeckStudioDeckSignature(rows: deck.rows)),
              (end == .completed || won == nil), (end == .inProgress) == (finishedAt == nil)
        else { throw DeckStudioDeckSignature.Failure.invalidDeck }
        try timeline?.validate(game: self)
    }
}

/// Observes successful native envelopes only. It never fabricates missing casts,
/// draws, mulligans, missed land drops, or a game outcome from a disconnect.
struct DeckStudioPlaytestAccumulator {
    private(set) var game: DeckStudioRecordedGame?
    private var timelineRecorder = DeckStudioPublicTimelineRecorder()
    private var detailRevoked = false

    mutating func observe(request: Data, response: Data, enabled: Bool, appBuild: String, now: Date,
                          detailedEnabled: Bool = false, sanitizeLog: ((String) -> String)? = nil) -> Bool {
        guard enabled, now.timeIntervalSince1970.isFinite,
              let input = DeckStudioJSON.object(request), let reply = DeckStudioJSON.object(response),
              DeckStudioJSON.integer(input["protocol"]) == 1, DeckStudioJSON.integer(reply["protocol"]) == 1,
              DeckStudioJSON.boolean(reply["ok"]) == true,
              let result = reply["result"] as? [String: Any], let op = input["op"] as? String else { return false }
        if op == "create" {
            guard enabled, game == nil,
                  let config = input["configuration"] as? [String: Any],
                  let seats = config["seats"] as? [[String: Any]], (2...4).contains(seats.count),
                  seats.allSatisfy({ ["human", "ai"].contains($0["controller"] as? String ?? "human") }),
                  seats.filter({ ($0["controller"] as? String ?? "human") == "human" }).count == 1,
                  let human = seats.first(where: { ($0["controller"] as? String ?? "human") == "human" }),
                  let seat = human["seatId"] as? String, !seat.isEmpty,
                  let deck = human["deck"] as? [String: Any], let signature = try? DeckStudioDeckSignature.native(deck),
                  let match = result["matchId"] as? String, UUID(uuidString: match) != nil,
                  let engine = result["engine"] as? [String: Any], engine["engine"] as? String == "xmage",
                  engine["execution"] as? String == "native-aot",
                  let upstream = engine["upstream"] as? String, let catalogue = engine["catalogueHash"] as? String else { return false }
            var created = DeckStudioRecordedGame(id: UUID(), matchID: match, seatID: seat, deck: signature,
                title: String((deck["name"] as? String ?? "Commander deck").prefix(128)),
                upstream: upstream, catalogue: catalogue, appBuild: appBuild,
                aiOpponents: seats.count - 1, startedAt: now, observedAt: now)
            if detailedEnabled { created.timeline = DeckStudioPublicTimeline() }
            guard (try? created.validate()) != nil else { return false }
            game = created
            return true
        }
        guard var current = game, current.end == .inProgress, input["matchId"] as? String == current.matchID else { return false }
        if !detailedEnabled { detailRevoked = true; current.timeline = nil }
        if op == "destroy" {
            guard DeckStudioJSON.boolean(result["destroyed"]) == true else { return false }
            current.end = .left; current.finishedAt = max(now, current.observedAt); current.observedAt = current.finishedAt!
            guard (try? current.validate()) != nil else { return false }
            game = current; return true
        }
        guard op == "poll", input["viewerId"] as? String == current.seatID,
              result["matchId"] as? String == current.matchID, result["viewerId"] as? String == current.seatID,
              let revision = DeckStudioJSON.integer(result["revision"]), revision >= 0, revision > current.lastRevision,
              let phase = result["phase"] as? String,
              ["starting", "running", "ended", "failed", "closed"].contains(phase) else { return false }
        // Reject a mismatched inner view before advancing the recorded revision.
        // A malformed update must not block a later valid lower-revision reply.
        if let raw = result["snapshot"], !(raw is NSNull) {
            guard let root = raw as? [String: Any], root["schema"] as? String == "xmage-gameview-v1",
                  let viewer = root["enginePlayerId"] as? String, UUID(uuidString: viewer) != nil,
                  current.viewerPlayerID == nil || current.viewerPlayerID == viewer,
                  let view = root["gameView"] as? [String: Any], view["myPlayerId"] as? String == viewer else { return false }
        }
        current.lastRevision = revision
        current.observedAt = max(now, current.observedAt)
        if let root = result["snapshot"] as? [String: Any], root["schema"] as? String == "xmage-gameview-v1",
           let viewer = root["enginePlayerId"] as? String, UUID(uuidString: viewer) != nil,
           current.viewerPlayerID == nil || current.viewerPlayerID == viewer,
           let view = root["gameView"] as? [String: Any], view["myPlayerId"] as? String == viewer {
            current.viewerPlayerID = viewer
            if let players = view["players"] as? [[String: Any]], (2...4).contains(players.count),
               players.contains(where: { $0["playerId"] as? String == viewer }),
               players.allSatisfy({ UUID(uuidString: $0["playerId"] as? String ?? "") != nil }) {
                let publicCommanders = root["commanders"] as? [String: [String: Any]] ?? [:]
                let opponents = players.compactMap { player -> DeckStudioRecordedGame.Opponent? in
                    guard let id = player["playerId"] as? String, id != viewer,
                          let name = player["name"] as? String, !name.isEmpty, name.utf8.count <= 128,
                          !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
                    let names = publicCommanders.sorted(by: { $0.key < $1.key }).compactMap { _, info -> String? in
                        guard info["ownerPlayerId"] as? String == id else { return nil }
                        guard let name = info["name"] as? String, !name.isEmpty, name.utf8.count <= 200,
                              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
                        return name
                    }
                    return .init(playerID: id, name: name, commanders: names)
                }
                if opponents.count == current.aiOpponents, opponents.allSatisfy({ $0.commanders.count <= 12 }) {
                    current.opponents = opponents
                }
            }
            if let turn = DeckStudioJSON.integer(view["turn"]), (0...1_000_000).contains(turn) {
                current.observedTurn = max(current.observedTurn, turn)
            }
            if let commanders = root["commanders"] as? [String: [String: Any]], commanders.count <= 12 {
                for info in commanders.values where info["ownerPlayerId"] as? String == viewer {
                    guard let name = info["name"] as? String,
                          current.deck.rows.contains(where: { $0.section == "commanders" && $0.name == name }),
                          let count = DeckStudioJSON.integer(info["castsFromCommandZone"]), (0...1_000_000).contains(count) else { continue }
                    current.commandZoneCasts[name] = max(current.commandZoneCasts[name, default: 0], count)
                }
            }
            if phase != "failed", phase != "closed", let outcome = root["outcome"] as? [String: Any], DeckStudioJSON.boolean(outcome["ended"]) == true {
                current.end = .completed; current.finishedAt = current.observedAt
                if let winners = outcome["winnerPlayerIds"] as? [String], winners.allSatisfy({ UUID(uuidString: $0) != nil }) {
                    current.won = winners.isEmpty ? nil : winners.contains(viewer)
                }
            }
        }
        if current.end == .inProgress {
            switch phase {
            case "failed": current.end = .engineFailed
            case "closed": current.end = .interrupted
            case "ended": current.end = .completed // Engine termination, not an inferred winner.
            default: break
            }
            if current.end != .inProgress { current.finishedAt = current.observedAt }
        }
        if !detailRevoked, detailedEnabled, current.timeline != nil {
            timelineRecorder.observe(result: result, game: &current, now: current.observedAt,
                                     sanitizeLog: sanitizeLog)
            timelineRecorder.finish(game: &current)
        }
        guard (try? current.validate()) != nil else { return false }
        game = current; return true
    }
    mutating func close(now: Date) -> DeckStudioRecordedGame? {
        if now.timeIntervalSince1970.isFinite, var value = game, value.end == .inProgress {
            value.end = .interrupted; value.finishedAt = max(now, value.observedAt); value.observedAt = value.finishedAt!
            if (try? value.validate()) != nil { game = value }
        }
        return game
    }
}
