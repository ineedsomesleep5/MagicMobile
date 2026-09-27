import XCTest
import CoreGraphics
import ImageIO
@testable import MagicMobile

final class NativeAssetDownloadsTests: XCTestCase {
    /// A finished download starts its own recount. A test scan that begins before that
    /// recount runs is superseded and returns without publishing, so wait for both.
    @MainActor private func settle(_ model: NativeAssetDownloads) async throws {
        for _ in 0..<500 where model.isRunning || model.isScanning { try await Task.sleep(for: .milliseconds(10)) }
    }

    @MainActor func testFailedScanCannotLeaveSuccessfulCoverageState() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = NativeAssetDownloads(store: NativeAssetStore(directory: directory))
        await model.scan(names: ["Sol Ring"])
        XCTAssertTrue(model.scanSucceeded)
        await model.scan(names: [String(repeating: "x", count: 10_000)])
        XCTAssertFalse(model.scanSucceeded)
        XCTAssertFalse(model.isScanning)
    }
    @MainActor func testOptInFullPublicTokenDownloadThenOfflineReopenAndMissingOnlyRetry() async throws {
        guard ProcessInfo.processInfo.environment["MM_LIVE_FULL_TOKEN_DOWNLOAD"] == "1",
              let fixture = ProcessInfo.processInfo.environment["MAGICMOBILE_BULK_FIXTURE"],
              let destination = ProcessInfo.processInfo.environment["MAGICMOBILE_ARTWORK_AUDIT_DIR"] else {
            throw XCTSkip("Explicit live token-download opt-in and local catalogue/audit paths required.")
        }
        let catalogue = try NativeArtworkCatalogue.parse(file: URL(fileURLWithPath: fixture))
        for family in ["Soldier", "Human", "Elf Warrior", "Zombie", "Treasure"] {
            XCTAssertTrue(catalogue.allTokens.contains { $0.name == family }, "Full catalogue must cover \(family)")
        }
        let directory = URL(fileURLWithPath: destination, isDirectory: true)
        let store = NativeAssetStore(directory: directory.appendingPathComponent("images"))
        let queue = NativeArtworkBackgroundQueue(directory: directory.appendingPathComponent("queue"), store: store,
            configuration: .ephemeral, allowNetwork: { true })
        let model = NativeAssetDownloads(store: store, catalogueLoader: { catalogue }, backgroundQueue: queue)
        model.download(names: ["Betor, Kin to All"], includeTokens: true, allowNetwork: true, quality: .standard, fullCatalogue: true)
        let deadline = Date().addingTimeInterval(300)
        while (model.isRunning || model.isScanning) && Date() < deadline { try await Task.sleep(for: .milliseconds(200)) }
        if model.isRunning { model.cancel(); XCTFail("Public artwork download exceeded five minutes"); return }
        XCTAssertEqual(model.failures, [])
        XCTAssertEqual(model.tokenStored, catalogue.allTokens.count)
        XCTAssertEqual(model.cardStored, 1)
        let reopened = NativeAssetStore(directory: directory.appendingPathComponent("images"))
        let offline = NativeDeckArtwork(assetStore: reopened, tokenLookup: { _, _, _, _, _, _, _ in
            XCTFail("Offline verification must not use token search"); throw URLError(.notConnectedToInternet)
        })
        for token in catalogue.allTokens {
            let runtimeName = token.name.hasSuffix(" Token") ? token.name : token.name + " Token"
            let bytes = try await offline.imageData(name: runtimeName, variant: .board, allowNetwork: false,
                tokenTypeLine: token.typeLine, tokenOracleText: token.oracleText, tokenPower: token.power,
                tokenToughness: token.toughness, tokenColors: token.colors)
            XCTAssertNotNil(bytes, "Offline token missing: \(token.name) \(token.artworkKey)")
            if let bytes { XCTAssertNotNil(NativeDeckArtwork.decodedImage(bytes, variant: .board)) }
        }
        let commander = try await offline.imageData(name: "Betor, Kin to All", variant: .board, allowNetwork: false)
        XCTAssertNotNil(commander)
        model.download(names: ["Betor, Kin to All"], includeTokens: true, allowNetwork: true, quality: .standard, fullCatalogue: true)
        while (model.isRunning || model.isScanning) && Date() < deadline { try await Task.sleep(for: .milliseconds(200)) }
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(queue.total, 0, "Second download must transfer no already stored images")
        print("OFFLINE_TOKEN_AUDIT tokens=\(catalogue.allTokens.count) backFaces=\(catalogue.allTokens.filter { $0.face == "back" }.count) commander=Betor repeatedTransfers=\(queue.total) bytes=\(model.storedBytes)")
    }
    func testExactTokenPrintingsRemainResolvableBesideVariableTokenOffline() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NativeAssetStore(directory: directory, availableBytes: { _ in Int64.max })
        let first = NativeTokenArtwork(id: UUID(), name: "Zombie", typeLine: "Token Creature — Zombie", oracleText: "", power: "2", toughness: "2", colors: ["B"])
        var other = first; other.face = "back"
        let variable = NativeTokenArtwork(id: UUID(), name: "Zombie", typeLine: "Token Creature — Zombie", oracleText: "", power: "*", toughness: "*", colors: ["B"])
        let bytes = try image(width: 488, height: 680)
        for token in [first, other, variable] { try await store.saveToken(token) }
        try await store.save(bytes, key: other.artworkKey, quality: .standard)
        let reopened = NativeAssetStore(directory: directory, availableBytes: { _ in Int64.max })
        let offline = await reopened.tokenImage(name: "Zombie Token", typeLine: "Creature — Zombie", oracleText: "", power: "2", toughness: "2", colors: ["B"])
        XCTAssertEqual(offline, bytes, "Equivalent exact printings must resolve even beside a different variable-size token")
        let wrong = await reopened.tokenImage(name: "Zombie Token", typeLine: "Creature — Zombie", oracleText: "Decayed", power: "2", toughness: "2", colors: ["B"])
        XCTAssertNil(wrong)
    }

    func testTreasureSelfReferenceWordingAndRefreshUseTokenIdentity() async throws {
        let treasure = NativeTokenArtwork(id: UUID(), name: "Treasure", typeLine: "Token Artifact — Treasure",
            oracleText: "{T}, Sacrifice this token: Add one mana of any color.", colors: [])
        XCTAssertEqual(NativeAssetStore.matchTokenArtwork([treasure], name: "Treasure Token", typeLine: "Artifact — Treasure",
            oracleText: "{T}, Sacrifice this artifact: Add one mana of any color.", power: "0", toughness: "0", colors: []), treasure)
        XCTAssertNil(NativeAssetStore.matchTokenArtwork([treasure], name: "Treasure Token", typeLine: "Artifact — Treasure",
            oracleText: "{T}, Sacrifice this artifact: Add {C}.", power: "0", toughness: "0", colors: []))
        XCTAssertTrue(NativeAssetStore.artworkChangeAffects(key: treasure.artworkKey, storedName: "Treasure", name: "Treasure Token", isToken: true))
        XCTAssertFalse(NativeAssetStore.artworkChangeAffects(key: treasure.artworkKey, storedName: "Treasure", name: "Zombie Token", isToken: true))
    }
    func testEngineStyleFoodSelfReferenceFindsDownloadedArtworkOffline() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NativeAssetStore(directory: directory, availableBytes: { _ in Int64.max })
        let food = NativeTokenArtwork(id: UUID(), name: "Food", typeLine: "Token Artifact — Food",
            oracleText: "{2}, {T}, Sacrifice this token: You gain 3 life.", colors: [])
        let imageBytes = try image(width: 488, height: 680)
        try await store.saveToken(food)
        try await store.save(imageBytes, key: food.artworkKey, quality: .standard)

        let reopened = NativeAssetStore(directory: directory, availableBytes: { _ in Int64.max })
        let offline = NativeDeckArtwork(assetStore: reopened, tokenLookup: { _, _, _, _, _, _, _ in
            XCTFail("Downloaded Food must resolve without a network lookup")
            return nil
        })
        let artwork = try await offline.imageData(name: "Food Token", variant: .board, allowNetwork: false,
            tokenTypeLine: "Artifact — Food",
            tokenOracleText: "{2}, {T}, Sacrifice Food Token: You gain 3 life.",
            tokenPower: "0", tokenToughness: "0", tokenColors: [])
        XCTAssertEqual(artwork, imageBytes)
    }
    /// Offline only: a downloaded token whose rules are worded differently still shows when
    /// name, type, colors and printed P/T agree and the downloads hold one such token.
    func testOfflineFallbackUsesTheOnlyDownloadedTokenWithTheSameIdentity() async throws {
        let squirrel = NativeTokenArtwork(id: UUID(), name: "Squirrel", typeLine: "Token Creature — Squirrel",
            oracleText: "", power: "1", toughness: "1", colors: ["G"])
        let store = NativeAssetStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                                     availableBytes: { _ in Int64.max })
        let bytes = try image(width: 488, height: 680)
        try await store.saveToken(squirrel)
        try await store.save(bytes, key: squirrel.artworkKey, quality: .standard)
        func lookup(_ rules: String, power: String = "1", colors: [String] = ["G"], offline: Bool) async -> Data? {
            await store.tokenImage(name: "Squirrel Token", typeLine: "Creature — Squirrel", oracleText: rules,
                                   power: power, toughness: "1", colors: colors, offlineFallback: offline)
        }
        let result1 = await lookup("Forestwalk", offline: false); XCTAssertNil(result1, "online keeps the exact match")
        let result2 = await lookup("Forestwalk", offline: true); XCTAssertEqual(result2, bytes)
        let result3 = await lookup("Forestwalk", power: "2", offline: true); XCTAssertNil(result3, "a different printed P/T is a different token")
        let result4 = await lookup("Forestwalk", colors: ["B"], offline: true); XCTAssertNil(result4, "a different color is a different token")
        let flier = NativeTokenArtwork(id: UUID(), name: "Squirrel", typeLine: "Token Creature — Squirrel",
            oracleText: "Flying", power: "1", toughness: "1", colors: ["G"])
        try await store.saveToken(flier)
        try await store.save(bytes, key: flier.artworkKey, quality: .standard)
        let result5 = await lookup("Trample", offline: true); XCTAssertNil(result5, "two different downloads stay ambiguous")
    }
    func testFoodWithoutTokenSuffixMatchesDownloadedFood() {
        let food = NativeTokenArtwork(id: UUID(), name: "Food", typeLine: "Token Artifact — Food",
            oracleText: "{2}, {T}, Sacrifice this token: You gain 3 life.", colors: [])
        XCTAssertEqual(NativeAssetStore.matchTokenArtwork([food], name: "Food", typeLine: "Artifact — Food",
            oracleText: "{2}, {T}, Sacrifice Food: You gain 3 life.", power: "0", toughness: "0", colors: []), food)
    }
    func testNamedTokenSelfReferenceDoesNotCollapseOtherRulesOrVariants() {
        let food = NativeTokenArtwork(id: UUID(), name: "Food", typeLine: "Token Artifact — Food",
            oracleText: "{2}, {T}, Sacrifice this token: You gain 3 life.", colors: [])
        let differentFood = NativeTokenArtwork(id: UUID(), name: "Food", typeLine: "Token Artifact — Food",
            oracleText: "{2}, {T}, Sacrifice this token: Add {C}.", colors: [])
        func match(_ rules: String) -> NativeTokenArtwork? {
            NativeAssetStore.matchTokenArtwork([food, differentFood], name: "Food Token",
                typeLine: "Artifact — Food", oracleText: rules, power: "0", toughness: "0", colors: [])
        }
        XCTAssertEqual(match("{2}, {T}, Sacrifice Food Token: You gain 3 life."), food)
        XCTAssertNil(match("{2}, {T}, Sacrifice a Food Token: You gain 3 life."))
        XCTAssertNil(match("{2}, {T}, Sacrifice Food Token: Draw a card."))
        XCTAssertFalse(NativeAssetStore.sameTokenIdentity(food, differentFood))

        let treasure = NativeTokenArtwork(id: UUID(), name: "Treasure", typeLine: "Token Artifact — Treasure",
            oracleText: "{T}, Sacrifice this artifact: Add one mana of any color.", colors: [])
        XCTAssertEqual(NativeAssetStore.matchTokenArtwork([treasure], name: "Treasure Token",
            typeLine: "Artifact — Treasure", oracleText: "{T}, Sacrifice Treasure Token: Add one mana of any color.",
            power: "0", toughness: "0", colors: []), treasure)
    }
    func testLiveDownloadedFoodResolvesEngineStyleRequestWhenAuditStoreProvided() async throws {
        guard let audit = ProcessInfo.processInfo.environment["MAGICMOBILE_ARTWORK_AUDIT_DIR"] else {
            throw XCTSkip("Set MAGICMOBILE_ARTWORK_AUDIT_DIR to the existing read-only token audit store")
        }
        let store = NativeAssetStore(directory: URL(fileURLWithPath: audit).appendingPathComponent("images"))
        let offline = NativeDeckArtwork(assetStore: store, tokenLookup: { _, _, _, _, _, _, _ in
            XCTFail("The existing Food download must work offline")
            return nil
        })
        for (name, type, rules) in [
            ("Food", "Food", "{2}, {T}, Sacrifice Food Token: You gain 3 life."),
            ("Treasure", "Treasure", "{T}, Sacrifice Treasure Token: Add one mana of any color."),
            ("Clue", "Clue", "{2}, Sacrifice Clue Token: Draw a card."),
            ("Blood", "Blood", "{1}, {T}, Discard a card, Sacrifice Blood Token: Draw a card.")
        ] {
            let artwork = try await offline.imageData(name: name + " Token", variant: .board, allowNetwork: false,
                tokenTypeLine: "Artifact — " + type, tokenOracleText: rules,
                tokenPower: "0", tokenToughness: "0", tokenColors: [])
            XCTAssertNotNil(artwork, "Previously downloaded \(name) must resolve its engine-style self name offline")
        }
    }
    @MainActor func testTokenOnlyDownloadsNoCardsAndResumesFromStoredImage() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let tokenID = UUID()
        let fixture = directory.appendingPathComponent("tokens.json")
        try JSONSerialization.data(withJSONObject: [
            ["id": tokenID.uuidString, "name": "Zombie", "layout": "token",
             "type_line": "Token Creature — Zombie", "oracle_text": "", "power": "2", "toughness": "2", "colors": ["B"],
             "image_uris": ["normal": "https://cards.scryfall.io/normal/zombie.jpg"]]
        ]).write(to: fixture)
        let bytes = try image(width: 488, height: 680)
        DownloadImageFixtureProtocol.configure(data: bytes)
        defer { DownloadImageFixtureProtocol.configure(data: Data()) }
        let store = NativeAssetStore(directory: directory.appendingPathComponent("images"), availableBytes: { _ in Int64.max })
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DownloadImageFixtureProtocol.self]
        let queue = NativeArtworkBackgroundQueue(directory: directory.appendingPathComponent("queue"), store: store,
                                                configuration: configuration, allowNetwork: { true })
        let model = NativeAssetDownloads(store: store, catalogueLoader: { try NativeArtworkCatalogue.parse(file: fixture) }, backgroundQueue: queue)
        model.download(names: [], includeTokens: true, allowNetwork: false, quality: .standard, fullCatalogue: true, tokenOnly: true)
        XCTAssertEqual(DownloadImageFixtureProtocol.urls.count, 0)
        for run in 0..<2 {
            model.download(names: [], includeTokens: true, allowNetwork: true, quality: .standard, fullCatalogue: true, tokenOnly: true)
            try await settle(model)
            await model.scan(names: [], quality: .standard, fullCatalogue: true, tokenOnly: true)
            XCTAssertFalse(model.isRunning)
            XCTAssertEqual(model.failures, [])
            XCTAssertEqual(model.cardTotal, 0)
            XCTAssertEqual(model.tokenTotal, 1)
            XCTAssertEqual(model.tokenStored, 1)
            XCTAssertEqual(DownloadImageFixtureProtocol.urls.count, 1, "Run \(run) must not redownload")
        }
        let stored = await store.image(key: NativeAssetStore.tokenKey(tokenID), quality: .standard)
        XCTAssertEqual(stored, bytes)
    }

    func testTokenArtMatchesModifiedStatsOnlyWhenBaseIdentityUnambiguous() {
        let zombie = NativeTokenArtwork(id: UUID(), name: "Zombie", typeLine: "Token Creature — Zombie",
                                        oracleText: "", power: "2", toughness: "2", colors: ["B"])
        let alternate = NativeTokenArtwork(id: UUID(), name: "Zombie", typeLine: "Token Creature — Zombie",
                                           oracleText: "", power: "3", toughness: "3", colors: ["B"])
        func match(_ candidates: [NativeTokenArtwork], _ name: String = "Zombie", _ text: String = "") -> NativeTokenArtwork? {
            NativeAssetStore.matchTokenArtwork(candidates, name: name, typeLine: "Creature — Zombie",
                                               oracleText: text, power: "4", toughness: "4", colors: ["B"])
        }
        XCTAssertEqual(match([zombie]), zombie)
        XCTAssertEqual(match([zombie], "Zombie Token"), zombie)
        XCTAssertNil(match([zombie, alternate]))
        XCTAssertNil(match([zombie], "Human"))
        XCTAssertNil(match([zombie], "Flying"))
        XCTAssertNil(NativeAssetStore.matchTokenArtwork([zombie], name: "Zombie", typeLine: "Creature — Zombie",
                                                       oracleText: "", power: "2", toughness: "2", colors: nil))
        let catBeast = NativeTokenArtwork(id: UUID(), name: "Cat Beast", typeLine: "Token Creature — Cat Beast",
                                         oracleText: "", power: "3", toughness: "2", colors: ["G"])
        XCTAssertEqual(NativeAssetStore.matchTokenArtwork([catBeast], name: "Cat Beast Token",
                                                           typeLine: "Creature — Cat Beast", oracleText: "",
                                                           power: "5", toughness: "4", colors: ["G"]), catBeast)
        XCTAssertEqual(NativeAssetStore.tokenArtworkName("Token"), "Token")
        XCTAssertEqual(NativeAssetStore.tokenArtworkName("Token Collector"), "Token Collector")
    }
    func testEquivalentTokenPrintingUsesTheStoredImageWhenFirstIsMissing() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NativeAssetStore(directory: directory, availableBytes: { _ in Int64.max })
        let first = NativeTokenArtwork(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Zombie",
                                       typeLine: "Token Creature — Zombie", oracleText: "", power: "2", toughness: "2", colors: ["B"])
        let second = NativeTokenArtwork(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Zombie",
                                        typeLine: "Token Creature — Zombie", oracleText: "", power: "2", toughness: "2", colors: ["B"])
        try await store.saveToken(first)
        try await store.saveToken(second)
        let bytes = try image(width: 488, height: 680)
        try await store.save(bytes, key: NativeAssetStore.tokenKey(second.id), quality: .standard)
        let result = await store.tokenImage(name: "Zombie", typeLine: "Creature — Zombie", oracleText: "",
                                            power: "4", toughness: "4", colors: ["B"])
        XCTAssertEqual(result, bytes)
    }
    @MainActor func testProductionFullCataloguePlanUsesBackgroundQueueAndSkipsStoredImages() async throws {
        try await verifyBackgroundPlan(fullCatalogue: true)
    }

    @MainActor func testProductionDeckPlanKeepsExactRelatedTokenIdentityAndDownloadsBackFace() async throws {
        try await verifyBackgroundPlan(fullCatalogue: false)
    }

    @MainActor private func verifyBackgroundPlan(fullCatalogue: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let tokenID = UUID(), unrelatedTokenID = UUID(), cardID = UUID()
        let front = "Background Front \(UUID())", back = "Background Back \(UUID())"
        func images(_ path: String) -> [String: String] {
            ["small": "https://cards.scryfall.io/small/\(path).jpg", "normal": "https://cards.scryfall.io/normal/\(path).jpg", "large": "https://cards.scryfall.io/large/\(path).jpg"]
        }
        var objects: [[String: Any]] = [
            ["id": cardID.uuidString, "name": "\(front) // \(back)", "layout": "transform", "type_line": "Creature",
             "all_parts": [["id": tokenID.uuidString, "name": "Soldier", "component": "token"]],
             "card_faces": [["name": front, "image_uris": images("front")], ["name": back, "image_uris": images("back")]]],
            ["id": tokenID.uuidString, "name": "Soldier", "layout": "token", "type_line": "Token Creature — Soldier",
             "oracle_text": "Vigilance", "power": "1", "toughness": "1", "colors": ["W"], "image_uris": images("exact-soldier")]
        ]
        if !fullCatalogue {
            objects.append(["id": unrelatedTokenID.uuidString, "name": "Soldier", "layout": "token", "type_line": "Token Creature — Soldier",
                            "oracle_text": "", "power": "2", "toughness": "2", "colors": ["B"], "image_uris": images("wrong-soldier")])
        }
        let fixture = directory.appendingPathComponent("bulk.json")
        try JSONSerialization.data(withJSONObject: objects).write(to: fixture)
        let bytes = try image(width: 488, height: 680)
        DownloadImageFixtureProtocol.configure(data: bytes)
        defer { DownloadImageFixtureProtocol.configure(data: Data()) }
        let store = NativeAssetStore(directory: directory.appendingPathComponent("images"), availableBytes: { _ in Int64.max })
        // Compact artwork must not make a Standard-quality job incorrectly skip the front.
        try await store.save(image(width: 146, height: 204), key: NativeAssetStore.cardKey(front), quality: .compact)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DownloadImageFixtureProtocol.self]
        let queue = NativeArtworkBackgroundQueue(directory: directory.appendingPathComponent("queue"), store: store,
                                                configuration: configuration, allowNetwork: { true })
        let model = NativeAssetDownloads(store: store, catalogueLoader: { try NativeArtworkCatalogue.parse(file: fixture) },
            backgroundQueue: queue, deckCatalogueLoader: { names, includeTokens in
                XCTAssertEqual(names, [front]); XCTAssertTrue(includeTokens)
                return try NativeArtworkCatalogue.parse(file: fixture)
            }, tokenSearch: { _ in NativeArtworkCatalogue() }, rulesText: { _ in [:] }, opponentDecks: { [] })
        let stored = expectation(description: "Each stored image refreshes artwork consumers")
        stored.expectedFulfillmentCount = 3
        let observer = NotificationCenter.default.addObserver(forName: NativeArtworkBackgroundQueue.didStoreImage, object: nil, queue: .main) { _ in stored.fulfill() }
        defer { NotificationCenter.default.removeObserver(observer) }
        model.download(names: [front], includeTokens: true, allowNetwork: true, quality: .standard, fullCatalogue: fullCatalogue)
        try await settle(model)
        XCTAssertFalse(model.isRunning); XCTAssertFalse(queue.isRunning)
        XCTAssertEqual(model.failures, []); XCTAssertEqual(model.completed, 3); XCTAssertEqual(model.total, 3)
        await fulfillment(of: [stored], timeout: 2)
        NotificationCenter.default.removeObserver(observer)
        XCTAssertEqual(try queuedKeys(directory.appendingPathComponent("queue")).map { $0.hasPrefix("token:") }, [true, false, false],
                       "Token images are queued before card images")
        XCTAssertEqual(DownloadImageFixtureProtocol.urls.count, 3)
        XCTAssertEqual(Set(DownloadImageFixtureProtocol.urls.map(\.lastPathComponent)), ["front.jpg", "back.jpg", "exact-soldier.jpg"])
        XCTAssertTrue(DownloadImageFixtureProtocol.urls.allSatisfy { $0.host == "cards.scryfall.io" && $0.path.hasPrefix("/normal/") })
        let frontData = await store.image(key: NativeAssetStore.cardKey(front), quality: .standard)
        let backData = await store.image(key: NativeAssetStore.cardKey(back), quality: .standard)
        let tokenData = await store.image(key: NativeAssetStore.tokenKey(tokenID), quality: .standard)
        let token = await store.tokenDetails(id: tokenID)
        let unrelated = await store.tokenDetails(id: unrelatedTokenID)
        XCTAssertEqual(frontData, bytes); XCTAssertEqual(backData, bytes); XCTAssertEqual(tokenData, bytes)
        XCTAssertEqual(token?.id, tokenID); XCTAssertEqual(token?.oracleText, "Vigilance"); XCTAssertNil(unrelated)
        await model.scan(names: [front, back], quality: .standard, fullCatalogue: fullCatalogue)
        XCTAssertEqual(model.cardStored, 2); XCTAssertEqual(model.tokenStored, 1)
        model.download(names: [front], includeTokens: true, allowNetwork: true, quality: .standard, fullCatalogue: fullCatalogue)
        try await settle(model)
        XCTAssertFalse(model.isRunning); XCTAssertEqual(model.failures, [])
        XCTAssertEqual(queue.total, 0); XCTAssertEqual(model.total, 0)
        XCTAssertEqual(DownloadImageFixtureProtocol.urls.count, 3, "Repeat should not transfer any already stored image")
        // A single corrupt file must produce one repair, preserving other art.
        let frontFile = await store.file(key: NativeAssetStore.cardKey(front) + "|standard")
        try Data("interrupted image".utf8).write(to: frontFile)
        await model.scan(names: [front], quality: .standard, fullCatalogue: fullCatalogue)
        XCTAssertEqual(model.missingNames, [front])
        model.download(names: [front], includeTokens: true, allowNetwork: true, quality: .standard, fullCatalogue: fullCatalogue)
        try await settle(model)
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(queue.total, 1)
        XCTAssertEqual(DownloadImageFixtureProtocol.urls.count, 4)
        let retainedBack = await store.image(key: NativeAssetStore.cardKey(back), quality: .standard)
        XCTAssertEqual(retainedBack, bytes)
    }

    @MainActor func testFullCatalogueDownloadStoresFrontBackAndTokenWithoutNamedRequestsAndResumesOffline() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let tokenID = UUID()
        let front = "Fixture Front \(UUID().uuidString)", back = "Fixture Back \(UUID().uuidString)"
        func images(_ path: String) -> [String: String] { ["small": "https://cards.scryfall.io/small/\(path).jpg", "normal": "https://cards.scryfall.io/normal/\(path).jpg", "large": "https://cards.scryfall.io/large/\(path).jpg"] }
        let objects: [[String: Any]] = [
            ["id": UUID().uuidString, "name": "\(front) // \(back)", "layout": "transform", "type_line": "Creature",
             "card_faces": [["name": front, "image_uris": images("front")], ["name": back, "image_uris": images("back")]]],
            ["id": tokenID.uuidString, "name": "Soldier", "layout": "token", "type_line": "Token Creature — Soldier",
             "oracle_text": "", "power": "1", "toughness": "1", "colors": ["W"], "image_uris": images("soldier")]
        ]
        let fixture = directory.appendingPathComponent("bulk.json")
        try JSONSerialization.data(withJSONObject: objects).write(to: fixture)
        let bytes = try image(width: 488, height: 680)
        DownloadImageFixtureProtocol.configure(data: bytes)
        defer { DownloadImageFixtureProtocol.configure(data: Data()) }
        let cache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 0, diskPath: nil)
        let artwork = NativeDeckArtwork(cache: cache, protocolClasses: [DownloadImageFixtureProtocol.self])
        let store = NativeAssetStore(directory: directory.appendingPathComponent("artwork"), availableBytes: { _ in Int64.max })
        let model = NativeAssetDownloads(store: store, artwork: artwork, catalogueLoader: { try NativeArtworkCatalogue.parse(file: fixture) })
        for run in 0..<2 {
            cache.removeAllCachedResponses()
            model.download(names: [front], includeTokens: true, allowNetwork: true, quality: .standard, fullCatalogue: true)
            for _ in 0..<500 {
                if !model.isRunning { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            if model.isRunning { model.cancel(); XCTFail("Bounded fixture run did not complete") }
            XCTAssertFalse(model.isRunning)
            XCTAssertEqual(model.status, "Download complete.")
            XCTAssertEqual(model.failures, [])
            XCTAssertEqual(model.cardTotal, 2); XCTAssertEqual(model.cardStored, 2)
            XCTAssertEqual(model.tokenTotal, 1); XCTAssertEqual(model.tokenStored, 1)
            XCTAssertEqual(model.completed, 3); XCTAssertEqual(model.total, 3)
            XCTAssertEqual(DownloadImageFixtureProtocol.urls.count, 3, "Run \(run) should request only missing images")
        }
        let frontBytes = await store.image(key: NativeAssetStore.cardKey(front), quality: .standard)
        let backBytes = await store.image(key: NativeAssetStore.cardKey(back), quality: .standard)
        let tokenBytes = await store.image(key: NativeAssetStore.tokenKey(tokenID), quality: .standard)
        let faces = await store.catalogueFaces(), tokens = await store.catalogueTokens()
        XCTAssertEqual(frontBytes, bytes); XCTAssertEqual(backBytes, bytes); XCTAssertEqual(tokenBytes, bytes)
        XCTAssertEqual(faces, [back]); XCTAssertEqual(tokens?.map(\.id), [tokenID])
        XCTAssertTrue(DownloadImageFixtureProtocol.urls.allSatisfy { $0.host == "cards.scryfall.io" && $0.path.hasPrefix("/normal/") })
        await model.scan(names: [front], quality: .high, fullCatalogue: true)
        XCTAssertEqual(model.cardStored, 0); XCTAssertEqual(model.tokenStored, 0)
    }
    @MainActor func testCatalogueScaleNamesAreBoundedAndDeduplicated() throws {
        let names = (0..<5_001).map { "Card \($0)" }
        XCTAssertEqual(try NativeAssetDownloads.names(names + [" Card 0 "]).count, 5_001)
        XCTAssertThrowsError(try NativeAssetDownloads.names(Array(repeating: "Card", count: NativeAssetDownloads.maximumNames * 2 + 1)))
    }

    func testQualityCoverageRequiresRequestedResolutionOrHigher() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NativeAssetStore(directory: directory, availableBytes: { _ in Int64.max })
        let compact = try image(width: 146, height: 204)
        let high = try image()
        try await store.save(compact, key: "card", quality: .compact)
        let compactHit = await store.image(key: "card", quality: .compact)
        let highMiss = await store.image(key: "card", quality: .high)
        XCTAssertEqual(compactHit, compact); XCTAssertNil(highMiss)
        do { try await store.save(compact, key: "card", quality: .standard); XCTFail("Reject undersized image") } catch {}
        try await store.save(high, key: "card", quality: .high)
        let best = await store.image(key: "card")
        let standard = await store.image(key: "card", quality: .standard)
        XCTAssertEqual(best, high); XCTAssertEqual(standard, high)
    }

    func testByteAccountingReplacementAndLowFreeSpacePreserveFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = try image()
        let store = NativeAssetStore(directory: directory, availableBytes: { _ in Int64.max })
        try await store.save(data, key: "first")
        try await store.save(data, key: "first")
        try await store.save(data, key: "second")
        let accounted = await store.storedBytes()
        let reconciled = await store.storedBytes(refresh: true)
        XCTAssertEqual(accounted, data.count * 2); XCTAssertEqual(reconciled, accounted)
        let lowSpace = NativeAssetStore(directory: directory, availableBytes: { _ in Int64(NativeAssetStore.minimumFreeBytes) })
        do { try await lowSpace.save(data, key: "first"); XCTFail("Atomic write must reserve full new bytes") }
        catch { XCTAssertTrue(error is NativeAssetStore.StoreError) }
        let preserved = await lowSpace.image(key: "first")
        XCTAssertEqual(preserved, data)
    }

    @MainActor func testScanReportsQualityUpgradeAsMissingUntilHigherResolutionStored() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NativeAssetStore(directory: directory, availableBytes: { _ in Int64.max })
        try await store.save(image(width: 146, height: 204), key: NativeAssetStore.cardKey("Card"), quality: .compact)
        let model = NativeAssetDownloads(store: store)
        await model.scan(names: ["Card"], quality: .compact)
        XCTAssertEqual(model.cardStored, 1)
        await model.scan(names: ["Card"], quality: .standard)
        XCTAssertEqual(model.cardStored, 0)
        XCTAssertEqual(model.missingNames, ["Card"])
        try await store.save(image(), key: NativeAssetStore.cardKey("Card"), quality: .high)
        await model.scan(names: ["Card"], quality: .standard)
        XCTAssertEqual(model.cardStored, 1)
    }

    @MainActor func testFullCatalogueUsesCanonicalTokenManifestAndRequiresCompleteFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NativeAssetStore(directory: directory, availableBytes: { _ in Int64.max })
        let model = NativeAssetDownloads(store: store)
        await model.scan(names: ["Creator"], fullCatalogue: true)
        XCTAssertEqual(model.tokenDiscoveryRemaining, 1)
        let token = NativeTokenArtwork(id: UUID(), name: "Soldier", typeLine: "Token Creature — Soldier", oracleText: "", power: "1", toughness: "1", colors: ["W"])
        try await store.saveRelations([NativeTokenArtwork(id: UUID(), name: "Different printing")], name: "Creator")
        try await store.saveCatalogueTokens([token])
        await model.scan(names: ["Creator"], fullCatalogue: true)
        XCTAssertEqual(model.tokenDiscoveryRemaining, 0)
        XCTAssertEqual(model.tokenTotal, 1)
        XCTAssertEqual(model.missingTokenNames, ["Soldier"])
        try await store.saveToken(token)
        try await store.save(image(), key: NativeAssetStore.tokenKey(token.id))
        await model.scan(names: ["Creator"], fullCatalogue: true)
        XCTAssertEqual(model.tokenStored, 1)
        try Data("broken".utf8).write(to: directory.appendingPathComponent("catalogue-tokens-v1.json"))
        await model.scan(names: ["Creator"], fullCatalogue: true)
        XCTAssertEqual(model.tokenTotal, 0)
        XCTAssertEqual(model.tokenDiscoveryRemaining, 1)
    }

    func testCanonicalTokenManifestRejectsDuplicateIDsAndOversizedLists() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NativeAssetStore(directory: directory, availableBytes: { _ in Int64.max })
        let token = NativeTokenArtwork(id: UUID(), name: "Treasure", typeLine: "Token Artifact — Treasure", oracleText: "", colors: [])
        try await store.saveCatalogueTokens([token])
        do { try await store.saveCatalogueTokens([token, token]); XCTFail("Duplicate UUIDs must fail") } catch {}
        do { try await store.saveCatalogueTokens(Array(repeating: token, count: 10_001)); XCTFail("Oversized list must fail") } catch {}
        let preserved = await store.catalogueTokens()
        XCTAssertEqual(preserved, [token])
    }

    @MainActor func testUnsupportedCatalogueTokensRemainMissingInsteadOfComplete() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NativeAssetStore(directory: directory, availableBytes: { _ in Int64.max })
        let token = NativeTokenArtwork(id: UUID(), name: "Treasure", typeLine: "Token Artifact — Treasure", oracleText: "", colors: [])
        try await store.saveCatalogueTokens([token], unavailableNames: ["Unsupported token"])
        try await store.saveToken(token)
        try await store.save(image(), key: NativeAssetStore.tokenKey(token.id))
        let model = NativeAssetDownloads(store: store)
        await model.scan(names: [], fullCatalogue: true)
        XCTAssertEqual(model.tokenTotal, 2)
        XCTAssertEqual(model.tokenStored, 1)
        XCTAssertEqual(model.missingTokenNames, ["Unsupported token"])
        XCTAssertEqual(model.downloadableMissingTokenCount, 0, "Unavailable artwork must not inflate transfer estimate")
        XCTAssertEqual(model.tokenDiscoveryRemaining, 0)
        do { try await store.saveCatalogueTokens([], unavailableNames: [String(repeating: "x", count: 513)]); XCTFail("Reject oversized unavailable name") } catch {}
        let unavailable = await store.unavailableCatalogueTokenNames()
        XCTAssertEqual(unavailable, ["Unsupported token"])
    }

    @MainActor func testFullCatalogueScanIncludesPersistedTransformFacesOnlyInFullScope() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NativeAssetStore(directory: directory, availableBytes: { _ in Int64.max })
        let model = NativeAssetDownloads(store: store)
        await model.scan(names: ["Delver of Secrets"], fullCatalogue: true)
        XCTAssertTrue(model.faceDiscoveryPending)
        try await store.saveCatalogueFaces(["Insectile Aberration"])
        try await store.save(image(), key: NativeAssetStore.cardKey("Insectile Aberration"))
        await model.scan(names: ["Delver of Secrets"], fullCatalogue: true)
        XCTAssertFalse(model.faceDiscoveryPending)
        XCTAssertEqual(model.cardTotal, 2)
        XCTAssertEqual(model.cardStored, 1)
        XCTAssertEqual(model.missingNames, ["Delver of Secrets"])
        await model.scan(names: ["Delver of Secrets"], fullCatalogue: false)
        XCTAssertEqual(model.cardTotal, 1)
        XCTAssertEqual(model.cardStored, 0)
        do { try await store.saveCatalogueFaces(["Insectile Aberration", "insectile aberration"]); XCTFail("Reject duplicate face keys") } catch {}
        do { try await store.saveCatalogueFaces(Array(repeating: "Face", count: 10_001)); XCTFail("Reject oversized face manifest") } catch {}
        do { try await store.saveCatalogueFaces([String(repeating: "x", count: 513)]); XCTFail("Reject overlong face name") } catch {}
        let preserved = await store.catalogueFaces()
        XCTAssertEqual(preserved, ["Insectile Aberration"])
    }
    func testRelatedTokensUseIDsAndExcludeMeldAndComboParts() throws {
        let id = UUID()
        let json = """
        {"object":"card","all_parts":[
        {"id":"\(id)","name":"Soldier","component":"token"},
        {"id":"\(id)","name":"Soldier","component":"token"},
        {"id":"\(UUID())","name":"Other","component":"combo_piece"}]}
        """
        XCTAssertEqual(try NativeTokenDiscovery.decode(Data(json.utf8)), [NativeTokenArtwork(id: id, name: "Soldier")])
        XCTAssertThrowsError(try NativeTokenDiscovery.decode(Data(#"{"object":"error"}"#.utf8)))
    }

    func testTokenMatchingRejectsAmbiguityAndDifferentVisibleRules() {
        let first = NativeTokenArtwork(id: UUID(), name: "Soldier", typeLine: "Token Creature — Soldier", oracleText: "Vigilance", power: "1", toughness: "1", colors: ["W"])
        let second = NativeTokenArtwork(id: UUID(), name: "Soldier", typeLine: "Token Creature — Soldier", oracleText: "Vigilance", power: "1", toughness: "1", colors: ["W"])
        XCTAssertEqual(NativeAssetStore.matchToken([first], name: "Soldier", typeLine: "Creature — Soldier", oracleText: "<i>Vigilance</i>", power: "1", toughness: "1", colors: ["W"]), first)
        XCTAssertNil(NativeAssetStore.matchToken([first, second], name: "Soldier", typeLine: "Creature — Soldier", oracleText: "Vigilance", power: "1", toughness: "1", colors: ["W"]))
        XCTAssertNil(NativeAssetStore.matchToken([first], name: "Soldier", typeLine: "Creature — Soldier", oracleText: "Flying", power: "1", toughness: "1", colors: ["W"]))
        XCTAssertNil(NativeAssetStore.matchToken([first], name: "Human", typeLine: "Creature — Soldier", oracleText: "Vigilance", power: "1", toughness: "1", colors: ["W"]))
        XCTAssertNil(NativeAssetStore.matchToken([first], name: "Soldier", typeLine: "Creature — Soldier", oracleText: "Vigilance", power: "2", toughness: "2", colors: ["W"]))
        XCTAssertNil(NativeAssetStore.matchToken([first], name: "Soldier", typeLine: "Creature — Soldier", oracleText: "Vigilance", power: "1", toughness: "1", colors: ["R"]))
        XCTAssertNil(NativeAssetStore.matchToken([first], name: "Soldier", typeLine: "Creature — Soldier", oracleText: "Vigilance", power: "1", toughness: "1", colors: nil))
        let treasure = NativeTokenArtwork(id: UUID(), name: "Treasure", typeLine: "Token Artifact — Treasure", oracleText: "Sacrifice this artifact.", colors: [])
        XCTAssertEqual(NativeAssetStore.matchToken([treasure], name: "Treasure", typeLine: "Artifact — Treasure", oracleText: "Sacrifice this artifact.", power: nil, toughness: nil, colors: []), treasure)
        XCTAssertFalse(NativeTokenArtwork(id: UUID(), name: "Soldier", typeLine: "Token Creature — Soldier", colors: ["W"]).hasMatchingMetadata)
        XCTAssertFalse(NativeTokenArtwork(id: UUID(), name: "Treasure", typeLine: "Token Artifact — Treasure", colors: ["purple"]).hasMatchingMetadata)
    }

    func testDurableImagesSurviveStoreRecreationAndScanRejectsMissingBytes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = NativeAssetStore.cardKey("Black Lotus")
        let data = try image()
        let store = NativeAssetStore(directory: directory)
        try await store.save(data, key: key)
        let reopened = NativeAssetStore(directory: directory)
        let restored = await reopened.image(key: key)
        XCTAssertEqual(restored, data)
        let file = await reopened.file(key: key)
        try Data("incomplete".utf8).write(to: file)
        let corrupt = await reopened.image(key: key)
        XCTAssertNil(corrupt)
    }

    func testCapacityFailurePreservesExistingImages() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = try image()
        let store = NativeAssetStore(directory: directory, capacity: data.count)
        try await store.save(data, key: "first")
        do { try await store.save(data, key: "second"); XCTFail("Should enforce disk cap") } catch {}
        let first = await store.image(key: "first")
        let second = await store.image(key: "second")
        XCTAssertEqual(first, data); XCTAssertNil(second)
    }

    @MainActor func testTokenCoverageRequiresValidMetadataAndBytes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NativeAssetStore(directory: directory)
        let token = NativeTokenArtwork(id: UUID(), name: "Soldier", typeLine: "Token Creature — Soldier", oracleText: "", power: "1", toughness: "1", colors: ["W"])
        try await store.saveRelations([NativeTokenArtwork(id: token.id, name: token.name)], name: "Creator")
        try await store.save(image(), key: NativeAssetStore.tokenKey(token.id))
        let model = NativeAssetDownloads(store: store)
        await model.scan(names: ["Creator"])
        XCTAssertEqual(model.tokenStored, 0)
        XCTAssertEqual(model.missingTokenNames, ["Soldier"])
        try await store.saveToken(token)
        await model.scan(names: ["Creator"])
        XCTAssertEqual(model.tokenStored, 1)
        XCTAssertEqual(model.missingTokenNames, [])
        let metadata = await store.file(key: NativeAssetStore.tokenKey(token.id), extension: "token")
        try Data("corrupt".utf8).write(to: metadata)
        await model.scan(names: ["Creator"])
        XCTAssertEqual(model.tokenStored, 0)
        XCTAssertEqual(model.missingTokenNames, ["Soldier"])
    }

    @MainActor func testScanIsOfflineAndConsentDenialDoesNotStartDownload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NativeAssetStore(directory: directory)
        let model = NativeAssetDownloads(store: store)
        await model.scan(names: ["Black Lotus", " Black Lotus "])
        XCTAssertEqual(model.cardTotal, 1); XCTAssertEqual(model.cardStored, 0)
        // The card's own relations and the deck's common/opponent tokens are both unknown.
        XCTAssertEqual(model.tokenDiscoveryRemaining, 2); XCTAssertEqual(model.missingNames, ["Black Lotus"])
        model.download(names: ["Black Lotus"], includeTokens: true, allowNetwork: false)
        XCTAssertFalse(model.isRunning)
        XCTAssertTrue(model.status.contains("Enable online artwork"))
        XCTAssertThrowsError(try NativeAssetDownloads.names(Array(repeating: "x", count: 1) + ["\n"]))
    }

    @MainActor func testCancellingTokenDiscoveryPreservesCompletedCardAndSendsNoNextRequest() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NativeAssetStore(directory: directory)
        try await store.save(image(), key: NativeAssetStore.cardKey("Black Lotus"))
        let transport = WaitingTransport()
        let model = NativeAssetDownloads(store: store, discovery: NativeTokenDiscovery(transport: transport))
        model.download(names: ["Black Lotus"], includeTokens: true, allowNetwork: true)
        for _ in 0..<150 {
            if await transport.calls > 0 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        model.cancel()
        for _ in 0..<100 {
            if !model.isRunning { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.cardStored, 1)
        XCTAssertEqual(model.tokenDiscoveryRemaining, 2, "Relations and the deck's extra tokens stay unknown")
        let calls = await transport.calls
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(model.status.contains("cancelled"))
    }

    func testRulesTextFindsTheTokensACardMakes() {
        typealias Request = NativeTokenRules.Request
        XCTAssertEqual(NativeTokenRules.requests(rules: "Forestwalk\nIf one or more tokens would be created under your control, those tokens plus that many 1/1 green Squirrel creature tokens are created instead.\n{B}, Sacrifice X Squirrels: Target creature gets +X/-X until end of turn."),
                       [Request(name: "Squirrel", power: "1", toughness: "1", colors: ["G"])], "Chatterfang makes Squirrels")
        XCTAssertEqual(NativeTokenRules.requests(rules: "When {this} enters, create a Food token.\n{1}{G}, {T}: Create a Food token.\n{T}, Sacrifice a Food: Add one mana of any color."),
                       [Request(name: "Food")])
        XCTAssertEqual(NativeTokenRules.requests(rules: "<i>Landfall</i> &mdash; Whenever a land you control enters, create a Food token or a Treasure token."),
                       [Request(name: "Food"), Request(name: "Treasure")])
        XCTAssertEqual(NativeTokenRules.requests(rules: "If you would create a Clue, Food, or Treasure token, instead create one of each."),
                       ["Clue", "Food", "Treasure"].map { Request(name: $0) })
        XCTAssertEqual(NativeTokenRules.requests(rules: "Create X X/X green Ooze creature tokens."), [Request(name: "Ooze", colors: ["G"])])
        XCTAssertEqual(NativeTokenRules.requests(rules: "create a 0/1 colorless Eldrazi Spawn creature token. It has \"Sacrifice this token: Add {C}.\""),
                       [Request(name: "Eldrazi Spawn", power: "0", toughness: "1", colors: [])])
        XCTAssertEqual(NativeTokenRules.requests(rules: "{1}{R}, {T}: Create a 0/1 red Kobold creature token named Kobolds of Kher Keep."),
                       [Request(name: "Kobolds of Kher Keep")])
        for reference in ["Populate <i>(Create a token that's a copy of a creature token you control.)</i>",
                          "Whenever a Zombie token you control attacks, it gains lifelink.",
                          "Creature tokens you control get +1/+1.", "Attacking tokens you control have deathtouch.",
                          "If one or more tokens would be created under your control, twice that many of those tokens are created instead."] {
            XCTAssertEqual(NativeTokenRules.requests(rules: reference), [], reference)
        }
        XCTAssertEqual(NativeTokenRules.commonTokenNames, ["Food", "Treasure", "Clue", "Blood", "Map", "Powerstone", "Incubator", "Junk", "Gold", "Shard"])
    }

    func testBundledCatalogueRulesTextFindsWhatDecksMake() async throws {
        let rules = await NativeAssetDownloads.bundledRulesText(names: ["Chatterfang, Squirrel General", "Tireless Provisioner", "Not A Card"])
        XCTAssertNil(rules["Not A Card"])
        XCTAssertEqual(NativeTokenRules.requests(rules: try XCTUnwrap(rules["Chatterfang, Squirrel General"])).map(\.name), ["Squirrel"])
        XCTAssertEqual(NativeTokenRules.requests(rules: try XCTUnwrap(rules["Tireless Provisioner"])).map(\.name), ["Food", "Treasure"])
    }

    func testTokenSelectionMatchesStatedStatsAndKeepsOnePrintingPerIdentity() throws {
        func token(_ id: Int, _ name: String, _ type: String, _ rules: String, _ power: String?, _ toughness: String?, _ colors: [String]) -> [String: Any] {
            var row: [String: Any] = ["id": String(format: "00000000-0000-0000-0000-%012d", id), "name": name, "layout": "token", "type_line": type,
                                      "oracle_text": rules, "colors": colors, "image_uris": ["normal": "https://cards.scryfall.io/normal/\(id).jpg"]]
            if let power, let toughness { row["power"] = power; row["toughness"] = toughness }
            return row
        }
        func face(_ name: String, _ type: String, _ rules: String, _ path: String, power: String? = nil) -> [String: Any] {
            var face: [String: Any] = ["name": name, "type_line": type, "oracle_text": rules, "colors": [String](),
                                       "image_uris": ["normal": "https://cards.scryfall.io/normal/\(path).jpg"]]
            if let power { face["power"] = power; face["toughness"] = power }
            return face
        }
        let rows: [[String: Any]] = [
            token(2, "Squirrel", "Token Creature — Squirrel", "", "1", "1", ["G"]),
            token(1, "Squirrel", "Token Creature — Squirrel", "", "1", "1", ["G"]),
            token(3, "Squirrel", "Token Creature — Squirrel", "", "2", "2", ["G"]),
            token(4, "Treasure", "Token Artifact — Treasure", "{T}, Sacrifice this token: Add one mana of any color.", nil, nil, []),
            ["id": "00000000-0000-0000-0000-000000000005", "name": "Dinosaur // Treasure", "layout": "double_faced_token", "card_faces": [
                face("Dinosaur", "Token Creature — Dinosaur", "Trample", "dinosaur"),
                face("Treasure", "Token Artifact — Treasure", "{T}, Sacrifice this artifact: Add one mana of any color.", "treasure-back")]],
            ["id": "00000000-0000-0000-0000-000000000006", "name": "Incubator // Phyrexian", "layout": "double_faced_token", "card_faces": [
                face("Incubator", "Token Artifact — Incubator", "{2}: Transform this artifact.", "incubator"),
                face("Phyrexian", "Token Artifact Creature — Phyrexian", "", "phyrexian", power: "0")]],
            ["id": "00000000-0000-0000-0000-000000000007", "name": "Clue // Clue", "layout": "double_faced_token", "card_faces": [
                face("Clue", "Token Artifact — Clue", "{2}, Sacrifice this artifact: Draw a card.", "clue"),
                face("Clue", "Token", "", "clue-back")]],
        ]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("tokens.json")
        try JSONSerialization.data(withJSONObject: rows).write(to: file)
        let catalogue = try NativeArtworkCatalogue.parse(file: file)
        func id(_ value: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))! }
        let selected = NativeTokenRules.select([.init(name: "Squirrel", power: "1", toughness: "1", colors: ["G"]),
                                                .init(name: "Treasure"), .init(name: "Incubator"), .init(name: "Clue")], from: catalogue)
        XCTAssertEqual(selected.map(\.artworkKey), [NativeAssetStore.tokenKey(id(1)), NativeAssetStore.tokenKey(id(4)),
                                                    NativeAssetStore.tokenKey(id(6)), NativeAssetStore.tokenKey(id(6), face: "back"),
                                                    NativeAssetStore.tokenKey(id(7))],
                       "Stated 1/1 green excludes the 2/2; equivalent printings and the Treasure back face collapse; the Incubator brings its Phyrexian; a bare 'Token' face is skipped")
        XCTAssertEqual(NativeTokenRules.select([.init(name: "Squirrel")], from: catalogue).count, 2, "Without stated stats every Squirrel identity is kept")
    }

    func testBatchedTokenSearchSendsTenExactNamesPerQueryAndFollowsPages() async throws {
        let transport = TokenBatchFixture()
        let names = (0..<12).map { "Name\($0)" } + ["Bad\" Name", "Name0 Token"]
        let catalogue = try await NativeArtworkCatalogue.searchTokens(names: names, transport: transport, budget: DeckStudioScryfallBudget())
        let queries = await transport.queries
        XCTAssertEqual(queries.map(\.q), ["t:token (" + (0..<10).map { "!\"Name\($0)\"" }.joined(separator: " or ") + ")",
                                          "t:token (!\"Name10\" or !\"Name11\")", "t:token (!\"Name10\" or !\"Name11\")"])
        XCTAssertEqual(queries.map(\.page), ["1", "1", "2"], "The second batch reads its next page")
        XCTAssertEqual(Set(catalogue.allTokens.map(\.name)), ["Food", "Treasure"])
        let empty = try await NativeArtworkCatalogue.searchTokens(names: ["Missing"], transport: TokenBatchFixture(notFound: true), budget: DeckStudioScryfallBudget())
        XCTAssertTrue(empty.allTokens.isEmpty, "No match is an empty result, not an error")
    }

    @MainActor func testDeckDownloadQueuesTokensFirstAndCountsCommonRulesTextAndOpponentTokens() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let maker = "Fixture Squirrel Maker \(UUID())"
        func images(_ path: String) -> [String: String] { ["normal": "https://cards.scryfall.io/normal/\(path).jpg"] }
        func token(_ id: Int, _ name: String, _ type: String, _ power: String?, _ colors: [String]) -> [String: Any] {
            var row: [String: Any] = ["id": String(format: "00000000-0000-0000-0000-%012d", id), "name": name, "layout": "token",
                                      "type_line": type, "oracle_text": "", "colors": colors, "image_uris": images("token-\(id)")]
            if let power { row["power"] = power; row["toughness"] = power }
            return row
        }
        let deckFile = directory.appendingPathComponent("deck.json"), tokenFile = directory.appendingPathComponent("tokens.json")
        try JSONSerialization.data(withJSONObject: [["id": UUID().uuidString, "name": maker, "layout": "normal", "type_line": "Creature",
                                                     "image_uris": images("maker")]]).write(to: deckFile)
        try JSONSerialization.data(withJSONObject: [
            token(1, "Squirrel", "Token Creature — Squirrel", "1", ["G"]), token(2, "Squirrel", "Token Creature — Squirrel", "2", ["G"]),
            token(3, "Food", "Token Artifact — Food", nil, []), token(4, "Treasure", "Token Artifact — Treasure", nil, []),
            token(5, "Zombie", "Token Creature — Zombie", "2", ["B"])]).write(to: tokenFile)
        let bytes = try image(width: 488, height: 680)
        DownloadImageFixtureProtocol.configure(data: bytes)
        defer { DownloadImageFixtureProtocol.configure(data: Data()) }
        let store = NativeAssetStore(directory: directory.appendingPathComponent("images"), availableBytes: { _ in Int64.max })
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DownloadImageFixtureProtocol.self]
        let queue = NativeArtworkBackgroundQueue(directory: directory.appendingPathComponent("queue"), store: store,
                                                configuration: configuration, allowNetwork: { true })
        let searched = SearchedNames()
        var opponents = [NativeAssetDownloads.OpponentDeck(id: "fixture-opponent", cardNames: ["Opponent Zombie Maker"])]
        let model = NativeAssetDownloads(store: store, backgroundQueue: queue,
            deckCatalogueLoader: { _, _ in try NativeArtworkCatalogue.parse(file: deckFile) },
            tokenSearch: { names in await searched.record(names); return try NativeArtworkCatalogue.parse(file: tokenFile) },
            rulesText: { _ in [maker: "If one or more tokens would be created under your control, those tokens plus that many 1/1 green Squirrel creature tokens are created instead.",
                               "Opponent Zombie Maker": "When {this} dies, create a 2/2 black Zombie creature token."] },
            opponentDecks: { opponents })
        model.download(names: [maker], includeTokens: true, allowNetwork: true, quality: .standard)
        try await settle(model)
        XCTAssertEqual(model.failures, [])
        let names = await searched.names
        XCTAssertEqual(names, ["Squirrel"] + NativeTokenRules.commonTokenNames + ["Zombie"], "One batched search covers the deck, the common list and the opponent")
        let keys = try queuedKeys(directory.appendingPathComponent("queue"))
        XCTAssertEqual(keys, ["token:00000000-0000-0000-0000-000000000001", "token:00000000-0000-0000-0000-000000000003",
                              "token:00000000-0000-0000-0000-000000000004", "token:00000000-0000-0000-0000-000000000005",
                              NativeAssetStore.cardKey(maker)], "Stated 1/1 Squirrel only; tokens before the card")
        let related = await store.relations(name: maker)
        XCTAssertEqual(related?.map(\.name), ["Squirrel"], "Rules-text tokens are recorded with the card's relations")
        let extras = await store.extraTokens(key: NativeAssetDownloads.extraTokenKey(opponents))
        XCTAssertEqual(extras?.map(\.name), ["Food", "Treasure", "Zombie"])
        await model.scan(names: [maker], quality: .standard)
        XCTAssertEqual(model.tokenDiscoveryRemaining, 0)
        XCTAssertEqual(model.tokenTotal, 4); XCTAssertEqual(model.tokenStored, 4); XCTAssertEqual(model.cardStored, 1)
        let squirrel = await store.tokenImage(name: "Squirrel Token", typeLine: "Creature — Squirrel", oracleText: "Forestwalk",
                                              power: "1", toughness: "1", colors: ["G"], quality: .standard, offlineFallback: true)
        XCTAssertEqual(squirrel, bytes, "The downloaded Squirrel shows offline")
        opponents = [NativeAssetDownloads.OpponentDeck(id: "another-opponent", cardNames: [])]
        await model.scan(names: [maker], quality: .standard)
        XCTAssertEqual(model.tokenDiscoveryRemaining, 1, "Different opponents need checking again")
    }

    private func queuedKeys(_ queueDirectory: URL) throws -> [String] {
        struct Job: Decodable { struct Entry: Decodable { let key: String }; let entries: [Entry] }
        return try JSONDecoder().decode(Job.self, from: Data(contentsOf: queueDirectory.appendingPathComponent("job.json"))).entries.map(\.key)
    }

    private func image(width: Int = 672, height: Int = 936) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }
}

