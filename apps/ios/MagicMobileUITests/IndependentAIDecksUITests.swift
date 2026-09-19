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
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ondevice-setup-ui-test"]
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
        waitFor(countControl, "label == 'AI opponents: 3'")
        for (index, name) in choices.enumerated() { assertSelection(index + 1, name) }
        // Deliberately do not tap Start game; this verifies setup state, not engine execution.
    }

    private var countControl: XCUIElement {
        app.steppers["ondevice.aiCount"]
    }

    private func changeCount(from initial: Int, to target: Int) {
        let stepper = countControl
        reveal(stepper, upward: false)
        waitFor(stepper, "label == 'AI opponents: \(initial)'")
        let direction = target > initial ? 1 : -1
        var count = initial
        while count != target {
            let button = stepper.buttons[direction > 0 ? "ondevice.aiCount-Increment" : "ondevice.aiCount-Decrement"]
            XCTAssertTrue(button.exists && button.isHittable && button.isEnabled)
            button.press(forDuration: 0.15)
            count += direction
            waitFor(stepper, "label == 'AI opponents: \(count)'")
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
        reveal(play)
        play.press(forDuration: 0.15)
        XCTAssertTrue(app.textFields["ondevice.playerName"].waitForExistence(timeout: 10))
        reveal(countControl)
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
