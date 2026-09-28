import Foundation

/// Table chat's text rules. Android's TableChat.kt applies the same ones;
/// apps/android/core/src/test/resources/parity/chat-cases.json checks both.
enum TableChatText {
    /// Unicode scalars (code points) in one message.
    static let maxScalars = 200

    /// One line of chat: control characters, tabs and line breaks become spaces, runs of spaces
    /// collapse, and the result is trimmed and capped. Nothing is left: nothing is sent.
    static func sanitize(_ raw: String) -> String? {
        var scalars = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in raw.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control, .spaceSeparator, .lineSeparator, .paragraphSeparator:
                pendingSpace = !scalars.isEmpty
            default:
                if pendingSpace { scalars.append(" "); pendingSpace = false }
                scalars.append(scalar)
            }
        }
        let capped = String(String.UnicodeScalarView(scalars.prefix(maxScalars)))
        let trimmed = capped.hasSuffix(" ") ? String(capped.dropLast()) : capped
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Masks strong language in received chat, keeping each word's first letter
/// ("s***"). Only whole words of ASCII letters are checked, so card names such as
/// Cockatrice or Scunthorpe-style words are left alone.
enum TableChatFilter {
    static let words: Set<String> = [
        "ass", "asshole", "bastard", "bitch", "bollocks", "chink", "cock", "cunt", "dick", "dickhead",
        "fag", "faggot", "fuck", "kike", "motherfucker", "nigga", "nigger", "prick", "pussy", "retard",
        "shit", "slut", "spic", "twat", "wanker", "whore",
    ]
    /// Words that start with these are masked whatever follows ("fucking", "shitty").
    static let stems = ["bitch", "cunt", "fagg", "fuck", "motherf", "nigg", "retard", "shit", "slut", "twat", "wank", "whore"]
    static let suffixes = ["s", "es", "ed", "er", "ers", "ing", "y"]

    static func isBlocked(_ word: String) -> Bool {
        let lower = word.lowercased()
        if words.contains(lower) || stems.contains(where: lower.hasPrefix) { return true }
        return suffixes.contains { lower.hasSuffix($0) && words.contains(String(lower.dropLast($0.count))) }
    }

    static func filtered(_ text: String) -> String {
        var result = ""
        var word = ""
        func flush() {
            if !word.isEmpty, isBlocked(word) {
                result += String(word.prefix(1)) + String(repeating: "*", count: word.count - 1)
            } else {
                result += word
            }
            word = ""
        }
        for character in text {
            if character.isASCII, character.isLetter { word.append(character) } else { flush(); result.append(character) }
        }
        flush()
        return result
    }
}

/// Join links for a cross-play table. The site's /join/CODE page opens the app (a universal
/// link when installed) or offers the download; magicmobile://join/CODE opens the app directly.
/// Android's TableLinks reads the same forms (parity/chat-cases.json).
enum TableJoinLink {
    static let host = "magicmobile-downloads.vercel.app"
    static let scheme = "magicmobile"
    /// The relay's table-code alphabet (no 0/O, 1/I).
    static let alphabet = Set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    static func url(code: String) -> URL? {
        guard let code = normalized(code) else { return nil }
        return URL(string: "https://\(host)/join/\(code)")
    }

    static func normalized(_ raw: String) -> String? {
        let code = raw.uppercased()
        return code.count == 6 && code.allSatisfy(alphabet.contains) ? code : nil
    }

    /// The table code in a join link, or nil for any other URL.
    static func code(from url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        if url.scheme?.lowercased() == scheme, url.host?.lowercased() == "join", parts.count == 1 {
            return normalized(parts[0])
        }
        if url.scheme?.lowercased() == "https", url.host?.lowercased() == host, parts.count == 2, parts[0] == "join" {
            return normalized(parts[1])
        }
        return nil
    }
}
