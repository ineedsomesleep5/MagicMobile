import XCTest

/// The game history lives on the profile: recent games as cards that open the match dashboard when a detailed record
/// exists. These are the checks Deck Studio's Playtest chapter used to carry (it was removed from the deck workspace), run
/// from the profile with the same `--deck-history-layout-ui-test` fixture: eighteen development games, the first with a
/// sampled timeline, the second without.
@MainActor
final class ProfileHistoryUITests: XCTestCase {
    private var app: XCUIApplication!
    private let firstGame = "deckHistory.match.00000000-0000-0000-0000-000000000001.expand"
    private let secondGame = "deckHistory.match.00000000-0000-0000-0000-000000000002.expand"
    private let lastGame = "deckHistory.match.00000000-0000-0000-0000-000000000018.expand"

    override func setUpWithError() throws { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
        XCUIDevice.shared.orientation = .portrait
    }

    private func openProfile() {
        app = XCUIApplication()
        UITestHarness.configure(app, extraArguments: ["--deck-history-layout-ui-test", "-magicmobile.boardAppearance", "tavern"])
        app.launch()
        XCTAssertTrue(app.buttons["menu.profile"].waitForExistence(timeout: 20))
        UITestHarness.settleFirstTouch(app)
        let profile = app.buttons["menu.profile"]
        for _ in 0..<6 where !(profile.exists && profile.isHittable) { app.swipeUp() }
        tapSteady(profile, until: app.descendants(matching: .any)["profile.history"])
        XCTAssertTrue(app.descendants(matching: .any)["profile.history"].waitForExistence(timeout: 10))
    }

