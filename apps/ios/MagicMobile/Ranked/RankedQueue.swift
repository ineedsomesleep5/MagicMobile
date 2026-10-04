import Foundation

/// One ranked queue ticket as the server reports it (mm_ranked_* in
/// supabase/migrations/20261004120000_ranked_ladder.sql).
struct RankedTicket: Equatable, Decodable, Sendable {
    let ticket: UUID?
    let status: String
    let matchId: UUID?
    /// "host" opens the relay table, "guest" joins it.
    let role: String?
    let tableCode: String?
    let opponent: String?
    let opponentStep: Int?

    var isMatched: Bool { status == "matched" && matchId != nil }
    var isHost: Bool { role == "host" }
}

/// The server calls ranked play makes. Tests use a fake.
protocol RankedQueueService: AnyObject {
    func enqueue(protocol: String, rankStep: Int, deckBracket: Int) async throws -> RankedTicket
    func poll(_ ticket: UUID) async throws -> RankedTicket
    func cancel(_ ticket: UUID) async throws -> RankedTicket
    func setTable(match: UUID, code: String) async throws
    func report(match: UUID, outcome: RankOutcome) async throws
}

final class SupabaseRankedQueue: RankedQueueService {
    private let api: SupabaseLite
    init(api: SupabaseLite) { self.api = api }

    private func ticket(_ data: Data) throws -> RankedTicket { try JSONDecoder().decode(RankedTicket.self, from: data) }

    func enqueue(protocol identity: String, rankStep: Int, deckBracket: Int) async throws -> RankedTicket {
        try ticket(await api.rpc("mm_ranked_enqueue", ["p_protocol": identity, "p_rank_step": rankStep, "p_deck_bracket": deckBracket]))
    }
    func poll(_ ticket: UUID) async throws -> RankedTicket {
        try self.ticket(await api.rpc("mm_ranked_poll", ["p_ticket": ticket.uuidString]))
    }
    func cancel(_ ticket: UUID) async throws -> RankedTicket {
        try self.ticket(await api.rpc("mm_ranked_cancel", ["p_ticket": ticket.uuidString]))
    }
    func setTable(match: UUID, code: String) async throws {
        _ = try await api.rpc("mm_ranked_set_table", ["p_match": match.uuidString, "p_code": code])
    }
    func report(match: UUID, outcome: RankOutcome) async throws {
        _ = try await api.rpc("mm_ranked_report", ["p_match": match.uuidString, "p_result": outcome.rawValue])
    }
}

/// Searches the ranked queue for a person for a short while; when nobody suitable is searching, an
/// AI at your tier takes the seat. Shared with Android (RankedMatchmaker.kt).
@MainActor
final class RankedMatchmaker: ObservableObject {
    enum Phase: Equatable {
        case idle
        case searching(since: Date)
        /// Paired with a person. The guest waits here for the host's table code.
        case matched(RankedTicket)
    }

    enum Outcome: Equatable {
        case human(RankedTicket)
        case ai
        case cancelled
    }

    /// How long to look for a person before an AI takes the seat.
    static let searchSeconds: TimeInterval = 40
    /// How long a guest waits for the host's table code.
    static let tableCodeSeconds: TimeInterval = 30

    @Published private(set) var phase: Phase = .idle
    /// The server queue; nil without a profile, which makes every search an AI game.
    var service: RankedQueueService?
    private let sleep: (Double) async throws -> Void
    private var ticket: UUID?
    private var cancelled = false
    private var playAINow = false

    init(service: RankedQueueService?, sleep: @escaping (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.service = service
        self.sleep = sleep
    }

    var isSearching: Bool { phase != .idle }

    /// Looks for an opponent. Without a profile (offline, or profiles switched off) this is an AI game at once.
    func search(protocol identity: String, rankStep: Int, deckBracket: Int) async -> Outcome {
        guard let service, phase == .idle else { return .ai }
        cancelled = false; playAINow = false
        let started = Date()
        phase = .searching(since: started)
        defer { if case .matched = phase {} else { phase = .idle } }
        do {
            var current = try await service.enqueue(protocol: identity, rankStep: rankStep, deckBracket: deckBracket)
            ticket = current.ticket
            while !current.isMatched {
                if cancelled || playAINow || Date().timeIntervalSince(started) >= Self.searchSeconds {
                    // A match made in the meantime still goes ahead (unless the player cancelled outright).
                    guard let ticket else { return cancelled ? .cancelled : .ai }
                    let final = try await service.cancel(ticket)
                    if final.isMatched, !cancelled { current = final; break }
                    if final.isMatched, let match = final.matchId { try? await service.report(match: match, outcome: .loss) }
                    self.ticket = nil
                    return cancelled ? .cancelled : .ai
                }
                try await sleep(2)
                guard let ticket else { return .ai }
                current = try await service.poll(ticket)
            }
            phase = .matched(current)
            if current.isHost { return .human(current) }
            // The guest needs the host's table code.
            let waitStarted = Date()
            while current.tableCode == nil {
                if cancelled { phase = .idle; return .cancelled }
                if Date().timeIntervalSince(waitStarted) >= Self.tableCodeSeconds { phase = .idle; return .ai }
                try await sleep(1.5)
                guard let ticket else { phase = .idle; return .ai }
                current = try await service.poll(ticket)
                phase = .matched(current)
            }
            return .human(current)
        } catch {
            // The queue is a bonus: any server trouble means an AI game.
            phase = .idle
            return cancelled ? .cancelled : .ai
        }
    }

    /// Stops searching and goes back to the ranked screen.
    func cancel() { cancelled = true }

    /// Stops searching and plays the AI now.
    func skipToAI() { playAINow = true }

    /// The match is under way (or abandoned): the matchmaker is free again.
    func finish() { phase = .idle; ticket = nil }

    func shareTable(match: UUID, code: String) async {
        try? await service?.setTable(match: match, code: code)
    }

    func report(match: UUID, outcome: RankOutcome) async {
        try? await service?.report(match: match, outcome: outcome)
    }
}
