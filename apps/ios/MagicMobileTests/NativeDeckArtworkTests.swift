import XCTest
import CoreGraphics
import ImageIO
@testable import MagicMobile

final class NativeDeckArtworkTests: XCTestCase {
    func testOptInLiveTokenArtworkAndVisibleCopySource() async throws {
        guard ProcessInfo.processInfo.environment["MM_LIVE_TOKEN_ARTWORK_TEST"] == "1" else {
            throw XCTSkip("Set MM_LIVE_TOKEN_ARTWORK_TEST=1 to verify two public Scryfall artwork identities.")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MagicMobile-LiveToken-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NativeAssetStore(directory: directory, availableBytes: { _ in Int64.max })
        let transport = LiveTokenSearchTransport()
        let artwork = NativeDeckArtwork(cache: URLCache(memoryCapacity: 4_000_000, diskCapacity: 0, diskPath: nil),
                                        assetStore: store, tokenLookup: { name, type, rules, power, toughness, colors, quality in
            let match = try await NativeArtworkCatalogue.searchToken(name: name, typeLine: type, oracleText: rules,
                power: power, toughness: toughness, colors: colors, quality: quality,
                transport: transport, budget: .shared)
            if let match { await transport.recordMatch(match.0.id, imageURL: match.1) }
            return match
        })
        @Sendable func visibleZombie(online: Bool) async throws -> Data? {
            try await artwork.imageData(name: "Zombie Token", variant: .board, allowNetwork: online,
                                        tokenTypeLine: "Creature — Zombie", tokenOracleText: "",
                                        tokenPower: "2", tokenToughness: "2", tokenColors: ["B"])
        }
        let tokenImage = try await liveArtworkTimeout { try await visibleZombie(online: true) }
        XCTAssertNotNil(NativeDeckArtwork.decodedImage(try XCTUnwrap(tokenImage), variant: .board))
        let matchedID = await transport.matchedTokenID
        let tokenID = try XCTUnwrap(matchedID)
        let persisted = await store.image(key: NativeAssetStore.tokenKey(tokenID), quality: .standard)
        XCTAssertEqual(persisted, tokenImage)
        let requestsBeforeOffline = await transport.requests
        let offline = try await visibleZombie(online: false)
        XCTAssertEqual(offline, tokenImage)
        let requestsAfterOffline = await transport.requests
        XCTAssertEqual(requestsAfterOffline, requestsBeforeOffline)

        let sourceImage = try await liveArtworkTimeout {
            try await artwork.imageData(name: "Loyal Guardian", variant: .board, allowNetwork: true,
                                        tokenTypeLine: "Creature — Zombie", tokenOracleText: "",
                                        tokenPower: "4", tokenToughness: "4", tokenColors: ["B"],
                                        tokenSourceName: "Loyal Guardian")
        }
        XCTAssertNotNil(NativeDeckArtwork.decodedImage(try XCTUnwrap(sourceImage), variant: .board))
        XCTAssertNotEqual(sourceImage, tokenImage)
        let searchPaths = await transport.requestPaths
        let tokenImagePath = await transport.matchedImagePath
        XCTAssertTrue(searchPaths.allSatisfy { $0 == "/cards/search" })
        XCTAssertNotNil(tokenImagePath)
        print("LIVE_TOKEN_ARTWORK search=\(searchPaths) tokenImage=\(tokenImagePath ?? "missing") source=api.scryfall.com/cards/named tokenID=\(tokenID)")
    }
    func testTokenInspectionUpgradesWithConsentAndKeepsStandardArtOfflineOrOnFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NativeAssetStore(directory: directory, availableBytes: { _ in Int64.max })
        let token = NativeTokenArtwork(id: UUID(), name: "Zombie", typeLine: "Token Creature — Zombie",
                                       oracleText: "", power: "2", toughness: "2", colors: ["B"])
        let standard = try png(width: 488, height: 680)
        let high = try png(width: 672, height: 936)
        try await store.saveToken(token)
        try await store.save(standard, key: NativeAssetStore.tokenKey(token.id), quality: .standard)
        let counter = TokenLookupCounter()
        let artwork = NativeDeckArtwork(cache: URLCache(memoryCapacity: 4_000_000, diskCapacity: 0, diskPath: nil),
                                        protocolClasses: [LiveArtworkFixtureProtocol.self], assetStore: store,
                                        tokenLookup: { _, _, _, _, _, _, quality in
                                            XCTAssertEqual(quality, .high)
                                            await counter.record()
                                            return (token, URL(string: "https://cards.scryfall.io/large/zombie.jpg")!)
                                        })
        @Sendable func inspect(_ online: Bool) async throws -> Data? {
            try await artwork.imageData(name: "Zombie Token", variant: .inspection, allowNetwork: online,
                                        tokenTypeLine: "Creature — Zombie", tokenOracleText: "",
                                        tokenPower: "2", tokenToughness: "2", tokenColors: ["B"])
        }
        LiveArtworkFixtureProtocol.bytes = high
        LiveArtworkFixtureProtocol.requests = 0
        defer { LiveArtworkFixtureProtocol.bytes = Data() }
        let offline = try await inspect(false)
        XCTAssertEqual(offline, standard)
        let before = await counter.count
        XCTAssertEqual(before, 0)
        let upgraded = try await inspect(true)
        XCTAssertEqual(upgraded, high)
        XCTAssertEqual(LiveArtworkFixtureProtocol.requests, 1)
        let cached = try await inspect(true)
        XCTAssertEqual(cached, high)
        let after = await counter.count
        XCTAssertEqual(after, 1)
        let offlineHigh = try await inspect(false)
        XCTAssertEqual(offlineHigh, high)

        let failureStore = NativeAssetStore(directory: directory.appendingPathComponent("failure"), availableBytes: { _ in Int64.max })
        try await failureStore.saveToken(token)
        try await failureStore.save(standard, key: NativeAssetStore.tokenKey(token.id), quality: .standard)
        let failing = NativeDeckArtwork(cache: URLCache(memoryCapacity: 4_000_000, diskCapacity: 0, diskPath: nil),
                                        assetStore: failureStore, tokenLookup: { _, _, _, _, _, _, _ in
            throw NativeArtworkCatalogue.CatalogueError.invalidResponse
        })
        let fallback = try await failing.imageData(name: "Zombie Token", variant: .inspection, allowNetwork: true,
                                                    tokenTypeLine: "Creature — Zombie", tokenOracleText: "",
                                                    tokenPower: "2", tokenToughness: "2", tokenColors: ["B"])
        XCTAssertEqual(fallback, standard)
    }
    func testOnDemandTokenLookupNeedsConsentCoalescesAndPersistsByExactID() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NativeAssetStore(directory: directory, availableBytes: { _ in Int64.max })
        let id = UUID()
        let token = NativeTokenArtwork(id: id, name: "Zombie", typeLine: "Token Creature — Zombie",
                                       oracleText: "", power: "2", toughness: "2", colors: ["B"])
        let counter = TokenLookupCounter()
        let bytes = try png(width: 488, height: 680)
        LiveArtworkFixtureProtocol.bytes = bytes
        LiveArtworkFixtureProtocol.requests = 0
        defer { LiveArtworkFixtureProtocol.bytes = Data() }
        let artwork = NativeDeckArtwork(cache: URLCache(memoryCapacity: 4_000_000, diskCapacity: 0, diskPath: nil),
                                        protocolClasses: [LiveArtworkFixtureProtocol.self], assetStore: store,
                                        tokenLookup: { _, _, _, _, _, _, _ in
                                            await counter.record()
                                            return (token, URL(string: "https://cards.scryfall.io/normal/zombie.jpg")!)
                                        })
        @Sendable func fetch(_ online: Bool) async throws -> Data? {
            try await artwork.imageData(name: "Zombie Token", allowNetwork: online, tokenTypeLine: "Creature — Zombie",
                                        tokenOracleText: "", tokenPower: "4", tokenToughness: "4", tokenColors: ["B"])
        }
        let offline = try await fetch(false)
        XCTAssertNil(offline)
        let before = await counter.count
        XCTAssertEqual(before, 0)
        async let first = fetch(true), second = fetch(true)
        let results = try await (first, second)
        XCTAssertEqual(results.0, bytes); XCTAssertEqual(results.1, bytes)
        let calls = await counter.count
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(LiveArtworkFixtureProtocol.requests, 1)
        let reopened = NativeAssetStore(directory: directory)
        let saved = await reopened.tokenImage(name: "Zombie Token", typeLine: "Creature — Zombie", oracleText: "",
                                               power: "4", toughness: "4", colors: ["B"])
        XCTAssertEqual(saved, bytes)
        let offlineAgain = try await fetch(false)
        XCTAssertEqual(offlineAgain, bytes)
    }
    func testExplicitVisibleCopySourceUsesSavedCardArtWithoutTokenNameLookup() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NativeAssetStore(directory: directory, availableBytes: { _ in Int64.max })
        let bytes = try png(width: 488, height: 680)
        try await store.save(bytes, key: NativeAssetStore.cardKey("Loyal Guardian"), quality: .standard)
        let artwork = NativeDeckArtwork(cache: URLCache(memoryCapacity: 4_000_000, diskCapacity: 0, diskPath: nil),
                                        assetStore: store)
        let copied = try await artwork.imageData(name: "Loyal Guardian", allowNetwork: false,
                                                 tokenTypeLine: "Creature — Zombie", tokenOracleText: "",
                                                 tokenPower: "4", tokenToughness: "4", tokenColors: ["B"],
                                                 tokenSourceName: "Loyal Guardian")
        XCTAssertEqual(copied, bytes)
        let unknown = try await artwork.imageData(name: "Custom token", allowNetwork: false,
                                                  tokenTypeLine: "Creature — Zombie", tokenOracleText: "",
                                                  tokenPower: "4", tokenToughness: "4", tokenColors: ["B"])
        XCTAssertNil(unknown)
        let hidden = try await artwork.imageData(name: "Custom token", allowNetwork: false,
                                                 tokenTypeLine: "Creature — Zombie", tokenOracleText: "",
                                                 tokenSourceName: "Face-down card")
        XCTAssertNil(hidden)
    }
    func testLiveUpgradeKeepsCompactDownloadAndOfflineConsentBoundary() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NativeAssetStore(directory: directory, availableBytes: { _ in Int64.max })
        let compact = try png(width: 146, height: 204)
        let sharper = try png(width: 488, height: 680)
        let name = "Local upgrade fixture"
        try await store.save(compact, key: NativeAssetStore.cardKey(name), quality: .compact)
        let cache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 0, diskPath: nil)
        LiveArtworkFixtureProtocol.bytes = sharper
        LiveArtworkFixtureProtocol.requests = 0
        defer { LiveArtworkFixtureProtocol.bytes = Data() }
        let artwork = NativeDeckArtwork(cache: cache, protocolClasses: [LiveArtworkFixtureProtocol.self], assetStore: store)
        let offline = try await artwork.imageData(name: name, allowNetwork: false)
        XCTAssertEqual(offline, compact)
        XCTAssertEqual(LiveArtworkFixtureProtocol.requests, 0)
        let live = try await artwork.imageData(name: name, allowNetwork: true)
        XCTAssertEqual(live, sharper)
        XCTAssertEqual(LiveArtworkFixtureProtocol.requests, 1)
        let downloaded = await store.image(key: NativeAssetStore.cardKey(name))
        XCTAssertEqual(downloaded, compact, "Live art must not replace the selected offline quality")
        let cached = try await artwork.imageData(name: name, allowNetwork: true)
        XCTAssertEqual(cached, sharper)
        XCTAssertEqual(LiveArtworkFixtureProtocol.requests, 1)
        let offAgain = try await artwork.imageData(name: name, allowNetwork: false)
        XCTAssertEqual(offAgain, compact)
        XCTAssertEqual(LiveArtworkFixtureProtocol.requests, 1)
        cache.removeAllCachedResponses()
        LiveArtworkFixtureProtocol.bytes = Data() // Offline/failure must keep usable saved art.
        let fallback = try await artwork.imageData(name: name, allowNetwork: true)
        XCTAssertEqual(fallback, compact)
    }
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

    func testDeckCoverCropPreservesTheOriginalCard() throws {
        let data = try png(width: 488, height: 680)
        let full = try XCTUnwrap(NativeDeckArtwork.decodedImage(data, variant: .board))
        let art = try XCTUnwrap(NativeDeckArtwork.illustrationImage(full))
        XCTAssertGreaterThan(art.width, art.height)
        XCTAssertLessThan(art.height, full.height / 2)
        XCTAssertEqual(full.width, 488)
        XCTAssertEqual(full.height, 680)
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

private enum LiveArtworkTestError: Error { case timeout, tooManySearchRequests }

private func liveArtworkTimeout<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(25))
            throw LiveArtworkTestError.timeout
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}

private actor LiveTokenSearchTransport: DeckStudioScryfallHTTP {
    private let production = DeckStudioScryfallHTTPTransport()
    private(set) var requestPaths: [String] = []
    private(set) var matchedTokenID: UUID?
    private(set) var matchedImagePath: String?
    var requests: Int { requestPaths.count }
    func recordMatch(_ id: UUID, imageURL: URL) {
        matchedTokenID = id
        matchedImagePath = "\(imageURL.host ?? "missing")\(imageURL.path)"
    }
    func send(_ request: URLRequest) async throws -> Data {
        guard requestPaths.count < 3, let url = request.url, url.host == "api.scryfall.com",
              url.path == "/cards/search" else { throw LiveArtworkTestError.tooManySearchRequests }
        requestPaths.append(url.path)
        return try await production.send(request)
    }
}

private actor TokenLookupCounter {
    private(set) var count = 0
    func record() { count += 1 }
}

private final class LiveArtworkFixtureProtocol: URLProtocol {
    static var bytes = Data()
    static var requests = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.bytes.isEmpty ? 503 : 200,
            httpVersion: nil, headerFields: ["Content-Type": "image/png"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.bytes)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
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
