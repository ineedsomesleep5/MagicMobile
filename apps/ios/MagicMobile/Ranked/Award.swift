import SwiftUI

/// An award on a profile (mm_my_awards, mm_public_profile `awards`; Caleb, 2026-10-30): a medal that lives on the server,
/// art included, so a new one needs no build (docs/SERVER_CONTROLS.md). Android's Award and the web's Award match it.
struct Award: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let detail: String
    /// The medal's art; without it, or until it loads, a star medal in `tint`.
    var imageURL: URL?
    var tint: Color
    /// 1 plain, 2 a soft glow, 3 a strong glow and a gold ring.
    var rarity: Int
    var note: String?
    var awardedAt: Date?
    /// A trophy, which stands on the Trophies shelf rather than among the awards.
    var shelf = false
    /// False until the player's app has shown it, which it does with a ceremony.
    var seen = true

    static let gold = Color(red: 1, green: 0.8, blue: 0.36)

    /// The rows from the server; one without an id or a name is skipped.
    static func parse(_ rows: [[String: Any]]) -> [Award] {
        rows.compactMap { row in
            guard let id = row["id"] as? String, !id.isEmpty, let name = row["name"] as? String, !name.isEmpty else { return nil }
            let image = (row["imageUrl"] as? String).flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
            return Award(id: id, name: name, detail: row["description"] as? String ?? "", imageURL: image,
                         tint: color(row["tint"] as? String), rarity: min(max((row["rarity"] as? NSNumber)?.intValue ?? 1, 1), 3),
                         note: row["note"] as? String, awardedAt: (row["awardedAt"] as? String).flatMap(PublicProfile.timestamp),
                         shelf: row["shelf"] as? Bool ?? false, seen: row["seen"] as? Bool ?? true)
        }
    }

    /// "#RRGGBB"; anything else is gold.
    static func color(_ hex: String?) -> Color {
        guard let hex, hex.count == 7, hex.hasPrefix("#"), let value = UInt32(hex.dropFirst(), radix: 16) else { return gold }
        return Color(red: Double(value >> 16 & 255) / 255, green: Double(value >> 8 & 255) / 255, blue: Double(value & 255) / 255)
    }

    /// The award's note and the day it was earned.
    var caption: String {
        [note, awardedAt?.formatted(date: .abbreviated, time: .omitted)].compactMap { $0 }.joined(separator: " · ")
    }
}
