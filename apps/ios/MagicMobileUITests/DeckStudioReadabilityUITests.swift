import XCTest
import UIKit

@MainActor
final class DeckStudioReadabilityUITests: XCTestCase {
    private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        UITestHarness.configure(app, extraArguments: extra)
        app.launch()
        XCTAssertTrue(app.buttons["menu.decks"].waitForExistence(timeout: 20))
        // Match the foreground-verified press duration; destination assertions
        // remain mandatory and the action is never silently retried.
        XCTAssertTrue(app.buttons["menu.decks"].isHittable)
        app.buttons["menu.decks"].press(forDuration: 0.15)
        XCTAssertTrue(app.buttons["deckStudio.create"].waitForExistence(timeout: 15))
        app.buttons["deckStudio.create"].tap()
        XCTAssertTrue(app.buttons["deckStudio.addCards"].waitForExistence(timeout: 10))
        return app
    }

    func testGrayMerchantControlsRemainBesideNameInPortraitAndLandscape() {
        let app = launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        app.buttons["deckStudio.addCards"].tap()
        let search = app.textFields["Card name or rules text"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("Gray Merchant of Asphodel\n")
        let add = app.buttons["Add Gray Merchant of Asphodel to deck"]
        XCTAssertTrue(add.waitForExistence(timeout: 10)); add.tap()
        XCTAssertTrue(app.buttons["Remove one Gray Merchant of Asphodel from deck"].waitForExistence(timeout: 5))
        app.buttons["deckStudio.search.close"].tap()
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let list = app.scrollViews["deckStudio.cards.list"]
            let name = list.buttons["Inspect Gray Merchant of Asphodel, quantity 1"]
            let plus = list.buttons["Add one Gray Merchant of Asphodel"]
            XCTAssertTrue(name.waitForExistence(timeout: 10))
            if !plus.isHittable { list.swipeUp() }
            XCTAssertTrue(plus.isHittable)
            XCTAssertLessThan(abs(name.frame.midY - plus.frame.midY), 24, "Controls must stay beside the card name")
            plus.tap()
            XCTAssertTrue(list.buttons["Inspect Gray Merchant of Asphodel, quantity 2"].waitForExistence(timeout: 5))
            list.buttons["Remove one Gray Merchant of Asphodel"].tap()
            XCTAssertTrue(name.waitForExistence(timeout: 5))
        }
    }

    func testComboFixtureShowsCardsThenPrerequisitesOrderedStepsAndResults() {
        let app = launch(extra: ["--deck-combo-readability-ui-test"])
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        app.buttons["Ideas"].tap()
        XCTAssertTrue(app.navigationBars["Combo details"].waitForExistence(timeout: 10))
        let cards = app.scrollViews["deckStudio.combo.cards"]
        XCTAssertTrue(cards.exists)
        XCTAssertTrue(app.staticTexts["Alpha"].isHittable)
        XCTAssertTrue(app.staticTexts["Beta"].isHittable)
        let prerequisites = app.staticTexts["Before you begin"]
        XCTAssertGreaterThan(prerequisites.frame.minY, cards.frame.minY)
        app.swipeUp()
        let first = app.staticTexts["deckStudio.combo.step.1"]
        let second = app.staticTexts["deckStudio.combo.step.2"]
        XCTAssertTrue(first.exists); XCTAssertTrue(second.exists)
        XCTAssertEqual(first.label, "Example first step")
        XCTAssertEqual(second.label, "Example second step")
        XCTAssertLessThan(first.frame.minY, second.frame.minY)
        XCTAssertGreaterThan(app.staticTexts["Results"].frame.minY, second.frame.minY)
        XCTAssertTrue(app.staticTexts["Example result"].exists)
    }
}
