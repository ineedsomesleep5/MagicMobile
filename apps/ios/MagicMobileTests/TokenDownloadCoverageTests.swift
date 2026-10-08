import Foundation
import XCTest
@testable import MagicMobile

/// Every token and emblem a catalogue card points to is in what a download fetches. Android's
/// ArtworkTokenCoverageTest follows the same cases.
final class TokenDownloadCoverageTests: XCTestCase {
    private func images(_ path: String) -> [String: String] {
        ["small": "https://cards.scryfall.io/small/\(path).jpg", "normal": "https://cards.scryfall.io/normal/\(path).jpg",
         "large": "https://cards.scryfall.io/large/\(path).jpg"]
    }
    private func part(_ id: UUID, _ name: String, _ component: String, _ typeLine: String) -> [String: Any] {
        ["id": id.uuidString, "name": name, "component": component, "type_line": typeLine]
    }
    private func token(_ id: UUID, _ name: String, _ typeLine: String, power: String? = "1", toughness: String? = "1",
                       colors: [String] = ["W"], rules: String = "", layout: String = "token") -> [String: Any] {
        var object: [String: Any] = ["id": id.uuidString, "name": name, "layout": layout, "type_line": typeLine, "oracle_text": rules,
                                     "colors": colors, "image_uris": images(name.lowercased().replacingOccurrences(of: " ", with: "-") + "-" + id.uuidString.prefix(4))]
        if let power { object["power"] = power }
        if let toughness { object["toughness"] = toughness }
        return object
    }
    private func catalogue(_ objects: [[String: Any]]) throws -> NativeArtworkCatalogue {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        try JSONSerialization.data(withJSONObject: objects).write(to: file)
        return try NativeArtworkCatalogue.parse(file: file)
    }

    // The five ways a card can point at a token, in one catalogue.
    private let soldier = UUID(), otherSoldierPrinting = UUID(), incubator = UUID(), emblem = UUID(), vampire = UUID(), absent = UUID()
    private func fixture() throws -> NativeArtworkCatalogue {
        try catalogue([
            // 1: the token itself is in the bulk.
            ["id": UUID().uuidString, "name": "Maker One", "layout": "normal", "type_line": "Creature",
             "all_parts": [part(soldier, "Soldier", "token", "Token Creature — Soldier")]],
            token(soldier, "Soldier", "Token Creature — Soldier"),
            // 2: the card points at another printing of a token the bulk holds under a different ID.
            ["id": UUID().uuidString, "name": "Maker Two", "layout": "normal", "type_line": "Creature",
             "all_parts": [part(otherSoldierPrinting, "Soldier", "token", "Token Creature — Soldier")]],
            // 3: a double-faced token: both faces are downloadable.
            ["id": UUID().uuidString, "name": "Maker Three", "layout": "normal", "type_line": "Sorcery",
             "all_parts": [part(incubator, "Incubator // Phyrexian", "token", "Token Artifact — Incubator // Token Artifact Creature — Phyrexian")]],
            ["id": incubator.uuidString, "name": "Incubator // Phyrexian", "layout": "double_faced_token", "type_line": "Token Artifact — Incubator // Token Artifact Creature — Phyrexian",
             "card_faces": [["name": "Incubator", "type_line": "Token Artifact — Incubator", "oracle_text": "{2}: Transform this artifact.", "colors": [String](), "image_uris": images("incubator-front")],
                            ["name": "Phyrexian", "type_line": "Token Artifact Creature — Phyrexian", "oracle_text": "", "power": "0", "toughness": "0", "colors": [String](), "image_uris": images("incubator-back")]]],
            // 4: an emblem, which Scryfall links as a combo piece, not as a token.
            ["id": UUID().uuidString, "name": "Maker Four", "layout": "normal", "type_line": "Legendary Planeswalker — Sorin",
             "all_parts": [part(vampire, "Vampire", "token", "Token Creature — Vampire"),
                           part(UUID(), "Maker Four", "combo_piece", "Legendary Planeswalker — Sorin"),
                           part(emblem, "Maker Four Emblem", "combo_piece", "Emblem — Sorin")]],
            token(vampire, "Vampire", "Token Creature — Vampire", colors: ["B"]),
            ["id": emblem.uuidString, "name": "Maker Four Emblem", "layout": "emblem", "type_line": "Emblem — Sorin",
             "oracle_text": "Creatures you control get +1/+0.", "colors": [String](), "image_uris": images("emblem")],
            // 5: a token that is neither in the bulk nor like any token in it.
            ["id": UUID().uuidString, "name": "Maker Five", "layout": "normal", "type_line": "Creature",
             "all_parts": [part(absent, "Shard Golem", "token", "Token Artifact Creature — Golem"),
                           part(UUID(), "Meld Half", "meld_part", "Legendary Creature — Eldrazi")]]
        ])
    }

