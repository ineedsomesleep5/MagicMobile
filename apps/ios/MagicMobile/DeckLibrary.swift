import Foundation
import Security
import SwiftUI
import UniformTypeIdentifiers

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

    var validationMessages: [String] {
        var messages: [String] = []
        if commander == nil { messages.append("Choose a commander.") }
        if cardCount != 100 { messages.append("Commander decks need 100 cards; this list has \(cardCount).") }
        if entries.contains(where: { $0.quantity < 1 }) { messages.append("Every card needs a quantity of at least one.") }
        return messages
    }

    var isBattleReady: Bool { validationMessages.isEmpty }
}

enum DeckLibraryError: LocalizedError {
    case invalidServerURL
    case invalidDeckText
    case invalidFile
    case unauthenticated
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "Enter a valid MagicMobile server URL in Settings before syncing decks."
        case .invalidDeckText:
            return "No cards were found. Paste an exported Commander list with quantities, such as ‘1 Sol Ring’."
        case .invalidFile:
            return "MagicMobile could not read that deck file. Choose a UTF-8 .txt, .dec, or .csv export."
        case .unauthenticated:
            return "Sign in to MagicMobile on this device before using the cloud deck library. Your local decks are still available."
        case .server(let message):
            return message
        }
    }
}

struct DeckLibraryClient {
    let baseURL: URL
    var accessToken: () -> String? = CloudAccessTokenStore.read

    func list() async throws -> [DeckLibraryRecord] {
        let data = try await send(path: "api/decks", method: "GET")
        if let envelope = try? decoder.decode(DeckListEnvelope.self, from: data) { return envelope.decks }
        return try decoder.decode([DeckLibraryRecord].self, from: data)
    }

    func save(_ deck: DeckLibraryRecord, isNew: Bool) async throws -> DeckLibraryRecord {
        let path = isNew ? "api/decks" : "api/decks/\(deck.id)"
        let data = try await send(
            path: path,
            method: isNew ? "POST" : "PUT",
            body: SaveDeckRequest(deck: deck, includeRevision: !isNew)
        )
        if let envelope = try? decoder.decode(DeckEnvelope.self, from: data) { return envelope.deck }
        return try decoder.decode(DeckLibraryRecord.self, from: data)
    }

    func importURL(_ sourceURL: URL) async throws -> DeckLibraryRecord {
        let data = try await send(path: "api/decks/import", method: "POST", body: ImportURLRequest(sourceURL: sourceURL.absoluteString))
        if let envelope = try? decoder.decode(DeckEnvelope.self, from: data) { return envelope.deck }
        return try decoder.decode(DeckLibraryRecord.self, from: data)
    }

    func delete(id: String) async throws {
        _ = try await send(path: "api/decks/\(id)", method: "DELETE")
    }

    private func send<Body: Encodable>(path: String, method: String, body: Body) async throws -> Data {
        var request = try request(path: path, method: method)
        request.httpBody = try JSONEncoder.magicMobileDecks.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await perform(request)
    }

    private func send(path: String, method: String) async throws -> Data {
        try await perform(request(path: path, method: method))
    }

    private func request(path: String, method: String) throws -> URLRequest {
        let url = path.split(separator: "/").reduce(baseURL) { partial, component in
            partial.appendingPathComponent(String(component))
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = accessToken()?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DeckLibraryError.server("The deck server returned an invalid response.")
        }
        if http.statusCode == 401 { throw DeckLibraryError.unauthenticated }
        guard (200..<300).contains(http.statusCode) else {
            let response = try? decoder.decode(DeckAPIError.self, from: data)
            throw DeckLibraryError.server(response?.message ?? response?.error ?? "Deck sync failed (HTTP \(http.statusCode)).")
        }
        return data
    }

    private var decoder: JSONDecoder { .magicMobileDecks }
}

