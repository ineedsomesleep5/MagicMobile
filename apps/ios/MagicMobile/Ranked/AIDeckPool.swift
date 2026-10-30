import CryptoKit
import Foundation

/// An AI opponent's deck: the included precons (Core) plus ai-decks.json, built from EDHREC's
/// average decks per bracket (scripts/ranked/build_ai_decks.py). Players may play them too.
struct AIDeck: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let subtitle: String
    let colors: String
    let commander: String
    let bracket: CommanderBracket
    let deckList: DeckList
    /// Hidden deck Power, 1–10 (ai-decks.json `power`, scripts/ranked/deck_power.py); nil when unrated.
    var power: Double? = nil

    /// The setup screen's deck ID when a player picks one of these decks for themselves.
    var playerDeckID: String { "included:\(id)" }
    /// An official precon; ai-decks.json IDs all start with "ai-".
    var isPrecon: Bool { !id.hasPrefix("ai-") }
}

/// ai-decks.json's `power` block (docs/DECK_POWER.md): each deck's Power, Ranked's tier bands and Quick Match's levels.
/// Shared with Android (`DeckPowerData` in Ranked.kt) and web (aiDeckPool.ts); parity/power-cases.json checks all three.
struct DeckPowerData: Decodable, Sendable {
    struct Level: Decodable, Sendable { let power: Double; let skill: Int }
    let closest: Int
    /// How many decks each tier picks among, Bronze to Mythic; `closest` for a tier it leaves out.
    var rankedClosest: [Int]? = nil
    /// Bronze to Mythic: each tier's [low, high] Power band.
    let rankedTiers: [[Double]]
    let quickMatch: [String: Level]
    let decks: [String: Double]

    /// How many of the nearest decks a tier picks among.
    func closest(tier: Int) -> Int { rankedClosest.flatMap { $0.indices.contains(tier) ? $0[tier] : nil } ?? closest }
}

enum AIDeckPool {
    private struct PowerFile: Decodable { let power: DeckPowerData? }

    private struct File: Decodable {
        struct Deck: Decodable {
            struct Entry: Decodable { let name: String; let quantity: Int; let section: String }
            let id: String
            let name: String
            let subtitle: String
            let colors: String
            let commander: String
            let bracket: Int
            let entries: [Entry]
        }
        let decks: [Deck]
    }

    static func decode(_ data: Data) throws -> [AIDeck] {
        try JSONDecoder().decode(File.self, from: data).decks.map { deck in
            let commander = deck.entries.first { $0.section == "commander" }
            return AIDeck(id: deck.id, name: deck.name, subtitle: deck.subtitle, colors: deck.colors, commander: deck.commander,
                          bracket: CommanderBracket(clamping: deck.bracket),
                          deckList: DeckList(name: deck.name,
                                             commander: commander.map { DeckEntry(cardName: $0.name, quantity: 1, section: "commander") },
                                             entries: deck.entries.filter { $0.section != "commander" }
                                                 .map { DeckEntry(cardName: $0.name, quantity: $0.quantity, section: "deck") }))
        }
    }

