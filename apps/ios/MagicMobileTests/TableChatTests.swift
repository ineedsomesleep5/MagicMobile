import XCTest
@testable import MagicMobile

/// chat-cases.json: chat text, the language filter, invite links and profile rules.
/// TableChatParityTest.kt checks Android against the same file.
final class TableChatTests: XCTestCase {
    private var root: [String: Any] = [:]

    override func setUpWithError() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("../android/core/src/test/resources/parity/chat-cases.json").standardizedFileURL
        root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func rows(_ key: String) throws -> [[String: Any]] { try XCTUnwrap(root[key] as? [[String: Any]]) }

    func testSanitize() throws {
        XCTAssertEqual(root["maxScalars"] as? Int, TableChatText.maxScalars)
        for item in try rows("sanitize") {
            XCTAssertEqual(TableChatText.sanitize(try XCTUnwrap(item["input"] as? String)), item["output"] as? String,
                           "sanitize · \(item["name"] ?? "")")
        }
    }

    func testFilter() throws {
        for item in try rows("filter") {
            XCTAssertEqual(TableChatFilter.filtered(try XCTUnwrap(item["input"] as? String)), item["output"] as? String)
        }
    }

    func testInviteLinks() throws {
        for item in try rows("links") {
            let link = try XCTUnwrap(item["link"] as? String)
            XCTAssertEqual(URL(string: link).flatMap(TableJoinLink.code(from:)), item["code"] as? String, link)
        }
        let share = try XCTUnwrap(root["shareLink"] as? [String: String])
        XCTAssertEqual(TableJoinLink.url(code: try XCTUnwrap(share["code"]))?.absoluteString, share["url"])
        XCTAssertNil(TableJoinLink.url(code: "nope"))
    }

    func testProfileRules() throws {
        for item in try rows("usernames") {
            XCTAssertEqual(PlayerAccountRules.isValidUsername(try XCTUnwrap(item["name"] as? String)), item["valid"] as? Bool,
                           "\(item["name"] ?? "")")
        }
        for (code, message) in try XCTUnwrap(root["messages"] as? [String: String]) {
            XCTAssertEqual(PlayerAccountRules.message(for: code), message, code)
        }
        for item in try rows("requestResults") {
            XCTAssertEqual(PlayerAccountRules.requestResult(try XCTUnwrap(item["result"] as? String),
                                                            username: try XCTUnwrap(item["username"] as? String)),
                           item["text"] as? String)
        }
    }

    func testFriendRowsDecodeAndOnlyOnlineFriendsWithSeatsAreJoinable() throws {
        let rows = try PlayerFriend.decodeList(Data("""
        [{"id":"0B105EE9-8D80-4E09-B177-6D85B6782C65","username":"Host","relation":"friend","online":true,"last_seen_at":"2026-09-28T04:23:48.401014+00:00","platform":"ios","hosting_code":"abc234","hosting_open_seats":1},
         {"id":"8F11874A-78CA-4BFF-871B-92A3B135862B","username":"Full","relation":"friend","online":true,"last_seen_at":null,"platform":"android","hosting_code":"ABC234","hosting_open_seats":0},
         {"id":"8F11874A-78CA-4BFF-871B-92A3B135862C","username":"Asker","relation":"incoming","online":false,"last_seen_at":null,"platform":null,"hosting_code":null,"hosting_open_seats":null}]
        """.utf8))
        XCTAssertEqual(rows.map(\.joinableCode), ["ABC234", nil, nil])
        XCTAssertEqual(rows.map(\.isFriend), [true, true, false])
        XCTAssertNotNil(rows[0].lastSeenAt)
    }

    func testServerErrorCodes() {
        XCTAssertEqual(SupabaseLite.errorCode(Data(#"{"code":"P0001","details":null,"hint":null,"message":"no_username"}"#.utf8)), "no_username")
        XCTAssertEqual(SupabaseLite.errorCode(Data(#"{"code":422,"error_code":"anonymous_provider_disabled","msg":"Anonymous sign-ins are disabled"}"#.utf8)),
                       "anonymous_provider_disabled")
        XCTAssertEqual(SupabaseLite.code(of: URLError(.notConnectedToInternet)), "offline")
    }
}
