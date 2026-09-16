import Foundation
import Combine
import MagicMobileOnDevice

/// Kept alive for cleanup retries. Never destroys a live game's isolate, never
/// validates by starting a sacrificial game, and never calls a remote host.
@MainActor
final class DeckStudioValidationService: ObservableObject {
    static let shared = DeckStudioValidationService()
    @Published private(set) var busy = false
    @Published private(set) var cleanupRequired = false
    private let runtime = OnDeviceRuntimeManager()
    static var appBuild: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development" }
    func validate(_ deck: MagicMobileOnDevice.JSONValue, resolver: OnDeviceDeckResolver) async throws -> DeckStudioValidationReceipt {
        guard !busy, !cleanupRequired, !runtime.isOpen else { throw EngineError.invalidMessage("Wait for validation or retry its cleanup before checking another deck") }
        busy = true; defer { busy = false }
        let identity = BuildIdentity(upstreamCommit: resolver.upstreamCommit, catalogueHash: resolver.catalogueHash)
        let request = try deck.encoded()
        let result: Result<DeckStudioValidationReceipt, Error>
        do {
            try Task.checkCancellation()
            let client = try await runtime.makeClient(identity: identity, observePlaytests: false)
            guard runtime.capabilities?["deckValidation"]?.bool == true else {
                throw EngineError.invalidMessage("This installed engine does not expose standalone deck validation. A fresh native-engine build is required; the draft is not marked legal.")
            }
            try Task.checkCancellation()
            do {
                let report = try await client.call("validateDeck", fields: ["deck": deck])
                result = .success(try .success(result: report.encoded(), request: request,
                    upstream: resolver.upstreamCommit, catalogue: resolver.catalogueHash, appBuild: Self.appBuild))
            } catch EngineError.rejectionDetails(let code, let message, let details) where code == "invalid_deck" {
                result = .success(try .rejection(details: details.encoded(), message: message, request: request,
                    upstream: resolver.upstreamCommit, catalogue: resolver.catalogueHash, appBuild: Self.appBuild))
            }
        } catch { result = .failure(error) }
        do { try await runtime.close(); cleanupRequired = false }
        catch {
            cleanupRequired = runtime.isOpen
            throw EngineError.invalidMessage("Validation cleanup has not completed. Retry cleanup before playing or validating again. The engine handle is still safely retained.")
        }
        try Task.checkCancellation()
        return try result.get()
    }
    func retryCleanup() async throws {
        guard !busy else { throw EngineError.invalidMessage("Wait for the current validation operation") }
        busy = true; defer { busy = false }
        try await runtime.close()
        cleanupRequired = runtime.isOpen
    }
}
