// TEST-ONLY process: installing this fixture separately preserves the Swift suite's
// native-library-missing test. No native library, Java, or XMage executes here.
import Foundation
import CMagicEngine

private enum Fixture {
    // Calls are serialized by the production transport actor; assertions run after each await.
    nonisolated(unsafe) static var attempts = 0
    nonisolated(unsafe) static var destroyed = 0
    static func install() {
        let backend = mm_backend(abi_version: MM_BACKEND_ABI_VERSION, create: {
            let state = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
            state.initialize(to: 1) // live worker
            return UnsafeMutableRawPointer(state)
        }, request: { state, input, size, length in
            if input!.pointee == 48 { state!.assumingMemoryBound(to: UInt8.self).pointee = 0 }
            let result = UnsafeMutablePointer<CChar>.allocate(capacity: size)
            result.initialize(from: input!, count: size)
            length!.pointee = size
            return result
        }, free_response: { _, response in response!.deallocate() }, destroy: { state in
            Fixture.attempts += 1
            let worker = state!.assumingMemoryBound(to: UInt8.self)
            if worker.pointee != 0 { return MM_BUSY }
            worker.deallocate(); Fixture.destroyed += 1
            return MM_OK
        })
        precondition(mm_install_backend(backend) == MM_OK)
    }
}

@main private struct NativeCloseTests {
    static func retryClose() async throws {
        let transport = try NativeEngineTransport()
        let request = Data("{}".utf8)
        let initial = try await transport.request(request)
        precondition(initial == request)
        do {
            try await transport.close()
            preconditionFailure("busy close must throw")
        } catch EngineError.runtimeFailure(let status) {
            precondition(status == Int32(MM_BUSY.rawValue))
        }
        precondition(Fixture.destroyed == 0)
        let retained = try await transport.request(request)
        precondition(retained == request)
        _ = try await transport.request(Data("0".utf8)) // fixture worker terminates
        try await transport.close()
        try await transport.close() // idempotent; no second free
        do {
            _ = try await transport.request(request)
            preconditionFailure("closed transport must reject requests")
        } catch EngineError.invalidMessage(let message) {
            precondition(message == "Native engine transport is closed")
        }
    }
    static func abandonBusyTransport() throws {
        let transport = try NativeEngineTransport()
        withExtendedLifetime(transport) {}
        // Deinit must attempt shutdown but may not free this busy runtime.
    }
    static func main() async throws {
        Fixture.install()
        try await retryClose()
        precondition(Fixture.attempts == 2 && Fixture.destroyed == 1)
        try abandonBusyTransport()
        precondition(Fixture.attempts == 3 && Fixture.destroyed == 1)
        print("PASS: Swift actor busy close, retained request, retry, idempotence, closed request rejection, safe deinit retention (fixture only)")
    }
}
