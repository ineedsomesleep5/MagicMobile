import XCTest
@testable import MagicMobile

final class GameLogPresentationTests: XCTestCase {
    private let id = "d80199fe-06bb-486b-b9f7-a3d4a685bdd5"

    func testRulesSymbolsPreserveTextAndSpeakManaAndActions() {
        let source = "Pay {2}{C}{W/U}{B/P}{2/R}{G/U/P}, {T}: Add {X}.\n{Q} then {S}."
        let symbols = GameRulesSymbols(GameRulesPresentation(source: source))
        XCTAssertEqual(symbols.fragments.map(\.literal).joined(), source)
        XCTAssertEqual(symbols.fragments.compactMap(\.code), ["2", "C", "W/U", "B/P", "2/R", "G/U/P", "T", "X", "Q", "S"])
        XCTAssertEqual(symbols.accessibilityText,
                       "Pay 2 generic mana colorless mana white or blue mana black mana or two life two generic or red mana green or blue mana or two life , tap : Add X generic mana .\n untap then snow mana .")
    }

    func testRulesSymbolsRecognizeAllBasicColorsAndBoundedGenericValues() {
        let symbols = GameRulesSymbols(GameRulesPresentation(source: "{W}{U}{B}{R}{G}{C}{0}{16}{999}{Y}{Z}"))
        XCTAssertEqual(symbols.fragments.compactMap(\.code), ["W", "U", "B", "R", "G", "C", "0", "16", "999", "Y", "Z"])
        XCTAssertEqual(symbols.fragments.compactMap(\.spoken), ["white mana", "blue mana", "black mana", "red mana", "green mana", "colorless mana", "0 generic mana", "16 generic mana", "999 generic mana", "Y generic mana", "Z generic mana"])
    }

    func testRulesSymbolsKeepUnknownMalformedAndOverlongTokensLiteral() {
        let source = "{CHAOS} {W/W} {P} {W//U} {1234} {abcdefghijklmnop} {oops {T} {u}"
        let symbols = GameRulesSymbols(GameRulesPresentation(source: source))
        XCTAssertEqual(symbols.fragments.map(\.literal).joined(), source)
        XCTAssertEqual(symbols.fragments.compactMap(\.code), ["T", "U"])
        XCTAssertTrue(symbols.accessibilityText.hasPrefix("{CHAOS} {W/W} {P} {W//U} {1234}"))
        XCTAssertTrue(symbols.accessibilityText.hasSuffix("{oops tap blue mana"))
    }

    func testRulesSymbolsOnlyReadNormalizedVisibleText() {
        let source = "&lt;script&gt;Secret {B}&lt;/script&gt;<img alt='{C}' src='https://private.invalid'> {T} {this}"
        let visible = GameRulesSymbols(GameRulesPresentation(source: source, cardName: "Test card"))
        XCTAssertEqual(visible.fragments.compactMap(\.code), ["C", "T"])
        XCTAssertEqual(visible.accessibilityText, "colorless mana tap Test card")
        let hidden = GameRulesSymbols(GameRulesPresentation(source: source, cardName: "Secret", isHidden: true))
        XCTAssertTrue(hidden.fragments.isEmpty)
        XCTAssertEqual(hidden.accessibilityText, "")
        XCTAssertFalse(visible.accessibilityText.contains("private"))
    }

    func testRulesSymbolWorkIsBoundedWithoutDroppingVisibleText() {
        let source = String(repeating: "{C}", count: GameRulesSymbols.maximumSymbols + 10)
        let symbols = GameRulesSymbols(GameRulesPresentation(source: source))
        XCTAssertEqual(symbols.fragments.compactMap(\.code).count, GameRulesSymbols.maximumSymbols)
        XCTAssertEqual(symbols.fragments.map(\.literal).joined(), source)
        XCTAssertEqual(symbols.fragments.last?.literal, String(repeating: "{C}", count: 10))
        let oversized = GameRulesSymbols(GameRulesPresentation(source: String(repeating: "{T}", count: GameRulesPresentation.maximumBytes)))
        XCTAssertEqual(oversized.accessibilityText, GameRulesPresentation.unavailableText)
        XCTAssertTrue(oversized.fragments.compactMap(\.code).isEmpty)
    }

