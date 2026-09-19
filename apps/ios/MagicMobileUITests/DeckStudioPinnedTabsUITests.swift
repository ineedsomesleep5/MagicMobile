import XCTest

@MainActor
final class DeckStudioPinnedTabsUITests: XCTestCase {
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
