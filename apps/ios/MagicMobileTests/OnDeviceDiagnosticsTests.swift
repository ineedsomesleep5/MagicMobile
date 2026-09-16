import Foundation
import XCTest
@testable import MagicMobile

@MainActor
final class OnDeviceDiagnosticsTests: XCTestCase {
    func testRepeatedCapturePreservesTimestampAndHistoricalIdentity() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OnDeviceDiagnostics(directory: directory)
        let incident = "[local-engine-incident] invalid_deck\nOccurred: 2026-09-15T01:02:03Z\nExact validator issue"
        try store.save(engineReport: incident, status: "First failure")
        XCTAssertFalse(store.isHistorical)
        let original = store.report
        store.beginAttempt()
        XCTAssertTrue(store.isHistorical)
        await store.capture(status: "Different status") { incident }
        XCTAssertEqual(store.report, original)
        let reopened = OnDeviceDiagnostics(directory: directory)
        XCTAssertTrue(reopened.isHistorical)
        await reopened.capture(status: "Reopened sheet") { incident }
        XCTAssertEqual(reopened.report, original)
        XCTAssertTrue(reopened.isHistorical)
        try reopened.save(engineReport: "New incident", status: "New failure")
        XCTAssertFalse(reopened.isHistorical)
    }
    func testReportSurvivesRestartReplacesOldReportAndDeletes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OnDeviceDiagnostics(directory: directory)
        XCTAssertNil(store.report)
        try store.save(engineReport: "private first failure", status: "Game stopped")
        XCTAssertTrue(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        let reopened = OnDeviceDiagnostics(directory: directory)
        XCTAssertTrue(reopened.report?.contains("private first failure") == true)
        try reopened.save(engineReport: "second failure", status: "Game stopped")
        XCTAssertFalse(reopened.report?.contains("private first failure") == true)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1)
        try reopened.clear()
        XCTAssertNil(reopened.report)
        XCTAssertNil(OnDeviceDiagnostics(directory: directory).report)
    }

    func testOversizedUnicodeReportIsBoundedAndReadable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OnDeviceDiagnostics(directory: directory)
        try store.save(engineReport: String(repeating: "🦊", count: 100_000), status: "Game stopped")
        let report = try XCTUnwrap(store.report)
        XCTAssertLessThanOrEqual(report.utf8.count, OnDeviceDiagnostics.maxBytes)
        XCTAssertFalse(report.contains("�"))
        XCTAssertEqual(OnDeviceDiagnostics(directory: directory).report, report)
    }

    func testFailedSaveKeepsReportAvailableForExplicitSharing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("blocking-file".utf8).write(to: directory)
        let store = OnDeviceDiagnostics(directory: directory)
        XCTAssertThrowsError(try store.save(engineReport: "failure to preserve", status: "Game stopped"))
        XCTAssertTrue(store.report?.contains("failure to preserve") == true)
        try FileManager.default.removeItem(at: directory)
        try store.save(engineReport: "failure to preserve", status: "Game stopped")
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(OnDeviceDiagnostics(directory: directory).report, store.report)
    }

    func testLateCaptureCannotRestoreDeletedReport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OnDeviceDiagnostics(directory: directory)
        await store.capture(status: "Game stopped") {
            try await store.clear(engine: {})
            return "stale in-flight failure"
        }
        XCTAssertNil(store.report)
        XCTAssertNil(OnDeviceDiagnostics(directory: directory).report)
    }

    func testEngineClearFailureRetainsSavedReport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OnDeviceDiagnostics(directory: directory)
        try store.save(engineReport: "retain this report", status: "Game stopped")
        do {
            try await store.clear(engine: { throw CocoaError(.fileWriteUnknown) })
            XCTFail("Expected engine clear failure")
        } catch {}
        XCTAssertTrue(store.report?.contains("retain this report") == true)
        XCTAssertEqual(OnDeviceDiagnostics(directory: directory).report, store.report)
    }

    func testUnreadableReportCanBeDeleted() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(repeating: 65, count: OnDeviceDiagnostics.maxBytes + 1)
            .write(to: directory.appendingPathComponent("latest-engine-failure.txt"))
        let store = OnDeviceDiagnostics(directory: directory)
        XCTAssertNil(store.report)
        XCTAssertNotNil(store.errorMessage)
        try store.clear()
        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
}
