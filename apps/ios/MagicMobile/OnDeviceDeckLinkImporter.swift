import Foundation

/// No gateway, login, cookies, retries, redirects, scraping, or remote card-name resolution.
/// Archidekt allows use of its undocumented deck endpoint:
/// https://archidekt.com/forum/thread/2832338
/// Moxfield's unauthenticated endpoint returned 403 during research (2026-09-14).
/// Its decoder is fixture-covered, not a claim of currently available provider access.
struct OnDeviceDeckLinkImporter {
    static let maximumBytes = 2 * 1024 * 1024
    let resolver: OnDeviceDeckResolver

    struct Preview {
        let deck: DeckList
        let unresolvedNames: [String]
        var annotations: [OnDeviceDeckEditing.TextAnnotation] = []
    }

    func preview(_ deck: DeckList) throws -> Preview {
        try OnDeviceDeckEditing.validateDraft(deck)
        var unresolved = Set<String>()
        func entry(_ row: DeckEntry) -> DeckEntry {
            let canonical = resolver.canonicalCardName(row.cardName)
            if canonical == nil { unresolved.insert(row.cardName) }
            return DeckEntry(cardName: canonical ?? row.cardName, quantity: row.quantity, section: row.section, printing: row.printing)
        }
        let result = DeckList(name: deck.name, commander: deck.commander.map(entry), entries: deck.entries.map(entry))
        return Preview(deck: result, unresolvedNames: unresolved.sorted())
    }

    /// Review-only parsing retains names, sections and provider export annotations.
    /// The strict play resolver remains separate from importing an editable draft.
    func preview(text: String, name: String) throws -> Preview {
        let imported = try OnDeviceDeckEditing.importText(text, name: name)
        var result = try preview(imported.deck)
        result.annotations = imported.annotations
        return result
    }

    /// The commander the player picked before importing leads the reviewed deck, whether or not the list
    /// marked one. One main-deck copy is promoted (keeping its printing); a card the list marked as commander
    /// instead joins the main deck, except a partner already in the command zone, which stays beside it.
    func preview(_ preview: Preview, commander name: String) throws -> Preview {
        var result = try self.preview(Self.choosingCommander(resolver.canonicalCardName(name) ?? name, in: preview.deck))
        result.annotations = preview.annotations
        return result
    }

