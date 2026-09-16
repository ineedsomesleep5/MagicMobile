import Foundation
import SwiftUI

/// Display-only interpretation of an already authorized GameLogEntry.message.
/// Never queries cards, retains messages, emits events, or uses an HTML renderer.
struct GameLogPresentation: Equatable {
    enum Role: Equatable { case action, player, card }

    /// Identity and label already disclosed by this log entry. Not lookup authorization.
    struct CardReference: Equatable, Hashable {
        let objectID: UUID
        let name: String
    }

    struct Span: Equatable {
        let text: String
        let role: Role
        let bold: Bool
        let italic: Bool
        var cardReference: CardReference? = nil
    }

    let spans: [Span]
    var plainText: String { spans.map(\.text).joined() }

    private struct Style {
        var role: Role = .action
        var bold = false
        var italic = false
    }

    private struct Frame {
        let name: String
        let previous: Style
        let objectID: UUID?
        let start: Int
    }

    // Tokenize before decoding so encoded angle brackets remain literal text.
    private static let tokens = try! NSRegularExpression(pattern:
        #"(?s)<!--.*?(?:-->|$)|</?([A-Za-z][A-Za-z0-9:-]*)\b(?:[^<>"']|"[^"]*"|'[^']*')*>|&(#(?:[xX][0-9a-fA-F]+|[0-9]+)|[A-Za-z]+);|<(?i:font)\s+[^<>]*$"#)
    private static let attributes = try! NSRegularExpression(pattern:
        #"(?i)\s+([a-z][a-z0-9_-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#)
    // Matches mage.util.GameLog's log palette, not arbitrary CSS or tooltip colors.
    private static let cardColors: Set<String> = [
        "#90ee90", "#ff6347", "#87cefa", "#696969", "#f0e68c", "#daa520", "#b0c4de"
    ]

    init(_ source: String) {
        // Apply the entity decoder's control policy to literal input too, before
        // tokenization so controls cannot disguise markup names or attributes.
        let source = String(source.unicodeScalars.filter { scalar in
            let value = scalar.value
            return !((value < 32 && ![9, 10, 13].contains(value))
                     || (127...159).contains(value) || (0x202A...0x202E).contains(value)
                     || (0x2066...0x2069).contains(value))
        })
        let ns = source as NSString
        var result: [Span] = []
        var style = Style()
        var frames: [Frame] = []
        var hidden: [String] = []
        var pendingCardID: String?
        var cursor = 0
        var textBuffer = ""
        let suppressed: Set<String> = ["script", "style", "iframe", "object", "svg", "math", "head", "template"]
        let blocks: Set<String> = ["br", "p", "div", "li", "ul", "ol", "table", "tr", "td", "hr"]

        func append(_ value: String) {
            guard hidden.isEmpty, !value.isEmpty else { return }
            var text = value
            if let id = pendingCardID {
                // Only a UUID-matching suffix directly after a named card is metadata.
                let pattern = "^[ \\t]*\\[" + id + "\\](?=[\\s.,;:!?()]|$)"
                if let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                    text.removeSubrange(range)
                }
                pendingCardID = nil
            }
            guard !text.isEmpty else { return }
            result.append(Span(text: text, role: style.role, bold: style.bold, italic: style.italic))
        }

        for match in Self.tokens.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            textBuffer += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            cursor = NSMaxRange(match.range)
            let token = ns.substring(with: match.range)
            if token.hasPrefix("&") {
                // Reuse the prompt decoder's entity allowlist/control-character policy.
                // Whitespace entities need special handling because text() trims labels.
                textBuffer += Self.entity(token)
                continue
            }
            append(textBuffer)
            textBuffer = ""
            if token.hasPrefix("<!--") { continue }
            // A truncated font opening tag must not expose its private attributes.
            guard match.range(at: 1).location != NSNotFound else { continue }
            let name = ns.substring(with: match.range(at: 1)).lowercased()
            let closing = token.hasPrefix("</")
            if suppressed.contains(name) {
                if closing {
                    // Closing an ancestor also closes its malformed/unclosed
                    // children. Unrelated closing tags cannot end suppression.
                    if let index = hidden.lastIndex(of: name) { hidden.removeSubrange(index...) }
                } else if !token.hasSuffix("/>") || !["svg", "math"].contains(name) {
                    // HTML containers are not void elements, even with a slash.
                    hidden.append(name)
                }
                continue
            }
            guard hidden.isEmpty else { continue }
            if blocks.contains(name) { append("\n"); continue }
            if name == "img" {
                append(EngineDisplayText.text(token)) // canonical mana alt only; no src/title lookup
                continue
            }
            guard ["font", "i", "b"].contains(name) else { continue }
            if closing {
                guard let index = frames.lastIndex(where: { $0.name == name }) else { continue }
                let frame = frames[index]
                let label = result.dropFirst(frame.start).map(\.text).joined()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                style = frame.previous
                frames.removeSubrange(index...)
                if let id = frame.objectID, !label.isEmpty,
                   label.contains(where: { $0.isLetter }), !label.hasPrefix("[") {
                    pendingCardID = String(id.uuidString.prefix(3))
                    if !["hidden card", "face-down card", "face down card", "card details unavailable"].contains(label.lowercased()) {
                        for position in frame.start..<result.count where result[position].cardReference == nil {
                            result[position].cardReference = CardReference(objectID: id, name: label)
                        }
                    }
                }
            } else if !token.hasSuffix("/>") {
                let attrs = Self.readAttributes(token)
                let id = attrs["object_id"].flatMap(UUID.init(uuidString:))
                frames.append(Frame(name: name, previous: style, objectID: name == "font" ? id : nil,
                                    start: result.count))
                if name == "b" { style.bold = true }
                if name == "i" { style.italic = true }
                if name == "font" {
                    let color = attrs["color"]?.lowercased() ?? ""
                    if id != nil || Self.cardColors.contains(color) { style.role = .card }
                    else if color == "#20b2aa" { style.role = .player }
                }
            }
        }
        append(textBuffer + ns.substring(from: cursor))
        spans = result
    }

