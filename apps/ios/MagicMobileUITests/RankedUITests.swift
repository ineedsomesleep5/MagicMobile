import XCTest

/// Quick Match, Ranked, the profile and the rank moments, in the tavern (Caleb, 2026-10-04).
/// Each screen is captured; no engine game is played here.
@MainActor
final class RankedUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    private func launch(_ environment: [String: String] = [:], settle: Bool = true) {
        app = XCUIApplication()
        UITestHarness.configure(app, extraArguments: ["-magicmobile.boardAppearance", "tavern"])
        environment.forEach { app.launchEnvironment[$0.key] = $0.value }
        app.launch()
        XCTAssertTrue(app.buttons["menu.play"].waitForExistence(timeout: 20))
        if settle { UITestHarness.settleFirstTouch(app) }
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Screens slide in: tap once the control has stopped moving.
    private func tapSteady(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 10), .completed, "\(element)", file: file, line: line)
        Thread.sleep(forTimeInterval: 0.45)
        element.tap()
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<6 where !(element.exists && element.isHittable) { app.swipeUp() }
    }

    func testPlayOffersQuickRankedAndCustom() {
        launch()
        tapSteady(app.buttons["menu.play"])
        for id in ["play.quick", "play.ranked", "play.custom"] {
            XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 10), id)
        }
        capture("Play mode chooser")
        tapSteady(app.buttons["play.quick"])
        XCTAssertTrue(app.buttons["quick.bracket"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["play.deck"].exists)
        capture("Quick Match")
        reveal(app.buttons["quick.start"])
        XCTAssertTrue(app.buttons["quick.start"].exists, "Quick Match starts from its own screen")
        capture("Quick Match bottom")
        tapSteady(app.buttons["lobby.back"])
        XCTAssertTrue(app.buttons["play.ranked"].waitForExistence(timeout: 5))
        tapSteady(app.buttons["play.ranked"])
        XCTAssertTrue(app.buttons["ranked.find"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["ranked.standing"].exists || app.descendants(matching: .any)["ranked.standing"].exists)
        capture("Ranked lobby")
        reveal(app.buttons["ranked.find"])
        capture("Ranked lobby bottom")
        tapSteady(app.buttons["lobby.back"])
        tapSteady(app.buttons["lobby.back"])
        XCTAssertTrue(app.buttons["menu.play"].waitForExistence(timeout: 5), "Back returns to the main menu")
    }

    func testQuickMatchBracketSheetExplainsTheDeck() {
        launch()
        tapSteady(app.buttons["menu.play"])
        tapSteady(app.buttons["play.quick"])
        let bracket = app.buttons["play.deck.bracket"]
        XCTAssertTrue(bracket.waitForExistence(timeout: 10))
        tapSteady(bracket)
        XCTAssertTrue(app.buttons["bracket.close"].waitForExistence(timeout: 5))
        capture("Bracket sheet")
        tapSteady(app.buttons["bracket.close"])
        XCTAssertTrue(app.buttons["quick.bracket"].waitForExistence(timeout: 5))
    }

    func testProfileShowsRankStatsAndHistory() {
        launch(["MAGICMOBILE_UI_TEST_RANK": "gold-2-3-1", "MAGICMOBILE_UI_TEST_MATCHES": "14"])
        let profile = app.buttons["menu.profile"]
        reveal(profile)
        XCTAssertTrue(profile.waitForExistence(timeout: 10))
        XCTAssertEqual(profile.value as? String, "Gold II")
        tapSteady(profile)
        XCTAssertTrue(app.descendants(matching: .any)["profile.season"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Gold II"].exists)
        capture("Profile top")
        reveal(app.descendants(matching: .any)["profile.achievements"])
        capture("Profile achievements")
        reveal(app.descendants(matching: .any)["profile.history"])
        capture("Profile history")
        tapSteady(app.buttons["lobby.back"])
        XCTAssertTrue(app.buttons["menu.play"].waitForExistence(timeout: 5))
    }

    func testRankUpAndDownMoments() {
        for kind in ["tierUp", "tierDown", "divisionUp", "divisionDown"] {
            launch(["MAGICMOBILE_UI_TEST_CEREMONY": kind])
            let ceremony = app.descendants(matching: .any)["rank.ceremony"]
            XCTAssertTrue(ceremony.waitForExistence(timeout: 10), kind)
            capture("\(kind) mid")
            let done = app.buttons["rank.ceremony.continue"]
            XCTAssertTrue(done.waitForExistence(timeout: 8), kind)
            capture("\(kind) settled")
            tapSteady(done)
            let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: ceremony)
            XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed, "\(kind) closes on Continue")
            app.terminate()
        }
    }
}
