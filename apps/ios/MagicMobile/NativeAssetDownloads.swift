import Foundation
import Combine
import CryptoKit
import ImageIO

enum NativeArtworkQuality: String, CaseIterable, Identifiable {
    case compact, standard, high
    var id: String { rawValue }
    var label: String { switch self { case .compact: return "Compact"; case .standard: return "Standard"; case .high: return "High" } }
    var minShortEdge: Int { switch self { case .compact: return 146; case .standard: return 488; case .high: return 672 } }
    var estimatedBytes: Int { switch self { case .compact: return 20_000; case .standard: return 100_000; case .high: return 200_000 } }
    var imageSizeString: String { switch self { case .compact: return "small"; case .standard: return "normal"; case .high: return "large" } }
    func accepts(_ data: Data) -> Bool {
        guard NativeDeckArtwork.isSufficient(data, for: .board),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return false }
        return min(width, height) >= minShortEdge
    }
}

/// Explicit artwork downloads survive URLCache eviction. No rules or engine data lives here.
actor NativeAssetStore {
    static let shared = NativeAssetStore()
    static let maximumBytes = 20 * 1024 * 1024 * 1024
    static let minimumFreeBytes = 1024 * 1024 * 1024
    let directory: URL
    let capacity: Int
    private let freeSpaceReserve: Int
    private let availableBytes: @Sendable (URL) throws -> Int64
    // This actor is the only writer. Reconcile from disk once per explicit scan;
    // successful writes adjust the total rather than listing all files again.
    private var fileSizes: [String: Int]?
    private var accountedBytes = 0
    enum StoreError: LocalizedError {
        case full, lowDiskSpace, invalidImage
        var errorDescription: String? {
            switch self {
            case .full: return "Artwork storage reached its configured limit (20 GB in the app). Existing downloads are preserved."
            case .lowDiskSpace: return "Download paused to preserve at least 1 GB of free device space. Free up storage before resuming."
            case .invalidImage: return "The artwork file was incomplete or unsupported."
            }
        }
    }
    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MagicMobile-DownloadedArtwork-v1", isDirectory: true), capacity: Int = maximumBytes,
         freeSpaceReserve: Int = minimumFreeBytes,
         availableBytes: @escaping @Sendable (URL) throws -> Int64 = NativeAssetStore.freeBytes) {
        self.directory = directory; self.capacity = max(0, capacity)
        self.freeSpaceReserve = max(0, freeSpaceReserve); self.availableBytes = availableBytes
    }
    static func cardKey(_ name: String) -> String { "card:" + name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    static func tokenKey(_ id: UUID) -> String { "token:" + id.uuidString.lowercased() }
    func file(key: String, extension suffix: String = "image") -> URL {
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash).appendingPathExtension(suffix)
    }
    private func qualityKey(_ key: String, quality: NativeArtworkQuality) -> String {
        // Keep the existing high-quality filename so previous downloads remain usable.
        quality == .high ? key : key + "|" + quality.rawValue
    }
    func image(key: String) -> Data? { image(key: key, quality: .compact) }
    func image(key: String, quality: NativeArtworkQuality) -> Data? {
        for candidate in NativeArtworkQuality.allCases.reversed() where candidate.minShortEdge >= quality.minShortEdge {
            if let data = NativeDeckArtwork.localImageData(at: file(key: qualityKey(key, quality: candidate))), quality.accepts(data) { return data }
        }
        return nil
    }
    nonisolated static func freeBytes(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: url.path)
        guard let value = attributes[.systemFreeSize] as? NSNumber else { throw StoreError.lowDiskSpace }
        return value.int64Value
    }
    func storedBytes(refresh: Bool = false) -> Int {
        if refresh || fileSizes == nil {
            do { try reconcile() } catch { return accountedBytes }
        }
        return accountedBytes
    }
    private func reconcile() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            fileSizes = [:]; accountedBytes = 0; return
        }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
        var sizes: [String: Int] = [:]
        for url in files {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values.isRegularFile == true { sizes[url.lastPathComponent] = max(0, values.fileSize ?? 0) }
        }
        fileSizes = sizes; accountedBytes = sizes.values.reduce(0, +)
    }
    private func write(_ data: Data, to destination: URL) throws {
        try prepare()
        if fileSizes == nil { try reconcile() }
        let previous = fileSizes?[destination.lastPathComponent] ?? 0
        guard data.count <= capacity, accountedBytes - previous <= capacity - data.count else { throw StoreError.full }
        // Atomic replacement temporarily needs space for the complete new file.
        let free = try availableBytes(directory)
        guard free >= Int64(freeSpaceReserve), Int64(data.count) <= free - Int64(freeSpaceReserve) else { throw StoreError.lowDiskSpace }
        try data.write(to: destination, options: .atomic)
        fileSizes?[destination.lastPathComponent] = data.count
        accountedBytes = accountedBytes - previous + data.count
    }
    private func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var location = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try location.setResourceValues(values)
    }
    func save(_ data: Data, key: String, quality: NativeArtworkQuality = .high) throws {
        guard quality.accepts(data) else { throw StoreError.invalidImage }
        try write(data, to: file(key: qualityKey(key, quality: quality)))
    }
    func relations(name: String) -> [NativeTokenArtwork]? {
        let url = file(key: Self.cardKey(name), extension: "json")
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 128 * 1024,
              let data = try? Data(contentsOf: url), let result = try? JSONDecoder().decode([NativeTokenArtwork].self, from: data),
              result.count <= 100, result.allSatisfy({ !$0.name.isEmpty && $0.name.utf8.count <= 512 }) else { return nil }
        return result
    }
    func saveRelations(_ tokens: [NativeTokenArtwork], name: String) throws {
        let data = try JSONEncoder().encode(tokens)
        guard tokens.count <= 100, data.count <= 128 * 1024 else { throw StoreError.full }
        try write(data, to: file(key: Self.cardKey(name), extension: "json"))
    }
    func saveToken(_ token: NativeTokenArtwork) throws {
        let data = try JSONEncoder().encode(token)
        guard data.count <= 64 * 1024 else { throw StoreError.full }
        try write(data, to: file(key: Self.tokenKey(token.id), extension: "token"))
    }
    func tokenDetails(id: UUID) -> NativeTokenArtwork? {
        let url = file(key: Self.tokenKey(id), extension: "token")
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 64 * 1024,
              let data = try? Data(contentsOf: url), let token = try? JSONDecoder().decode(NativeTokenArtwork.self, from: data),
              token.id == id, token.hasMatchingMetadata else { return nil }
        return token
    }
    private var catalogueTokensFile: URL { directory.appendingPathComponent("catalogue-tokens-v1.json") }
    private struct CatalogueTokenManifest: Codable {
        let tokens: [NativeTokenArtwork]
        let unavailableNames: [String]
    }
    private static func validCatalogueTokens(_ tokens: [NativeTokenArtwork]) -> Bool {
        tokens.count <= 10_000 && Set(tokens.map(\.id)).count == tokens.count &&
            tokens.allSatisfy { $0.hasMatchingMetadata && $0.name.utf8.count <= 512 &&
                ($0.typeLine?.utf8.count ?? 0) <= 2048 && ($0.oracleText?.utf8.count ?? 0) <= 32768 }
    }
    private func catalogueTokenManifest() -> CatalogueTokenManifest? {
        guard let size = try? catalogueTokensFile.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 8 * 1024 * 1024,
              let data = try? Data(contentsOf: catalogueTokensFile),
              let manifest = try? JSONDecoder().decode(CatalogueTokenManifest.self, from: data),
              Self.validCatalogueTokens(manifest.tokens), Self.validUnavailableTokens(manifest.unavailableNames),
              manifest.tokens.count + manifest.unavailableNames.count <= 10_000 else { return nil }
        return manifest
    }
    func catalogueTokens() -> [NativeTokenArtwork]? { catalogueTokenManifest()?.tokens }
    func unavailableCatalogueTokenNames() -> [String] { catalogueTokenManifest()?.unavailableNames ?? [] }
    private static func validUnavailableTokens(_ names: [String]) -> Bool {
        names.count <= 10_000 && names.allSatisfy { !$0.isEmpty && $0.utf8.count <= 512 &&
            !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }
    }
    func saveCatalogueTokens(_ tokens: [NativeTokenArtwork], unavailableNames: [String] = []) throws {
        guard Self.validCatalogueTokens(tokens), Self.validUnavailableTokens(unavailableNames),
              tokens.count + unavailableNames.count <= 10_000 else { throw DeckStudioScryfallError.invalidResponse }
        let data = try JSONEncoder().encode(CatalogueTokenManifest(tokens: tokens, unavailableNames: unavailableNames))
        guard data.count <= 8 * 1024 * 1024 else { throw DeckStudioScryfallError.tooLarge }
        try write(data, to: catalogueTokensFile)
    }
    private var catalogueFacesFile: URL { directory.appendingPathComponent("catalogue-faces-v1.json") }
    private static func validCatalogueFaces(_ names: [String]) -> Bool {
        guard names.count <= 10_000, Set(names.map(cardKey)).count == names.count else { return false }
        return names.allSatisfy { !$0.isEmpty && $0.utf8.count <= 512 &&
            $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines) &&
            !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }
    }
    func catalogueFaces() -> [String]? {
        guard let size = try? catalogueFacesFile.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 6 * 1024 * 1024, let data = try? Data(contentsOf: catalogueFacesFile),
              let names = try? JSONDecoder().decode([String].self, from: data), Self.validCatalogueFaces(names) else { return nil }
        return names
    }
    func saveCatalogueFaces(_ names: [String]) throws {
        guard Self.validCatalogueFaces(names) else { throw DeckStudioScryfallError.invalidInput }
        let data = try JSONEncoder().encode(names)
        guard data.count <= 6 * 1024 * 1024 else { throw DeckStudioScryfallError.tooLarge }
        try write(data, to: catalogueFacesFile)
    }
    func tokenImage(name: String, typeLine: String?, oracleText: String?, power: String?, toughness: String?, colors: [String]?) -> Data? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return nil }
        let candidates: [NativeTokenArtwork] = files.filter { $0.pathExtension == "token" }.compactMap { url in
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 64 * 1024,
                  let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(NativeTokenArtwork.self, from: data)
        }
        guard let token = Self.matchToken(candidates, name: name, typeLine: typeLine, oracleText: oracleText,
                                         power: power, toughness: toughness, colors: colors) else { return nil }
        return image(key: Self.tokenKey(token.id))
    }
    static func matchToken(_ candidates: [NativeTokenArtwork], name: String, typeLine: String?, oracleText: String?,
                           power: String?, toughness: String?, colors: [String]?) -> NativeTokenArtwork? {
        func normalized(_ value: String) -> String { EngineDisplayText.text(value).lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
        func type(_ value: String) -> String { normalized(value).replacingOccurrences(of: "token ", with: "").replacingOccurrences(of: "—", with: "-") }
        guard let colors, Set(colors).isSubset(of: ["W", "U", "B", "R", "G"]), Set(colors).count == colors.count,
              let typeLine, !typeLine.isEmpty, let oracleText else { return nil }
        let matches = candidates.filter {
            $0.hasMatchingMetadata && normalized($0.name) == normalized(name) &&
            type($0.typeLine ?? "") == type(typeLine) &&
            normalized($0.oracleText ?? "") == normalized(oracleText) &&
            $0.power == power && $0.toughness == toughness && Set($0.colors ?? []) == Set(colors)
        }
        // Never choose between two printings/variants solely on generic names.
        return matches.count == 1 ? matches[0] : nil
    }
}

