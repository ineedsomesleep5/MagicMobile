import XCTest
@testable import MagicMobile

/// Mirrors apps/android/core/src/test/kotlin/io/magicmobile/android/game/BadgeArtTest.kt.
final class BadgeArtStoreTests: XCTestCase {
    private let big = URL(string: "https://raw.githubusercontent.com/o/r/main/design/awards/lifer.png")!
    private let small = URL(string: "https://raw.githubusercontent.com/o/r/main/design/awards/small/lifer.png")!

    private final class Server: @unchecked Sendable {
        var answer: (URL) -> BadgeFetch
        var asked: [(URL, String?)] = []
        init(_ answer: @escaping (URL) -> BadgeFetch) { self.answer = answer }
    }

    private func store(_ server: Server) -> BadgeArtStore {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("badges-\(UUID().uuidString)", isDirectory: true)
        return BadgeArtStore(folder: folder) { url, etag in
            server.asked.append((url, etag))
            return server.answer(url)
        }
    }

    func testOurArtHasASmallCopyAndOtherArtDoesnt() {
        XCTAssertEqual(BadgeArtStore.smallURL(big), small)
        XCTAssertEqual(BadgeArtStore.smallURL(small), small)
        let other = URL(string: "https://example.com/a.png")!
        XCTAssertEqual(BadgeArtStore.smallURL(other), other)
    }

    func testABadgeDownloadsOnceAndWaitsOnThePhone() async {
        let server = Server { _ in .new(Data([1, 2]), etag: "tag") }
        let store = store(server)
        XCTAssertNil(store.stored(big))
        let changed = await store.refresh(big, now: Date(timeIntervalSince1970: 1_000))
        XCTAssertTrue(changed)
        XCTAssertEqual(store.stored(big), Data([1, 2]))
        let again = await store.refresh(big, now: Date(timeIntervalSince1970: 2_000))
        XCTAssertFalse(again, "checked lately")
        XCTAssertEqual(server.asked.map(\.0), [small])
        XCTAssertNil(server.asked[0].1)
    }

    /// A replaced file comes down again, and an unchanged one costs a single short answer.
    func testAfterSixHoursOnlyAChangedFileComesDown() async {
        let server = Server { _ in .new(Data([1]), etag: "one") }
        let store = store(server)
        let start = Date(timeIntervalSince1970: 1_000)
        await store.refresh(big, now: start)
        server.answer = { _ in .unchanged }
        let same = await store.refresh(big, now: start + BadgeArtStore.recheck)
        XCTAssertFalse(same)
        await store.refresh(big, now: start + BadgeArtStore.recheck + 1)
        XCTAssertEqual(server.asked.count, 2, "the check counts")
        server.answer = { _ in .new(Data([2]), etag: "two") }
        let changed = await store.refresh(big, now: start + BadgeArtStore.recheck * 2)
        XCTAssertTrue(changed)
        XCTAssertEqual(store.stored(big), Data([2]))
        XCTAssertEqual(server.asked.map(\.1), [nil, "one", "one"])
    }

    func testAMissingSmallCopyFallsBackToTheBigFile() async {
        let server = Server { [small] url in url == small ? .missing : .new(Data([9]), etag: nil) }
        let store = store(server)
        await store.refresh(big)
        XCTAssertEqual(store.stored(big), Data([9]))
        XCTAssertEqual(server.asked.map(\.0), [small, big])
    }

    func testBeingOfflineKeepsTheCoinAndTriesAgain() async {
        let server = Server { _ in .new(Data([5]), etag: "t") }
        let store = store(server)
        let start = Date(timeIntervalSince1970: 1_000)
        await store.refresh(big, now: start)
        server.answer = { _ in .failed }
        await store.refresh(big, now: start + BadgeArtStore.recheck)
        await store.refresh(big, now: start + BadgeArtStore.recheck + 1)
        XCTAssertEqual(server.asked.count, 3, "a failure doesn't count as a check")
        XCTAssertEqual(store.stored(big), Data([5]))
    }

    func testTheBigAndSmallCopiesAreKeptApart() async {
        let server = Server { [small] url in .new(url == small ? Data([1]) : Data([2]), etag: nil) }
        let store = store(server)
        await store.refresh(big)
        await store.refresh(big, small: false)
        XCTAssertEqual(store.stored(big), Data([1]))
        XCTAssertEqual(store.stored(big, small: false), Data([2]))
    }

    func testPrefetchReturnsWhatChanged() async {
        let server = Server { _ in .new(Data([1]), etag: nil) }
        let store = store(server)
        let urls = (0..<9).map { URL(string: "https://example.com/\($0).png")! }
        let first = await store.prefetch(urls)
        XCTAssertEqual(Set(first), Set(urls))
        let second = await store.prefetch(urls)
        XCTAssertEqual(second, [])
    }

    func testEveryCoinHasASmallCopy() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appendingPathComponent("design/awards")
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".png") }
        XCTAssertGreaterThan(names.count, 25)
        for name in names {
            let copy = folder.appendingPathComponent("small/\(name)")
            let size = (try? FileManager.default.attributesOfItem(atPath: copy.path)[.size] as? Int) ?? nil
            XCTAssertNotNil(size, "run scripts/brand/award_small.sh: \(name)")
            XCTAssertLessThan(size ?? 0, 60_000, name)
        }
    }
}
