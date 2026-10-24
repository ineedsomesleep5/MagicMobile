import Foundation

/// When a game that still answers has stopped moving (docs/FREEZE_LOG.md; parity: freeze-cases.json).
enum FreezeRules {
    static let answerSeconds: TimeInterval = 20
    static let soloQuietSeconds: TimeInterval = 120
    static let tableQuietSeconds: TimeInterval = 180

    /// "answer-not-accepted", "engine-quiet", or nil while the game is fine (or waiting on you).
    static func stall(inGame: Bool, over: Bool, waitingOnYou: Bool, answerPendingSeconds: TimeInterval?,
                      quietSeconds: TimeInterval, withPeople: Bool) -> String? {
        guard inGame, !over else { return nil }
        if let pending = answerPendingSeconds, pending >= answerSeconds { return "answer-not-accepted" }
        guard !waitingOnYou else { return nil }
        return quietSeconds >= (withPeople ? tableQuietSeconds : soloQuietSeconds) ? "engine-quiet" : nil
    }
}

/// One freeze: what kind, when, how long (hangs), the game around it, and the breadcrumbs that led there.
struct FreezeIncident: Codable, Equatable, Identifiable {
    let id: UUID
    let kind: String
    let at: Date
    var duration: TimeInterval?
    let context: String
    let breadcrumbs: [String]
    /// A game was on: a hang in the menus (a slow launch) is kept for the report but never asked about.
    let inGame: Bool
    /// Sent to the developer, or the player chose Not now: either way the launch prompt doesn't ask again.
    var sent = false
    var dismissed = false
}

/// The app's own freeze record (docs/FREEZE_LOG.md): a ring of breadcrumbs, the latest game context, and the last few
/// incidents on disk in the diagnostics folder. Written from the main thread and the watchdog thread, so it locks.
/// Nothing leaves the phone unless the player sends a report.
final class FreezeLog: @unchecked Sendable {
    static let shared = FreezeLog(directory: OnDeviceDiagnostics.defaultDirectory)
    static let fileName = "freeze-log.json"
    static let didChange = Notification.Name("MagicMobile.FreezeLog.didChange")
    static let breadcrumbLimit = 80
    static let incidentLimit = 5

    private let lock = NSLock()
    private let directory: URL
    private let started: TimeInterval
    private let uptime: () -> TimeInterval
    private var crumbs: [String] = []
    static let noGame = "No game"
    private var context = FreezeLog.noGame
    private var stored: [FreezeIncident]

    init(directory: URL, uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.directory = directory
        self.uptime = uptime
        started = uptime()
        stored = Self.load(directory: directory)
    }

    /// A breadcrumb, stamped with seconds since launch.
    func note(_ text: String) {
        let line = String(format: "+%.1fs ", uptime() - started) + String(text.prefix(200))
        lock.lock(); defer { lock.unlock() }
        crumbs.append(line)
        if crumbs.count > Self.breadcrumbLimit { crumbs.removeFirst(crumbs.count - Self.breadcrumbLimit) }
    }

    /// What the game looks like now; read by the watchdog when the main thread is stuck, so it's kept ready.
    func setContext(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        context = text
    }

