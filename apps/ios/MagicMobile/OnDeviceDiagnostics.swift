import Foundation
import Combine

/// Latest local engine failure only, plus the app's own crash and hang summaries from MetricKit.
/// No snapshots, action payloads, networking, or automatic sharing.
@MainActor
final class OnDeviceDiagnostics: ObservableObject {
    static let maxBytes = 65_536
    /// What the report sheet shows and shares: the engine failure, then any crash and hang summaries.
    @Published private(set) var report: String?
    private var engineReport: String?
    private var persistedReport: String?
    private var systemReport: String?
    @Published private(set) var isHistorical = false
    @Published var errorMessage: String?
    private let directory: URL
    private var captureGeneration = 0
    private var clearing = false
    private var systemReportsObserver: AnyCancellable?
    private var file: URL { directory.appendingPathComponent("latest-engine-failure.txt") }

    nonisolated static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MagicMobile/Diagnostics", isDirectory: true)
    }

    init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= Self.maxBytes else { throw CocoaError(.fileReadTooLarge) }
                engineReport = try String(contentsOf: file, encoding: .utf8)
                persistedReport = engineReport
                isHistorical = true
            }
        } catch { errorMessage = "Could not load the saved engine report: \(error.localizedDescription)" }
        systemReport = OnDeviceSystemReports.section(OnDeviceSystemReports.load(directory: self.directory))
        publish()
        // MetricKit delivers payloads shortly after launch, after this store exists.
        systemReportsObserver = NotificationCenter.default.publisher(for: OnDeviceSystemReports.didChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, (note.object as? URL)?.standardizedFileURL == self.directory.standardizedFileURL else { return }
                    self.systemReport = OnDeviceSystemReports.section(OnDeviceSystemReports.load(directory: self.directory))
                    self.publish()
                }
            }
    }

    private func publish() {
        let parts = [engineReport, systemReport].compactMap { $0 }
        report = parts.isEmpty ? nil : parts.joined(separator: "\n\n")
        // Crash and hang summaries always describe an earlier session.
        if engineReport == nil { isHistorical = systemReport != nil }
    }

    func beginAttempt() {
        captureGeneration += 1
        if report != nil { isHistorical = true }
    }

    func save(engineReport: String, status: String) throws {
        // Reopening the sheet must not date an existing incident as a new failure.
        if let report = self.engineReport, persistedReport == report, let range = report.range(of: "\n\n"),
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
        self.engineReport = String(data: bytes, encoding: .utf8)
        isHistorical = false
        errorMessage = nil
        publish()
        do {
            try Self.prepare(directory)
            #if os(iOS)
            try bytes.write(to: file, options: [.atomic, .completeFileProtection])
            #else
            try bytes.write(to: file, options: .atomic)
            #endif
            persistedReport = self.engineReport
        } catch {
            errorMessage = "Report is available to share now, but could not be saved on this device: \(error.localizedDescription)"
            throw error
        }
    }

    /// Creates the private, backup-excluded report directory.
    nonisolated static func prepare(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var excludedDirectory = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try excludedDirectory.setResourceValues(values)
    }

    /// Deletes the engine report and the crash and hang summaries.
    func clear() throws {
        captureGeneration += 1
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        engineReport = nil; persistedReport = nil
        try OnDeviceSystemReports.clear(directory: directory)
        systemReport = nil
        errorMessage = nil; isHistorical = false
        publish()
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

/// The app's own crash and hang reports, as MetricKit delivers them to this phone (iOS), kept
/// only in the diagnostics directory and shared only through the report sheet. A summary holds
/// the MetricKit time window, app and OS versions, CPU architecture, the exception or hang
/// duration, and the affected thread's frames (binary name, offset and UUID). MetricKit's
/// region format, device model and process ID are left out.
enum OnDeviceSystemReports {
    struct Entry: Codable, Equatable {
        let kind: String
        let text: String
    }

    static let didChange = Notification.Name("MagicMobile.OnDeviceSystemReports.didChange")
    static let fileName = "crash-and-hang-reports.json"
    static let limit = 5
    static let maxEntryCharacters = 8_000
    static let maxFrames = 32

    /// Crash and hang summaries in one `MXDiagnosticPayload.jsonRepresentation()`.
    static func entries(fromPayload data: Data) -> [Entry] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let window = [root["timeStampBegin"], root["timeStampEnd"]].compactMap { clean($0 as? String, limit: 40) }
            .joined(separator: " – ")
        let crashes = (root["crashDiagnostics"] as? [[String: Any]] ?? []).map { entry(kind: "Crash", diagnostic: $0, window: window) }
        let hangs = (root["hangDiagnostics"] as? [[String: Any]] ?? []).map { entry(kind: "Hang", diagnostic: $0, window: window) }
        return crashes + hangs
    }

    private static func entry(kind: String, diagnostic: [String: Any], window: String) -> Entry {
        let meta = diagnostic["diagnosticMetaData"] as? [String: Any] ?? [:]
        var lines: [String] = []
        var title = kind
        if kind == "Hang", let duration = clean(meta["hangDuration"] as? String, limit: 40) { title += " for \(duration)" }
        if !window.isEmpty { title += " · reported \(window)" }
        lines.append(title)
        let app = clean(meta["appVersion"] as? String, limit: 40).map { version in
            "App \(version)" + (clean(meta["appBuildVersion"] as? String, limit: 40).map { " (\($0))" } ?? "")
        }
        lines.append([app, clean(meta["osVersion"] as? String, limit: 80), clean(meta["platformArchitecture"] as? String, limit: 20)]
            .compactMap { $0 }.joined(separator: " · "))
        if kind == "Crash" {
            var exception: [String] = []
            if let type = integer(meta["exceptionType"]) {
                exception.append("\(machExceptionName(type)) (type \(type), code \(integer(meta["exceptionCode"]).map(String.init) ?? "?"))")
            }
            if let signal = integer(meta["signal"]) { exception.append("signal \(signal)\(signalName(signal).map { " (\($0))" } ?? "")") }
            if !exception.isEmpty { lines.append("Exception: " + exception.joined(separator: " · ")) }
            if let reason = clean(meta["terminationReason"] as? String, limit: 200) { lines.append("Termination: \(reason)") }
            if let region = clean(meta["virtualMemoryRegionInfo"] as? String, limit: 200) { lines.append("Memory: \(region)") }
            if let reason = meta["exceptionReason"] as? [String: Any] {
                let name = clean((reason["exceptionName"] ?? reason["className"]) as? String, limit: 80)
                let message = clean(reason["composedMessage"] as? String, limit: 300)
                let text = [name, message].compactMap { $0 }.joined(separator: ": ")
                if !text.isEmpty { lines.append("Reason: \(text)") }
            }
        }
        let frames = threadFrames(diagnostic["callStackTree"] as? [String: Any])
        if !frames.isEmpty {
            lines.append(kind == "Hang" ? "Main thread:" : "Crashed thread:")
            lines += frames.prefix(maxFrames).enumerated().map { "  \($0.offset) \($0.element)" }
            if frames.count > maxFrames { lines.append("  … \(frames.count - maxFrames) more frames") }
        }
        return Entry(kind: kind, text: String(lines.joined(separator: "\n").prefix(maxEntryCharacters)))
    }

    /// The attributed thread's stack: MetricKit nests each caller in the frame above's `subFrames`.
    private static func threadFrames(_ tree: [String: Any]?) -> [String] {
        let stacks = tree?["callStacks"] as? [[String: Any]] ?? []
        guard let stack = stacks.first(where: { $0["threadAttributed"] as? Bool == true }) ?? stacks.first,
              var frame = (stack["callStackRootFrames"] as? [[String: Any]])?.first else { return [] }
        var frames: [String] = []
        while frames.count <= maxFrames + 64 {
            let binary = clean(frame["binaryName"] as? String, limit: 80) ?? "?"
            let offset = integer(frame["offsetIntoBinaryTextSegment"]).map { "+0x" + String($0, radix: 16) } ?? ""
            let uuid = clean(frame["binaryUUID"] as? String, limit: 36).map { " \($0)" } ?? ""
            frames.append("\(binary) \(offset)\(uuid)".trimmingCharacters(in: .whitespaces))
            guard let next = (frame["subFrames"] as? [[String: Any]])?.first else { break }
            frame = next
        }
        return frames
    }

    private static func clean(_ value: String?, limit: Int) -> String? {
        guard let value else { return nil }
        let text = String(value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
            .trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : String(text.prefix(limit))
    }

    private static func integer(_ value: Any?) -> Int64? {
        // NSNumber bridges 0 and 1 to Bool, so test for a JSON boolean by its CF type instead.
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { return number.int64Value }
        if let text = value as? String { return Int64(text) }
        return nil
    }

    private static func machExceptionName(_ type: Int64) -> String {
        let names: [Int64: String] = [1: "EXC_BAD_ACCESS", 2: "EXC_BAD_INSTRUCTION", 3: "EXC_ARITHMETIC", 4: "EXC_EMULATION",
                                      5: "EXC_SOFTWARE", 6: "EXC_BREAKPOINT", 7: "EXC_SYSCALL", 8: "EXC_MACH_SYSCALL",
                                      9: "EXC_RPC_ALERT", 10: "EXC_CRASH", 11: "EXC_RESOURCE", 12: "EXC_GUARD", 13: "EXC_CORPSE_NOTIFY"]
        return names[type] ?? "Mach exception"
    }

    private static func signalName(_ signal: Int64) -> String? {
        [4: "SIGILL", 5: "SIGTRAP", 6: "SIGABRT", 7: "SIGEMT", 8: "SIGFPE", 9: "SIGKILL", 10: "SIGBUS",
         11: "SIGSEGV", 12: "SIGSYS", 13: "SIGPIPE", 15: "SIGTERM"][signal]
    }

    /// New summaries join the saved ones; a repeated delivery is kept once, newest last.
    static func merged(_ existing: [Entry], _ new: [Entry]) -> [Entry] {
        var result = existing
        for entry in new where !result.contains(entry) { result.append(entry) }
        return Array(result.suffix(limit))
    }

    /// The export text, or nil when this phone has no crash or hang report.
    static func section(_ entries: [Entry]) -> String? {
        guard !entries.isEmpty else { return nil }
        return (["MagicMobile crash and hang reports (\(entries.count), newest last, from MetricKit on this phone)"]
            + entries.map(\.text)).joined(separator: "\n\n")
    }

    static func load(directory: URL) -> [Entry] {
        let url = directory.appendingPathComponent(fileName)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= limit * maxEntryCharacters * 4 + 4_096,
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return Array(entries.suffix(limit))
    }

    static func save(_ entries: [Entry], directory: URL) throws {
        try OnDeviceDiagnostics.prepare(directory)
        let data = try JSONEncoder().encode(Array(entries.suffix(limit)))
        let url = directory.appendingPathComponent(fileName)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }

    /// Adds the summaries in `payloads` (MetricKit JSON) and tells open report sheets.
    @discardableResult
    static func record(payloads: [Data], directory: URL) -> Bool {
        let new = payloads.flatMap(entries(fromPayload:))
        guard !new.isEmpty else { return false }
        let existing = load(directory: directory)
        let combined = merged(existing, new)
        guard combined != existing, (try? save(combined, directory: directory)) != nil else { return false }
        NotificationCenter.default.post(name: didChange, object: directory)
        return true
    }

    static func clear(directory: URL) throws {
        let url = directory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

#if canImport(MetricKit) && os(iOS)
import MetricKit

/// Registered at launch (MagicMobileAppDelegate). MetricKit hands the app its own crash and hang
/// diagnostics, usually on the next launch; they are summarized into the local report and never uploaded.
final class OnDeviceCrashReporter: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = OnDeviceCrashReporter()
    private var started = false

    @MainActor
    func start() {
        guard !started else { return }
        started = true
        MXMetricManager.shared.add(self)
        record(MXMetricManager.shared.pastDiagnosticPayloads)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) { record(payloads) }

    private func record(_ payloads: [MXDiagnosticPayload]) {
        let data = payloads.map { $0.jsonRepresentation() }
        guard !data.isEmpty else { return }
        DispatchQueue.main.async {
            OnDeviceSystemReports.record(payloads: data, directory: OnDeviceDiagnostics.defaultDirectory)
        }
    }
}
#endif
