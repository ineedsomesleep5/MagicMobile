import XCTest
@testable import MagicMobile

/// feedback-cases.json: the Send feedback note, its contact, and the fixed payload (Android FeedbackParityTest, web feedback.test).
final class FeedbackTests: XCTestCase {
    private var root: [String: Any] = [:]

    override func setUpWithError() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("../android/core/src/test/resources/parity/feedback-cases.json").standardizedFileURL
        root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func rows(_ key: String) throws -> [[String: Any]] { try XCTUnwrap(root[key] as? [[String: Any]]) }
    private func text(_ value: Any?) -> String? { value as? String }

    func testCapsMatchTheServer() {
        XCTAssertEqual(root["maxMessage"] as? Int, FeedbackDraft.maxMessage)
        XCTAssertEqual(root["maxContact"] as? Int, FeedbackDraft.maxContact)
    }

    func testMessagesAndContacts() throws {
        for item in try rows("messages") {
            XCTAssertEqual(FeedbackDraft.message(text(item["input"]) ?? ""), text(item["output"]), text(item["name"]) ?? "")
        }
        for item in try rows("contacts") {
            let contact = FeedbackDraft.contact(text(item["input"]) ?? "")
            XCTAssertEqual(contact.ok, item["ok"] as? Bool, text(item["name"]) ?? "")
            XCTAssertEqual(contact.value, text(item["output"]), text(item["name"]) ?? "")
        }
    }

    func testLengthCapsAndCleaning() {
        XCTAssertNil(FeedbackDraft.message(String(repeating: "a", count: FeedbackDraft.maxMessage + 1)))
        XCTAssertEqual(FeedbackDraft.message(String(repeating: "a", count: FeedbackDraft.maxMessage)), String(repeating: "a", count: FeedbackDraft.maxMessage))
        XCTAssertFalse(FeedbackDraft.contact(String(repeating: "a", count: FeedbackDraft.maxContact + 1)).ok)
        XCTAssertTrue(FeedbackDraft.contact(String(repeating: "a", count: FeedbackDraft.maxContact)).ok)
        XCTAssertEqual(FeedbackDraft.chars(FeedbackDraft.cleanMessage(String(repeating: "a", count: FeedbackDraft.maxMessage + 5))), FeedbackDraft.maxMessage)
        XCTAssertEqual(FeedbackDraft.chars(FeedbackDraft.cleanContact(String(repeating: "a", count: FeedbackDraft.maxContact + 10))), FeedbackDraft.maxContact)
        XCTAssertEqual(FeedbackDraft.cleanMessage("a\u{1}b\nc"), "ab\nc")
        XCTAssertEqual(FeedbackDraft.cleanContact("a\nb"), "ab")
    }

    func testPayloadIsTheNoteAndTheDeviceOnly() throws {
        let keys = Set(try XCTUnwrap(root["payloadKeys"] as? [String]))
        for item in try rows("payloads") {
            let params = FeedbackDraft.params(kind: text(item["kind"]) ?? "", message: text(item["message"]) ?? "", contact: text(item["contact"]) ?? "",
                                              platform: text(item["platform"]) ?? "", version: text(item["version"]) ?? "", build: text(item["build"]) ?? "",
                                              device: text(item["device"]) ?? "")
            let name = text(item["name"]) ?? ""
            if item["ok"] as? Bool == true {
                let body = try XCTUnwrap(params, name)
                XCTAssertEqual(Set(body.keys), keys, name)
                XCTAssertFalse(body.keys.contains { $0.localizedCaseInsensitiveContains("deck") }, name)
                XCTAssertEqual(body["p_message"] as? String, text(item["messageOut"]), name)
                if item["contactOut"] is NSNull {
                    XCTAssertTrue(body["p_contact"] is NSNull, name)
                } else {
                    XCTAssertEqual(body["p_contact"] as? String, text(item["contactOut"]), name)
                }
                XCTAssertEqual(body["p_platform"] as? String, text(item["platform"]), name)
            } else {
                XCTAssertNil(params, name)
            }
        }
    }

    func testNotices() throws {
        let notices = try XCTUnwrap(root["notices"] as? [String: String])
        for (code, message) in notices {
            XCTAssertEqual(FeedbackDraft.notice(for: code), message, code)
        }
        XCTAssertEqual(FeedbackDraft.notice(for: "nope"), FeedbackDraft.notice(for: "error"))
        for code in ["invalid_feedback", "too_many_feedback", "not_signed_in"] {
            XCTAssertEqual(PlayerAccountRules.message(for: code), FeedbackDraft.notice(for: code), code)
        }
    }
}