    var incidents: [FreezeIncident] {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    /// The newest in-game incident nobody has sent or set aside, for the launch prompt.
    var unsent: FreezeIncident? { incidents.last { $0.inGame && !$0.sent && !$0.dismissed } }

    /// Records an incident now (saved at once: a stuck app may be ended before it recovers) and returns its id.
    @discardableResult
    func record(kind: String, duration: TimeInterval? = nil, extra: String? = nil, at date: Date = Date()) -> UUID {
        lock.lock()
        let body = [extra, context].compactMap { $0 }.joined(separator: "\n")
        let incident = FreezeIncident(id: UUID(), kind: kind, at: date, duration: duration, context: body, breadcrumbs: crumbs,
                                      inGame: context != Self.noGame)
        stored = Array((stored + [incident]).suffix(Self.incidentLimit))
        let snapshot = stored
        lock.unlock()
        persist(snapshot)
        return incident.id
    }

    func update(_ id: UUID, duration: TimeInterval) { change(id) { $0.duration = duration } }
    func markSent(_ id: UUID) { change(id) { $0.sent = true } }
    func dismiss(_ id: UUID) { change(id) { $0.dismissed = true } }

    func clear() {
        lock.lock(); stored = []; lock.unlock()
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(Self.fileName))
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    private func change(_ id: UUID, _ edit: (inout FreezeIncident) -> Void) {
        lock.lock()
        guard let index = stored.firstIndex(where: { $0.id == id }) else { lock.unlock(); return }
        edit(&stored[index])
        let snapshot = stored
        lock.unlock()
        persist(snapshot)
    }

    private func persist(_ incidents: [FreezeIncident]) {
        do {
            try OnDeviceDiagnostics.prepare(directory)
            let data = try JSONEncoder().encode(incidents)
            #if os(iOS)
            try data.write(to: directory.appendingPathComponent(Self.fileName), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: directory.appendingPathComponent(Self.fileName), options: .atomic)
            #endif
        } catch { return }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    static func load(directory: URL) -> [FreezeIncident] {
        let url = directory.appendingPathComponent(fileName)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 512_000,
              let data = try? Data(contentsOf: url),
              let incidents = try? JSONDecoder().decode([FreezeIncident].self, from: data) else { return [] }
        return Array(incidents.suffix(incidentLimit))
    }

    /// One incident as the report sheet shows it and a sent report carries.
    static func text(_ incident: FreezeIncident) -> String {
        let stamp = ISO8601DateFormatter().string(from: incident.at)
        var title = "\(title(incident.kind)) · \(stamp)"
        if let duration = incident.duration { title += String(format: " · %.1f s", duration) }
        return ([title, incident.context, "Breadcrumbs (oldest first):"] + incident.breadcrumbs.map { "  " + $0 })
            .joined(separator: "\n")
    }

    /// The report sheet's section, or nil with no incident.
    static func section(_ incidents: [FreezeIncident]) -> String? {
        guard !incidents.isEmpty else { return nil }
        return (["MagicMobile freeze log (\(incidents.count), newest last)"] + incidents.map(text)).joined(separator: "\n\n")
    }

    static func title(_ kind: String) -> String {
        switch kind {
        case "hang": return "The screen stopped responding"
        case "answer-not-accepted": return "An answer was never accepted"
        case "engine-quiet": return "The game stopped moving"
        case "reported": return "Reported from the game menu"
        default: return kind
        }
    }
}

/// Pings the main thread from its own thread; 2 s without an answer is a hang (docs/FREEZE_LOG.md). The hang is saved
/// the moment it's noticed and its duration kept current, so a phone that ends the stuck app still leaves the record.
final class MainThreadWatchdog: @unchecked Sendable {
    static let shared = MainThreadWatchdog(log: .shared)
    static let threshold: TimeInterval = 2
    private let log: FreezeLog
    private let lock = NSLock()
    private var pingSentAt: TimeInterval?
    private var hang: (id: UUID, savedAt: TimeInterval)?
    private var paused = false
    private var started = false

    init(log: FreezeLog) { self.log = log }

    func start() {
        lock.lock(); defer { lock.unlock() }
        guard !started else { return }
        started = true
        let thread = Thread { [weak self] in
            while let self { self.tick(); Thread.sleep(forTimeInterval: 0.5) }
        }
        thread.name = "MagicMobile.MainThreadWatchdog"
        thread.qualityOfService = .utility
        thread.start()
    }

    /// In the background the app is suspended mid-ping; time asleep is not a hang.
    func setPaused(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        paused = value; pingSentAt = nil; hang = nil
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        guard !paused else { lock.unlock(); return }
        guard let sent = pingSentAt else {
            pingSentAt = now
            lock.unlock()
            DispatchQueue.main.async { [weak self] in self?.answered() }
            return
        }
        let waited = now - sent
        var record = false
        var refresh: UUID?
        if waited >= Self.threshold {
            if let current = hang {
                if now - current.savedAt >= 2 { refresh = current.id; hang = (current.id, now) }
            } else {
                record = true
            }
        }
        lock.unlock()
        if record {
            let id = log.record(kind: "hang", duration: waited, extra: FreezeDevice.summary(foreground: true))
            lock.lock(); if pingSentAt == sent { hang = (id, now) }; lock.unlock()
        } else if let refresh {
            log.update(refresh, duration: waited)
        }
    }

    private func answered() {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        let finished = hang.flatMap { hang in pingSentAt.map { (hang.id, now - $0) } }
        pingSentAt = nil; hang = nil
        lock.unlock()
        if let finished {
            log.update(finished.0, duration: finished.1)
            log.note(String(format: "Main thread answered again after %.1f s", finished.1))
        }
    }
}

/// The phone and app around an incident.
enum FreezeDevice {
    static func summary(foreground: Bool) -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        var model = "unknown"
        var system = utsname()
        if uname(&system) == 0 {
            model = withUnsafeBytes(of: &system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        }
        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "nominal"
        case .fair: thermal = "fair"
        case .serious: thermal = "serious"
        case .critical: thermal = "critical"
        @unknown default: thermal = "unknown"
        }
        let memory = AppMemory.footprint().map { "\($0 / 1_048_576) MB" } ?? "?"
        return "App \(version) (\(build)) · \(ProcessInfo.processInfo.operatingSystemVersionString) · \(model) · thermal \(thermal) · memory \(memory) · \(foreground ? "foreground" : "background")"
    }
}
