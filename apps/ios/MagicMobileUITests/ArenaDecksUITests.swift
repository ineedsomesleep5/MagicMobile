import XCTest

/// Deck Studio as Arena's Decks tab (Caleb, 2026-10-22): deck boxes under the top bar, the chosen deck's details
/// beside them, Edit Deck into the workspace and its chapters. (It was a spell book with a film and page curls.)
@MainActor
final class ArenaDecksUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        // A deck's cards as the full-art grid, as players get them.
        UITestHarness.configure(app, extraArguments: ["-deckStudio.cards.layout.v1", "Grid"])
        app.launch()
        XCTAssertTrue(app.buttons["menu.decks"].waitForExistence(timeout: 20))
        UITestHarness.settleFirstTouch(app)
        return app
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }

    func testDecksTabChoosesABoxThenEditsItsDeck() {
        let app = launch()
        defer { app.terminate() }
        app.buttons["menu.decks"].press(forDuration: 0.15)
        XCTAssertTrue(app.buttons["deckStudio.create"].waitForExistence(timeout: 15), "Decks opens on the deck boxes")
        XCTAssertTrue(app.buttons["menu.decks"].isSelected, "The Decks tab is lit")
        attach("Decks tab")

        let search = app.textFields["deckStudio.library.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("First Flight\n")
        let deck = app.buttons["deckStudio.deck.precon:first-flight"]
        XCTAssertTrue(deck.waitForExistence(timeout: 10))
        if !deck.isHittable { app.swipeUp() }
        // The first tap opens its box and shows it beside the others; Edit Deck opens it.
        deck.press(forDuration: 0.15)
        XCTAssertTrue(waitUntil { deck.isSelected }, "The tapped deck is chosen")
        let edit = app.buttons["deckStudio.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["deckStudio.detail"].exists)
        attach("Decks tab, a chosen deck")
        edit.tap()

        // The workspace and its chapters.
        let cards = app.buttons["Cards"], ideas = app.buttons["Ideas"], analysis = app.buttons["Analysis"]
        XCTAssertTrue(ideas.waitForExistence(timeout: 10))
        XCTAssertTrue(cards.isSelected)
        attach("Deck workspace")
        ideas.press(forDuration: 0.15)
        XCTAssertTrue(waitUntil { ideas.isSelected }, "A tab opens its chapter")
        analysis.press(forDuration: 0.15)
        XCTAssertTrue(waitUntil { analysis.isSelected })

        // Done returns to the boxes; Home leaves Decks.
        app.buttons["deckStudio.close"].tap()
        XCTAssertTrue(app.buttons["deckStudio.create"].waitForExistence(timeout: 10))
        app.buttons["menu.tab.home"].tap()
        XCTAssertTrue(waitUntil(timeout: 10) { app.buttons["menu.play"].isHittable }, "Home leaves Decks")
    }

    /// A deck's cards show their full art: the plus under a card (or its right half) adds a copy,
    /// the minus (or its left half) takes one away, and the last copy removes the card.
    func testTappingACardsRightHalfAddsACopyAndItsLeftHalfTakesOneAway() {
        let app = launch()
        defer { app.terminate() }
        app.buttons["menu.decks"].press(forDuration: 0.15)
        UITestHarness.revealCreateDeck(app).tap()
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
        XCTAssertTrue(more.waitForExistence(timeout: 10), "The card's plus adds a copy")
        XCTAssertTrue(cards.staticTexts["Sol Ring, quantity 1"].exists)
        XCTAssertLessThan(fewer.frame.midX, more.frame.midX, "Left takes away, right adds")
        XCTAssertLessThan(abs(fewer.frame.midY - more.frame.midY), 2, "The two halves of one card")
        // The sleeve can start under Quick Add and the Done/Play bar at the foot of the page; bring it well clear first.
        for _ in 0..<4 where !more.isHittable || more.frame.maxY > app.frame.maxY - 190 { cards.swipeUp() }
        more.tap()
        XCTAssertTrue(cards.staticTexts["Sol Ring, quantity 2"].waitForExistence(timeout: 5), "A tap on the right adds a copy")
        attach("Deck card grid")
        fewer.tap()
        XCTAssertTrue(cards.staticTexts["Sol Ring, quantity 1"].waitForExistence(timeout: 5), "A tap on the left takes one away")
        fewer.tap()
        XCTAssertTrue(more.waitForNonExistence(timeout: 5), "Taking the last copy away removes the card")
    }

    /// Sideways, the boxes fill the left and the chosen deck's details stand on the right, as Arena's Decks page.
    func testLandscapeDecksShowTheChosenDeckUnderTheBoxes() {
        let app = launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(waitUntil { app.buttons["menu.decks"].isHittable })
        app.buttons["menu.decks"].press(forDuration: 0.15)
        let create = app.buttons["deckStudio.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 15))
        let detail = app.descendants(matching: .any)["deckStudio.detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 10))
        // The boxes scroll under the bar, so measure the bar against the screen: it runs along the foot, full width.
        XCTAssertGreaterThan(detail.frame.minY, app.frame.height * 0.6, "The chosen deck's bar runs along the foot, under the boxes")
        XCTAssertGreaterThan(detail.frame.width, app.frame.width * 0.7)
        attach("Decks tab landscape")
        app.buttons["deckStudio.edit"].tap()
        let close = app.buttons["deckStudio.close"], cardsList = app.scrollViews["deckStudio.cards.list"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertTrue(cardsList.waitForExistence(timeout: 10))
        for chapter in ["Cards", "Ideas", "Analysis"] { XCTAssertTrue(app.buttons[chapter].exists, chapter) }
        attach("Deck workspace landscape")
        close.tap()
        XCTAssertTrue(create.waitForExistence(timeout: 10))
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
