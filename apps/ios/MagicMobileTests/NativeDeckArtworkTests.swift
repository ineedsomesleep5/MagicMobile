import XCTest
import CoreGraphics
import ImageIO
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
        let bytes = try png(width: 32, height: 44)
        let http = try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 200,
                                               httpVersion: nil, headerFields: ["Content-Type": "image/jpeg"]))
        cache.storeCachedResponse(CachedURLResponse(response: http, data: bytes), for: request)
        let hit = try await artwork.imageData(name: "Black Lotus", allowNetwork: false)
        XCTAssertEqual(hit, bytes)
    }

    func testInspectionRequestAndCacheAreSeparateFromBoard() async throws {
        let cache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 0, diskPath: nil)
        let artwork = NativeDeckArtwork(cache: cache)
        let board = try NativeDeckArtwork.request(name: "Serra Angel", variant: .board)
        let inspection = try NativeDeckArtwork.request(name: "Serra Angel", variant: .inspection)
        XCTAssertNotEqual(board.url, inspection.url)
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(inspection.url), resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "version" })?.value, "large")
        let small = try png(width: 488, height: 680)
        let large = try png(width: 672, height: 936)
        func store(_ bytes: Data, for request: URLRequest) throws {
            let response = try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 200,
                httpVersion: nil, headerFields: ["Content-Type": "image/png"]))
            cache.storeCachedResponse(CachedURLResponse(response: response, data: bytes), for: request)
        }
        try store(small, for: board)
        let miss = try await artwork.imageData(name: "Serra Angel", variant: .inspection, allowNetwork: false)
        XCTAssertNil(miss)
        // Even a legacy undersized response under the large key cannot satisfy inspection.
        try store(small, for: inspection)
        let undersized = try await artwork.imageData(name: "Serra Angel", variant: .inspection, allowNetwork: false)
        XCTAssertNil(undersized)
        try store(large, for: inspection)
        let hit = try await artwork.imageData(name: "Serra Angel", variant: .inspection, allowNetwork: false)
        XCTAssertEqual(hit, large)
        let boardHit = try await artwork.imageData(name: "Serra Angel", variant: .board, allowNetwork: false)
        XCTAssertEqual(boardHit, small)
    }

    func testImageDimensionsAndDecodeAreBounded() throws {
        let small = try png(width: 488, height: 680)
        XCTAssertTrue(NativeDeckArtwork.isSufficient(small, for: .board))
        XCTAssertFalse(NativeDeckArtwork.isSufficient(small, for: .inspection))
        XCTAssertNotNil(NativeDeckArtwork.decodedImage(small, variant: .inspection), "Safe offline fallback remains renderable")
        let large = try png(width: 1000, height: 1500)
        XCTAssertTrue(NativeDeckArtwork.isSufficient(large, for: .inspection))
        let decoded = try XCTUnwrap(NativeDeckArtwork.decodedImage(large, variant: .inspection))
        XCTAssertLessThanOrEqual(max(decoded.width, decoded.height), 1400)
        let board = try XCTUnwrap(NativeDeckArtwork.decodedImage(large, variant: .board))
        XCTAssertLessThanOrEqual(max(board.width, board.height), 680)
        let excessivePixels = try png(width: 2001, height: 2000)
        XCTAssertLessThan(excessivePixels.count, NativeDeckArtwork.maximumBytes)
        XCTAssertFalse(NativeDeckArtwork.isSufficient(excessivePixels, for: .inspection))
        XCTAssertNil(NativeDeckArtwork.decodedImage(excessivePixels, variant: .inspection))
        for invalid in [Data(), Data([0xff, 0xd8, 0xff, 0xd9]), Data(repeating: 0, count: NativeDeckArtwork.maximumBytes + 1)] {
            XCTAssertFalse(NativeDeckArtwork.isSufficient(invalid, for: .inspection))
            XCTAssertNil(NativeDeckArtwork.decodedImage(invalid, variant: .board))
        }
    }

    func testUndersizedLocalCacheIsOnlyAFallbackAndInvalidLocalDataIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("cached.png")
        let small = try png(width: 488, height: 680)
        try small.write(to: url)
        let local = try XCTUnwrap(NativeDeckArtwork.localImageData(at: url))
        XCTAssertEqual(local, small)
        XCTAssertFalse(NativeDeckArtwork.isSufficient(local, for: .inspection))
        XCTAssertNotNil(NativeDeckArtwork.decodedImage(local, variant: .inspection))
        try Data("not artwork".utf8).write(to: url)
        XCTAssertNil(NativeDeckArtwork.localImageData(at: url))
        try Data(repeating: 0, count: NativeDeckArtwork.maximumBytes + 1).write(to: url)
        XCTAssertNil(NativeDeckArtwork.localImageData(at: url))
        XCTAssertNil(NativeDeckArtwork.localImageData(at: URL(string: "https://example.invalid/image")!))
    }

    private func png(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
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

    func testCancellationStopsSuspendedHeadersAndBodyWithoutCaching() async throws {
        // Every request is intercepted locally. This test cannot reach Scryfall.
        for sendHeaders in [false, true] {
            let started = expectation(description: "Mock artwork request started")
            let stopped = expectation(description: "Mock artwork request cancelled")
            let finished = expectation(description: "Cancelled fetch returned")
            StalledArtworkProtocol.sendHeaders = sendHeaders
            StalledArtworkProtocol.onStart = { started.fulfill() }
            StalledArtworkProtocol.onStop = { stopped.fulfill() }
            let artwork = NativeDeckArtwork(cache: URLCache(memoryCapacity: 1024, diskCapacity: 0, diskPath: nil),
                                            protocolClasses: [StalledArtworkProtocol.self])
            let task = Task {
                defer { finished.fulfill() }
                do {
                    _ = try await artwork.imageData(name: "Serra Angel", variant: .inspection, allowNetwork: true)
                    XCTFail("Cancelled artwork request must not succeed")
                } catch {
                    XCTAssertTrue(Task.isCancelled, "Fetch must not fail before cancellation")
                }
            }
            await fulfillment(of: [started], timeout: 3)
            task.cancel() // Same cancellation delivered by the consent-keyed SwiftUI task.
            await fulfillment(of: [stopped, finished], timeout: 3)
            let cached = try await artwork.imageData(name: "Serra Angel", variant: .inspection, allowNetwork: false)
            XCTAssertNil(cached)
        }
        StalledArtworkProtocol.onStart = nil
        StalledArtworkProtocol.onStop = nil
    }

    private func response(status: Int, headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://api.scryfall.com/cards/named")!, statusCode: status,
                        httpVersion: nil, headerFields: headers)!
    }
}

private final class StalledArtworkProtocol: URLProtocol {
    static var sendHeaders = false
    static var onStart: (() -> Void)?
    static var onStop: (() -> Void)?
    private var stopped: (() -> Void)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        stopped = Self.onStop
        if Self.sendHeaders {
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Type": "image/png"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data([0x89, 0x50]))
        }
        Self.onStart?()
        // Deliberately never finishes: cancellation must interrupt the suspended read.
    }
    override func stopLoading() {
        stopped?()
        stopped = nil
    }
}
