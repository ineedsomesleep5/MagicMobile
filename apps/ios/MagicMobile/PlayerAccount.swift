import Foundation
import Security

/// The rules shared with Android (PlayerAccount.kt; parity/chat-cases.json checks both).
enum PlayerAccountRules {
    /// 3–20 letters, digits or underscores; unique ignoring case on the server.
    static func isValidUsername(_ name: String) -> Bool {
        (3...20).contains(name.count) && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }

    /// What the player reads for a server error code (the mm_* functions raise these).
    static func message(for code: String) -> String {
        switch code {
        case "username_taken": return String(localized: "That name is taken. Try another.")
        case "invalid_username": return String(localized: "Use 3–20 letters, numbers or underscores.")
        case "not_found": return String(localized: "No player has that name.")
        case "self": return String(localized: "That's you.")
        case "no_username": return String(localized: "Choose your name first.")
        case "too_many_requests": return String(localized: "You have too many friend requests waiting.")
        case "too_many_reports": return String(localized: "You've sent a lot of reports. Try again later.")
        case "anonymous_provider_disabled", "anonymous_disabled": return String(localized: "Profiles aren't available right now. You can still play.")
        case "offline": return String(localized: "You're offline. Profiles and friends come back when you reconnect.")
        default: return String(localized: "Something went wrong. Try again.")
        }
    }

    /// A friend request's result, as the player reads it.
    static func requestResult(_ result: String, username: String) -> String {
        switch result {
        case "accepted": return String(localized: "You and \(username) are now friends.")
        case "already_friends": return String(localized: "You're already friends with \(username).")
        default: return String(localized: "Friend request sent to \(username).")
        }
    }
}

/// One row of mm_friends(): a friend, or a request either way.
struct PlayerFriend: Identifiable, Equatable, Decodable {
    let id: UUID
    let username: String
    let relation: String
    let online: Bool
    let lastSeenAt: Date?
    let platform: String?
    let hostingCode: String?
    let hostingOpenSeats: Int?

    enum CodingKeys: String, CodingKey {
        case id, username, relation, online, platform
        case lastSeenAt = "last_seen_at", hostingCode = "hosting_code", hostingOpenSeats = "hosting_open_seats"
    }

    var isFriend: Bool { relation == "friend" }
    var isIncoming: Bool { relation == "incoming" }
    /// A table this online friend is hosting with a seat still open.
    var joinableCode: String? {
        guard isFriend, online, let code = hostingCode, (hostingOpenSeats ?? 0) > 0 else { return nil }
        return TableJoinLink.normalized(code)
    }

    static func decodeList(_ data: Data) throws -> [PlayerFriend] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(text)"))
        }
        return try decoder.decode([PlayerFriend].self, from: data)
    }
}

/// Another player's public ranked card (mm_profile_card).
struct PlayerProfileCard: Equatable, Decodable {
    let username: String
    let season: String?
    let rankStep: Int?
    let pips: Int?
    let peakStep: Int?
    let wins: Int?
    let losses: Int?
    let title: String?
    let favoriteCommander: String?

    /// This season's place, or nil when unranked or from an earlier season.
    var position: RankPosition? {
        guard let rankStep, season == RankLadder.season(for: Date()) else { return nil }
        return .published(step: rankStep, pips: pips ?? 0)
    }
}

/// The player's instant profile: an anonymous Supabase account made on first use, a unique
/// username used at every table, friends with presence, and the table the player hosts.
/// Games never depend on it: offline, the app keeps the typed name and plays as before.
@MainActor
final class PlayerAccount: ObservableObject {
    enum Phase: Equatable { case idle, loading, ready, unavailable }

    static let shared = PlayerAccount()

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var username: String?
    @Published private(set) var friends: [PlayerFriend] = []
    @Published private(set) var blocked: [String] = []
    /// Friends' ranked standings by username (mm_friend_ranks), for their badges.
    @Published private(set) var friendRanks: [String: RankPosition] = [:]
    @Published var notice: String?

    /// The code of the table this player hosts while it still has open seats (shared with friends).
    var hosting: (code: String, openSeats: Int)? {
        didSet { if hosting?.code != oldValue?.code || hosting?.openSeats != oldValue?.openSeats { Task { await heartbeat() } } }
    }

    private let api: SupabaseLite
    private var heartbeatTask: Task<Void, Never>?

    init(api: SupabaseLite = SupabaseLite()) { self.api = api }

    var onlineFriendCount: Int { friends.filter { $0.isFriend && $0.online }.count }
    var incomingCount: Int { friends.filter(\.isIncoming).count }

