import Foundation
import Combine
import CryptoKit
import ImageIO
#if canImport(UIKit)
import UIKit
#endif

enum NativeArtworkQuality: String, CaseIterable, Identifiable, Codable {
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
    static let didStoreArtwork = Notification.Name("MagicMobileStoredArtworkChanged")
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
    private var tokenMetadata: [String: NativeTokenArtwork]?
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
    static func tokenKey(_ id: UUID, face: String? = nil) -> String {
        "token:" + id.uuidString.lowercased() + (face == "back" ? ":back" : "")
    }
    static func artworkChangeAffects(key: String, storedName: String?, name: String, isToken: Bool, sourceName: String? = nil) -> Bool {
        if let sourceName { return key == cardKey(sourceName) }
        if !isToken { return key == cardKey(name) }
        return key.hasPrefix("token:") && storedName.map {
            tokenArtworkName($0).caseInsensitiveCompare(tokenArtworkName(name)) == .orderedSame
        } == true
    }
    static func tokenArtworkName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 6, trimmed.lowercased().hasSuffix(" token") else { return trimmed }
        return String(trimmed.dropLast(6)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
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
        let name = key.hasPrefix("token:") ? storedTokens()[key]?.name : nil
        NotificationCenter.default.post(name: Self.didStoreArtwork, object: nil,
                                        userInfo: ["key": key, "name": name ?? ""])
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
        try write(data, to: file(key: token.artworkKey, extension: "token"))
        if tokenMetadata != nil { tokenMetadata?[token.artworkKey] = token }
    }
    func tokenDetails(id: UUID, face: String? = nil) -> NativeTokenArtwork? {
        let url = file(key: Self.tokenKey(id, face: face), extension: "token")
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 64 * 1024,
              let data = try? Data(contentsOf: url), let token = try? JSONDecoder().decode(NativeTokenArtwork.self, from: data),
              token.id == id, token.face == face, token.hasMatchingMetadata else { return nil }
        return token
    }
    private var catalogueTokensFile: URL { directory.appendingPathComponent("catalogue-tokens-v1.json") }
    private struct CatalogueTokenManifest: Codable {
        let tokens: [NativeTokenArtwork]
        let unavailableNames: [String]
        let coverageVersion: Int?
    }
    private static func validCatalogueTokens(_ tokens: [NativeTokenArtwork]) -> Bool {
        tokens.count <= 10_000 && Set(tokens.map(\.artworkKey)).count == tokens.count &&
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
    func catalogueTokenCoverageCurrent() -> Bool { catalogueTokenManifest()?.coverageVersion == 2 }
    func unavailableCatalogueTokenNames() -> [String] { catalogueTokenManifest()?.unavailableNames ?? [] }
    private static func validUnavailableTokens(_ names: [String]) -> Bool {
        names.count <= 10_000 && names.allSatisfy { !$0.isEmpty && $0.utf8.count <= 512 &&
            !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }
    }
    func saveCatalogueTokens(_ tokens: [NativeTokenArtwork], unavailableNames: [String] = []) throws {
        guard Self.validCatalogueTokens(tokens), Self.validUnavailableTokens(unavailableNames),
              tokens.count + unavailableNames.count <= 10_000 else { throw DeckStudioScryfallError.invalidResponse }
        let data = try JSONEncoder().encode(CatalogueTokenManifest(tokens: tokens, unavailableNames: unavailableNames, coverageVersion: 2))
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
    func tokenImage(name: String, typeLine: String?, oracleText: String?, power: String?, toughness: String?, colors: [String]?,
                    quality: NativeArtworkQuality = .compact) -> Data? {
        let lookupName = Self.tokenArtworkName(name).lowercased()
        let candidates = storedTokens().values.filter { Self.tokenArtworkName($0.name).lowercased() == lookupName }
        guard let token = Self.matchTokenArtwork(candidates, name: name, typeLine: typeLine, oracleText: oracleText,
                                                power: power, toughness: toughness, colors: colors) else { return nil }
        if let data = image(key: token.artworkKey, quality: quality) { return data }
        for alternate in candidates.sorted(by: { $0.artworkKey < $1.artworkKey }) where
            Self.sameTokenIdentity(alternate, token) {
            if let data = image(key: alternate.artworkKey, quality: quality) { return data }
        }
        return nil
    }
    private func storedTokens() -> [String: NativeTokenArtwork] {
        if let tokenMetadata { return tokenMetadata }
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return [:] }
        let candidates: [NativeTokenArtwork] = files.filter { $0.pathExtension == "token" }.compactMap { url in
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 64 * 1024,
                  let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(NativeTokenArtwork.self, from: data)
        }
        let result = Dictionary(candidates.filter(\.hasMatchingMetadata).map { ($0.artworkKey, $0) }, uniquingKeysWith: { first, _ in first })
        tokenMetadata = result
        return result
    }
    private static func normalizedTokenText(_ value: String) -> String {
        EngineDisplayText.text(value).lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
    private static func normalizedTokenType(_ value: String) -> String {
        let line = normalizedTokenText(value).replacingOccurrences(of: "—", with: "-")
        return line.hasPrefix("token ") ? String(line.dropFirst(6)) : line
    }
    private static func normalizedTokenRules(_ value: String, typeLine: String, name: String) -> String {
        var rules = normalizedTokenText(value).replacingOccurrences(of: "this token", with: "this permanent")
        // XMage and current Oracle use different self-reference wording. Do not
        // remove abilities or reminder text, or collapse unrelated token variants.
        for kind in ["artifact", "creature", "enchantment", "land"] where normalizedTokenType(typeLine).components(separatedBy: " - ")[0].split(separator: " ").contains(Substring(kind)) {
            rules = rules.replacingOccurrences(of: "this " + kind, with: "this permanent")
        }
        // XMage can spell an activated sacrifice cost with the token's visible
        // name ("Sacrifice Food Token:") where Oracle says "this token". Limit
        // this equivalence to a self-named cost; "a Food Token" and references
        // elsewhere in the effect must keep their distinct meaning.
        let selfName = normalizedTokenText(tokenArtworkName(name)) + " token"
        let pattern = "(?<![a-z0-9])sacrifice " + NSRegularExpression.escapedPattern(for: selfName) + "(?=\\s*:)"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            rules = regex.stringByReplacingMatches(in: rules, range: NSRange(rules.startIndex..., in: rules),
                                                  withTemplate: "sacrifice this permanent")
        }
        return rules
    }
    static func sameTokenIdentity(_ lhs: NativeTokenArtwork, _ rhs: NativeTokenArtwork) -> Bool {
        normalizedTokenText(tokenArtworkName(lhs.name)) == normalizedTokenText(tokenArtworkName(rhs.name)) &&
        normalizedTokenType(lhs.typeLine ?? "") == normalizedTokenType(rhs.typeLine ?? "") &&
        normalizedTokenRules(lhs.oracleText ?? "", typeLine: lhs.typeLine ?? "", name: lhs.name) ==
            normalizedTokenRules(rhs.oracleText ?? "", typeLine: rhs.typeLine ?? "", name: rhs.name) &&
        lhs.power == rhs.power && lhs.toughness == rhs.toughness && Set(lhs.colors ?? []) == Set(rhs.colors ?? [])
    }
    /// Art identity does not change when counters, buffs, or copy effects alter P/T.
    /// Require all other visible metadata and only select among equivalent printings;
    /// an ambiguous same-name token with different rules/type/color remains unresolved.
    static func matchTokenArtwork(_ candidates: [NativeTokenArtwork], name: String, typeLine: String?, oracleText: String?,
                                  power: String?, toughness: String?, colors: [String]?) -> NativeTokenArtwork? {
        guard let colors, let typeLine, let oracleText, !typeLine.isEmpty,
              Set(colors).isSubset(of: ["W", "U", "B", "R", "G"]), Set(colors).count == colors.count else { return nil }
        let matches = candidates.filter {
            $0.hasMatchingMetadata && normalizedTokenText(Self.tokenArtworkName($0.name)) == normalizedTokenText(Self.tokenArtworkName(name)) &&
            normalizedTokenType($0.typeLine ?? "") == normalizedTokenType(typeLine) &&
            normalizedTokenRules($0.oracleText ?? "", typeLine: $0.typeLine ?? "", name: $0.name) ==
                normalizedTokenRules(oracleText, typeLine: typeLine, name: name) && Set($0.colors ?? []) == Set(colors)
        }
        // Several equivalent 2/2 printings must not become ambiguous merely
        // because a different */* token also exists in the full catalogue.
        let exact = matches.filter { $0.power == power && $0.toughness == toughness }
        if let first = exact.sorted(by: { $0.artworkKey < $1.artworkKey }).first { return first }
        // A different printed P/T may be an entirely different token. Only relax
        // runtime P/T if every eligible printing describes the same base token.
        guard let first = matches.first,
              matches.allSatisfy({ $0.power == first.power && $0.toughness == first.toughness }) else { return nil }
        return matches.sorted { $0.artworkKey < $1.artworkKey }.first
    }
    static func matchToken(_ candidates: [NativeTokenArtwork], name: String, typeLine: String?, oracleText: String?,
                           power: String?, toughness: String?, colors: [String]?) -> NativeTokenArtwork? {
        func normalized(_ value: String) -> String { EngineDisplayText.text(value).lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
        func type(_ value: String) -> String {
            let line = normalized(value).replacingOccurrences(of: "—", with: "-")
            return line.hasPrefix("token ") ? String(line.dropFirst(6)) : line
        }
        guard let colors, Set(colors).isSubset(of: ["W", "U", "B", "R", "G"]), Set(colors).count == colors.count,
              let typeLine, !typeLine.isEmpty, let oracleText else { return nil }
        let matches = candidates.filter {
            $0.hasMatchingMetadata && normalized(Self.tokenArtworkName($0.name)) == normalized(Self.tokenArtworkName(name)) &&
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
    var face: String? = nil
    var artworkKey: String { NativeAssetStore.tokenKey(id, face: face) }
    var hasMatchingMetadata: Bool {
        guard face == nil || face == "back", !name.isEmpty, let typeLine, !typeLine.isEmpty, oracleText != nil, let colors,
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
    static let shared = NativeAssetDownloads(backgroundQueue: .shared)
    nonisolated static let maximumNames = 100_000
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
    @Published private(set) var scanSucceeded = false
    var downloadableMissingTokenCount: Int { missingTokenIDs.count }
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
    private let deckCatalogueLoader: @Sendable ([String], Bool) async throws -> NativeArtworkCatalogue
    private var task: Task<Void, Never>?
    private var scanGeneration = UUID()
    private struct ScanContext {
        let names: [String]
        let quality: NativeArtworkQuality
        let fullCatalogue: Bool
        let tokenOnly: Bool
    }
    private var scanContext: ScanContext?
    private var missingTokenIDs = Set<String>()
    private var unavailableTokenNames: [String] = []
    private let backgroundQueue: NativeArtworkBackgroundQueue?
    private var queueObservation: AnyCancellable?
    private var preparingBackgroundJob = false
    private var preparationFailures: [String] = []
#if canImport(UIKit)
    private var preparationBackgroundTask: UIBackgroundTaskIdentifier = .invalid
#endif
    init(store: NativeAssetStore = .shared, artwork: NativeDeckArtwork = .shared, discovery: NativeTokenDiscovery = NativeTokenDiscovery(),
         catalogueLoader: @escaping @Sendable () async throws -> NativeArtworkCatalogue = { try await NativeArtworkCatalogue.load() },
         backgroundQueue: NativeArtworkBackgroundQueue? = nil,
         deckCatalogueLoader: @escaping @Sendable ([String], Bool) async throws -> NativeArtworkCatalogue = { try await NativeArtworkCatalogue.load(names: $0, includeTokens: $1) }) {
        self.store = store; self.artwork = artwork; self.discovery = discovery; self.catalogueLoader = catalogueLoader
        self.backgroundQueue = backgroundQueue
        self.deckCatalogueLoader = deckCatalogueLoader
        if let backgroundQueue {
            queueObservation = backgroundQueue.objectWillChange.sink { [weak self] in
                Task { @MainActor [weak self] in self?.syncBackgroundProgress() }
            }
            syncBackgroundProgress()
        }
    }
    nonisolated static func names(_ names: [String]) throws -> [String] {
        guard names.count <= maximumNames * 2 else { throw DeckStudioScryfallError.invalidInput }
        var seen = Set<String>()
        let result = try names.map { name -> String in
            _ = try NativeDeckArtwork.request(name: name)
            return name.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { seen.insert(NativeAssetStore.cardKey($0)).inserted }
        guard result.count <= maximumNames else { throw DeckStudioScryfallError.invalidInput }
        return result
    }
    func scan(names: [String], quality: NativeArtworkQuality = .high, fullCatalogue: Bool = false,
              tokenOnly: Bool = false) async {
        scanContext = ScanContext(names: names, quality: quality, fullCatalogue: fullCatalogue, tokenOnly: tokenOnly)
        let generation = UUID(); scanGeneration = generation
        scanSucceeded = false
        isScanning = true
        defer { if generation == scanGeneration { isScanning = false } }
        do {
            var names = tokenOnly ? [] : try Self.names(names)
            var pendingFaces = false
            if fullCatalogue && !tokenOnly {
                if let faces = await store.catalogueFaces() { names = try Self.names(names + faces) }
                else { pendingFaces = true }
            }
            var missing: [String] = [], related: [NativeTokenArtwork] = []
            var seen = Set<String>(), unknown = 0, savedTokens = 0
            var missingTokens: [String] = []
            var missingIDs = Set<String>()
            var unavailable: [String] = []
            for name in names {
                guard generation == scanGeneration, !Task.isCancelled else { return }
                if await store.image(key: NativeAssetStore.cardKey(name), quality: quality) == nil { missing.append(name) }
                if !fullCatalogue {
                    if let found = await store.relations(name: name) {
                        related += found.filter { seen.insert($0.artworkKey).inserted }
                    } else { unknown += 1 }
                }
            }
            if fullCatalogue {
                if let found = await store.catalogueTokens() { related = found }
                else { unknown = 1 }
                if !(await store.catalogueTokenCoverageCurrent()) { unknown = max(1, unknown) }
                unavailable = await store.unavailableCatalogueTokenNames()
            }
            for token in related {
                guard generation == scanGeneration, !Task.isCancelled else { return }
                if await store.tokenDetails(id: token.id, face: token.face) != nil,
                   await store.image(key: token.artworkKey, quality: quality) != nil { savedTokens += 1 }
                else { missingTokens.append(token.name); missingIDs.insert(token.artworkKey) }
            }
            let bytes = await store.storedBytes(refresh: true)
            guard generation == scanGeneration else { return }
            cardTotal = names.count; cardStored = names.count - missing.count; missingNames = missing
            tokens = related; tokenTotal = related.count + unavailable.count; tokenStored = savedTokens; tokenDiscoveryRemaining = unknown; storedBytes = bytes
            missingTokenNames = missingTokens + unavailable
            missingTokenIDs = missingIDs
            unavailableTokenNames = unavailable
            faceDiscoveryPending = pendingFaces
            scanSucceeded = true
            if !isRunning {
                status = "\(cardStored) of \(cardTotal) card images stored on this device."
                if !failures.isEmpty { status += " \(failures.count) artwork issues need attention." }
            }
        } catch { if generation == scanGeneration { status = error.localizedDescription } }
    }
    func download(names rawNames: [String], includeTokens: Bool, allowNetwork: Bool,
                  quality: NativeArtworkQuality = .high, fullCatalogue: Bool = false,
                  tokenOnly: Bool = false) {
        guard !isRunning else { return }
        guard allowNetwork else { status = "Enable online artwork before downloading from Scryfall."; return }
        guard !tokenOnly || (fullCatalogue && includeTokens) else { status = "Token-only downloads require the supported token catalogue."; return }
        let inputNames: [String]
        do { inputNames = tokenOnly ? [] : try Self.names(rawNames) } catch { status = error.localizedDescription; return }
        scanContext = ScanContext(names: inputNames, quality: quality, fullCatalogue: fullCatalogue, tokenOnly: tokenOnly)
        if let backgroundQueue {
            prepareBackgroundDownload(names: inputNames, includeTokens: includeTokens, quality: quality,
                                      fullCatalogue: fullCatalogue, tokenOnly: tokenOnly, queue: backgroundQueue)
            return
        }
        isRunning = true; failures = []; completed = 0; total = inputNames.count
        task = Task { [weak self] in
            guard let self else { return }
            var names = inputNames
            var stopped = false
            var savedCards = Set<String>()
            var savedTokens = Set<String>()
            do {
                await scan(names: names, quality: quality, fullCatalogue: fullCatalogue, tokenOnly: tokenOnly)
                try Task.checkCancellation()
                status = fullCatalogue ? "Preparing Scryfall artwork catalogue…" : "Preparing artwork downloads…"
                let catalogue = fullCatalogue ? try await catalogueLoader() : nil
                try Task.checkCancellation()
                if let catalogue, !tokenOnly {
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
                for name in tokenOnly ? [] : names {
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
                await scan(names: names, quality: quality, fullCatalogue: fullCatalogue, tokenOnly: tokenOnly)
                try Task.checkCancellation()
                savedCards = []
                if includeTokens && !stopped {
                    total += tokens.count
                    for token in tokens {
                        try Task.checkCancellation()
                        status = "Downloading token: \(token.name)…"
                        do {
                            if await store.tokenDetails(id: token.id, face: token.face) == nil {
                                let details: NativeTokenArtwork
                                if let catalogue {
                                    guard let found = catalogue.token(id: token.id, face: token.face) else { throw DeckStudioScryfallError.invalidResponse }
                                    details = found
                                } else { details = try await discovery.details(id: token.id) }
                                try Task.checkCancellation()
                                try await store.saveToken(details)
                            }
                            if await store.image(key: token.artworkKey, quality: quality) == nil {
                                let url = catalogue?.imageURL(id: token.id, size: quality.imageSizeString, face: token.face)
                                if fullCatalogue && url == nil { throw DeckStudioScryfallError.invalidResponse }
                                guard let data = try await artwork.imageData(id: token.id, allowNetwork: true, quality: quality, imageURL: url, face: token.face) else { throw NativeAssetStore.StoreError.invalidImage }
                                try Task.checkCancellation()
                                try await store.save(data, key: token.artworkKey, quality: quality)
                            }
                            savedTokens.insert(token.artworkKey)
                        } catch is CancellationError { throw CancellationError() }
                        catch {
                            failures.append("Token \(token.name): \(error.localizedDescription)")
                            if Self.mustStop(error) { stopped = true; break }
                        }
                        completed += 1
                    }
                }
                try Task.checkCancellation()
                await scan(names: names, quality: quality, fullCatalogue: fullCatalogue, tokenOnly: tokenOnly)
                status = stopped ? "Download paused after an error. Completed images are preserved; retry when ready." :
                    (failures.isEmpty ? "Download complete." : "Download finished with \(failures.count) issues. Retry missing items when ready.")
            } catch {
                // A cancelled catalogue run must not spend minutes scanning every
                // file. Retain verified progress; the next explicit check rescans.
                missingNames.removeAll { savedCards.contains($0) }
                cardStored = cardTotal - missingNames.count
                missingTokenIDs.subtract(savedTokens)
                missingTokenNames = tokens.filter { self.missingTokenIDs.contains($0.artworkKey) }.map(\.name) + unavailableTokenNames
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
    private func syncBackgroundProgress() {
        guard !preparingBackgroundJob, let queue = backgroundQueue else { return }
        let wasRunning = isRunning
        isRunning = queue.isRunning
        completed = queue.completed; total = queue.total
        status = !queue.isRunning && !preparationFailures.isEmpty
            ? "\(preparationFailures.count) images could not be prepared. Review Needs attention below."
            : queue.status
        failures = preparationFailures + queue.failureMessages
        if wasRunning && !isRunning {
            NotificationCenter.default.post(name: Self.didFinish, object: nil)
            if let context = scanContext {
                isScanning = true
                Task { [weak self] in
                    await self?.scan(names: context.names, quality: context.quality,
                                     fullCatalogue: context.fullCatalogue, tokenOnly: context.tokenOnly)
                }
            }
        }
    }

    private func prepareBackgroundDownload(names inputNames: [String], includeTokens: Bool,
                                           quality: NativeArtworkQuality, fullCatalogue: Bool,
                                           tokenOnly: Bool, queue: NativeArtworkBackgroundQueue) {
        preparingBackgroundJob = true; isRunning = true; failures = []; preparationFailures = []
        completed = 0; total = inputNames.count
        status = "Preparing image list… You can play while this finishes."
#if canImport(UIKit)
        preparationBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Prepare artwork downloads") { [weak self] in
            // The image queue uses its own system background session. Preparation
            // may suspend here and continue when the app next becomes active.
            self?.finishPreparationBackgroundTime()
        }
#endif
        task = Task { [weak self] in
            guard let self else { return }
            defer {
#if canImport(UIKit)
                finishPreparationBackgroundTime()
#endif
            }
            do {
                let catalogue = fullCatalogue ? try await catalogueLoader() :
                    try await deckCatalogueLoader(inputNames, includeTokens)
                try Task.checkCancellation()
                let faces = tokenOnly ? [] : catalogue.additionalFaceNames(for: inputNames)
                let names = tokenOnly ? [] : try Self.names(inputNames + faces)
                if fullCatalogue && !tokenOnly { try await store.saveCatalogueFaces(faces) }
                var entries: [NativeArtworkBackgroundQueue.Entry] = []
                var tokenIDs = Set<String>()
                var relatedTokens: [NativeTokenArtwork] = []
                for name in names {
                    try Task.checkCancellation()
                    if includeTokens && !fullCatalogue {
                        let related = catalogue.relatedTokens(name: name)
                        try await store.saveRelations(related, name: name)
                        relatedTokens += related.filter { tokenIDs.insert($0.artworkKey).inserted }
                    }
                    let key = NativeAssetStore.cardKey(name)
                    if await store.image(key: key, quality: quality) == nil {
                        if let url = catalogue.imageURL(name: name, size: quality.imageSizeString) {
                            entries.append(.init(key: key, name: name, url: url, quality: quality))
                        } else { preparationFailures.append("\(name): artwork is unavailable.") }
                    }
                }
                if includeTokens {
                    if fullCatalogue {
                        relatedTokens = catalogue.allTokens
                        try await store.saveCatalogueTokens(relatedTokens, unavailableNames: catalogue.unavailableTokenNames)
                        preparationFailures += catalogue.unavailableTokenNames.map { "Token \($0): artwork is unavailable." }
                    }
                    for related in relatedTokens {
                        try Task.checkCancellation()
                        guard let token = catalogue.token(id: related.id, face: related.face), token.hasMatchingMetadata,
                              let url = catalogue.imageURL(id: related.id, size: quality.imageSizeString, face: related.face) else {
                            preparationFailures.append("Token \(related.name): safe artwork metadata is unavailable.")
                            continue
                        }
                        try await store.saveToken(token)
                        let key = token.artworkKey
                        if await store.image(key: key, quality: quality) == nil {
                            entries.append(.init(key: key, name: token.name, url: url, quality: quality))
                        }
                    }
                }
                try Task.checkCancellation()
                try queue.start(entries: entries)
                preparingBackgroundJob = false; task = nil
                syncBackgroundProgress()
                await scan(names: inputNames, quality: quality, fullCatalogue: fullCatalogue, tokenOnly: tokenOnly)
            } catch {
                preparingBackgroundJob = false; isRunning = false; task = nil
                status = error is CancellationError ? "Download cancelled. Completed images remain available offline." :
                    "Could not prepare downloads. Try again when connected."
                if !(error is CancellationError) { failures = [error.localizedDescription] }
            }
        }
    }

    func cancel() { task?.cancel(); backgroundQueue?.cancel() }
#if canImport(UIKit)
    private func finishPreparationBackgroundTime() {
        guard preparationBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(preparationBackgroundTask)
        preparationBackgroundTask = .invalid
    }
#endif
    private static func mustStop(_ error: Error) -> Bool {
        if let value = error as? NativeDeckArtwork.ArtworkError, [.rateLimited, .httpStatus(403), .httpStatus(401)].contains(value) { return true }
        if let value = error as? DeckStudioScryfallError, [.rateLimited, .unavailable, .http(403), .http(401)].contains(value) { return true }
        if error is URLError { return true }
        return error is NativeAssetStore.StoreError
    }
}