    func testStackRulesUseSourceIdentityAndNormalizeEncodedMarkup() {
        let rules = "&lt;b&gt;{this}&lt;/b&gt; deals 1 damage.<br>Pay <img alt='{R}' src='ignored'>."
        XCTAssertEqual(GameRulesPresentation(source: rules, cardName: "Prodigal Pyromancer").plainText,
                       "Prodigal Pyromancer deals 1 damage.\nPay {R}.")
        XCTAssertEqual(GameRulesPresentation(source: rules, cardName: "Private source", isHidden: true).plainText, "")
    }

    func testPublicLogReferenceCanResolveBundledRulesWithoutChangingHistoricalIdentity() throws {
        let presentation = GameLogPresentation("<font object_id='\(id)'>Sol Ring</font> was sacrificed.")
        let reference = try XCTUnwrap(presentation.spans.compactMap(\.cardReference).first)
        let catalogue = try NativeDeckMetadataCatalogue.bundled()
        let printed = try XCTUnwrap(catalogue.card(named: reference.name))
        XCTAssertEqual(reference.objectID, UUID(uuidString: id))
        XCTAssertEqual(reference.name, "Sol Ring")
        XCTAssertEqual(printed.name, reference.name)
        let rules = try XCTUnwrap(printed.oracleText)
        XCTAssertFalse(GameRulesPresentation(source: rules, cardName: reference.name).plainText.isEmpty)
        XCTAssertNotNil(printed.manaCost)
        XCTAssertNil(catalogue.card(named: "Not a real catalogue card"))
        // Redacted log labels authorize no reference, even though a UUID exists.
        for name in ["Hidden card", "Face-down card", "Card details unavailable"] {
            XCTAssertTrue(GameLogPresentation("<font object_id='\(id)'>\(name)</font>")
                .spans.compactMap(\.cardReference).isEmpty)
        }
    }

    func testEngineMessageKeepsActionsAndStylesNames() {
        let source = "<font color='White'><font color='#20B2AA'>Alice</font> casts <font color='#F0E68C' object_id='\(id)'>Isamaru, Hound of Konda</font> [d80] from hand.</font>"
        let value = GameLogPresentation(source)
        XCTAssertEqual(value.plainText, "Alice casts Isamaru, Hound of Konda from hand.")
        XCTAssertEqual(value.spans.filter { $0.role == .player }.map(\.text), ["Alice"])
        XCTAssertEqual(value.spans.filter { $0.role == .card }.map(\.text), ["Isamaru, Hound of Konda"])
        XCTAssertEqual(value.spans.filter { $0.role == .action }.map(\.text).joined(), " casts  from hand.")
    }

    func testNestedEmphasisRestoresOuterStyle() {
        let value = GameLogPresentation("<b>A <i>B</i> C</b> D")
        XCTAssertEqual(value.plainText, "A B C D")
        XCTAssertEqual(value.spans.map(\.bold), [true, true, true, false])
        XCTAssertEqual(value.spans.map(\.italic), [false, true, false, false])
    }

    func testAllKnownCardColorsAreSemanticAndUnknownColorDoesNotHideActions() {
        for color in ["#90EE90", "#FF6347", "#87CEFA", "#696969", "#F0E68C", "#DAA520", "#B0C4DE"] {
            XCTAssertEqual(GameLogPresentation("<font color='\(color)'>Card</font>").spans.first?.role, .card)
        }
        XCTAssertEqual(GameLogPresentation("<font color=black>draws a card</font>").spans.first?.role, .action)
    }

    func testOnlyMatchingAttachedUUIDSuffixIsRemoved() {
        let card = "<font object_id='\(id)'>Card</font>"
        XCTAssertEqual(GameLogPresentation(card + " [D80], then attacks.").plainText, "Card, then attacks.")
        XCTAssertEqual(GameLogPresentation(card + "&nbsp;&#91;d80&#93; attacks.").plainText, "Card attacks.")
        for suffix in [" [abc]", " [d801]", " [flying]", " [2 damage]", " [d80]x", " attacks [d80]", "\n[d80]"] {
            XCTAssertEqual(GameLogPresentation(card + suffix).plainText, "Card" + suffix)
        }
        XCTAssertEqual(GameLogPresentation("Card [d80] [flying] {W}").plainText, "Card [d80] [flying] {W}")
        XCTAssertEqual(GameLogPresentation("<font color='#B0C4DE'>Card</font> [d80]").plainText, "Card [d80]")
    }

