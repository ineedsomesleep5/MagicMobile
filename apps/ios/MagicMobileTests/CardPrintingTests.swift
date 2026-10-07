import Foundation
import XCTest
@testable import MagicMobile

/// The chosen printing of a deck row: validation, how it is saved, exported and imported again.
/// Android's CardPrintingTest follows the same cases.
final class CardPrintingTests: XCTestCase {
    private let solRing = CardPrinting(set: "CMM", number: "400")!

    func testSetCodeAndCollectorNumberAreValidatedAndNormalized() throws {
        XCTAssertEqual(solRing.setCode, "cmm")
        XCTAssertEqual(solRing.key, "cmm/400")
        XCTAssertEqual(solRing.exportSuffix, "(CMM) 400")
        XCTAssertEqual(solRing.label, "CMM 400")
        for number in ["107m", "★1", "A-12", "123†", "1"] { XCTAssertNotNil(CardPrinting(set: "plst", number: number), number) }
        for (set, number) in [("c", "1"), ("toolong1", "1"), ("cmm", ""), ("cmm", "1/2"), ("cm m", "1"), ("cmm", "1?x=1"),
                              ("cmm", "../1"), ("é", "1"), ("cmm", String(repeating: "1", count: 17))] {
            XCTAssertNil(CardPrinting(set: set, number: number), "\(set) \(number)")
        }
    }

    func testDeckListSuffixParsesOnlyWhenItNamesOnePrinting() {
        XCTAssertEqual(CardPrinting.parse(suffix: "(CMM) 400"), solRing)
        XCTAssertEqual(CardPrinting.parse(suffix: " (cmm) 400 "), solRing)
        XCTAssertNil(CardPrinting.parse(suffix: "(clb)"), "a set code alone does not pick a printing")
        XCTAssertNil(CardPrinting.parse(suffix: "CMM 400"))
        XCTAssertEqual(CardPrinting.parse(suffix: "(SLD) 1234★")?.number, "1234★")
    }

