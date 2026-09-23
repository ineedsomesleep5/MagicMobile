import XCTest

/// DEBUG, unlinked presentation target only. These are actual simulator UI captures
/// of supplied design fixtures, NOT real XMage gameplay, legality, privacy, or device acceptance.
/// Artwork is deliberately replaced with placeholders; review layout, not downloaded art.
@MainActor
final class BoardPolishUITests: XCTestCase {
    private var app: XCUIApplication?
    private var currentCapture = "board-polish"
    private var stackDragX: CGFloat = 0.9
    private var modalOffers = false

    func testPortraitModalOfferGlows() {
        modalOffers = true
        runMatrix(portrait: true, selectedFixtures: ["normal-battlefield"])
    }

    func testLandscapeModalOfferGlows() {
        modalOffers = true
        runMatrix(portrait: false, selectedFixtures: ["normal-battlefield"])
    }

    func testSharedD20FitsPortraitAndLandscape() {
        let application = XCUIApplication()
        app = application
        application.launchEnvironment["MAGICMOBILE_MULTIPLAYER_D20_FIXTURE"] = "1"
        application.launchEnvironment["MAGICMOBILE_UI_TEST_PREFERENCES"] = UUID().uuidString
        application.launchArguments = ["--ondevice-setup-ui-test", "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US", "-magicmobile.portraitModeEnabled", "YES"]
        XCUIDevice.shared.orientation = .portrait
        application.launch()
        XCTAssertTrue(application.staticTexts["DEVELOPMENT FIXTURE · NO ENGINE"].waitForExistence(timeout: 15))
        capture(application, name: "shared-d20-rolling-fixture")
        XCTAssertFalse(application.buttons["multiplayerD20.continue"].exists)
        let tapToRoll = application.buttons["multiplayerD20.tapToRoll"]
        XCTAssertTrue(tapToRoll.waitForExistence(timeout: 5))
        XCTAssertFalse(application.staticTexts["Rolled 12"].exists, "No die may roll before the first tap")
        tapToRoll.tap()
        XCTAssertTrue(waitForRollButtonToDisappear(tapToRoll))
        currentCapture = "shared-d20-portrait-fixture"
        capture(application, name: currentCapture)
        let result = application.staticTexts["Rolled 12"]
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        // The reveal is intentionally brief. Read its frame before slower
        // accessibility queries can outlive the result animation.
        let resultFrame = result.frame
        let playerSquare = application.otherElements["multiplayerD20.seat.player1"]
        XCTAssertTrue(playerSquare.exists)
        let playerSquareFrame = playerSquare.frame
        XCTAssertLessThan(abs(resultFrame.midX - application.frame.midX), 20)
        XCTAssertLessThanOrEqual(resultFrame.maxY + 12, playerSquareFrame.minY,
                                 "Rolled result must have a visible gap above player squares")
        let rollArea = application.otherElements["multiplayerD20.rollArea"]
        XCTAssertTrue(rollArea.exists)
        XCTAssertEqual(rollArea.value as? String, "Rebounded from screen edge")
        capture(application, name: "shared-d20-result-above-player-squares")
        for _ in 0..<4 {
            XCTAssertTrue(tapToRoll.waitForExistence(timeout: 12))
            tapToRoll.tap()
            XCTAssertTrue(waitForRollButtonToDisappear(tapToRoll), "Each tap must start a distinct roll")
        }
        XCTAssertTrue(application.staticTexts["Starting roll preview complete"].waitForExistence(timeout: 45))
        application.terminate()

        application.launchEnvironment["MAGICMOBILE_D20_LANDSCAPE_FIXTURE"] = "1"
        XCUIDevice.shared.orientation = .landscapeLeft
        application.launch()
        XCTAssertTrue(application.staticTexts["DEVELOPMENT FIXTURE · NO ENGINE"].waitForExistence(timeout: 15))
        let landscape = NSPredicate { _, _ in
            let frame = application.frame
            return frame.width > frame.height
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: landscape, object: application)],
                                    timeout: 10), .completed)
        currentCapture = "shared-d20-landscape-fixture"
        capture(application, name: currentCapture)
        let landscapeSeats = (1...3).map { application.otherElements["multiplayerD20.seat.player\($0)"] }
        for seat in landscapeSeats {
            XCTAssertTrue(seat.exists)
            XCTAssertLessThan(seat.frame.maxY, application.frame.maxY - 12,
                              "The full player square should be visible without scrolling in landscape")
        }
        XCTAssertTrue(application.buttons["multiplayerD20.skipAnimation"].exists)
        tapToRoll.tap()
        XCTAssertTrue(waitForRollButtonToDisappear(tapToRoll))
        application.buttons["multiplayerD20.skipAnimation"].tap()
        for _ in 0..<4 {
            XCTAssertTrue(tapToRoll.waitForExistence(timeout: 8))
            tapToRoll.tap()
        }
        XCTAssertTrue(application.staticTexts["Starting roll preview complete"].waitForExistence(timeout: 8))
    }

    private func waitForRollButtonToDisappear(_ button: XCUIElement) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: button)
        return XCTWaiter.wait(for: [gone], timeout: 4) == .completed
    }

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
    func testPendingOnlinePreservesAIAndGameCenterSetup() {
        let application = XCUIApplication()
        app = application
        application.launchEnvironment["MAGICMOBILE_UI_TEST_PREFERENCES"] = UUID().uuidString
        application.launchEnvironment["MAGICMOBILE_FORCE_CARD_PLACEHOLDERS"] = "true"
        application.launchArguments = ["--ondevice-setup-ui-test", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-magicmobile.playerDisplayName", "Test Player"]
        XCUIDevice.shared.orientation = .portrait
        application.launch()
        XCTAssertTrue(application.buttons["menu.play"].waitForExistence(timeout: 20))
        application.buttons["menu.play"].press(forDuration: 0.15)
        let ai = application.segmentedControls.buttons["AI"]
        for _ in 0..<5 {
            if ai.isHittable { break }
            application.swipeUp()
        }
        visible(ai, in: application)
        ai.press(forDuration: 0.15)
        XCTAssertTrue(application.buttons["Start game"].exists)
        let gameCenter = application.segmentedControls.buttons["Game Center"]
        gameCenter.press(forDuration: 0.15)
        XCTAssertTrue(application.buttons["Sign in to Game Center"].waitForExistence(timeout: 10))
        XCTAssertTrue(application.buttons["Find players"].exists)
        application.segmentedControls.buttons["Online"].press(forDuration: 0.15)
        XCTAssertTrue(application.staticTexts["Online play is coming soon"].waitForExistence(timeout: 10))
        XCTAssertFalse(application.textFields["Email"].exists)
        XCTAssertFalse(application.secureTextFields["Password"].exists)
        XCTAssertFalse(application.buttons["Create lobby"].exists)
        XCTAssertFalse(application.buttons["Join"].exists)
        currentCapture = "pending-online-portrait-setup-fixture"
        capture(application, name: currentCapture)
        gameCenter.press(forDuration: 0.15)
        XCTAssertTrue(application.buttons["Find players"].waitForExistence(timeout: 5))
        ai.press(forDuration: 0.15)
        XCTAssertTrue(application.buttons["Start game"].waitForExistence(timeout: 5))
        XCTAssertTrue(application.buttons["Start game"].isEnabled)
        let rollMode = application.segmentedControls.buttons["Roll D20"]
        for _ in 0..<5 where !rollMode.isHittable { application.swipeUp() }
        XCTAssertTrue(rollMode.isHittable)
        rollMode.tap()
        XCTAssertTrue(rollMode.isSelected)
        XCTAssertTrue(application.staticTexts["Everyone rolls a D20. The highest roll starts; ties reroll."].exists)
    }

    func testPortraitCrowdedBattlefield() { runMatrix(portrait: true, selectedFixtures: ["crowded-battlefield"]) }
    func testLandscapeCrowdedBattlefield() { runMatrix(portrait: false, selectedFixtures: ["crowded-battlefield"]) }
    func testPortraitAttachments() { runMatrix(portrait: true, selectedFixtures: ["attached-permanents"]) }
    func testLandscapeAttachments() { runMatrix(portrait: false, selectedFixtures: ["attached-permanents"]) }
    func testSixBattlefieldBackgroundsInPortraitAndLandscape() {
        for theme in ["arena", "midnight", "wood", "moss", "ember", "tide"] {
            app?.terminate()
            let application = XCUIApplication()
            app = application
            application.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                "-magicmobile.portraitModeEnabled", "YES", "-magicmobile.boardAppearance", theme]
            application.launchEnvironment["MAGICMOBILE_DESIGN_PREVIEW"] = "crowded-battlefield"
            application.launchEnvironment["MAGICMOBILE_FORCE_CARD_PLACEHOLDERS"] = "true"
            XCUIDevice.shared.orientation = .portrait
            application.launch()
            XCTAssertTrue(application.staticTexts["DEVELOPMENT FIXTURE · NO ENGINE"].waitForExistence(timeout: 15))
            for portrait in [true, false] {
                currentCapture = "background-\(theme)-\(portrait ? "portrait" : "landscape")"
                XCTContext.runActivity(named: currentCapture) { _ in
                    XCUIDevice.shared.orientation = portrait ? .portrait : .landscapeLeft
                    let orientation = NSPredicate { _, _ in
                        let frame = application.frame
                        return frame.width > 0 && frame.height > 0 && (portrait ? frame.height > frame.width : frame.width > frame.height)
                    }
                    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: orientation, object: application)], timeout: 10), .completed)
                    let firstRow = card(in: application, identifierPrefix: "card-your-board-isamaru")
                    visible(firstRow, in: application)
                    // Crowded creatures scroll horizontally; later cards need not
                    // be visible before scrolling. Backgrounds must preserve lanes.
                    XCTAssertGreaterThanOrEqual(firstRow.frame.width, 44)
                    visible(application.scrollViews["board.battlefield.Your lands"], in: application)
                    visible(card(in: application, identifierPrefix: "card-your-lands-plains"), in: application)
                    visible(application.buttons["board.hand.expand"], in: application)
                    visible(application.buttons["board.action.primary"], in: application)
                    XCTAssertFalse(application.staticTexts["YOUR DECISION"].exists)
                    capture(application, name: currentCapture)
                }
            }
        }
    }

    func testSettingsOffersAllSixBattlefieldBackgrounds() {
        let application = XCUIApplication()
        app = application
        application.launchEnvironment["MAGICMOBILE_UI_TEST_PREFERENCES"] = UUID().uuidString
        application.launchArguments = ["--ondevice-setup-ui-test", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        XCUIDevice.shared.orientation = .portrait
        application.launch()
        XCTAssertTrue(application.buttons["menu.settings"].waitForExistence(timeout: 20))
        // A deliberate short press avoids the observed dropped synthesized 50ms
        // taps. Still assert the destination; no retry conceals a failed action.
        XCTAssertTrue(application.buttons["menu.settings"].isHittable)
        application.buttons["menu.settings"].press(forDuration: 0.15)
        XCTAssertTrue(application.navigationBars["Settings"].waitForExistence(timeout: 10))
        for title in ["Stone Arena", "Midnight", "Classic Wood", "Moss Sanctuary", "Obsidian Ember", "Tidal Slate"] {
            let choice = application.buttons[title + " battlefield"]
            for _ in 0..<3 {
                if choice.isHittable { break }
                application.swipeUp()
            }
            visible(choice, in: application)
            choice.tap()
            let selected = NSPredicate(format: "selected == true")
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: selected, object: choice)], timeout: 5), .completed)
        }
        currentCapture = "settings-six-battlefield-backgrounds"
        capture(application, name: currentCapture)
    }
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
                if modalOffers { application.launchEnvironment["MAGICMOBILE_MDFC_UI_TEST"] = "1" }
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
        if modalOffers {
            let values = ["Play land or cast spell available", "Cast spell available", "Play land available"]
            for value in values {
                XCTAssertTrue(app.buttons.matching(NSPredicate(format: "value == %@", value)).firstMatch.waitForExistence(timeout: 5))
            }
            capture(app, name: "\(portrait ? "portrait" : "landscape")-modal-offers")
            return
        }
        switch fixture {
        case "attached-permanents":
            visible(app.buttons["board.action.primary"], in: app)
            visible(app.buttons["board.hand.expand"], in: app)
            let lane = app.scrollViews["board.battlefield.Opponent board"]
            let host = card(in: app, identifierPrefix: "card-opponent-board-silvercoat-lion-ai-1-pre")
            for _ in 0..<3 {
                if host.exists && host.isHittable && lane.frame.contains(host.frame) { break }
                lane.swipeLeft()
            }
            visible(host, in: app)
            let aura = card(in: app, identifierPrefix: "card-opponent-board-karametra-s-favor-human-at")
            let equipment = card(in: app, identifierPrefix: "card-opponent-board-short-sword")
            visible(aura, in: app)
            visible(equipment, in: app)
            XCTAssertEqual(aura.frame.midY, host.frame.midY, accuracy: 8)
            XCTAssertLessThan(equipment.frame.minX, host.frame.minX)
            XCTAssertLessThanOrEqual(host.frame.minX - equipment.frame.minX, max(44, equipment.frame.width))
            XCTAssertFalse(card(in: app, identifierPrefix: "card-your-board-karametra-s-favor").exists,
                           "Cross-controller Aura follows its public host, without a duplicate in the controller lane")
            aura.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 20, dy: 25)).tap()
            XCTAssertTrue(aura.label.hasSuffix(", selected"))
            aura.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 20, dy: 25)).press(forDuration: 0.7)
            XCTAssertTrue(card(in: app, identifierPrefix: "card-inspector-karametra-s-favor").waitForNonExistence(timeout: 3))
            XCTAssertFalse(app.staticTexts["preview.captured-command"].exists)
            let phased = card(in: app, identifierPrefix: "card-your-board-sol-ring")
            visible(phased, in: app)
            XCTAssertTrue((phased.value as? String)?.contains("Phased out") == true)
            phased.tap()
            XCTAssertFalse(app.staticTexts["preview.captured-command"].exists, "Phased-out card never activates")
            let effects = app.buttons["board.player.effects.ai-1"]
            visible(effects, in: app)
            XCTAssertTrue(effects.label.contains("poison") || effects.label.contains("Poison"))
            effects.tap()
            app.buttons["Curse of Opulence · attached"].tap()
            visible(app.buttons["Inspect Curse of Opulence"], in: app)
            app.buttons["Close Enchanting Aurelia"].tap()
            app.buttons["preview.advance"].tap()
            XCTAssertFalse((phased.value as? String)?.contains("Phased out") == true)
            XCTAssertTrue(app.buttons["board.player.effects.human"].label.contains("Poison 5"))
            XCTAssertTrue(app.buttons["board.player.effects.human"].label.contains("Curse of Opulence attached"))
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
            let cards = app.buttons.matching(NSPredicate(format: "label == %@", "Choose Sol Ring ability"))
            visible(cards.firstMatch, in: app)
            XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "CHOOSE ABILITY")).count, 1,
                           "Ability details should have only the outer heading")
            let choices = app.buttons.matching(NSPredicate(format: "label == %@", "Choose ability"))
            XCTAssertEqual(choices.count, 2, "Identical abilities retain separate engine choices")
            if app.frame.width > app.frame.height {
                XCTAssertLessThanOrEqual(choices.firstMatch.frame.maxY, app.scrollViews["prompt.details.scroll"].frame.maxY,
                                  "Short ability actions should fit the landscape sheet")
            }
            capture(app, name: currentCapture + "-cards")
            let swipeStart = cards.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            swipeStart.press(forDuration: 0.05, thenDragTo: swipeStart.withOffset(CGVector(dx: 0, dy: -60)))
            XCTAssertFalse(app.buttons["Close card"].exists, "Scrolling must not inspect or select an ability")
            app.buttons["Cancel prompt details"].tap()
            XCTAssertFalse(app.staticTexts["preview.captured-command"].exists, "Scrolling must not submit an ability")
            app.buttons["board.action.primary"].tap()
            visible(cards.firstMatch, in: app)
            // Leave margin for simulator scroll-view touch-delivery delay.
            // The app's recognition threshold remains 0.35 seconds.
            cards.firstMatch.press(forDuration: 1)
            XCTAssertTrue(app.buttons["Close card"].waitForNonExistence(timeout: 2), "Releasing a held ability source must close inspection")
            capture(app, name: currentCapture + "-after-hold")
            app.buttons["Cancel prompt details"].tap()
            XCTAssertFalse(app.staticTexts["preview.captured-command"].exists, "Inspection must not submit an ability")
            app.buttons["board.action.primary"].tap()
            visible(cards.element(boundBy: 1), in: app)
            // A tap on the card-backed choice must submit, not open a second
            // inspector that makes the user choose the same ability again.
            cards.element(boundBy: 1).tap()
            XCTAssertFalse(app.buttons["Close card"].exists, "Tapping a choice should not open inspection")
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
            XCTAssertTrue(card(in: app, identifierPrefix: "card-inspector-sol-ring").waitForNonExistence(timeout: 2), "Hand inspection ends on release")
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
            let header = app.staticTexts["board.choice.header"].firstMatch
            let close = app.buttons["Close card choices"]
            let confirm = app.buttons["board.choice.confirm"]
            XCTAssertTrue(header.waitForExistence(timeout: 5))
            // SwiftUI exposes a modal ancestor with a full-screen AX frame.
            // Measure the visible content instead of that inherited container.
            func contentBounds() -> CGRect {
                header.frame.union(close.frame).union(confirm.frame)
            }
            XCTAssertLessThan(abs(contentBounds().midX - app.frame.midX), 35, "Card dialog stays horizontally centered")
            XCTAssertLessThan(abs(contentBounds().midY - app.frame.midY), 60, "Card dialog stays vertically centered")
            XCTAssertLessThanOrEqual(contentBounds().width, portrait ? 430 : 660, "Dialog must not stretch edge-to-edge")
            let choice = app.descendants(matching: .any)["board.choice.card.choice-0"].firstMatch
            visible(choice, in: app)
            XCTAssertEqual(confirm.isEnabled, fixture == "scry-choice", "Keep-all is a valid scry draft")
            if fixture == "empty-library-choice" {
                choice.tap()
                XCTAssertFalse(confirm.isEnabled, "No-match searches must not enable an invalid response")
            } else {
                choice.tap()
                XCTAssertTrue(confirm.isEnabled)
                choice.tap()
                XCTAssertEqual(confirm.isEnabled, fixture == "scry-choice", "Tap again removes the draft choice")
                choice.press(forDuration: 0.6)
                XCTAssertTrue(app.buttons["board.choice.inspection.close"].waitForNonExistence(timeout: 2), "Card-choice inspection ends on release")
                XCTAssertEqual(confirm.isEnabled, fixture == "scry-choice", "Holding a card must not change the draft")
            }
            if fixture != "scry-choice" {
                let invalid = app.descendants(matching: .any)["board.choice.card.choice-1"].firstMatch
                invalid.tap()
                XCTAssertFalse(confirm.isEnabled)
                visible(app.textFields["board.choice.search"], in: app)
                let search = app.textFields["board.choice.search"]
                search.press(forDuration: 0.15)
                search.typeText("zzzznotacard")
                XCTAssertTrue(app.staticTexts["board.choice.search.empty"].waitForExistence(timeout: 5))
                let clearSearch = app.buttons["board.choice.search.clear"]
                XCTAssertTrue(clearSearch.isHittable)
                clearSearch.press(forDuration: 0.15)
                XCTAssertTrue(choice.waitForExistence(timeout: 5), "Clearing a search restores the supplied cards")
                search.typeText("graveyard")
                XCTAssertTrue(choice.waitForExistence(timeout: 5))
                XCTAssertTrue(choice.isHittable, "Search results remain usable with the keyboard open")
                capture(app, name: currentCapture + "-search-keyboard")
                search.typeText("\n")
                XCTAssertTrue(choice.waitForExistence(timeout: 5), "Rules-only matches remain visible after keyboard dismissal")
                XCTAssertFalse(invalid.exists, "Cards without the rules keyword are filtered out")
                XCTAssertTrue(choice.isHittable, "A matching card stays reachable after search")
                XCTAssertLessThan(abs(contentBounds().midY - app.frame.midY), 60, "Search dismissal restores centered presentation")
                choice.press(forDuration: 0.15)
                XCTAssertEqual(confirm.isEnabled, fixture == "library-choice",
                               "Searching must preserve the engine's eligibility constraints")
            }
            if fixture != "scry-choice" { visible(app.buttons["board.choice.done"], in: app) }
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
            XCTAssertTrue(card(in: app, identifierPrefix: "card-inspector-spirited-companion").waitForNonExistence(timeout: 2), "Hand inspection ends on release")
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
            commander.press(forDuration: 5)
            XCTAssertTrue(card(in: app, identifierPrefix: "card-inspector-isamaru").waitForNonExistence(timeout: 2), "Battlefield inspection ends on release")
            XCTAssertFalse(app.staticTexts["preview.captured-command"].exists, "Holding must not activate the card")
            XCTAssertTrue(commander.label.hasSuffix(", selected"), "Inspection preserves the existing selection")
            commander.tap()
            XCTAssertFalse(commander.label.hasSuffix(", selected"), "A tap still clears selection after inspection")
            commander.tap()
            XCTAssertTrue(commander.label.hasSuffix(", selected"), "Selection remains available after inspection")
            capture(app, name: currentCapture + "-after-inspection-release")
        case "mana-payment-prompt":
            visible(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Pay")).firstMatch, in: app)
            if portrait {
                let floatingMana = app.buttons["board.mana.spend.W"]
                visible(floatingMana, in: app)
                floatingMana.tap()
                XCTAssertTrue(app.staticTexts["preview.captured-command"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.staticTexts["preview.captured-command"].label.contains("Spend floating {W}"))
            }
            visible(card(in: app, identifierPrefix: "card-your-board-sol-ring"), in: app)
            card(in: app, identifierPrefix: "card-your-board-sol-ring").tap()
            XCTAssertTrue(app.staticTexts["preview.captured-command"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["preview.captured-command"].label.contains("Tap Sol Ring"))
        case "stack-response-prompt":
            if portrait {
                XCTAssertEqual(app.staticTexts["board.response.status"].label, "Respond to the stack")
            } else {
                XCTAssertTrue(app.descendants(matching: .any)["board.response.window"].firstMatch.waitForExistence(timeout: 5))
            }
            if !portrait && !app.buttons["board.stack.done"].exists {
                let inspectStack = app.buttons["Inspect stack"]
                visible(inspectStack, in: app)
                inspectStack.press(forDuration: 0.15)
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
            XCTAssertTrue(app.buttons["board.action.primary"].label.contains("Pass Priority"))
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
            app.buttons["Close Aurelia · Graveyard"].tap()
            let ownZones = app.buttons["board.zones.human"]
            visible(ownZones, in: app)
            XCTAssertTrue(ownZones.label.contains("commander cast available"))
            ownZones.tap()
            app.buttons["Command · Cast available"].tap()
            visible(app.buttons["Close You · Command"], in: app)
            app.buttons["Cast"].tap()
            XCTAssertTrue(app.buttons["Close You · Command"].waitForNonExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["preview.captured-command"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["preview.captured-command"].label.contains("Cast commander"))
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
