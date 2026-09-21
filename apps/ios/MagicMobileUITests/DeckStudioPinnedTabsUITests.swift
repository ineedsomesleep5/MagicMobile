import XCTest

@MainActor
final class DeckStudioPinnedTabsUITests: XCTestCase {
    func testPortraitPlaytestHistoryScrollsHeaderAwayAndPinsWorkspaceTabs() throws {
        let app = XCUIApplication()
        continueAfterFailure = false
        app.launchEnvironment["MAGICMOBILE_UI_TEST_PREFERENCES"] = UUID().uuidString
        app.launchArguments = ["--ondevice-setup-ui-test", "--deck-history-layout-ui-test",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
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
        let last = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Fixture match 18")).firstMatch
        XCTAssertFalse(last.isHittable)
        history.swipeUp()
        history.swipeUp()
        XCTAssertFalse(header.isHittable)
        let pinnedTabY = app.buttons["Playtest"].frame.midY
        for _ in 0..<10 where !last.isHittable { history.swipeUp() }
        XCTAssertTrue(last.isHittable, "All retained fixture sessions should be reachable")
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
        app.launchEnvironment["MAGICMOBILE_UI_TEST_PREFERENCES"] = UUID().uuidString
        app.launchArguments = ["--ondevice-setup-ui-test", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
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
