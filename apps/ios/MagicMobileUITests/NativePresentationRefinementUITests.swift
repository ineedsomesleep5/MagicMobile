import XCTest

@MainActor
final class NativePresentationRefinementUITests: XCTestCase {
    private func launch(error: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        continueAfterFailure = false
        app.launchEnvironment["MAGICMOBILE_UI_TEST_PREFERENCES"] = UUID().uuidString
        if error { app.launchEnvironment["MAGICMOBILE_UI_TEST_ENGINE_ERROR"] = "1" }
        app.launchArguments = ["--ondevice-setup-ui-test", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.buttons["menu.play"].waitForExistence(timeout: 20))
        return app
    }

    func testNoReportLinkWithoutIncidentAndMenuRemainsReachable() {
        let app = launch()
        defer { app.terminate() }
        let menu = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        menu.name = "Edge-to-edge native menu"
        menu.lifetime = .keepAlways
        add(menu)
        app.buttons["menu.play"].tap()
        XCTAssertTrue(app.buttons["Main menu"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertFalse(app.buttons["ondevice.diagnostics"].exists)
        app.swipeDown()
        app.buttons["Main menu"].tap()
        XCTAssertTrue(app.buttons["menu.play"].waitForExistence(timeout: 5))
    }

    func testErrorNotificationExpiresWithoutDeletingReport() {
        let app = launch(error: true)
        defer { app.terminate() }
        let dismiss = app.buttons["ondevice.dismissNotification"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
        let expired = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: dismiss)
        XCTAssertEqual(XCTWaiter.wait(for: [expired], timeout: 10), .completed)
        app.buttons["menu.play"].tap()
        XCTAssertTrue(app.buttons["Main menu"].waitForExistence(timeout: 5))
        let report = app.buttons["ondevice.diagnostics"]
        for _ in 0..<4 where !report.isHittable { app.swipeUp() }
        XCTAssertTrue(report.isHittable)
        report.tap()
        XCTAssertTrue(app.buttons["ondevice.shareReport"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.swipeDown()
        app.buttons["Main menu"].tap()
        XCTAssertTrue(app.buttons["menu.play"].waitForExistence(timeout: 5))
    }
}
