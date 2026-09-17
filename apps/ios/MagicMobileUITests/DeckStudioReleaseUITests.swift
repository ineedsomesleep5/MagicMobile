import XCTest

/// Shipping Deck Studio views with an isolated preferences suite; no engine fixture gameplay.
@MainActor
final class DeckStudioReleaseUITests: XCTestCase {
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
        capture("Card inspector with offline rules")
        app.buttons["deckStudio.inspector.close"].tap()
        app.buttons["deckStudio.search.close"].tap()
        XCTAssertTrue(app.buttons["deckStudio.addCards"].isHittable)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["deckStudio.cards.search"].isHittable)
        capture("Landscape collection and deck together")
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