    private static let bundledFile: Data? = Bundle.main.url(forResource: "ai-decks", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
    /// The file in play: a newer one the server sent (AIDeckUpdates) if there is one, or the app's own.
    private static let deckFile: Data? = bundledFile.map { AIDeckUpdates.installedFile(bundled: $0) ?? $0 }

    /// The `power` block of an ai-decks.json, or nil when it has none.
    static func decodePower(_ data: Data) -> DeckPowerData? { (try? JSONDecoder().decode(PowerFile.self, from: data))?.power }

    /// Power picking's settings from the bundled file.
    static let power: DeckPowerData? = deckFile.flatMap(decodePower)

    /// The bundled bracket decks (ai-decks.json), without the precons.
    static let bracketDecks: [AIDeck] = all.filter { !$0.isPrecon }

    /// Every AI deck: the precons first (Core; their IDs are the precon IDs saved games already use), each with its Power.
    static let all: [AIDeck] = (PreconCatalog.all.map { precon in
        AIDeck(id: precon.id, name: precon.name, subtitle: precon.subtitle, colors: precon.colors,
               commander: precon.commander, bracket: .core, deckList: precon.deckList)
    } + (deckFile.flatMap { try? decode($0) } ?? [])).map { deck in
        var rated = deck
        rated.power = power?.decks[deck.id]
        return rated
    }

    /// Ranked's target Power: the tier's band split in four divisions, IV low to I high; Mythic (division 0) aims at
    /// the middle of its band.
    static func rankedTarget(tier: Int, division: Int, tiers: [[Double]]) -> Double {
        let band = tiers[min(tiers.count - 1, max(0, tier))]
        let (low, high) = (band[0], band[1])
        if division <= 0 { return (low + high) / 2 }
        return low + (high - low) * (Double(4 - min(4, division)) + 0.5) / 4
    }

    /// An AI deck by Power: decks with a Power and a bracket at most `maxBracket` (nil: any), never your commander and
    /// not a recent deck while others remain, then the `closest` nearest the target (ties by id), `roll` picking among
    /// them. Nil when no deck qualifies.
    static func pick(targetPower target: Double, maxBracket: Int?, avoidingCommander commander: String?, recent: [String],
                     in decks: [AIDeck] = all, closest: Int = power?.closest ?? 3,
                     roll: (Int) -> Int = { Int.random(in: 0..<$0) }) -> AIDeck? {
        var candidates = decks.filter { deck in deck.power != nil && maxBracket.map { deck.bracket.rawValue <= $0 } ?? true }
        if let commander, candidates.contains(where: { $0.commander != commander }) {
            candidates.removeAll { $0.commander == commander }
        }
        let fresh = candidates.filter { !recent.contains($0.id) }
        if !fresh.isEmpty { candidates = fresh }
        let near = candidates.sorted { a, b in
            let (da, db) = (abs(a.power! - target), abs(b.power! - target))
            return da != db ? da < db : a.id < b.id
        }.prefix(closest)
        guard !near.isEmpty else { return nil }
        return near[near.startIndex + min(near.count - 1, max(0, roll(near.count)))]
    }

    static func deck(id: String) -> AIDeck? { all.first { $0.id == id } }

    /// Precons, by the ID a player's deck picker saves.
    static func playerDeck(id: String) -> AIDeck? {
        guard id.hasPrefix("included:") else { return nil }
        return bracketDecks.first { $0.playerDeckID == id }
    }

    static func decks(in bracket: CommanderBracket) -> [AIDeck] { all.filter { $0.bracket == bracket } }

    /// The pool for a bracket. cEDH borrows Optimized; an empty bracket borrows its nearest neighbour.
    static func pool(for bracket: Int, in decks: [AIDeck] = all) -> [AIDeck] {
        let wanted = min(4, max(1, bracket))
        for distance in 0...3 {
            for candidate in [wanted - distance, wanted + distance] where (1...4).contains(candidate) {
                let found = decks.filter { $0.bracket.rawValue == candidate }
                if !found.isEmpty { return found }
            }
        }
        return decks
    }

    /// The softest precons in the AI's hands, for Bronze ranked: an equal-skill round-robin of all five (C3, 2026-10-15,
    /// 200 games) put Chaos Incarnate at 36%, Grave Danger 45% and Token Triumph 50%, against First Flight 56% and
    /// Draconic Destruction 62% (docs/cloud/reports/c3.md).
    static let gentlestPrecons: Set<String> = ["chaos-incarnate", "grave-danger", "token-triumph"]

    /// An AI deck for this bracket: never your own commander, and not one of the last few you faced
    /// while others remain. `preconsOnly` keeps to the official precons, and `onlyPrecons` narrows them further
    /// when any of those are present. `roll` picks among what is left (injectable for tests).
    static func pick(bracket: Int, avoidingCommander commander: String?, recent: [String], preconsOnly: Bool = false,
                     onlyPrecons: Set<String>? = nil,
                     in decks: [AIDeck] = all, roll: (Int) -> Int = { Int.random(in: 0..<$0) }) -> AIDeck? {
        var precons = decks.filter(\.isPrecon)
        if let onlyPrecons, precons.contains(where: { onlyPrecons.contains($0.id) }) { precons.removeAll { !onlyPrecons.contains($0.id) } }
        var candidates = pool(for: bracket, in: preconsOnly && !precons.isEmpty ? precons : decks)
        if let commander, candidates.contains(where: { $0.commander != commander }) {
            candidates.removeAll { $0.commander == commander }
        }
        let fresh = candidates.filter { !recent.contains($0.id) }
        if !fresh.isEmpty { candidates = fresh }
        guard !candidates.isEmpty else { return nil }
        return candidates[min(candidates.count - 1, max(0, roll(candidates.count)))]
    }
}

/// A newer ai-decks.json than the app's own, so AI decks and their Power change without a build (docs/SERVER_CONTROLS.md).
/// The server names a file for this card catalogue; the phone checks it, keeps it, and plays with it from the next launch.
/// A missing or bad file leaves the app's own, and the server naming none goes back to it.
enum AIDeckUpdates {
    private struct Header: Decodable { let schemaVersion: Int; let catalogueHash: String; let revision: Int? }

