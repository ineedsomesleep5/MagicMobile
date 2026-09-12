import Foundation
import MagicMobileOnDevice

/// Retains the native handle until the engine confirms all workers have stopped.
@MainActor
final class OnDeviceRuntimeManager {
    private var transport: NativeEngineTransport?
    private var changing = false
    private var destroyedMatchID: String?
    private(set) var capabilities: MagicMobileOnDevice.JSONValue?
    var isOpen: Bool { transport != nil }

    func makeClient(identity: BuildIdentity) async throws -> EngineClient {
        guard !changing, transport == nil else { throw EngineError.invalidMessage("Close the previous native runtime first") }
        changing = true; defer { changing = false }
        #if XMAGE_NATIVE_LINKED
        guard mm_install_graal_backend() == MM_OK else {
            throw EngineError.invalidMessage("Could not register the compiled XMage library")
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
            // A failed close deliberately retains the handle so the UI can retry cleanup.
            do { try await native.close(); transport = nil } catch { throw error }
            throw error
        }
        #endif
    }

    func close() async throws {
        guard !changing else { throw EngineError.invalidMessage("Native runtime is still processing an operation") }
        guard let transport else { return }
        changing = true; defer { changing = false }
        try await transport.close()
        self.transport = nil; capabilities = nil; destroyedMatchID = nil
    }

    func closeMatch(client: EngineClient, matchID: String) async throws {
        guard isOpen else { return }
        guard destroyedMatchID == nil || destroyedMatchID == matchID else { throw EngineError.incompatibleBuild }
        if destroyedMatchID == nil {
            try await client.destroy(matchID: matchID)
            destroyedMatchID = matchID
        }
        // If isolate shutdown fails after match destruction, a retry must not destroy twice.
        try await close()
    }

    static func validate(_ value: MagicMobileOnDevice.JSONValue, identity: BuildIdentity) throws {
        guard value["engine"]?.string == "xmage", value["execution"]?.string == "native-aot",
              value["protocol"]?.integer == Int64(identity.protocolVersion),
              value["upstream"]?.string == identity.upstreamCommit,
              value["catalogueHash"]?.string == identity.catalogueHash,
              value["maxPlayers"]?.integer == 4 else { throw EngineError.incompatibleBuild }
    }
}
