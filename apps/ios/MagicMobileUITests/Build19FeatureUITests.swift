import XCTest

/// DEBUG presentation fixtures and the on-device menus for build 19: Sound Lab, concede,
/// spectating, the opening hand, attachment inspection and deck covers. These are UI
/// captures, NOT real XMage gameplay; the concede engine path is covered by RealConcedeTests.
@MainActor
final class Build19FeatureUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    private func launch(preview: String? = nil, environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        UITestHarness.configure(app, preview: preview, extraArguments: ["-magicmobile.portraitModeEnabled", "YES"])
        environment.forEach { app.launchEnvironment[$0.key] = $0.value }
        app.launch()
        return app
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testSoundLabOpensFromSettingsWithEveryGroupAndCredits() {
        let app = launch()
        let settings = app.buttons["menu.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        let soundLab = app.buttons["settings.soundLab"]
        XCTAssertTrue(soundLab.waitForExistence(timeout: 10))
        soundLab.tap()
        XCTAssertTrue(app.buttons["soundlab.done"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["soundlab.music.menu.shuffle"].exists)
        capture(app, "sound-lab-music")
        let chip = app.buttons["soundlab.play.cast-red"]
        for _ in 0..<6 where !chip.isHittable { app.swipeUp() }
        XCTAssertTrue(chip.isHittable, "every sound can be auditioned")
        chip.tap()
        let spells = app.switches["soundlab.category.spells"]
        XCTAssertTrue(spells.exists)
        capture(app, "sound-lab-effects")
        for _ in 0..<8 where !app.otherElements["soundlab.credits"].exists { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["Licensed under Creative Commons: By Attribution 4.0 License"].exists,
                      "the music license's attribution is shown")
        capture(app, "sound-lab-credits")
        app.buttons["soundlab.done"].tap()
        XCTAssertFalse(app.buttons["soundlab.done"].waitForExistence(timeout: 2))
    }

    func testDeckStudioCoversNameTheCommander() {
        let app = launch()
        XCTAssertTrue(app.buttons["menu.decks"].waitForExistence(timeout: 20))
        app.buttons["menu.decks"].press(forDuration: 0.15)
        XCTAssertTrue(app.buttons["deckStudio.deck.precon:token-triumph"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["A new story to build"].exists, "covers without art show the deck, not a blank")
        capture(app, "deck-studio-covers")
    }

    func testConcedeAsksFirstAndExplainsTheResult() {
        let app = launch(preview: "ai-thinking")
        let controls = app.buttons["Game controls"]
        XCTAssertTrue(controls.waitForExistence(timeout: 20))
        controls.press(forDuration: 0.15)
        XCTAssertTrue(app.buttons["Game Settings"].waitForExistence(timeout: 5))
        app.buttons["Game Settings"].press(forDuration: 0.15)
        let concede = app.buttons["board.menu.concede"]
        XCTAssertTrue(concede.waitForExistence(timeout: 10))
        XCTAssertTrue(concede.isEnabled, "the fixture offers XMage's concede action")
        concede.tap() // XCUITest scrolls the menu to the button
        // Newer iOS shows the confirmation as a popover on the button. Either way it
        // adds a second, destructive "Concede" that is not the menu's own button.
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Concede", "board.menu.concede")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "conceding asks first")
        capture(app, "concede-confirmation")
    }

    func testSpectatorBarReplacesYourControls() {
        let app = launch(preview: "spectating")
        XCTAssertTrue(app.otherElements["board.spectator"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["board.spectator.leave"].exists)
        XCTAssertFalse(app.buttons["Pass Priority"].exists, "a spectator has no game controls")
        capture(app, "spectating")
    }

    func testOpeningHandFansTheHandWithMulliganAndKeep() {
        let app = launch(preview: "opening-hand")
        XCTAssertTrue(app.otherElements["board.opening"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Mulligan to 6 cards?"].exists)
        XCTAssertTrue(app.buttons["board.opening.keep"].isHittable)
        XCTAssertTrue(app.buttons["board.opening.mulligan"].isHittable)
        capture(app, "opening-hand")
        app.buttons["board.opening.keep"].tap()
        XCTAssertTrue(app.staticTexts["preview.captured-command"].waitForExistence(timeout: 5)
                      || app.otherElements["preview.captured-command"].exists, "keeping sends XMage's own answer")
    }

    func testInspectorListsEveryAttachmentWithItsText() {
        let app = launch(preview: "attached-permanents", environment: ["MAGICMOBILE_PREVIEW_INSPECT": "ai-1-preview-creature-0"])
        let equipment = app.descendants(matching: .any)["inspector.attachment.attached-equipment"]
        XCTAssertTrue(equipment.waitForExistence(timeout: 20), "the creature lists its Equipment")
        XCTAssertTrue(equipment.label.contains("Equipped creature gets +1/+1"), "with its rules text")
        XCTAssertTrue(app.staticTexts["ATTACHED · 3"].exists, "both Auras and the Equipment")
        capture(app, "inspector-attachments")
    }
}
