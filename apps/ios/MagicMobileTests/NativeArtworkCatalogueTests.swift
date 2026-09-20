import XCTest
import zlib
@testable import MagicMobile

final class NativeArtworkCatalogueTests: XCTestCase {
    func testDeckCollectionsBatchNamesAndResolveExactTokenIDs() async throws {
        let transport = ArtworkCollectionFixture()
        let names = (0..<76).map { "Fixture \($0)" }
        let catalogue = try await NativeArtworkCatalogue.load(names: names, includeTokens: true, transport: transport, budget: DeckStudioScryfallBudget())
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 3, "76 names use two collection requests and one exact token batch")
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "POST" && $0.url?.path == "/cards/collection" })
        XCTAssertEqual(catalogue.imageURL(name: "Fixture 75", size: "normal")?.host, "cards.scryfall.io")
        XCTAssertEqual(catalogue.relatedTokens(name: "Fixture 0").map(\.id), [ArtworkCollectionFixture.tokenID])
        XCTAssertEqual(catalogue.token(id: ArtworkCollectionFixture.tokenID)?.power, "1")
        XCTAssertEqual(catalogue.imageURL(id: ArtworkCollectionFixture.tokenID, size: "small")?.host, "cards.scryfall.io")
        let tokenRequest = try XCTUnwrap(requests.last?.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: tokenRequest) as? [String: [[String: String]]])
        XCTAssertEqual(object["identifiers"], [["id": ArtworkCollectionFixture.tokenID.uuidString.lowercased()]])
    }

    func testDeckCollectionWithoutTokensDoesNotFetchRelatedCards() async throws {
        let transport = ArtworkCollectionFixture()
        let catalogue = try await NativeArtworkCatalogue.load(names: ["Fixture 0"], includeTokens: false, transport: transport, budget: DeckStudioScryfallBudget())
        let count = await transport.requests.count
        XCTAssertEqual(count, 1)
        XCTAssertNil(catalogue.token(id: ArtworkCollectionFixture.tokenID))
    }
    private let cardID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let tokenID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let missingID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    func testStreamingHandlesEscapedBracesAndSplitUnicodeInArrayAndJSONLines() throws {
        let objects = [["text": "brace } and quote \" and 🪷"], ["text": "next"]]
        for source in [try JSONSerialization.data(withJSONObject: objects),
                       try objects.map { try JSONSerialization.data(withJSONObject: $0) }.reduce(Data()) { $0 + $1 + Data([10]) }] {
            var parser = NativeArtworkCatalogue.ObjectStream()
            var decoded: [[String: String]] = []
            for byte in source {
                try parser.append([byte]) { decoded.append(try JSONDecoder().decode([String: String].self, from: $0)) }
            }
            try parser.finish()
            XCTAssertEqual(decoded, objects)
        }
    }

    func testRejectsTruncationTrailingCommaAndAdjacentJSONObjects() {
        for source in ["[{\"text\":\"unfinished", "[{},]", "{}{}", "[{}]x", "[{},", ""] {
            var parser = NativeArtworkCatalogue.ObjectStream()
            XCTAssertThrowsError(try {
                try parser.append(source.utf8) { _ in }
                try parser.finish()
            }())
        }
    }

    func testLimitsIndividualObjectBuffer() throws {
        var parser = NativeArtworkCatalogue.ObjectStream()
        try parser.append("{\"text\":\"".utf8) { _ in }
        XCTAssertThrowsError(try parser.append(repeatElement(UInt8(65), count: NativeArtworkCatalogue.maximumObjectBytes)) { _ in }) {
            XCTAssertEqual($0 as? NativeArtworkCatalogue.CatalogueError, .oversized)
        }
    }

    func testURLAllowlistAndBulkMetadataFormats() throws {
        for raw in ["http://data.scryfall.io/a", "https://user@data.scryfall.io/a", "https://data.scryfall.io.evil.test/a",
                    "https://data.scryfall.io:444/a", "https://data.scryfall.io/a#secret", "file:///a"] {
            XCTAssertFalse(NativeArtworkCatalogue.isAllowed(URL(string: raw)!, host: "data.scryfall.io"))
        }
        for key in ["download_uri", "jsonl_download_uri"] {
            let data = try JSONSerialization.data(withJSONObject: ["data": [["type": "oracle_cards", key: "https://data.scryfall.io/oracle/file.jsonl.gz"]]])
            XCTAssertEqual(try NativeArtworkCatalogue.bulkURL(data).host, "data.scryfall.io")
        }
        XCTAssertThrowsError(try NativeArtworkCatalogue.bulkURL(Data("{\"data\":[{\"type\":\"oracle_cards\",\"download_uri\":\"https://evil.test/x\"}]}".utf8)))
    }

    func testNamesFrontFaceTokenMetadataAndMissingPrintingStayExact() throws {
        let token: [String: Any] = ["id": tokenID.uuidString, "name": "Soldier", "type_line": "Token Creature — Soldier",
            "power": "1", "toughness": "1", "colors": ["W"], "oracle_text": "Vigilance", "image_uris": images("soldier")]
        let card: [String: Any] = ["id": cardID.uuidString, "name": "Front // Back", "type_line": "Creature",
            "card_faces": [["name": "Front", "image_uris": images("front")], ["name": "Back", "image_uris": images("back")]],
            "all_parts": [["id": tokenID.uuidString, "component": "token", "name": "Soldier"],
                          ["id": missingID.uuidString, "component": "token", "name": "Soldier"]]]
        let catalogue = try parse([card, token])
        XCTAssertEqual(catalogue.cardCount, 2)
        XCTAssertEqual(catalogue.tokenCount, 1)
        XCTAssertEqual(catalogue.allTokens.map(\.id), [tokenID])
        XCTAssertEqual(catalogue.imageURL(name: " front ", size: "normal"), catalogue.imageURL(name: "Front // Back", size: "normal"))
        XCTAssertEqual(catalogue.imageURL(name: "Front", size: "normal")?.lastPathComponent, "front.jpg")
        XCTAssertEqual(catalogue.imageURL(name: "Back", size: "normal")?.lastPathComponent, "back.jpg")
        XCTAssertEqual(catalogue.additionalFaceNames(for: ["Front"]), ["Back"])
        XCTAssertEqual(catalogue.additionalFaceNames(for: ["Front // Back"]), ["Back", "Front"])
        XCTAssertEqual(catalogue.additionalFaceNames(for: ["Front", "Back"]), [])
        XCTAssertNil(catalogue.imageURL(name: "Front", size: "arbitrary"))
        XCTAssertNil(catalogue.imageURL(id: tokenID, size: "arbitrary"))
        XCTAssertEqual(catalogue.relatedTokens(name: "Front").map(\.id), [tokenID, missingID])
        XCTAssertEqual(catalogue.token(id: tokenID)?.power, "1")
        XCTAssertNil(catalogue.token(id: missingID), "Absent printing must never select a same-name token")
        XCTAssertNil(catalogue.imageURL(id: missingID, size: "large"))
    }

    func testAmbiguousFrontAliasAndUntrustedImageAreNotReturned() throws {
        let first: [String: Any] = ["id": cardID.uuidString, "name": "Shared // One", "card_faces": [["name": "Shared", "image_uris": images("one")]]]
        let second: [String: Any] = ["id": tokenID.uuidString, "name": "Shared // Two", "card_faces": [["name": "Shared", "image_uris": images("two")]]]
        let unsafe: [String: Any] = ["id": missingID.uuidString, "name": "Unsafe", "image_uris": ["large": "https://evil.test/image.jpg"]]
        let catalogue = try parse([first, second, unsafe])
        XCTAssertNil(catalogue.imageURL(name: "Shared", size: "normal"))
        XCTAssertEqual(catalogue.additionalFaceNames(for: ["Shared // One", "Shared // Two"]), [])
        XCTAssertNotNil(catalogue.imageURL(name: "Shared // One", size: "normal"))
        XCTAssertNil(catalogue.imageURL(name: "Unsafe", size: "large"))
    }

    func testAllTokensSortByNameThenIDRegardlessOfInputOrder() throws {
        let objects: [[String: Any]] = [
            ["id": missingID.uuidString, "name": "Soldier", "type_line": "Token Creature — Soldier", "power": "1", "toughness": "1", "colors": ["W"]],
            ["id": tokenID.uuidString, "name": "Soldier", "type_line": "Token Creature — Soldier", "power": "1", "toughness": "1", "colors": ["W"]],
            ["id": cardID.uuidString, "name": "Angel", "type_line": "Token Creature — Angel", "power": "4", "toughness": "4", "colors": ["W"]]
        ]
        XCTAssertEqual(try parse(objects).allTokens.map(\.id), [cardID, tokenID, missingID])
        XCTAssertEqual(try parse(Array(objects.reversed())).allTokens.map(\.id), [cardID, tokenID, missingID])
    }

    func testCombinedSplitCardDoesNotInventBackFaceImage() throws {
        let card: [String: Any] = ["id": cardID.uuidString, "name": "Left // Right", "image_uris": images("combined"),
                                  "card_faces": [["name": "Left"], ["name": "Right"]]]
        let catalogue = try parse([card])
        XCTAssertEqual(catalogue.imageURL(name: "Left", size: "normal")?.lastPathComponent, "combined.jpg")
        XCTAssertNil(catalogue.imageURL(name: "Right", size: "normal"))
        XCTAssertEqual(catalogue.additionalFaceNames(for: ["Left"]), [])
    }

    func testEmblemDoesNotReplaceOrdinaryCardWithSameName() throws {
        let card: [String: Any] = ["id": cardID.uuidString, "name": "Planeswalker", "type_line": "Legendary Planeswalker", "image_uris": images("card")]
        let emblem: [String: Any] = ["id": tokenID.uuidString, "name": "Planeswalker", "layout": "emblem", "type_line": "Emblem", "colors": [], "image_uris": images("emblem")]
        for objects in [[card, emblem], [emblem, card]] {
            let catalogue = try parse(objects)
            XCTAssertEqual(catalogue.imageURL(name: "Planeswalker", size: "large")?.lastPathComponent, "card.jpg")
            XCTAssertEqual(catalogue.imageURL(id: tokenID, size: "large")?.lastPathComponent, "emblem.jpg")
            XCTAssertEqual(catalogue.allTokens.map(\.id), [tokenID])
            XCTAssertTrue(try XCTUnwrap(catalogue.token(id: tokenID)).hasMatchingMetadata)
        }
    }

    func testDuplicateOrdinaryNamesAreAmbiguousRegardlessOfOrder() throws {
        let first: [String: Any] = ["id": cardID.uuidString, "name": "Duplicate", "image_uris": images("one")]
        let second: [String: Any] = ["id": tokenID.uuidString, "name": "Duplicate", "image_uris": images("two")]
        for objects in [[first, second], [second, first]] {
            XCTAssertNil(try parse(objects).imageURL(name: "Duplicate", size: "normal"))
        }
    }

    func testArtSeriesCannotPoisonTransformAliasesInEitherOrder() throws {
        let transform: [String: Any] = ["id": cardID.uuidString, "name": "Delver of Secrets // Insectile Aberration", "layout": "transform",
            "card_faces": [["name": "Delver of Secrets", "image_uris": images("delver")],
                           ["name": "Insectile Aberration", "image_uris": images("insectile")]]]
        let art: [String: Any] = ["id": tokenID.uuidString, "name": "Delver of Secrets // Delver of Secrets", "layout": "art_series",
            "card_faces": [["name": "Delver of Secrets", "image_uris": images("art")]]]
        for objects in [[transform, art], [art, transform]] {
            let catalogue = try parse(objects)
            XCTAssertEqual(catalogue.imageURL(name: "Delver of Secrets", size: "normal")?.lastPathComponent, "delver.jpg")
            XCTAssertEqual(catalogue.imageURL(name: "Insectile Aberration", size: "normal")?.lastPathComponent, "insectile.jpg")
            XCTAssertEqual(catalogue.additionalFaceNames(for: ["Delver of Secrets"]), ["Insectile Aberration"])
            XCTAssertNil(catalogue.imageURL(id: tokenID, size: "normal"))
        }
    }

    func testDoubleFacedTokenMetadataUsesFrontAndInvalidTokensAreCounted() throws {
        let token: [String: Any] = ["id": tokenID.uuidString, "name": "Soldier // Angel", "layout": "double_faced_token",
            "card_faces": [["name": "Soldier", "type_line": "Token Creature — Soldier", "oracle_text": "Vigilance",
                            "power": "1", "toughness": "1", "colors": ["W"], "image_uris": images("soldier")]]]
        let invalid: [String: Any] = ["id": missingID.uuidString, "name": "Unknown", "layout": "token", "type_line": "Token Creature"]
        let catalogue = try parse([token, invalid])
        XCTAssertEqual(catalogue.allTokens.map(\.id), [tokenID])
        XCTAssertEqual(catalogue.allTokens.first?.name, "Soldier")
        XCTAssertEqual(catalogue.allTokens.first?.power, "1")
        XCTAssertEqual(catalogue.unavailableTokenCount, 1)
        XCTAssertEqual(catalogue.unavailableTokenNames, ["Unknown"])
        XCTAssertNotNil(catalogue.token(id: missingID))
    }

    func testLiveBulkFixtureWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["MAGICMOBILE_BULK_FIXTURE"], !path.isEmpty else {
            throw XCTSkip("Set MAGICMOBILE_BULK_FIXTURE to a downloaded local oracle bulk file; this test never accesses the network.")
        }
        let catalogue = try NativeArtworkCatalogue.parse(file: URL(fileURLWithPath: path))
        XCTAssertGreaterThan(catalogue.cardCount, 30_000)
        XCTAssertGreaterThan(catalogue.allTokens.count, 500)
        XCTAssertTrue(catalogue.allTokens.allSatisfy(\.hasMatchingMetadata))
        XCTAssertTrue(catalogue.additionalFaceNames(for: ["Delver of Secrets"]).contains("Insectile Aberration"))
        let front = try XCTUnwrap(catalogue.imageURL(name: "Delver of Secrets", size: "large"))
        let back = try XCTUnwrap(catalogue.imageURL(name: "Insectile Aberration", size: "large"))
        XCTAssertNotEqual(front, back)
        XCTAssertTrue(back.path.contains("/back/"))
        let sorin = try XCTUnwrap(catalogue.imageURL(name: "Sorin, Lord of Innistrad", size: "normal"))
        let emblem = try XCTUnwrap(catalogue.allTokens.first {
            $0.name.contains("Sorin") && $0.typeLine?.localizedCaseInsensitiveContains("emblem") == true
        })
        XCTAssertNotEqual(sorin, try XCTUnwrap(catalogue.imageURL(id: emblem.id, size: "normal")))
    }

    func testGzipAndPlainFileProduceSameCatalogue() throws {
        let object: [String: Any] = ["id": cardID.uuidString, "name": "Example", "image_uris": images("example")]
        let raw = try JSONSerialization.data(withJSONObject: object)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let stream = try XCTUnwrap(gzopen(file.path, "wb"))
        let written = raw.withUnsafeBytes { gzwrite(stream, $0.baseAddress, UInt32($0.count)) }
        XCTAssertEqual(gzclose(stream), Z_OK)
        XCTAssertEqual(written, Int32(raw.count))
        XCTAssertEqual(try NativeArtworkCatalogue.parse(file: file).imageURL(name: "Example", size: "small"),
                       try parse([object]).imageURL(name: "Example", size: "small"))
    }

    func testCancelledTaskStopsBeforeReadingFile() async {
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try NativeArtworkCatalogue.parse(file: URL(fileURLWithPath: "/nonexistent-artwork-test"))
        }
        do { _ = try await task.value; XCTFail("Cancellation must stop parsing") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    private func images(_ key: String) -> [String: String] {
        Dictionary(uniqueKeysWithValues: ["small", "normal", "large"].map { ($0, "https://cards.scryfall.io/\($0)/front/\(key).jpg") })
    }
    private func parse(_ objects: [[String: Any]]) throws -> NativeArtworkCatalogue {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try JSONSerialization.data(withJSONObject: objects).write(to: file)
        return try NativeArtworkCatalogue.parse(file: file)
    }
}