private actor SearchedNames {
    private(set) var names: [String] = []
    func record(_ value: [String]) { names += value }
}

/// Scryfall token search pages: the first batch has one page, the second two.
private actor TokenBatchFixture: DeckStudioScryfallHTTP {
    private(set) var queries: [(q: String, page: String)] = []
    private let notFound: Bool
    init(notFound: Bool = false) { self.notFound = notFound }
    func send(_ request: URLRequest) async throws -> Data {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let q = items.first { $0.name == "q" }?.value ?? "", page = items.first { $0.name == "page" }?.value ?? ""
        queries.append((q, page))
        if notFound { throw DeckStudioScryfallError.http(404) }
        func token(_ id: Int, _ name: String) -> [String: Any] {
            ["id": String(format: "00000000-0000-0000-0000-%012d", id), "name": name, "layout": "token",
             "type_line": "Token Artifact — \(name)", "oracle_text": "", "colors": [String](),
             "image_uris": ["normal": "https://cards.scryfall.io/normal/\(id).jpg"]]
        }
        let first = q.contains("Name0")
        let rows = first ? [token(1, "Food")] : (page == "1" ? [token(2, "Treasure")] : [])
        return try JSONSerialization.data(withJSONObject: ["object": "list", "has_more": !first && page == "1", "data": rows])
    }
}

private actor WaitingTransport: DeckStudioScryfallHTTP {
    private(set) var calls = 0
    func send(_ request: URLRequest) async throws -> Data {
        calls += 1
        try await Task.sleep(for: .seconds(10))
        return Data(#"{"object":"card"}"#.utf8)
    }
}

private final class DownloadImageFixtureProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var bytes = Data()
    private static var requests: [URL] = []
    static var urls: [URL] { lock.lock(); defer { lock.unlock() }; return requests }
    static func configure(data: Data) { lock.lock(); defer { lock.unlock() }; bytes = data; requests = [] }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        Self.lock.lock(); Self.requests.append(url); let data = Self.bytes; Self.lock.unlock()
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/png", "Content-Length": String(data.count)])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
