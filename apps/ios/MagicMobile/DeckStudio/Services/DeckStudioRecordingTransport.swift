import Foundation
import MagicMobileOnDevice

/// A transparent observer of successful local-native responses. It does not
/// alter requests, replies, retries, errors, or seat routing. Not installed on peers.
actor DeckStudioRecordingTransport: EngineTransport {
    private let base: any EngineTransport
    private let store: DeckStudioPlaytestStore
    private let appBuild: String
    private var admission: DeckStudioPlaytestStore.Admission?
    private var accumulator = DeckStudioPlaytestAccumulator()
    private var lastSaved = Date.distantPast
    init(base: any EngineTransport, store: DeckStudioPlaytestStore = .shared,
         appBuild: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development") {
        self.base = base; self.store = store; self.appBuild = appBuild
    }
    func request(_ data: Data) async throws -> Data {
        let op = DeckStudioJSON.object(data)?["op"] as? String
        if op == "create", admission == nil { admission = await store.admission() }
        let reply = try await base.request(data)
        if let admission, admission.enabled {
            let now = Date()
            if accumulator.observe(request: data, response: reply, enabled: true, appBuild: appBuild, now: now),
               let game = accumulator.game,
               op == "create" || game.end != .inProgress || now.timeIntervalSince(lastSaved) >= 15 {
                _ = await store.record(game, admission: admission)
                lastSaved = now
            }
        }
        return reply
    }
    func runtimeClosed() async {
        guard let admission, let value = accumulator.close(now: Date()) else { return }
        _ = await store.record(value, admission: admission)
    }
}
