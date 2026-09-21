import XCTest

@MainActor
final class DeckStudioPinnedTabsUITests: XCTestCase {
    func testPublicHistoryDashboardScrubsAndInspectsCards() throws {
        let app = XCUIApplication()
        continueAfterFailure = false
        UITestHarness.configure(app, extraArguments: ["--deck-history-layout-ui-test"])
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.buttons["menu.decks"].waitForExistence(timeout: 20))
        app.buttons["menu.decks"].tap()
        let search = app.textFields["deckStudio.library.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("Token Triumph\n")
        let deck = app.buttons["deckStudio.deck.precon:token-triumph"]
        XCTAssertTrue(deck.waitForExistence(timeout: 10))
        if !deck.isHittable { app.swipeUp() }
        deck.tap()
        XCTAssertTrue(app.buttons["Playtest"].waitForExistence(timeout: 10))
        app.buttons["Playtest"].tap()
        let history = app.scrollViews["deckStudio.playtest.list"]
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        let first = app.buttons["deckHistory.match.00000000-0000-0000-0000-000000000001.expand"]
        UITestHarness.reveal(first, in: history, swipes: 6)
        XCTAssertTrue(first.label.contains("versus Fixture rival"))
        first.tap()
        XCTAssertEqual(first.value as? String, "Expanded")
        let previous = app.buttons["deckHistory.timeline.previous"]
        UITestHarness.reveal(previous, in: history, swipes: 6)
        XCTAssertTrue(previous.isEnabled)
        previous.tap()
        XCTAssertTrue(app.buttons["deckHistory.timeline.next"].isEnabled)
        let inspect = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "deckHistory.event.", ".inspect")).firstMatch
        UITestHarness.reveal(inspect, in: history, swipes: 4)
        let portrait = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        portrait.name = "Public history dashboard portrait fixture"; portrait.lifetime = .keepAlways; add(portrait)
        inspect.tap()
        XCTAssertTrue(app.buttons["deckStudio.inspector.close"].waitForExistence(timeout: 5))
        app.buttons["deckStudio.inspector.close"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        let workspace = app.buttons["deckStudio.workspace"]
        XCTAssertTrue(workspace.waitForExistence(timeout: 10))
        XCTAssertTrue(workspace.label.contains("Playtest"))
        UITestHarness.reveal(first, in: history, swipes: 6)
        // A partly visible row under the compact navigation bar can report
        // hittable while its tap center is obscured. Bring the whole row inside.
        for _ in 0..<6 {
            let visible = history.frame.insetBy(dx: 0, dy: 12)
            if visible.contains(first.frame) { break }
            let shift = max(-history.frame.height * 0.3, min(history.frame.height * 0.3,
                visible.midY - first.frame.midY))
            let start = history.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: shift)))
        }
        if first.value as? String != "Expanded" { first.tap() }
        XCTAssertEqual(first.value as? String, "Expanded")
        UITestHarness.reveal(previous, in: history, swipes: 8)
        XCTAssertTrue(app.sliders["deckHistory.timeline.scrubber"].isHittable)
        let landscape = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        landscape.name = "Public history dashboard landscape fixture"; landscape.lifetime = .keepAlways; add(landscape)
    }
    func testPortraitPlaytestHistoryScrollsHeaderAwayAndPinsWorkspaceTabs() throws {
        let app = XCUIApplication()
        continueAfterFailure = false
        UITestHarness.configure(app, extraArguments: ["--deck-history-layout-ui-test"])
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }

        XCTAssertTrue(app.buttons["menu.decks"].waitForExistence(timeout: 20))
        app.buttons["menu.decks"].tap()
        let search = app.textFields["deckStudio.library.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("Token Triumph\n")
        let deck = app.buttons["deckStudio.deck.precon:token-triumph"]
        XCTAssertTrue(deck.waitForExistence(timeout: 10))
        if !deck.isHittable { app.swipeUp() }
        deck.tap()

        let header = app.otherElements["deckStudio.deckHeader"]
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertTrue(header.isHittable)
        XCTAssertEqual(app.buttons["Deck details"].value as? String, "Expanded")
        XCTAssertTrue(app.staticTexts["Included / read-only"].isHittable,
                      "The expanded commander header should be visible before scrolling")
        let initialHeader = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        initialHeader.name = "Expanded commander header before Playtest scroll"
        initialHeader.lifetime = .keepAlways
        add(initialHeader)
        app.buttons["Playtest"].tap()
        XCTAssertTrue(app.buttons["Playtest"].isSelected, "Playtest must become the active workspace after tapping its tab")
        let history = app.scrollViews["deckStudio.playtest.list"]
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Development fixture · not saved"].waitForExistence(timeout: 10))
        let last = history.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Fixture match 18")).firstMatch
        XCTAssertFalse(last.isHittable)
        history.swipeUp()
        history.swipeUp()
        XCTAssertFalse(header.isHittable)
        let pinnedTabY = app.buttons["Playtest"].frame.midY
        UITestHarness.reveal(last, in: history, swipes: 10)
        XCTAssertFalse(header.isHittable, "The expanded header must scroll away with history")
        for title in ["Cards", "Ideas", "Analysis", "Playtest"] {
            XCTAssertTrue(app.buttons[title].isHittable, "Workspace tab must remain pinned: \(title)")
        }
        XCTAssertLessThan(abs(app.buttons["Playtest"].frame.midY - pinnedTabY), 8,
                          "Workspace tabs must stay at the same top position while history scrolls")
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Portrait Playtest history with pinned tabs"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPortraitCardsScrollHeaderAwayAndKeepWorkspaceTabsReachable() throws {
        let app = XCUIApplication()
        continueAfterFailure = false
        UITestHarness.configure(app)
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }

        XCTAssertTrue(app.buttons["menu.decks"].waitForExistence(timeout: 20))
        app.buttons["menu.decks"].tap()
        let librarySearch = app.textFields["deckStudio.library.search"]
        XCTAssertTrue(librarySearch.waitForExistence(timeout: 10))
        librarySearch.tap()
        librarySearch.typeText("Token Triumph\n")
        let deck = app.buttons["deckStudio.deck.precon:token-triumph"]
        XCTAssertTrue(deck.waitForExistence(timeout: 10))
        if !deck.isHittable { app.swipeUp() }
        deck.tap()

        let cards = app.scrollViews["deckStudio.cards.list"]
        XCTAssertTrue(cards.waitForExistence(timeout: 10))
        let search = app.textFields["deckStudio.cards.search"]
        XCTAssertTrue(search.isHittable)
        cards.swipeUp()
        cards.swipeUp()
        XCTAssertFalse(search.isHittable, "Search should scroll away with the commander header")
        XCTAssertFalse(app.otherElements["deckStudio.deckHeader"].isHittable)
        for title in ["Cards", "Ideas", "Analysis", "Playtest"] {
            XCTAssertTrue(app.buttons[title].isHittable, "Workspace tab must remain reachable: \(title)")
        }
        let visibleRows = cards.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Inspect "))
            .allElementsBoundByIndex.filter(\.isHittable)
        XCTAssertGreaterThanOrEqual(visibleRows.count, 4)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Portrait deck with pinned tabs and scrolling header"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["Analysis"].tap()
        XCTAssertTrue(app.staticTexts["Your deck at a glance"].waitForExistence(timeout: 5))
    }
}
