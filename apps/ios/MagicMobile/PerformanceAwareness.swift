import Foundation
import os
import SwiftUI

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
    /// The board's slow ambient motion (breathing glows, the inspector's foil): 30 steps a second, 15 while hot.
    var ambientInterval: Double { Self.ambientInterval(hot: isHot) }

    nonisolated static func isHot(_ state: ProcessInfo.ThermalState) -> Bool { state == .serious || state == .critical }
    nonisolated static func ambientInterval(hot: Bool) -> Double { hot ? 1.0 / 15 : 1.0 / 30 }

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

/// One wall-clock grid for the board's ambient motion (BoardBreath, InspectionFoil). Every timeline on it updates in the
/// same frames, however many are on screen. Each glow used to run its own `.animation(minimumInterval:)` timeline from
/// the moment it appeared, so a few glows at 30 steps a second kept SwiftUI redrawing the whole board 60 times a second
/// (Instruments on Caleb's iPhone, 2026-10-18). Grid times are whole multiples of `interval`, computed from an index so
/// two timelines never disagree by a rounding error. Like BurstTimelineSchedule it answers with the latest grid time at
/// or before the date asked for, then strictly later ones; starting from "now" would update the view forever. Paused, it
/// gives that one time and the view draws once.
struct AmbientTimelineSchedule: TimelineSchedule {
    var interval: TimeInterval
    var paused = false

    /// How far through a repeating `period` a grid time is, 0 up to 1. Reading the wall clock keeps every loop in step.
    static func phase(at date: Date, period: TimeInterval) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
    }

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        // Always-on displays get one step a second.
        let step = mode == .lowFrequency ? max(interval, 1) : max(interval, 1.0 / 120)
        var index = (startDate.timeIntervalSinceReferenceDate / step).rounded(.down)
        if index * step > startDate.timeIntervalSinceReferenceDate { index -= 1 }
        return Entries(index: index, step: step, single: paused)
    }

    struct Entries: Sequence, IteratorProtocol {
        var index: Double
        let step: TimeInterval
        let single: Bool
        var finished = false

        mutating func next() -> Date? {
            guard !finished else { return nil }
            let date = Date(timeIntervalSinceReferenceDate: index * step)
            index += 1
            finished = single
            return date
        }
    }
}

/// Whether anyone is using the board. Once nothing has changed in the game and nobody has touched the screen for
/// `idleAfter` seconds, the breathing glows rest (lit and still) and the board stops redrawing; the next touch or game
/// change wakes them. NativeGameView reports both.
@MainActor
final class BoardActivity: ObservableObject {
    static let shared = BoardActivity()
    nonisolated static let idleAfter: TimeInterval = 15
    @Published private(set) var isIdle = false
    private var last = Date()
    private var watcher: Task<Void, Never>?

    func note(at now: Date = Date()) {
        last = now
        if isIdle { isIdle = false }
        guard watcher == nil else { return }
        watcher = Task { [weak self] in
            while let self, !Task.isCancelled {
                let wait = Self.remaining(lastActivity: self.last, now: Date())
                if wait <= 0 {
                    self.isIdle = true
                    self.watcher = nil
                    return
                }
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    /// Seconds until the board counts as idle; zero or less once it does.
    nonisolated static func remaining(lastActivity: Date, now: Date) -> TimeInterval {
        idleAfter - now.timeIntervalSince(lastActivity)
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

/// Whether the phone is on a charger; false where the system doesn't say (simulator, Mac).
enum DevicePower {
    @MainActor static var onCharger: Bool {
        #if os(iOS)
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        return device.batteryState == .charging || device.batteryState == .full
        #else
        return false
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
    /// The state at the first reading: a game that began warm didn't heat the phone by itself. Optional, like the two
    /// below, so records saved by earlier builds still load.
    var startThermal: Int?
    /// On a charger at any reading (charging heats a phone by itself).
    var charging: Bool?
    /// Low Power Mode at any reading.
    var lowPower: Bool?

    /// Takes one reading. Time since the previous reading counts as hot when this reading is hot.
    mutating func absorb(at now: Date, footprint: UInt64?, available: UInt64?, thermal: Int, onCharger: Bool = false, lowPowerMode: Bool = false) {
        if startThermal == nil { startThermal = thermal }
        if onCharger { charging = true }
        if lowPowerMode { lowPower = true }
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
        if let startThermal, startThermal > 0 { parts.append("began \(Self.thermalNames[min(startThermal, 3)])") }
        if charging == true { parts.append("charging") }
        if lowPower == true { parts.append("low power") }
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
                thermal: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState,
                lowPowerMode: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled) {
        current?.absorb(at: now, footprint: footprint, available: available, thermal: thermal.rawValue,
                        onCharger: DevicePower.onCharger, lowPowerMode: lowPowerMode)
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
