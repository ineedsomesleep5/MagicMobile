import XCTest

/// Real setup views in a presentation-only build; no native gameplay or Game Center login.
@MainActor
final class OnDeviceSetupUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        // Argument-domain preferences override only this launch; never reset stored user data.
        app.launchArguments = [
            "-magicmobile.playerDisplayName", "",
            "-magicmobile.portraitModeEnabled", "YES",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "--ondevice-setup-ui-test"
        ]
        app.launch()
        XCTAssertTrue(app.textFields["ondevice.playerName"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Choose your deck and players."].waitForExistence(timeout: 15))
    }

    override func tearDownWithError() throws {
        if let app {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
        app = nil
    }

    func testEmptyNameDisablesStartAndEnteringNameEnablesIt() {
        let start = app.buttons["Start game"]
        reveal(start)
        XCTAssertFalse(start.isEnabled)

        let playerName = app.textFields["ondevice.playerName"]
        reveal(playerName, scrollingUp: false)
        playerName.tap()
        playerName.typeText("Setup Tester")
        reveal(start)
        waitFor(start, predicate: "enabled == true")
    }

    func testGameCenterSettingsAllowTwoThroughFourHumansWithoutSigningIn() {
        let gameCenter = app.segmentedControls.buttons["Game Center"]
        reveal(gameCenter)
        gameCenter.tap()
        let humans = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Human players")).firstMatch
        reveal(humans)
        // Select a different value before returning to the initial two-player choice.
        for count in [3, 4, 2] {
            humans.tap()
            let option = app.buttons["\(count) players"]
            XCTAssertTrue(option.waitForExistence(timeout: 5))
            option.tap()
            waitFor(humans, predicate: "label CONTAINS '\(count) players' OR value CONTAINS '\(count) players'")
        }
        let signIn = app.buttons["Sign in to Game Center"]
        reveal(signIn)
        XCTAssertTrue(signIn.exists)
        XCTAssertFalse(app.buttons["Find players"].isEnabled)
        // Neither sign-in nor matchmaking is invoked by this test.
        let ai = app.segmentedControls.buttons["Against AI"]
        reveal(ai, scrollingUp: false)
        ai.tap()
        XCTAssertTrue(app.buttons["Start game"].waitForExistence(timeout: 5))
    }

    func testInvalidImportRetainsDraftUntilCancelled() {
        app.buttons["Import deck text"].tap()
        let editor = app.textViews["Deck list text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let submit = app.buttons["Import and use deck"]
        XCTAssertFalse(submit.isEnabled)
        let deckName = app.textFields["Deck name"]
        let originalName = deckName.value as? String
        let draft = "this is not a deck entry"
        editor.tap()
        editor.typeText(draft)
        // A scroll dismisses the editor keyboard and exposes the import action.
        app.swipeUp()
        reveal(submit)
        submit.tap()
        let error = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Cannot import line 1:")).firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        reveal(editor, scrollingUp: false)
        XCTAssertEqual(editor.value as? String, draft)
        XCTAssertEqual(deckName.value as? String, originalName)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Invalid import retains draft"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["Cancel"].tap()
        waitFor(editor, predicate: "exists == false")
        XCTAssertTrue(app.textFields["ondevice.playerName"].exists)
        XCTAssertTrue(app.buttons["Import deck text"].exists)
    }

    func testMissingNativeLibraryReportsFailureAndKeepsSetupAvailable() {
        let playerName = app.textFields["ondevice.playerName"]
        playerName.tap()
        playerName.typeText("Setup Tester")
        let start = app.buttons["Start game"]
        reveal(start)
        waitFor(start, predicate: "enabled == true")
        start.tap()
        let failure = app.staticTexts[
            "The native XMage library is not linked. No remote engine or simulator was substituted."
        ]
        XCTAssertTrue(failure.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Unable to start local game"].exists)
        waitFor(start, predicate: "enabled == true")
        XCTAssertTrue(playerName.exists, "A failed start must leave the real setup visible.")
        XCTAssertFalse(app.staticTexts["Game started"].exists)
    }

    private func waitFor(_ element: XCUIElement, predicate: String,
                         file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, file: file, line: line)
    }

    private func reveal(_ element: XCUIElement, scrollingUp: Bool = true,
                        file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<5 {
            if element.exists && element.isHittable { return }
            if scrollingUp { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.exists && element.isHittable, "Expected accessible control: \(element)", file: file, line: line)
    }
}
