import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import MagicMobile

/// The art a card shows follows the player's choice: found by name, requested from Scryfall by exact
/// printing, saved and served offline by printing. Android's CardArtChoicesTest follows the same cases.
final class CardArtChoicesTests: XCTestCase {
    private let cmm = CardPrinting(set: "cmm", number: "400")!
    private let c21 = CardPrinting(set: "c21", number: "263")!
    private let isd = CardPrinting(set: "isd", number: "51")!

    // MARK: Which printing a name shows

    private func deck(_ rows: [(String, CardPrinting?)], commander: (String, CardPrinting?)? = nil) -> DeckList {
        DeckList(name: "Test", commander: commander.map { DeckEntry(cardName: $0.0, quantity: 1, section: "commanders", printing: $0.1) },
                 entries: rows.map { DeckEntry(cardName: $0.0, quantity: 1, section: "deck", printing: $0.1) })
    }

    func testAPlayingDecksChoiceWinsAndItsDefaultArtIsNeverReplacedByAnotherDecks() {
        let choices = CardArtChoices()
        let older = Date(timeIntervalSince1970: 100), newer = Date(timeIntervalSince1970: 200)
        choices.update(library: [
            .init(id: "a", deck: deck([("Sol Ring", c21), ("Arcane Signet", c21)]), updated: newer),
            .init(id: "b", deck: deck([("Sol Ring", cmm), ("Forest", nil)]), updated: older)], selectedDeckID: "b")
        XCTAssertEqual(choices.printing(forName: "Sol Ring"), cmm, "the playing deck's choice")
        XCTAssertEqual(choices.printing(forName: "Arcane Signet"), c21, "a card the playing deck lacks follows the saved decks")
        choices.update(library: [
            .init(id: "a", deck: deck([("Sol Ring", c21)]), updated: newer),
            .init(id: "b", deck: deck([("Sol Ring", nil)]), updated: older)], selectedDeckID: "b")
        XCTAssertNil(choices.printing(forName: "Sol Ring"), "the playing deck holds Sol Ring with default art")
    }

    func testWithoutAPlayingSavedDeckTheMostRecentlySavedDeckWinsAndNamesIgnoreCase() {
        let choices = CardArtChoices()
        choices.update(library: [
            .init(id: "old", deck: deck([("Sol Ring", c21)]), updated: Date(timeIntervalSince1970: 1)),
            .init(id: "new", deck: deck([], commander: ("Sol Ring", cmm)), updated: Date(timeIntervalSince1970: 2))], selectedDeckID: "precon:x")
        XCTAssertEqual(choices.printing(forName: "sol ring "), cmm)
        XCTAssertNil(choices.printing(forName: "Forest"))
        XCTAssertFalse(choices.isEmpty)
        choices.update(library: [], selectedDeckID: nil)
        XCTAssertTrue(choices.isEmpty)
    }

    func testAReverseFaceShowsTheBackOfItsFrontsChosenPrinting() {
        let choices = CardArtChoices()
        choices.update(library: [.init(id: "a", deck: deck([("Delver of Secrets", isd)]), updated: .now)], selectedDeckID: "a")
        XCTAssertNil(choices.selection(forName: "Insectile Aberration"), "reverse faces are unknown until the catalogue names them")
        XCTAssertTrue(choices.needsReverseFaces)
        choices.setReverseFaces(["Insectile Aberration": "Delver of Secrets"])
        XCTAssertEqual(choices.selection(forName: "Delver of Secrets"), .init(printing: isd, back: false))
        XCTAssertEqual(choices.selection(forName: "Insectile Aberration"), .init(printing: isd, back: true))
        XCTAssertFalse(choices.needsReverseFaces)
    }