    func testEmblemsLinkedAsComboPiecesCountAsTokensButMeldAndComboPiecesDoNot() throws {
        XCTAssertTrue(NativeArtworkCatalogue.isTokenPart(component: "token", typeLine: nil))
        XCTAssertTrue(NativeArtworkCatalogue.isTokenPart(component: "combo_piece", typeLine: "Emblem — Sorin"))
        XCTAssertTrue(NativeArtworkCatalogue.isTokenPart(component: "meld_result", typeLine: "Token Creature — Eldrazi"))
        XCTAssertFalse(NativeArtworkCatalogue.isTokenPart(component: "combo_piece", typeLine: "Legendary Planeswalker — Sorin"))
        XCTAssertFalse(NativeArtworkCatalogue.isTokenPart(component: "meld_part", typeLine: "Legendary Creature — Eldrazi"))
        XCTAssertFalse(NativeArtworkCatalogue.isTokenPart(component: "combo_piece", typeLine: nil))
        let related = try fixture().relatedTokens(name: "Maker Four")
        XCTAssertEqual(related.map(\.name), ["Vampire", "Maker Four Emblem"])
        XCTAssertEqual(related.last?.typeLine, "Emblem — Sorin")
        // The per-card discovery path reads the same parts.
        let json = """
        {"object":"card","all_parts":[{"id":"\(vampire)","name":"Vampire","component":"token","type_line":"Token Creature — Vampire"},
        {"id":"\(emblem)","name":"Maker Four Emblem","component":"combo_piece","type_line":"Emblem — Sorin"},
        {"id":"\(UUID())","name":"Maker Four","component":"combo_piece","type_line":"Legendary Planeswalker — Sorin"}]}
        """
        XCTAssertEqual(try NativeTokenDiscovery.decode(Data(json.utf8)).map(\.id), [vampire, emblem])
    }

    func testAllTokensHoldsEveryFaceAndEmblemAndOnlyTheUnresolvedReferencedTokenIsMissing() throws {
        let catalogue = try fixture()
        XCTAssertEqual(Set(catalogue.allTokens.map(\.name)), ["Soldier", "Incubator", "Phyrexian", "Vampire", "Maker Four Emblem"])
        XCTAssertTrue(catalogue.allTokens.contains { $0.face == "back" && $0.name == "Phyrexian" })
        // The token a card names by another printing is covered by the same token in the bulk; a different token is not.
        XCTAssertEqual(catalogue.referencedTokensWithoutDownload.map(\.id), [absent])
        XCTAssertEqual(catalogue.referencedTokensWithoutDownload.first?.name, "Shard Golem")
    }