private actor ArtworkCollectionFixture: DeckStudioScryfallHTTP {
    static let tokenID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
    private(set) var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> Data {
        requests.append(request)
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: [[String: String]]])
        let identifiers = try XCTUnwrap(object["identifiers"])
        XCTAssertLessThanOrEqual(identifiers.count, 75)
        let cards: [[String: Any]] = identifiers.map { identifier in
            let token = identifier["id"] != nil
            var card: [String: Any] = ["id": token ? Self.tokenID.uuidString : UUID().uuidString,
                "name": token ? "Soldier" : identifier["name"]!, "object": "card",
                "type_line": token ? "Token Creature — Soldier" : "Creature", "layout": token ? "token" : "normal",
                "oracle_text": "", "power": "1", "toughness": "1", "colors": ["W"],
                "image_uris": Dictionary(uniqueKeysWithValues: ["small", "normal", "large"].map { ($0, "https://cards.scryfall.io/\($0)/front/fixture.jpg") })]
            if identifier["name"] == "Fixture 0" {
                card["all_parts"] = [["id": Self.tokenID.uuidString, "component": "token", "name": "Soldier"]]
            }
            return card
        }
        // The live collection endpoint omits has_more (unlike paginated search).
        return try JSONSerialization.data(withJSONObject: ["object": "list", "not_found": [], "data": cards])
    }
}
