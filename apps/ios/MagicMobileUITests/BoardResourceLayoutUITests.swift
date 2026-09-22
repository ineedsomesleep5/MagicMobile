import XCTest

/// Actual UI checks of opt-in presentation fixtures. No XMage game is running.
@MainActor
final class BoardResourceLayoutUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 240
    }

    override func tearDownWithError() throws {
        app?.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    private func launch(mode: String, portrait: Bool) {
        app = XCUIApplication()
        UITestHarness.configure(app, preview: "crowded-battlefield",
                                extraArguments: ["-magicmobile.portraitModeEnabled", "YES"])
        app.launchEnvironment["MAGICMOBILE_BOARD_RESOURCE_LAYOUT_UI_TEST"] = mode
        XCUIDevice.shared.orientation = portrait ? .portrait : .landscapeLeft
        app.launch()
        XCTAssertTrue(app.staticTexts["DEVELOPMENT FIXTURE · NO ENGINE"].waitForExistence(timeout: 20))
        rotate(portrait: portrait)
    }

    private func rotate(portrait: Bool) {
        XCUIDevice.shared.orientation = portrait ? .portrait : .landscapeLeft
        let orientation = NSPredicate { [self] _, _ in
            let frame = app.frame
            return frame.width > 0 && frame.height > 0 &&
                (portrait ? frame.height > frame.width : frame.width > frame.height)
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: orientation, object: app)], timeout: 10), .completed)
    }

    private func cards(_ prefix: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
    }

    private func card(_ prefix: String) -> XCUIElement { cards(prefix).firstMatch }

    private func resourceRow(containing prefix: String) -> XCUIElement {
        let matching = app.scrollViews.containing(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).allElementsBoundByIndex
        XCTAssertFalse(matching.isEmpty, "Missing scroll row for \(prefix)")
        return matching.min(by: { $0.frame.height < $1.frame.height }) ?? app.scrollViews.firstMatch
    }

    private func dragArtworkLeft(in row: XCUIElement, cardPrefix: String) {
        let visible = cards(cardPrefix).allElementsBoundByIndex.filter {
            $0.isHittable && row.frame.intersection($0.frame).width > 25 && row.frame.intersection($0.frame).height > 25
        }
        guard let source = visible.max(by: { $0.frame.midX < $1.frame.midX }) else {
            XCTFail("No visible card artwork in \(cardPrefix)"); return
        }
        let clipped = source.frame.intersection(row.frame).intersection(app.frame)
        let start = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: clipped.midX, dy: clipped.midY))
        let distance = min(row.frame.width * 0.6, clipped.midX - row.frame.minX - 8)
        XCTAssertGreaterThan(distance, 20)
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -distance, dy: 0)))
    }

    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }

    func testLandscapeRocksUseRightResourcesForBothPlayersAndRowsScrollIndependently() {
        launch(mode: "rocks", portrait: false)
        for side in ["your", "opponent"] {
            let rock = card("card-\(side)-lands-fixture-rock-0-")
            let creature = card("card-\(side)-board-silvercoat-lion-")
            XCTAssertTrue(rock.waitForExistence(timeout: 5))
            XCTAssertTrue(creature.waitForExistence(timeout: 5))
            XCTAssertGreaterThan(rock.frame.midX, creature.frame.midX + 20)
            XCTAssertFalse(card("card-\(side)-board-fixture-rock-0-").exists)
            XCTAssertEqual(cards("card-\(side)-lands-fixture-rock-0-").count, 1)
            for name in ["dimir-signet", "talisman-of-dominance", "treasure-token", "ashnod-s-altar"] {
                XCTAssertEqual(cards("card-\(side)-lands-\(name)-").count, 1, "\(name) must use the resource lane")
                XCTAssertFalse(card("card-\(side)-board-\(name)-").exists)
            }
        }
        let tappedRock = card("card-your-lands-fixture-rock-1-")
        XCTAssertTrue(tappedRock.label.contains("tapped"))

        let landPrefix = "card-your-lands-fixture-land-"
        let rockPrefix = "card-your-lands-fixture-rock-"
        let landRow = resourceRow(containing: landPrefix)
        let rockRow = resourceRow(containing: rockPrefix)
        XCTAssertGreaterThan(abs(landRow.frame.midY - rockRow.frame.midY), 20)
        let firstLand = card("card-your-lands-fixture-land-0-")
        let firstRock = card("card-your-lands-fixture-rock-0-")
        let landX = firstLand.frame.minX
        let rockX = firstRock.frame.minX
        dragArtworkLeft(in: landRow, cardPrefix: "card-your-lands-")
        XCTAssertLessThan(firstLand.frame.minX, landX - 15)
        XCTAssertEqual(firstRock.frame.minX, rockX, accuracy: 3, "Land scrolling must not move rocks")
        let landAfter = firstLand.frame.minX
        dragArtworkLeft(in: rockRow, cardPrefix: "card-your-lands-")
        XCTAssertLessThan(firstRock.frame.minX, rockX - 15)
        XCTAssertEqual(firstLand.frame.minX, landAfter, accuracy: 3, "Rock scrolling must not move lands")
        XCTAssertFalse(app.staticTexts["preview.captured-command"].exists, "Artwork drags must not activate mana")

        let tappable = cards(rockPrefix).allElementsBoundByIndex.first { $0.isHittable && rockRow.frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
        guard let tappable else { XCTFail("No rock remains tappable after scrolling"); return }
        tappable.press(forDuration: 0.15)
        XCTAssertTrue(tappable.label.hasSuffix(", selected"))
        tappable.press(forDuration: 0.7)
        XCTAssertFalse(app.buttons["Close card"].exists, "Held inspection closes on release")
        capture("resource-rocks-landscape")
    }

    func testLandscapeWithoutRocksUsesTwoIndependentlyScrollableLandRows() {
        launch(mode: "lands-only", portrait: false)
        XCTAssertFalse(card("card-your-lands-sol-ring-").exists)
        let prefix = "card-your-lands-fixture-land-"
        let rows = app.scrollViews.containing(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
            .allElementsBoundByIndex.sorted { $0.frame.midY < $1.frame.midY }
        XCTAssertEqual(rows.count, 2, "Lands need two independently scrolling viewports")
        guard rows.count == 2 else { return }
        let firstRow = rows[0]
        let secondRow = rows[1]
        XCTAssertGreaterThan(abs(firstRow.frame.midY - secondRow.frame.midY), 20)
        let available = cards(prefix).allElementsBoundByIndex
        guard let first = available.first(where: { $0.isHittable && firstRow.frame.intersects($0.frame) }),
              let second = available.first(where: { $0.isHittable && secondRow.frame.intersects($0.frame) }) else {
            XCTFail("Both land rows need visible cards"); return
        }
        let firstX = first.frame.minX
        let secondX = second.frame.minX
        dragArtworkLeft(in: firstRow, cardPrefix: "card-your-lands-")
        XCTAssertLessThan(first.frame.minX, firstX - 15)
        XCTAssertEqual(second.frame.minX, secondX, accuracy: 3)
        let firstAfter = first.frame.minX
        dragArtworkLeft(in: secondRow, cardPrefix: "card-your-lands-")
        XCTAssertLessThan(second.frame.minX, secondX - 15)
        XCTAssertEqual(first.frame.minX, firstAfter, accuracy: 3)
        capture("resource-land-only-landscape")
    }

    func testPortraitEquipmentForegroundAndRotationKeepsBothPlayersRocksUnique() {
        launch(mode: "rocks", portrait: true)
        for side in ["your", "opponent"] {
            let sword = card("card-\(side)-board-fixture-sword-")
            let oath = card("card-\(side)-board-fixture-oath-")
            let creature = card("card-\(side)-board-silvercoat-lion-")
            XCTAssertTrue(sword.waitForExistence(timeout: 5))
            XCTAssertTrue(oath.waitForExistence(timeout: 5))
            XCTAssertEqual(sword.frame.midY, creature.frame.midY, accuracy: 12)
            if side == "your" { XCTAssertLessThan(sword.frame.midY, oath.frame.midY) }
            else { XCTAssertGreaterThan(sword.frame.midY, oath.frame.midY) }
        }
        for portrait in [true, false, true] {
            rotate(portrait: portrait)
            for side in ["your", "opponent"] {
                let active = "card-\(side)-\(portrait ? "board" : "lands")-fixture-rock-0-"
                let inactive = "card-\(side)-\(portrait ? "lands" : "board")-fixture-rock-0-"
                XCTAssertEqual(cards(active).count, 1, "Rock missing or duplicated after rotation")
                XCTAssertFalse(card(inactive).exists, "Rock retained in its old lane")
            }
            capture("resource-rotation-\(portrait ? "portrait" : "landscape")")
        }
        XCTAssertFalse(app.staticTexts["preview.captured-command"].exists)
    }
}
