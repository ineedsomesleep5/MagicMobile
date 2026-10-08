import Foundation

/// A friend challenge as the server reports it (mm_challenge_* in
/// supabase/migrations/20261004180000_friend_challenges.sql). Shared with Android (FriendChallenges.kt).
struct FriendChallenge: Equatable, Identifiable, Decodable, Sendable {
    let id: UUID
    /// "quick" or "ranked".
    let mode: String
    /// pending, accepted, declined, cancelled or expired.
    let status: String
    let role: String?
    let challenger: String?
    let challenged: String?
    let challengerStep: Int?
    /// The relay identity the challenger's table needs.
    let `protocol`: String?
    /// Only after accepting, for the friend.
    let tableCode: String?
    /// The ranked match both sides report to (ranked challenges only).
    let matchId: UUID?

    var isRanked: Bool { mode == PlayMode.ranked.rawValue }
    var playMode: PlayMode { isRanked ? .ranked : .quick }
    var isPending: Bool { status == "pending" }

    /// What a challenge reads as once nothing is known about it any more.
    static func closed(_ id: UUID) -> FriendChallenge {
        FriendChallenge(id: id, mode: "quick", status: "cancelled", role: nil, challenger: nil, challenged: nil,
                        challengerStep: nil, protocol: nil, tableCode: nil, matchId: nil)
    }
}

enum FriendChallengeRules {
    /// A challenge waits this long for an answer (the server's limit).
    static let expirySeconds: TimeInterval = 120

    /// Ranked friend games need the same tier, Gold with Gold (Caleb, 2026-10-04). A friend without a
    /// published standing this season is a fresh Bronze IV, as the server reads them.
    static func mayRank(myStep: Int, friendStep: Int?) -> Bool {
        RankPosition.atStep(myStep).tier == RankPosition.atStep(friendStep ?? 0).tier
    }

    static func message(for code: String) -> String {
        switch code {
        case "rank_mismatch": return String(localized: "Ranked challenges need the same tier.")
        case "not_friends": return String(localized: "You can only challenge friends.")
        case "challenge_closed": return String(localized: "That challenge has closed.")
        case "protocol_mismatch": return String(localized: "You're on different app versions. Update both phones to play.")
        default: return PlayerAccountRules.message(for: code)
        }
    }
}

/// The server calls challenges make. Tests use a fake.
protocol FriendChallengeService: AnyObject {
    func send(to username: String, mode: PlayMode, protocol: String, rankStep: Int, tableCode: String) async throws -> FriendChallenge
    func incoming() async throws -> [FriendChallenge]
    func status(_ id: UUID) async throws -> FriendChallenge
    func accept(_ id: UUID, protocol: String, rankStep: Int) async throws -> FriendChallenge
    func decline(_ id: UUID) async throws
    func cancel(_ id: UUID) async throws -> FriendChallenge
}

final class SupabaseFriendChallenges: FriendChallengeService {
    private let api: SupabaseLite
    init(api: SupabaseLite) { self.api = api }

    private func challenge(_ data: Data, id: UUID? = nil) throws -> FriendChallenge {
        if let decoded = try? JSONDecoder().decode(FriendChallenge.self, from: data) { return decoded }
        guard let id else { throw SupabaseLite.Failure(code: "error") }
        return .closed(id)  // the server no longer shows it to this player
    }

    func send(to username: String, mode: PlayMode, protocol identity: String, rankStep: Int, tableCode: String) async throws -> FriendChallenge {
        try challenge(await api.rpc("mm_challenge_send", ["p_username": username, "p_mode": mode.rawValue, "p_protocol": identity,
                                                          "p_rank_step": rankStep, "p_table_code": tableCode]))
    }
    func incoming() async throws -> [FriendChallenge] {
        try JSONDecoder().decode([FriendChallenge].self, from: await api.rpc("mm_challenge_incoming"))
    }
    func status(_ id: UUID) async throws -> FriendChallenge {
        try challenge(await api.rpc("mm_challenge_status", ["p_challenge": id.uuidString]), id: id)
    }
    func accept(_ id: UUID, protocol identity: String, rankStep: Int) async throws -> FriendChallenge {
        try challenge(await api.rpc("mm_challenge_accept", ["p_challenge": id.uuidString, "p_protocol": identity, "p_rank_step": rankStep]))
    }
    func decline(_ id: UUID) async throws {
        _ = try await api.rpc("mm_challenge_decline", ["p_challenge": id.uuidString])
    }
    func cancel(_ id: UUID) async throws -> FriendChallenge {
        try challenge(await api.rpc("mm_challenge_cancel", ["p_challenge": id.uuidString]), id: id)
    }
}