    /// The test that fails when a catalogue card points to a token a download would skip.
    func testAfterAResolveEveryTokenAnyCardPointsToIsInTheDownloadSet() async throws {
        var catalogue = try fixture()
        let transport = TokenIDTransport(tokens: [token(absent, "Shard Golem", "Token Artifact Creature — Golem", power: "2", toughness: "2", colors: [])])
        catalogue.addTokens(from: try await NativeArtworkCatalogue.load(tokenIDs: catalogue.referencedTokensWithoutDownload.map(\.id),
                                                                       transport: transport, budget: DeckStudioScryfallBudget()))
        let asked = await transport.identifiers
        XCTAssertEqual(asked, [["id": absent.uuidString.lowercased()]], "Only the unresolved token is asked for, by exact ID")
        XCTAssertEqual(catalogue.referencedTokensWithoutDownload, [])
        let downloadable = Set(catalogue.allTokens.map(\.artworkKey))
        for name in ["Maker One", "Maker Two", "Maker Three", "Maker Four", "Maker Five"] {
            for related in catalogue.relatedTokens(name: name) {
                let front = related.name.components(separatedBy: " // ")[0]
                let covered = downloadable.contains(related.artworkKey) ||
                    catalogue.allTokens.contains { NativeAssetStore.tokenNameKey($0.name) == NativeAssetStore.tokenNameKey(front) }
                XCTAssertTrue(covered, "\(name) points to \(related.name), which no download would fetch")
            }
        }
        XCTAssertTrue(catalogue.allTokens.contains { $0.id == absent })
        XCTAssertNotNil(catalogue.imageURL(id: absent, size: "normal"))
    }

    func testATokenScryfallDoesNotReturnStaysReportedAsMissing() async throws {
        var catalogue = try fixture()
        catalogue.addTokens(from: try await NativeArtworkCatalogue.load(tokenIDs: [absent], transport: TokenIDTransport(tokens: []),
                                                                       budget: DeckStudioScryfallBudget()))
        XCTAssertEqual(catalogue.referencedTokensWithoutDownload.map(\.name), ["Shard Golem"])
    }

    func testDoubleFacedTokenAndEmblemKeepTheirOwnStoredKeys() throws {
        let catalogue = try fixture()
        let keys = catalogue.allTokens.map(\.artworkKey)
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertTrue(keys.contains(NativeAssetStore.tokenKey(incubator, face: "back")))
        XCTAssertNotNil(catalogue.imageURL(id: incubator, size: "normal", face: "back"))
        XCTAssertNotNil(catalogue.imageURL(id: emblem, size: "normal"))
    }

    func testManifestsAndRelationListsFromBeforeEmblemsReadAsIncomplete() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NativeAssetStore(directory: directory, availableBytes: { _ in Int64.max })
        let saved = NativeTokenArtwork(id: vampire, name: "Vampire", typeLine: "Token Creature — Vampire", oracleText: "", power: "1", toughness: "1", colors: ["B"])
        let tokenData = try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved))
        try JSONSerialization.data(withJSONObject: ["tokens": [tokenData], "unavailableNames": [String](), "coverageVersion": 2])
            .write(to: directory.appendingPathComponent("catalogue-tokens-v1.json"))
        let old = await store.catalogueTokenCoverageCurrent()
        XCTAssertFalse(old, "A version 2 manifest has no emblems")
        try await store.saveCatalogueTokens([saved])
        let current = await store.catalogueTokenCoverageCurrent()
        XCTAssertTrue(current)
        // A relation list saved under the old key is unknown, so the next download rediscovers it with emblems.
        let legacy = await store.file(key: NativeAssetStore.cardKey("Maker Four"), extension: "json")
        try JSONEncoder().encode([NativeTokenArtwork(id: vampire, name: "Vampire")]).write(to: legacy)
        let unreadable = await store.relations(name: "Maker Four")
        XCTAssertNil(unreadable)
        try await store.saveRelations([NativeTokenArtwork(id: emblem, name: "Maker Four Emblem")], name: "Maker Four")
        let kept = await store.relations(name: "Maker Four")
        XCTAssertEqual(kept?.map(\.id), [emblem])
    }
}

/// Scryfall's /cards/collection by exact ID: answers the tokens it has.
private actor TokenIDTransport: DeckStudioScryfallHTTP {
    private let tokens: [[String: Any]]
    private(set) var identifiers: [[String: String]] = []
    init(tokens: [[String: Any]]) { self.tokens = tokens }
    func send(_ request: URLRequest) async throws -> Data {
        let body = try XCTUnwrap(request.httpBody)
        let wanted = try XCTUnwrap((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["identifiers"] as? [[String: String]])
        identifiers += wanted
        let found = wanted.compactMap { id in tokens.first { ($0["id"] as? String)?.lowercased() == id["id"] } }
        return try JSONSerialization.data(withJSONObject: ["object": "list", "not_found": [[String: String]](), "data": found])
    }
}