struct NativeTokenArtwork: Codable, Hashable, Identifiable {
    let id: UUID
    let name: String
    var typeLine: String? = nil
    var oracleText: String? = nil
    var power: String? = nil
    var toughness: String? = nil
    var colors: [String]? = nil
    var hasMatchingMetadata: Bool {
        guard !name.isEmpty, let typeLine, !typeLine.isEmpty, let colors,
              Set(colors).isSubset(of: ["W", "U", "B", "R", "G"]), Set(colors).count == colors.count,
              (power?.utf8.count ?? 0) <= 32, (toughness?.utf8.count ?? 0) <= 32 else { return false }
        if typeLine.localizedCaseInsensitiveContains("creature") {
            return !(power ?? "").isEmpty && !(toughness ?? "").isEmpty
        }
        return true
    }
}

/// Uses Scryfall's related-card IDs, never a fuzzy token-name match.
actor NativeTokenDiscovery {
    private let transport: any DeckStudioScryfallHTTP
    init(transport: any DeckStudioScryfallHTTP = DeckStudioScryfallHTTPTransport()) { self.transport = transport }
    func tokens(name: String) async throws -> [NativeTokenArtwork] {
        let request = try DeckStudioScryfallClient.request(name)
        try await DeckStudioScryfallBudget.shared.reserve()
        return try Self.decode(try await transport.send(request))
    }
    func details(id: UUID) async throws -> NativeTokenArtwork {
        var request = try DeckStudioScryfallClient.request("token")
        request.url = URL(string: "https://api.scryfall.com/cards/\(id.uuidString.lowercased())")!
        try await DeckStudioScryfallBudget.shared.reserve()
        let data = try await transport.send(request)
        let card = try JSONDecoder().decode(DeckStudioScryfallCard.self, from: data).validated()
        guard card.id == id, card.typeLine?.localizedCaseInsensitiveContains("token") == true else { throw DeckStudioScryfallError.invalidResponse }
        struct Attributes: Decodable { let power: String?; let toughness: String?; let colors: [String]? }
        let attributes = try JSONDecoder().decode(Attributes.self, from: data)
        let token = NativeTokenArtwork(id: id, name: card.name, typeLine: card.typeLine, oracleText: card.oracleText,
                                       power: attributes.power, toughness: attributes.toughness, colors: attributes.colors)
        guard token.hasMatchingMetadata else { throw DeckStudioScryfallError.invalidResponse }
        return token
    }
    static func decode(_ data: Data) throws -> [NativeTokenArtwork] {
        struct Related: Decodable { let id: UUID; let name: String; let component: String }
        struct Card: Decodable { let object: String; let all_parts: [Related]? }
        guard data.count <= 4 * 1024 * 1024 else { throw DeckStudioScryfallError.tooLarge }
        let card = try JSONDecoder().decode(Card.self, from: data)
        guard card.object == "card", (card.all_parts?.count ?? 0) <= 100 else { throw DeckStudioScryfallError.invalidResponse }
        var seen = Set<UUID>()
        return try (card.all_parts ?? []).filter { $0.component == "token" }.compactMap {
            guard !$0.name.isEmpty, $0.name.utf8.count <= 512 else { throw DeckStudioScryfallError.invalidResponse }
            return seen.insert($0.id).inserted ? NativeTokenArtwork(id: $0.id, name: $0.name) : nil
        }
    }
}

