import XCTest
import MagicMobileOnDevice
@testable import MagicMobile

/// turn-clock-cases.json: the online turn timer's rules, packet and rope.
/// TurnClockParityTest.kt checks Android against the same file.
final class TurnClockTests: XCTestCase {
    private var root: MagicMobileOnDevice.JSONValue = .null

    override func setUpWithError() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("../android/core/src/test/resources/parity/turn-clock-cases.json").standardizedFileURL
        root = try MagicMobileOnDevice.JSONValue.decode(Data(contentsOf: url))
    }

    private func number(_ value: MagicMobileOnDevice.JSONValue?) throws -> Double {
        switch value {
        case .integer(let v)?: return Double(v)
        case .number(let v)?: return v
        default: throw EngineError.invalidMessage("Expected a number")
        }
    }
    private func prompt(_ value: MagicMobileOnDevice.JSONValue?) -> TurnClockPrompt? {
        value?.string.map { TurnClockPrompt(id: $0, revision: 1) }
    }
    private func rows(_ value: MagicMobileOnDevice.JSONValue?) throws -> [MagicMobileOnDevice.JSONValue] { try XCTUnwrap(value?.array) }

    func testRules() throws {
        let rules = try XCTUnwrap(root["rules"])
        XCTAssertEqual(TurnClockRules(decision: try number(rules["decision"]), rope: try number(rules["rope"]),
                                      grace: try number(rules["grace"]), strikesToForfeit: Int(try XCTUnwrap(rules["strikesToForfeit"]?.integer)),
                                      resumeFloor: try number(rules["resumeFloor"])), .online)
    }

    func testScenarios() throws {
        for scenario in try rows(root["scenarios"]) {
            let name = scenario["name"]?.string ?? ""
            var clock = TurnClock()
            for step in try rows(scenario["steps"]) {
                let at = try number(step["at"])
                let label = "\(name) @ \(at)"
                if let observe = step["observe"] {
                    let changed = clock.observe(seat: try XCTUnwrap(observe["seat"]?.string), prompt: prompt(observe["prompt"]), now: at)
                    if let expected = step["changed"]?.bool { XCTAssertEqual(changed, expected, label) }
                }
                if let pause = step["pause"]?.bool {
                    let changed = clock.setPaused(pause, now: at)
                    if let expected = step["changed"]?.bool { XCTAssertEqual(changed, expected, label) }
                }
                if let timeout = step["timeout"] {
                    let result = clock.timeout(seat: try XCTUnwrap(timeout["seat"]?.string), prompt: try XCTUnwrap(prompt(timeout["prompt"])),
                                               hasDefault: try XCTUnwrap(timeout["hasDefault"]?.bool), now: at)
                    XCTAssertEqual(result?.rawValue, step["result"]?.string, label)
                }
                if let failed = step["answerFailed"] {
                    clock.answerFailed(seat: try XCTUnwrap(failed["seat"]?.string), prompt: try XCTUnwrap(prompt(failed["prompt"])), now: at)
                }
                if let expired = step["expired"]?.array {
                    XCTAssertEqual(clock.expired(now: at).map(\.seat), expired.compactMap(\.string), label)
                }
                if let entries = step["entries"]?.array {
                    let expected = try entries.map {
                        TurnClockEntry(seat: try XCTUnwrap($0["seat"]?.string), remaining: try number($0["remaining"]),
                                       limit: try number($0["limit"]), strikes: Int(try XCTUnwrap($0["strikes"]?.integer)))
                    }
                    XCTAssertEqual(clock.entries(now: at), expected, label)
                }
                for (seat, count) in step["strikes"]?.object ?? [:] {
                    XCTAssertEqual(clock.strikes(seat), Int(try XCTUnwrap(count.integer)), "\(label) \(seat)")
                }
            }
        }
    }

    func testDefaultAnswers() throws {
        for item in try rows(root["defaultAnswers"]) {
            var shape = try XCTUnwrap(item["prompt"]?.object)
            shape["promptId"] = .string("p"); shape["revision"] = .integer(1); shape["submitted"] = .bool(false)
            shape["min"] = .integer(0); shape["max"] = .integer(1)
            let prompt = try MagicMobileOnDevice.EnginePrompt(.object(shape))
            let expected = item["answer"] == .null ? nil : item["answer"]
            XCTAssertEqual(TurnClock.defaultAnswer(prompt), expected, item["name"]?.string ?? "")
        }
    }

    func testWire() throws {
        for item in try rows(root["wire"]?["valid"]) {
            let packet = try XCTUnwrap(item["packet"])
            let parsed = try TurnClockWire.parse(packet)
            XCTAssertEqual(TurnClockWire.packet(epoch: "E", paused: parsed.paused, entries: parsed.entries), packet, item["name"]?.string ?? "")
        }
        for item in try rows(root["wire"]?["invalid"]) {
            XCTAssertThrowsError(try TurnClockWire.parse(try XCTUnwrap(item["packet"])), item["name"]?.string ?? "")
        }
    }

    func testRopes() throws {
        for item in try rows(root["ropes"]) {
            let name = item["name"]?.string ?? ""
            let board = TurnClockBoard(paused: try XCTUnwrap(item["board"]?["paused"]?.bool), clocks: try rows(item["board"]?["clocks"]).map {
                TurnClockBoard.Clock(seat: try XCTUnwrap($0["seat"]?.string), deadline: try number($0["deadline"]),
                                     limit: try number($0["limit"]), strikes: Int(try XCTUnwrap($0["strikes"]?.integer)))
            })
            let local = item["local"]?.string
            let now = try number(item["now"])
            if let expected = item["rope"], expected != .null {
                XCTAssertEqual(board.rope(localSeat: local, now: now),
                               TurnClockBoard.Rope(seat: try XCTUnwrap(expected["seat"]?.string), isLocal: try XCTUnwrap(expected["isLocal"]?.bool),
                                                   remaining: try number(expected["remaining"]), fraction: try number(expected["fraction"]),
                                                   strikes: Int(try XCTUnwrap(expected["strikes"]?.integer))), name)
            } else {
                XCTAssertNil(board.rope(localSeat: local, now: now), name)
            }
            let until = item["untilRope"] == .null ? nil : try number(item["untilRope"])
            XCTAssertEqual(board.secondsUntilRope(localSeat: local, now: now), until, name)
        }
    }
}
