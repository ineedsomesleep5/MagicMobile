import XCTest
@testable import MagicMobile

/// Heat and memory awareness (docs/LIGHTER_ENGINE_PLAN.md step 2): the per-game performance record.
@MainActor
final class PerformanceAwarenessTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "PerformanceAwarenessTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testReadingsKeepPeaksAndHotTime() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var entry = GamePerformanceEntry(started: start, mode: "ranked", aiSkill: 4)
        entry.absorb(at: start, footprint: 300 * 1_048_576, available: 900 * 1_048_576, thermal: 1)
        entry.absorb(at: start + 60, footprint: 520 * 1_048_576, available: 640 * 1_048_576, thermal: 2)
        entry.absorb(at: start + 120, footprint: 410 * 1_048_576, available: nil, thermal: 2)
        entry.absorb(at: start + 180, footprint: nil, available: 700 * 1_048_576, thermal: 1)
        XCTAssertEqual(entry.peakFootprintMB, 520)
        XCTAssertEqual(entry.lowestAvailableMB, 640)
        XCTAssertEqual(entry.hottest, 2)
        XCTAssertEqual(entry.hotMinutes, 2, accuracy: 0.001, "only the minutes ending in a hot reading count")
    }

    /// The report tells a game that heated the phone from a phone already warm or on a charger.
    func testRecordKeepsHowTheGameBegan() throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var entry = GamePerformanceEntry(started: start, mode: "ranked", aiSkill: 6)
        entry.absorb(at: start, footprint: nil, available: nil, thermal: 1)
        entry.absorb(at: start + 60, footprint: nil, available: nil, thermal: 2, onCharger: true)
        entry.absorb(at: start + 120, footprint: nil, available: nil, thermal: 0, lowPowerMode: true)
        XCTAssertEqual(entry.startThermal, 1)
        XCTAssertTrue(entry.line.hasSuffix("hottest serious, hot 1 min, began fair, charging, low power"), entry.line)

        var cool = GamePerformanceEntry(started: start, mode: "ranked", aiSkill: 6)
        cool.absorb(at: start, footprint: nil, available: nil, thermal: 0)
        cool.absorb(at: start + 60, footprint: nil, available: nil, thermal: 1)
        XCTAssertTrue(cool.line.hasSuffix("hottest fair"), "only what is worth saying: \(cool.line)")

        // A record saved by an earlier build has none of these and still loads.
        var saved = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(cool)) as? [String: Any])
        saved["startThermal"] = nil
        let old = try JSONDecoder().decode(GamePerformanceEntry.self, from: JSONSerialization.data(withJSONObject: saved))
        XCTAssertNil(old.startThermal)
        XCTAssertNil(old.charging)
    }

    private func played(minutes: Int = 3, thermal: Int = 1, id: UUID? = UUID(), build: Int? = 78) -> GamePerformanceEntry {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var entry = GamePerformanceEntry(started: start, mode: "ranked", aiSkill: 6)
        entry.id = id
        entry.build = build
        for tick in 0...(minutes * 6) {
            let spent = Double(tick) * 10
            entry.absorb(at: start + spent, footprint: 600 * 1_048_576, available: nil, thermal: tick >= 6 ? thermal : 0,
                         cpu: CPUReading(total: spent * 0.4, board: spent * 0.2, ai: spent * 0.05), battery: 80 - tick / 6)
        }
        return entry
    }

    /// The server's numbers: heat over time, CPU by part as percent of one core, and how the game looked.
    func testReportCarriesTheGamesNumbers() throws {
        var entry = played(thermal: 2)
        entry.turns = 9
        entry.setup = GameBoardNote(board: "arena", table: "volcano", motion: "full", effects: "reduced")
        entry.noteFrames(170, slow: 17)
        let report = try XCTUnwrap(entry.report(device: "iPhone17,2", system: "27.0"))
        XCTAssertEqual(report["p_platform"] as? String, "ios")
        XCTAssertEqual(report["p_build"] as? Int, 78)
        XCTAssertEqual(report["p_device"] as? String, "iPhone17,2")
        XCTAssertEqual(report["p_ai_skill"] as? Int, 6)
        XCTAssertEqual(report["p_table"] as? String, "volcano")
        XCTAssertEqual(report["p_motion"] as? String, "full")
        XCTAssertEqual(report["p_effects"] as? String, "reduced")
        let stats = try XCTUnwrap(report["p_stats"] as? [String: Any])
        XCTAssertEqual(stats["minutes"] as? Double, 3)
        XCTAssertEqual(stats["hottest"] as? Int, 2)
        XCTAssertEqual(stats["secondsToWarm"] as? Double, 60)
        XCTAssertEqual(stats["secondsToHot"] as? Double, 60)
        XCTAssertEqual(stats["warmMinutes"] as? Double, 2.2)
        XCTAssertEqual(stats["hotMinutes"] as? Double, 2.2)
        XCTAssertEqual(stats["cpu"] as? Double, 40)
        XCTAssertEqual(stats["cpuBoard"] as? Double, 20)
        XCTAssertEqual(stats["cpuUpdates"] as? Double, 15)
        XCTAssertEqual(stats["cpuAI"] as? Double, 5)
        XCTAssertEqual(stats["slowFrames"] as? Double, 10)
        XCTAssertEqual(stats["batteryUsed"] as? Int, 3)
        XCTAssertNotNil(try? JSONSerialization.data(withJSONObject: report), "it has to go through JSON")
        XCTAssertTrue(entry.line.hasSuffix("volcano, CPU 40% (board 20, updates 15, AI 5), 10.0% slow frames, battery 3%"), entry.line)
    }

    /// A phone on a charger didn't spend its battery, and a world the server stilled says so.
    func testReportLeavesOutWhatItCantKnow() throws {
        var entry = played()
        entry.setup = GameBoardNote(board: "arena", table: "utopia", motion: "off", effects: "full")
        entry.absorb(at: entry.lastSample ?? Date(), footprint: nil, available: nil, thermal: 0, onCharger: true)
        let stats = try XCTUnwrap(entry.report(device: "d", system: "s")?["p_stats"] as? [String: Any])
        XCTAssertNil(stats["batteryUsed"])
        XCTAssertEqual(stats["charging"] as? Bool, true)
        XCTAssertNil(stats["slowFrames"])
        XCTAssertTrue(entry.line.contains("utopia motion off"), entry.line)
    }

    func testReportsNeedAWholeMinuteAndAnID() {
        XCTAssertNotNil(played(minutes: 1).report(device: "d", system: "s"))
        var short = GamePerformanceEntry(started: Date(), mode: "quick", aiSkill: nil)
        short.id = UUID()
        short.build = 78
        XCTAssertNil(short.report(device: "d", system: "s"), "under a minute says nothing")
        XCTAssertNil(played(id: nil).report(device: "d", system: "s"), "a record from an earlier build")
        XCTAssertNil(played(build: nil).report(device: "d", system: "s"))
    }

    /// A long gap is the app in the background: that time and its CPU don't count against the game.
    func testTimeInTheBackgroundDoesntCount() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var entry = GamePerformanceEntry(started: start, mode: "quick", aiSkill: nil)
        entry.absorb(at: start, footprint: nil, available: nil, thermal: 0, cpu: CPUReading(total: 10, board: 5, ai: 0))
        entry.absorb(at: start + 10, footprint: nil, available: nil, thermal: 0, cpu: CPUReading(total: 14, board: 7, ai: 0))
        entry.absorb(at: start + 1_000, footprint: nil, available: nil, thermal: 1, cpu: CPUReading(total: 60, board: 8, ai: 0))
        entry.absorb(at: start + 1_010, footprint: nil, available: nil, thermal: 1, cpu: CPUReading(total: 62, board: 9, ai: 0))
        XCTAssertEqual(entry.activeSeconds, 20)
        XCTAssertEqual(entry.cpu?.total, 6)
        XCTAssertEqual(entry.cpu?.board, 3)
        XCTAssertEqual(entry.warmMinutes ?? 0, 10.0 / 60, accuracy: 0.001)
        XCTAssertEqual(entry.secondsToWarm, 10)
    }

    /// Each finished game goes once, and what couldn't go waits for the next pass.
    func testFlushSendsEachGameOnce() async {
        let defaults = freshDefaults()
        defaults.set(try? JSONEncoder().encode([played(), played(id: nil), played()]), forKey: GamePerformanceLog.key)
        let log = GamePerformanceLog(defaults: defaults)
        var sent = 0
        await log.flush(device: "d", system: "s") { _ in sent += 1; return sent == 1 ? .sent : .retryLater }
        XCTAssertEqual(sent, 2)
        XCTAssertEqual(log.entries.map { $0.sent == true }, [true, false, false])
        await log.flush(device: "d", system: "s") { _ in .rejected }
        XCTAssertEqual(log.entries.map { $0.sent == true }, [true, false, true], "a refused report isn't sent again; the old record never was")
        var again = 0
        await log.flush(device: "d", system: "s") { _ in again += 1; return .sent }
        XCTAssertEqual(again, 0)
    }

    /// A game cut off (heat, memory, a force quit) still reports, up to its last saved minute.
    func testAGameTheAppNeverEndedStillCounts() async throws {
        let defaults = freshDefaults()
        defaults.set(try JSONEncoder().encode(played(thermal: 3)), forKey: GamePerformanceLog.runningKey)
        let log = GamePerformanceLog(defaults: defaults)
        var reports: [[String: Any]] = []
        await log.flush(device: "d", system: "s") { reports.append($0); return .sent }
        let stats = try XCTUnwrap(reports.first?["p_stats"] as? [String: Any])
        XCTAssertEqual(stats["interrupted"] as? Bool, true)
        XCTAssertEqual(stats["hottest"] as? Int, 3)
        XCTAssertNil(defaults.data(forKey: GamePerformanceLog.runningKey))
        XCTAssertEqual(log.entries.first?.minutes ?? 0, 3, accuracy: 0.001)
        XCTAssertTrue(log.entries.first?.line.hasSuffix("cut short") == true)
    }

    func testBoardNoteArrivesBeforeOrAfterTheGameStarts() {
        let log = GamePerformanceLog(defaults: freshDefaults())
        let note = GameBoardNote(board: "arena", table: "volcano", motion: "half", effects: "full")
        log.noteBoard(note)
        log.begin(mode: "quick", aiSkill: nil, sampling: false)
        log.end()
        XCTAssertEqual(log.entries.last?.setup, note)
        log.begin(mode: "quick", aiSkill: nil, sampling: false)
        log.noteBoard(note)
        log.end()
        XCTAssertEqual(log.entries.last?.setup, note)
        log.begin(mode: "quick", aiSkill: nil, sampling: false)
        log.end()
        XCTAssertNil(log.entries.last?.setup, "a game keeps only its own board")
    }

    /// The engine's search threads are told apart by name; everything else is game updates.
    func testCPUMeterFindsTheSearchThreads() {
        XCTAssertTrue(CPUMeter.isSearchThread("AI-SIM-MAD - 5"))
        XCTAssertFalse(CPUMeter.isSearchThread("ee-522377db2ea8"))
        XCTAssertFalse(CPUMeter.isSearchThread(""))
        let meter = CPUMeter()
        let first = meter.reading()
        let started = DispatchSemaphore(value: 0)
        let finish = DispatchSemaphore(value: 0)
        let search = Thread {
            let until = Date() + 0.1
            var spin = 0
            while Date() < until { spin &+= 1 }
            started.signal()
            finish.wait()
            _ = spin
        }
        search.name = "AI-SIM-MAD - 1"
        search.start()
        started.wait()
        let second = meter.reading()
        finish.signal()
        XCTAssertGreaterThan(second.ai - first.ai, 0.03)
        XCTAssertGreaterThan(second.total, first.total)
        XCTAssertGreaterThanOrEqual(second.board, first.board)
    }

    func testAFrameMoreThanHalfAFrameLateIsSlow() {
        XCTAssertFalse(BoardFrameSampler.isSlow(gap: 0.0167, frame: 0.0167))
        XCTAssertFalse(BoardFrameSampler.isSlow(gap: 0.024, frame: 0.0167))
        XCTAssertTrue(BoardFrameSampler.isSlow(gap: 0.034, frame: 0.0167))
        XCTAssertFalse(BoardFrameSampler.isSlow(gap: 0.034, frame: 0.0333), "a phone in Low Power Mode runs at 30")
    }

    func testLogKeepsTheLastTwentyGames() {
        let log = GamePerformanceLog(defaults: freshDefaults())
        let start = Date(timeIntervalSince1970: 2_000_000)
        for game in 0..<23 {
            let begun = start + Double(game) * 3_600
            log.begin(mode: "quick", aiSkill: 3, now: begun, sampling: false)
            log.noteTurn(game + 1)
            if game == 22 { log.noteMemoryWarning() }
            log.end(now: begun + 900)
        }
        let entries = log.entries
        XCTAssertEqual(entries.count, GamePerformanceLog.limit)
        XCTAssertEqual(entries.last?.turns, 23)
        XCTAssertEqual(entries.last?.minutes ?? 0, 15, accuracy: 0.001)
        XCTAssertEqual(entries.last?.memoryWarnings, 1)
        XCTAssertNil(log.current)
        let section = GamePerformanceLog.section(entries) ?? ""
        XCTAssertTrue(section.contains("20 games"))
        XCTAssertTrue(section.contains("15 min, 23 turns"))
        XCTAssertTrue(section.contains("1 memory warning"))
        XCTAssertNil(GamePerformanceLog.section([]))
    }

    func testHeatHalvesEffectFrames() {
        XCTAssertFalse(DeviceHeat.isHot(.fair))
        XCTAssertTrue(DeviceHeat.isHot(.serious))
        XCTAssertTrue(DeviceHeat.isHot(.critical))
        XCTAssertEqual(DeviceHeat.ambientInterval(hot: false), 1.0 / 30, accuracy: 1e-9)
        XCTAssertEqual(DeviceHeat.ambientInterval(hot: true), 1.0 / 15, accuracy: 1e-9)
    }

    /// Timelines that start at different moments step on the same grid, so the board redraws once per step however
    /// many glows are on screen; the first entry is never after the date asked for.
    func testAmbientTimelinesShareOneGrid() {
        let schedule = AmbientTimelineSchedule(interval: 1.0 / 30)
        let a = Date(timeIntervalSinceReferenceDate: 782_000_000.0123)
        let b = a.addingTimeInterval(0.2471)
        let fromA = Array(schedule.entries(from: a, mode: .normal).prefix(40))
        let fromB = Array(schedule.entries(from: b, mode: .normal).prefix(10))
        XCTAssertLessThanOrEqual(fromA[0], a)
        XCTAssertGreaterThan(fromA[1], a)
        XCTAssertLessThanOrEqual(fromB[0], b)
        XCTAssertGreaterThan(fromB[1], b)
        XCTAssertTrue(zip(fromA, fromA.dropFirst()).allSatisfy { $0 < $1 })
        XCTAssertTrue(fromB.allSatisfy { fromA.contains($0) }, "both timelines tick at exactly the same times")
        // The same answer asked again: a fixed grid, never "now".
        XCTAssertEqual(Array(schedule.entries(from: b, mode: .normal).prefix(10)), fromB)
    }

    func testAmbientLoopsReadTheSharedClock() {
        XCTAssertEqual(AmbientTimelineSchedule.phase(at: Date(timeIntervalSinceReferenceDate: 9), period: 2), 0.5, accuracy: 1e-9)
        XCTAssertEqual(AmbientTimelineSchedule.phase(at: Date(timeIntervalSinceReferenceDate: 8), period: 2), 0, accuracy: 1e-9)
    }

    func testPausedAmbientTimelineDrawsOnce() {
        let date = Date(timeIntervalSinceReferenceDate: 782_000_000.5)
        let entries = Array(AmbientTimelineSchedule(interval: 1.0 / 30, paused: true).entries(from: date, mode: .normal))
        XCTAssertEqual(entries.count, 1)
        XCTAssertLessThanOrEqual(entries[0], date)
    }

    func testBoardRestsAfterFifteenQuietSeconds() {
        let touched = Date(timeIntervalSinceReferenceDate: 1_000)
        XCTAssertEqual(BoardActivity.remaining(lastActivity: touched, now: touched + 5), 10, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(BoardActivity.remaining(lastActivity: touched, now: touched + 15), 0)
    }
}
