import XCTest

/// Shipping Deck Studio views with an isolated preferences suite; no engine fixture gameplay.
@MainActor
final class DeckStudioReleaseUITests: XCTestCase {
    func testCommanderMenuSetupAndLibraryNavigation() throws {
        let app = XCUIApplication()
        continueAfterFailure = false
        app.launchEnvironment["MAGICMOBILE_UI_TEST_PREFERENCES"] = UUID().uuidString
        app.launchArguments = ["--ondevice-setup-ui-test", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.buttons["menu.play"].waitForExistence(timeout: 20))
        capture("Commander menu portrait")
        app.buttons["menu.play"].tap()
        XCTAssertTrue(app.textFields["ondevice.playerName"].waitForExistence(timeout: 10))
        capture("Commander table setup portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        capture("Commander table setup landscape")
        app.buttons["Main menu"].tap()
        XCTAssertTrue(app.buttons["menu.decks"].waitForExistence(timeout: 10))
        capture("Commander menu landscape")
        XCUIDevice.shared.orientation = .portrait
        app.buttons["menu.decks"].tap()
        XCTAssertTrue(app.buttons["deckStudio.create"].waitForExistence(timeout: 10))
        capture("Commander deck library portrait")
    }

    func testNewDraftSearchAddInspectRotateAndDiscard() throws {
        let app = XCUIApplication()
        continueAfterFailure = false
        app.launchEnvironment["MAGICMOBILE_UI_TEST_PREFERENCES"] = UUID().uuidString
        app.launchArguments = ["--ondevice-setup-ui-test", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.buttons["menu.decks"].waitForExistence(timeout: 20))
        app.buttons["menu.decks"].tap()
        XCTAssertTrue(app.buttons["deckStudio.create"].waitForExistence(timeout: 15))
        app.buttons["deckStudio.create"].tap()
        XCTAssertTrue(app.buttons["deckStudio.addCards"].waitForExistence(timeout: 10))
        app.buttons["deckStudio.addCards"].tap()
        let search = app.textFields["Card name or rules text"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("Sol Ring\n")
        let add = app.buttons["Add Sol Ring to deck"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        if !add.isHittable { app.swipeUp() }
        add.tap()
        XCTAssertTrue(app.buttons["Remove one Sol Ring from deck"].waitForExistence(timeout: 5))
        capture("Portrait card search with quantity controls")
        app.buttons["Inspect Sol Ring"].tap()
        XCTAssertTrue(app.buttons["deckStudio.inspector.close"].waitForExistence(timeout: 5))
        app.swipeUp()
        capture("Card inspector with offline rules")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "tap", "colorless mana")).firstMatch.exists, app.debugDescription)
        app.buttons["deckStudio.inspector.close"].tap()
        for name in ["Arcane Signet", "Command Tower", "Swords to Plowshares", "Llanowar Elves", "Forest", "Plains"] {
            app.buttons["Clear collection search"].tap()
            search.tap(); search.typeText(name + "\n")
            let addCard = app.buttons["Add \(name) to deck"]
            XCTAssertTrue(addCard.waitForExistence(timeout: 10))
            addCard.tap()
            XCTAssertTrue(app.buttons["Remove one \(name) from deck"].waitForExistence(timeout: 5))
        }
        app.buttons["deckStudio.search.close"].tap()
        XCTAssertTrue(app.buttons["deckStudio.addCards"].isHittable)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["deckStudio.cards.search"].isHittable)
        XCTAssertTrue(app.buttons["deckStudio.cards.options"].isHittable)
        let cardList = app.scrollViews["deckStudio.cards.list"]
        XCTAssertGreaterThan(cardList.frame.height, app.frame.height * 0.55)
        let visibleCards = cardList.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Inspect ")).allElementsBoundByIndex.filter(\.isHittable)
        XCTAssertGreaterThanOrEqual(visibleCards.count, 3)
        capture("Landscape collection and deck together")
        cardList.swipeUp()
        XCTAssertTrue(cardList.buttons["Inspect Plains, quantity 1"].isHittable)
        capture("Landscape populated deck after scrolling")
        XCUIDevice.shared.orientation = .portrait
        let deckSearch = app.textFields["deckStudio.cards.search"]
        XCTAssertTrue(deckSearch.waitForExistence(timeout: 10))
        capture("Portrait deck draft")
        app.buttons["deckStudio.close"].tap()
        let discard = app.buttons["Discard unsaved changes and close"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5)); discard.tap()
        XCTAssertTrue(app.buttons["deckStudio.create"].waitForExistence(timeout: 10))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
