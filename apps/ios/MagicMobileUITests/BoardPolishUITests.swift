import XCTest

/// DEBUG, unlinked presentation target only. These are actual simulator UI captures
/// of supplied design fixtures, NOT real XMage gameplay, legality, privacy, or device acceptance.
/// Artwork is deliberately replaced with placeholders; review layout, not downloaded art.
@MainActor
final class BoardPolishUITests: XCTestCase {
    private var app: XCUIApplication?
    private var currentCapture = "board-polish"
    private var stackDragX: CGFloat = 0.9

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 420
    }

    override func tearDownWithError() throws {
        if let app {
            capture(app, name: currentCapture + "-final")
            app.terminate()
        }
        app = nil
        XCUIDevice.shared.orientation = .portrait
    }

    // Independent cases keep one failed control from hiding the remaining surfaces.
    func testPortraitCrowdedBattlefield() { runMatrix(portrait: true, selectedFixtures: ["crowded-battlefield"]) }
    func testLandscapeCrowdedBattlefield() { runMatrix(portrait: false, selectedFixtures: ["crowded-battlefield"]) }
    func testPortraitOffscreenCombatInspection() { runMatrix(portrait: true, selectedFixtures: ["combat-arrows"]) }
    func testLandscapeOffscreenCombatInspection() { runMatrix(portrait: false, selectedFixtures: ["combat-arrows"]) }
    func testPortraitManaPayment() { runMatrix(portrait: true, selectedFixtures: ["mana-payment-prompt"]) }
    func testLandscapeManaPayment() { runMatrix(portrait: false, selectedFixtures: ["mana-payment-prompt"]) }
    func testPortraitOpponentFocus() { runMatrix(portrait: true, selectedFixtures: ["four-player-focus"]) }
    func testLandscapeOpponentFocus() { runMatrix(portrait: false, selectedFixtures: ["four-player-focus"]) }
    func testPortraitPlayerTarget() { runMatrix(portrait: true, selectedFixtures: ["player-target-prompt"]) }
    func testLandscapePlayerTarget() { runMatrix(portrait: false, selectedFixtures: ["player-target-prompt"]) }
    func testPortraitZoneInspection() { runMatrix(portrait: true, selectedFixtures: ["zone-inspection"]) }
    func testLandscapeZoneInspection() { runMatrix(portrait: false, selectedFixtures: ["zone-inspection"]) }
    func testPortraitHandInspection() { runMatrix(portrait: true, selectedFixtures: ["full-hand-inspection"]) }
    func testLandscapeHandInspection() { runMatrix(portrait: false, selectedFixtures: ["full-hand-inspection"]) }
    func testPortraitHandArtworkScroll() { runMatrix(portrait: true, selectedFixtures: ["normal-battlefield"]) }
    func testLandscapeHandArtworkScroll() { runMatrix(portrait: false, selectedFixtures: ["normal-battlefield"]) }
    func testPortraitLargeHandScrubber() { runMatrix(portrait: true, selectedFixtures: ["hand-scrubber"]) }
    func testLandscapeLargeHandScrubber() { runMatrix(portrait: false, selectedFixtures: ["hand-scrubber"]) }
    func testPortraitHandDrag() { runMatrix(portrait: true, selectedFixtures: ["hand-drag"]) }
    func testLandscapeHandDrag() { runMatrix(portrait: false, selectedFixtures: ["hand-drag"]) }
    func testPortraitCardBackedAbilityChoice() { runMatrix(portrait: true, selectedFixtures: ["ability-choice"]) }
    func testLandscapeCardBackedAbilityChoice() { runMatrix(portrait: false, selectedFixtures: ["ability-choice"]) }
    func testPortraitPhaseAnnouncement() { runMatrix(portrait: true, selectedFixtures: ["phase-announcement"]) }
    func testLandscapePhaseAnnouncement() { runMatrix(portrait: false, selectedFixtures: ["phase-announcement"]) }
    func testPortraitLifeChange() { runMatrix(portrait: true, selectedFixtures: ["life-change"]) }
    func testLandscapeLifeChange() { runMatrix(portrait: false, selectedFixtures: ["life-change"]) }
    func testPortraitMixedChoices() { runMatrix(portrait: true, selectedFixtures: ["mixed-card-choice"]) }
    func testLandscapeMixedChoices() { runMatrix(portrait: false, selectedFixtures: ["mixed-card-choice"]) }
    func testPortraitScryChoices() { runMatrix(portrait: true, selectedFixtures: ["scry-choice"]) }
    func testLandscapeScryChoices() { runMatrix(portrait: false, selectedFixtures: ["scry-choice"]) }
    func testPortraitLibraryChoices() { runMatrix(portrait: true, selectedFixtures: ["library-choice", "empty-library-choice"]) }
    func testLandscapeLibraryChoices() { runMatrix(portrait: false, selectedFixtures: ["library-choice", "empty-library-choice"]) }

    func testPortraitStackPresentation() {
        runMatrix(portrait: true, selectedFixtures: ["stack-response-prompt"])
    }

    func testPortraitStackArtworkScroll() {
        stackDragX = 0.25
        runMatrix(portrait: true, selectedFixtures: ["stack-response-prompt"])
    }

    func testLandscapeStackPresentation() {
        runMatrix(portrait: false, selectedFixtures: ["stack-response-prompt"])
    }

    func testRotateToLandscapeStackPresentation() {
        runMatrix(portrait: false, selectedFixtures: ["stack-response-prompt"], rotateDuringTest: true)
    }

    private func runMatrix(portrait: Bool, selectedFixtures: [String], rotateDuringTest: Bool = false) {
        for fixture in selectedFixtures {
            XCTContext.runActivity(named: "\(portrait ? "portrait" : "landscape") / \(fixture)") { _ in
                app?.terminate()
                let application = XCUIApplication()
                app = application
                currentCapture = "\(portrait ? "portrait" : "landscape")-\(fixture)"
                application.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                                               "-magicmobile.portraitModeEnabled", portrait || rotateDuringTest ? "YES" : "NO"]
                application.launchEnvironment["MAGICMOBILE_DESIGN_PREVIEW"] = fixture
                application.launchEnvironment["MAGICMOBILE_FORCE_CARD_PLACEHOLDERS"] = "true"
                XCUIDevice.shared.orientation = portrait || rotateDuringTest ? .portrait : .landscapeLeft
                application.launch()
                XCTAssertTrue(application.staticTexts["DEVELOPMENT FIXTURE · NO ENGINE"].waitForExistence(timeout: 15))
                XCUIDevice.shared.orientation = portrait ? .portrait : .landscapeLeft
                // Check rendered orientation, not just the requested simulator orientation.
                let orientation = NSPredicate { _, _ in
                    let frame = application.frame
                    return frame.width > 0 && frame.height > 0 && (portrait ? frame.height > frame.width : frame.width > frame.height)
                }
                XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: orientation, object: application)], timeout: 10), .completed)
                verify(fixture, in: application, portrait: portrait)
                capture(application, name: currentCapture)
            }
        }
    }

    private func verify(_ fixture: String, in app: XCUIApplication, portrait: Bool) {
        switch fixture {
        case "phase-announcement":
            app.buttons["preview.advance"].tap()
            captureImage(name: currentCapture + "-visible")
            let cue = app.staticTexts["Declare blockers"].firstMatch
            XCTAssertTrue(cue.exists || cue.waitForExistence(timeout: 6))
            XCTAssertGreaterThan(cue.frame.midY, app.frame.height * 0.25)
            XCTAssertLessThan(cue.frame.midY, app.frame.height * 0.75)
            XCTAssertTrue(cue.waitForNonExistence(timeout: 5))
            XCTAssertTrue(app.buttons["board.hand.expand"].isHittable)
        case "life-change":
            app.buttons["preview.advance"].tap()
            captureImage(name: currentCapture + "-loss")
            XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "35 life")).firstMatch.waitForExistence(timeout: 5))
            app.buttons["preview.advance"].tap()
            captureImage(name: currentCapture + "-gain")
            XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "43 life")).firstMatch.waitForExistence(timeout: 5))
        case "ability-choice":
            let inspect = app.buttons["Inspect Sol Ring"].firstMatch
            visible(inspect, in: app)
            let choices = app.buttons.matching(NSPredicate(format: "label == %@", "Choose ability"))
            XCTAssertEqual(choices.count, 2, "Identical abilities retain separate engine choices")
            capture(app, name: currentCapture + "-cards")
            choices.element(boundBy: 1).tap()
            // Fixtures capture commands without advancing an engine snapshot.
            // Dismiss the sheet to expose the capture on the underlying board.
            app.buttons["Cancel prompt details"].tap()
            XCTAssertTrue(app.staticTexts["preview.captured-command"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["preview.captured-command"].label.contains("22222222-2222-4222-8222-222222222222"))
        case "combat-arrows":
            let lane = app.scrollViews["board.battlefield.Your board"]
            visible(lane, in: app)
            let edge = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "board.combat.offscreen.")).firstMatch
            for _ in 0..<5 {
                if edge.exists && edge.isHittable { break }
                lane.swipeLeft()
            }
            visible(edge, in: app)
            capture(app, name: currentCapture + "-edge")
            edge.tap()
            let inspect = app.buttons["Inspect Silvercoat Lion"].firstMatch
            visible(inspect, in: app)
            inspect.tap()
            visible(card(in: app, identifierPrefix: "card-inspector-silvercoat-lion"), in: app)
        case "hand-scrubber":
            let scrubber = app.descendants(matching: .any)["board.hand.scrubber"].firstMatch
            visible(scrubber, in: app)
            XCTAssertGreaterThanOrEqual(scrubber.frame.height, 44)
            let hand = app.scrollViews["board.hand.scroll"]
            let first = card(in: app, identifierPrefix: "card-hand-sol-ring")
            let last = card(in: app, identifierPrefix: "card-hand-spirited-companion-last-han")
            scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
            visible(last, in: app)
            XCTAssertEqual(scrubber.value as? String, "100 percent")
            XCTAssertGreaterThanOrEqual(last.frame.minX, hand.frame.minX - 1)
            XCTAssertLessThanOrEqual(last.frame.maxX, hand.frame.maxX + 1)
            app.buttons["board.hand.expand"].tap()
            scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
            visible(last, in: app)
            XCTAssertTrue(hand.frame.insetBy(dx: -1, dy: -1).contains(last.frame))
            scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertEqual(scrubber.value as? String, "50 percent")
            scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5)))
            visible(first, in: app)
            XCTAssertEqual(scrubber.value as? String, "0 percent")
            hand.swipeLeft()
            XCTAssertNotEqual(scrubber.value as? String, "0 percent", "Card swipes update the same slider")
            XCTAssertFalse(app.staticTexts["preview.captured-command"].exists, "Scrubbing must not cast a card")
            scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5)).tap()
            first.press(forDuration: 0.6)
            visible(card(in: app, identifierPrefix: "card-inspector-sol-ring"), in: app)
        case "hand-drag":
            app.buttons["board.hand.expand"].tap()
            let source = card(in: app, identifierPrefix: "card-hand-sol-ring")
            let destination = card(in: app, identifierPrefix: "card-your-board-isamaru")
            visible(source, in: app)
            visible(destination, in: app)
            source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: destination.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
            let capture = app.staticTexts["preview.captured-command"]
            XCTAssertTrue(capture.waitForExistence(timeout: 5))
            XCTAssertTrue(capture.label.contains("Cast Sol Ring"))
        case "mixed-card-choice":
            visible(app.buttons["board.choice.target.ai-1"], in: app)
            app.buttons["board.choice.target.ai-1"].tap()
            XCTAssertTrue(app.buttons["board.choice.confirm"].isEnabled)
            app.buttons["board.choice.confirm"].tap()
            XCTAssertTrue(app.staticTexts["preview.captured-command"].waitForExistence(timeout: 5))
        case "scry-choice", "library-choice", "empty-library-choice":
            let choice = app.descendants(matching: .any)["board.choice.card.choice-0"].firstMatch
            visible(choice, in: app)
            let confirm = app.buttons["board.choice.confirm"]
            XCTAssertFalse(confirm.isEnabled)
            if fixture == "empty-library-choice" {
                choice.tap()
                XCTAssertFalse(confirm.isEnabled, "No-match searches must not enable an invalid response")
            } else {
                choice.tap()
                XCTAssertTrue(confirm.isEnabled)
                choice.tap()
                XCTAssertFalse(confirm.isEnabled, "A tentative choice can be cleared")
            }
            if fixture != "scry-choice" {
                let invalid = app.descendants(matching: .any)["board.choice.card.choice-1"].firstMatch
                invalid.tap()
                XCTAssertFalse(confirm.isEnabled)
                visible(app.textFields["board.choice.search"], in: app)
            }
            visible(app.buttons["board.choice.done"], in: app)
            capture(app, name: currentCapture + "-chooser")
            app.buttons["Close card choices"].tap()
            XCTAssertFalse(app.buttons["board.choice.confirm"].exists)
        case "normal-battlefield":
            app.buttons[portrait ? "Game log" : "Open game log"].firstMatch.tap()
            visible(app.staticTexts["Caleb plays Temple of Plenty"], in: app)
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "object_id=")).firstMatch.exists)
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "<font")).firstMatch.exists)
            capture(app, name: currentCapture + "-formatted-log")
            let logCard = app.links["Temple of Plenty"].firstMatch
            visible(logCard, in: app)
            logCard.tap()
            visible(app.staticTexts["From the game log"], in: app)
            let historicalCard = card(in: app, identifierPrefix: "card-inspector-temple-of-plenty-36fc54d7")
            visible(historicalCard, in: app)
            XCTAssertFalse(app.staticTexts["preview.captured-command"].exists)
            capture(app, name: currentCapture + "-log-card-inspection")
            app.buttons["Done"].firstMatch.tap()
            XCTAssertTrue(historicalCard.waitForNonExistence(timeout: 5))
            app.buttons["Close game log"].tap()
            XCTAssertTrue(app.buttons["Close game log"].waitForNonExistence(timeout: 5))
            let expandHand = app.buttons["board.hand.expand"]
            XCTAssertTrue(expandHand.isHittable)
            expandHand.tap()
            XCTAssertEqual(expandHand.label, "Tuck hand")
            let first = card(in: app, identifierPrefix: "card-hand-sol-ring")
            visible(first, in: app)
            let last = card(in: app, identifierPrefix: "card-hand-spirited-companion")
            let hand = app.scrollViews["board.hand.scroll"]
            let scrubber = app.descendants(matching: .any)["board.hand.scrubber"].firstMatch
            visible(scrubber, in: app)
            XCTAssertGreaterThanOrEqual(scrubber.frame.height, 44)
            // Drag the thumb to the end, then tap the track to return to the start.
            // The actual cards must move, not merely the indicator.
            scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)))
            visible(last, in: app)
            XCTAssertTrue(hand.frame.insetBy(dx: -1, dy: -1).contains(last.frame))
            XCTAssertEqual(scrubber.value as? String, "100 percent")
            scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5)).tap()
            visible(first, in: app)
            XCTAssertTrue(hand.frame.insetBy(dx: -1, dy: -1).contains(first.frame))
            XCTAssertEqual(scrubber.value as? String, "0 percent")
            for _ in 0..<5 {
                if last.isHittable && hand.frame.insetBy(dx: -1, dy: -1).contains(last.frame) { break }
                hand.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.65))
                    .press(forDuration: 0.05, thenDragTo: hand.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.65)))
            }
            visible(last, in: app)
            // Accessibility rounds subpixel card/viewport edges independently.
            XCTAssertTrue(hand.frame.insetBy(dx: -1, dy: -1).contains(last.frame), "Last hand card must scroll fully into hand viewport: hand=\(hand.frame), last=\(last.frame)")
            last.press(forDuration: 0.6)
            visible(card(in: app, identifierPrefix: "card-inspector-spirited-companion"), in: app)
        case "crowded-battlefield":
            XCTAssertFalse(app.staticTexts["YOUR DECISION"].exists, "Routine priority must not cover the battlefield with a redundant banner")
            let firstRow = card(in: app, identifierPrefix: "card-your-board-isamaru")
            let secondRow = card(in: app, identifierPrefix: "card-your-board-sun-titan")
            visible(firstRow, in: app)
            visible(secondRow, in: app)
            XCTAssertGreaterThan(secondRow.frame.minY, firstRow.frame.midY, "Crowded permanents use the reclaimed height for a second row")
            XCTAssertGreaterThanOrEqual(secondRow.frame.width, 44)
            XCTAssertFalse(app.buttons["Close game log"].exists, "Log must start closed")
            let log = app.buttons[portrait ? "Game log" : "Open game log"].firstMatch
            visible(log, in: app)
            log.tap()
            visible(app.buttons["Close game log"], in: app)
            capture(app, name: currentCapture + "-log")
            app.buttons["Close game log"].tap()
            XCTAssertTrue(app.buttons["Close game log"].waitForNonExistence(timeout: 5))
            let commander = card(in: app, identifierPrefix: "card-your-board-isamaru")
            visible(commander, in: app)
            commander.tap() // This fixture's creature has no actionable ability.
            XCTAssertTrue(commander.label.hasSuffix(", selected"), "An ordinary tap must still select")
            capture(app, name: currentCapture + "-board")
            // Inspect rather than activate: no synthetic legal action is sent to a server.
            commander.press(forDuration: 0.6)
            visible(card(in: app, identifierPrefix: "card-inspector-isamaru"), in: app)
            capture(app, name: currentCapture + "-crowded-inspector")
        case "mana-payment-prompt":
            visible(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Pay")).firstMatch, in: app)
            visible(card(in: app, identifierPrefix: "card-your-board-sol-ring"), in: app)
            card(in: app, identifierPrefix: "card-your-board-sol-ring").tap()
            XCTAssertTrue(app.staticTexts["preview.captured-command"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["preview.captured-command"].label.contains("Tap Sol Ring"))
        case "stack-response-prompt":
            if !portrait && !app.buttons["board.stack.done"].exists {
                let inspectStack = app.buttons["Inspect stack"]
                visible(inspectStack, in: app)
                inspectStack.tap()
            }
            // Portrait auto-opens this fixture; both orientations use BoardStackInspector.
            visible(app.buttons["board.stack.done"], in: app)
            XCTAssertTrue(app.frame.contains(app.buttons["board.stack.done"].frame))
            // design-preview stacks are reversed by stackTopFirst: the spell is first.
            visible(app.staticTexts["Source: Swords to Plowshares"], in: app)
            let stackScroll = app.scrollViews["board.stack.items"]
            XCTAssertTrue(stackScroll.exists)
            // The underlying quick peek uses the same card identity; scope to the modal.
            let spell = stackScroll.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "card-stack-swords-to-plowshares")).firstMatch
            visible(spell, in: app)
            capture(app, name: currentCapture + "-stack-inspector")
            let abilitySource = app.staticTexts["Source: Prodigal Pyromancer"]
            let abilityCard = stackScroll.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "card-stack-prodigal-pyromancer")).firstMatch
            for _ in 0..<6 {
                if abilitySource.isHittable && abilityCard.isHittable { break }
                // Short strokes avoid jumping past the source caption on tall rows.
                stackScroll.coordinate(withNormalizedOffset: CGVector(dx: stackDragX, dy: 0.7))
                    .press(forDuration: 0.1, thenDragTo: stackScroll.coordinate(withNormalizedOffset: CGVector(dx: stackDragX, dy: 0.4)))
            }
            visible(abilitySource, in: app)
            visible(abilityCard, in: app)
            capture(app, name: currentCapture + "-stack-ability")
            app.buttons["board.stack.done"].tap()
            XCTAssertTrue(app.buttons["board.stack.done"].waitForNonExistence(timeout: 5))
        case "four-player-focus":
            let focus = app.buttons["board.opponentFocus"]
            visible(focus, in: app)
            focus.tap()
            visible(app.buttons["Kozilek"], in: app)
            visible(app.buttons["Meren"], in: app)
            capture(app, name: currentCapture + "-opponent-menu")
            app.buttons["Meren"].tap()
            let changed = NSPredicate(format: "value == %@", "Meren")
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: changed, object: focus)], timeout: 5), .completed)
            visible(focus, in: app)
        case "player-target-prompt":
            visible(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Choose a player")).firstMatch, in: app)
            // Target controls must be present; selecting one would invoke a preview command.
            visible(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Aurelia")).firstMatch, in: app)
        case "zone-inspection":
            if portrait {
                // portraitGameContent automatically opens the viewer's graveyard fixture.
                visible(app.buttons["Close You · Graveyard"], in: app)
                visible(app.buttons["Inspect Spirited Companion"], in: app)
                capture(app, name: currentCapture + "-viewer-graveyard")
                app.buttons["Close You · Graveyard"].tap()
            }
            // Exercise the same seat-specific menu route in both layouts, including
            // an empty supplied zone rather than accidentally retaining the viewer's cards.
            let zones = app.buttons["Aurelia zones"]
            visible(zones, in: app)
            zones.tap()
            let graveyard = app.buttons["Graveyard · 0"]
            visible(graveyard, in: app)
            graveyard.tap()
            visible(app.buttons["Close Aurelia · Graveyard"], in: app)
            visible(app.staticTexts["Aurelia · Graveyard · 0"], in: app)
            visible(app.staticTexts["No cards in this zone."], in: app)
            XCTAssertFalse(app.buttons["Inspect Spirited Companion"].exists)
        case "full-hand-inspection":
            // ContentView sets the first supplied hand card as inspected on this fixture.
            visible(card(in: app, identifierPrefix: "card-inspector-sol-ring"), in: app)
            visible(app.staticTexts["{T}: Add {C}{C}."], in: app)
        default:
            XCTFail("Unreviewed fixture: \(fixture)")
        }
    }

    private func card(in app: XCUIApplication, identifierPrefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", identifierPrefix)).firstMatch
    }

    private func visible(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "Missing \(element)", file: file, line: line)
        XCTAssertFalse(element.frame.isEmpty, file: file, line: line)
        XCTAssertTrue(app.frame.intersects(element.frame), "Control is outside the screen", file: file, line: line)
        XCTAssertTrue(element.isHittable, "Control/label is obscured", file: file, line: line)
    }

    private func capture(_ app: XCUIApplication, name: String) {
        captureImage(name: name)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name + "-accessibility"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    // Capture short-lived feedback before the slower accessibility-tree export.
    private func captureImage(name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