    func testIdentifierOnlyLabelAndEmptyCardCannotDisappear() {
        for label in ["[d80]", ""] {
            XCTAssertEqual(GameLogPresentation("<font object_id='\(id)'>\(label)</font> [d80]").plainText, label + " [d80]")
        }
    }

    func testQuotedGreaterThanAndDuplicateAttributes() {
        let source = "<FONT title='not > content' COLOR=#20B2AA>Alice</FONT> plays <font object_id=\(id)><b>Card</b></font> [d80]."
        XCTAssertEqual(GameLogPresentation(source).plainText, "Alice plays Card.")
        let duplicate = "<font object_id='\(id)' object_id='\(id)' alternative_name='Secret'>Card</font> [d80]"
        XCTAssertEqual(GameLogPresentation(duplicate).plainText, "Card [d80]")
        XCTAssertEqual(GameLogPresentation("<font object_id='invalid'>Card</font> [d80]").plainText, "Card [d80]")
    }

    func testEntitiesUnicodeAndWhitespace() {
        let value = GameLogPresentation("A&amp;B&nbsp;&#x1F0CF; &#8212; &#123;T&#125;\nnext&#9;step &unknown; &#xD800; &#99999999999;")
        XCTAssertEqual(value.plainText, "A&B 🃏 — {T}\nnext\tstep &unknown; &#xD800; &#99999999999;")
        XCTAssertEqual(GameLogPresentation("A&#0;&#x202E;&#x2066;B").plainText, "AB")
    }

    func testEncodedMarkupRemainsLiteralAndIsNeverReparsed() {
        XCTAssertEqual(GameLogPresentation("&lt;b&gt;literal&lt;/b&gt; &amp;lt;i&amp;gt;").plainText,
                       "<b>literal</b> &lt;i&gt;")
    }

    func testLiteralControlsFollowEntityPolicyWithoutChangingReadableUnicode() {
        let controls = (Array(0...31).filter { ![9, 10, 13].contains($0) }
                        + Array(127...159) + Array(0x202A...0x202E) + Array(0x2066...0x2069))
            .compactMap(UnicodeScalar.init).map(String.init).joined()
        let visible = "Alice\tcasts\nカード\rالعربية 👩‍👩‍👧‍👦 e\u{301} [flying]"
        XCTAssertEqual(GameLogPresentation(controls + visible + controls).plainText, visible)
        XCTAssertEqual(GameLogPresentation("<scr\u{0}ipt>hidden</scr\u{0}ipt>Alice draws").plainText, "Alice draws")
        XCTAssertEqual(GameLogPresentation("<font object_\u{7}id='\(id)'>Card</font> [d80]").plainText, "Card")
    }

    func testNestedHiddenRegionsNeverLeakContentsOrStyles() {
        let source = "<b>Alice</b><object>hidden<object><font color='#20B2AA'><i>secret</i></font>&amp;hidden</object>still hidden</object> draws."
        let value = GameLogPresentation(source)
        XCTAssertEqual(value.plainText, "Alice draws.")
        XCTAssertEqual(value.spans.map(\.bold), [true, false])
        XCTAssertEqual(value.spans.map(\.italic), [false, false])
        XCTAssertEqual(value.spans.map(\.role), [.action, .action])
    }

    func testHiddenAncestorCloseRecoversAfterMismatchedNesting() {
        XCTAssertEqual(GameLogPresentation("Alice<object><svg>hidden</object> draws</svg>.").plainText,
                       "Alice draws.")
        XCTAssertEqual(GameLogPresentation("Alice<script>const s = '<style>';</script> draws.").plainText,
                       "Alice draws.")
        XCTAssertEqual(GameLogPresentation("Alice<object>hidden</script>still hidden</object> draws.").plainText,
                       "Alice draws.")
        XCTAssertEqual(GameLogPresentation("Alice<object><svg>unclosed hidden").plainText, "Alice")
    }

