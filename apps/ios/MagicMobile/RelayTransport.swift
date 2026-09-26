import Foundation
import MagicMobileOnDevice

/// What OnDeviceMultiplayer needs from a table connection: Game Center or the cross-play relay.
/// Both report only authenticated peer IDs (a GKPlayer ID or a relay-assigned connection ID).
@MainActor
protocol TablePacketTransport: AnyObject {
    var onPacket: (@MainActor @Sendable (Data, String) -> Void)? { get set }
    var onDisconnect: (@MainActor @Sendable (String) -> Void)? { get set }
    var onError: (@MainActor @Sendable (String) -> Void)? { get set }
    var onPacketRejected: (@MainActor @Sendable (String) -> Void)? { get set }
    func send(_ data: Data, to authenticatedPeerID: String) throws
    func disconnect()
}

extension GameKitTransport: TablePacketTransport {}

/// One seat at a relay table, as the relay reports it.
struct RelayPeer: Equatable, Sendable {
    let id: String
    let name: String
    let connected: Bool
}

enum RelayConfiguration {
    static let defaultURL = URL(string: "https://magicmobile-relay.calebjfeliciano.workers.dev")!

    /// Debug builds may point at a local `wrangler dev` (MAGICMOBILE_RELAY_URL).
    static var url: URL {
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["MAGICMOBILE_RELAY_URL"], let url = URL(string: value) { return url }
        #endif
        return defaultURL
    }
}

/// The cross-play relay (services/table-relay), in GameKitTransport's role for tables that
/// mix iPhones and Android phones. The relay stamps each delivered packet with the sender's
/// relay-assigned ID; that is the only sender identity this transport reports.
@MainActor
final class RelayTransport: TablePacketTransport {
    var onPacket: (@MainActor @Sendable (Data, String) -> Void)?
    var onDisconnect: (@MainActor @Sendable (String) -> Void)?
    var onError: (@MainActor @Sendable (String) -> Void)?
    var onPacketRejected: (@MainActor @Sendable (String) -> Void)?
    var onRoster: ((_ peers: [RelayPeer], _ full: Bool) -> Void)?
    /// This phone lost the relay and is trying to reclaim its seat.
    var onConnectionChanged: ((Bool) -> Void)?

    private(set) var localPeerID: String?
    private(set) var code: String?
    private(set) var peers: [RelayPeer] = []
    private(set) var isFull = false
    private(set) var seats = 0

    private let baseURL: URL
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var name = "Player"
    private var token: String?
    private var closed = false
    private var generation = 0
    private var reconnectAttempts = 0
    private var parts: [String: [String?]] = [:]
    /// Frames written while the socket reconnects; sent in order once the relay returns the seat.
    private var outbox: [String] = []
    private var outboxCharacters = 0
    private var welcomed = false
    private var pingTask: Task<Void, Never>?
    /// Frames stay well under the relay's 1,000,000-character limit after JSON escaping.
    private static let partCharacters = 400_000

