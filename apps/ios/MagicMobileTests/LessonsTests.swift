import XCTest
import MagicMobileOnDevice
@testable import MagicMobile

/// The lessons' recordings (scripts/lessons/record.py) played through LessonTransport the way the board drives it.
@MainActor
final class LessonsTests: XCTestCase {
    private static let lessons = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("MagicMobile/Resources/Lessons")
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "LessonsTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    private func ids() throws -> [String] {
        let index = try LessonJSON.decode(Data(contentsOf: Self.lessons.appendingPathComponent("lessons.json")))
        return try XCTUnwrap(index["lessons"]?.array).compactMap { $0["id"]?.string }
    }

    private func script(_ id: String) throws -> LessonScript {
        try LessonScript(LessonJSON.decode(Data(contentsOf: Self.lessons.appendingPathComponent("lesson-\(id).json"))))
    }

    /// A clock the test moves by hand, so frames that move on by themselves don't make the test wait.
    private final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 0)
    }

    private func client(_ script: LessonScript, clock: Clock) -> (EngineClient, LessonTransport, LessonRun) {
        let run = LessonRun(script: LessonInfo(id: script.id, title: script.title), defaults: defaults)
        let transport = LessonTransport(script: script, run: run, clock: { clock.now })
        return (EngineClient(transport: transport), transport, run)
    }

    func testEveryLessonPlaysThroughWithItsRecordedMoves() async throws {
        let ids = try ids()
        XCTAssertEqual(ids, ["first-spells", "combat", "stack", "commander", "table"])
        for id in ids {
            let script = try script(id)
            let clock = Clock()
            let (client, transport, _) = client(script, clock: clock)
            let created = try await client.create(configuration: .object([:]))
            let match = try XCTUnwrap(created["matchId"]?.string)
            var moves = 0, steps = 0
            while true {
                steps += 1
                XCTAssertLessThan(steps, 500, "\(id) never finished")
                let poll = try await client.poll(matchID: match, seatID: script.viewer)
                let position = await transport.position
                if poll.phase == "ended" || position.index == position.count - 1 && position.expect == nil && !position.waitsForGotIt { break }
                if position.waitsForGotIt { await transport.release(); continue }
                if let expect = position.expect {
                    let prompt = try XCTUnwrap(poll.prompt, "\(id) frame \(position.index) waits for a move with no question open")
                    _ = try await client.respond(matchID: match, seatID: script.viewer, prompt: prompt, answer: expect)
                    moves += 1
                } else {
                    XCTAssertNil(poll.prompt, "\(id) frame \(position.index) moves on by itself but asks something")
                    clock.now += 2
                }
            }
            XCTAssertEqual(moves, script.frames.filter { $0.expect != nil }.count, id)
            XCTAssertTrue(script.frames.last?.complete == true || script.frames.last?.poll["phase"]?.string == "ended", id)
        }
    }

    func testAWrongMoveIsTurnedDownAndNudges() async throws {
        let script = try script("first-spells")
        let clock = Clock()
        let (client, transport, run) = client(script, clock: clock)
        let created = try await client.create(configuration: .object([:]))
        let match = try XCTUnwrap(created["matchId"]?.string)
        // Past the welcome to the first move: play the Forest.
        var poll = try await client.poll(matchID: match, seatID: script.viewer)
        while await transport.position.expect == nil {
            await transport.release(); clock.now += 2
            poll = try await client.poll(matchID: match, seatID: script.viewer)
        }
        let prompt = try XCTUnwrap(poll.prompt)
        do {
            _ = try await client.respond(matchID: match, seatID: script.viewer, prompt: prompt, answer: MagicMobileOnDevice.EnginePrompt.answer("boolean", .bool(true)))
            XCTFail("A pass instead of the land was accepted")
        } catch MagicMobileOnDevice.EngineError.rejected(let code, _) {
            XCTAssertEqual(code, "lesson_wrong_move")
        }
        await Task.yield()
        XCTAssertEqual(run.nudges, 1)
        let after = await transport.position
        XCTAssertNotNil(after.expect, "The lesson moved on after a wrong move")
    }

    func testEitherOfTwoForestsPaysAndTheRecordingFollows() async throws {
        let script = try script("first-spells")
        let clock = Clock()
        let (client, transport, _) = client(script, clock: clock)
        let created = try await client.create(configuration: .object([:]))
        let match = try XCTUnwrap(created["matchId"]?.string)
        // Play through to the first payment, then pay with the Forest the recording didn't use.
        while true {
            let poll = try await client.poll(matchID: match, seatID: script.viewer)
            let position = await transport.position
            if position.waitsForGotIt { await transport.release(); continue }
            guard let expect = position.expect, let prompt = poll.prompt else { clock.now += 2; continue }
            if prompt.kind == "PLAY_MANA" {
                let recorded = try XCTUnwrap(expect["value"]?.string)
                let view = try XCTUnwrap(poll.snapshot?["gameView"])
                let mine = try XCTUnwrap(view["players"]?.array?.first { $0["name"]?.string == "You" })
                let other = try XCTUnwrap(mine["battlefield"]?.object?.first { $0.key != recorded && $0.value["name"]?.string == "Forest" }?.key)
                _ = try await client.respond(matchID: match, seatID: script.viewer, prompt: prompt, answer: MagicMobileOnDevice.EnginePrompt.answer("uuid", .string(other)))
                let next = try await client.poll(matchID: match, seatID: script.viewer)
                let tapped = next.snapshot?["gameView"]?["players"]?.array?.first { $0["name"]?.string == "You" }?["battlefield"]?[other]?["tapped"]?.bool
                XCTAssertEqual(tapped, true, "The Forest the player tapped shows tapped")
                return
            }
            _ = try await client.respond(matchID: match, seatID: script.viewer, prompt: prompt, answer: expect)
        }
    }

    func testFinishingALessonRemembersIt() async throws {
        let script = try script("table")
        let run = LessonRun(script: LessonInfo(id: script.id, title: script.title), defaults: defaults)
        run.show(try XCTUnwrap(script.frames.last))
        XCTAssertTrue(run.complete)
        XCTAssertEqual(LessonProgress.completed(in: defaults), ["table"])
    }

    func testTheCoachPointsAtTheExpectedCardByName() throws {
        let script = try script("first-spells")
        let frame = try XCTUnwrap(script.frames.first { $0.coach?.spot == "Forest" && $0.expect != nil })
        let spot = LessonSpot.resolve("Forest", poll: frame.poll, expect: frame.expect)
        XCTAssertEqual(spot.ids, [try XCTUnwrap(frame.expect?["value"]?.string)])
        XCTAssertEqual(LessonSpot.resolve("primary", poll: frame.poll, expect: nil).control, "primary")
    }
}
