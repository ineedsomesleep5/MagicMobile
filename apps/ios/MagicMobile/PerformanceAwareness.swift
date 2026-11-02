import Foundation
import os
#if os(iOS)
import QuartzCore
#endif
import SwiftUI

/// Heat and memory awareness (docs/LIGHTER_ENGINE_PLAN.md step 2, app only). While the phone reports heat, board effects
/// draw at half rate; memory warnings free the app's caches (OnDeviceRootView); every game keeps a small performance
/// record (memory peak, heat, CPU, the table it was played on) that goes to the server once the game ends (mm_game_heat,
/// docs/SERVER_CONTROLS.md "Heat reports"), so builds, tables and phones compare without anyone recording a phone. While hot,
/// games the engine runs on this phone (not ranked, not online) ask the AI to think for less time
/// (OnDeviceSession.devicePaceHot, engine release C). Android's DeviceHeat and GamePerformanceLog match it.
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

    /// The battery's charge in percent, in the system's 5% steps; nil where the system doesn't say.
    @MainActor static var batteryPercent: Int? {
        #if os(iOS)
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        return device.batteryLevel < 0 ? nil : Int((device.batteryLevel * 100).rounded())
        #else
        return nil
        #endif
    }
}

/// What this phone is: "iPhone17,2" and "27.0".
enum DeviceModel {
    static var identifier: String {
        var system = utsname()
        guard uname(&system) == 0 else { return "unknown" }
        return withUnsafeBytes(of: &system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }

    static var system: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion)"
    }
}

/// The app's CPU time so far, in seconds. The graphics chip's work isn't in it: the system doesn't say.
struct CPUReading: Codable, Equatable, Sendable {
    var total: Double
    /// The main thread: the board, its effects and the encoding of the world's Metal patches.
    var board: Double
    /// The AI's search threads.
    var ai: Double
    /// The rest: polling the engine, decoding, and the engine's own game thread.
    var updates: Double { max(0, total - board - ai) }
}

/// Splits the app's CPU time by what the threads do, the way the 2026-10-18 phone traces did. The engine names its search
/// threads AI-SIM-…, so nothing in the engine changes. Reads on the main thread, ten seconds apart.
@MainActor
final class CPUMeter {
    private var searchThreads: [thread_t: Double] = [:]
    private var ai: Double = 0
    private var read = false

    nonisolated static func isSearchThread(_ name: String) -> Bool { name.hasPrefix("AI-") }

    func reading() -> CPUReading {
        let live = Self.threadTimes()
        for (thread, seconds) in live where read { ai += max(0, seconds - (searchThreads[thread] ?? 0)) }
        searchThreads = live
        read = true
        return CPUReading(total: Double(clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID)) / 1e9,
                          board: Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1e9, ai: ai)
    }

    /// The search threads alive now, and their CPU time.
    private static func threadTimes() -> [thread_t: Double] {
        var list: thread_act_array_t?
        var count: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &list, &count) == KERN_SUCCESS, let list else { return [:] }
        defer {
            for index in 0..<Int(count) { mach_port_deallocate(mach_task_self_, list[index]) }
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: list), vm_size_t(Int(count) * MemoryLayout<thread_t>.stride))
        }
        var times: [thread_t: Double] = [:]
        for index in 0..<Int(count) {
            let thread = list[index]
            var name = [CChar](repeating: 0, count: 64)
            guard let handle = pthread_from_mach_thread_np(thread), pthread_getname_np(handle, &name, name.count) == 0,
                  isSearchThread(String(cString: name)) else { continue }
            var info = thread_basic_info()
            var size = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), $0, &size) }
            }
            guard result == KERN_SUCCESS else { continue }
            times[thread] = Double(info.user_time.seconds + info.system_time.seconds)
                + Double(info.user_time.microseconds + info.system_time.microseconds) / 1e6
        }
        return times
    }
}

/// Times the board's frames for a few seconds, a minute apart and never while it rests, so measuring costs next to nothing.
@MainActor
final class BoardFrameSampler: NSObject {
    /// A frame more than half a frame late is what a stutter looks like.
    nonisolated static func isSlow(gap: TimeInterval, frame: TimeInterval) -> Bool { gap > frame * 1.5 }

    #if os(iOS)
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var until: CFTimeInterval = 0
    private var frames = 0
    private var slow = 0
    private var done: ((Int, Int) -> Void)?

