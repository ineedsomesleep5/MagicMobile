import XCTest

/// Development fixtures verify touch delivery and draft presentation, not XMage execution.
@MainActor
final class CardChoiceDraftUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 180
    }

    override func tearDownWithError() throws {
        if let app {
            let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            image.lifetime = .keepAlways
            add(image)
            app.terminate()
        }
        XCUIDevice.shared.orientation = .portrait
    }

    private func launch(_ fixture: String, portrait: Bool = true, commandFailure: Bool = false) {
        app = XCUIApplication()
        app.launchEnvironment["MAGICMOBILE_UI_TEST_PREFERENCES"] = UUID().uuidString
        app.launchEnvironment["MAGICMOBILE_DESIGN_PREVIEW"] = fixture
        app.launchEnvironment["MAGICMOBILE_FORCE_CARD_PLACEHOLDERS"] = "true"
        if commandFailure { app.launchEnvironment["MAGICMOBILE_UI_TEST_CARD_CHOICE_FAILURE"] = "1" }
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-magicmobile.portraitModeEnabled", portrait ? "YES" : "NO"]
        XCUIDevice.shared.orientation = portrait ? .portrait : .landscapeLeft
        app.launch()
        XCTAssertTrue(app.staticTexts["DEVELOPMENT FIXTURE · NO ENGINE"].waitForExistence(timeout: 15))
    }

    func testLandscapeScryCardsAndFooterRemainUsableBesideOrderingControls() {
        launch("scry-choice", portrait: false)
        let grid = app.scrollViews["board.choice.cards"]
        let order = app.scrollViews["board.choice.order.scroll"]
        let confirm = app.buttons["board.choice.confirm"]
        let header = app.staticTexts["board.choice.header"]
        let first = app.descendants(matching: .any)["board.choice.card.choice-0"].firstMatch
        let second = app.descendants(matching: .any)["board.choice.card.choice-1"].firstMatch
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        XCTAssertTrue(order.exists)
        XCTAssertTrue(header.exists)
        XCTAssertLessThanOrEqual(grid.frame.minY - header.frame.maxY, 60,
                                 "Landscape header should not reserve a tall blank spacer")
        XCTAssertTrue(confirm.isHittable, "The confirmation footer remains pinned")
        for card in [first, second] {
            XCTAssertTrue(card.isHittable)
            XCTAssertGreaterThanOrEqual(card.frame.width, 90)
            XCTAssertGreaterThanOrEqual(card.frame.height, 120)
            let visibleFrame = card.frame.intersection(grid.frame)
            XCTAssertGreaterThanOrEqual(visibleFrame.height, card.frame.height * 0.9)
        }
        for id in ["choice-0", "choice-1"] {
            let caption = app.staticTexts["board.choice.caption.\(id)"]
            XCTAssertTrue(caption.isHittable, "Card caption should be visible without scrolling")
            XCTAssertGreaterThanOrEqual(caption.frame.intersection(grid.frame).height,
                                        caption.frame.height * 0.9)
        }
        first.tap()
        second.tap()
        for id in ["choice-0", "choice-1"] {
            let label = app.staticTexts["board.choice.order.bottom.\(id)"]
            XCTAssertTrue(label.exists)
            XCTAssertGreaterThanOrEqual(label.frame.intersection(order.frame).width,
                                        label.frame.width * 0.9,
                                        "Order names should fit the right pane without horizontal clipping")
        }
        let moveEarlier = app.buttons.matching(NSPredicate(format: "label == %@ AND enabled == true", "Move earlier")).firstMatch
        XCTAssertTrue(moveEarlier.waitForExistence(timeout: 5))
        moveEarlier.tap()
        XCTAssertTrue((second.value as? String ?? "").contains("position 1"))
        XCTAssertTrue(confirm.isHittable)
    }

    func testScryDraftTwoBucketsReorderDeselectAndConfirmOnce() {
        launch("scry-choice")
        let confirm = app.buttons["board.choice.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(confirm.isEnabled, "Keeping every card on top is a valid scry draft")
        let first = app.descendants(matching: .any)["board.choice.card.choice-0"].firstMatch
        let second = app.descendants(matching: .any)["board.choice.card.choice-1"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        second.tap()
        XCTAssertTrue(app.staticTexts["Put bottom · first to last"].exists)
        XCTAssertTrue(app.staticTexts["Keep top · top first"].exists)
        XCTAssertTrue((second.value as? String ?? "").contains("position 2"))
        let moveEarlier = app.buttons.matching(NSPredicate(format: "label == %@ AND enabled == true", "Move earlier")).firstMatch
        XCTAssertTrue(moveEarlier.waitForExistence(timeout: 5))
        moveEarlier.tap()
        let choiceScroll = app.scrollViews["board.choice.cards"]
        XCTAssertTrue(choiceScroll.exists)
        for _ in 0..<3 {
            if first.exists && first.isHittable && second.exists && second.isHittable { break }
            choiceScroll.swipeDown()
        }
        XCTAssertTrue(second.isHittable, "Return to the card grid after reordering")
        XCTAssertTrue((second.value as? String ?? "").contains("position 1"))
        XCTAssertTrue(first.isHittable, "Deselect the first card from the grid")
        first.tap()
        XCTAssertTrue((first.value as? String ?? "").contains("Keep top"))
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()
        XCTAssertTrue(app.staticTexts["preview.captured-command"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "preview.captured-command").count, 1)
        XCTAssertTrue(app.descendants(matching: .any)["board.choice.progress"].firstMatch.exists)
    }

    func testCommandFailureReturnsCommittedDraftToManualPrompt() {
        launch("scry-choice", commandFailure: true)
        let confirm = app.buttons["board.choice.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        let alert = app.alerts["MagicMobile"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["OK"].tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Current prompt reopens for manual review")
        XCTAssertFalse(app.descendants(matching: .any)["board.choice.progress"].firstMatch.exists)
    }

    func testCreatureTypeChoicesCanBeSearched() {
        launch("search-select-prompt")
        let search = app.textFields["prompt.choices.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("gob")
        XCTAssertTrue(app.buttons["Goblin"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Wizard"].exists)
    }

    func testCreatureTypeSearchShowsEmptyResult() {
        launch("search-select-prompt")
        let search = app.textFields["prompt.choices.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("NoSuchCreatureType")
        XCTAssertTrue(app.staticTexts["prompt.choices.noMatches"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Goblin"].exists)
    }
}