    init(baseURL: URL = RelayConfiguration.url) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        session = URLSession(configuration: configuration)
    }

    /// Creates a table and returns its code and the host key only this phone holds.
    func createTable(seats: Int) async throws -> (code: String, hostKey: String) {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/tables"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["seats": seats])
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) }
        catch { throw EngineError.invalidMessage("Could not reach the table service. Check your connection and try again.") }
        let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let code = value?["code"] as? String, let key = value?["hostKey"] as? String else {
            throw EngineError.invalidMessage((value?["message"] as? String) ?? "The table service could not open a table. Try again.")
        }
        return (code, key)
    }

    /// Opens the table's socket: the creator passes its host key, guests only the code.
    func connect(code: String, name: String, hostKey: String? = nil) {
        self.code = code.uppercased(); self.name = name
        open(hostKey: hostKey, resume: nil)
    }

    private func open(hostKey: String?, resume: String?) {
        guard let code else { return }
        generation += 1
        let current = generation
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/tables/\(code)/socket"), resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.queryItems = [URLQueryItem(name: "name", value: name)]
            + (hostKey.map { [URLQueryItem(name: "key", value: $0)] } ?? [])
            + (resume.map { [URLQueryItem(name: "resume", value: $0)] } ?? [])
        let task = session.webSocketTask(with: components.url!)
        task.maximumMessageSize = 4 * 1024 * 1024
        self.task = task
        task.resume()
        receiveNext(task, generation: current)
        pingTask?.cancel()
        pingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard let self, current == self.generation, !self.closed else { return }
                self.task?.send(.string("{\"t\":\"ping\"}")) { _ in }
            }
        }
    }

    private func receiveNext(_ task: URLSessionWebSocketTask, generation current: Int) {
        task.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, current == self.generation else { return }
                switch result {
                case .success(.string(let text)):
                    if !self.closed { self.receive(text) }
                    self.receiveNext(task, generation: current)
                case .success(.data(let data)):
                    if !self.closed, let text = String(data: data, encoding: .utf8) { self.receive(text) }
                    self.receiveNext(task, generation: current)
                case .success:
                    self.receiveNext(task, generation: current)
                case .failure:
                    self.dropped(closeCode: task.closeCode.rawValue)
                }
            }
        }
    }

    private func receive(_ text: String) {
        guard let data = text.data(using: .utf8),
              let frame = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = frame["t"] as? String else { return }
        switch type {
        case "welcome":
            welcomed = true
            localPeerID = frame["you"] as? String
            token = frame["token"] as? String
            seats = (frame["seats"] as? Int) ?? seats
            reconnectAttempts = 0
            let queued = outbox
            outbox.removeAll(); outboxCharacters = 0
            for text in queued { task?.send(.string(text)) { _ in } }
            updateRoster(frame["peers"], full: frame["full"] as? Bool == true)
            onConnectionChanged?(true)
        case "roster":
            updateRoster(frame["peers"], full: frame["full"] as? Bool == true)
        case "msg":
            guard let from = frame["from"] as? String, let payload = frame["d"] as? String else { return }
            guard let part = frame["p"] as? [String: Any] else {
                onPacket?(Data(payload.utf8), from); return
            }
            guard let id = part["id"] as? String, let index = part["i"] as? Int, let count = part["n"] as? Int,
                  (1...64).contains(count), (0..<count).contains(index) else { return }
            let key = "\(from)/\(id)"
            var pieces = parts[key] ?? Array(repeating: nil, count: count)
            guard pieces.count == count else { parts[key] = nil; return }
            pieces[index] = payload
            if pieces.allSatisfy({ $0 != nil }) {
                parts[key] = nil
                onPacket?(Data(pieces.compactMap { $0 }.joined().utf8), from)
            } else {
                parts[key] = pieces
            }
        case "gone":
            if let id = frame["id"] as? String { onDisconnect?(id) }
        case "error":
            closed = true
            onError?((frame["message"] as? String) ?? "The table service closed the connection.")
        default:
            break
        }
    }

    private func updateRoster(_ value: Any?, full: Bool) {
        if let rows = value as? [[String: Any]] {
            peers = rows.compactMap { row in
                guard let id = row["id"] as? String else { return nil }
                return RelayPeer(id: id, name: (row["name"] as? String) ?? "Player", connected: row["connected"] as? Bool == true)
            }
        }
        isFull = full
        onRoster?(peers, full)
    }

    /// A dropped socket reclaims the seat with its resume token, with backoff, for about a minute.
    private func dropped(closeCode: Int) {
        task = nil; welcomed = false
        guard !closed else { return }
        guard let resume = token, closeCode != 4400 else {
            closed = true; onError?("Could not connect to the table."); return
        }
        onConnectionChanged?(false)
        guard reconnectAttempts < 12 else { closed = true; onError?("Lost the connection to the table."); return }
        let delay = min(8.0, 0.5 * pow(2.0, Double(min(reconnectAttempts, 4))))
        reconnectAttempts += 1
        let current = generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !self.closed, self.task == nil, self.generation == current else { return }
            self.open(hostKey: nil, resume: resume)
        }
    }

    func send(_ data: Data, to authenticatedPeerID: String) throws {
        guard !closed else { throw EngineError.invalidMessage("The table connection is closed.") }
        guard let text = String(data: data, encoding: .utf8) else { throw EngineError.invalidMessage("Invalid table packet.") }
        let characters = Array(text)
        if characters.count <= Self.partCharacters {
            try write(try frame(to: authenticatedPeerID, text: text, part: nil))
            return
        }
        let count = (characters.count + Self.partCharacters - 1) / Self.partCharacters
        guard count <= 64 else { throw EngineError.messageTooLarge }
        let id = UUID().uuidString
        for index in 0..<count {
            let slice = String(characters[(index * Self.partCharacters)..<min(characters.count, (index + 1) * Self.partCharacters)])
            try write(try frame(to: authenticatedPeerID, text: slice, part: ["id": id, "i": index, "n": count]))
        }
    }

    /// Sends now, or holds the frame until the relay returns this phone's seat.
    private func write(_ frame: String) throws {
        if let task, welcomed { task.send(.string(frame)) { _ in }; return }
        guard outbox.count < 512, outboxCharacters + frame.count <= 8_000_000 else {
            throw EngineError.invalidMessage("Lost the connection to the table.")
        }
        outbox.append(frame); outboxCharacters += frame.count
    }

    private func frame(to peer: String, text: String, part: [String: Any]?) throws -> String {
        var value: [String: Any] = ["t": "send", "to": peer, "d": text]
        if let part { value["p"] = part }
        let data = try JSONSerialization.data(withJSONObject: value)
        return String(decoding: data, as: UTF8.self)
    }

    /// Leaves the table for good; the other phones are told at once.
    func disconnect() {
        guard !closed || task != nil else { return }
        closed = true
        generation += 1
        pingTask?.cancel(); pingTask = nil
        if let task {
            task.send(.string("{\"t\":\"bye\"}")) { _ in }
            task.cancel(with: .normalClosure, reason: nil)
        }
        task = nil; welcomed = false; outbox.removeAll(); outboxCharacters = 0
        onPacket = nil; onRoster = nil; onDisconnect = nil; onError = nil; onPacketRejected = nil; onConnectionChanged = nil
    }
}