    func run(seconds: TimeInterval, done: @escaping (_ frames: Int, _ slow: Int) -> Void) {
        guard link == nil else { return }
        (last, frames, slow) = (0, 0, 0)
        until = CACurrentMediaTime() + seconds
        self.done = done
        let created = CADisplayLink(target: self, selector: #selector(tick(_:)))
        created.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        created.add(to: .main, forMode: .common)
        link = created
    }

    func stop() {
        link?.invalidate()
        link = nil
        done = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        if last > 0 {
            frames += 1
            if Self.isSlow(gap: link.timestamp - last, frame: link.targetTimestamp - link.timestamp) { slow += 1 }
        }
        last = link.timestamp
        guard link.timestamp >= until else { return }
        let finish = done
        stop()
        finish?(frames, slow)
    }
    #else
    func run(seconds: TimeInterval, done: @escaping (_ frames: Int, _ slow: Int) -> Void) {}
    func stop() {}
    #endif
}

/// How a game looked: what the board was showing and how much of it moved. Android has no moving worlds, so it names neither.
struct GameBoardNote: Codable, Equatable, Sendable {
    var board: String
    var table: String?
    var motion: String?
    var effects: String
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
    /// What the report needs. Optional, so older records load; without an id a record is never sent.
    var id: UUID?
    var build: Int?
    var setup: GameBoardNote?
    /// Seconds the app was awake for: readings further apart than `awakeGap` had it in the background.
    var activeSeconds: Double?
    var warmMinutes: Double?
    var secondsToWarm: Double?
    var secondsToHot: Double?
    var cpu: CPUReading?
    var lastCPU: CPUReading?
    var frames: Int?
    var slowFrames: Int?
    var batteryStart: Int?
    var batteryEnd: Int?
    /// The app never got to end this game: it stopped at its last saved minute.
    var interrupted: Bool?
    /// The server has it, or refused it for good.
    var sent: Bool?

    static let awakeGap: TimeInterval = 30
    static let shortest: TimeInterval = 60

