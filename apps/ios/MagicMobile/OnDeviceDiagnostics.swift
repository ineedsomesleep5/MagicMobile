import Foundation
import Combine

/// Latest local engine failure only. No snapshots, action payloads, networking, or automatic sharing.
@MainActor
final class OnDeviceDiagnostics: ObservableObject {
    static let maxBytes = 65_536
    @Published private(set) var report: String?
    private var persistedReport: String?
    @Published private(set) var isHistorical = false
    @Published var errorMessage: String?
    private let directory: URL
    private var captureGeneration = 0
    private var clearing = false
    private var file: URL { directory.appendingPathComponent("latest-engine-failure.txt") }

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MagicMobile/Diagnostics", isDirectory: true)
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= Self.maxBytes else { throw CocoaError(.fileReadTooLarge) }
                report = try String(contentsOf: file, encoding: .utf8)
                persistedReport = report
                isHistorical = true
            }
        } catch { errorMessage = "Could not load the saved engine report: \(error.localizedDescription)" }
    }

    func beginAttempt() {
        captureGeneration += 1
        if report != nil { isHistorical = true }
    }

    func save(engineReport: String, status: String) throws {
        // Reopening the sheet must not date an existing incident as a new failure.
        if let report, persistedReport == report, let range = report.range(of: "\n\n"),
           engineReport.hasPrefix(String(report[range.upperBound...])) { return }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let text = """
        MagicMobile local engine diagnostic
        App: \(version) (\(build))
        OS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Captured: \(ISO8601DateFormatter().string(from: Date()))
        Status: \(status.prefix(200))
        Private: error text may contain card information. Share only by explicit choice.

        \(String(decoding: engineReport.utf8.prefix(Self.maxBytes), as: UTF8.self))
        """
        var bytes = Data(text.utf8.prefix(Self.maxBytes))
        // A byte limit may land inside a Unicode scalar; trim only that incomplete tail.
        while String(data: bytes, encoding: .utf8) == nil { bytes.removeLast() }
        report = String(data: bytes, encoding: .utf8)
        isHistorical = false
        errorMessage = nil
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            var excludedDirectory = directory
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try excludedDirectory.setResourceValues(values)
            #if os(iOS)
            try bytes.write(to: file, options: [.atomic, .completeFileProtection])
            #else
            try bytes.write(to: file, options: .atomic)
            #endif
            persistedReport = report
        } catch {
            errorMessage = "Report is available to share now, but could not be saved on this device: \(error.localizedDescription)"
            throw error
        }
    }

    func clear() throws {
        captureGeneration += 1
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        report = nil; persistedReport = nil; errorMessage = nil; isHistorical = false
    }

    func capture(status: String, read: () async throws -> String?) async {
        guard !clearing else { return }
        let generation = captureGeneration
        do {
            guard let report = try await read(), generation == captureGeneration else { return }
            try save(engineReport: report, status: status)
        } catch {
            guard generation == captureGeneration else { return }
            if errorMessage == nil { errorMessage = "Could not capture the local engine report: \(error.localizedDescription)" }
        }
    }

    func clear(engine: () async throws -> Void) async throws {
        guard !clearing else { return }
        captureGeneration += 1; clearing = true
        defer { clearing = false }
        try await engine()
        try clear()
    }
}
