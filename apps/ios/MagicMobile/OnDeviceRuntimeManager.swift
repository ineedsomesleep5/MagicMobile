import Foundation
import MagicMobileOnDevice

/// Retains the native handle until the engine confirms all workers have stopped.
@MainActor
final class OnDeviceRuntimeManager {
    private static let registration = OnDeviceBackendRegistration()
    // Validation and gameplay must not allocate competing full native engines.
    // The owner is released only after confirmed isolate closure.
    private static var owner: UUID?
    private let ownerID = UUID()
    private var transport: NativeEngineTransport?
    private var recording: DeckStudioRecordingTransport?
    private var changing = false
    private var destroyedMatchID: String?
    private var startupDiagnostic: String?
    private(set) var capabilities: MagicMobileOnDevice.JSONValue?
    var isOpen: Bool { transport != nil }
    func diagnosticReport() async throws -> String? {
        if let startupDiagnostic { return startupDiagnostic }
        guard let transport, !changing else { return startupDiagnostic }
        let value = try await EngineClient(transport: transport).call("diagnostics")
        return value["report"]?.string ?? startupDiagnostic
    }
    func clearDiagnostics() async throws {
        guard !changing else { throw EngineError.invalidMessage("Wait for the native operation to finish") }
        if let transport { _ = try await EngineClient(transport: transport).call("clearDiagnostics") }
        startupDiagnostic = nil
    }
    func makeClient(identity: BuildIdentity, observePlaytests: Bool = true) async throws -> EngineClient {
        guard !changing, transport == nil else { throw EngineError.invalidMessage("Close the previous native runtime first") }
        guard Self.owner == nil else { throw EngineError.invalidMessage("Finish the active game or retry pending validation cleanup before opening another engine") }
        changing = true; defer { changing = false }
        startupDiagnostic = nil
        #if XMAGE_NATIVE_LINKED
        try Self.registration.ensureInstalled {
            guard mm_install_graal_backend() == MM_OK else { throw EngineError.invalidMessage("Could not register the compiled XMage library") }
        }
        #else
        throw EngineError.nativeEngineNotLinked
        #endif
        #if XMAGE_NATIVE_LINKED
        Self.owner = ownerID
        defer { if transport == nil, Self.owner == ownerID { Self.owner = nil } }
        let native = try await Task.detached(priority: .userInitiated) { try NativeEngineTransport() }.value
        transport = native
        let client: EngineClient
        if observePlaytests {
            let observer = DeckStudioRecordingTransport(base: native)
            recording = observer
            client = EngineClient(transport: observer)
        } else { client = EngineClient(transport: native) }
        do {
            let capabilities = try await client.capabilities()
            try Self.validate(capabilities, identity: identity)
            self.capabilities = capabilities
            return client
        } catch {
            if let report = try? await client.call("diagnostics")["report"]?.string { startupDiagnostic = String(report.prefix(16_384)) }
            do { try await native.close(); transport = nil; recording = nil } catch { /* Retain ownership for retry. */ }
            throw error
        }
        #endif
    }
    func create(client: EngineClient, configuration: MagicMobileOnDevice.JSONValue) async throws -> MagicMobileOnDevice.JSONValue {
        guard !changing else { throw EngineError.invalidMessage("Native runtime is still processing an operation") }
        changing = true; defer { changing = false }
        do { return try await client.create(configuration: configuration) }
        catch {
            if let report = try? await client.call("diagnostics")["report"]?.string { startupDiagnostic = String(report.prefix(16_384)) }
            else { startupDiagnostic = "[local-engine-incident] create\nOccurred: \(ISO8601DateFormatter().string(from: Date()))\n\(error.localizedDescription.prefix(12_000))" }
            try? await closeTransport()
            throw error
        }
    }
    func close() async throws {
        guard !changing else { throw EngineError.invalidMessage("Native runtime is still processing an operation") }
        changing = true; defer { changing = false }
        try await closeTransport()
    }
    private func closeTransport() async throws {
        guard let transport else { return }
        try await transport.close()
        await recording?.runtimeClosed()
        self.transport = nil; recording = nil; capabilities = nil; destroyedMatchID = nil
        if Self.owner == ownerID { Self.owner = nil }
    }
    func closeMatch(client: EngineClient, matchID: String) async throws {
        guard !changing else { throw EngineError.invalidMessage("Native runtime is still processing an operation") }
        guard isOpen else { return }
        guard destroyedMatchID == nil || destroyedMatchID == matchID else { throw EngineError.incompatibleBuild }
        changing = true; defer { changing = false }
        if destroyedMatchID == nil { try await client.destroy(matchID: matchID); destroyedMatchID = matchID }
        try await closeTransport()
    }
    static func validate(_ value: MagicMobileOnDevice.JSONValue, identity: BuildIdentity) throws {
        guard value["engine"]?.string == "xmage", value["execution"]?.string == "native-aot",
              value["protocol"]?.integer == Int64(identity.protocolVersion),
              value["upstream"]?.string == identity.upstreamCommit,
              value["catalogueHash"]?.string == identity.catalogueHash,
              value["maxPlayers"]?.integer == 4 else { throw EngineError.incompatibleBuild }
    }
}