enum CloudAccessTokenStore {
    private static let service = "com.calebfeliciano.magicmobile.cloud"
    private static let account = "supabase-access-token"

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String?) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        guard let token, let data = token.data(using: .utf8) else { return }
        var insert = query
        insert[kSecValueData as String] = data
        SecItemAdd(insert as CFDictionary, nil)
    }
}

private struct DeckListEnvelope: Decodable { let decks: [DeckLibraryRecord] }
private struct DeckEnvelope: Decodable { let deck: DeckLibraryRecord }
private struct DeckAPIError: Decodable { let error: String?; let message: String? }
private struct ImportURLRequest: Encodable { let sourceURL: String }
private struct SaveDeckRequest: Encodable {
    struct Source: Encodable {
        let kind: String
        let url: String?
    }

    let name: String
    let entries: [DeckEntry]
    let commander: DeckEntry?
    let source: Source
    let revision: Int?

    init(deck: DeckLibraryRecord, includeRevision: Bool) {
        name = deck.name
        entries = deck.entries
        commander = deck.commander
        if let url = deck.sourceURL {
            source = Source(kind: url.localizedCaseInsensitiveContains("archidekt") ? "archidekt" : "moxfield", url: url)
        } else {
            source = Source(kind: "manual", url: nil)
        }
        revision = includeRevision ? deck.revision : nil
    }
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

enum DeckFileParser {
    static func parse(data: Data, filename: String, source: String? = nil) throws -> DeckList {
        guard let text = String(data: data, encoding: .utf8) else { throw DeckLibraryError.invalidFile }
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        let normalized = ext == "csv" ? normalizedCSV(text) : text
        guard let deck = DeckImporter.parse(
            text: normalized,
            source: source ?? URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        ) else { throw DeckLibraryError.invalidDeckText }
        return deck
    }

    static func normalizedCSV(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let fields = csvFields(String(rawLine))
            guard fields.count >= 2 else { return nil }
            if fields[0].lowercased().contains("quantity") || fields[0].lowercased() == "qty" { return nil }
            let quantityIndex = fields.firstIndex(where: { Int($0.trimmingCharacters(in: .whitespaces)) != nil })
            guard let quantityIndex, let quantity = Int(fields[quantityIndex].trimmingCharacters(in: .whitespaces)) else { return nil }
            let nameIndex = fields.indices.first(where: { $0 != quantityIndex && !fields[$0].trimmingCharacters(in: .whitespaces).isEmpty })
            guard let nameIndex else { return nil }
            return "\(quantity) \(fields[nameIndex].trimmingCharacters(in: .whitespacesAndNewlines))"
        }.joined(separator: "\n")
    }

    private static func csvFields(_ row: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quoted = false
        for character in row {
            if character == "\"" { quoted.toggle() }
            else if character == "," && !quoted { result.append(current); current = "" }
            else { current.append(character) }
        }
        result.append(current)
        return result
    }
}

@MainActor
final class DeckLibraryStore: ObservableObject {
    @Published private(set) var decks: [DeckLibraryRecord] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var notice: String?

    private let cacheURL: URL

    init(cacheURL: URL? = nil) {
        self.cacheURL = cacheURL ?? Self.defaultCacheURL
        loadCache()
    }

    func refresh(serverURL: String) async {
        guard !isLoading else { return }
        guard let client = client(serverURL) else {
            notice = DeckLibraryError.invalidServerURL.localizedDescription
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let remote = try await client.list()
            let localOnly = decks.filter { !$0.isCloudBacked }
            decks = (remote + localOnly.filter { local in !remote.contains(where: { $0.id == local.id }) })
                .sorted { $0.updatedAt > $1.updatedAt }
            persist()
            notice = nil
        } catch {
            notice = error.localizedDescription
        }
    }

    func addLocal(_ deck: DeckList, sourceURL: String? = nil) -> DeckLibraryRecord {
        let record = DeckLibraryRecord(deck: deck, sourceURL: sourceURL)
        decks.insert(record, at: 0)
        persist()
        return record
    }

