import XCTest
@testable import MagicMobile

/// Voice chat's shared rules against parity/voice-cases.json (web voiceChat.test.ts, Android VoiceChatRulesTest).
final class VoiceChatRulesTests: XCTestCase {
    private func cases() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../android/core/src/test/resources/parity/voice-cases.json").standardizedFileURL
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func rows(_ key: String, in cases: [String: Any]) -> [[String: Any]] { cases[key] as? [[String: Any]] ?? [] }

    func testMatchesTheParityCases() throws {
        let cases = try cases()
        XCTAssertEqual(VoiceChatRules.speakingLevel, cases["speakingLevel"] as? Double)
        XCTAssertEqual(VoiceChatRules.holdSeconds, cases["holdSeconds"] as? Double)
        for row in rows("channel", in: cases) {
            XCTAssertEqual(VoiceChatRules.channel(epoch: row["epoch"] as? String), row["channel"] as? String, "\(row)")
        }
        for row in rows("account", in: cases) {
            XCTAssertEqual(VoiceChatRules.account(seat: row["seat"] as? String), row["account"] as? String, "\(row)")
        }
        for row in rows("level", in: cases) {
            XCTAssertEqual(VoiceChatRules.isSpeaking(level: (row["level"] as? NSNumber)?.doubleValue ?? -1), row["speaking"] as? Bool, "\(row)")
        }
        for row in rows("hold", in: cases) {
            XCTAssertEqual(VoiceChatRules.stillSpeaking(heardAt: (row["heardAt"] as? NSNumber)?.doubleValue,
                                                        now: (row["now"] as? NSNumber)?.doubleValue ?? 0), row["speaking"] as? Bool, "\(row)")
        }
        for row in rows("shown", in: cases) {
            XCTAssertEqual(VoiceChatRules.shown(switchOn: row["switchOn"] as? Bool ?? false, solo: row["solo"] as? Bool ?? true,
                                                channel: row["channel"] as? Bool ?? false, account: row["account"] as? Bool ?? false,
                                                unavailable: row["unavailable"] as? Bool ?? true), row["shown"] as? Bool, "\(row)")
        }
    }

    func testTheSwitchStaysOffUntilTheServerNamesIt() {
        XCTAssertFalse(AppConfig().isOn(VoiceChatRules.switchName, default: false))
        XCTAssertTrue(AppConfig(switches: [VoiceChatRules.switchName: true]).isOn(VoiceChatRules.switchName, default: false))
        XCTAssertTrue(AppConfig().isOn("stackAutoTuck"))
    }
}
