import Foundation
import XCTest
@testable import MagicMobile

/// The freeze log (docs/FREEZE_LOG.md): the stall rules against parity/freeze-cases.json, which Android runs too, and
/// the log's records on disk.
final class FreezeLogTests: XCTestCase {
    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    func testSharedStallCases() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../android/core/src/test/resources/parity/freeze-cases.json").standardizedFileURL
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)
        for item in cases {
            let input = try XCTUnwrap(item["input"] as? [String: Any])
            let result = FreezeRules.stall(
                inGame: input["inGame"] as! Bool, over: input["over"] as! Bool, waitingOnYou: input["waitingOnYou"] as! Bool,
                waitingOnPerson: input["waitingOnPerson"] as? Bool ?? false,
                answerPendingSeconds: (input["answerPendingSeconds"] as? NSNumber)?.doubleValue,
                quietSeconds: (input["quietSeconds"] as! NSNumber).doubleValue, withPeople: input["withPeople"] as! Bool)
            XCTAssertEqual(result, item["expect"] as? String, item["name"] as? String ?? "")
        }
        let asks = try XCTUnwrap(root["askCases"] as? [[String: Any]])
        XCTAssertFalse(asks.isEmpty)
        for item in asks {
            XCTAssertEqual(FreezeRules.worthAsking(kind: item["kind"] as! String, duration: (item["duration"] as? NSNumber)?.doubleValue),
                           item["expect"] as! Bool, item["name"] as? String ?? "")
        }
        let mayAsks = try XCTUnwrap(root["mayAskCases"] as? [[String: Any]])
        XCTAssertFalse(mayAsks.isEmpty)
        for item in mayAsks {
            XCTAssertEqual(FreezeRules.mayAsk(secondsSinceAsked: (item["secondsSinceAsked"] as? NSNumber)?.doubleValue),
                           item["expect"] as! Bool, item["name"] as? String ?? "")
        }
    }

    func testRecordsKeepTheContextAndBreadcrumbsAndSurviveRelaunch() throws {
        let directory = temporaryDirectory()
        var clock: TimeInterval = 100
        let log = FreezeLog(directory: directory, uptime: { clock })
        for index in 1...(FreezeLog.breadcrumbLimit + 5) { clock += 1; log.note("step \(index)") }
        log.setContext("Game: ranked vs AI")
        let id = log.record(kind: "engine-quiet", extra: "App 0.1.1 (60)")
        log.update(id, duration: 3.5)

        let reopened = FreezeLog(directory: directory)
        let incident = try XCTUnwrap(reopened.incidents.last)
        XCTAssertEqual(incident.kind, "engine-quiet")
        XCTAssertEqual(incident.duration, 3.5)
        XCTAssertEqual(incident.context, "App 0.1.1 (60)\nGame: ranked vs AI")
        XCTAssertEqual(incident.breadcrumbs.count, FreezeLog.breadcrumbLimit)
        XCTAssertEqual(incident.breadcrumbs.last, "+85.0s step 85")
        XCTAssertTrue(incident.inGame)
        XCTAssertEqual(reopened.unsent?.id, id)

        reopened.dismiss(id)
        XCTAssertNil(FreezeLog(directory: directory).unsent)
    }

    func testOnlyInGameIncidentsAreAskedAboutAndTheLastFiveAreKept() {
        let log = FreezeLog(directory: temporaryDirectory())
        log.record(kind: "hang")
        XCTAssertNil(log.unsent, "a hang in the menus is kept but never asked about")
        log.setContext("Game: quick vs AI")
        for _ in 1...6 { log.record(kind: "hang") }
        XCTAssertEqual(log.incidents.count, FreezeLog.incidentLimit)
        log.markSent(log.incidents.last!.id)
        XCTAssertEqual(log.unsent?.id, log.incidents[FreezeLog.incidentLimit - 2].id)
    }

    func testReportText() throws {
        let log = FreezeLog(directory: temporaryDirectory(), uptime: { 0 })
        log.note("Answer: Pass (pass_priority)")
        log.setContext("Game: ranked vs AI")
        log.record(kind: "answer-not-accepted", at: Date(timeIntervalSince1970: 1_792_800_000))
        let text = try XCTUnwrap(FreezeLog.section(log.incidents))
        XCTAssertEqual(text, """
        MagicMobile freeze log (1, newest last)

        An answer was never accepted · 2026-10-24T00:00:00Z
        Game: ranked vs AI
        Breadcrumbs (oldest first):
          +0.0s Answer: Pass (pass_priority)
        """)
        XCTAssertNil(FreezeLog.section([]))
    }

    func testAHangIsSavedWhileTheMainThreadIsStillStuck() throws {
        let directory = temporaryDirectory()
        let log = FreezeLog(directory: directory)
        log.setContext("Game: quick vs AI")
        let watchdog = MainThreadWatchdog(log: log)
        watchdog.start()
        // Hold the main thread past the threshold; the watchdog saves the hang before it's released.
        Thread.sleep(forTimeInterval: MainThreadWatchdog.threshold + 1.2)
        XCTAssertEqual(FreezeLog(directory: directory).incidents.first?.kind, "hang")
        // Released: the duration is brought up to date.
        let released = expectation(description: "the watchdog sees the main thread again")
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) { released.fulfill() }
        wait(for: [released], timeout: 5)
        let hang = try XCTUnwrap(log.incidents.first)
        XCTAssertGreaterThanOrEqual(hang.duration ?? 0, MainThreadWatchdog.threshold)
        watchdog.setPaused(true)
    }
}