    func testSelfClosingSyntaxCannotExposeHTMLContainerContents() {
        for name in ["script", "style", "iframe", "object", "head", "template"] {
            XCTAssertEqual(GameLogPresentation("Alice<\(name)/>hidden</\(name)> draws.").plainText, "Alice draws.")
        }
        XCTAssertEqual(GameLogPresentation("Alice<svg/><math/> draws.").plainText, "Alice draws.")
    }

    func testUnsupportedHTMLHasNoExecutionOrAttributeDerivedContent() {
        let source = "Alice<script>private script</script><style>private style</style><!--private comment--> plays <a href='https://example.invalid'>Card</a><br><img alt='{W}' src='private'><img alt='hidden card name'> [flying]"
        XCTAssertEqual(GameLogPresentation(source).plainText, "Alice plays Card\n{W} [flying]")
        XCTAssertEqual(GameLogPresentation("before<script>unclosed payload").plainText, "before")
    }

    func testNestedCardsAndPopupWrappersRestorePlayerRole() {
        let source = "<font color='#20B2AA'>Alice <a href='ignored'><font object_id='\(id)'><i>Card</i></font></a> [d80] chooses</font> [option 2]"
        let value = GameLogPresentation(source)
        XCTAssertEqual(value.plainText, "Alice Card chooses [option 2]")
        XCTAssertEqual(value.spans.map(\.role), [.player, .card, .player, .action])
        XCTAssertEqual(value.spans.map(\.italic), [false, true, false, false])
    }

    func testMalformedAndPlainTextRemainReadable() {
        XCTAssertEqual(GameLogPresentation("2 < 3; 5 > 4 [choice] **not Markdown**").plainText,
                       "2 < 3; 5 > 4 [choice] **not Markdown**")
        XCTAssertEqual(GameLogPresentation("<b>draw <i>one</b> card</i>").plainText, "draw one card")
        XCTAssertEqual(GameLogPresentation("</font>Alice draws <b>one").plainText, "Alice draws one")
        XCTAssertEqual(GameLogPresentation("Alice draws <font object_id='private-attribute").plainText, "Alice draws ")
        XCTAssertTrue(GameLogPresentation("").spans.isEmpty)
    }

    func testPresentationLeavesOriginalEntryAndIdentityUntouched() {
        let source = "<font object_id='\(id)'>Visible card</font> [d80]"
        let entry = GameLogEntry(id: "seat-scoped-event", message: source, createdAt: nil)
        XCTAssertEqual(GameLogPresentation(entry.message).plainText, "Visible card")
        XCTAssertEqual(entry.message, source)
        XCTAssertEqual(entry.id, "seat-scoped-event")
        XCTAssertNil(entry.createdAt)
    }

    func testValidatedCardReferenceSurvivesEmphasisAndRoutesOnlyGeneratedURL() throws {
        let value = GameLogPresentation("casts <font object_id='\(id)'>Serra <i>Angel</i></font> [d80].")
        let references = value.spans.compactMap(\.cardReference)
        XCTAssertEqual(references.count, 2)
        XCTAssertTrue(references.allSatisfy { $0.objectID == UUID(uuidString: id) && $0.name == "Serra Angel" })
        let index = try XCTUnwrap(value.spans.firstIndex { $0.cardReference != nil })
        let url = try XCTUnwrap(value.inspectionURL(at: index))
        XCTAssertEqual(value.cardReference(for: url), references.first)
        for invalid in ["https://example.com/\(index)", "magicmobile-log://inspect/\(index)?other=1",
                        "magicmobile-log://inspect/999", "magicmobile-log://other/\(index)",
                        "magicmobile-log://inspect/0"] {
            XCTAssertNil(value.cardReference(for: try XCTUnwrap(URL(string: invalid))))
        }
    }

    func testColorOnlyMalformedHiddenAndAttributeNamesNeverBecomeReferences() {
        for source in ["<font color='#90EE90'>Card</font>",
                       "<font object_id='invalid'>Card</font>",
                       "<font object_id='\(id)' object_id='\(id)'>Card</font>",
                       "<font object_id='\(id)'>unclosed",
                       "<font object_id='\(id)'>Face-down card</font>",
                       "<script><font object_id='\(id)'>Secret</font></script>",
                       "<a href='magicmobile-log://inspect/0' title='Secret'>Card</a>"] {
            XCTAssertTrue(GameLogPresentation(source).spans.allSatisfy { $0.cardReference == nil }, source)
        }
    }

