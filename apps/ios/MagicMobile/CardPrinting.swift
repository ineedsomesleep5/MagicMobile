import Foundation

/// One printing of a card, picked for its artwork. It changes only which picture shows; the
/// rules, the engine's compiled printing and deck validation never read it. Android's
/// CardPrinting (core/CardPrinting.kt) follows the same rules, and parity/printing-cases.json
/// pins both.
struct CardPrinting: Hashable, Sendable {
    /// Lowercase Scryfall set code ("cmm", "plst").
    let setCode: String
    /// Collector number as printed ("400", "107m", "★1").
    let number: String

    init?(set: String, number: String) {
        let set = set.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let number = number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isSetCode(set), Self.isNumber(number) else { return nil }
        self.setCode = set; self.number = number
    }

    /// Letters and digits, 2 to 6 of them ("tmm3", "30a", "plst").
    static func isSetCode(_ value: String) -> Bool {
        (2...6).contains(value.count) && value.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0)) }
    }
    /// Collector numbers carry letters, digits, hyphens and the star and dagger marks.
    static func isNumber(_ value: String) -> Bool {
        guard (1...16).contains(value.count) else { return false }
        return value.unicodeScalars.allSatisfy {
            ($0.isASCII && CharacterSet.alphanumerics.contains($0)) || $0 == "-" || $0 == "★" || $0 == "†"
        }
    }

    /// The offline store's key and the memory key: "set/number".
    var key: String { setCode + "/" + number }
    /// How exports write it: "(CMM) 400".
    var exportSuffix: String { "(\(setCode.uppercased())) \(number)" }
    /// "CMM 400", for a caption.
    var label: String { "\(setCode.uppercased()) \(number)" }

    /// The suffix at the end of a deck-list line: "(CMM) 400" or "(cmm) 400". A set code with no
    /// number does not name one printing, so it gives nil.
    static func parse(suffix: String) -> CardPrinting? {
        let text = suffix.trimmingCharacters(in: .whitespaces)
        guard text.hasPrefix("("), let close = text.firstIndex(of: ")") else { return nil }
        let set = String(text[text.index(after: text.startIndex)..<close])
        let number = String(text[text.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        return CardPrinting(set: set, number: number)
    }

    /// Scryfall's image route for exactly this printing. A double-faced card's other face is `face=back`.
    func imageURL(version: String, back: Bool = false) -> URL? {
        var parts = URLComponents()
        parts.scheme = "https"; parts.host = "api.scryfall.com"
        parts.percentEncodedPath = "/cards/\(Self.encode(setCode))/\(Self.encode(number))"
        var items = [URLQueryItem(name: "format", value: "image"), URLQueryItem(name: "version", value: version)]
        if back { items.append(URLQueryItem(name: "face", value: "back")) }
        parts.queryItems = items
        return parts.url
    }
    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")) ?? value
    }
}