    func addLocalDurably(_ deck: DeckList) throws -> DeckLibraryRecord {
        let record = DeckLibraryRecord(deck: deck)
        let candidate = [record] + decks
        let data = try JSONEncoder.magicMobileDecks.encode(candidate)
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: cacheURL, options: .atomic)
        decks = candidate
        return record
    }

    func importURL(_ rawValue: String, serverURL: String) async -> DeckLibraryRecord? {
        guard let sourceURL = URL(string: rawValue), ["https", "http"].contains(sourceURL.scheme?.lowercased()) else {
            notice = "Paste a complete public Archidekt or Moxfield URL."
            return nil
        }
        guard let client = client(serverURL) else {
            notice = DeckLibraryError.invalidServerURL.localizedDescription
            return nil
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let imported = try await client.importURL(sourceURL)
            upsert(imported)
            notice = "Imported \(imported.name)."
            return imported
        } catch {
            notice = error.localizedDescription
            return nil
        }
    }

    func save(_ draft: DeckEditorDraft, serverURL: String) async -> DeckLibraryRecord? {
        guard let record = draft.record else {
            notice = "Add a commander and at least one valid card entry before saving."
            return nil
        }
        isSaving = true
        defer { isSaving = false }
        if let client = client(serverURL) {
            do {
                let saved = try await client.save(record, isNew: !record.isCloudBacked)
                upsert(saved)
                notice = "Saved \(saved.name) to the cloud."
                return saved
            } catch DeckLibraryError.unauthenticated {
                upsert(record)
                notice = "Saved on this iPhone. Sign in to sync it to the cloud."
                return record
            } catch {
                upsert(record)
                notice = "Saved on this iPhone. Cloud sync failed: \(error.localizedDescription)"
                return record
            }
        }
        upsert(record)
        notice = "Saved on this iPhone. Add a valid server URL to enable cloud sync."
        return record
    }

    func delete(_ deck: DeckLibraryRecord, serverURL: String) async {
        decks.removeAll { $0.id == deck.id }
        persist()
        guard deck.isCloudBacked, let client = client(serverURL) else { return }
        do { try await client.delete(id: deck.id) }
        catch { notice = "Removed locally. Cloud deletion failed: \(error.localizedDescription)" }
    }

    private func client(_ rawURL: String) -> DeckLibraryClient? {
        guard let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme?.lowercased()) else { return nil }
        return DeckLibraryClient(baseURL: url)
    }

    private func upsert(_ record: DeckLibraryRecord) {
        decks.removeAll { $0.id == record.id }
        decks.insert(record, at: 0)
        persist()
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let cached = try? JSONDecoder.magicMobileDecks.decode([DeckLibraryRecord].self, from: data) else { return }
        decks = cached
    }

    private func persist() {
        guard let data = try? JSONEncoder.magicMobileDecks.encode(decks) else { return }
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
    }

    private static var defaultCacheURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MagicMobile", isDirectory: true).appendingPathComponent("decks.json")
    }
}

struct DeckEditorDraft: Equatable {
    var id: String
    var name: String
    var commanderName: String
    var rows: [DeckEditorRow]
    var sourceURL: String?
    var revision: Int
    var isCloudBacked: Bool

    init(deck: DeckLibraryRecord? = nil) {
        id = deck?.id ?? UUID().uuidString
        name = deck?.name ?? "New Commander Deck"
        commanderName = deck?.commander?.cardName ?? ""
        rows = (deck?.entries ?? []).map(DeckEditorRow.init)
        sourceURL = deck?.sourceURL
        revision = deck?.revision ?? 1
        isCloudBacked = deck?.isCloudBacked ?? false
    }

