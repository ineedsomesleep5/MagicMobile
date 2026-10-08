import XCTest

@MainActor
final class DeckStudioPinnedTabsUITests: XCTestCase {
    // The match history and its dashboard moved from Deck Studio's Playtest chapter to the player's
    // profile (Caleb, 2026-10-06); their UI tests live with the profile.
    func testPortraitCardsScrollHeaderAwayAndKeepWorkspaceTabsReachable() throws {
        let app = XCUIApplication()
        continueAfterFailure = false
        UITestHarness.configure(app)
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }

        XCTAssertTrue(app.buttons["menu.decks"].waitForExistence(timeout: 20))
        UITestHarness.settleFirstTouch(app)
        app.buttons["menu.decks"].press(forDuration: 0.15)
        let librarySearch = app.textFields["deckStudio.library.search"]
        XCTAssertTrue(librarySearch.waitForExistence(timeout: 10))
        librarySearch.tap()
        librarySearch.typeText("Token Triumph\n")
        let deck = app.buttons["deckStudio.deck.precon:token-triumph"]
        XCTAssertTrue(deck.waitForExistence(timeout: 10))
        if !deck.isHittable { app.swipeUp() }
        deck.press(forDuration: 0.15)

        let cards = app.scrollViews["deckStudio.cards.list"]
        XCTAssertTrue(cards.waitForExistence(timeout: 10))
        let search = app.textFields["deckStudio.cards.search"]
        XCTAssertTrue(search.isHittable)
        cards.swipeUp()
        cards.swipeUp()
        XCTAssertFalse(search.isHittable, "Search should scroll away with the commander header")
        XCTAssertFalse(app.otherElements["deckStudio.deckHeader"].isHittable)
        for title in ["Cards", "Ideas", "Analysis"] {
            XCTAssertTrue(app.buttons[title].isHittable, "Workspace tab must remain reachable: \(title)")
        }
        let visibleRows = cards.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Inspect "))
            .allElementsBoundByIndex.filter(\.isHittable)
        XCTAssertGreaterThanOrEqual(visibleRows.count, 4)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Portrait deck with pinned tabs and scrolling header"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["Analysis"].press(forDuration: 0.15)
        XCTAssertTrue(app.staticTexts["Your deck at a glance"].waitForExistence(timeout: 5))
    }

    func testPortraitIdeasAndAnalysisScrollHeaderAwayAndTabSwitchesLandAtTop() throws {
        let app = XCUIApplication()
        continueAfterFailure = false
        UITestHarness.configure(app)
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }

        XCTAssertTrue(app.buttons["menu.decks"].waitForExistence(timeout: 20))
        UITestHarness.settleFirstTouch(app)
        app.buttons["menu.decks"].press(forDuration: 0.15)
        let librarySearch = app.textFields["deckStudio.library.search"]
        XCTAssertTrue(librarySearch.waitForExistence(timeout: 10))
        librarySearch.tap()
        librarySearch.typeText("Token Triumph\n")
        let deck = app.buttons["deckStudio.deck.precon:token-triumph"]
        XCTAssertTrue(deck.waitForExistence(timeout: 10))
        if !deck.isHittable { app.swipeUp() }
        deck.press(forDuration: 0.15)

        let header = app.otherElements["deckStudio.deckHeader"]
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertTrue(header.isHittable)
        let restingTabY = app.buttons["Analysis"].frame.midY

        // A tab change lands on the pinned tabs: the header scrolls away and the new tab
        // starts at its top.
        app.buttons["Analysis"].press(forDuration: 0.15)
        let analysis = app.scrollViews["deckStudio.analysis.list"]
        XCTAssertTrue(analysis.waitForExistence(timeout: 10))
        let glance = app.staticTexts["Your deck at a glance"]
        assertLandsAtTop(glance, header: header, "Analysis")
        let pinnedTabY = app.buttons["Analysis"].frame.midY
        XCTAssertLessThan(abs(pinnedTabY - restingTabY), 8, "The index tabs stay at the binder's edge")
        capture("Portrait Analysis lands on the pinned tabs")
        analysis.swipeUp()
        analysis.swipeUp()
        XCTAssertFalse(header.isHittable)
        XCTAssertFalse(glance.isHittable, "Analysis should scroll under the pinned tabs")
        assertTabsPinned(app, at: pinnedTabY)
        capture("Portrait Analysis scrolled under pinned tabs")

        // Ideas scrolls with the header too, even when its content is short.
        app.buttons["Ideas"].press(forDuration: 0.15)
        let ideas = app.scrollViews["deckStudio.ideas.list"]
        XCTAssertTrue(ideas.waitForExistence(timeout: 10))
        let combos = app.staticTexts["Find your combos"]
        assertLandsAtTop(combos, header: header, "Ideas")
        assertTabsPinned(app, at: pinnedTabY)
        ideas.swipeDown()
        waitUntil(header, "hittable == true", "Ideas should scroll back down to the header")
        ideas.swipeUp()
        waitUntil(header, "hittable == false", "Ideas should scroll the header away")
        assertTabsPinned(app, at: pinnedTabY)
        capture("Portrait Ideas with pinned tabs")

        let edhrec = app.buttons["EDHREC"].firstMatch
        edhrec.press(forDuration: 0.15)
        waitUntil(edhrec, "selected == true", "EDHREC should become the Ideas source")
        let recs = app.buttons["Open EDHREC's Recs tool"]
        UITestHarness.reveal(recs, in: ideas)
        XCTAssertFalse(header.isHittable)
        assertTabsPinned(app, at: pinnedTabY)
        XCTAssertEqual(app.webViews.count, 0, "Scrolling must not open the website")

        // From deep in one tab, the next tab still starts at its top.
        app.buttons["Analysis"].press(forDuration: 0.15)
        XCTAssertTrue(analysis.waitForExistence(timeout: 10))
        assertLandsAtTop(glance, header: header, "Analysis after Ideas")
        assertTabsPinned(app, at: pinnedTabY)
        analysis.swipeUp()
        analysis.swipeUp()
        analysis.swipeUp()
        app.buttons["Cards"].press(forDuration: 0.15)
        let cardSearch = app.textFields["deckStudio.cards.search"]
        XCTAssertTrue(app.scrollViews["deckStudio.cards.list"].waitForExistence(timeout: 10))
        assertLandsAtTop(cardSearch, header: header, "Cards after Analysis")
        assertTabsPinned(app, at: pinnedTabY)
        capture("Portrait Cards at its top after a tab change")
    }

    /// The new tab's first content shows, then the switch lands on the pinned tabs (header
    /// scrolled away) with that content still at the top.
    private func assertLandsAtTop(_ top: XCUIElement, header: XCUIElement, _ tab: String,
                                  file: StaticString = #filePath, line: UInt = #line) {
        waitUntil(top, "hittable == true", "\(tab) content should appear", file: file, line: line)
        waitUntil(header, "hittable == false", "Switching to \(tab) should land on the pinned tabs", file: file, line: line)
        XCTAssertTrue(top.isHittable, "\(tab) should start at its top", file: file, line: line)
    }

    private func assertTabsPinned(_ app: XCUIApplication, at y: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        for title in ["Cards", "Ideas", "Analysis"] {
            XCTAssertTrue(app.buttons[title].isHittable, "Workspace tab must remain pinned: \(title)", file: file, line: line)
        }
        XCTAssertLessThan(abs(app.buttons["Analysis"].frame.midY - y), 8,
                          "Workspace tabs must stay at the same top position", file: file, line: line)
    }

    private func waitUntil(_ element: XCUIElement, _ format: String, _ message: String,
                           file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: 5)
        if result != .completed { capture("Failed: \(message)") }
        XCTAssertEqual(result, .completed, message, file: file, line: line)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
