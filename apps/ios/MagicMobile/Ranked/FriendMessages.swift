import Foundation

/// Messages between friends (mm_message_*; roadmap release B). Android's FriendMessages.kt matches it.

/// One message in a conversation.
struct FriendMessage: Decodable, Equatable, Identifiable, Sendable {
    let id: Int64
    let body: String
    let sentAt: Date
    let fromMe: Bool
    let read: Bool
}

/// A conversation with a friend: the last message and how many of theirs are unread.
struct MessageConversation: Decodable, Equatable, Identifiable, Sendable {
    let username: String
    let unread: Int
    let last: FriendMessage
    var id: String { username }
}

/// A page of one conversation, oldest first.
struct MessageThread: Decodable, Equatable, Sendable {
    let username: String
    let messages: [FriendMessage]
    let hasMore: Bool
}

enum FriendMessageRules {
    /// Unicode scalars in one message (the server allows 500 characters).
    static let maxScalars = 500
    /// How often an open conversation asks for new messages.
    static let pollSeconds: UInt64 = 5

    /// What gets sent: one tidy line, or nothing.
    static func sanitize(_ raw: String) -> String? { TableChatText.sanitize(raw, limit: maxScalars) }

    /// A friend's message as shown: strong language masked, like table chat. Your own show as typed.
    static func shown(_ message: FriendMessage) -> String { message.fromMe ? message.body : TableChatFilter.filtered(message.body) }

    /// A newer page merged into what's on screen: one copy of each message, oldest first.
    static func merged(_ existing: [FriendMessage], _ page: [FriendMessage]) -> [FriendMessage] {
        var byID: [Int64: FriendMessage] = [:]
        for message in existing + page { byID[message.id] = message }
        return byID.values.sorted { $0.id < $1.id }
    }

    /// Friends ordered for the Messages tab: conversations by their last message (newest first), then friends you
    /// haven't written to yet, alphabetically.
    static func ordered(friends: [String], conversations: [MessageConversation]) -> [(name: String, conversation: MessageConversation?)] {
        let byName = Dictionary(conversations.map { ($0.username, $0) }, uniquingKeysWith: { first, _ in first })
        let talked = conversations.filter { friends.contains($0.username) }.sorted { $0.last.id > $1.last.id }.map { ($0.username, Optional($0)) }
        let quiet = friends.filter { byName[$0] == nil }.sorted { $0.lowercased() < $1.lowercased() }.map { ($0, MessageConversation?.none) }
        return talked + quiet
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(text)"))
        }
        return decoder
    }

    static func parseConversations(_ data: Data) throws -> [MessageConversation] { try decoder().decode([MessageConversation].self, from: data) }
    static func parseThread(_ data: Data) throws -> MessageThread { try decoder().decode(MessageThread.self, from: data) }
    static func parseMessage(_ data: Data) throws -> FriendMessage { try decoder().decode(FriendMessage.self, from: data) }
}
