import Foundation
import Combine
import Security
import MagicMobileOnDevice

struct OnlineConfiguration: Decodable, Sendable {
    let serverURL: URL
    let supabaseURL: URL
    let publishableKey: String

    static func bundled() -> OnlineConfiguration? {
        guard let url = Bundle.main.url(forResource: "OnlineConfiguration", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(Self.self, from: data),
              value.serverURL.scheme == "https", value.supabaseURL.scheme == "https",
              !value.publishableKey.isEmpty else { return nil }
        return value
    }
}

struct OnlineLobby: Decodable, Equatable, Sendable {
    struct Player: Decodable, Equatable, Identifiable, Sendable {
        let userId: String
        let name: String
        let seatId: String
        let ready: Bool
        let deckSubmitted: Bool
        var id: String { userId }
    }
    let id: String
    let code: String
    let status: String
    let hostUserId: String
    let playerCount: Int
    let players: [Player]
    let matchId: String?
    let seatId: String?
}

private struct OnlineCredentials: Codable, Sendable {
    let access_token: String
    let refresh_token: String
    let expires_at: TimeInterval?
    let user: User
    struct User: Codable, Sendable { let id: String; let email: String? }
}

private enum OnlineKeychain {
    static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.calebfeliciano.magicmobile.online",
        kSecAttrAccount as String: "supabase-session"]
    static func read() -> Data? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }
    static func save(_ data: Data?) throws {
        guard let data else { SecItemDelete(query as CFDictionary); return }
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updated == errSecItemNotFound {
            var insert = query; attributes.forEach { insert[$0.key] = $0.value }
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
                throw OnlineError.message("Your sign-in could not be saved securely. Please try again.")
            }
        } else if updated != errSecSuccess {
            throw OnlineError.message("Your sign-in could not be saved securely. Please try again.")
        }
    }
}

enum OnlineError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

