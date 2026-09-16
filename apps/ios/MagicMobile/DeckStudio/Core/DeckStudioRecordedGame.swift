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
    var elapsedSeconds: TimeInterval { max(0, (finishedAt ?? observedAt).timeIntervalSince(startedAt)) }

    func validate() throws {
        guard UUID(uuidString: matchID) != nil, !seatID.isEmpty, seatID.utf8.count <= 128,
              title.utf8.count <= 512, upstream.utf8.count <= 128, catalogue.utf8.count <= 256,
              appBuild.utf8.count <= 128, (1...3).contains(aiOpponents), (0...1_000_000).contains(observedTurn),
              startedAt.timeIntervalSince1970.isFinite, observedAt >= startedAt,
              finishedAt.map({ $0 >= startedAt }) ?? true,
              commandZoneCasts.count <= 12,
              commandZoneCasts.allSatisfy({ !$0.key.isEmpty && $0.key.utf8.count <= 2000 && (0...1_000_000).contains($0.value) }),
              deck == (try DeckStudioDeckSignature(rows: deck.rows)),
              (end == .completed || won == nil), (end == .inProgress) == (finishedAt == nil)
        else { throw DeckStudioDeckSignature.Failure.invalidDeck }
    }
}

/// Observes successful native envelopes only. It never fabricates missing casts,
/// draws, mulligans, missed land drops, or a game outcome from a disconnect.
struct DeckStudioPlaytestAccumulator {
    private(set) var game: DeckStudioRecordedGame?

    mutating func observe(request: Data, response: Data, enabled: Bool, appBuild: String, now: Date) -> Bool {
        guard let input = DeckStudioJSON.object(request), let reply = DeckStudioJSON.object(response),
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
            game = DeckStudioRecordedGame(id: UUID(), matchID: match, seatID: seat, deck: signature,
                title: String((deck["name"] as? String ?? "Commander deck").prefix(128)),
                upstream: upstream, catalogue: catalogue, appBuild: appBuild,
                aiOpponents: seats.count - 1, startedAt: now, observedAt: now)
            return true
        }
        guard var current = game, current.end == .inProgress, input["matchId"] as? String == current.matchID else { return false }
        if op == "destroy" {
            current.end = .left; current.finishedAt = max(now, current.startedAt); current.observedAt = current.finishedAt!
            game = current; return true
        }
        guard op == "poll", input["viewerId"] as? String == current.seatID,
              result["matchId"] as? String == current.matchID, result["viewerId"] as? String == current.seatID,
              let revision = DeckStudioJSON.integer(result["revision"]), revision > current.lastRevision else { return false }
        current.lastRevision = revision
        current.observedAt = max(now, current.observedAt)
        if let root = result["snapshot"] as? [String: Any], root["schema"] as? String == "xmage-gameview-v1",
           let viewer = root["enginePlayerId"] as? String, UUID(uuidString: viewer) != nil,
           current.viewerPlayerID == nil || current.viewerPlayerID == viewer,
           let view = root["gameView"] as? [String: Any], view["myPlayerId"] as? String == viewer {
            current.viewerPlayerID = viewer
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
            if let outcome = root["outcome"] as? [String: Any], DeckStudioJSON.boolean(outcome["ended"]) == true {
                current.end = .completed; current.finishedAt = current.observedAt
                if let winners = outcome["winnerPlayerIds"] as? [String], winners.allSatisfy({ UUID(uuidString: $0) != nil }) {
                    current.won = winners.isEmpty ? nil : winners.contains(viewer)
                }
            }
        }
        if current.end == .inProgress, result["phase"] as? String == "FAILED" {
            current.end = .engineFailed; current.finishedAt = current.observedAt
        }
        game = current; return true
    }
    mutating func close(now: Date) -> DeckStudioRecordedGame? {
        if var value = game, value.end == .inProgress {
            value.end = .interrupted; value.finishedAt = max(now, value.observedAt); value.observedAt = value.finishedAt!
            game = value
        }
        return game
    }
}
