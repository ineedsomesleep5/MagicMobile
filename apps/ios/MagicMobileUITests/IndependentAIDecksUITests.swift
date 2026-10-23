import XCTest

/// Real setup controls with isolated preferences. Never starts a game or signs in.
@MainActor
final class IndependentAIDecksUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchEnvironment["MAGICMOBILE_UI_TEST_PREFERENCES"] = UUID().uuidString
        app.launchArguments = ["-magicmobile.boardMode", "hearth", "-magicmobile.boardAppearance", "arena", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ondevice-setup-ui-test"]
        app.launch()
    }

    override func tearDownWithError() throws {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
        if let app {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Final setup hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
            app.terminate()
        }
        app = nil
        XCUIDevice.shared.orientation = .portrait
    }

    func testDistinctOpponentDecksSurviveCountChangesAndRelaunch() {
        openSetup()
        changeCount(from: 1, to: 3)
        let choices = ["First Flight", "Grave Danger", "Draconic Destruction"]
        for (index, name) in choices.enumerated() {
            let picker = app.buttons["ondevice.aiDeck.\(index + 1)"]
            reveal(picker)
            picker.press(forDuration: 0.15)
            let option = app.buttons[name]
            XCTAssertTrue(option.waitForExistence(timeout: 5))
            // The deck list scrolls inside its pop-over, opening on the current deck.
            let list = app.scrollViews.containing(NSPredicate(format: "label == %@", name)).firstMatch
            for step in 0..<8 where !option.isHittable {
                if step < 4 { list.swipeUp(velocity: .slow) } else { list.swipeDown(velocity: .slow) }
            }
            XCTAssertTrue(option.isHittable)
            option.press(forDuration: 0.15)
            assertSelection(index + 1, name)
        }
        changeCount(from: 3, to: 1)
        XCTAssertFalse(app.buttons["ondevice.aiDeck.2"].exists)
        XCTAssertFalse(app.buttons["ondevice.aiDeck.3"].exists)
        assertSelection(1, choices[0])
        changeCount(from: 1, to: 3)
        for (index, name) in choices.enumerated() { assertSelection(index + 1, name) }
        app.terminate(); app.launch()
        openSetup()
        XCTAssertTrue(app.buttons["ondevice.aiDeck.3"].waitForExistence(timeout: 5), "Three seats after relaunch")
        for (index, name) in choices.enumerated() { assertSelection(index + 1, name) }
        // Deliberately do not tap Start game; this verifies setup state, not engine execution.
    }

    /// The AI seats are deck boxes (Arena's custom table): "+" adds a seat, × on the last one empties it.
    private func changeCount(from initial: Int, to target: Int) {
        XCTAssertTrue(app.buttons["ondevice.aiDeck.\(initial)"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["ondevice.aiDeck.\(initial + 1)"].exists)
        var count = initial
        while count != target {
            if target > count {
                let add = app.buttons["ondevice.aiSeat.add"]
                reveal(add)
                add.press(forDuration: 0.15)
                count += 1
            } else {
                let remove = app.buttons["ondevice.aiSeat.remove.\(count)"]
                reveal(remove)
                remove.press(forDuration: 0.15)
                count -= 1
            }
            XCTAssertTrue(app.buttons["ondevice.aiDeck.\(count)"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["ondevice.aiDeck.\(count + 1)"].waitForNonExistence(timeout: 5))
        }
    }

    private func assertSelection(_ seat: Int, _ name: String) {
        let picker = app.buttons["ondevice.aiDeck.\(seat)"]
        reveal(picker)
        let predicate = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", name, name)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: picker)], timeout: 5), .completed)
    }

    private func openSetup() {
        let play = app.buttons["menu.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        // The first touch after launch only moves focus on this simulator (UITestHarness.settleFirstTouch).
        UITestHarness.settleFirstTouch(app)
        reveal(play)
        play.press(forDuration: 0.15)
        UITestHarness.chooseCustomTable(app)
        XCTAssertTrue(app.textFields["ondevice.playerName"].waitForExistence(timeout: 10))
        reveal(app.buttons["ondevice.aiDeck.1"])
    }

    private func reveal(_ element: XCUIElement, upward: Bool = true) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            if upward { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.exists && element.isHittable, "Setup control must be visible before interaction")
    }

    private func waitFor(_ element: XCUIElement, _ format: String) {
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)], timeout: 5), .completed)
    }
}
