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

    /// A MetricKit diagnostic payload in the shape `MXDiagnosticPayload.jsonRepresentation()` returns.
    static let metricKitPayload = Data("""
    {
      "timeStampBegin": "2026-09-24 00:00:00",
      "timeStampEnd": "2026-09-24 23:59:00",
      "crashDiagnostics": [{
        "version": "1.0.0",
        "diagnosticMetaData": {
          "appVersion": "0.1.1", "appBuildVersion": "19", "osVersion": "iPhone OS 27.0 (24A5300a)",
          "platformArchitecture": "arm64e", "regionFormat": "US", "deviceType": "iPhone17,1", "pid": 4321,
          "bundleIdentifier": "com.calebfeliciano.magicmobile",
          "exceptionType": 1, "exceptionCode": 0, "signal": 11,
          "terminationReason": "Namespace SIGNAL, Code 11 Segmentation fault: 11",
          "virtualMemoryRegionInfo": "0 is not in any region."
        },
        "callStackTree": {
          "callStackPerThread": true,
          "callStacks": [
            {"threadAttributed": false, "callStackRootFrames": [{"binaryName": "libsystem_kernel.dylib", "offsetIntoBinaryTextSegment": 16, "binaryUUID": "11111111-1111-1111-1111-111111111111", "sampleCount": 1}]},
            {"threadAttributed": true, "callStackRootFrames": [{
              "binaryName": "MagicMobile", "offsetIntoBinaryTextSegment": 4660, "binaryUUID": "22222222-2222-2222-2222-222222222222", "sampleCount": 1,
              "subFrames": [{"binaryName": "libswiftCore.dylib", "offsetIntoBinaryTextSegment": 255, "binaryUUID": "33333333-3333-3333-3333-333333333333", "sampleCount": 1}]
            }]}
          ]
        }
      }],
      "hangDiagnostics": [{
        "version": "1.0.0",
        "diagnosticMetaData": {"appVersion": "0.1.1", "appBuildVersion": "19", "osVersion": "iPhone OS 27.0 (24A5300a)", "hangDuration": "3.2 sec", "regionFormat": "US"},
        "callStackTree": {"callStackPerThread": true, "callStacks": [{"threadAttributed": true, "callStackRootFrames": [{"binaryName": "MagicMobile", "offsetIntoBinaryTextSegment": 43981, "sampleCount": 12}]}]}
      }],
      "cpuExceptionDiagnostics": [{"diagnosticMetaData": {"appVersion": "0.1.1"}}]
    }
    """.utf8)

    func testMetricKitCrashAndHangSummariesKeepOnlyTriageFields() throws {
        let entries = OnDeviceSystemReports.entries(fromPayload: Self.metricKitPayload)
        XCTAssertEqual(entries.map(\.kind), ["Crash", "Hang"], "Only crashes and hangs are kept")
        let crash = entries[0].text, hang = entries[1].text
        XCTAssertTrue(crash.hasPrefix("Crash · reported 2026-09-24 00:00:00 – 2026-09-24 23:59:00"))
        XCTAssertTrue(crash.contains("App 0.1.1 (19) · iPhone OS 27.0 (24A5300a) · arm64e"))
        XCTAssertTrue(crash.contains("Exception: EXC_BAD_ACCESS (type 1, code 0) · signal 11 (SIGSEGV)"))
        XCTAssertTrue(crash.contains("Termination: Namespace SIGNAL, Code 11 Segmentation fault: 11"))
        XCTAssertTrue(crash.contains("Crashed thread:\n  0 MagicMobile +0x1234 22222222-2222-2222-2222-222222222222\n  1 libswiftCore.dylib +0xff"))
        XCTAssertFalse(crash.contains("libsystem_kernel"), "Only the attributed thread")
        XCTAssertTrue(hang.hasPrefix("Hang for 3.2 sec · reported"))
        XCTAssertTrue(hang.contains("Main thread:\n  0 MagicMobile +0xabcd"))
        for text in [crash, hang] {
            XCTAssertFalse(text.contains("iPhone17,1"))
            XCTAssertFalse(text.contains("US"))
            XCTAssertFalse(text.contains("4321"))
            XCTAssertFalse(text.contains("com.calebfeliciano"))
        }
        XCTAssertTrue(OnDeviceSystemReports.entries(fromPayload: Data("not json".utf8)).isEmpty)
    }

    func testMetricKitSummariesAreDeduplicatedAndBounded() {
        let entries = (0..<8).map { OnDeviceSystemReports.Entry(kind: "Crash", text: "crash \($0)") }
        var saved = OnDeviceSystemReports.merged([], Array(entries.prefix(2)))
        saved = OnDeviceSystemReports.merged(saved, Array(entries.prefix(2)))
        XCTAssertEqual(saved.map(\.text), ["crash 0", "crash 1"], "A repeated delivery is kept once")
        saved = OnDeviceSystemReports.merged(saved, entries)
        XCTAssertEqual(saved.map(\.text), (3..<8).map { "crash \($0)" }, "Newest \(OnDeviceSystemReports.limit), newest last")
        XCTAssertNil(OnDeviceSystemReports.section([]))
        let section = try? XCTUnwrap(OnDeviceSystemReports.section(saved))
        XCTAssertTrue(section?.hasPrefix("MagicMobile crash and hang reports (5, newest last, from MetricKit on this phone)") == true)
    }

    func testCrashAndHangReportsJoinTheSharedReportAndAreDeleted() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OnDeviceDiagnostics(directory: directory)
        XCTAssertNil(store.report)
        XCTAssertTrue(OnDeviceSystemReports.record(payloads: [Self.metricKitPayload], directory: directory))
        XCTAssertFalse(OnDeviceSystemReports.record(payloads: [Self.metricKitPayload], directory: directory), "Already saved")
        XCTAssertTrue(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        let reopened = OnDeviceDiagnostics(directory: directory)
        let crashOnly = try XCTUnwrap(reopened.report)
        XCTAssertTrue(crashOnly.hasPrefix("MagicMobile crash and hang reports (2"))
        XCTAssertTrue(reopened.isHistorical, "MetricKit reports describe an earlier session")
        try reopened.save(engineReport: "engine failure", status: "Game stopped")
        let combined = try XCTUnwrap(reopened.report)
        XCTAssertTrue(combined.hasPrefix("MagicMobile local engine diagnostic"))
        XCTAssertTrue(combined.contains("engine failure"))
        XCTAssertTrue(combined.hasSuffix(crashOnly), "The export carries the engine report, then crashes and hangs")
        XCTAssertFalse(reopened.isHistorical)
        try reopened.clear()
        XCTAssertNil(reopened.report)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        XCTAssertNil(OnDeviceDiagnostics(directory: directory).report)
    }

    func testOpenStorePicksUpReportsDeliveredAfterLaunch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OnDeviceDiagnostics(directory: directory)
        let other = OnDeviceDiagnostics(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        XCTAssertTrue(OnDeviceSystemReports.record(payloads: [Self.metricKitPayload], directory: directory))
        for _ in 0..<200 where store.report == nil { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(store.report?.contains("EXC_BAD_ACCESS") == true)
        XCTAssertNil(other.report, "Another directory's store is unaffected")
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
