import Foundation
import zlib

/// Image references only. Loading is explicit and does not alter the engine catalogue.
struct NativeArtworkCatalogue {
    static let maximumBytes = 250 * 1024 * 1024
    static let maximumObjectBytes = 2 * 1024 * 1024
    enum CatalogueError: Error, Equatable, LocalizedError {
        case unsafeURL, invalidResponse, oversized, malformedJSON, decompressionFailed
        var errorDescription: String? {
            switch self {
            case .unsafeURL: return "The artwork catalogue returned an untrusted download address. Please try again later."
            case .invalidResponse: return "Scryfall could not provide the artwork catalogue. Check your connection and try again."
            case .oversized: return "The artwork catalogue exceeded the supported download size. An app update may be needed."
            case .malformedJSON: return "The artwork catalogue was incomplete or unreadable. Please download it again."
            case .decompressionFailed: return "The artwork catalogue could not be unpacked. Please download it again."
            }
        }
    }

    private struct Images {
        let small: URL?
        let normal: URL?
        let large: URL?
        func url(_ size: String) -> URL? {
            switch size { case "small": return small; case "normal": return normal; case "large": return large; default: return nil }
        }
    }
    private var imagesByID: [UUID: Images] = [:]
    private var names: [String: UUID] = [:]
    private var ambiguousNames: Set<String> = []
    private var aliases: [String: UUID] = [:]
    private var ambiguousAliases: Set<String> = []
    private var faceImages: [String: Images] = [:]
    private var faceNamesByID: [UUID: [String]] = [:]
    private var tokens: [UUID: NativeTokenArtwork] = [:]
    private var relations: [UUID: [NativeTokenArtwork]] = [:]
    var cardCount: Int { imagesByID.count }
    var tokenCount: Int { tokens.count }
    var unavailableTokenCount: Int { tokens.values.filter { !$0.hasMatchingMetadata }.count }
    var unavailableTokenNames: [String] {
        tokens.values.filter { !$0.hasMatchingMetadata }.map(\.name).sorted()
    }
    var allTokens: [NativeTokenArtwork] {
        tokens.values.filter(\.hasMatchingMetadata).sorted {
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func imageURL(name: String, size: String) -> URL? {
        let key = Self.key(name)
        guard !ambiguousNames.contains(key) else { return nil }
        if names[key] == nil, !ambiguousAliases.contains(key), let images = faceImages[key] {
            return images.url(size)
        }
        guard let id = id(for: name) else { return nil }
        return imageURL(id: id, size: size)
    }
    func additionalFaceNames(for requestedNames: [String]) -> [String] {
        let requested = Set(requestedNames.map(Self.key))
        var result: Set<String> = []
        for name in requestedNames {
            guard let cardID = id(for: name) else { continue }
            for face in faceNamesByID[cardID] ?? [] {
                let key = Self.key(face)
                guard !requested.contains(key), !ambiguousAliases.contains(key),
                      id(for: face) == cardID, faceImages[key] != nil else { continue }
                result.insert(face)
            }
        }
        return result.sorted()
    }
    func imageURL(id: UUID, size: String) -> URL? { imagesByID[id]?.url(size) }
    func token(id: UUID) -> NativeTokenArtwork? { tokens[id] }
    /// Bounded on-demand lookup for a visible token name. Search is only invoked
    /// by the consent-aware artwork actor; never for hidden or incomplete views.
    static func searchToken(name: String, typeLine: String, oracleText: String, power: String?, toughness: String?,
                            colors: [String], quality: NativeArtworkQuality,
                            transport: any DeckStudioScryfallHTTP = DeckStudioScryfallHTTPTransport(),
                            budget: DeckStudioScryfallBudget = .shared) async throws -> (NativeTokenArtwork, URL)? {
        let name = NativeAssetStore.tokenArtworkName(name)
        guard !name.isEmpty, name.utf8.count <= 120,
              !name.contains("\"") && !name.contains("\\"),
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        var catalogue = Self()
        for page in 1...3 {
            try Task.checkCancellation()
            var parts = URLComponents(string: "https://api.scryfall.com/cards/search")!
            parts.queryItems = [.init(name: "q", value: "!\"\(name)\" t:token"),
                                .init(name: "unique", value: "cards"), .init(name: "page", value: String(page))]
            let data: Data
            do {
                try await budget.reserve()
                data = try await transport.send(request(parts.url!))
            } catch DeckStudioScryfallError.http(404) { return nil }
            guard data.count <= 4 * 1024 * 1024,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["object"] as? String == "list", let rows = object["data"] as? [[String: Any]],
                  rows.count <= 200, let more = object["has_more"] as? Bool else { throw CatalogueError.invalidResponse }
            for row in rows {
                try Task.checkCancellation()
                // The exact-name search also returns split/double-faced token
                // printings (e.g. "Snake // Zombie"). A visible plain token does
                // not disclose which face or printing produced it, so only flat
                // token rows are eligible for this on-demand route.
                guard row["layout"] as? String == "token" else { continue }
                try catalogue.accept(JSONSerialization.data(withJSONObject: row))
            }
            if !more { break }
            if page == 3 { return nil } // incomplete candidates cannot establish unique identity
        }
        guard let match = NativeAssetStore.matchTokenArtwork(catalogue.allTokens, name: name, typeLine: typeLine,
                                                               oracleText: oracleText, power: power, toughness: toughness,
                                                               colors: colors) else { return nil }
        if let url = catalogue.imageURL(id: match.id, size: quality.imageSizeString) { return (match, url) }
        let equivalent = catalogue.allTokens.first {
            $0.name == match.name && $0.typeLine == match.typeLine && $0.oracleText == match.oracleText &&
            $0.power == match.power && $0.toughness == match.toughness && $0.colors == match.colors &&
            catalogue.imageURL(id: $0.id, size: quality.imageSizeString) != nil
        }
        guard let equivalent, let url = catalogue.imageURL(id: equivalent.id, size: quality.imageSizeString) else { return nil }
        return (equivalent, url)
    }
    func relatedTokens(name: String) -> [NativeTokenArtwork] {
        guard let id = id(for: name) else { return [] }
        // Oracle bulk chooses one printing per Oracle ID. A related printing may be
        // absent: retain its explicit ID/name, never substitute a similarly named token.
        return (relations[id] ?? []).map { tokens[$0.id] ?? $0 }
    }
    private func id(for name: String) -> UUID? {
        let key = Self.key(name)
        guard !ambiguousNames.contains(key) else { return nil }
        return names[key] ?? (ambiguousAliases.contains(key) ? nil : aliases[key])
    }
    private static func key(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    /// Resolve deck artwork in bounded collections instead of one named request
    /// and image redirect per card. Exact token IDs retain their identity.
    static func load(names: [String], includeTokens: Bool,
                     transport: any DeckStudioScryfallHTTP = DeckStudioScryfallHTTPTransport(),
                     budget: DeckStudioScryfallBudget = .shared) async throws -> Self {
        let names = try NativeAssetDownloads.names(names)
        var result = Self()
        for start in stride(from: 0, to: names.count, by: 75) {
            try Task.checkCancellation()
            let batch = Array(names[start..<min(start + 75, names.count)])
            try await result.fetchCollection(batch.map { ["name": $0] }, transport: transport, budget: budget)
        }
        if includeTokens {
            let ids = Set(names.flatMap { result.relatedTokens(name: $0).map(\.id) }).sorted { $0.uuidString < $1.uuidString }
            for start in stride(from: 0, to: ids.count, by: 75) {
                try Task.checkCancellation()
                let batch = ids[start..<min(start + 75, ids.count)]
                try await result.fetchCollection(batch.map { ["id": $0.uuidString.lowercased()] }, transport: transport, budget: budget)
            }
        }
        return result
    }

    private mutating func fetchCollection(_ identifiers: [[String: String]], transport: any DeckStudioScryfallHTTP,
                                          budget: DeckStudioScryfallBudget) async throws {
        guard (1...75).contains(identifiers.count) else { throw CatalogueError.invalidResponse }
        var request = try Self.request(URL(string: "https://api.scryfall.com/cards/collection")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["identifiers": identifiers])
        try await budget.reserve()
        let data = try await transport.send(request)
        guard data.count <= 4 * 1024 * 1024,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["object"] as? String == "list", object["has_more"] as? Bool != true,
              let cards = object["data"] as? [[String: Any]], cards.count <= identifiers.count else {
            throw CatalogueError.invalidResponse
        }
        for card in cards { try accept(JSONSerialization.data(withJSONObject: card)) }
    }

    /// Reuse today's compressed index when checking another download scope.
    /// The cache is disposable; downloaded artwork remains in Application Support.
    static func load() async throws -> Self {
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MagicMobile-ArtworkIndex-v1", isDirectory: true)
        let cachedFile = cache.appendingPathComponent("oracle.json.gz")
        if let modified = try? cachedFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           Date().timeIntervalSince(modified) >= 0, Date().timeIntervalSince(modified) < 24 * 60 * 60,
           let existing = try? parse(file: cachedFile) { return existing }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 600
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await DeckStudioScryfallBudget.shared.reserve()
            let indexURL = URL(string: "https://api.scryfall.com/bulk-data")!
            let (bytes, response) = try await session.bytes(for: request(indexURL), delegate: BoundedTransfer())
            defer { bytes.task.cancel() }
            try validate(response, host: "api.scryfall.com", limit: 1024 * 1024)
            var index = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard index.count < 1024 * 1024 else { throw CatalogueError.oversized }
                index.append(byte)
            }
            let downloadURL = try bulkURL(index)
            let (file, bulkResponse) = try await session.download(for: request(downloadURL), delegate: BoundedTransfer())
            defer { try? FileManager.default.removeItem(at: file) }
            try Task.checkCancellation()
            try validate(bulkResponse, host: "data.scryfall.io", limit: maximumBytes)
            // Parsing happens away from the main actor, in fixed-size decompressed chunks.
            let catalogue = try parse(file: file)
            // Validate before replacing the cache; leave the previous copy on failure.
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            let staging = cache.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: staging) }
            try FileManager.default.copyItem(at: file, to: staging)
            if FileManager.default.fileExists(atPath: cachedFile.path) {
                _ = try FileManager.default.replaceItemAt(cachedFile, withItemAt: staging)
            } else { try FileManager.default.moveItem(at: staging, to: cachedFile) }
            return catalogue
        } onCancel: { session.invalidateAndCancel() }
    }

    static func isAllowed(_ url: URL, host: String) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return parts.scheme?.lowercased() == "https" && parts.host?.lowercased() == host &&
            parts.user == nil && parts.password == nil && parts.fragment == nil &&
            (parts.port == nil || parts.port == 443)
    }
    private static func request(_ url: URL) throws -> URLRequest {
        guard isAllowed(url, host: "api.scryfall.com") || isAllowed(url, host: "data.scryfall.io") else { throw CatalogueError.unsafeURL }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.httpShouldHandleCookies = false
        request.setValue("MagicMobile-OfflineArtwork/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json,application/gzip,application/octet-stream", forHTTPHeaderField: "Accept")
        return request
    }
    private static func validate(_ response: URLResponse, host: String, limit: Int) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let url = http.url, isAllowed(url, host: host),
              ["application/json", "application/x-ndjson", "application/gzip", "application/x-gzip", "application/octet-stream"].contains(http.mimeType?.lowercased() ?? "") else { throw CatalogueError.invalidResponse }
        guard response.expectedContentLength <= Int64(limit) else { throw CatalogueError.oversized }
    }
    static func bulkURL(_ data: Data) throws -> URL {
        struct Index: Decodable {
            struct Entry: Decodable { let type: String; let download_uri: String?; let jsonl_download_uri: String? }
            let data: [Entry]
        }
        let index = try JSONDecoder().decode(Index.self, from: data)
        guard let entry = index.data.first(where: { $0.type == "oracle_cards" }),
              let raw = entry.jsonl_download_uri ?? entry.download_uri,
              let url = URL(string: raw), isAllowed(url, host: "data.scryfall.io") else { throw CatalogueError.unsafeURL }
        return url
    }

    static func parse(file: URL) throws -> Self {
        try Task.checkCancellation()
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard file.isFileURL, (attributes[.type] as? FileAttributeType) == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.int64Value <= Int64(maximumBytes) else { throw CatalogueError.oversized }
        // zlib transparently reads both gzip and the legacy uncompressed JSON format.
        guard let stream = gzopen(file.path, "rb") else { throw CatalogueError.decompressionFailed }
        defer { gzclose(stream) }
        var parser = ObjectStream()
        var catalogue = Self()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        var total = 0
        while true {
            try Task.checkCancellation()
            let count = buffer.withUnsafeMutableBytes { gzread(stream, $0.baseAddress, UInt32($0.count)) }
            guard count >= 0 else { throw CatalogueError.decompressionFailed }
            if count == 0 {
                var code: Int32 = 0
                _ = gzerror(stream, &code)
                guard code == Z_OK || code == Z_STREAM_END else { throw CatalogueError.decompressionFailed }
                break
            }
            total += Int(count)
            guard total <= maximumBytes else { throw CatalogueError.oversized }
            try parser.append(buffer.prefix(Int(count))) { try catalogue.accept($0) }
        }
        try parser.finish()
        return catalogue
    }

    /// Testable incremental decoder, including buffers ending inside escaped strings.
    struct ObjectStream {
        private var array: Bool?
        private var closed = false
        private var separatorRequired = false
        private var lineBreak = false
        private var afterComma = false
        private var depth = 0
        private var quoted = false
        private var escaped = false
        private var object = Data()
        mutating func append<S: Sequence>(_ bytes: S, consume: (Data) throws -> Void) throws where S.Element == UInt8 {
            for byte in bytes {
                if depth > 0 {
                    guard object.count < maximumObjectBytes else { throw CatalogueError.oversized }
                    object.append(byte)
                    if quoted {
                        if escaped { escaped = false }
                        else if byte == 92 { escaped = true }
                        else if byte == 34 { quoted = false }
                    } else if byte == 34 { quoted = true }
                    else if byte == 123 { depth += 1 }
                    else if byte == 125 {
                        depth -= 1
                        if depth == 0 {
                            try consume(object)
                            object.removeAll(keepingCapacity: true)
                            separatorRequired = true; lineBreak = false; afterComma = false
                        }
                    }
                    continue
                }
                if [9, 10, 13, 32].contains(byte) {
                    if byte == 10 || byte == 13 { lineBreak = true }
                    continue
                }
                guard !closed else { throw CatalogueError.malformedJSON }
                if array == nil {
                    array = byte == 91
                    if byte == 91 { continue }
                }
                if byte == 93, array == true, !afterComma { closed = true; continue }
                if byte == 44, array == true, separatorRequired {
                    separatorRequired = false; afterComma = true; continue
                }
                guard byte == 123, !separatorRequired || (array == false && lineBreak) else { throw CatalogueError.malformedJSON }
                depth = 1; object.append(byte)
            }
        }
        func finish() throws {
            guard depth == 0, array != nil, array == false || closed else { throw CatalogueError.malformedJSON }
        }
    }

    private struct Card: Decodable {
        struct Face: Decodable {
            let name: String
            let image_uris: [String: String]?
            let type_line: String?
            let oracle_text: String?
            let power: String?
            let toughness: String?
            let colors: [String]?
        }
        struct Part: Decodable { let id: UUID; let component: String; let name: String; let type_line: String? }
        let id: UUID
        let name: String
        let layout: String?
        let type_line: String?
        let oracle_text: String?
        let power: String?
        let toughness: String?
        let colors: [String]?
        let image_uris: [String: String]?
        let card_faces: [Face]?
        let all_parts: [Part]?
    }
    private mutating func accept(_ object: Data) throws {
        try Task.checkCancellation()
        guard imagesByID.count < 100_000 else { throw CatalogueError.oversized }
        let card = try JSONDecoder().decode(Card.self, from: object)
        // Art Series inserts are not playable cards. Their repeated face names can
        // collide with the transform card's real front/back artwork aliases.
        guard card.layout != "art_series" else { return }
        func images(_ uris: [String: String]) -> Images {
            func safe(_ size: String) -> URL? {
                guard let raw = uris[size], let url = URL(string: raw), Self.isAllowed(url, host: "cards.scryfall.io") else { return nil }
                return url
            }
            return Images(small: safe("small"), normal: safe("normal"), large: safe("large"))
        }
        imagesByID[card.id] = images(card.image_uris ?? card.card_faces?.first?.image_uris ?? [:])
        let tokenLike = ["token", "double_faced_token", "emblem"].contains(card.layout ?? "") ||
            card.type_line?.localizedCaseInsensitiveContains("token") == true ||
            card.type_line?.localizedCaseInsensitiveContains("emblem") == true
        if tokenLike {
            let face = card.card_faces?.first
            let doubleFaced = card.layout == "double_faced_token"
            tokens[card.id] = NativeTokenArtwork(id: card.id,
                name: doubleFaced ? face?.name ?? card.name : card.name,
                typeLine: (doubleFaced ? face?.type_line : nil) ?? card.type_line ?? face?.type_line,
                oracleText: (doubleFaced ? face?.oracle_text : nil) ?? card.oracle_text ?? face?.oracle_text,
                power: (doubleFaced ? face?.power : nil) ?? card.power ?? face?.power,
                toughness: (doubleFaced ? face?.toughness : nil) ?? card.toughness ?? face?.toughness,
                colors: (doubleFaced ? face?.colors : nil) ?? card.colors ?? face?.colors)
        } else {
            let nameKey = Self.key(card.name)
            if let previous = names[nameKey], previous != card.id { ambiguousNames.insert(nameKey) }
            else { names[nameKey] = card.id }
            if let face = card.card_faces?.first {
                let key = Self.key(face.name)
                if let previous = aliases[key], previous != card.id { ambiguousAliases.insert(key) }
                else { aliases[key] = card.id }
            }
            for face in card.card_faces ?? [] {
                guard let uris = face.image_uris else { continue }
                let artwork = images(uris)
                guard artwork.small != nil || artwork.normal != nil || artwork.large != nil else { continue }
                let key = Self.key(face.name)
                if let previous = aliases[key], previous != card.id { ambiguousAliases.insert(key) }
                else { aliases[key] = card.id }
                faceImages[key] = artwork
                faceNamesByID[card.id, default: []].append(face.name)
            }
        }
        let related = (card.all_parts ?? []).filter { $0.component == "token" }.map {
            NativeTokenArtwork(id: $0.id, name: $0.name, typeLine: $0.type_line)
        }
        if !related.isEmpty { relations[card.id] = related }
    }

    private final class BoundedTransfer: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            if totalBytesWritten > Int64(maximumBytes) || totalBytesExpectedToWrite > Int64(maximumBytes) { downloadTask.cancel() }
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
        func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
        }
    }
}