    private func tapSteady(_ element: XCUIElement, until next: XCUIElement? = nil) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "\(element)")
        Thread.sleep(forTimeInterval: 0.6)
        for _ in 0..<3 {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            guard let next, element.exists else { return }
            if next.waitForExistence(timeout: 4) { return }
        }
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }

    func testProfileHistoryOpensTheDashboardScrubsAndInspectsCards() throws {
        openProfile()
        let page = app.scrollViews["lobby.scroll"]
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        // The recording choices sit behind "History settings & privacy".
        let settings = app.buttons["deckHistory.settings"]
        UITestHarness.reveal(settings, in: page, swipes: 12)
        XCTAssertFalse(app.switches["Save detailed public game history"].exists, "Detailed recording choices stay behind History settings")
        settings.press(forDuration: 0.15)
        XCTAssertTrue(app.switches["Save AI game summaries"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["Save detailed public game history"].exists)
        settings.press(forDuration: 0.15)

        let first = app.buttons[firstGame]
        UITestHarness.reveal(first, in: page, swipes: 12, upward: false)
        XCTAssertTrue(first.label.contains("Fixture rival"), first.label)
        XCTAssertTrue(first.label.contains("Token Triumph"), first.label)
        attach("Profile recent games fixture")
        first.press(forDuration: 0.15)
        let dashboard = app.scrollViews["deckHistory.dashboard.scroll"]
        let closeDashboard = app.buttons["deckHistory.dashboard.close"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 10))
        XCTAssertTrue(closeDashboard.isHittable)
        XCTAssertFalse(app.buttons["lobby.back"].isHittable, "The match dashboard covers the profile")
        attach("Full-screen match overview portrait fixture")
        let lifeChart = app.otherElements["deckHistory.chart.life"].firstMatch
        let boardChart = app.otherElements["deckHistory.chart.battlefield"].firstMatch
        XCTAssertTrue(lifeChart.exists)
        XCTAssertTrue(boardChart.exists)
        XCTAssertGreaterThan(boardChart.frame.minY, lifeChart.frame.maxY, "Portrait charts stack without squeezing their plots")
        let previous = app.buttons["deckHistory.timeline.previous"]
        center(previous, in: dashboard)
        XCTAssertTrue(previous.isEnabled)
        previous.press(forDuration: 0.15)
        XCTAssertTrue(app.buttons["deckHistory.timeline.next"].isEnabled)
        let inspect = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "deckHistory.event.", ".inspect")).firstMatch
        center(inspect, in: dashboard)
        attach("Public history dashboard portrait fixture")
        inspect.press(forDuration: 0.15)
        XCTAssertTrue(app.buttons["deckStudio.inspector.close"].waitForExistence(timeout: 5))
        app.buttons["deckStudio.inspector.close"].press(forDuration: 0.15)
        XCTAssertTrue((app.sliders["deckHistory.timeline.scrubber"].value as? String)?.contains("observation 3 of") == true,
                      "Closing card inspection must preserve the selected observation")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(closeDashboard.waitForExistence(timeout: 5))
        center(lifeChart, in: dashboard)
        XCTAssertLessThan(abs(lifeChart.frame.midY - boardChart.frame.midY), 5, "Landscape charts sit side by side")
        XCTAssertGreaterThan(boardChart.frame.minX, lifeChart.frame.maxX)
        attach("Full-screen landscape chart placement fixture")
        let scrubber = app.sliders["deckHistory.timeline.scrubber"]
        center(scrubber, in: dashboard)
        XCTAssertTrue(scrubber.isHittable)
        // Drag the thumb itself to the start, as a person does (adjust(toNormalizedSliderPosition:) is unreliable on iOS 27).
        let thumb = scrubber.coordinate(withNormalizedOffset: CGVector(dx: scrubber.normalizedSliderPosition, dy: 0.5))
        thumb.press(forDuration: 0.3, thenDragTo: scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)),
                    withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue((scrubber.value as? String)?.contains("observation 1 of") == true)
        attach("Public history dashboard landscape fixture")
        closeDashboard.press(forDuration: 0.15)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(page.waitForExistence(timeout: 5))

        // A game saved without a timeline still opens, and says so.
        let legacy = app.buttons[secondGame]
        UITestHarness.reveal(legacy, in: page, swipes: 12)
        legacy.press(forDuration: 0.15)
        XCTAssertTrue(dashboard.waitForExistence(timeout: 5))
        let missing = app.staticTexts["Detailed history was not recorded for this match."]
        center(missing, in: dashboard)
        XCTAssertTrue(missing.isHittable)
        closeDashboard.press(forDuration: 0.15)
    }

    func testProfileHistoryListShowsMoreGamesAndFiltersByResult() throws {
        openProfile()
        let page = app.scrollViews["lobby.scroll"]
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        let more = app.buttons["profile.games.more"]
        UITestHarness.reveal(more, in: page, swipes: 14)
        XCTAssertFalse(app.buttons[lastGame].exists, "Six games show first")
        more.press(forDuration: 0.15)
        let last = app.buttons[lastGame]
        UITestHarness.reveal(last, in: page, swipes: 14)
        XCTAssertTrue(last.label.contains("Token Triumph"), last.label)
        attach("Profile history with every fixture game")
        // Wins only: the 18 fixture games alternate, so nine are wins and the first loss (game 2) disappears.
        let wins = app.buttons["profile.filter.result.wins"]
        UITestHarness.reveal(wins, in: page, swipes: 14, upward: false)
        wins.press(forDuration: 0.15)
        XCTAssertFalse(app.buttons[secondGame].waitForExistence(timeout: 2), "Losses leave the list when Wins is chosen")
        XCTAssertTrue(app.buttons[firstGame].waitForExistence(timeout: 5))
    }

    private func center(_ element: XCUIElement, in scroll: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        var reach: CGFloat = 0.35
        var lastDirection: CGFloat = 0
        var trace: [String] = []
        for _ in 0..<16 {
            let visible = scroll.frame.intersection(app.frame).insetBy(dx: 0, dy: 50)
            if element.exists && element.isHittable && visible.contains(element.frame) { return }
            let offset = element.exists ? visible.midY - element.frame.midY : -visible.height
            // A correction that crosses the target means the last drag moved further than asked: halve the next one.
            let direction: CGFloat = offset < 0 ? -1 : 1
            if lastDirection != 0 && direction != lastDirection { reach = max(reach / 2, 0.05) }
            lastDirection = direction
            let limit = visible.height * (element.exists ? reach : 0.25)
            let shift = max(-limit, min(limit, offset))
            trace.append("\(Int(element.exists ? element.frame.midY : -1))→\(Int(shift))")
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5))
            // Hold before lifting so the list stops where the drag ends (a release at speed flings it on iOS 27).
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: shift)), withVelocity: .default, thenHoldForDuration: 0.3)
        }
        XCTFail("Could not center \(element.identifier); midY→drag: \(trace.joined(separator: ", "))", file: file, line: line)
    }
}