    /// URLs are generated locally per span; never trust an href from the message.
    func inspectionURL(at index: Int) -> URL? {
        guard spans.indices.contains(index), spans[index].cardReference != nil else { return nil }
        return URL(string: "magicmobile-log://inspect/\(index)")
    }

    func cardReference(for url: URL) -> CardReference? {
        guard let index = Int(url.lastPathComponent), spans.indices.contains(index),
              inspectionURL(at: index) == url else { return nil }
        return spans[index].cardReference
    }

    private static func readAttributes(_ tag: String) -> [String: String] {
        let ns = tag as NSString
        var values: [String: String] = [:]
        var duplicates: Set<String> = []
        for match in attributes.matches(in: tag, range: NSRange(location: 0, length: ns.length)) {
            let key = ns.substring(with: match.range(at: 1)).lowercased()
            guard let range = (2...4).map({ match.range(at: $0) }).first(where: { $0.location != NSNotFound }) else { continue }
            if values[key] != nil { duplicates.insert(key) }
            values[key] = ns.substring(with: range)
        }
        for key in duplicates { values.removeValue(forKey: key) }
        return values
    }

    private static func entity(_ token: String) -> String {
        if token == "&nbsp;" { return " " }
        if token.hasPrefix("&#") {
            let body = token.dropFirst(2).dropLast()
            let hex = body.first == "x" || body.first == "X"
            if let value = UInt32(hex ? body.dropFirst() : body, radix: hex ? 16 : 10) {
                if value == 160 { return " " }
                if let scalar = UnicodeScalar(value),
                   CharacterSet.whitespacesAndNewlines.contains(scalar),
                   ![11, 12, 133].contains(value) { return String(scalar) }
            }
        }
        return EngineDisplayText.text(token)
    }
}

/// Native Text only. Set usesDarkBackground for the board's always-dark log drawer.
/// Dynamic Type is inherited; VoiceOver receives the same cleaned visible text.
struct GameLogText: View {
    let message: String
    var usesDarkBackground = false
    var onInspect: ((GameLogPresentation.CardReference) -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        let presentation = GameLogPresentation(message)
        let dark = usesDarkBackground || colorScheme == .dark
        let foreground: Color = usesDarkBackground ? .white : .primary
        let player = dark ? Color(red: 0.45, green: 0.86, blue: 0.82) : Color(red: 0, green: 0.34, blue: 0.32)
        let card = dark ? Color(red: 1, green: 0.84, blue: 0.46) : Color(red: 0.40, green: 0.25, blue: 0.04)
        let text = presentation.spans.enumerated().reduce(Text(verbatim: "")) { partial, item in
            let (index, span) = item
            let color = contrast == .increased || differentiateWithoutColor ? foreground
                : (span.role == .player ? player : span.role == .card ? card : foreground)
            var attributed = AttributedString(span.text)
            if onInspect != nil { attributed.link = presentation.inspectionURL(at: index) }
            var fragment = Text(attributed).foregroundColor(color)
            if span.bold || span.role == .player { fragment = fragment.bold() }
            if span.italic || span.role == .card { fragment = fragment.italic() }
            return partial + fragment
        }
        if let onInspect {
            text.environment(\.openURL, OpenURLAction { url in
                guard let reference = presentation.cardReference(for: url) else { return .discarded }
                onInspect(reference)
                return .handled
            })
        } else {
            text.accessibilityLabel(Text(verbatim: presentation.plainText))
        }
    }
}

/// Rules use the same inert tokenizer, but decode escaped markup to plain native
/// text as well. Self references are substituted only after markup is removed.
struct GameRulesPresentation: Equatable {
    static let maximumBytes = 32 * 1024
    static let maximumNormalizationPasses = 8
    static let unavailableText = "Rules unavailable."
    let plainText: String

    init(source: String, cardName: String? = nil, isHidden: Bool = false) {
        guard !isHidden else { plainText = ""; return }
        guard let text = Self.normalized(source, maximumBytes: Self.maximumBytes) else {
            plainText = Self.unavailableText; return
        }
        let name = cardName.flatMap { Self.normalized($0, maximumBytes: 512) }
            .flatMap { $0.isEmpty ? nil : $0 } ?? "This card"
        let replacements = text.components(separatedBy: "{this}").count - 1
        // Bound expansion before allocating repeated self-reference replacements.
        guard text.utf8.count + replacements * (name.utf8.count - 6) <= Self.maximumBytes else {
            plainText = Self.unavailableText; return
        }
        plainText = text.replacingOccurrences(of: "{this}", with: name)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalized(_ source: String, maximumBytes: Int) -> String? {
        guard source.utf8.prefix(maximumBytes + 1).count <= maximumBytes else { return nil }
        var text = source
        for _ in 0..<maximumNormalizationPasses {
            let next = GameLogPresentation(text).plainText
            guard next.utf8.prefix(maximumBytes + 1).count <= maximumBytes else { return nil }
            if next == text { return next }
            text = next
        }
        // Never return partially decoded tags or hidden-region contents at the limit.
        return nil
    }
}

struct GameRulesText: View {
    let source: String
    var cardName: String? = nil
    var isHidden = false

    var body: some View {
        Text(verbatim: GameRulesPresentation(source: source, cardName: cardName, isHidden: isHidden).plainText)
    }
}
