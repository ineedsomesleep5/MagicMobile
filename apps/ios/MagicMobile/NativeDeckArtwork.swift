import Foundation

/// Artwork only; never resolves or changes rules/deck metadata.
/// Network callers must obtain consent to share card names and IP with Scryfall.
actor NativeDeckArtwork {
    static let shared = NativeDeckArtwork()
    static let maximumBytes = 2 * 1024 * 1024
    // https://scryfall.com/docs/api/rate-limits: /cards/named is limited to 2/s.
    static let requestSpacing: TimeInterval = 0.51

    enum ArtworkError: Error, Equatable {
        case invalidInput, unsafeURL, invalidResponse, oversized, tooManyRedirects
        case httpStatus(Int), rateLimited
    }

    private let cache: URLCache
    private var networkBusy = false
    private var nextRequestAt: TimeInterval = 0
    private var blockedUntil: TimeInterval = 0

    init(cache: URLCache = URLCache(memoryCapacity: 8 * 1024 * 1024,
                                  diskCapacity: 64 * 1024 * 1024,
                                  diskPath: "MagicMobileNativeDeckArtwork")) {
        self.cache = cache
    }

    func imageData(name: String, allowNetwork: Bool) async throws -> Data? {
        try Task.checkCancellation()
        // Imported card names are literal query values, never filesystem paths.
        let original = try Self.request(name: name)
        if let data = cachedData(for: original) { return data }
        // Do not create a session, reserve network work, or revalidate HTTP caches offline.
        guard allowNetwork else { return nil }
        while networkBusy {
            try await Task.sleep(for: .milliseconds(10))
        }
        try Task.checkCancellation()
        networkBusy = true
        defer { networkBusy = false }
        if let data = cachedData(for: original) { return data }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = original
        for hop in 0...5 {
            try await reserveRequest()
            let (bytes, response) = try await session.bytes(for: request, delegate: NoRedirects())
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse,
                  let responseURL = http.url, Self.isAllowed(responseURL) else {
                throw ArtworkError.invalidResponse
            }
            if http.statusCode == 429 {
                blockedUntil = ProcessInfo.processInfo.systemUptime + Self.retryDelay(http.value(forHTTPHeaderField: "Retry-After"))
                throw ArtworkError.rateLimited
            }
            if [301, 302, 303, 307, 308].contains(http.statusCode) {
                guard hop < 5 else { throw ArtworkError.tooManyRedirects }
                request = try Self.redirectRequest(response: http)
                continue
            }
            try Self.validate(http)
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                try Self.append(byte, to: &data)
            }
            guard !data.isEmpty else { throw ArtworkError.invalidResponse }
            // Explicitly retain the successful artwork under the original exact-name key.
            // URLCache enforces cache budgets; no metadata/catalogue files are touched.
            cache.storeCachedResponse(CachedURLResponse(response: http, data: data, storagePolicy: .allowed), for: original)
            return data
        }
        throw ArtworkError.tooManyRedirects
    }

    private func cachedData(for request: URLRequest) -> Data? {
        guard let entry = cache.cachedResponse(for: request), let http = entry.response as? HTTPURLResponse,
              (try? Self.validate(http)) != nil, !entry.data.isEmpty,
              entry.data.count <= Self.maximumBytes else { return nil }
        return entry.data
    }

    private func reserveRequest() async throws {
        while true {
            try Task.checkCancellation()
            let now = ProcessInfo.processInfo.systemUptime
            guard now >= blockedUntil else { throw ArtworkError.rateLimited }
            let delay = nextRequestAt - now
            if delay <= 0 {
                nextRequestAt = now + Self.requestSpacing
                return
            }
            try await Task.sleep(for: .seconds(delay))
        }
    }

    static func request(name: String) throws -> URLRequest {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.utf8.count <= 512,
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw ArtworkError.invalidInput
        }
        var url = URLComponents(string: "https://api.scryfall.com/cards/named")!
        url.queryItems = [URLQueryItem(name: "exact", value: name), URLQueryItem(name: "format", value: "image"),
                          URLQueryItem(name: "version", value: "normal")]
        guard let endpoint = url.url else { throw ArtworkError.invalidInput }
        return try request(url: endpoint)
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
        // Rebuild instead of forwarding cookies, credentials, or arbitrary response headers.
        return try request(url: url)
    }

    static func validate(_ response: HTTPURLResponse) throws {
        guard let url = response.url, isAllowed(url) else { throw ArtworkError.unsafeURL }
        guard response.statusCode == 200 else { throw ArtworkError.httpStatus(response.statusCode) }
        guard response.expectedContentLength <= Int64(maximumBytes) else { throw ArtworkError.oversized }
        guard ["image/jpeg", "image/png"].contains(response.mimeType?.lowercased() ?? "") else {
            throw ArtworkError.invalidResponse
        }
    }

    static func append(_ byte: UInt8, to data: inout Data) throws {
        guard data.count < maximumBytes else { throw ArtworkError.oversized }
        data.append(byte)
    }

    static func retryDelay(_ value: String?, now: Date = Date()) -> TimeInterval {
        if let value, let seconds = TimeInterval(value), seconds.isFinite { return max(30, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        return max(30, value.flatMap(formatter.date(from:))?.timeIntervalSince(now) ?? 30)
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
                              ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
        }
    }
}