/// Sends challenges and waits for the answer; watches for challenges sent to this player while the
/// menu is open. Shared with Android (FriendChallengeCoordinator in FriendChallenges.kt).
@MainActor
final class FriendChallengeCoordinator: ObservableObject {
    enum Answer: Equatable {
        case accepted(FriendChallenge)
        case declined
        case expired
        case cancelled
        /// A server error code (FriendChallengeRules.message).
        case failed(String)
    }

    /// The challenge this player sent, while waiting for the friend.
    @Published private(set) var outgoing: FriendChallenge?
    /// Challenges waiting for this player, newest first.
    @Published private(set) var incoming: [FriendChallenge] = []
    var service: FriendChallengeService?
    /// How often the menu checks for challenges while a friend is online, and while none is (a
    /// friend who has just come online can still challenge before the friends list catches up).
    static let watchSeconds: Double = 5
    static let quietWatchSeconds: Double = 20
    private let sleep: (Double) async throws -> Void
    private var cancelRequested = false
    private var answered: Set<UUID> = []

    init(service: FriendChallengeService?, sleep: @escaping (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.service = service
        self.sleep = sleep
    }

    var isWaiting: Bool { outgoing != nil }

    /// Sends a challenge for a table this player already opened, then waits for the answer.
    func challenge(_ username: String, mode: PlayMode, protocol identity: String, rankStep: Int, tableCode: String) async -> Answer {
        guard let service else { return .failed("offline") }
        guard outgoing == nil else { return .failed("error") }
        cancelRequested = false
        do {
            var current = try await service.send(to: username, mode: mode, protocol: identity, rankStep: rankStep, tableCode: tableCode)
            outgoing = current
            defer { outgoing = nil }
            let started = Date()
            while current.isPending {
                if cancelRequested || Date().timeIntervalSince(started) > FriendChallengeRules.expirySeconds + 5 {
                    // An answer that arrived meanwhile still stands.
                    let final = (try? await service.cancel(current.id)) ?? .closed(current.id)
                    if final.status == "accepted" { return .accepted(final) }
                    return cancelRequested ? .cancelled : .expired
                }
                try await sleep(2)
                current = try await service.status(current.id)
            }
            switch current.status {
            case "accepted": return .accepted(current)
            case "declined": return .declined
            case "expired": return .expired
            default: return .cancelled
            }
        } catch {
            outgoing = nil
            return .failed(SupabaseLite.code(of: error))
        }
    }

    /// Withdraws the challenge being waited on.
    func cancelOutgoing() { cancelRequested = true }

    /// Checks for challenges until cancelled (run while the menu is showing). `friendOnline` picks
    /// the pace: each check wakes the phone's radio, so it is slower when nobody could challenge.
    func watch(friendOnline: @MainActor () -> Bool = { true }) async {
        while !Task.isCancelled {
            await refreshIncoming()
            do { try await sleep(friendOnline() ? Self.watchSeconds : Self.quietWatchSeconds) } catch { return }
        }
    }

    func refreshIncoming() async {
        guard let service else { if !incoming.isEmpty { incoming = [] }; return }
        guard let list = try? await service.incoming() else { return }
        let next = list.filter { $0.isPending && !answered.contains($0.id) }
        // Assigned only on a change: every assignment redraws the menu.
        if next != incoming { incoming = next }
    }

    /// Accepts: the challenge with its table code (and the ranked match for ranked).
    func accept(_ challenge: FriendChallenge, protocol identity: String, rankStep: Int) async throws -> FriendChallenge {
        answered.insert(challenge.id)
        incoming.removeAll { $0.id == challenge.id }
        guard let service else { throw SupabaseLite.Failure(code: "offline") }
        return try await service.accept(challenge.id, protocol: identity, rankStep: rankStep)
    }

    func decline(_ challenge: FriendChallenge) async {
        answered.insert(challenge.id)
        incoming.removeAll { $0.id == challenge.id }
        try? await service?.decline(challenge.id)
    }
}
