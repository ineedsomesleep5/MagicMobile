// TEST ONLY: real production manager/client/C boundary with an explicitly fake
// ABI backend. No XMage, iOS gameplay, network or signed product is executed.
import Foundation
import MagicMobileOnDevice

@main private struct RuntimeLeaseChecks {
    @MainActor private static var checks = 0
    @MainActor private static func check(_ condition: Bool, _ text: String) {
        checks += 1
        if !condition { fatalError("FAIL: \(text)") }
    }
    @MainActor static func main() async throws {
        fixture_mode(0)
        let identity = BuildIdentity(upstreamCommit: "fixture-upstream", catalogueHash: "fixture-catalogue")
        let first = OnDeviceRuntimeManager(), second = OnDeviceRuntimeManager()
        _ = try await first.makeClient(identity: identity, observePlaytests: false)
        do { _ = try await second.makeClient(identity: identity, observePlaytests: false); check(false, "A second full engine must not open") }
        catch { check(first.isOpen && !second.isOpen, "first owner retained, second rejected") }
        try await second.close()
        check(first.isOpen && fixture_close_calls() == 0, "non-owner cleanup cannot close the game")
        fixture_busy_closes(1)
        do { try await first.close(); check(false, "busy close expected") }
        catch { check(first.isOpen, "unconfirmed close retains owner") }
        do { _ = try await second.makeClient(identity: identity); check(false, "lease must stay held during failed cleanup") }
        catch { check(!second.isOpen, "failed cleanup blocks competing allocation") }
        try await first.close()
        check(!first.isOpen && fixture_close_calls() == 2, "cleanup retry releases lease once confirmed")
        _ = try await second.makeClient(identity: identity, observePlaytests: false)
        check(second.isOpen, "validation/game manager can acquire after cleanup")
        try await second.close()
        check(fixture_close_calls() == 3, "second runtime closes once")
        do { _ = try await first.makeClient(identity: BuildIdentity(upstreamCommit: "wrong", catalogueHash: "wrong")); check(false, "identity mismatch expected") }
        catch { check(!first.isOpen, "startup mismatch cleans its isolate") }
        _ = try await second.makeClient(identity: identity)
        check(second.isOpen, "successful startup cleanup did not leak global lease")
        try await second.close()
        print("PASS: \(checks) native runtime ownership assertions. Test-only ABI backend, not native XMage/device acceptance.")
    }
}