    enum Step: Equatable {
        case keep, remove
        case download(AppConfig.DeckFile)
    }

    static let maxBytes = 5_000_000

    static var installedURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ai-decks.json")
    }

    private static func header(_ file: Data) -> Header? { try? JSONDecoder().decode(Header.self, from: file) }

    /// Saved games and deck choices name decks by ID, so a newer file keeps every deck of the app's own (to retire one,
    /// drop its Power). The publish script checks the card names against the catalogue.
    static func isUsable(_ file: Data, bundled: Data) -> Bool {
        guard let new = header(file), let own = header(bundled), new.schemaVersion == own.schemaVersion,
              new.catalogueHash == own.catalogueHash, new.revision ?? 0 > own.revision ?? 0,
              let decks = try? AIDeckPool.decode(file), let ownDecks = try? AIDeckPool.decode(bundled),
              let power = AIDeckPool.decodePower(file), power.closest > 0, power.rankedTiers.count == 6,
              power.rankedTiers.allSatisfy({ $0.count == 2 }), power.quickMatch.count == 3 else { return false }
        let ids = Set(decks.map(\.id))
        return ids.count == decks.count && ids.isSuperset(of: ownDecks.map(\.id))
            && decks.allSatisfy { deck in
                deck.id.hasPrefix("ai-") && deck.deckList.commander != nil && deck.deckList.entries.reduce(1) { $0 + $1.quantity } == 100
            }
    }

    static func step(for offered: AppConfig.DeckFile?, installedRevision: Int?, bundledRevision: Int) -> Step {
        guard let offered, offered.revision > bundledRevision else { return installedRevision == nil ? .keep : .remove }
        return offered.revision == installedRevision ? .keep : .download(offered)
    }

    static func installedFile(bundled: Data) -> Data? {
        (try? Data(contentsOf: installedURL)).flatMap { isUsable($0, bundled: bundled) ? $0 : nil }
    }

    /// Best effort, and nothing changes until the next launch: a game in progress keeps the decks it started with.
    static func refresh(_ config: AppConfig) async {
        guard let bundled = Bundle.main.url(forResource: "ai-decks", withExtension: "json").flatMap({ try? Data(contentsOf: $0) }),
              let own = header(bundled) else { return }
        let installed = installedFile(bundled: bundled).flatMap { header($0)?.revision }
        switch step(for: config.deckFiles[own.catalogueHash], installedRevision: installed, bundledRevision: own.revision ?? 0) {
        case .keep: return
        case .remove: try? FileManager.default.removeItem(at: installedURL)
        case .download(let offered):
            guard let (file, response) = try? await URLSession.shared.data(from: offered.url),
                  (response as? HTTPURLResponse)?.statusCode == 200, file.count <= maxBytes,
                  SHA256.hash(data: file).map({ String(format: "%02x", $0) }).joined() == offered.sha256,
                  isUsable(file, bundled: bundled) else { return }
            try? FileManager.default.createDirectory(at: installedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? file.write(to: installedURL, options: .atomic)
        }
    }
}