    /// Takes one reading. Time since the previous reading counts as hot when this reading is hot.
    mutating func absorb(at now: Date, footprint: UInt64?, available: UInt64?, thermal: Int, onCharger: Bool = false, lowPowerMode: Bool = false,
                         cpu reading: CPUReading? = nil, battery: Int? = nil) {
        absorbLoad(at: now, thermal: thermal, cpu: reading, battery: battery)
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

    /// Before `lastSample` moves: what happened since the previous reading.
    private mutating func absorbLoad(at now: Date, thermal: Int, cpu reading: CPUReading?, battery: Int?) {
        if batteryStart == nil { batteryStart = battery }
        batteryEnd = battery ?? batteryEnd
        let gap = lastSample.map { max(0, now.timeIntervalSince($0)) } ?? 0
        if gap <= Self.awakeGap {
            activeSeconds = (activeSeconds ?? 0) + gap
            if thermal >= ProcessInfo.ThermalState.fair.rawValue { warmMinutes = (warmMinutes ?? 0) + gap / 60 }
            if let reading, let lastCPU {
                let used = cpu ?? CPUReading(total: 0, board: 0, ai: 0)
                cpu = CPUReading(total: used.total + max(0, reading.total - lastCPU.total), board: used.board + max(0, reading.board - lastCPU.board),
                                 ai: used.ai + max(0, reading.ai - lastCPU.ai))
            }
        }
        lastCPU = reading ?? lastCPU
        if thermal >= ProcessInfo.ThermalState.fair.rawValue, secondsToWarm == nil { secondsToWarm = activeSeconds ?? 0 }
        if thermal >= ProcessInfo.ThermalState.serious.rawValue, secondsToHot == nil { secondsToHot = activeSeconds ?? 0 }
    }

    mutating func noteFrames(_ count: Int, slow: Int) {
        frames = (frames ?? 0) + count
        slowFrames = (slowFrames ?? 0) + slow
    }

    private var batteryUsed: Int? {
        guard let batteryStart, let batteryEnd, charging != true else { return nil }
        return max(0, batteryStart - batteryEnd)
    }

    /// Percent of one core while the app was awake.
    private func percent(_ seconds: Double) -> Double {
        guard let activeSeconds, activeSeconds > 0 else { return 0 }
        return (seconds / activeSeconds * 1000).rounded() / 10
    }

    /// mm_game_heat's parameters, or nil for a record with nothing to say: one from an earlier build, or a game under a minute.
    func report(device: String, system: String) -> [String: Any]? {
        guard let id, let build, let activeSeconds, activeSeconds >= Self.shortest else { return nil }
        let tenth = { (value: Double) in (value * 10).rounded() / 10 }
        var stats: [String: Any] = ["minutes": tenth(activeSeconds / 60), "turns": turns, "hottest": hottest,
                                    "hotMinutes": tenth(min(hotMinutes, activeSeconds / 60)), "warmMinutes": tenth(warmMinutes ?? 0),
                                    "peakMB": peakFootprintMB, "memoryWarnings": memoryWarnings, "charging": charging == true,
                                    "lowPower": lowPower == true, "interrupted": interrupted == true]
        if let startThermal { stats["startThermal"] = startThermal }
        if let secondsToWarm { stats["secondsToWarm"] = secondsToWarm.rounded() }
        if let secondsToHot { stats["secondsToHot"] = secondsToHot.rounded() }
        if let lowestAvailableMB { stats["lowestHeadroomMB"] = lowestAvailableMB }
        if let cpu {
            stats["cpu"] = percent(cpu.total)
            stats["cpuBoard"] = percent(cpu.board)
            stats["cpuUpdates"] = percent(cpu.updates)
            stats["cpuAI"] = percent(cpu.ai)
        }
        if let frames, frames > 0 { stats["slowFrames"] = tenth(100 * Double(slowFrames ?? 0) / Double(frames)) }
        if let batteryUsed { stats["batteryUsed"] = batteryUsed }
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var report: [String: Any] = ["p_client_id": id.uuidString, "p_played_at": stamp.string(from: started), "p_platform": "ios", "p_build": build,
                                     "p_device": String(device.prefix(40)), "p_os": String(system.prefix(40)), "p_mode": mode, "p_stats": stats]
        if let aiSkill { report["p_ai_skill"] = aiSkill }
        if let setup {
            report["p_board"] = setup.board
            report["p_effects"] = setup.effects
            if let table = setup.table { report["p_table"] = table }
            if let motion = setup.motion { report["p_motion"] = motion }
        }
        return report
    }

    static let thermalNames = ["nominal", "fair", "serious", "critical"]

    var line: String {
        let day = ISO8601DateFormatter.string(from: started, timeZone: .current, formatOptions: [.withFullDate, .withTime, .withColonSeparatorInTime])
        var parts = ["\(day) \(mode)" + (aiSkill.map { " skill \($0)" } ?? "") + (build.map { " build \($0)" } ?? ""),
                     String(format: "%.0f min, %d turns", minutes, turns),
                     "peak \(peakFootprintMB) MB"]
        if let lowestAvailableMB { parts.append("lowest headroom \(lowestAvailableMB) MB") }
        parts.append("hottest \(Self.thermalNames[min(max(hottest, 0), 3)])")
        if hotMinutes >= 0.5 { parts.append(String(format: "hot %.0f min", hotMinutes)) }
        if let startThermal, startThermal > 0 { parts.append("began \(Self.thermalNames[min(startThermal, 3)])") }
        if charging == true { parts.append("charging") }
        if lowPower == true { parts.append("low power") }
        if memoryWarnings > 0 { parts.append("\(memoryWarnings) memory warning" + (memoryWarnings == 1 ? "" : "s")) }
        if let table = setup?.table { parts.append(table + (setup?.motion == WorldMotion.full.rawValue ? "" : " motion \(setup?.motion ?? "?")")) }
        if let cpu { parts.append(String(format: "CPU %.0f%% (board %.0f, updates %.0f, AI %.0f)", percent(cpu.total), percent(cpu.board), percent(cpu.updates), percent(cpu.ai))) }
        if let frames, frames > 0 { parts.append(String(format: "%.1f%% slow frames", 100 * Double(slowFrames ?? 0) / Double(frames))) }
        if let batteryUsed { parts.append("battery \(batteryUsed)%") }
        if interrupted == true { parts.append("cut short") }
        return parts.joined(separator: ", ")
    }
}

/// The last twenty games' performance records. Each goes to the server once its game ends (`flush`); the numbers stay here too.
@MainActor
final class GamePerformanceLog {
    static let shared = GamePerformanceLog()
    static let limit = 20
    static let key = "magicmobile.performance.games"
    /// The game running now, saved each minute, so one the app never got to end (heat, memory, a force quit) still counts.
    static let runningKey = "magicmobile.performance.running"
    private static let logger = Logger(subsystem: "com.calebfeliciano.magicmobile", category: "performance")

