import XCTest
import CoreGraphics
import ImageIO
@testable import MagicMobile

final class NativeArtworkBackgroundQueueTests: XCTestCase {
    @MainActor func testStagingFailurePausesInsteadOfContinuingTransfers() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory); ArtworkImageTransferProtocol.configureBeforeResponse(nil) }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ArtworkImageTransferProtocol.self]
        let queue = NativeArtworkBackgroundQueue(directory: directory, configuration: config, allowNetwork: { true })
        // Simulate the staging destination becoming unavailable after a transfer starts.
        ArtworkImageTransferProtocol.configureBeforeResponse { try? FileManager.default.removeItem(at: directory) }
        try queue.start(entries: [entry()])
        for _ in 0..<200 where queue.isRunning { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(queue.isRunning); XCTAssertEqual(queue.completed, 0); XCTAssertEqual(queue.failures, 0)
        XCTAssertTrue(queue.status.contains("file could not be saved"))
    }
    @MainActor func testRateLimitPausesAndHonorsRetryAfterAcrossRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ArtworkImageTransferProtocol.self]
        let queue = NativeArtworkBackgroundQueue(directory: directory, configuration: config, allowNetwork: { true })
        let item = NativeArtworkBackgroundQueue.Entry(key: "throttled", name: "Throttled", url: URL(string: "https://cards.scryfall.io/throttled.jpg")!, quality: .compact)
        try queue.start(entries: [item])
        for _ in 0..<200 where queue.isRunning { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(queue.isRunning); XCTAssertEqual(queue.failures, 0); XCTAssertEqual(queue.completed, 0)
        XCTAssertTrue(queue.status.contains("paused"))
        let restored = NativeArtworkBackgroundQueue(directory: directory, configuration: config, allowNetwork: { true })
        XCTAssertFalse(restored.isRunning)
        XCTAssertThrowsError(try restored.start(entries: [item]))
    }

    @MainActor func testStorageFullPausesWithoutDiscardingPendingManifest() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NativeAssetStore(directory: directory.appendingPathComponent("images"), capacity: 0, availableBytes: { _ in Int64.max })
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ArtworkImageTransferProtocol.self]
        let queue = NativeArtworkBackgroundQueue(directory: directory.appendingPathComponent("queue"), store: store, configuration: config, allowNetwork: { true })
        try queue.start(entries: [entry()])
        for _ in 0..<200 where queue.isRunning { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(queue.isRunning); XCTAssertEqual(queue.completed, 0); XCTAssertEqual(queue.failures, 0)
        XCTAssertTrue(queue.status.contains("storage"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("queue/job.json").path))
    }
    @MainActor func testLargeManifestSchedulesBoundedSystemTasks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        HeldArtworkTransferProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HeldArtworkTransferProtocol.self]
        let queue = NativeArtworkBackgroundQueue(directory: directory, configuration: config, allowNetwork: { true })
        try queue.start(entries: (0..<100).map { entry(key: "card:\($0)") })
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertGreaterThan(HeldArtworkTransferProtocol.started, 0)
        XCTAssertLessThanOrEqual(HeldArtworkTransferProtocol.started, 64)
        XCTAssertEqual(queue.total, 100)
        queue.cancel()
    }
    @MainActor func testDownloadedImagesAreValidatedStoredAndJournaled() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NativeAssetStore(directory: directory.appendingPathComponent("images"), availableBytes: { _ in Int64.max })
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ArtworkImageTransferProtocol.self]
        let queue = NativeArtworkBackgroundQueue(directory: directory.appendingPathComponent("queue"), store: store, configuration: config, allowNetwork: { true })
        try queue.start(entries: [entry()])
        for _ in 0..<200 where queue.isRunning { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(queue.isRunning)
        XCTAssertEqual(queue.completed, 1); XCTAssertEqual(queue.failures, 0)
        let saved = await store.image(key: "card:one", quality: .compact)
        XCTAssertNotNil(saved)
        let restored = NativeArtworkBackgroundQueue(directory: directory.appendingPathComponent("queue"), store: store, configuration: config, allowNetwork: { true })
        XCTAssertEqual(restored.completed, 1); XCTAssertFalse(restored.isRunning)
    }
    @MainActor func testOnlyDirectHTTPSCDNImagesAreAccepted() {
        XCTAssertTrue(NativeArtworkBackgroundQueue.allowed(URL(string: "https://cards.scryfall.io/normal/front/a.jpg")!))
        for value in ["http://cards.scryfall.io/a.jpg", "https://cards.scryfall.io.evil.test/a.jpg", "https://user@cards.scryfall.io/a.jpg", "https://cards.scryfall.io:444/a.jpg", "https://api.scryfall.com/cards/named?exact=test"] {
            XCTAssertFalse(NativeArtworkBackgroundQueue.allowed(URL(string: value)!))
        }
    }

    @MainActor func testConsentOffRejectsNewWork() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = NativeArtworkBackgroundQueue(directory: directory, configuration: .ephemeral, allowNetwork: { false })
        XCTAssertThrowsError(try queue.start(entries: [entry()]))
        XCTAssertFalse(queue.isRunning)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("job.json").path))
    }

    @MainActor func testRestorationIgnoresOtherJobsAndDuplicateJournalRecords() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID()
        try writeManifest(id: id, entries: [entry(), entry(key: "card:two")], directory: directory)
        let log = "\(UUID()):1:ok\n\(id):0:ok\n\(id):0:ok\n\(id):1:failed\n"
        try Data(log.utf8).write(to: directory.appendingPathComponent("results.log"))
        let queue = NativeArtworkBackgroundQueue(directory: directory, configuration: .ephemeral, allowNetwork: { true })
        XCTAssertEqual(queue.total, 2); XCTAssertEqual(queue.completed, 1); XCTAssertEqual(queue.failures, 1)
        XCTAssertEqual(queue.failureMessages, ["Fixture"])
        XCTAssertFalse(queue.isRunning)
    }

    @MainActor func testCancellationSurvivesRelaunchAndKeepsManifestForMissingScan() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HeldArtworkTransferProtocol.self]
        let queue = NativeArtworkBackgroundQueue(directory: directory, configuration: config, allowNetwork: { true })
        try queue.start(entries: [entry()])
        XCTAssertTrue(queue.isRunning)
        queue.cancel()
        let restored = NativeArtworkBackgroundQueue(directory: directory, configuration: config, allowNetwork: { true })
        XCTAssertFalse(restored.isRunning); XCTAssertEqual(restored.total, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("cancelled").path))
    }

    @MainActor func testInvalidOrDuplicateEntriesNeverCreateManifest() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = NativeArtworkBackgroundQueue(directory: directory, configuration: .ephemeral, allowNetwork: { true })
        XCTAssertThrowsError(try queue.start(entries: [entry(), entry()]))
        XCTAssertThrowsError(try queue.start(entries: [.init(key: "bad", name: "Bad", url: URL(string: "https://example.com/image.jpg")!, quality: .compact)]))
        XCTAssertFalse(queue.isRunning)
    }

    @MainActor private func entry(key: String = "card:one") -> NativeArtworkBackgroundQueue.Entry {
        .init(key: key, name: "Fixture", url: URL(string: "https://cards.scryfall.io/small/front/fixture.jpg")!, quality: .compact)
    }
    @MainActor private func writeManifest(id: UUID, entries: [NativeArtworkBackgroundQueue.Entry], directory: URL) throws {
        struct Manifest: Encodable { let id: UUID; let entries: [NativeArtworkBackgroundQueue.Entry] }
        try JSONEncoder().encode(Manifest(id: id, entries: entries)).write(to: directory.appendingPathComponent("job.json"))
    }
}

private final class HeldArtworkTransferProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var count = 0
    static var started: Int { lock.lock(); defer { lock.unlock() }; return count }
    static func reset() { lock.lock(); defer { lock.unlock() }; count = 0 }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.lock.lock(); Self.count += 1; Self.lock.unlock() }
    override func stopLoading() {}
}

private final class ArtworkImageTransferProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var beforeResponse: (() -> Void)?
    static func configureBeforeResponse(_ action: (() -> Void)?) { lock.lock(); defer { lock.unlock() }; beforeResponse = action }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let action = Self.beforeResponse; Self.beforeResponse = nil; Self.lock.unlock()
        action?()
        let context = CGContext(data: nil, width: 146, height: 204, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 146, height: 204))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        let status = request.url!.path.contains("throttled") ? 429 : 200
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg", "Content-Length": "\(data.length)", "Retry-After": "300"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data as Data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