    func testRepeatedAndDifferentObjectIDsRemainDistinct() throws {
        let other = "d80199fe-06bb-486b-b9f7-a3d4a685bdd6"
        let value = GameLogPresentation("<font object_id='\(id)'>Army</font> blocks <font object_id='\(other)'>Army</font>")
        XCTAssertEqual(value.spans.compactMap(\.cardReference).map(\.objectID), [UUID(uuidString: id)!, UUID(uuidString: other)!])
        XCTAssertEqual(value.plainText, "Army blocks Army")
    }

    func testRulesCleanMarkupEntitiesSelfReferenceAndManaWithoutLookup() {
        let source = "<b>{this}</b> gets +1/+1.<br><i>Pay <img alt='{W}' src='secret'> &amp; {T}.</i> [choice]"
        XCTAssertEqual(GameRulesPresentation(source: source, cardName: "Army").plainText,
                       "Army gets +1/+1.\nPay {W} & {T}. [choice]")
        XCTAssertEqual(GameRulesPresentation(source: "&amp;lt;b&amp;gt;Flying&amp;lt;/b&amp;gt;").plainText, "Flying")
        XCTAssertEqual(GameRulesPresentation(source: "{this} attacks").plainText, "This card attacks")
        XCTAssertEqual(GameRulesPresentation(source: "{this} attacks", cardName: "A&B").plainText, "A&B attacks")
    }

    func testRulesHiddenAndNestedHiddenMarkupCannotDiscloseDetails() {
        XCTAssertEqual(GameRulesPresentation(source: "Secret rules", cardName: "Secret name", isHidden: true).plainText, "")
        XCTAssertEqual(GameRulesPresentation(source: "<object><svg>secret</object>Flying").plainText, "Flying")
        XCTAssertEqual(GameRulesPresentation(source: "&lt;script&gt;secret&lt;/script&gt;Flying").plainText, "Flying")
        XCTAssertEqual(GameRulesPresentation(source: "<img alt='Secret name' src='secret'>Flying").plainText, "Flying")
    }

    func testRulesNormalizationLimitFailsClosedForDeeplyEncodedHiddenContent() {
        var source = "<script>private payload</script>Flying"
        for _ in 0...GameRulesPresentation.maximumNormalizationPasses {
            source = source.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }
        XCTAssertEqual(GameRulesPresentation(source: source).plainText, GameRulesPresentation.unavailableText)
        XCTAssertEqual(GameRulesPresentation(source: source, isHidden: true).plainText, "")
        // Normal two-level engine escaping still works below the bound.
        XCTAssertEqual(GameRulesPresentation(source: "&amp;lt;i&amp;gt;Flying&amp;lt;/i&amp;gt;").plainText, "Flying")
    }

    func testRulesInputAndSelfReferenceExpansionAreByteBounded() {
        let limit = GameRulesPresentation.maximumBytes
        let exact = String(repeating: "A", count: limit)
        XCTAssertEqual(GameRulesPresentation(source: exact).plainText, exact)
        XCTAssertEqual(GameRulesPresentation(source: exact + "A").plainText, GameRulesPresentation.unavailableText)
        XCTAssertEqual(GameRulesPresentation(source: String(repeating: "🃏", count: limit / 4 + 1)).plainText,
                       GameRulesPresentation.unavailableText)
        XCTAssertEqual(GameRulesPresentation(source: String(repeating: "{this}", count: 100),
                                             cardName: String(repeating: "N", count: 512)).plainText,
                       GameRulesPresentation.unavailableText)
        XCTAssertEqual(GameRulesPresentation(source: "{this} attacks", cardName: String(repeating: "N", count: 513)).plainText,
                       "This card attacks")
        XCTAssertEqual(GameRulesPresentation(source: "{this} attacks", cardName: "&lt;b&gt;Army&lt;/b&gt;").plainText,
                       "Army attacks")
    }
}