    func testAChangeIsAnnouncedOnlyWhenWhatANameShowsChanges() {
        let choices = CardArtChoices()
        var posted = 0
        let observer = NotificationCenter.default.addObserver(forName: CardArtChoices.didChange, object: nil, queue: .main) { _ in posted += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        let saved = CardArtChoices.SavedDeck(id: "a", deck: deck([("Sol Ring", cmm)]), updated: .now)
        choices.update(library: [saved], selectedDeckID: "a")
        choices.update(library: [saved], selectedDeckID: "a")
        XCTAssertEqual(posted, 1)
        choices.update(library: [.init(id: "a", deck: deck([("Sol Ring", c21)]), updated: .now)], selectedDeckID: "a")
        XCTAssertEqual(posted, 2)
    }

    // MARK: What is requested and stored

    private func store() -> (NativeAssetStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (NativeAssetStore(directory: directory, availableBytes: { _ in Int64.max }), directory)
    }

    func testOnlineArtIsRequestedByExactPrintingNeverByName() async throws {
        let (assets, directory) = store(); defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = try png(width: 488, height: 680)
        PrintingFixtureProtocol.configure(["/cards/cmm/400": .image(bytes)])
        let artwork = NativeDeckArtwork(cache: URLCache(memoryCapacity: 4_000_000, diskCapacity: 0, diskPath: nil),
                                        protocolClasses: [PrintingFixtureProtocol.self], assetStore: assets, frontFaceOfReverse: { _ in nil })
        let data = try await artwork.imageData(name: "Sol Ring", variant: .board, allowNetwork: true, art: .init(printing: cmm, back: false))
        XCTAssertEqual(data, bytes)
        XCTAssertEqual(PrintingFixtureProtocol.requested, ["https://api.scryfall.com/cards/cmm/400?format=image&version=normal"])
        // Without a choice the same card is still looked up by name, as before.
        PrintingFixtureProtocol.configure(["/cards/named": .image(bytes)])
        _ = try await artwork.imageData(name: "Sol Ring", variant: .board, allowNetwork: true)
        XCTAssertEqual(PrintingFixtureProtocol.requested.map { URLComponents(string: $0)?.path }, ["/cards/named"])
    }

    func testInspectionAndBoardRequestTheirOwnSizeOfTheChosenPrinting() async throws {
        let (assets, directory) = store(); defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = try png(width: 672, height: 936)
        PrintingFixtureProtocol.configure(["/cards/c21/263": .image(bytes)])
        let artwork = NativeDeckArtwork(cache: URLCache(memoryCapacity: 4_000_000, diskCapacity: 0, diskPath: nil),
                                        protocolClasses: [PrintingFixtureProtocol.self], assetStore: assets, frontFaceOfReverse: { _ in nil })
        _ = try await artwork.imageData(name: "Sol Ring", variant: .inspection, allowNetwork: true, art: .init(printing: c21, back: false))
        XCTAssertEqual(PrintingFixtureProtocol.requested, ["https://api.scryfall.com/cards/c21/263?format=image&version=large"])
    }

    func testOfflineServesTheSavedPrintingNotTheDefaultImageAndFallsBackToTheDefaultWhenNoneIsSaved() async throws {
        let (assets, directory) = store(); defer { try? FileManager.default.removeItem(at: directory) }
        let chosen = try png(width: 488, height: 680), standard = try png(width: 600, height: 840)
        try await assets.save(standard, key: NativeAssetStore.cardKey("Sol Ring"), quality: .standard)
        PrintingFixtureProtocol.configure([:])
        let artwork = NativeDeckArtwork(cache: URLCache(memoryCapacity: 4_000_000, diskCapacity: 0, diskPath: nil),
                                        protocolClasses: [PrintingFixtureProtocol.self], assetStore: assets, frontFaceOfReverse: { _ in nil })
        let art = CardArtChoices.Selection(printing: cmm, back: false)
        let fallback = try await artwork.imageData(name: "Sol Ring", variant: .board, allowNetwork: false, art: art)
        XCTAssertEqual(fallback, standard, "nothing saved for the printing: the default art is better than a blank")
        try await assets.save(chosen, key: NativeAssetStore.printingKey(cmm), quality: .standard)
        let offline = try await artwork.imageData(name: "Sol Ring", variant: .board, allowNetwork: false, art: art)
        XCTAssertEqual(offline, chosen)
        let plain = try await artwork.imageData(name: "Sol Ring", variant: .board, allowNetwork: false)
        XCTAssertEqual(plain, standard, "a card with no choice still shows its default art")
        // Online, a saved image that already meets the quality is kept without a request.
        let online = try await artwork.imageData(name: "Sol Ring", variant: .board, allowNetwork: true, art: art)
        XCTAssertEqual(online, chosen)
        XCTAssertEqual(PrintingFixtureProtocol.requested, [])
        XCTAssertNotEqual(NativeAssetStore.printingKey(cmm), NativeAssetStore.cardKey("Sol Ring"))
    }

    func testAPrintingScryfallDoesNotHaveShowsTheDefaultArtInstead() async throws {
        let (assets, directory) = store(); defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = try png(width: 488, height: 680)
        PrintingFixtureProtocol.configure(["/cards/cmm/400": .status(404), "/cards/named": .image(bytes)])
        let artwork = NativeDeckArtwork(cache: URLCache(memoryCapacity: 4_000_000, diskCapacity: 0, diskPath: nil),
                                        protocolClasses: [PrintingFixtureProtocol.self], assetStore: assets, frontFaceOfReverse: { _ in nil })
        let data = try await artwork.imageData(name: "Sol Ring", variant: .board, allowNetwork: true, art: .init(printing: cmm, back: false))
        XCTAssertEqual(data, bytes)
        XCTAssertEqual(PrintingFixtureProtocol.requested.map { URLComponents(string: $0)?.path }, ["/cards/cmm/400", "/cards/named"])
    }

    func testAReverseFaceNameAsksForTheBackOfItsFrontNotTheFrontImage() async throws {
        let (assets, directory) = store(); defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = try png(width: 488, height: 680)
        PrintingFixtureProtocol.configure(["/cards/named": .image(bytes), "/cards/isd/51": .image(bytes)])
        let artwork = NativeDeckArtwork(cache: URLCache(memoryCapacity: 4_000_000, diskCapacity: 0, diskPath: nil),
                                        protocolClasses: [PrintingFixtureProtocol.self], assetStore: assets,
                                        frontFaceOfReverse: { $0 == "Insectile Aberration" ? "Delver of Secrets" : nil })
        _ = try await artwork.imageData(name: "Insectile Aberration", variant: .board, allowNetwork: true)
        var query = try XCTUnwrap(URLComponents(string: try XCTUnwrap(PrintingFixtureProtocol.requested.last))).queryItems ?? []
        XCTAssertEqual(query.first { $0.name == "exact" }?.value, "Delver of Secrets")
        XCTAssertEqual(query.first { $0.name == "face" }?.value, "back")
        // The front face of the same card asks for no face.
        PrintingFixtureProtocol.configure(["/cards/named": .image(bytes)])
        _ = try await artwork.imageData(name: "Delver of Secrets", variant: .board, allowNetwork: true)
        query = try XCTUnwrap(URLComponents(string: try XCTUnwrap(PrintingFixtureProtocol.requested.last))).queryItems ?? []
        XCTAssertNil(query.first { $0.name == "face" })
        // And the chosen printing's reverse face is that printing's `face=back`.
        PrintingFixtureProtocol.configure(["/cards/isd/51": .image(bytes)])
        _ = try await artwork.imageData(name: "Insectile Aberration", variant: .board, allowNetwork: true, art: .init(printing: isd, back: true))
        XCTAssertEqual(PrintingFixtureProtocol.requested, ["https://api.scryfall.com/cards/isd/51?format=image&version=normal&face=back"])
    }

    func testSavedPrintingKeysAreSeparatePerFaceAndTargetTheRightViews() {
        XCTAssertEqual(NativeAssetStore.printingKey(isd), "print:isd/51")
        XCTAssertEqual(NativeAssetStore.printingKey(isd, back: true), "print:isd/51:back")
        XCTAssertTrue(NativeAssetStore.artworkChangeAffects(key: "print:isd/51", storedName: nil, name: "Delver of Secrets", isToken: false, printing: isd))
        XCTAssertFalse(NativeAssetStore.artworkChangeAffects(key: "print:isd/51", storedName: nil, name: "Delver of Secrets", isToken: false, printing: c21))
        XCTAssertFalse(NativeAssetStore.artworkChangeAffects(key: "print:isd/51:back", storedName: nil, name: "Delver of Secrets", isToken: false, printing: isd))
        XCTAssertTrue(NativeAssetStore.artworkChangeAffects(key: "card:delver of secrets", storedName: nil, name: "Delver of Secrets", isToken: false, printing: isd),
                      "default art stored later still matters: it is the fallback")
    }

    func testThumbnailsComeOnlyFromScryfallsImageHostAreCachedAndSpendNoApiRequest() async throws {
        let (assets, directory) = store(); defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = try png(width: 146, height: 204)
        PrintingFixtureProtocol.configure(["/small/front/a.jpg": .image(bytes)])
        let artwork = NativeDeckArtwork(cache: URLCache(memoryCapacity: 4_000_000, diskCapacity: 0, diskPath: nil),
                                        protocolClasses: [PrintingFixtureProtocol.self], assetStore: assets, frontFaceOfReverse: { _ in nil })
        let url = try XCTUnwrap(URL(string: "https://cards.scryfall.io/small/front/a.jpg"))
        let offlineMiss = try await artwork.thumbnailData(url: url, allowNetwork: false)
        XCTAssertNil(offlineMiss)
        let first = try await artwork.thumbnailData(url: url, allowNetwork: true)
        XCTAssertEqual(first, bytes)
        let cached = try await artwork.thumbnailData(url: url, allowNetwork: false)
        XCTAssertEqual(cached, bytes)
        XCTAssertEqual(PrintingFixtureProtocol.requested, [url.absoluteString], "One request, to the image host, then the cache")
        for text in ["https://api.scryfall.com/cards/cmm/400?format=image", "http://cards.scryfall.io/a.jpg", "https://evil.test/a.jpg",
                     "https://cards.scryfall.io.evil.test/a.jpg"] {
            do { _ = try await artwork.thumbnailData(url: try XCTUnwrap(URL(string: text)), allowNetwork: true); XCTFail(text) }
            catch NativeDeckArtwork.ArtworkError.unsafeURL { }
        }
    }

    // MARK: The printings Scryfall lists

    func testPrintingsRequestAndReadingAreExactAndBounded() async throws {
        let request = try DeckStudioScryfallClient.printingsRequest(name: "Sol Ring", page: 2)
        let parts = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.host, "api.scryfall.com"); XCTAssertEqual(parts.path, "/cards/search")
        XCTAssertEqual(parts.queryItems, [.init(name: "q", value: "!\"Sol Ring\""), .init(name: "unique", value: "prints"),
                                          .init(name: "order", value: "released"), .init(name: "dir", value: "desc"), .init(name: "page", value: "2")])
        XCTAssertThrowsError(try DeckStudioScryfallClient.printingsRequest(name: "Ach! \"Hans\"", page: 1))
        XCTAssertThrowsError(try DeckStudioScryfallClient.printingsRequest(name: "Sol Ring", page: 11))
        XCTAssertThrowsError(try DeckStudioScryfallClient.printingsRequest(name: "a\\b", page: 1))
        let ids = (1...3).map { _ in UUID().uuidString }
        let list: [String: Any] = ["object": "list", "has_more": true, "data": [
            ["id": ids[0], "name": "Sol Ring", "set": "cmm", "set_name": "Commander Masters", "collector_number": "400", "released_at": "2023-08-04",
             "image_uris": ["small": "https://cards.scryfall.io/small/front/a.jpg"]],
            ["id": ids[1], "name": "Delver", "set": "isd", "set_name": "Innistrad", "collector_number": "51", "released_at": "2011-09-30",
             "card_faces": [["name": "Delver of Secrets", "image_uris": ["small": "https://cards.scryfall.io/small/front/b.jpg"]],
                            ["name": "Insectile Aberration", "image_uris": ["small": "https://cards.scryfall.io/small/back/b.jpg"]]]],
            ["id": ids[2], "name": "Evil", "set": "zzz", "set_name": "Evil", "collector_number": "1/2", "image_uris": ["small": "https://evil.test/a.jpg"]]]]
        let client = DeckStudioScryfallClient(transport: PrintingListTransport(try JSONSerialization.data(withJSONObject: list)), directory: nil, pace: false)
        let fetched = try await client.printings(of: "Sol Ring", allowNetwork: true)
        let page = try XCTUnwrap(fetched)
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.printings.map { $0.printing?.key }, ["cmm/400", "isd/51", nil])
        XCTAssertEqual(page.printings[0].caption, "Commander Masters · 2023")
        XCTAssertEqual(page.printings[1].thumbnailURL?.absoluteString, "https://cards.scryfall.io/small/front/b.jpg")
        XCTAssertNil(page.printings[2].thumbnailURL, "only Scryfall's image host is trusted")
        let offline = try await client.printings(of: "Sol Ring", page: 3, allowNetwork: false)
        XCTAssertNil(offline, "no network and nothing cached: no request is made")
    }

    private func png(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: CGFloat(width % 7) / 7, green: 0.3, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

private struct PrintingListTransport: DeckStudioScryfallHTTP {
    let data: Data
    init(_ data: Data) { self.data = data }
    func send(_ request: URLRequest) async throws -> Data { data }
}

/// Answers by path and records every URL asked for.
private final class PrintingFixtureProtocol: URLProtocol {
    enum Answer { case image(Data), status(Int) }
    private static let lock = NSLock()
    private static var answers: [String: Answer] = [:]
    private static var urls: [String] = []
    static var requested: [String] { lock.lock(); defer { lock.unlock() }; return urls }
    static func configure(_ values: [String: Answer]) { lock.lock(); answers = values; urls = []; lock.unlock() }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        Self.lock.lock(); Self.urls.append(url.absoluteString); let answer = Self.answers[url.path]; Self.lock.unlock()
        var status = 503, bytes = Data()
        switch answer {
        case .image(let data)?: status = 200; bytes = data
        case .status(let code)?: status = code
        case nil: break
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "image/png", "Content-Length": String(bytes.count)])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: bytes)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