    /// Signs in (making the anonymous account on first use) and loads the profile. Safe to call often.
    func start() async {
        guard phase != .loading else { return }
        // UI tests and previews never make accounts on the real server.
        guard !HowToPlayLaunch.isAutomated(arguments: ProcessInfo.processInfo.arguments,
                                           environment: ProcessInfo.processInfo.environment) else {
            phase = .unavailable; notice = PlayerAccountRules.message(for: "offline"); return
        }
        phase = .loading
        do {
            let data = try await api.rpc("mm_profile")
            let profile = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            username = profile?["username"] as? String
            phase = .ready
            await refresh()
        } catch {
            phase = .unavailable
            notice = PlayerAccountRules.message(for: SupabaseLite.code(of: error))
        }
    }

    func claim(_ name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard PlayerAccountRules.isValidUsername(trimmed) else {
            notice = PlayerAccountRules.message(for: "invalid_username"); return false
        }
        do {
            _ = try await api.rpc("mm_claim_username", ["p_username": trimmed])
            username = trimmed
            notice = nil
            await heartbeat()
            return true
        } catch {
            notice = PlayerAccountRules.message(for: SupabaseLite.code(of: error)); return false
        }
    }

    func refresh() async {
        guard phase == .ready else { return }
        do {
            friends = try PlayerFriend.decodeList(try await api.rpc("mm_friends"))
            let rows = try JSONSerialization.jsonObject(with: try await api.rpc("mm_blocked")) as? [[String: Any]] ?? []
            blocked = rows.compactMap { $0["username"] as? String }
        } catch {
            notice = PlayerAccountRules.message(for: SupabaseLite.code(of: error))
        }
        // Ranks are extra: a server without them leaves the badges off.
        if let data = try? await api.rpc("mm_friend_ranks"),
           let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            let season = RankLadder.season(for: Date())
            friendRanks = Dictionary(rows.compactMap { row -> (String, RankPosition)? in
                guard let name = row["username"] as? String, let step = row["rank_step"] as? Int, let pips = row["pips"] as? Int,
                      row["season"] as? String == season else { return nil }
                return (name, RankPosition.published(step: step, pips: pips))
            }, uniquingKeysWith: { first, _ in first })
        }
    }

    /// The ranked queue, once the player has a profile name.
    var rankedQueue: RankedQueueService? { phase == .ready && username != nil ? SupabaseRankedQueue(api: api) : nil }

    /// Friend challenges, once the player has a profile name.
    var challenges: FriendChallengeService? { phase == .ready && username != nil ? SupabaseFriendChallenges(api: api) : nil }

    /// Shares this season's standing with friends. Quiet on failure: ranks still count on the phone.
    func publishRank(_ rank: RankState, stats: PlayerStats, title: Achievement?, commander: String?) async {
        guard phase == .ready, username != nil else { return }
        _ = try? await api.rpc("mm_ranked_publish", [
            "p_season": rank.season, "p_rank_step": rank.position.step, "p_pips": rank.position.pips,
            "p_peak_step": rank.peak.step, "p_wins": rank.wins, "p_losses": rank.losses,
            "p_title": title?.title ?? NSNull(), "p_favorite_commander": commander ?? NSNull()])
    }

    /// Another player's ranked card, or nil when they have none (or can't be seen).
    func profileCard(_ username: String) async -> PlayerProfileCard? {
        guard phase == .ready, let data = try? await api.rpc("mm_profile_card", ["p_username": username]) else { return nil }
        return try? JSONDecoder().decode(PlayerProfileCard.self, from: data)
    }

    func addFriend(_ name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            let data = try await api.rpc("mm_friend_request", ["p_username": trimmed])
            let result = (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? String) ?? "requested"
            notice = PlayerAccountRules.requestResult(result, username: trimmed)
            await refresh()
        } catch {
            notice = PlayerAccountRules.message(for: SupabaseLite.code(of: error))
        }
    }

    func respond(to friend: PlayerFriend, accept: Bool) async {
        await perform("mm_respond_friend", ["p_requester": friend.id.uuidString, "p_accept": accept])
    }

    func remove(_ friend: PlayerFriend) async { await perform("mm_remove_friend", ["p_other": friend.id.uuidString]) }
    func block(_ name: String) async { await perform("mm_block", ["p_username": name]) }
    func unblock(_ name: String) async { await perform("mm_unblock", ["p_username": name]) }

    /// Reports another player's chat message or name to the developer.
    func report(_ name: String, message: String?, context: String) async {
        await perform("mm_report", ["p_username": name, "p_message": message ?? NSNull(), "p_context": context], refreshAfter: false)
        if notice == nil { notice = String(localized: "Thanks. \(name) was reported.") }
    }

    /// Deletes the account and everything tied to it; a new one is made the next time.
    func deleteAccount() async -> Bool {
        do {
            _ = try await api.rpc("mm_delete_account")
            api.forgetSession()
            username = nil; friends = []; blocked = []; hosting = nil
            phase = .idle
            return true
        } catch {
            notice = PlayerAccountRules.message(for: SupabaseLite.code(of: error)); return false
        }
    }

    /// Presence while the app is open: once now, then every 45 seconds, with friends refreshed.
    func setForeground(_ active: Bool) {
        heartbeatTask?.cancel()
        guard active else { return }
        heartbeatTask = Task { [weak self] in
            if self?.phase != .ready { await self?.start() }
            while !Task.isCancelled {
                await self?.heartbeat()
                await self?.refresh()
                try? await Task.sleep(for: .seconds(45))
            }
        }
    }

    private func heartbeat() async {
        guard phase == .ready, username != nil else { return }
        var params: [String: Any] = ["p_platform": "ios", "p_hosting_code": NSNull(), "p_open_seats": NSNull()]
        if let hosting { params["p_hosting_code"] = hosting.code; params["p_open_seats"] = hosting.openSeats }
        _ = try? await api.rpc("mm_heartbeat", params)
    }

    private func perform(_ function: String, _ params: [String: Any], refreshAfter: Bool = true) async {
        do {
            _ = try await api.rpc(function, params)
            notice = nil
            if refreshAfter { await refresh() }
        } catch {
            notice = PlayerAccountRules.message(for: SupabaseLite.code(of: error))
        }
    }
}

