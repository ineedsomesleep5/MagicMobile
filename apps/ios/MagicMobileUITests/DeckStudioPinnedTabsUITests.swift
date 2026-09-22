import XCTest

@MainActor
final class DeckStudioPinnedTabsUITests: XCTestCase {
    func testPublicHistoryDashboardScrubsAndInspectsCards() throws {
        let app = XCUIApplication()
        continueAfterFailure = false
        UITestHarness.configure(app, extraArguments: ["--deck-history-layout-ui-test"])
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.buttons["menu.decks"].waitForExistence(timeout: 20))
        app.buttons["menu.decks"].press(forDuration: 0.15)
        let search = app.textFields["deckStudio.library.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("Token Triumph\n")
        let deck = app.buttons["deckStudio.deck.precon:token-triumph"]
        XCTAssertTrue(deck.waitForExistence(timeout: 10))
        if !deck.isHittable { app.swipeUp() }
        deck.press(forDuration: 0.15)
        XCTAssertTrue(app.buttons["Playtest"].waitForExistence(timeout: 10))
        app.buttons["Playtest"].press(forDuration: 0.15)
        let history = app.scrollViews["deckStudio.playtest.list"]
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        let settings = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@",
            "deckHistory.settings", "History settings & privacy")).firstMatch
        XCTAssertTrue(settings.exists)
        XCTAssertFalse(app.switches["Save detailed public game history"].exists,
                       "Detailed recording choices should be behind History settings")
        settings.press(forDuration: 0.15)
        XCTAssertTrue(app.switches["Save AI game summaries"].exists)
        XCTAssertTrue(app.switches["Save detailed public game history"].exists)
        settings.press(forDuration: 0.15)
        let first = app.buttons["deckHistory.match.00000000-0000-0000-0000-000000000001.expand"]
        UITestHarness.reveal(first, in: history, swipes: 6)
        XCTAssertTrue(first.label.contains("Aurelia, the Warleader"))
        XCTAssertTrue(first.label.contains("Fixture rival, versus your deck Token Triumph"))
        let summary = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        summary.name = "Compact opponent-led history fixture"; summary.lifetime = .keepAlways; add(summary)
        first.press(forDuration: 0.15)
        let dashboard = app.scrollViews["deckHistory.dashboard.scroll"]
        let closeDashboard = app.buttons["deckHistory.dashboard.close"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 10))
        XCTAssertTrue(closeDashboard.isHittable)
        XCTAssertFalse(app.buttons["Playtest"].isHittable, "Match review replaces the editor with a full-screen dashboard")
        let overview = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        overview.name = "Full-screen match overview portrait fixture"; overview.lifetime = .keepAlways; add(overview)
        let lifeChart = app.otherElements["deckHistory.chart.life"].firstMatch
        let boardChart = app.otherElements["deckHistory.chart.battlefield"].firstMatch
        XCTAssertTrue(lifeChart.exists)
        XCTAssertTrue(boardChart.exists)
        XCTAssertGreaterThan(boardChart.frame.minY, lifeChart.frame.maxY,
                             "Portrait charts stack without squeezing their plots")
        let previous = app.buttons["deckHistory.timeline.previous"]
        center(previous, in: dashboard, app: app)
        XCTAssertTrue(previous.isEnabled)
        previous.press(forDuration: 0.15)
        XCTAssertTrue(app.buttons["deckHistory.timeline.next"].isEnabled)
        let inspect = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "deckHistory.event.", ".inspect")).firstMatch
        center(inspect, in: dashboard, app: app)
        let portrait = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        portrait.name = "Public history dashboard portrait fixture"; portrait.lifetime = .keepAlways; add(portrait)
        inspect.press(forDuration: 0.15)
        XCTAssertTrue(app.buttons["deckStudio.inspector.close"].waitForExistence(timeout: 5))
        app.buttons["deckStudio.inspector.close"].press(forDuration: 0.15)
        XCTAssertTrue((app.sliders["deckHistory.timeline.scrubber"].value as? String)?.contains("observation 3 of") == true,
                      "Closing card inspection must preserve the selected observation")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(closeDashboard.waitForExistence(timeout: 5))
        center(lifeChart, in: dashboard, app: app)
        XCTAssertLessThan(abs(lifeChart.frame.midY - boardChart.frame.midY), 5,
                          "Landscape charts sit side by side")
        XCTAssertGreaterThan(boardChart.frame.minX, lifeChart.frame.maxX)
        let charts = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        charts.name = "Full-screen landscape chart placement fixture"; charts.lifetime = .keepAlways; add(charts)
        let scrubber = app.sliders["deckHistory.timeline.scrubber"]
        center(scrubber, in: dashboard, app: app)
        XCTAssertTrue(scrubber.isHittable)
        scrubber.adjust(toNormalizedSliderPosition: 0)
        XCTAssertTrue((scrubber.value as? String)?.contains("observation 1 of") == true)
        let landscape = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        landscape.name = "Public history dashboard landscape fixture"; landscape.lifetime = .keepAlways; add(landscape)
        closeDashboard.press(forDuration: 0.15)
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        let legacy = app.buttons["deckHistory.match.00000000-0000-0000-0000-000000000002.expand"]
        center(legacy, in: history, app: app)
        legacy.press(forDuration: 0.15)
        XCTAssertTrue(dashboard.waitForExistence(timeout: 5))
        let missing = app.staticTexts["Detailed history was not recorded for this match."]
        center(missing, in: dashboard, app: app)
        XCTAssertTrue(missing.isHittable)
        closeDashboard.press(forDuration: 0.15)
    }

    private func center(_ element: XCUIElement, in scroll: XCUIElement, app: XCUIApplication,
                        file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<16 {
            let visible = scroll.frame.intersection(app.frame).insetBy(dx: 0, dy: 50)
            if element.exists && element.isHittable && visible.contains(element.frame) { return }
            let shift = element.exists
                ? max(-visible.height * 0.35, min(visible.height * 0.35, visible.midY - element.frame.midY))
                : -visible.height * 0.25
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: shift)))
        }
        XCTFail("Could not center \(element.identifier)", file: file, line: line)
    }
    func testPortraitPlaytestHistoryScrollsHeaderAwayAndPinsWorkspaceTabs() throws {
        let app = XCUIApplication()
        continueAfterFailure = false
        UITestHarness.configure(app, extraArguments: ["--deck-history-layout-ui-test"])
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }

        XCTAssertTrue(app.buttons["menu.decks"].waitForExistence(timeout: 20))
        app.buttons["menu.decks"].press(forDuration: 0.15)
        let search = app.textFields["deckStudio.library.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("Token Triumph\n")
        let deck = app.buttons["deckStudio.deck.precon:token-triumph"]
        XCTAssertTrue(deck.waitForExistence(timeout: 10))
        if !deck.isHittable { app.swipeUp() }
        deck.press(forDuration: 0.15)

        let header = app.otherElements["deckStudio.deckHeader"]
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertTrue(header.isHittable)
        XCTAssertEqual(app.buttons["Deck details"].value as? String, "Expanded")
        XCTAssertTrue(app.staticTexts["Included / read-only"].isHittable,
                      "The expanded commander header should be visible before scrolling")
        let initialHeader = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        initialHeader.name = "Expanded commander header before Playtest scroll"
        initialHeader.lifetime = .keepAlways
        add(initialHeader)
        app.buttons["Playtest"].press(forDuration: 0.15)
        XCTAssertTrue(app.buttons["Playtest"].isSelected, "Playtest must become the active workspace after tapping its tab")
        let history = app.scrollViews["deckStudio.playtest.list"]
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Development fixture · not saved"].waitForExistence(timeout: 10))
        let last = app.buttons["deckHistory.match.00000000-0000-0000-0000-000000000018.expand"]
        XCTAssertFalse(last.isHittable)
        history.swipeUp()
        history.swipeUp()
        XCTAssertFalse(header.isHittable)
        let pinnedTabY = app.buttons["Playtest"].frame.midY
        UITestHarness.reveal(last, in: history, swipes: 10)
        XCTAssertFalse(header.isHittable, "The expanded header must scroll away with history")
        for title in ["Cards", "Ideas", "Analysis", "Playtest"] {
            XCTAssertTrue(app.buttons[title].isHittable, "Workspace tab must remain pinned: \(title)")
        }
        XCTAssertLessThan(abs(app.buttons["Playtest"].frame.midY - pinnedTabY), 8,
                          "Workspace tabs must stay at the same top position while history scrolls")
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Portrait Playtest history with pinned tabs"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPortraitCardsScrollHeaderAwayAndKeepWorkspaceTabsReachable() throws {
        let app = XCUIApplication()
        continueAfterFailure = false
        UITestHarness.configure(app)
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }

        XCTAssertTrue(app.buttons["menu.decks"].waitForExistence(timeout: 20))
        app.buttons["menu.decks"].press(forDuration: 0.15)
        let librarySearch = app.textFields["deckStudio.library.search"]
        XCTAssertTrue(librarySearch.waitForExistence(timeout: 10))
        librarySearch.tap()
        librarySearch.typeText("Token Triumph\n")
        let deck = app.buttons["deckStudio.deck.precon:token-triumph"]
        XCTAssertTrue(deck.waitForExistence(timeout: 10))
        if !deck.isHittable { app.swipeUp() }
        deck.press(forDuration: 0.15)

        let cards = app.scrollViews["deckStudio.cards.list"]
        XCTAssertTrue(cards.waitForExistence(timeout: 10))
        let search = app.textFields["deckStudio.cards.search"]
        XCTAssertTrue(search.isHittable)
        cards.swipeUp()
        cards.swipeUp()
        XCTAssertFalse(search.isHittable, "Search should scroll away with the commander header")
        XCTAssertFalse(app.otherElements["deckStudio.deckHeader"].isHittable)
        for title in ["Cards", "Ideas", "Analysis", "Playtest"] {
            XCTAssertTrue(app.buttons[title].isHittable, "Workspace tab must remain reachable: \(title)")
        }
        let visibleRows = cards.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Inspect "))
            .allElementsBoundByIndex.filter(\.isHittable)
        XCTAssertGreaterThanOrEqual(visibleRows.count, 4)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Portrait deck with pinned tabs and scrolling header"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["Analysis"].press(forDuration: 0.15)
        XCTAssertTrue(app.staticTexts["Your deck at a glance"].waitForExistence(timeout: 5))
    }
}
