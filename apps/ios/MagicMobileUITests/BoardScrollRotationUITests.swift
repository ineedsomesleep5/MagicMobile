import XCTest

/// Presentation fixtures only: these exercise delivered touches and layout, not engine legality.
@MainActor
final class BoardScrollRotationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 240
    }

    override func tearDownWithError() throws {
        if let app {
            let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            image.lifetime = .keepAlways
            add(image)
            let tree = XCTAttachment(string: app.debugDescription)
            tree.lifetime = .keepAlways
            add(tree)
            app.terminate()
        }
        XCUIDevice.shared.orientation = .portrait
    }

    private func launch(_ fixture: String, portrait: Bool) {
        app = XCUIApplication()
        app.launchEnvironment["MAGICMOBILE_UI_TEST_PREFERENCES"] = UUID().uuidString
        app.launchEnvironment["MAGICMOBILE_DESIGN_PREVIEW"] = fixture
        app.launchEnvironment["MAGICMOBILE_FORCE_CARD_PLACEHOLDERS"] = "true"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-magicmobile.portraitModeEnabled", "YES"]
        XCUIDevice.shared.orientation = portrait ? .portrait : .landscapeLeft
        app.launch()
        XCTAssertTrue(app.staticTexts["DEVELOPMENT FIXTURE · NO ENGINE"].waitForExistence(timeout: 20))
        rotate(portrait)
    }

    private func rotate(_ portrait: Bool) {
        XCUIDevice.shared.orientation = portrait ? .portrait : .landscapeLeft
        let predicate = NSPredicate { [self] _, _ in
            let frame = app.frame
            return portrait ? frame.height > frame.width : frame.width > frame.height
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: app)], timeout: 10), .completed)
    }

    private func card(_ prefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
    }

    private func dragArtwork(_ element: XCUIElement, in viewport: XCUIElement, horizontally: Bool) {
        let visible = element.frame.intersection(viewport.frame).intersection(app.frame)
        XCTAssertGreaterThan(visible.width, 10)
        XCTAssertGreaterThan(visible.height, 10)
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: visible.midX, dy: visible.midY))
        let distance = horizontally ? min(viewport.frame.width * 0.65, visible.midX - viewport.frame.minX - 8)
            : min(viewport.frame.height * 0.65, visible.midY - viewport.frame.minY - 8)
        XCTAssertGreaterThan(distance, 10)
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: horizontally ? -distance : 0, dy: horizontally ? 0 : -distance)))
    }

    func testMenuThemeChangeReopenCanReachQuit() {
        launch("crowded-battlefield", portrait: false)
        for _ in 0..<2 {
            app.buttons["Open game settings"].tap()
            XCTAssertTrue(app.staticTexts["Game Menu"].waitForExistence(timeout: 5))
            let theme = app.buttons["Classic Wood battlefield"]
            for _ in 0..<4 {
                if theme.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(theme.isHittable)
            theme.tap()
            let quit = app.buttons["Quit"]
            for _ in 0..<5 {
                if quit.isHittable && app.frame.contains(quit.frame) { break }
                app.swipeUp()
            }
            XCTAssertTrue(quit.isHittable)
            XCTAssertTrue(app.frame.contains(quit.frame), "Quit must be fully visible after changing theme")
            let done = app.buttons["board.menu.done"]
            for _ in 0..<5 {
                if done.isHittable { break }
                app.swipeDown()
            }
            XCTAssertTrue(done.isHittable)
            done.tap()
            XCTAssertTrue(app.buttons["Open game settings"].waitForExistence(timeout: 5))
        }
    }

    func testLandscapeLandsAndPermanentsScrollFromArtwork() {
        launch("combat-arrows", portrait: false)
        for title in ["Your lands", "Your board"] {
            let lane = app.scrollViews["board.battlefield.\(title)"]
            XCTAssertTrue(lane.waitForExistence(timeout: 5))
            let prefix = title == "Your lands" ? "card-your-lands-" : "card-your-board-"
            let cards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).allElementsBoundByIndex
            guard let source = cards.filter({ $0.isHittable && lane.frame.intersection($0.frame).width > 20 })
                .max(by: { $0.frame.midX < $1.frame.midX }) else {
                XCTFail("No visible artwork in \(title)"); return
            }
            let before = source.frame.minX
            dragArtwork(source, in: lane, horizontally: true)
            XCTAssertLessThan(source.frame.minX, before - 20, "Dragging card artwork must scroll \(title)")
            XCTAssertFalse(app.staticTexts["preview.captured-command"].exists)
        }
    }

    func testCardTapAndHoldStillWorkAfterScrollingFix() {
        launch("crowded-battlefield", portrait: true)
        let creature = card("card-your-board-isamaru")
        XCTAssertTrue(creature.waitForExistence(timeout: 5))
        creature.tap()
        XCTAssertTrue(creature.label.hasSuffix(", selected"))
        creature.press(forDuration: 0.7)
        XCTAssertTrue(card("card-inspector-isamaru").waitForNonExistence(timeout: 3),
                      "Inspection must end when the finger lifts")
    }

    func testLibraryChoicesScrollFromArtwork() {
        launch("library-choice", portrait: true)
        let first = app.descendants(matching: .any)["board.choice.card.choice-0"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        let last = app.descendants(matching: .any)["board.choice.card.choice-10"].firstMatch
        for _ in 0..<6 {
            if last.isHittable { break }
            let candidates = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "board.choice.card.")).allElementsBoundByIndex
            guard let source = candidates.filter({ $0.isHittable }).max(by: { $0.frame.midY < $1.frame.midY }) else {
                XCTFail("No visible search result artwork"); return
            }
            dragArtwork(source, in: app.scrollViews["board.choice.cards"], horizontally: false)
        }
        XCTAssertTrue(last.isHittable, "Search results must scroll to later cards")
        XCTAssertFalse(app.buttons["board.choice.confirm"].isEnabled, "Scrolling must not select a card")
        last.tap()
        XCTAssertTrue(app.buttons["board.choice.confirm"].isEnabled)
    }

    func testZoneInspectorScrollsFromArtwork() {
        launch("zone-inspection", portrait: true)
        XCTAssertTrue(app.buttons["Close You · Graveyard"].waitForExistence(timeout: 5))
        let last = app.buttons["Inspect Fixture Graveyard 23"]
        for _ in 0..<12 {
            if last.isHittable { break }
            let candidates = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "card-you-graveyard-")).allElementsBoundByIndex
            guard let source = candidates.filter({ $0.isHittable }).max(by: { $0.frame.midY < $1.frame.midY }) else {
                XCTFail("No visible graveyard artwork to begin a scroll"); return
            }
            dragArtwork(source, in: app, horizontally: false)
        }
        XCTAssertTrue(last.isHittable)
        XCTAssertFalse(app.staticTexts["preview.captured-command"].exists)
    }

    func testCombatEdgeIndicatorsSurviveRepeatedRotation() {
        launch("combat-arrows", portrait: true)
        for (index, portrait) in [true, false, true, false, true].enumerated() {
            rotate(portrait)
            let lane = app.scrollViews["board.battlefield.Your board"]
            let edge = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "board.combat.offscreen.")).firstMatch
            for _ in 0..<5 {
                if edge.exists && edge.isHittable { break }
                lane.swipeLeft()
            }
            XCTAssertTrue(edge.isHittable, "Combat edge control missing after rotation \(index)")
            XCTAssertTrue(app.frame.contains(edge.frame), "Combat edge control retained offscreen geometry")
            let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            image.name = "combat-rotation-\(index)-\(portrait ? "portrait" : "landscape")"
            image.lifetime = .keepAlways
            add(image)
        }
        // This verifies indicator survival and supplies captures for arrow review;
        // it does not equate accessibility geometry with Canvas path endpoints.
    }
}