    func testImageURLRequestsExactlyThisPrintingAndEncodesThePath() throws {
        let url = try XCTUnwrap(solRing.imageURL(version: "normal"))
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.host, "api.scryfall.com")
        XCTAssertEqual(parts.path, "/cards/cmm/400")
        XCTAssertEqual(parts.queryItems, [.init(name: "format", value: "image"), .init(name: "version", value: "normal")])
        let star = try XCTUnwrap(CardPrinting(set: "sld", number: "★1")?.imageURL(version: "large", back: true))
        XCTAssertEqual(URLComponents(url: star, resolvingAgainstBaseURL: false)?.percentEncodedPath, "/cards/sld/%E2%98%851")
        XCTAssertTrue(star.absoluteString.hasSuffix("&face=back"))
        XCTAssertTrue(NativeDeckArtwork.isAllowed(url))
    }

    func testSavedDeckEntryKeepsTheChoiceAsSetCodeAndCollectorNumber() throws {
        let entry = DeckEntry(cardName: "Sol Ring", quantity: 1, section: "deck", printing: solRing)
        let data = try JSONEncoder().encode(entry)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["setCode"] as? String, "cmm")
        XCTAssertEqual(object["collectorNumber"] as? String, "400")
        XCTAssertEqual(try JSONDecoder().decode(DeckEntry.self, from: data), entry)
        let library = JSONDecoder(); library.keyDecodingStrategy = .convertFromSnakeCase // as the deck library decodes
        XCTAssertEqual(try library.decode(DeckEntry.self, from: data), entry)
        // A row with no choice saves exactly the three fields it always had.
        let plain = try JSONSerialization.jsonObject(with: JSONEncoder().encode(DeckEntry(cardName: "Forest", quantity: 3, section: "deck"))) as? [String: Any]
        XCTAssertEqual(Set(plain?.keys.map { $0 } ?? []), ["cardName", "quantity", "section"])
    }

    func testDecksSavedBeforeArtChoicesAndDamagedChoicesStillLoad() throws {
        let old = Data(#"{"cardName":"Forest","quantity":2,"section":"deck"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(DeckEntry.self, from: old).printing)
        for damaged in [",\"setCode\":\"cmm\"", ",\"setCode\":\"cmm\",\"collectorNumber\":\"\"", ",\"setCode\":\"x\",\"collectorNumber\":\"1\"",
                        ",\"setCode\":\"cmm\",\"collectorNumber\":\"../1\"", ",\"collectorNumber\":\"1\""] {
            let entry = try JSONDecoder().decode(DeckEntry.self, from: Data(("{\"cardName\":\"Forest\",\"quantity\":2,\"section\":\"deck\"" + damaged + "}").utf8))
            XCTAssertNil(entry.printing, damaged)
            XCTAssertEqual(entry.cardName, "Forest")
        }
    }

    func testEntriesWithTheSameNameButDifferentArtStayDistinctRows() {
        let one = DeckEntry(cardName: "Forest", quantity: 1, section: "deck", printing: CardPrinting(set: "unf", number: "1"))
        let two = DeckEntry(cardName: "Forest", quantity: 1, section: "deck", printing: CardPrinting(set: "unf", number: "2"))
        XCTAssertNotEqual(one.id, two.id)
        XCTAssertNotEqual(one.id, DeckEntry(cardName: "Forest", quantity: 1, section: "deck").id)
    }

    func testPlainTextExportWritesChosenPrintingsAndImportRestoresThem() throws {
        let deck = DeckList(name: "Art", commander: DeckEntry(cardName: "Atraxa, Praetors' Voice", quantity: 1, section: "commanders",
                                                              printing: CardPrinting(set: "c16", number: "28")),
                            entries: [DeckEntry(cardName: "Sol Ring", quantity: 1, section: "deck", printing: solRing),
                                      DeckEntry(cardName: "Forest", quantity: 20, section: "deck"),
                                      DeckEntry(cardName: "Swords to Plowshares", quantity: 1, section: "sideboard",
                                                printing: CardPrinting(set: "sld", number: "★12"))])
        let text = try DeckStudioTextExport.text(deck)
        XCTAssertEqual(text, """
        Commander
        1 Atraxa, Praetors' Voice (C16) 28

        Deck
        1 Sol Ring (CMM) 400
        20 Forest

        Sideboard
        1 Swords to Plowshares (SLD) ★12

        """)
        let back = try OnDeviceDeckEditing.importText(text, name: "Art").deck
        XCTAssertEqual(back.commander?.printing, CardPrinting(set: "c16", number: "28"))
        XCTAssertEqual(back.entries.map(\.printing), [solRing, nil, CardPrinting(set: "sld", number: "★12")])
        XCTAssertEqual(back.entries.map(\.cardName), ["Sol Ring", "Forest", "Swords to Plowshares"])
        XCTAssertEqual(back.entries.map(\.quantity), [1, 20, 1])
    }

    func testProviderExportsKeepTheirPrintingsWhileTheReviewStillListsTheSuffix() throws {
        // Moxfield and Archidekt both write "(set) number"; a set code alone picks nothing.
        let result = try OnDeviceDeckEditing.importText("""
        1x Sol Ring (cmm) 400 [Ramp]
        1 Arcane Signet (CMM) 384 *F*
        2 Rampant Growth (9ED) 263
        1x Emmara, Soul of the Accord (grn) [Maybeboard]
        """, name: "Providers")
        XCTAssertEqual(result.deck.entries.map(\.printing), [solRing, CardPrinting(set: "cmm", number: "384"),
                                                              CardPrinting(set: "9ed", number: "263"), nil])
        XCTAssertTrue(result.annotations.contains(.init(line: 3, text: "(9ED) 263")))
        XCTAssertTrue(result.annotations.contains(.init(line: 4, text: "(grn)")))
    }

    func testNativeJSONExportRoundTripsPrintings() throws {
        let deck = DeckList(name: "Json", commander: nil, entries: [DeckEntry(cardName: "Sol Ring", quantity: 1, section: "deck", printing: solRing)])
        let data = try OnDeviceDeckEditing(deck).exportJSON()
        XCTAssertEqual(try OnDeviceDeckEditing.importJSON(data).deckList, deck)
    }

    func testDraftRowsCarryTheChoiceThroughEditingSavingAndRecovery() throws {
        var draft = NativeDeckDraft(deck: DeckList(name: "Rows", commander: DeckEntry(cardName: "Atraxa", quantity: 1, section: "commanders", printing: solRing),
                                                   entries: [DeckEntry(cardName: "Sol Ring", quantity: 1, section: "deck", printing: solRing)]))
        XCTAssertEqual(draft.rows.map(\.printing), [solRing, solRing])
        XCTAssertEqual(try draft.deck().entries.first?.printing, solRing)
        XCTAssertEqual(try draft.deck().commander?.printing, solRing)
        let recovered = try JSONDecoder().decode(NativeDeckDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(recovered, draft)
        // More copies of the same card keep its art.
        try DeckStudioEditorOperations.add(in: &draft, name: "Sol Ring", quantity: 2, section: "deck")
        XCTAssertEqual(draft.rows.last?.quantity, 3)
        XCTAssertEqual(draft.rows.last?.printing, solRing)
        // A drafted deck from before art choices still decodes.
        let id = UUID().uuidString
        let old = Data(#"{"name":"Old","rows":[{"id":"\#(id)","cardName":"Forest","quantity":1,"section":"deck","isPrimaryCommander":false}]}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(NativeDeckDraft.self, from: old).rows.first?.printing)
    }

    func testReplacingACardClearsTheChoiceThatBelongedToTheOldOne() throws {
        var draft = NativeDeckDraft(deck: DeckList(name: "Replace", commander: nil,
                                                   entries: [DeckEntry(cardName: "Sol Ring", quantity: 1, section: "deck", printing: solRing)]))
        let id = draft.rows[0].id
        try DeckStudioEditorOperations.replaceCard(in: &draft, rowID: id, name: "Arcane Signet")
        XCTAssertEqual(draft.rows[0].cardName, "Arcane Signet")
        XCTAssertNil(draft.rows[0].printing)
    }

    func testTextEditReportsAChangedPrintingAsAnArtChange() throws {
        let draft = NativeDeckDraft(deck: DeckList(name: "Diff", commander: nil, entries: [
            DeckEntry(cardName: "Sol Ring", quantity: 1, section: "deck", printing: solRing),
            DeckEntry(cardName: "Forest", quantity: 2, section: "deck")]))
        let exported = try DeckStudioTextExport.text(draft.deck())
        XCTAssertTrue(DeckStudioTextDiff(from: draft, to: try DeckStudioTextDiff.draft(from: exported, replacing: draft).draft).isEmpty)
        let edited = exported.replacingOccurrences(of: "Sol Ring (CMM) 400", with: "Sol Ring (C21) 263")
            .replacingOccurrences(of: "2 Forest", with: "2 Forest (UNF) 5")
        let result = try DeckStudioTextDiff.draft(from: edited, replacing: draft)
        let diff = DeckStudioTextDiff(from: draft, to: result.draft)
        XCTAssertFalse(diff.isEmpty)
        XCTAssertTrue(diff.added.isEmpty && diff.removed.isEmpty)
        XCTAssertEqual(diff.art.map(\.label), ["Forest · default art → UNF 5", "Sol Ring · CMM 400 → C21 263"])
        // The applied draft keeps the rows' identities and the new art.
        XCTAssertEqual(result.draft.rows.map(\.id), draft.rows.map(\.id))
        XCTAssertEqual(result.draft.rows.map(\.printing), [CardPrinting(set: "c21", number: "263"), CardPrinting(set: "unf", number: "5")])
        // Deleting the suffix returns the card to its default art.
        let cleared = try DeckStudioTextDiff.draft(from: exported.replacingOccurrences(of: " (CMM) 400", with: ""), replacing: draft)
        XCTAssertEqual(DeckStudioTextDiff(from: draft, to: cleared.draft).art.map(\.label), ["Sol Ring · CMM 400 → default art"])
    }
}
