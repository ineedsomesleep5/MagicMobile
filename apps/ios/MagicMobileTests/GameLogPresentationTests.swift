import XCTest
@testable import MagicMobile

final class GameLogPresentationTests: XCTestCase {
    private let id = "d80199fe-06bb-486b-b9f7-a3d4a685bdd5"

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
}
