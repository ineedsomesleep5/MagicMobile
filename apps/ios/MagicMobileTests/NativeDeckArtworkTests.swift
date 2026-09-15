import XCTest
@testable import MagicMobile

final class NativeDeckArtworkTests: XCTestCase {
    func testExactNameIsEncodedAsOneQueryValueAndUsesExplicitHeaders() throws {
        let name = "Fire // Ice & Éowyn?format=json#secret"
        let request = try NativeDeckArtwork.request(name: name)
        let parts = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.host, "api.scryfall.com")
        XCTAssertEqual(parts.path, "/cards/named")
        XCTAssertEqual(parts.queryItems, [URLQueryItem(name: "exact", value: name),
                                         URLQueryItem(name: "format", value: "image"),
                                         URLQueryItem(name: "version", value: "normal")])
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "MagicMobile-NativeDeckArtwork/1.0")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "image/jpeg,image/png;q=0.9")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertEqual(request.timeoutInterval, 15)
        XCTAssertThrowsError(try NativeDeckArtwork.request(name: "\n"))
        XCTAssertThrowsError(try NativeDeckArtwork.request(name: String(repeating: "x", count: 513)))
    }

    func testRedirectsAllowOnlyHTTPSExactHostsWithoutCredentials() throws {
        for text in ["https://api.scryfall.com/cards/named", "https://cards.scryfall.io/normal/front/a.jpg"] {
            XCTAssertTrue(NativeDeckArtwork.isAllowed(try XCTUnwrap(URL(string: text))))
        }
        for text in ["http://cards.scryfall.io/a.jpg", "https://cards.scryfall.io.evil.test/a.jpg",
                     "https://evil.test/a.jpg", "https://user:pass@api.scryfall.com/a",
                     "https://api.scryfall.com:444/a", "file:///tmp/card.jpg",
                     "https://api.scryfall.com/a#fragment"] {
            XCTAssertFalse(NativeDeckArtwork.isAllowed(try XCTUnwrap(URL(string: text))), text)
            XCTAssertThrowsError(try NativeDeckArtwork.redirectRequest(response: response(status: 302, headers: ["Location": text])))
        }
        let redirect = try NativeDeckArtwork.redirectRequest(response: response(status: 302, headers: [
            "Location": "https://cards.scryfall.io/normal/front/a.jpg", "Set-Cookie": "secret=1"
        ]))
        XCTAssertEqual(redirect.url?.host, "cards.scryfall.io")
        XCTAssertNil(redirect.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(redirect.value(forHTTPHeaderField: "Authorization"))
    }

    func testStatusMIMEAndDeclaredOrStreamedSizeBounds() throws {
        try NativeDeckArtwork.validate(response(status: 200, headers: ["Content-Type": "image/jpeg"]))
        for status in [204, 301, 401, 404, 429, 500] {
            XCTAssertThrowsError(try NativeDeckArtwork.validate(response(status: status, headers: ["Content-Type": "image/jpeg"])))
        }
        XCTAssertThrowsError(try NativeDeckArtwork.validate(response(status: 200, headers: ["Content-Type": "text/html"])))
        XCTAssertThrowsError(try NativeDeckArtwork.validate(response(status: 200, headers: [
            "Content-Type": "image/png", "Content-Length": String(NativeDeckArtwork.maximumBytes + 1)
        ])))
        var data = Data(repeating: 0, count: NativeDeckArtwork.maximumBytes - 1)
        try NativeDeckArtwork.append(1, to: &data)
        XCTAssertEqual(data.count, NativeDeckArtwork.maximumBytes)
        XCTAssertThrowsError(try NativeDeckArtwork.append(2, to: &data))
        XCTAssertEqual(data.count, NativeDeckArtwork.maximumBytes)
    }

    func testOfflineMissDoesNotRequireNetworkAndOfflineCacheHitIsReturned() async throws {
        let cache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 0, diskPath: nil)
        let artwork = NativeDeckArtwork(cache: cache)
        let miss = try await artwork.imageData(name: "Black Lotus", allowNetwork: false)
        XCTAssertNil(miss)
        let request = try NativeDeckArtwork.request(name: "Black Lotus")
        let bytes = Data([0xff, 0xd8, 0xff, 0xd9])
        let http = try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 200,
                                               httpVersion: nil, headerFields: ["Content-Type": "image/jpeg"]))
        cache.storeCachedResponse(CachedURLResponse(response: http, data: bytes), for: request)
        let hit = try await artwork.imageData(name: "Black Lotus", allowNetwork: false)
        XCTAssertEqual(hit, bytes)
    }

    func testFileLookingNameIsLiteralAndOfflineMissNeverReadsAFile() async throws {
        let name = "file:///private/nonexistent-imported-card.jpg?format=json#fragment"
        let request = try NativeDeckArtwork.request(name: name)
        let parts = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.scheme, "https")
        XCTAssertEqual(parts.host, "api.scryfall.com")
        XCTAssertEqual(parts.queryItems?.first(where: { $0.name == "exact" })?.value, name)
        let artwork = NativeDeckArtwork(cache: URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil))
        let result = try await artwork.imageData(name: name, allowNetwork: false)
        XCTAssertNil(result)
    }

    func testBackoffHonorsRetryAfterAndOfficialMinimum() {
        XCTAssertGreaterThanOrEqual(NativeDeckArtwork.requestSpacing, 0.5)
        XCTAssertEqual(NativeDeckArtwork.retryDelay(nil), 30)
        XCTAssertEqual(NativeDeckArtwork.retryDelay("1"), 30)
        XCTAssertEqual(NativeDeckArtwork.retryDelay("120"), 120)
        XCTAssertEqual(NativeDeckArtwork.retryDelay("invalid"), 30)
        XCTAssertEqual(NativeDeckArtwork.retryDelay("Thu, 01 Jan 1970 00:02:00 GMT", now: Date(timeIntervalSince1970: 0)), 120)
    }

    private func response(status: Int, headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://api.scryfall.com/cards/named")!, statusCode: status,
                        httpVersion: nil, headerFields: headers)!
    }
}
