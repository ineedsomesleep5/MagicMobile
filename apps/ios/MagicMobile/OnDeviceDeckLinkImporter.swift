import Foundation

/// No gateway, login, cookies, retries, redirects, scraping, or remote card-name resolution.
/// Archidekt allows use of its undocumented deck endpoint:
/// https://archidekt.com/forum/thread/2832338
/// Moxfield's unauthenticated endpoint returned 403 during research (2026-09-14).
/// Its decoder is fixture-covered, not a claim of currently available provider access.
struct OnDeviceDeckLinkImporter {
    static let maximumBytes = 2 * 1024 * 1024
    let resolver: OnDeviceDeckResolver

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

    static func source(for text: String) throws -> Source {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.utf8.count <= 2048, let url = URLComponents(string: value),
              url.scheme == "https", url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, !url.percentEncodedPath.contains("%") else {
            throw ImportError(message: "Use an HTTPS public Moxfield or Archidekt deck URL without credentials or query parameters.")
        }
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

    func importDeck(url: String, excludeSideboards: Bool = false) async throws -> DeckList {
        let source = try Self.source(for: url)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: source.endpoint)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("MagicMobile-DeckImport/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: NoRedirects())
            guard let http = response as? HTTPURLResponse else { throw ImportError(message: "Provider returned no HTTP response.") }
            try Self.validate(response: http, source: source)
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < Self.maximumBytes else { throw ImportError(message: "Provider response exceeds 2 MiB.") }
                data.append(byte)
            }
            return try decode(data: data, source: source, excludeSideboards: excludeSideboards)
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
        guard response.url == source.endpoint, response.statusCode == 200 else {
            throw ImportError(message: "Provider unavailable (HTTP \(response.statusCode)); private decks, authentication, redirects and bot checks are not supported.")
        }
        guard response.expectedContentLength <= Int64(maximumBytes),
              response.mimeType?.lowercased() == "application/json" else {
            throw ImportError(message: "Provider response is oversized or is not JSON.")
        }
    }

    func decode(data: Data, source: Source, excludeSideboards: Bool = false) throws -> DeckList {
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
                deck = try checkedDeck(name: value.name, entries: entries)
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
                deck = try checkedDeck(name: value.name, entries: entries)
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

    private func checkedDeck(name: String, entries: [DeckEntry]) throws -> DeckList {
        guard !entries.isEmpty, entries.count <= 2000, name.utf8.count <= 512 else { throw ImportError(message: "Deck is empty or too large.") }
        var remaining = entries
        let firstCommander = remaining.firstIndex { $0.section == "commanders" }.map { remaining.remove(at: $0) }
        let deck = try resolver.canonicalized(DeckList(name: name, commander: firstCommander, entries: remaining))
        _ = try resolver.resolve(deck)
        return deck
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
