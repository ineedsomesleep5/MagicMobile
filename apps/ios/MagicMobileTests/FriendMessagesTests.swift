import XCTest
@testable import MagicMobile

/// Messages between friends (FriendMessages.swift; supabase/migrations/20261017180000_friend_messages.sql).
final class FriendMessagesTests: XCTestCase {
    func testParsesTheServerShapes() throws {
        let conversations = try FriendMessageRules.parseConversations(Data(#"""
        [{"username":"Aria_Blade","unread":2,"last":{"id":6,"body":"Want to play?","sentAt":"2026-10-17T19:16:34.123456+00:00","fromMe":false,"read":false}},
         {"username":"ManaFiend","unread":0,"last":{"id":4,"body":"Well played!","sentAt":"2026-10-16T08:00:00+00:00","fromMe":true,"read":true}}]
        """#.utf8))
        XCTAssertEqual(conversations.map(\.username), ["Aria_Blade", "ManaFiend"])
        XCTAssertEqual(conversations[0].unread, 2)
        XCTAssertFalse(conversations[0].last.fromMe)
        let thread = try FriendMessageRules.parseThread(Data(#"""
        {"username":"Aria_Blade","hasMore":true,"messages":[{"id":5,"body":"hi","sentAt":"2026-10-17T19:15:00+00:00","fromMe":true,"read":true}]}
        """#.utf8))
        XCTAssertTrue(thread.hasMore)
        XCTAssertEqual(thread.messages.first?.id, 5)
        let sent = try FriendMessageRules.parseMessage(Data(#"{"id":9,"body":"ok","sentAt":"2026-10-17T19:20:00.5+00:00","fromMe":true,"read":false}"#.utf8))
        XCTAssertEqual(sent.body, "ok")
    }

    func testSanitizeMaskAndMerge() {
        XCTAssertNil(FriendMessageRules.sanitize("   \n\t "))
        XCTAssertEqual(FriendMessageRules.sanitize("  up  for\na game?  "), "up for a game?")
        XCTAssertEqual(FriendMessageRules.sanitize(String(repeating: "x", count: 600))?.count, FriendMessageRules.maxScalars)
        let date = Date(timeIntervalSince1970: 1_000)
        let theirs = FriendMessage(id: 2, body: "well shit", sentAt: date, fromMe: false, read: false)
        let mine = FriendMessage(id: 1, body: "well shit", sentAt: date, fromMe: true, read: true)
        XCTAssertEqual(FriendMessageRules.shown(theirs), "well s***", "a friend's strong language is masked, like table chat")
        XCTAssertEqual(FriendMessageRules.shown(mine), "well shit")
        let read = FriendMessage(id: 2, body: "well shit", sentAt: date, fromMe: false, read: true)
        let merged = FriendMessageRules.merged([theirs, mine], [read, FriendMessage(id: 3, body: "new", sentAt: date, fromMe: false, read: false)])
        XCTAssertEqual(merged.map(\.id), [1, 2, 3])
        XCTAssertTrue(merged[1].read, "the newer copy of a message wins")
    }

    func testFriendsOrderedByLastMessageThenName() {
        let date = Date(timeIntervalSince1970: 1_000)
        let conversations = [
            MessageConversation(username: "Old", unread: 0, last: FriendMessage(id: 3, body: "a", sentAt: date, fromMe: true, read: true)),
            MessageConversation(username: "New", unread: 1, last: FriendMessage(id: 8, body: "b", sentAt: date, fromMe: false, read: false)),
            MessageConversation(username: "Gone", unread: 0, last: FriendMessage(id: 9, body: "c", sentAt: date, fromMe: false, read: true)),
        ]
        let rows = FriendMessageRules.ordered(friends: ["zed", "Old", "New", "amy"], conversations: conversations)
        XCTAssertEqual(rows.map(\.name), ["New", "Old", "amy", "zed"], "conversations newest first, then quiet friends A-Z; ex-friends left out")
        XCTAssertNil(rows[2].conversation)
    }
}