    var record: DeckLibraryRecord? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCommander = commanderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanCommander.isEmpty else { return nil }
        let entries = rows.compactMap(\.entry)
        return DeckLibraryRecord(
            id: id,
            name: cleanName,
            commander: DeckEntry(cardName: cleanCommander, quantity: 1, section: "commander"),
            entries: entries,
            sourceURL: sourceURL,
            revision: revision,
            updatedAt: .now,
            isCloudBacked: isCloudBacked
        )
    }
}

struct DeckEditorRow: Identifiable, Equatable {
    var id = UUID()
    var quantity: Int
    var cardName: String
    var section: String

    init(quantity: Int = 1, cardName: String = "", section: String = "deck") {
        self.quantity = quantity
        self.cardName = cardName
        self.section = section
    }

    init(_ entry: DeckEntry) {
        quantity = entry.quantity
        cardName = entry.cardName
        section = entry.section
    }

    var entry: DeckEntry? {
        let name = cardName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard quantity > 0, !name.isEmpty else { return nil }
        return DeckEntry(cardName: name, quantity: quantity, section: section)
    }
}

struct DeckLibraryView: View {
    let serverURL: String
    @Binding var activeDeck: DeckList?
    @Binding var selectedHumanPrecon: PreconDeck
    let portraitModeEnabled: Bool

    @StateObject private var store = DeckLibraryStore()
    @State private var route: [String] = []
    @State private var presentation: DeckPresentation?

    var body: some View {
        NavigationStack(path: $route) {
            GeometryReader { proxy in
                let portrait = GameOrientationMode.isPortraitLayout(size: proxy.size, portraitEnabled: portraitModeEnabled)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        header(portrait: portrait)
                        if let notice = store.notice { noticeBanner(notice) }
                        content(portrait: portrait)
                    }
                    .padding(.bottom, 20)
                }
                .refreshable { await store.refresh(serverURL: serverURL) }
            }
            .navigationDestination(for: String.self) { id in
                if let deck = store.decks.first(where: { $0.id == id }) {
                    DeckDetailView(
                        deck: deck,
                        isActive: activeDeck == deck.deckList,
                        useForBattle: { activeDeck = deck.deckList },
                        edit: { presentation = .editor(deck) },
                        delete: { Task { await store.delete(deck, serverURL: serverURL); route.removeAll() } }
                    )
                }
            }
            .task { await store.refresh(serverURL: serverURL) }
            .sheet(item: $presentation) { item in
                switch item {
                case .importer:
                    DeckImportView(store: store, serverURL: serverURL) { deck in
                        activeDeck = deck.deckList
                    }
                case .editor(let deck):
                    DeckEditorView(store: store, serverURL: serverURL, deck: deck) { saved in
                        activeDeck = saved.deckList
                    }
                }
            }
        }
        .tint(MagicPalette.antiqueGold)
    }

    private func header(portrait: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("SPELLBOOKS")
                        .font(.caption.weight(.black))
                        .foregroundStyle(MagicPalette.antiqueGold)
                    Text("Your Commander decks")
                        .font(.system(size: portrait ? 28 : 32, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                    Text("Import, inspect, edit, and choose the deck you’ll take into battle.")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white.opacity(0.66))
                }
                Spacer(minLength: 8)
                if store.isLoading { ProgressView().tint(MagicPalette.antiqueGold) }
            }
            if portrait {
                HStack(spacing: 8) { importButton; newDeckButton }
            } else {
                HStack(spacing: 8) { importButton; newDeckButton; Spacer() }
            }
        }
    }

    private var importButton: some View {
        Button { presentation = .importer } label: {
            Label("Import", systemImage: "square.and.arrow.down")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(MagicPrimaryButtonStyle(compact: true))
        .accessibilityHint("Import pasted text, a public deck URL, or a deck file")
    }

    private var newDeckButton: some View {
        Button { presentation = .editor(nil) } label: {
            Label("New deck", systemImage: "plus")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(MagicSecondaryButtonStyle(fillsWidth: true, compact: true))
    }

    @ViewBuilder
    private func content(portrait: Bool) -> some View {
        if store.decks.isEmpty && store.isLoading {
            deckSkeletons
        } else if store.decks.isEmpty {
            emptyState
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: portrait ? 158 : 220), spacing: 10)], spacing: 10) {
                ForEach(store.decks) { deck in
                    Button { route.append(deck.id) } label: {
                        DeckLibraryCard(deck: deck, isActive: activeDeck == deck.deckList)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens deck details and editing controls")
                }
            }
        }
        fallbackPrecon
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(MagicPalette.antiqueGold)
            Text("Your spellbook is empty")
                .font(.title3.weight(.black))
                .foregroundStyle(.white)
            Text("Import an Archidekt or Moxfield list, open a deck file, or build one card by card.")
                .font(.callout.weight(.medium))
                .foregroundStyle(.white.opacity(0.68))
                .multilineTextAlignment(.center)
            Button { presentation = .importer } label: { Label("Import your first deck", systemImage: "wand.and.stars") }
                .buttonStyle(MagicPrimaryButtonStyle(compact: true))
        }
        .frame(maxWidth: .infinity)
        .magicPanel(.leather, prominence: .elevated, cornerRadius: 14, padding: 22)
    }

    private var deckSkeletons: some View {
        HStack(spacing: 10) {
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)).frame(maxWidth: .infinity, minHeight: 145)
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityLabel("Loading decks")
    }

    private var fallbackPrecon: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BATTLE-READY PRECON")
                .font(.caption.weight(.black))
                .foregroundStyle(MagicPalette.antiqueGold)
            PreconPicker(title: "Included deck", selection: $selectedHumanPrecon)
            Button { activeDeck = selectedHumanPrecon.deckList } label: {
                Label("Use included deck", systemImage: "checkmark.shield.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(MagicSecondaryButtonStyle(fillsWidth: true, compact: true))
        }
        .magicPanel(.iron, prominence: .quiet, cornerRadius: 12, padding: 12)
    }

    private func noticeBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill").foregroundStyle(MagicPalette.warningAmber)
            Text(text).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.82))
            Spacer(minLength: 0)
            Button { store.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
        }
        .magicPanel(.iron, prominence: .quiet, cornerRadius: 10, padding: 10)
    }
}

