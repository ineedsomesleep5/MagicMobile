import Foundation
import Observation
import MagicMobileOnDevice

@MainActor @Observable
final class EngineLabModel {
    private(set) var capabilities: JSONValue?
    private(set) var matchID: String?
    private(set) var seats: [String] = []
    private(set) var poll: MatchPoll?
    private(set) var isWorking = false
    private(set) var isForeground = true
    private(set) var configuration: JSONValue?
    private(set) var status = "Checking the embedded native library…"
    private(set) var error: String?
    var selectedSeat = ""
    private var client: EngineClient?
    private var pollTask: Task<Void, Never>?
    private var connected = false

    func connect() async {
        guard !connected else { return }; connected = true
        do {
            #if XMAGE_NATIVE_LINKED
            guard mm_install_graal_backend() == MM_OK else {
                throw EngineError.invalidMessage("Could not install the compiled XMage backend")
            }
            #endif
            let transport = try NativeEngineTransport()
            let client = EngineClient(transport: transport)
            self.capabilities = try await client.capabilities()
            self.client = client
            status = "Embedded engine loaded. Import a resolved match configuration to test it."
        } catch {
            self.error = String(describing: error)
            status = "Native XMage is not available in this build. No simulator or remote engine is substituted."
        }
    }
    func importConfiguration(from url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= WireLimits.maxJSONBytes else { throw EngineError.messageTooLarge }
            let value = try JSONValue.decode(Data(contentsOf: url))
            guard let rows = value["seats"]?.array, (2...4).contains(rows.count) else {
                throw EngineError.invalidMessage("Expected a match configuration with 2–4 seats")
            }
            configuration = value; error = nil
            status = "Configuration loaded; the engine will validate the actual decks."
        } catch { self.error = String(describing: error) }
    }
    func start() async {
        guard let client, let configuration, matchID == nil, !isWorking, isForeground else { return }
        isWorking = true; defer { isWorking = false }
        do {
            let result = try await client.create(configuration: configuration)
            guard let id = result["matchId"]?.string, let rows = result["seats"]?.array else {
                throw EngineError.invalidMessage("Malformed create response")
            }
            matchID = id; seats = rows.compactMap(\.string); selectedSeat = seats.first ?? ""
            error = nil; status = "Local engine running. This is a development inspection client."
            beginPolling()
        } catch { self.error = String(describing: error) }
    }
    func chooseSeat(_ seat: String) {
        guard seats.contains(seat) else { return }
        selectedSeat = seat; poll = nil; beginPolling()
    }
    func setForeground(_ value: Bool) {
        isForeground = value
        if value { beginPolling() } else { pollTask?.cancel(); pollTask = nil }
    }
    private func beginPolling() {
        pollTask?.cancel()
        guard let client, let matchID, !selectedSeat.isEmpty, isForeground else { return }
        let seat = selectedSeat
        pollTask = Task { [weak self] in
            var cursor: Int64 = 0
            while !Task.isCancelled {
                do {
                    let result = try await client.poll(matchID: matchID, seatID: seat, after: cursor)
                    guard !Task.isCancelled, let self, self.matchID == matchID, self.selectedSeat == seat else { return }
                    self.poll = result; cursor = result.revision
                    if result.phase == "ended" || result.phase == "failed" || result.phase == "closed" {
                        self.status = "Match status: \(result.phase)"; return
                    }
                    try await Task.sleep(for: .milliseconds(250))
                } catch is CancellationError { return }
                catch { self?.error = String(describing: error); return }
            }
        }
    }
    func answer(_ kind: String, value: JSONValue, prompt: EnginePrompt) async {
        guard let client, let matchID, !isWorking, isForeground, !prompt.submitted else { return }
        let seat = selectedSeat
        isWorking = true; defer { isWorking = false }
        do {
            _ = try await client.respond(matchID: matchID, seatID: seat, prompt: prompt,
                                         answer: EnginePrompt.answer(kind, value))
            error = nil
        } catch { self.error = String(describing: error) }
        // Snapshot polling is authoritative; no guessed battlefield updates.
    }
    func discard() async {
        guard let client, let matchID, !isWorking else { return }
        isWorking = true; defer { isWorking = false }
        pollTask?.cancel(); pollTask = nil
        do {
            try await client.destroy(matchID: matchID)
            self.matchID = nil; seats = []; poll = nil; selectedSeat = ""
            status = "Match discarded"; error = nil
        } catch { self.error = String(describing: error) }
    }
    var canStart: Bool { client != nil && configuration != nil && matchID == nil && !isWorking && isForeground }
}
