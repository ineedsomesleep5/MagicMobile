import XCTest

/// Deck Studio as a spell book: the opening film, page turns and swipes, with the motion the other
/// UI tests switch off turned on.
@MainActor
final class GrimoireUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        // The book as players get it: a deck's cards as the full-art grid.
        UITestHarness.configure(app, extraArguments: ["-deckStudio.cards.layout.v1", "Grid"])
        app.launchEnvironment["MAGICMOBILE_UI_TEST_GRIMOIRE_MOTION"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["menu.decks"].waitForExistence(timeout: 20))
        UITestHarness.settleFirstTouch(app)
        return app
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }

    func testTheBookOpensTurnsItsPagesAndCloses() {
        let app = launch()
        defer { app.terminate() }
        app.buttons["menu.decks"].press(forDuration: 0.15)
        // The film plays over the menu, then the library is the book's first page.
        XCTAssertTrue(app.buttons["deckStudio.create"].waitForExistence(timeout: 15), "The book opens on the library")
        XCTAssertTrue(app.staticTexts["My Decks"].exists)
        attach("Spell book library page")

        let search = app.textFields["deckStudio.library.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("Token Triumph\n")
        let deck = app.buttons["deckStudio.deck.precon:token-triumph"]
        XCTAssertTrue(deck.waitForExistence(timeout: 10))
        if !deck.isHittable { app.swipeUp() }
        deck.press(forDuration: 0.15)

        // A deck is the next page; its chapters are the binder's index tabs.
        let cards = app.buttons["Cards"], ideas = app.buttons["Ideas"], analysis = app.buttons["Analysis"]
        XCTAssertTrue(ideas.waitForExistence(timeout: 10))
        XCTAssertTrue(cards.isSelected)
        attach("Spell book deck page")
        ideas.press(forDuration: 0.15)
        XCTAssertTrue(waitUntil { ideas.isSelected }, "An index tab turns to its chapter")

        // A swipe turns the page: leftward to the next chapter, rightward to the one before. (Both start
        // near the head of the page: lower down, Analysis has a chart that scrolls sideways and keeps
        // its own swipes.)
        let page = app.windows.firstMatch
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.32))
            .press(forDuration: 0.05, thenDragTo: page.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.32)))
        XCTAssertTrue(waitUntil { analysis.isSelected }, "Swiping left turns to the next chapter")
        attach("Spell book analysis page")
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.32))
            .press(forDuration: 0.05, thenDragTo: page.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.32)))
        XCTAssertTrue(waitUntil { ideas.isSelected }, "Swiping right turns back")

        // Done turns back to the library; Done there closes the book onto the menu. The library may still be
        // scrolled to the deck it opened, so scroll back to its head first.
        app.buttons["deckStudio.close"].tap()
        let create = app.buttons["deckStudio.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        for _ in 0..<3 where !waitUntil(timeout: 3, { create.isHittable }) { app.swipeDown() }
        XCTAssertTrue(waitUntil { create.isHittable })
        app.buttons["deckStudio.library.close"].tap()
        XCTAssertTrue(waitUntil(timeout: 15) { app.buttons["menu.decks"].isHittable }, "The book closes back onto the menu")
    }

    /// A deck's cards are sleeves of their full art: the plus under a card (or its right half) adds a copy,
    /// the minus (or its left half) takes one away, and the last copy removes the card.
    func testTappingACardsRightHalfAddsACopyAndItsLeftHalfTakesOneAway() {
        let app = launch()
        defer { app.terminate() }
        app.buttons["menu.decks"].press(forDuration: 0.15)
        XCTAssertTrue(app.buttons["deckStudio.create"].waitForExistence(timeout: 15))
        XCTAssertTrue(waitUntil { app.buttons["deckStudio.create"].isHittable })
        app.buttons["deckStudio.create"].tap()
        let skip = app.buttons["deckStudio.commanderFirst.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10))
        skip.tap()
        XCTAssertTrue(skip.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["deckStudio.addCards"].waitForExistence(timeout: 10))
        app.buttons["deckStudio.addCards"].tap()
        let search = app.textFields["Card name or rules text"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("Sol Ring\n")
        let add = app.buttons["Add Sol Ring to deck"]
        XCTAssertTrue(add.waitForExistence(timeout: 10)); add.tap()
        XCTAssertTrue(app.buttons["Remove one Sol Ring from deck"].waitForExistence(timeout: 5))
        app.buttons["deckStudio.search.close"].tap()

        let cards = app.scrollViews["deckStudio.cards.list"]
        let more = cards.buttons["Add one Sol Ring"], fewer = cards.buttons["Remove one Sol Ring"]
        XCTAssertTrue(more.waitForExistence(timeout: 10), "The card is in a sleeve whose plus adds a copy")
        XCTAssertTrue(cards.staticTexts["Sol Ring, quantity 1"].exists)
        let hint = cards.staticTexts["deckStudio.cards.tapHint"]
        XCTAssertTrue(hint.exists, "Until the first tap, the page says what a tap does")
        XCTAssertLessThan(fewer.frame.midX, more.frame.midX, "Left takes away, right adds")
        XCTAssertLessThan(abs(fewer.frame.midY - more.frame.midY), 2, "The two halves of one card")
        // The sleeve can start just under Quick Add at the foot of the page; bring it up first.
        for _ in 0..<3 where !more.isHittable { cards.swipeUp() }
        more.tap()
        XCTAssertTrue(cards.staticTexts["Sol Ring, quantity 2"].waitForExistence(timeout: 5), "A tap on the right adds a copy")
        XCTAssertTrue(hint.waitForNonExistence(timeout: 5), "The hint has done its job")
        attach("Spell book card grid")
        fewer.tap()
        XCTAssertTrue(cards.staticTexts["Sol Ring, quantity 1"].waitForExistence(timeout: 5), "A tap on the left takes one away")
        fewer.tap()
        XCTAssertTrue(more.waitForNonExistence(timeout: 5), "Taking the last copy away removes the card")
    }

    /// Sideways the book lies open as a spread: two pages, each with its own content, and nothing
    /// running across the fold between them.
    func testTheBookLiesOpenAsASpreadInLandscape() {
        let app = launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(waitUntil { app.buttons["menu.decks"].isHittable })
        app.buttons["menu.decks"].press(forDuration: 0.15)
        let create = app.buttons["deckStudio.create"], search = app.textFields["deckStudio.library.search"]
        XCTAssertTrue(create.waitForExistence(timeout: 15), "The book opens on the library")
        XCTAssertTrue(waitUntil { create.isHittable })
        let fold = app.windows.firstMatch.frame.midX
        // The library: its heading and filters on the left page, the decks on the right.
        let deck = app.buttons["deckStudio.deck.precon:token-triumph"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("Token Triumph\n")
        XCTAssertTrue(deck.waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(create.frame.maxX, fold, "The library's heading stays on the left page")
        XCTAssertLessThanOrEqual(search.frame.maxX, fold)
        XCTAssertGreaterThan(deck.frame.midX, fold, "The decks are the right page")
        attach("Spell book library spread")
        deck.press(forDuration: 0.15)

        // A deck: the title plate and the rail (search, tools, mana coins) on the left page, its cards on
        // the right, and the chapters as index tabs standing out of the right page's outer edge.
        let close = app.buttons["deckStudio.close"], cards = app.scrollViews["deckStudio.cards.list"]
        let deckSearch = app.textFields["deckStudio.cards.search"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil { close.isHittable }, "The deck's pages settle after the turn")
        XCTAssertTrue(cards.waitForExistence(timeout: 10))
        XCTAssertTrue(deckSearch.isHittable, "The rail is on the left page")
        XCTAssertLessThanOrEqual(deckSearch.frame.maxX, cards.frame.minX, "The rail is the left page, the cards the right")
        XCTAssertLessThanOrEqual(close.frame.maxX, cards.frame.minX)
        for chapter in ["Cards", "Ideas", "Analysis"] {
            XCTAssertGreaterThanOrEqual(app.buttons[chapter].frame.minX, cards.frame.maxX - 1, "\(chapter)'s tab stands out of the right page")
        }
        attach("Spell book deck spread")
        // The rail is on the Cards chapter only; the left page's edge is measured before turning.
        let leftPageEdge = deckSearch.frame.maxX
        app.buttons["Analysis"].press(forDuration: 0.15)
        XCTAssertTrue(waitUntil { app.buttons["Analysis"].isSelected })
        XCTAssertTrue(app.scrollViews["deckStudio.analysis.list"].waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(app.scrollViews["deckStudio.analysis.list"].frame.minX, leftPageEdge - 1,
                                    "The roles are the right page")
        attach("Spell book analysis spread")
        app.buttons["Ideas"].press(forDuration: 0.15)
        XCTAssertTrue(waitUntil { app.buttons["Ideas"].isSelected })
        attach("Spell book ideas spread")

        close.tap()
        // Back on the library: Done closes the book.
        let done = app.buttons["deckStudio.library.close"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil { done.isHittable }, "The library settles after the turn back")
        done.tap()
        XCTAssertTrue(waitUntil(timeout: 15) { app.buttons["menu.decks"].isHittable }, "The book closes back onto the menu")
    }

    private func waitUntil(timeout: TimeInterval = 8, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return condition()
    }
}