private enum DeckPresentation: Identifiable {
    case importer
    case editor(DeckLibraryRecord?)

    var id: String {
        switch self {
        case .importer: return "importer"
        case .editor(let deck): return "editor-\(deck?.id ?? "new")"
        }
    }
}

private struct DeckLibraryCard: View {
    let deck: DeckLibraryRecord
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: "crown.fill").foregroundStyle(MagicPalette.antiqueGold)
                Spacer()
                if isActive { Text("ACTIVE").magicBadge(.positive) }
                else { Text(deck.isBattleReady ? "READY" : "CHECK").magicBadge(deck.isBattleReady ? .positive : .warning) }
            }
            Text(deck.name).font(.system(.headline, design: .serif, weight: .bold)).foregroundStyle(.white).lineLimit(2)
            Text(deck.commander?.cardName ?? "Commander needed").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.68)).lineLimit(2)
            Spacer(minLength: 2)
            HStack {
                Label("\(deck.cardCount)", systemImage: "rectangle.stack.fill")
                Spacer()
                Text(deck.format.uppercased())
            }
            .font(.caption2.weight(.black)).foregroundStyle(MagicPalette.parchment.opacity(0.72))
        }
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
        .magicPanel(isActive ? .oak : .leather, prominence: isActive ? .elevated : .standard, cornerRadius: 12, padding: 13)
    }
}

