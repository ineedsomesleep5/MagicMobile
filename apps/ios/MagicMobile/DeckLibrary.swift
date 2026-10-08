import Combine
import Foundation

struct DeckLibraryRecord: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var format: String
    var commander: DeckEntry?
    var entries: [DeckEntry]
    var sourceURL: String?
    var revision: Int
    var updatedAt: Date
    var isCloudBacked: Bool

    private enum CodingKeys: String, CodingKey {
        case id, name, format, commander, entries, source, sourceURL, revision, updatedAt, isCloudBacked
    }

    private struct SourcePayload: Codable {
        let kind: String?
        let url: String?
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        format: String = "commander",
        commander: DeckEntry?,
        entries: [DeckEntry],
        sourceURL: String? = nil,
        revision: Int = 1,
        updatedAt: Date = .now,
        isCloudBacked: Bool = false
    ) {
        self.id = id
        self.name = name
        self.format = format
        self.commander = commander
        self.entries = entries
        self.sourceURL = sourceURL
        self.revision = revision
        self.updatedAt = updatedAt
        self.isCloudBacked = isCloudBacked
    }

    init(deck: DeckList, id: String = UUID().uuidString, sourceURL: String? = nil) {
        self.init(id: id, name: deck.name, commander: deck.commander, entries: deck.entries, sourceURL: sourceURL)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try values.decode(String.self, forKey: .name)
        format = try values.decodeIfPresent(String.self, forKey: .format) ?? "commander"
        commander = try values.decodeIfPresent(DeckEntry.self, forKey: .commander)
        entries = try values.decodeIfPresent([DeckEntry].self, forKey: .entries) ?? []
        sourceURL = try values.decodeIfPresent(String.self, forKey: .sourceURL)
            ?? values.decodeIfPresent(SourcePayload.self, forKey: .source)?.url
        revision = try values.decodeIfPresent(Int.self, forKey: .revision) ?? 1
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        isCloudBacked = try values.decodeIfPresent(Bool.self, forKey: .isCloudBacked) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(format, forKey: .format)
        try values.encodeIfPresent(commander, forKey: .commander)
        try values.encode(entries, forKey: .entries)
        if let sourceURL {
            let kind = sourceURL.localizedCaseInsensitiveContains("archidekt") ? "archidekt" : "moxfield"
            try values.encode(SourcePayload(kind: kind, url: sourceURL), forKey: .source)
        } else {
            try values.encode(SourcePayload(kind: "manual", url: nil), forKey: .source)
        }
        try values.encode(revision, forKey: .revision)
        try values.encode(updatedAt, forKey: .updatedAt)
        try values.encode(isCloudBacked, forKey: .isCloudBacked)
    }

    var deckList: DeckList {
        DeckList(name: name, commander: commander, entries: entries)
    }

    var cardCount: Int { deckList.totalCards }
}

extension JSONDecoder {
    static var magicMobileDecks: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = ISO8601DateFormatter().date(from: value) { return date }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date")
        }
        return decoder
    }
}

extension JSONEncoder {
    static var magicMobileDecks: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

@MainActor
final class DeckLibraryStore: ObservableObject {
    @Published private(set) var decks: [DeckLibraryRecord] = []
    @Published var notice: String?

    private let cacheURL: URL
    private var cacheBaseline: Data?
    private var cacheReadFailed = false

    init(cacheURL: URL? = nil) {
        self.cacheURL = cacheURL ?? Self.defaultCacheURL
        loadCache()
    }

    func addLocalDurably(_ deck: DeckList, sourceURL: String? = nil) throws -> DeckLibraryRecord {
        try OnDeviceDeckEditing.validateDraft(deck)
        let record = DeckLibraryRecord(deck: deck, sourceURL: sourceURL)
        let candidate = [record] + decks
        try persistDurably(candidate)
        return record
    }

    /// Draft persistence only: this does not certify card support or engine legality.
    func updateLocalDurably(_ record: DeckLibraryRecord) throws -> DeckLibraryRecord {
        try updateLocalDurably(record.deckList, id: record.id, expectedRevision: record.revision)
    }

    func deleteLocalDurably(id: String) throws {
        guard let record = decks.first(where: { $0.id == id }) else { throw OnDeviceDeckEditing.Error.missingRecord }
        try deleteLocalDurably(id: id, expectedRevision: record.revision)
    }

    /// Draft persistence only: this does not certify card support or engine legality.
    func updateLocalDurably(_ deck: DeckList, id: String, expectedRevision: Int) throws -> DeckLibraryRecord {
        try OnDeviceDeckEditing.validateDraft(deck)
        let index = try localIndex(id: id, expectedRevision: expectedRevision)
        var record = decks[index]
        guard record.revision < Int.max else { throw OnDeviceDeckEditing.Error.staleRevision }
        record.name = deck.name; record.commander = deck.commander; record.entries = deck.entries
        record.revision += 1; record.updatedAt = .now
        var candidate = decks; candidate[index] = record
        try persistDurably(candidate)
        return record
    }

    func deleteLocalDurably(id: String, expectedRevision: Int) throws {
        let index = try localIndex(id: id, expectedRevision: expectedRevision)
        var candidate = decks; candidate.remove(at: index)
        try persistDurably(candidate)
    }

    /// Copies imported/cloud records without mutating their identity or provenance.
    func duplicateLocalDurably(_ record: DeckLibraryRecord, name: String) throws -> DeckLibraryRecord {
        let deck = DeckList(name: name, commander: record.commander, entries: record.entries)
        try OnDeviceDeckEditing.validateDraft(deck)
        let copy = DeckLibraryRecord(name: name, format: record.format, commander: deck.commander,
                                     entries: deck.entries, sourceURL: record.sourceURL)
        try persistDurably([copy] + decks)
        return copy
    }

    private func localIndex(id: String, expectedRevision: Int) throws -> Int {
        guard let index = decks.firstIndex(where: { $0.id == id }) else { throw OnDeviceDeckEditing.Error.missingRecord }
        guard !decks[index].isCloudBacked else { throw OnDeviceDeckEditing.Error.copyRequired }
        guard decks[index].revision == expectedRevision else { throw OnDeviceDeckEditing.Error.staleRevision }
        return index
    }

    private func persistDurably(_ candidate: [DeckLibraryRecord]) throws {
        // Never replace an unreadable cache or another store's newer saved data.
        guard !cacheReadFailed else { throw OnDeviceDeckEditing.Error.unreadableCache }
        let disk = FileManager.default.fileExists(atPath: cacheURL.path) ? try Data(contentsOf: cacheURL) : nil
        guard disk == cacheBaseline else { throw OnDeviceDeckEditing.Error.staleRevision }
        let data = try JSONEncoder.magicMobileDecks.encode(candidate)
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: cacheURL, options: .atomic)
        cacheBaseline = data
        decks = candidate
        publishArtChoices()
    }

    /// Every saved deck's chosen art is what cards drawn by name show (CardArtChoices).
    private func publishArtChoices() {
        CardArtChoices.shared.setLibrary(decks.map { .init(id: "local:\($0.id)", deck: $0.deckList, updated: $0.updatedAt) })
    }

    private func loadCache() {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else { return }
        do {
            let data = try Data(contentsOf: cacheURL)
            decks = try JSONDecoder.magicMobileDecks.decode([DeckLibraryRecord].self, from: data)
            cacheBaseline = data
            publishArtChoices()
        } catch { cacheReadFailed = true; notice = "The saved deck library could not be read. It has not been replaced." }
    }

    private static var defaultCacheURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MagicMobile", isDirectory: true).appendingPathComponent("decks.json")
    }
}