    static func choosingCommander(_ name: String, in deck: DeckList) -> DeckList {
        func board(_ entry: DeckEntry) -> String { entry.section.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if deck.commander?.cardName == name { return deck }
        var entries = deck.entries
        var printing: CardPrinting?
        var demotedSection = "deck"
        if let index = entries.firstIndex(where: { $0.cardName == name && ["commander", "commanders"].contains(board($0)) }) {
            // A partner already in the command zone takes the lead; the old lead stays there too.
            printing = entries[index].printing
            entries.remove(at: index)
            demotedSection = "commanders"
        } else if let index = entries.firstIndex(where: { $0.cardName == name && ["main", "mainboard", "deck"].contains(board($0)) }) {
            let row = entries[index]
            printing = row.printing
            if row.quantity > 1 {
                entries[index] = DeckEntry(cardName: row.cardName, quantity: row.quantity - 1, section: row.section, printing: row.printing)
            } else { entries.remove(at: index) }
        }
        if let old = deck.commander {
            entries.insert(DeckEntry(cardName: old.cardName, quantity: old.quantity, section: demotedSection, printing: old.printing), at: 0)
        }
        return DeckList(name: deck.name, commander: DeckEntry(cardName: name, quantity: 1, section: "commanders", printing: printing), entries: entries)
    }

    static func importDeck(url: URL, resolver: OnDeviceDeckResolver, excludeSideboards: Bool = false) async throws -> DeckList {
        try await Self(resolver: resolver).importDeck(url: url.absoluteString, excludeSideboards: excludeSideboards)
    }

    enum Provider { case moxfield, archidekt }
    struct Source {
        let provider: Provider
        let id: String
        let endpoint: URL
    }

    struct ImportError: LocalizedError {
        let message: String
        var errorDescription: String? { message + " Export the deck as text and paste it instead; no cards were imported." }
    }

    /// A share link's query and fragment (`?utm_source=…`, `#title`) are ignored: the request goes to a fixed provider
    /// endpoint built from the deck ID alone (Caleb, 2026-10-22: an Archidekt share link failed on its tracking query).
    /// A link pasted without its scheme is read as HTTPS.
    static func source(for text: String) throws -> Source {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.contains("://") { value = "https://" + value }
        guard value.utf8.count <= 2048, var url = URLComponents(string: value),
              url.scheme == "https", url.user == nil, url.password == nil, url.port == nil,
              !url.percentEncodedPath.contains("%") else {
            throw ImportError(message: "Use an HTTPS public Moxfield or Archidekt deck URL without credentials.")
        }
        url.query = nil
        url.fragment = nil
        let path = url.path.split(separator: "/", omittingEmptySubsequences: false)
        guard path.count >= 3, path[0].isEmpty, path[1] == "decks" else {
            throw ImportError(message: "This is not a supported deck link.")
        }
        let id = String(path[2])
        switch url.host?.lowercased() {
        case "moxfield.com", "www.moxfield.com":
            guard id.range(of: "^[A-Za-z0-9_-]{22}$", options: .regularExpression) != nil,
                  path.count == 3 || (path.count == 4 && path[3].isEmpty) else {
                throw ImportError(message: "Invalid Moxfield deck ID.")
            }
            return Source(provider: .moxfield, id: id, endpoint: URL(string: "https://api2.moxfield.com/v3/decks/all/\(id)")!)
        case "archidekt.com", "www.archidekt.com":
            guard id.range(of: "^[1-9][0-9]{0,14}$", options: .regularExpression) != nil,
                  path.count == 3 || (path.count == 4 && path[3].range(of: "^[A-Za-z0-9_-]*$", options: .regularExpression) != nil) else {
                throw ImportError(message: "Invalid Archidekt deck ID or slug.")
            }
            return Source(provider: .archidekt, id: id, endpoint: URL(string: "https://archidekt.com/api/decks/\(id)/")!)
        default: throw ImportError(message: "Only moxfield.com and archidekt.com deck links are supported.")
        }
    }

    func importDeck(text: String, name: String) throws -> DeckList {
        try resolver.importDeck(text: text, name: name)
    }

    func importDeck(url: String, excludeSideboards: Bool = false, reviewOnly: Bool = false) async throws -> DeckList {
        let source = try Self.source(for: url)
        let data = try await fetchJSON(source.endpoint)
        return try decode(data: data, source: source, excludeSideboards: excludeSideboards, reviewOnly: reviewOnly)
    }

    /// One provider request: no cookies, credentials, cache or redirects, at most 2 MiB of JSON.
    private func fetchJSON(_ endpoint: URL) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: endpoint)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("MagicMobile-DeckImport/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: NoRedirects())
            guard let http = response as? HTTPURLResponse else { throw ImportError(message: "Provider returned no HTTP response.") }
            try Self.validate(response: http, endpoint: endpoint)
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < Self.maximumBytes else { throw ImportError(message: "Provider response exceeds 2 MiB.") }
                data.append(byte)
            }
            return data
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ImportError {
            throw error
        } catch let error as OnDeviceDeckResolver.ResolutionError {
            throw error
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw ImportError(message: "Provider unavailable, timed out, or returned an unsupported response.")
        }
    }

    static func validate(response: HTTPURLResponse, source: Source) throws {
        try validate(response: response, endpoint: source.endpoint)
    }

    static func validate(response: HTTPURLResponse, endpoint: URL) throws {
        guard response.url == endpoint, response.statusCode == 200 else {
            throw ImportError(message: "Provider unavailable (HTTP \(response.statusCode)); private decks, authentication, redirects and bot checks are not supported.")
        }
        guard response.expectedContentLength <= Int64(maximumBytes),
              response.mimeType?.lowercased() == "application/json" else {
            throw ImportError(message: "Provider response is oversized or is not JSON.")
        }
    }

    func decode(data: Data, source: Source, excludeSideboards: Bool = false, reviewOnly: Bool = false) throws -> DeckList {
        guard data.count <= Self.maximumBytes else { throw ImportError(message: "Provider response exceeds 2 MiB.") }
        do {
            let deck: DeckList
            switch source.provider {
            case .moxfield:
                let value = try JSONDecoder().decode(MoxfieldDeck.self, from: data)
                guard value.publicId == source.id, value.visibility.lowercased() == "public" else {
                    throw ImportError(message: "Moxfield deck is private, not public, or has a mismatched ID.")
                }
                var entries: [DeckEntry] = []
                let sections = ["mainboard": "main", "commanders": "commanders", "companions": "companions"]
                for key in value.boards.keys.sorted() {
                    let rows = value.boards[key]!.cards
                    guard let section = sections[key] else {
                        if excludeSideboards && ["sideboard", "maybeboard"].contains(key) {
                            try validateExcluded(rows.values.map { DeckEntry(cardName: $0.card.name, quantity: $0.quantity, section: "main") })
                            continue
                        }
                        if !rows.isEmpty { throw ImportError(message: "Unsupported Moxfield section '\(key)'; it cannot be discarded or treated as a companion.") }
                        continue
                    }
                    for id in rows.keys.sorted() {
                        let row = rows[id]!
                        entries.append(DeckEntry(cardName: row.card.name, quantity: row.quantity, section: section))
                    }
                }
                deck = try checkedDeck(name: value.name, entries: entries, reviewOnly: reviewOnly)
            case .archidekt:
                let value = try JSONDecoder().decode(ArchidektDeck.self, from: data)
                guard String(value.id) == source.id, !value.isPrivate, !value.unlisted else {
                    throw ImportError(message: "Archidekt deck is private, not public, or has a mismatched ID.")
                }
                var categories: [String: Bool] = [:]
                for category in value.categories {
                    guard categories[category.name] == nil else { throw ImportError(message: "Ambiguous Archidekt categories.") }
                    categories[category.name] = category.includedInDeck
                }
                var entries: [DeckEntry] = []
                for row in value.cards {
                    let labels = row.categories ?? []
                    guard labels.allSatisfy({ categories[$0] != nil }) else { throw ImportError(message: "Unknown Archidekt card category.") }
                    let roles = Set(labels.map { $0.lowercased() }.filter { ["commander", "companion", "sideboard", "maybeboard"].contains($0) })
                    guard roles.count <= 1 else { throw ImportError(message: "Conflicting Archidekt card roles.") }
                    guard row.companion != true || !roles.contains("commander") else { throw ImportError(message: "Card marked both commander and companion.") }
                    let companion = row.companion == true || roles.contains("companion")
                    let sideboard = roles.contains("sideboard") || roles.contains("maybeboard")
                    let excludedCategory = !labels.isEmpty && labels.allSatisfy { categories[$0] == false }
                    if sideboard || (excludedCategory && !companion) {
                        guard !roles.contains("commander"), !companion,
                              !sideboard || !labels.contains(where: { categories[$0] == true }) else {
                            throw ImportError(message: "Conflicting included and excluded Archidekt card roles.")
                        }
                        guard excludeSideboards else {
                            throw ImportError(message: "Archidekt contains sideboard or excluded cards; these cannot be silently discarded.")
                        }
                        try validateExcluded([DeckEntry(cardName: row.card.oracleCard.name, quantity: row.quantity, section: "main")])
                        continue
                    }
                    let section = roles.contains("commander") ? "commanders" : (companion ? "companions" : "main")
                    entries.append(DeckEntry(cardName: row.card.oracleCard.name, quantity: row.quantity, section: section))
                }
                deck = try checkedDeck(name: value.name, entries: entries, reviewOnly: reviewOnly)
            }
            return deck
        } catch let error as ImportError { throw error }
        catch let error as OnDeviceDeckResolver.ResolutionError { throw error }
        catch { throw ImportError(message: "Malformed or changed provider deck schema.") }
    }

    /// Opting out of a section does not permit malformed quantities or unknown card names.
    private func validateExcluded(_ entries: [DeckEntry]) throws {
        guard entries.isEmpty == false else { return }
        _ = try resolver.resolve(DeckList(name: "Excluded cards", commander: nil, entries: entries))
    }

    private func checkedDeck(name: String, entries: [DeckEntry], reviewOnly: Bool = false) throws -> DeckList {
        guard !entries.isEmpty, entries.count <= 2000, name.utf8.count <= 512 else { throw ImportError(message: "Deck is empty or too large.") }
        var remaining = entries
        let firstCommander = remaining.firstIndex { $0.section == "commanders" }.map { remaining.remove(at: $0) }
        let raw = DeckList(name: name, commander: firstCommander, entries: remaining)
        if reviewOnly { return try preview(raw).deck }
        let deck = try resolver.canonicalized(raw)
        _ = try resolver.resolve(deck)
        return deck
    }

    /// One public deck in an Archidekt user's list. Private and unlisted decks never appear: the list is
    /// read without signing in, and the deck import accepts only public decks.
    struct ArchidektDeckSummary: Identifiable, Hashable, Decodable {
        let id: Int
        let name: String
        let size: Int?
        let updatedAt: String?
        let isPrivate: Bool?
        let unlisted: Bool?
        enum CodingKeys: String, CodingKey { case id, name, size, updatedAt, isPrivate = "private", unlisted }
        var link: String { "https://archidekt.com/decks/\(id)" }
        /// The day it was last changed, from Archidekt's ISO timestamp.
        var updatedDay: String? { updatedAt.map { String($0.prefix(10)) } }
    }
    struct ArchidektDeckPage: Equatable {
        let decks: [ArchidektDeckSummary]
        let hasMore: Bool
    }

    /// Archidekt's public deck list for a username. Archidekt staff allow use of this API
    /// (https://archidekt.com/forum/thread/2832338); it runs only when the player asks, one page at a time.
    static func archidektDeckListEndpoint(username: String, page: Int) throws -> URL {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.range(of: "^[A-Za-z0-9_.-]{1,64}$", options: .regularExpression) != nil else {
            throw OnDeviceDeckResolver.ResolutionError("Enter an Archidekt username: letters, numbers, dots, dashes or underscores.")
        }
        guard (1...40).contains(page) else { throw OnDeviceDeckResolver.ResolutionError("That's as many decks as one list can show.") }
        var components = URLComponents(string: "https://archidekt.com/api/decks/v3/")!
        components.queryItems = [URLQueryItem(name: "ownerUsername", value: name), URLQueryItem(name: "pageSize", value: "50"), URLQueryItem(name: "page", value: String(page))]
        return components.url!
    }

    func archidektDecks(username: String, page: Int = 1) async throws -> ArchidektDeckPage {
        let data = try await fetchJSON(Self.archidektDeckListEndpoint(username: username, page: page))
        return try Self.decodeArchidektDeckPage(data)
    }

    static func decodeArchidektDeckPage(_ data: Data) throws -> ArchidektDeckPage {
        struct Page: Decodable { let next: String?; let results: [ArchidektDeckSummary] }
        guard let page = try? JSONDecoder().decode(Page.self, from: data), page.results.count <= 200 else {
            throw OnDeviceDeckResolver.ResolutionError("Archidekt returned a deck list this app can't read.")
        }
        let decks = page.results.filter { $0.isPrivate != true && $0.unlisted != true && !$0.name.isEmpty && $0.name.utf8.count <= 512 }
        return ArchidektDeckPage(decks: decks, hasMore: page.next != nil)
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    private struct MoxfieldDeck: Decodable {
        let publicId: String
        let name: String
        let visibility: String
        let boards: [String: Board]
        struct Board: Decodable { let cards: [String: Row] }
        struct Row: Decodable { let quantity: Int; let card: Card }
        struct Card: Decodable { let name: String }
    }
    private struct ArchidektDeck: Decodable {
        let id: Int
        let name: String
        let isPrivate: Bool
        let unlisted: Bool
        let categories: [Category]
        let cards: [Row]
        enum CodingKeys: String, CodingKey { case id, name, isPrivate = "private", unlisted, categories, cards }
        struct Category: Decodable { let name: String; let includedInDeck: Bool }
        struct Row: Decodable { let quantity: Int; let categories: [String]?; let companion: Bool?; let card: Card }
        struct Card: Decodable { let oracleCard: Oracle }
        struct Oracle: Decodable { let name: String }
    }
}