private struct DeckDetailView: View {
    let deck: DeckLibraryRecord
    let isActive: Bool
    let useForBattle: () -> Void
    let edit: () -> Void
    let delete: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(deck.name).font(.system(size: 30, weight: .bold, design: .serif)).foregroundStyle(.white)
                    Label(deck.commander?.cardName ?? "Commander needed", systemImage: "crown.fill")
                        .font(.headline).foregroundStyle(MagicPalette.antiqueGold)
                    Text("\(deck.cardCount) cards · Revision \(deck.revision)").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.62))
                }
                if !deck.validationMessages.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(deck.validationMessages, id: \.self) { Label($0, systemImage: "exclamationmark.triangle.fill") }
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(MagicPalette.warningAmber)
                    .magicPanel(.iron, prominence: .quiet, cornerRadius: 10, padding: 10)
                }
                HStack(spacing: 8) {
                    Button(action: useForBattle) { Label(isActive ? "Selected" : "Use for battle", systemImage: isActive ? "checkmark" : "shield.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(MagicPrimaryButtonStyle(compact: true)).disabled(isActive)
                    Button(action: edit) { Label("Edit", systemImage: "pencil").frame(maxWidth: .infinity) }
                        .buttonStyle(MagicSecondaryButtonStyle(fillsWidth: true, compact: true))
                }
                LazyVStack(spacing: 1) {
                    ForEach(deck.entries.sorted { $0.cardName.localizedCaseInsensitiveCompare($1.cardName) == .orderedAscending }) { entry in
                        HStack(spacing: 10) {
                            Text("\(entry.quantity)").font(.body.monospacedDigit().weight(.black)).foregroundStyle(MagicPalette.antiqueGold).frame(width: 28, alignment: .trailing)
                            Text(entry.cardName).font(.callout.weight(.semibold)).foregroundStyle(.white)
                            Spacer()
                            if entry.section != "deck" { Text(entry.section.uppercased()).font(.system(size: 8, weight: .black)).foregroundStyle(.white.opacity(0.5)) }
                        }
                        .padding(.horizontal, 12).frame(minHeight: 40).background(.black.opacity(0.18))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                Button(role: .destructive) { confirmDelete = true } label: { Label("Delete deck", systemImage: "trash").frame(maxWidth: .infinity) }
                    .buttonStyle(MagicSecondaryButtonStyle(fillsWidth: true, compact: true))
            }
            .padding(.vertical, 12)
        }
        .navigationTitle("Deck details").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete \(deck.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete deck", role: .destructive, action: delete)
        } message: { Text("This removes the local copy and attempts to remove its cloud copy.") }
    }
}