final class OnlineRedirectPolicy: NSObject, URLSessionTaskDelegate {
    static func session(configuration: URLSessionConfiguration = .ephemeral) -> URLSession {
        URLSession(configuration: configuration, delegate: OnlineRedirectPolicy(), delegateQueue: nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Auth bodies and bearer tokens stay at the configured endpoint, including
        // same-origin redirects which could replay a state-changing request.
        completionHandler(nil)
    }
}

actor OnlineAPI {
    let configuration: OnlineConfiguration
    private let session: URLSession
    private let persistsCredentials: Bool
    private var credentials: OnlineCredentials?
    private var refreshTask: Task<OnlineCredentials, Error>?
    private var credentialGeneration = UUID()
    init(configuration: OnlineConfiguration, session: URLSession = OnlineRedirectPolicy.session(), persistsCredentials: Bool = true) {
        self.configuration = configuration
        self.session = session
        self.persistsCredentials = persistsCredentials
        credentials = persistsCredentials ? OnlineKeychain.read().flatMap { try? JSONDecoder().decode(OnlineCredentials.self, from: $0) } : nil
    }
    func userID() -> String? { credentials?.user.id }
    func email() -> String? { credentials?.user.email }

    func authenticate(email: String, password: String, create: Bool) async throws -> Bool {
        credentialGeneration = UUID()
        let generation = credentialGeneration
        refreshTask?.cancel(); refreshTask = nil
        let path = create ? "auth/v1/signup" : "auth/v1/token?grant_type=password"
        let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let data = try await authRequest(path: path, body: body)
        guard credentialGeneration == generation else { throw CancellationError() }
        guard let session = try? JSONDecoder().decode(OnlineCredentials.self, from: data) else {
            if create { return false }
            throw OnlineError.message("Sign-in did not return a session. Please try again.")
        }
        // Requests still using the previous account must not retry with this one.
        credentialGeneration = UUID()
        refreshTask?.cancel(); refreshTask = nil
        try store(session)
        return true
    }

    func signOut() throws {
        credentialGeneration = UUID()
        refreshTask?.cancel(); refreshTask = nil
        if persistsCredentials { try OnlineKeychain.save(nil); CloudAccessTokenStore.save(nil) }
        credentials = nil
    }

    private func store(_ session: OnlineCredentials) throws {
        if persistsCredentials {
            try OnlineKeychain.save(JSONEncoder().encode(session))
            CloudAccessTokenStore.save(session.access_token)
        }
        credentials = session
    }

    private func token(forceRefresh: Bool = false) async throws -> String {
        let generation = credentialGeneration
        guard let current = credentials else { throw OnlineError.message("Sign in to play online.") }
        if !forceRefresh, (current.expires_at ?? 0) > Date().timeIntervalSince1970 + 60 { return current.access_token }
        if let refreshTask {
            let refreshed = try await refreshTask.value
            guard credentialGeneration == generation else { throw CancellationError() }
            return refreshed.access_token
        }
        let task = Task { () throws -> OnlineCredentials in
            let body = try JSONSerialization.data(withJSONObject: ["refresh_token": current.refresh_token])
            let data = try await self.authRequest(path: "auth/v1/token?grant_type=refresh_token", body: body)
            return try JSONDecoder().decode(OnlineCredentials.self, from: data)
        }
        refreshTask = task
        defer { if credentialGeneration == generation { refreshTask = nil } }
        let refreshed = try await task.value
        guard credentialGeneration == generation else { throw CancellationError() }
        try store(refreshed)
        return refreshed.access_token
    }

    private func authRequest(path: String, body: Data) async throws -> Data {
        guard let url = URL(string: path, relativeTo: configuration.supabaseURL.appendingPathComponent("/")) else {
            throw OnlineError.message("Online configuration is unavailable.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.httpBody = body; request.timeoutInterval = 30
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        try Self.validate(data: data, response: response)
        return data
    }

    func request(path: String, body: Data? = nil) async throws -> Data {
        let generation = credentialGeneration
        var request = URLRequest(url: configuration.serverURL.appendingPathComponent(path))
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body; request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        var (data, response) = try await session.data(for: request)
        guard credentialGeneration == generation else { throw CancellationError() }
        if (response as? HTTPURLResponse)?.statusCode == 401 {
            request.setValue("Bearer \(try await token(forceRefresh: true))", forHTTPHeaderField: "Authorization")
            (data, response) = try await session.data(for: request)
            guard credentialGeneration == generation else { throw CancellationError() }
        }
        try Self.validate(data: data, response: response)
        return data
    }

    func currentLobby() async throws -> OnlineLobby? {
        let data = try await request(path: "v1/lobbies/current")
        return try JSONDecoder().decode(OnlineLobby?.self, from: data)
    }

    private static func validate(data: Data, response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else { throw OnlineError.message("The server did not respond. Try again.") }
        guard (200..<300).contains(response.statusCode) else {
            let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let nested = value?["error"] as? [String: Any]
            let text = nested?["message"] as? String ?? value?["message"] as? String
                ?? value?["msg"] as? String ?? value?["error_description"] as? String
            throw OnlineError.message(text ?? "Online play is temporarily unavailable (\(response.statusCode)). Please try again.")
        }
    }
}

struct OnlineEngineTransport: EngineTransport {
    let api: OnlineAPI
    let matchID: String
    func request(_ data: Data) async throws -> Data {
        try await api.request(path: "v1/matches/\(matchID)/engine", body: data)
    }
}

@MainActor
final class OnlineSession: ObservableObject {
    @Published private(set) var userID: String?
    @Published private(set) var email: String?
    @Published private(set) var lobby: OnlineLobby?
    @Published private(set) var busy = false
    @Published private(set) var status = "Play with iPhone and Android friends."
    @Published private(set) var error: String?
    let api: OnlineAPI?
    private var polling: Task<Void, Never>?
    private var generation = UUID()
    var available: Bool { api != nil }

    init(configuration: OnlineConfiguration? = .bundled()) {
        api = configuration.map { OnlineAPI(configuration: $0) }
    }
    init(api: OnlineAPI) { self.api = api }
    func restore() async {
        userID = await api?.userID(); email = await api?.email()
        guard lobby == nil, userID != nil, let api else { return }
        do {
            if let lobby = try await api.currentLobby(), ["waiting", "ready", "active", "interrupted"].contains(lobby.status) {
                self.lobby = lobby; beginPolling()
            }
        } catch { self.error = error.localizedDescription }
    }
    func signIn(email: String, password: String, create: Bool) async {
        await perform {
            guard let api = self.api else { return }
            let signedIn = try await api.authenticate(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password, create: create)
            await self.restore()
            self.status = signedIn ? "Choose a lobby to get started." : "Check your email to confirm your account, then sign in."
        }
    }
    func signOut() async {
        guard lobby == nil else { return }
        await perform { try await self.api?.signOut(); await self.restore() }
    }
    func enter(code: String?, name: String, playerCount: Int, identity: BuildIdentity,
               deck: MagicMobileOnDevice.JSONValue) async {
        guard lobby == nil else { return }
        await perform {
            guard let api = self.api else { return }
            var fields: [String: MagicMobileOnDevice.JSONValue] = ["name": .string(name), "identity": identity.json,
                "deck": deck, "playerCount": .integer(Int64(playerCount)), "platform": .string("ios")]
            if let code { fields["code"] = .string(code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()) }
            do {
                let data = try await api.request(path: code == nil ? "v1/lobbies" : "v1/lobbies/join", body: MagicMobileOnDevice.JSONValue.object(fields).encoded())
                self.lobby = try JSONDecoder().decode(OnlineLobby.self, from: data)
            } catch {
                // A timeout can occur after the server created the lobby. Recover
                // membership rather than issuing a second create/join mutation.
                let originalError = error
                guard let recovered = try? await api.currentLobby(),
                      ["waiting", "ready", "active", "interrupted"].contains(recovered.status) else { throw originalError }
                self.lobby = recovered
            }
            self.status = "Waiting for players"
            self.beginPolling()
        }
    }
    func ready(_ value: Bool) async { await command("ready", fields: ["ready": .bool(value)]) }
    func start() async { await command("start") }
    private func command(_ action: String, fields: [String: MagicMobileOnDevice.JSONValue] = [:]) async {
        await perform {
            guard let api = self.api, let lobby = self.lobby else { return }
            let data = try await api.request(path: "v1/lobbies/\(lobby.id)/\(action)", body: MagicMobileOnDevice.JSONValue.object(fields).encoded())
            self.lobby = try JSONDecoder().decode(OnlineLobby.self, from: data)
        }
    }
    func leave() async throws {
        guard let api, let lobby else { return }
        _ = try await api.request(path: "v1/lobbies/\(lobby.id)/leave", body: Data("{}".utf8))
        generation = UUID(); polling?.cancel(); polling = nil
        self.lobby = nil; error = nil; status = "Choose a lobby to get started."
    }
    func leaveLobby() async { await perform { try await self.leave() } }
    func setForeground(_ active: Bool) {
        if active { beginPolling() } else { generation = UUID(); polling?.cancel(); polling = nil }
    }
    private func beginPolling() {
        guard polling == nil, lobby != nil else { return }
        let token = generation
        polling = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(2))
                    guard let self, let api = self.api, let lobby = self.lobby, token == self.generation else { return }
                    let data = try await api.request(path: "v1/lobbies/\(lobby.id)")
                    guard !Task.isCancelled, token == self.generation else { return }
                    self.lobby = try JSONDecoder().decode(OnlineLobby.self, from: data)
                    self.error = nil
                    switch self.lobby?.status {
                    case "active": self.status = "Connected"
                    case "interrupted": self.status = "Game interrupted"
                    case "finished", "abandoned", "cancelled": self.status = "Game ended"
                    default: self.status = "Waiting for players"
                    }
                } catch {
                    guard let self, !Task.isCancelled, token == self.generation else { return }
                    self.status = "Reconnecting…"
                    self.error = error.localizedDescription
                }
            }
        }
    }
    private func perform(_ action: () async throws -> Void) async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do { try await action() } catch { self.error = error.localizedDescription }
    }
}
