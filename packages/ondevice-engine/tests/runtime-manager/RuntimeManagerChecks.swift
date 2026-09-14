// TEST-ONLY isolated process. Actual production manager/client/C boundary,
// with a deterministic backend and a separately gated destroy transport.
// Does not execute Graal, Java, XMage, GameKit or the iOS application.
import Foundation
import MagicMobileOnDevice

private actor Gate {
    private var waiting: CheckedContinuation<Void, Never>?
    private var entered = false
    func wait() async { entered = true; await withCheckedContinuation { waiting = $0 } }
    func waitUntilEntered() async throws {
        for _ in 0..<400 {
            if entered { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw EngineError.invalidMessage("Runtime fixture did not reach its barrier")
    }
    func release() { waiting?.resume(); waiting = nil }
}

private actor DestroyFixture: EngineTransport {
    private var count = 0
    private let gate: Gate?
    init(gate: Gate? = nil) { self.gate = gate }
    func request(_ data: Data) async throws -> Data {
        guard try JSONValue.decode(data)["op"]?.string == "destroy" else {
            throw EngineError.invalidMessage("Only test match destruction is supported")
        }
        count += 1
        if count == 1, let gate { await gate.wait() }
        return try JSONValue.object([
            "protocol": .integer(1), "ok": .bool(true), "result": .object(["destroyed": .bool(true)])
        ]).encoded()
    }
    func requests() -> Int { count }
}

@main private struct RuntimeManagerChecks {
    @MainActor private static var checks = 0
    @MainActor private static var failures = 0
    @MainActor private static func check(_ value: Bool, _ message: String) {
        checks += 1
        if !value { failures += 1; print("FAIL: \(message)") }
    }
    @MainActor static func main() async throws {
        let identity = BuildIdentity(upstreamCommit: "fixture-upstream", catalogueHash: "fixture-catalogue")
        // The process-wide registration is reused by every runtime below, as in production.
        for busy in [false, true] {
            fixture_mode(1)
            fixture_busy_closes(busy ? 1 : 0)
            let runtime = OnDeviceRuntimeManager()
            do {
                _ = try await runtime.makeClient(identity: identity)
                check(false, "failing startup must throw")
            } catch {
                check(!error.localizedDescription.contains("PRIVATE"), "startup error remains sanitized")
            }
            check(runtime.isOpen == busy, "only unconfirmed startup cleanup retains native ownership")
            check(try await runtime.diagnosticReport() == "PRIVATE-startup-fixture", "startup report survives failed bootstrap")
            try await runtime.close()
            check(!runtime.isOpen, "startup cleanup retry terminates retained runtime")
            check(try await runtime.diagnosticReport() == "PRIVATE-startup-fixture", "startup report survives successful teardown")
            try await runtime.clearDiagnostics()
            check(try await runtime.diagnosticReport() == nil, "explicit deletion removes cached startup report")
            check(fixture_close_calls() == (busy ? 2 : 1), "startup cleanup closes only as many times as necessary")
        }
        do {
            fixture_mode(0)
            let runtime = OnDeviceRuntimeManager()
            _ = try await runtime.makeClient(identity: identity)
            let gate = Gate()
            // A separate transport gives deterministic suspension without blocking a native thread.
            let blocked = DestroyFixture(gate: gate)
            let client = EngineClient(transport: blocked)
            let first = Task { try await runtime.closeMatch(client: client, matchID: "m") }
            do { try await gate.waitUntilEntered() }
            catch { await gate.release(); _ = try? await first.value; throw error }
            do {
                try await runtime.closeMatch(client: client, matchID: "m")
                check(false, "concurrent match close must be rejected")
            } catch { check(true, "concurrent match close rejected") }
            do {
                try await runtime.close()
                check(false, "direct close cannot overtake match destruction")
            } catch { check(true, "direct close blocked while destruction is suspended") }
            do {
                _ = try await runtime.makeClient(identity: identity)
                check(false, "new runtime cannot replace an in-flight close")
            } catch { check(true, "new runtime blocked during teardown") }
            check(await blocked.requests() == 1 && fixture_close_calls() == 0, "one destroy and no premature native close")
            await gate.release()
            try await first.value
            check(!runtime.isOpen && runtime.capabilities == nil, "completed teardown clears handle and capabilities")
            try await runtime.close()
            check(fixture_close_calls() == 1, "successful close is idempotent")
        }
        do {
            fixture_mode(0)
            let runtime = OnDeviceRuntimeManager()
            _ = try await runtime.makeClient(identity: identity)
            fixture_busy_closes(1)
            let transport = DestroyFixture(), client = EngineClient(transport: transport)
            do {
                try await runtime.closeMatch(client: client, matchID: "m")
                check(false, "busy close must throw")
            } catch { check(runtime.isOpen, "busy close retains native ownership") }
            do {
                try await runtime.closeMatch(client: client, matchID: "other")
                check(false, "retry must retain the destroyed match identity")
            } catch { check(true, "different match cannot reuse cleanup transaction") }
            check(await transport.requests() == 1, "mismatched cleanup did not destroy another match")
            try await runtime.closeMatch(client: client, matchID: "m")
            check(await transport.requests() == 1, "retry never destroys an already destroyed match")
            check(!runtime.isOpen && fixture_close_calls() == 2, "retry closes retained native handle")
            _ = try await runtime.makeClient(identity: identity)
            check(runtime.isOpen && runtime.capabilities != nil, "new runtime reuses process registration after cleanup")
            try await runtime.close()
            check(fixture_close_calls() == 3, "replacement runtime cleaned up exactly once")
        }
        print("\(failures == 0 ? "PASS" : "FAIL"): \(checks) production runtime-manager assertions; \(failures) failures. Test-only native-ABI fixtures, NOT XMage/iPhone acceptance.")
        if failures != 0 { exit(1) }
    }
}
