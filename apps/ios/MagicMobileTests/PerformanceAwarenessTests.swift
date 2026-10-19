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
