import XCTest
@testable import MagicMobile

/// Tests the production one-time registration policy, not a running native engine.
final class OnDeviceBackendRegistrationTests: XCTestCase {
    private enum InstallationFailure: Error { case failed }

    @MainActor
    func testFirstInstallationRunsOnce() async throws {
        let registration = OnDeviceBackendRegistration()
        var calls = 0
        registration.ensureInstalled { calls += 1 }
        XCTAssertEqual(calls, 1)
    }

    @MainActor
    func testLaterGamesDoNotReplaceInstalledBackend() async throws {
        let registration = OnDeviceBackendRegistration()
        var calls = 0
        registration.ensureInstalled { calls += 1 }
        for _ in 0..<10 {
            try registration.ensureInstalled {
                calls += 1
                // The real C registry also rejects installing twice.
                throw InstallationFailure.failed
            }
        }
        XCTAssertEqual(calls, 1)
    }

    @MainActor
    func testFailedFirstInstallationCanBeRetried() async throws {
        let registration = OnDeviceBackendRegistration()
        var calls = 0
        do {
            try registration.ensureInstalled { calls += 1; throw InstallationFailure.failed }
            XCTFail("Expected the installation error")
        } catch InstallationFailure.failed { }
        registration.ensureInstalled { calls += 1 }
        registration.ensureInstalled { calls += 1 }
        XCTAssertEqual(calls, 2)
    }

    @MainActor
    func testRepeatedFailureDoesNotPretendBackendIsInstalled() async throws {
        let registration = OnDeviceBackendRegistration()
        var calls = 0
        for _ in 0..<3 {
            do {
                try registration.ensureInstalled { calls += 1; throw InstallationFailure.failed }
                XCTFail("Failed installer must remain retryable")
            } catch InstallationFailure.failed { }
        }
        XCTAssertEqual(calls, 3)
    }
}