@MainActor final class NativeAssetDownloads: ObservableObject {
    static let maximumNames = 100_000
    static let didFinish = Notification.Name("MagicMobileArtworkDownloadsDidFinish")
    @Published private(set) var cardTotal = 0
    @Published private(set) var cardStored = 0
    @Published private(set) var tokenTotal = 0
    @Published private(set) var tokenStored = 0
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published private(set) var storedBytes = 0
    @Published private(set) var isRunning = false
    @Published private(set) var isScanning = false
    @Published private(set) var status = "Choose a deck to check downloads."
    @Published private(set) var failures: [String] = []
    @Published private(set) var missingNames: [String] = []
    @Published private(set) var missingTokenNames: [String] = []
    @Published private(set) var tokens: [NativeTokenArtwork] = []
    @Published private(set) var tokenDiscoveryRemaining = 0
    @Published private(set) var faceDiscoveryPending = false
    private let store: NativeAssetStore
    private let artwork: NativeDeckArtwork
    private let discovery: NativeTokenDiscovery
    private let catalogueLoader: @Sendable () async throws -> NativeArtworkCatalogue
    private var task: Task<Void, Never>?
    private var scanGeneration = UUID()
    private var missingTokenIDs = Set<UUID>()
    private var unavailableTokenNames: [String] = []
    init(store: NativeAssetStore = .shared, artwork: NativeDeckArtwork = .shared, discovery: NativeTokenDiscovery = NativeTokenDiscovery(),
         catalogueLoader: @escaping @Sendable () async throws -> NativeArtworkCatalogue = { try await NativeArtworkCatalogue.load() }) {
        self.store = store; self.artwork = artwork; self.discovery = discovery; self.catalogueLoader = catalogueLoader
    }
    static func names(_ names: [String]) throws -> [String] {
        guard names.count <= maximumNames * 2 else { throw DeckStudioScryfallError.invalidInput }
        var seen = Set<String>()
        let result = try names.map { name -> String in
            _ = try NativeDeckArtwork.request(name: name)
            return name.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { seen.insert(NativeAssetStore.cardKey($0)).inserted }
        guard result.count <= maximumNames else { throw DeckStudioScryfallError.invalidInput }
        return result
    }
    func scan(names: [String], quality: NativeArtworkQuality = .high, fullCatalogue: Bool = false) async {
        let generation = UUID(); scanGeneration = generation
        isScanning = true
        defer { if generation == scanGeneration { isScanning = false } }
        do {
            var names = try Self.names(names)
            var pendingFaces = false
            if fullCatalogue {
                if let faces = await store.catalogueFaces() { names = try Self.names(names + faces) }
                else { pendingFaces = true }
            }
            var missing: [String] = [], related: [NativeTokenArtwork] = []
            var seen = Set<UUID>(), unknown = 0, savedTokens = 0
            var missingTokens: [String] = []
            var missingIDs = Set<UUID>()
            var unavailable: [String] = []
            for name in names {
                guard generation == scanGeneration, !Task.isCancelled else { return }
                if await store.image(key: NativeAssetStore.cardKey(name), quality: quality) == nil { missing.append(name) }
                if !fullCatalogue {
                    if let found = await store.relations(name: name) {
                        related += found.filter { seen.insert($0.id).inserted }
                    } else { unknown += 1 }
                }
            }
            if fullCatalogue {
                if let found = await store.catalogueTokens() { related = found }
                else { unknown = 1 }
                unavailable = await store.unavailableCatalogueTokenNames()
            }
            for token in related {
                guard generation == scanGeneration, !Task.isCancelled else { return }
                if await store.tokenDetails(id: token.id) != nil,
                   await store.image(key: NativeAssetStore.tokenKey(token.id), quality: quality) != nil { savedTokens += 1 }
                else { missingTokens.append(token.name); missingIDs.insert(token.id) }
            }
            let bytes = await store.storedBytes(refresh: true)
            guard generation == scanGeneration else { return }
            cardTotal = names.count; cardStored = names.count - missing.count; missingNames = missing
            tokens = related; tokenTotal = related.count + unavailable.count; tokenStored = savedTokens; tokenDiscoveryRemaining = unknown; storedBytes = bytes
            missingTokenNames = missingTokens + unavailable
            missingTokenIDs = missingIDs
            unavailableTokenNames = unavailable
            faceDiscoveryPending = pendingFaces
            if !isRunning { status = "\(cardStored) of \(cardTotal) card images stored on this device." }
        } catch { if generation == scanGeneration { status = error.localizedDescription } }
    }
    func download(names rawNames: [String], includeTokens: Bool, allowNetwork: Bool,
                  quality: NativeArtworkQuality = .high, fullCatalogue: Bool = false) {
        guard !isRunning else { return }
        guard allowNetwork else { status = "Enable online artwork before downloading from Scryfall."; return }
        let inputNames: [String]
        do { inputNames = try Self.names(rawNames) } catch { status = error.localizedDescription; return }
        isRunning = true; failures = []; completed = 0; total = inputNames.count
        task = Task { [weak self] in
            guard let self else { return }
            var names = inputNames
            var stopped = false
            var savedCards = Set<String>()
            var savedTokens = Set<UUID>()
            do {
                await scan(names: names, quality: quality, fullCatalogue: fullCatalogue)
                try Task.checkCancellation()
                status = fullCatalogue ? "Preparing Scryfall artwork catalogue…" : "Preparing artwork downloads…"
                let catalogue = fullCatalogue ? try await catalogueLoader() : nil
                try Task.checkCancellation()
                if let catalogue {
                    let faces = catalogue.additionalFaceNames(for: inputNames)
                    try await store.saveCatalogueFaces(faces)
                    names = try Self.names(inputNames + faces)
                    total = names.count
                    status = "Checking \(names.count) card faces for offline artwork…"
                    await scan(names: names, quality: quality, fullCatalogue: true)
                    try Task.checkCancellation()
                }
                if includeTokens, let catalogue {
                    try await store.saveCatalogueTokens(catalogue.allTokens, unavailableNames: catalogue.unavailableTokenNames)
                    failures += catalogue.unavailableTokenNames.prefix(10_000).map { "Token \($0): safe artwork metadata is unavailable." }
                }
                for name in names {
                    try Task.checkCancellation()
                    status = "Downloading \(name)…"
                    do {
                        if await store.image(key: NativeAssetStore.cardKey(name), quality: quality) == nil {
                            let url = catalogue?.imageURL(name: name, size: quality.imageSizeString)
                            if fullCatalogue && url == nil { throw DeckStudioScryfallError.invalidResponse }
                            guard let data = try await artwork.downloadImage(name: name, quality: quality, imageURL: url) else { throw NativeAssetStore.StoreError.invalidImage }
                            try Task.checkCancellation()
                            try await store.save(data, key: NativeAssetStore.cardKey(name), quality: quality)
                            savedCards.insert(name)
                        }
                        if includeTokens && !fullCatalogue, await store.relations(name: name) == nil {
                            let related = try await discovery.tokens(name: name)
                            try Task.checkCancellation()
                            try await store.saveRelations(related, name: name)
                        }
                    } catch is CancellationError { throw CancellationError() }
                    catch {
                        failures.append("\(name): \(error.localizedDescription)")
                        if Self.mustStop(error) { stopped = true; break }
                    }
                    completed += 1
                }
                await scan(names: names, quality: quality, fullCatalogue: fullCatalogue)
                try Task.checkCancellation()
                savedCards = []
                if includeTokens && !stopped {
                    total += tokens.count
                    for token in tokens {
                        try Task.checkCancellation()
                        status = "Downloading token: \(token.name)…"
                        do {
                            if await store.tokenDetails(id: token.id) == nil {
                                let details: NativeTokenArtwork
                                if let catalogue {
                                    guard let found = catalogue.token(id: token.id) else { throw DeckStudioScryfallError.invalidResponse }
                                    details = found
                                } else { details = try await discovery.details(id: token.id) }
                                try Task.checkCancellation()
                                try await store.saveToken(details)
                            }
                            if await store.image(key: NativeAssetStore.tokenKey(token.id), quality: quality) == nil {
                                let url = catalogue?.imageURL(id: token.id, size: quality.imageSizeString)
                                if fullCatalogue && url == nil { throw DeckStudioScryfallError.invalidResponse }
                                guard let data = try await artwork.imageData(id: token.id, allowNetwork: true, quality: quality, imageURL: url) else { throw NativeAssetStore.StoreError.invalidImage }
                                try Task.checkCancellation()
                                try await store.save(data, key: NativeAssetStore.tokenKey(token.id), quality: quality)
                            }
                            savedTokens.insert(token.id)
                        } catch is CancellationError { throw CancellationError() }
                        catch {
                            failures.append("Token \(token.name): \(error.localizedDescription)")
                            if Self.mustStop(error) { stopped = true; break }
                        }
                        completed += 1
                    }
                }
                try Task.checkCancellation()
                await scan(names: names, quality: quality, fullCatalogue: fullCatalogue)
                status = stopped ? "Download paused after an error. Completed images are preserved; retry when ready." :
                    (failures.isEmpty ? "Download complete." : "Download finished with \(failures.count) issues. Retry missing items when ready.")
            } catch {
                // A cancelled catalogue run must not spend minutes scanning every
                // file. Retain verified progress; the next explicit check rescans.
                missingNames.removeAll { savedCards.contains($0) }
                cardStored = cardTotal - missingNames.count
                missingTokenIDs.subtract(savedTokens)
                missingTokenNames = tokens.filter { missingTokenIDs.contains($0.id) }.map(\.name) + unavailableTokenNames
                tokenStored = tokenTotal - missingTokenIDs.count - unavailableTokenNames.count
                storedBytes = await store.storedBytes()
                if Task.isCancelled || error is CancellationError {
                    status = "Download cancelled. Completed images remain available offline."
                } else {
                    failures.append(error.localizedDescription)
                    status = "Download could not continue. Completed images are preserved; retry when ready."
                }
            }
            isRunning = false; task = nil
            NotificationCenter.default.post(name: Self.didFinish, object: nil)
        }
    }
    func cancel() { task?.cancel() }
    private static func mustStop(_ error: Error) -> Bool {
        if let value = error as? NativeDeckArtwork.ArtworkError, [.rateLimited, .httpStatus(403), .httpStatus(401)].contains(value) { return true }
        if let value = error as? DeckStudioScryfallError, [.rateLimited, .unavailable, .http(403), .http(401)].contains(value) { return true }
        if error is URLError { return true }
        return error is NativeAssetStore.StoreError
    }
}