private struct DeckImportView: View {
    @ObservedObject var store: DeckLibraryStore
    let serverURL: String
    let didImport: (DeckLibraryRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var mode: ImportMode = .text
    @State private var deckName = "Imported Commander Deck"
    @State private var value = ""
    @State private var isFileImporterOpen = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Import method", selection: $mode) {
                        ForEach(ImportMode.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                    }.pickerStyle(.segmented)
                    if mode == .text {
                        TextField("Deck name", text: $deckName).textFieldStyle(GameTextFieldStyle())
                        TextEditor(text: $value)
                            .font(.body.monospaced()).scrollContentBackground(.hidden).foregroundStyle(.white)
                            .padding(8).frame(minHeight: 260).background(.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(MagicPalette.borderBronze.opacity(0.5)))
                            .accessibilityLabel("Deck list text")
                    } else if mode == .url {
                        TextField("https://archidekt.com/decks/...", text: $value)
                            .textInputAutocapitalization(.never).keyboardType(.URL).autocorrectionDisabled().textFieldStyle(GameTextFieldStyle())
                        Text("Public Archidekt and Moxfield links are imported by the MagicMobile server, then saved to your library.")
                            .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.64))
                    } else {
                        Button { isFileImporterOpen = true } label: {
                            Label("Choose .txt, .dec, or .csv file", systemImage: "doc.badge.plus").frame(maxWidth: .infinity, minHeight: 48)
                        }.buttonStyle(MagicSecondaryButtonStyle(fillsWidth: true))
                    }
                    if let notice = store.notice { Text(notice).font(.caption.weight(.semibold)).foregroundStyle(MagicPalette.warningAmber) }
                    Button { importAction() } label: {
                        HStack { if store.isSaving { ProgressView().tint(.white) }; Text(mode == .url ? "Import from URL" : "Import deck") }.frame(maxWidth: .infinity)
                    }.buttonStyle(MagicPrimaryButtonStyle()).disabled(store.isSaving || mode == .file)
                }
                .magicPanel(.leather, prominence: .elevated, cornerRadius: 14, padding: 16).padding(14)
            }
            .background(BattlefieldSurface().ignoresSafeArea())
            .navigationTitle("Import spellbook").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .fileImporter(isPresented: $isFileImporterOpen, allowedContentTypes: [.plainText, .commaSeparatedText, UTType(filenameExtension: "dec") ?? .data]) { result in
                importFile(result)
            }
        }
    }

    private func importAction() {
        if mode == .url {
            Task {
                if let deck = await store.importURL(value, serverURL: serverURL) { didImport(deck); dismiss() }
            }
        } else {
            guard let parsed = DeckImporter.parse(text: value, source: deckName) else { store.notice = DeckLibraryError.invalidDeckText.localizedDescription; return }
            let deck = store.addLocal(parsed)
            didImport(deck); dismiss()
        }
    }

    private func importFile(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else { throw DeckLibraryError.invalidFile }
            defer { url.stopAccessingSecurityScopedResource() }
            let parsed = try DeckFileParser.parse(data: Data(contentsOf: url), filename: url.lastPathComponent)
            let deck = store.addLocal(parsed)
            didImport(deck); dismiss()
        } catch { store.notice = error.localizedDescription }
    }
}

private enum ImportMode: String, CaseIterable, Identifiable {
    case text, url, file
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String { self == .text ? "text.alignleft" : self == .url ? "link" : "doc" }
}

private struct DeckEditorView: View {
    @ObservedObject var store: DeckLibraryStore
    let serverURL: String
    let didSave: (DeckLibraryRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DeckEditorDraft

    init(store: DeckLibraryStore, serverURL: String, deck: DeckLibraryRecord?, didSave: @escaping (DeckLibraryRecord) -> Void) {
        self.store = store; self.serverURL = serverURL; self.didSave = didSave
        _draft = State(initialValue: DeckEditorDraft(deck: deck))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Deck") {
                    TextField("Deck name", text: $draft.name)
                    TextField("Commander", text: $draft.commanderName)
                }
                Section("Cards · \(draft.record?.cardCount ?? 0)") {
                    ForEach($draft.rows) { $row in
                        HStack(spacing: 8) {
                            Stepper("\(row.quantity)", value: $row.quantity, in: 1...99).labelsHidden()
                            Text("\(row.quantity)").font(.body.monospacedDigit().weight(.bold)).frame(width: 24)
                            TextField("Card name", text: $row.cardName)
                        }
                    }
                    .onDelete { draft.rows.remove(atOffsets: $0) }
                    Button { draft.rows.append(DeckEditorRow()) } label: { Label("Add card", systemImage: "plus") }
                }
                if let messages = draft.record?.validationMessages, !messages.isEmpty {
                    Section("Deck check") { ForEach(messages, id: \.self) { Label($0, systemImage: "exclamationmark.triangle.fill").foregroundStyle(MagicPalette.warningAmber) } }
                }
            }
            .scrollContentBackground(.hidden).background(BattlefieldSurface().ignoresSafeArea())
            .navigationTitle("Edit deck").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(store.isSaving ? "Saving…" : "Save") {
                        Task { if let saved = await store.save(draft, serverURL: serverURL) { didSave(saved); dismiss() } }
                    }.disabled(store.isSaving || draft.record == nil)
                }
            }
        }
    }
}