    private let defaults: UserDefaults
    private(set) var current: GamePerformanceEntry?
    private var sampler: Task<Void, Never>?
    private let meter = CPUMeter()
    private let frames = BoardFrameSampler()
    private var boardNote: GameBoardNote?
    private var flushing = false

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var entries: [GamePerformanceEntry] {
        guard let data = defaults.data(forKey: Self.key),
              let entries = try? JSONDecoder().decode([GamePerformanceEntry].self, from: data) else { return [] }
        return entries
    }

    /// A game started: readings every ten seconds until it ends.
    func begin(mode: String, aiSkill: Int?, now: Date = Date(), sampling: Bool = true) {
        end(now: now)
        recoverInterrupted()
        current = GamePerformanceEntry(started: now, mode: mode, aiSkill: aiSkill)
        current?.id = UUID()
        current?.build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String).flatMap(Int.init)
        sample(at: now)
        guard sampling else { return }
        sampler = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                self?.sample()
                tick += 1
                if tick % 6 == 0 { self?.minuteMark() }
            }
        }
    }

    func sample(at now: Date = Date(), footprint: UInt64? = AppMemory.footprint(), available: UInt64? = AppMemory.available(),
                thermal: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState,
                lowPowerMode: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled) {
        guard current != nil else { return }
        if let boardNote { current?.setup = boardNote }
        current?.absorb(at: now, footprint: footprint, available: available, thermal: thermal.rawValue,
                        onCharger: DevicePower.onCharger, lowPowerMode: lowPowerMode, cpu: meter.reading(), battery: DevicePower.batteryPercent)
    }

    /// The board on screen. It can arrive before `begin`.
    func noteBoard(_ note: GameBoardNote) { boardNote = note }

    /// Once a minute: keeps the running game safe, and times the board's frames unless it's resting.
    private func minuteMark() {
        saveRunning()
        guard !BoardActivity.shared.isIdle else { return }
        frames.run(seconds: 3) { [weak self] count, slow in self?.current?.noteFrames(count, slow: slow) }
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
        frames.stop()
        guard current != nil else { return }
        sample(at: now)
        guard var entry = current else { return }
        current = nil
        boardNote = nil
        defaults.removeObject(forKey: Self.runningKey)
        entry.minutes = max(0, now.timeIntervalSince(entry.started)) / 60
        entry.lastSample = nil
        entry.lastCPU = nil
        keep(entry)
        Self.logger.notice("game performance: \(entry.line, privacy: .public)")
    }

    private func keep(_ entry: GamePerformanceEntry) {
        let kept = Array((entries + [entry]).suffix(Self.limit))
        if let data = try? JSONEncoder().encode(kept) { defaults.set(data, forKey: Self.key) }
    }

    private func saveRunning() {
        if let current, let data = try? JSONEncoder().encode(current) { defaults.set(data, forKey: Self.runningKey) }
    }

    /// A game the app never got to end counts up to its last saved minute.
    private func recoverInterrupted() {
        guard current == nil, let data = defaults.data(forKey: Self.runningKey) else { return }
        defaults.removeObject(forKey: Self.runningKey)
        guard var entry = try? JSONDecoder().decode(GamePerformanceEntry.self, from: data) else { return }
        entry.interrupted = true
        entry.minutes = (entry.activeSeconds ?? 0) / 60
        entry.lastSample = nil
        entry.lastCPU = nil
        keep(entry)
    }

    /// Sends every finished game the server doesn't have, oldest first, and stops at the first that can't go for now.
    func flush(device: String = DeviceModel.identifier, system: String = DeviceModel.system,
               send: ([String: Any]) async -> GameUploadResult) async {
        guard !flushing else { return }
        flushing = true
        defer { flushing = false }
        recoverInterrupted()
        for entry in entries where entry.id != nil && entry.sent != true {
            if let report = entry.report(device: device, system: system) {
                switch await send(report) {
                case .sent, .rejected: break
                case .retryLater, .unavailable: return
                }
            }
            markSent(entry.id)
        }
    }

    private func markSent(_ id: UUID?) {
        var all = entries
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        all[index].sent = true
        if let data = try? JSONEncoder().encode(all) { defaults.set(data, forKey: Self.key) }
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
