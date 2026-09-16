import Foundation
import MagicMobileOnDevice

/// Retains the native handle until the engine confirms all workers have stopped.
@MainActor
final class OnDeviceRuntimeManager {
    private static let registration = OnDeviceBackendRegistration()
    private var transport: NativeEngineTransport?
    private var changing = false
    private var destroyedMatchID: String?
    // One bounded, local-only report survives a failed startup and isolate teardown.
    private var startupDiagnostic: String?
    private(set) var capabilities: MagicMobileOnDevice.JSONValue?
    var isOpen: Bool { transport != nil }

    // Uses only this phone's native transport, never a multiplayer peer endpoint.
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

    func makeClient(identity: BuildIdentity) async throws -> EngineClient {
        guard !changing, transport == nil else { throw EngineError.invalidMessage("Close the previous native runtime first") }
        changing = true; defer { changing = false }
        startupDiagnostic = nil
        #if XMAGE_NATIVE_LINKED
        try Self.registration.ensureInstalled {
            guard mm_install_graal_backend() == MM_OK else {
                throw EngineError.invalidMessage("Could not register the compiled XMage library")
            }
        }
        #else
        throw EngineError.nativeEngineNotLinked
        #endif
        #if XMAGE_NATIVE_LINKED
        let native = try await Task.detached(priority: .userInitiated) { try NativeEngineTransport() }.value
        transport = native
        let client = EngineClient(transport: native)
        do {
            let capabilities = try await client.capabilities()
            try Self.validate(capabilities, identity: identity)
            self.capabilities = capabilities
            return client
        } catch {
            // Read before closing the isolate, without replacing the original sanitized error.
            // This trusted local endpoint must never be forwarded to multiplayer peers.
            if let report = try? await client.call("diagnostics")["report"]?.string {
                startupDiagnostic = String(report.prefix(16_384))
            }
            // A failed close deliberately retains the handle so the UI can retry cleanup.
            do { try await native.close(); transport = nil } catch { /* Retain ownership for retry. */ }
            throw error
        }
        #endif
    }

    /// Failed creation owns no usable match. Capture locally before releasing the isolate.
    func create(client: EngineClient, configuration: MagicMobileOnDevice.JSONValue) async throws -> MagicMobileOnDevice.JSONValue {
        guard !changing else { throw EngineError.invalidMessage("Native runtime is still processing an operation") }
        changing = true; defer { changing = false }
        do { return try await client.create(configuration: configuration) }
        catch {
            if let report = try? await client.call("diagnostics")["report"]?.string {
                startupDiagnostic = String(report.prefix(16_384))
            } else {
                // Older engines may not capture expected rejections. Preserve a local incident.
                startupDiagnostic = "[local-engine-incident] create\nOccurred: \(ISO8601DateFormatter().string(from: Date()))\n\(error.localizedDescription.prefix(12_000))"
            }
            // A failed close retains the handle for explicit retry; never replace the create error.
            try? await closeTransport()
            throw error
        }
    }

    func close() async throws {
        guard !changing else { throw EngineError.invalidMessage("Native runtime is still processing an operation") }
        changing = true; defer { changing = false }
        try await closeTransport()
    }

    // Caller owns `changing` across every suspension in the entire teardown transaction.
    private func closeTransport() async throws {
        guard let transport else { return }
        try await transport.close()
        self.transport = nil; capabilities = nil; destroyedMatchID = nil
    }

    func closeMatch(client: EngineClient, matchID: String) async throws {
        guard !changing else { throw EngineError.invalidMessage("Native runtime is still processing an operation") }
        guard isOpen else { return }
        guard destroyedMatchID == nil || destroyedMatchID == matchID else { throw EngineError.incompatibleBuild }
        changing = true; defer { changing = false }
        if destroyedMatchID == nil {
            try await client.destroy(matchID: matchID)
            destroyedMatchID = matchID
        }
        // If isolate shutdown fails after match destruction, a retry must not destroy twice.
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
