import Foundation
import ImageIO

/// Artwork only; never resolves or changes rules/deck metadata.
/// Network callers must obtain consent to share card names and IP with Scryfall.
actor NativeDeckArtwork {
    static let shared = NativeDeckArtwork()
    static let maximumBytes = 2 * 1024 * 1024
    static let maximumPixels = 4_000_000
    enum Variant: String, Hashable {
        case compact = "small"
        case board = "normal"
        case inspection = "large"
        var minimumShortEdge: Int { self == .inspection ? 672 : 1 }
        var maximumDecodedEdge: Int { self == .inspection ? 1400 : 680 }
    }
    static let requestSpacing: TimeInterval = 0.51
    enum ArtworkError: Error, Equatable {
        case invalidInput, unsafeURL, invalidResponse, oversized, tooManyRedirects
        case httpStatus(Int), rateLimited
    }
    private let cache: URLCache
    private let assetStore: NativeAssetStore
    private let protocolClasses: [AnyClass]?
    private let requestBudget: DeckStudioScryfallBudget
    private let tokenLookup: @Sendable (String, String, String, String?, String?, [String], NativeArtworkQuality) async throws -> (NativeTokenArtwork, URL)?
    private var tokenBusy = Set<String>()
    private var tokenRetryAfter: [String: TimeInterval] = [:]
    private var networkBusy = false
    private var nextRequestAt: TimeInterval = 0
    private var blockedUntil: TimeInterval = 0
    init(cache: URLCache = URLCache(memoryCapacity: 8 * 1024 * 1024,
                                  diskCapacity: 64 * 1024 * 1024, diskPath: "MagicMobileNativeDeckArtwork"),
         protocolClasses: [AnyClass]? = nil, requestBudget: DeckStudioScryfallBudget? = nil,
         assetStore: NativeAssetStore = .shared,
         tokenLookup: @escaping @Sendable (String, String, String, String?, String?, [String], NativeArtworkQuality) async throws -> (NativeTokenArtwork, URL)? = {
             try await NativeArtworkCatalogue.searchToken(name: $0, typeLine: $1, oracleText: $2,
                                                          power: $3, toughness: $4, colors: $5, quality: $6)
         }) {
        self.cache = cache; self.protocolClasses = protocolClasses
        self.assetStore = assetStore
        self.tokenLookup = tokenLookup
        // Production artwork and card-reference lookups share one budget.
        // Injected HTTP fixture sessions default to an isolated budget.
        self.requestBudget = requestBudget ?? (protocolClasses == nil ? .shared : DeckStudioScryfallBudget())
    }
    func imageData(name: String, variant: Variant = .board, allowNetwork: Bool,
                   tokenTypeLine: String? = nil, tokenOracleText: String? = nil,
                   tokenPower: String? = nil, tokenToughness: String? = nil, tokenColors: [String]? = nil,
                   tokenSourceName: String? = nil) async throws -> Data? {
        try Task.checkCancellation()
        if let tokenTypeLine {
            // Only a caller with an explicitly disclosed copy-source identity may
            // use ordinary card artwork; never infer one from a generic token name.
            if let tokenSourceName, Self.permitsSourceName(tokenSourceName) {
                return try await imageData(name: tokenSourceName, variant: variant, allowNetwork: allowNetwork)
            }
            let quality: NativeArtworkQuality = variant == .inspection ? .high : (variant == .board ? .standard : .compact)
            let stored = await assetStore.tokenImage(name: name, typeLine: tokenTypeLine, oracleText: tokenOracleText,
                                                      power: tokenPower, toughness: tokenToughness, colors: tokenColors,
                                                      offlineFallback: !allowNetwork)
            if let stored, (!allowNetwork || quality.accepts(stored)) { return stored }
            guard allowNetwork, let tokenOracleText, let tokenColors, !tokenTypeLine.isEmpty,
                  !name.isEmpty, Set(tokenColors).isSubset(of: ["W", "U", "B", "R", "G"]),
                  Set(tokenColors).count == tokenColors.count else { return stored }
            let key = [name, tokenTypeLine, tokenOracleText, tokenPower ?? "", tokenToughness ?? "",
                       tokenColors.sorted().joined(), quality.rawValue].joined(separator: "\u{1f}")
            while tokenBusy.contains(key) { try await Task.sleep(for: .milliseconds(20)) }
            tokenBusy.insert(key)
            defer { tokenBusy.remove(key) }
            // Reserve before crossing another actor boundary. Otherwise two callers
            // can both observe a cache miss and issue duplicate catalogue searches.
            if let upgraded = await assetStore.tokenImage(name: name, typeLine: tokenTypeLine, oracleText: tokenOracleText,
                                                          power: tokenPower, toughness: tokenToughness, colors: tokenColors,
                                                          quality: quality) { return upgraded }
            guard ProcessInfo.processInfo.systemUptime >= tokenRetryAfter[key, default: 0] else { return stored }
            do {
                guard let (token, url) = try await tokenLookup(name, tokenTypeLine, tokenOracleText,
                                                               tokenPower, tokenToughness, tokenColors, quality) else {
                    tokenRetryAfter[key] = ProcessInfo.processInfo.systemUptime + 600
                    return stored
                }
                // Recheck the exact visible identity even for an injected provider.
                guard NativeAssetStore.matchTokenArtwork([token], name: name, typeLine: tokenTypeLine,
                                                         oracleText: tokenOracleText, power: tokenPower,
                                                         toughness: tokenToughness, colors: tokenColors) != nil else { return stored }
                let data = try await downloadImage(name: token.name, quality: quality, imageURL: url)
                guard let data else { return stored }
                try Task.checkCancellation()
                try await assetStore.saveToken(token)
                try await assetStore.save(data, key: token.artworkKey, quality: quality)
                return data
            } catch is CancellationError { throw CancellationError() }
            catch {
                tokenRetryAfter[key] = ProcessInfo.processInfo.systemUptime + 120
                if let stored { return stored }
                throw error
            }
        }
        let original = try Self.request(name: name, variant: variant)
        let downloaded = await assetStore.image(key: NativeAssetStore.cardKey(name))
        // Bulk-download quality stays untouched. Live upgrades use only the bounded
        // URL cache, and happen only with explicit network consent.
        if let downloaded {
            let quality: NativeArtworkQuality = variant == .inspection ? .high : (variant == .board ? .standard : .compact)
            if !allowNetwork || quality.accepts(downloaded) { return downloaded }
        }
        do { return try await imageData(request: original, variant: variant, allowNetwork: allowNetwork) ?? downloaded }
        catch is CancellationError { throw CancellationError() }
        catch { if let downloaded { return downloaded }; throw error }
    }
    func downloadImage(name: String, quality: NativeArtworkQuality, imageURL: URL? = nil) async throws -> Data? {
        let variant = Self.variant(for: quality)
        let request = try imageURL.map { try Self.request(url: $0) } ?? Self.request(name: name, variant: variant)
        return try await imageData(request: request, variant: variant, allowNetwork: true)
    }
    func imageData(id: UUID, allowNetwork: Bool, quality: NativeArtworkQuality = .high, imageURL: URL? = nil, face: String? = nil) async throws -> Data? {
        if let data = await assetStore.image(key: NativeAssetStore.tokenKey(id, face: face), quality: quality) { return data }
        let url = imageURL ?? URL(string: "https://api.scryfall.com/cards/\(id.uuidString.lowercased())?format=image&version=\(quality.imageSizeString)\(face == "back" ? "&face=back" : "")")!
        return try await imageData(request: Self.request(url: url), variant: Self.variant(for: quality), allowNetwork: allowNetwork)
    }
    private static func variant(for quality: NativeArtworkQuality) -> Variant {
        switch quality {
        case .compact: return .compact
        case .standard: return .board
        case .high: return .inspection
        }
    }
    private func imageData(request original: URLRequest, variant: Variant, allowNetwork: Bool) async throws -> Data? {
        if let data = cachedData(for: original, variant: variant) { return data }
        guard allowNetwork else { return nil }
        while networkBusy { try await Task.sleep(for: .milliseconds(10)) }
        try Task.checkCancellation()
        networkBusy = true
        defer { networkBusy = false }
        if let data = cachedData(for: original, variant: variant) { return data }
        let configuration = URLSessionConfiguration.ephemeral
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 25
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        return try await withTaskCancellationHandler {
            var request = original
            for hop in 0...5 {
                try await reserveRequest()
                if request.url?.host?.lowercased() == "api.scryfall.com" {
                    do { try await requestBudget.reserve() }
                    catch is CancellationError { throw CancellationError() }
                    catch { throw ArtworkError.rateLimited }
                }
                let (bytes, response) = try await session.bytes(for: request, delegate: NoRedirects())
                defer { bytes.task.cancel() }
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse,
                      let responseURL = http.url, Self.isAllowed(responseURL) else { throw ArtworkError.invalidResponse }
                if http.statusCode == 429 {
                    let delay = Self.retryDelay(http.value(forHTTPHeaderField: "Retry-After"))
                    blockedUntil = ProcessInfo.processInfo.systemUptime + delay
                    await requestBudget.backOff(delay)
                    throw ArtworkError.rateLimited
                }
                if [301, 302, 303, 307, 308].contains(http.statusCode) {
                    guard hop < 5 else { throw ArtworkError.tooManyRedirects }
                    request = try Self.redirectRequest(response: http)
                    continue
                }
                try Self.validate(http)
                var data = Data()
                for try await byte in bytes { try Task.checkCancellation(); try Self.append(byte, to: &data) }
                guard Self.isSufficient(data, for: variant) else { throw ArtworkError.invalidResponse }
                try Task.checkCancellation()
                cache.storeCachedResponse(CachedURLResponse(response: http, data: data, storagePolicy: .allowed), for: original)
                return data
            }
            throw ArtworkError.tooManyRedirects
        } onCancel: { session.invalidateAndCancel() }
    }
    private func cachedData(for request: URLRequest, variant: Variant) -> Data? {
        guard let entry = cache.cachedResponse(for: request), let http = entry.response as? HTTPURLResponse,
              (try? Self.validate(http)) != nil, !entry.data.isEmpty,
              Self.isSufficient(entry.data, for: variant) else { return nil }
        return entry.data
    }
    static func isSufficient(_ data: Data, for variant: Variant) -> Bool {
        guard let source = boundedSource(data),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return false }
        return min(width, height) >= variant.minimumShortEdge
    }
    private static func boundedSource(_ data: Data) -> CGImageSource? {
        guard !data.isEmpty, data.count <= maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              CGImageSourceGetStatus(source) == .statusComplete,
              let type = CGImageSourceGetType(source) as String?, ["public.jpeg", "public.png"].contains(type),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= maximumPixels / height else { return nil }
        return source
    }
    static func decodedImage(_ data: Data, variant: Variant) -> CGImage? {
        guard let source = boundedSource(data) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: variant.maximumDecodedEdge,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }
    /// Deck-cover presentation only: crop inside the illustration window of a
    /// conventional card, leaving the stored/full inspection image untouched.
    static func illustrationImage(_ image: CGImage) -> CGImage? {
        let bounds = CGRect(x: Double(image.width) * 0.08, y: Double(image.height) * 0.145,
                            width: Double(image.width) * 0.84, height: Double(image.height) * 0.385)
        return image.cropping(to: bounds.integral)
    }
    static func localImageData(at url: URL) -> Data? {
        guard url.isFileURL, let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true, let size = values.fileSize, size > 0, size <= maximumBytes,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe), boundedSource(data) != nil else { return nil }
        return data
    }
    private func reserveRequest() async throws {
        while true {
            try Task.checkCancellation()
            let now = ProcessInfo.processInfo.systemUptime
            guard now >= blockedUntil else { throw ArtworkError.rateLimited }
            let delay = nextRequestAt - now
            if delay <= 0 { nextRequestAt = now + Self.requestSpacing; return }
            try await Task.sleep(for: .seconds(delay))
        }
    }
    static func request(name: String, variant: Variant = .board) throws -> URLRequest {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.utf8.count <= 512,
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw ArtworkError.invalidInput }
        var url = URLComponents(string: "https://api.scryfall.com/cards/named")!
        url.queryItems = [URLQueryItem(name: "exact", value: name), URLQueryItem(name: "format", value: "image"), URLQueryItem(name: "version", value: variant.rawValue)]
        guard let endpoint = url.url else { throw ArtworkError.invalidInput }
        return try request(url: endpoint)
    }
    static func permitsSourceName(_ name: String) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !["", "hidden card", "face-down card", "face down card", "face-down", "face down",
                 "card details unavailable"].contains(normalized)
    }
    private static func request(url: URL) throws -> URLRequest {
        guard isAllowed(url) else { throw ArtworkError.unsafeURL }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpShouldHandleCookies = false
        request.setValue("MagicMobile-NativeDeckArtwork/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("image/jpeg,image/png;q=0.9", forHTTPHeaderField: "Accept")
        return request
    }
    static func isAllowed(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return parts.scheme?.lowercased() == "https" && parts.user == nil && parts.password == nil &&
            (parts.port == nil || parts.port == 443) && parts.fragment == nil &&
            ["api.scryfall.com", "cards.scryfall.io"].contains(parts.host?.lowercased() ?? "")
    }
    static func redirectRequest(response: HTTPURLResponse) throws -> URLRequest {
        guard let location = response.value(forHTTPHeaderField: "Location"), let base = response.url,
              let url = URL(string: location, relativeTo: base)?.absoluteURL else { throw ArtworkError.unsafeURL }
        return try request(url: url)
    }
    static func validate(_ response: HTTPURLResponse) throws {
        guard let url = response.url, isAllowed(url) else { throw ArtworkError.unsafeURL }
        guard response.statusCode == 200 else { throw ArtworkError.httpStatus(response.statusCode) }
        guard response.expectedContentLength <= Int64(maximumBytes) else { throw ArtworkError.oversized }
        guard ["image/jpeg", "image/png"].contains(response.mimeType?.lowercased() ?? "") else { throw ArtworkError.invalidResponse }
    }
    static func append(_ byte: UInt8, to data: inout Data) throws {
        guard data.count < maximumBytes else { throw ArtworkError.oversized }
        data.append(byte)
    }
    static func retryDelay(_ value: String?, now: Date = Date()) -> TimeInterval {
        if let value, let seconds = TimeInterval(value), seconds.isFinite { return max(30, seconds) }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        return max(30, value.flatMap(formatter.date(from:))?.timeIntervalSince(now) ?? 30)
    }
    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
        func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
        }
    }
}