/// The few Supabase Auth and PostgREST calls the profile needs, with the session in the Keychain.
/// The publishable key is public by design; every call runs as the signed-in player.
final class SupabaseLite: @unchecked Sendable {
    struct Failure: Error { let code: String }
    private struct Session: Codable { var accessToken: String; var refreshToken: String; var expiresAt: Date }

    static let baseURL = URL(string: "https://pbspondpyvrjcnvwhtim.supabase.co")!
    static let publishableKey = "sb_publishable_V_i-mPM26P8fNLlKAYu2xg_4p-lPHYu"
    private let keychainService = "com.calebfeliciano.magicmobile.account"
    private let urlSession: URLSession
    private var session: Session?
    private let lock = NSLock()

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        session = loadSession()
    }

    /// A server error's code ("username_taken"), "offline", or "error".
    static func code(of error: Error) -> String {
        if let failure = error as? Failure { return failure.code }
        if (error as? URLError) != nil { return "offline" }
        return "error"
    }

    func rpc(_ function: String, _ params: [String: Any] = [:]) async throws -> Data {
        let token = try await accessToken()
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("rest/v1/rpc/\(function)"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: params)
        let (data, response) = try await urlSession.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { lock.withLock { session?.expiresAt = .distantPast } }
        guard (200..<300).contains(status) else { throw Failure(code: Self.errorCode(data) ?? (status == 401 ? "not_signed_in" : "error")) }
        return data
    }

    func forgetSession() {
        lock.withLock { session = nil }
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: keychainService] as CFDictionary)
    }

    /// PostgREST's {"message": "username_taken", ...} or Auth's {"error_code": ...}.
    static func errorCode(_ data: Data) -> String? {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let code = body["error_code"] as? String { return code }
        return body["message"] as? String
    }

    private var tokenTask: Task<String, Error>?

    /// One sign-in or refresh at a time: two calls at first launch must not make two players.
    private func accessToken() async throws -> String {
        if let current = lock.withLock({ session }), current.expiresAt > Date().addingTimeInterval(60) { return current.accessToken }
        let task: Task<String, Error> = lock.withLock {
            if let running = tokenTask { return running }
            let running = Task { try await self.fetchToken() }
            tokenTask = running
            return running
        }
        defer { lock.withLock { if tokenTask == task { tokenTask = nil } } }
        return try await task.value
    }

    private func fetchToken() async throws -> String {
        let refresh = lock.withLock { session?.refreshToken }
        let path = refresh == nil ? "auth/v1/signup" : "auth/v1/token"
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if refresh != nil { components.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")] }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.publishableKey, forHTTPHeaderField: "apikey")
        // No email or password: Supabase makes an anonymous user.
        request.httpBody = try JSONSerialization.data(withJSONObject: refresh.map { ["refresh_token": $0] } ?? ["data": [String: String]()])
        let (data, response) = try await urlSession.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status),
              let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = body["access_token"] as? String, let newRefresh = body["refresh_token"] as? String else {
            let code = Self.errorCode(data) ?? "error"
            // A refresh token that no longer works (deleted account): start over as a new player.
            if refresh != nil, (400..<500).contains(status) { forgetSession() }
            throw Failure(code: code)
        }
        let expiresIn = (body["expires_in"] as? Double) ?? 3600
        let next = Session(accessToken: access, refreshToken: newRefresh, expiresAt: Date().addingTimeInterval(expiresIn))
        lock.withLock { session = next }
        saveSession(next)
        return access
    }

    private func loadSession() -> Session? {
        var item: CFTypeRef?
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: keychainService,
                                      kSecAttrAccount: "session", kSecReturnData: true]
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    private func saveSession(_ session: Session) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let base: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: keychainService, kSecAttrAccount: "session"]
        let attributes: [CFString: Any] = [kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        if SecItemUpdate(base as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            SecItemAdd(base.merging(attributes) { $1 } as CFDictionary, nil)
        }
    }
}
