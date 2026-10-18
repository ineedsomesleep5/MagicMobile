import Foundation
import os

/// Heat and memory awareness (docs/LIGHTER_ENGINE_PLAN.md step 2, app only). While the phone reports heat, board effects
/// draw at half rate; memory warnings free the app's caches (OnDeviceRootView); every game keeps a small performance
/// record (memory peak, hottest thermal state, memory warnings) that Diagnostics can share, so builds can be compared on
/// Caleb's phone. While hot, games the engine runs on this phone (not ranked, not online) ask the AI to think for less
/// time (OnDeviceSession.devicePaceHot, engine release C). Android's DeviceHeat and GamePerformanceLog match it.
@MainActor
final class DeviceHeat: ObservableObject {
    static let shared = DeviceHeat()
    @Published private(set) var thermal: ProcessInfo.ThermalState
    private var observer: NSObjectProtocol?

    /// Serious or critical: the system is already slowing the phone down to cool it.
    var isHot: Bool { Self.isHot(thermal) }
    /// Board effects' frame rate: 60 fps normally, 30 while hot.
    var effectsFrameInterval: Double { isHot ? 1.0 / 30 : 1.0 / 60 }

    nonisolated static func isHot(_ state: ProcessInfo.ThermalState) -> Bool { state == .serious || state == .critical }

    private init() {
        thermal = ProcessInfo.processInfo.thermalState
        observer = NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.thermal = ProcessInfo.processInfo.thermalState
                GamePerformanceLog.shared.sample()
            }
        }
    }
}

/// What the system counts against this app's memory limit, the engine included (it runs in the app's process).
enum AppMemory {
    static func footprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
    }

    /// How much more the app may use before the system ends it; nil where the system doesn't say (simulator, Mac).
    static func available() -> UInt64? {
        #if os(iOS) && !targetEnvironment(simulator)
        let bytes = os_proc_available_memory()
        return bytes > 0 ? UInt64(bytes) : nil
        #else
        return nil
        #endif
    }
}

/// One game's performance record.
struct GamePerformanceEntry: Codable, Equatable, Sendable {
    var started: Date
    var mode: String
    var aiSkill: Int?
    var minutes: Double = 0
    var turns = 0
    var peakFootprintMB = 0
    var lowestAvailableMB: Int?
    /// The hottest ProcessInfo.ThermalState seen (0 nominal … 3 critical).
    var hottest = 0
    var hotMinutes: Double = 0
    var memoryWarnings = 0
    var lastSample: Date?

    /// Takes one reading. Time since the previous reading counts as hot when this reading is hot.
    mutating func absorb(at now: Date, footprint: UInt64?, available: UInt64?, thermal: Int) {
        if let footprint { peakFootprintMB = max(peakFootprintMB, Int(footprint / 1_048_576)) }
        if let available {
            let mb = Int(available / 1_048_576)
            lowestAvailableMB = min(lowestAvailableMB ?? mb, mb)
        }
        hottest = max(hottest, thermal)
        if let lastSample, thermal >= ProcessInfo.ThermalState.serious.rawValue {
            hotMinutes += max(0, now.timeIntervalSince(lastSample)) / 60
        }
        lastSample = now
    }

    static let thermalNames = ["nominal", "fair", "serious", "critical"]

    var line: String {
        let day = ISO8601DateFormatter.string(from: started, timeZone: .current, formatOptions: [.withFullDate, .withTime, .withColonSeparatorInTime])
        var parts = ["\(day) \(mode)" + (aiSkill.map { " skill \($0)" } ?? ""),
                     String(format: "%.0f min, %d turns", minutes, turns),
                     "peak \(peakFootprintMB) MB"]
        if let lowestAvailableMB { parts.append("lowest headroom \(lowestAvailableMB) MB") }
        parts.append("hottest \(Self.thermalNames[min(max(hottest, 0), 3)])")
        if hotMinutes >= 0.5 { parts.append(String(format: "hot %.0f min", hotMinutes)) }
        if memoryWarnings > 0 { parts.append("\(memoryWarnings) memory warning" + (memoryWarnings == 1 ? "" : "s")) }
        return parts.joined(separator: ", ")
    }
}

/// The last twenty games' performance records, kept on this phone only (never uploaded).
@MainActor
final class GamePerformanceLog {
    static let shared = GamePerformanceLog()
    static let limit = 20
    static let key = "magicmobile.performance.games"
    private static let logger = Logger(subsystem: "com.calebfeliciano.magicmobile", category: "performance")

    private let defaults: UserDefaults
    private(set) var current: GamePerformanceEntry?
    private var sampler: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var entries: [GamePerformanceEntry] {
        guard let data = defaults.data(forKey: Self.key),
              let entries = try? JSONDecoder().decode([GamePerformanceEntry].self, from: data) else { return [] }
        return entries
    }

    /// A game started: readings every ten seconds until it ends.
    func begin(mode: String, aiSkill: Int?, now: Date = Date(), sampling: Bool = true) {
        end(now: now)
        current = GamePerformanceEntry(started: now, mode: mode, aiSkill: aiSkill)
        sample(at: now)
        guard sampling else { return }
        sampler = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                self?.sample()
            }
        }
    }

    func sample(at now: Date = Date(), footprint: UInt64? = AppMemory.footprint(), available: UInt64? = AppMemory.available(),
                thermal: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState) {
        current?.absorb(at: now, footprint: footprint, available: available, thermal: thermal.rawValue)
    }

    func noteTurn(_ turn: Int?) {
        guard let turn, var entry = current else { return }
        entry.turns = max(entry.turns, turn)
        current = entry
    }

    func noteMemoryWarning() {
        current?.memoryWarnings += 1
        Self.logger.notice("memory warning during a game")
    }

    /// The game ended: keep its record.
    func end(now: Date = Date()) {
        sampler?.cancel()
        sampler = nil
        guard var entry = current else { return }
        current = nil
        entry.minutes = max(0, now.timeIntervalSince(entry.started)) / 60
        entry.lastSample = nil
        let kept = Array((entries + [entry]).suffix(Self.limit))
        if let data = try? JSONEncoder().encode(kept) { defaults.set(data, forKey: Self.key) }
        Self.logger.notice("game performance: \(entry.line, privacy: .public)")
    }

    /// The Diagnostics text, newest first, or nil before the first game.
    static func section(_ entries: [GamePerformanceEntry]) -> String? {
        guard !entries.isEmpty else { return nil }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return (["MagicMobile game performance (\(entries.count) games, newest first), app \(version) (\(build))"]
            + entries.reversed().map(\.line)).joined(separator: "\n")
    }
}
