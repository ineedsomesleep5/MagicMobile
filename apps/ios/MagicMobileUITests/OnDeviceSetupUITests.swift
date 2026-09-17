import XCTest

/// Real setup views in a presentation-only build; no native gameplay or Game Center login.
@MainActor
final class OnDeviceSetupUITests: XCTestCase {
    private var app: XCUIApplication!
    private var createdDeckNames: [String] = []
    private var lastTappedControl: XCUIElement?

    override func setUpWithError() throws {
        continueAfterFailure = false
        lastTappedControl = nil
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        // A private preference suite stays writable and survives this test's relaunches.
        // Argument-domain game settings would override AppStorage writes during interaction.
        app.launchEnvironment["MAGICMOBILE_UI_TEST_PREFERENCES"] = UUID().uuidString
        app.launchArguments = [
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "--ondevice-setup-ui-test"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["menu.play"].waitForExistence(timeout: 15))
    }

    override func tearDownWithError() throws {
        if let app {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            cleanupCreatedDecks()
            app.terminate()
        }
        app = nil
    }

    func testAISkillCanChangeAndSurvivesRelaunch() {
        openSetup()
        let skill = app.steppers["onDevice.aiSkill"]
        reveal(skill)
        XCTAssertTrue(app.staticTexts["AI skill: 2"].exists)
        skill.buttons["Increment"].tap()
        XCTAssertTrue(app.staticTexts["AI skill: 3"].exists)
        capture("AI skill selection")
        app.terminate()
        app.launch()
        openSetup()
        reveal(app.steppers["onDevice.aiSkill"])
        XCTAssertTrue(app.staticTexts["AI skill: 3"].exists)
        app.steppers["onDevice.aiSkill"].buttons["Decrement"].tap()
        XCTAssertTrue(app.staticTexts["AI skill: 2"].exists)
    }

    func testUpdatesShowsInstalledBuildAndSeparatesUpstreamNews() {
        app.buttons["menu.updates"].tap()
        XCTAssertTrue(app.navigationBars["Updates"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Installed build"].exists)
        XCTAssertTrue(app.staticTexts["What's new"].exists)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "not installed automatically")).firstMatch.exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["menu.play"].exists)
    }

    func testEmptyNameDisablesStartAndEnteringNameEnablesIt() {
        openSetup()
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

    func testPlayButtonWholeLabelRoutesToSetup() {
        for horizontal in [0.15, 0.5, 0.85] {
            let play = app.buttons["menu.play"]
            XCTAssertTrue(play.waitForExistence(timeout: 10))
            reveal(play)
            play.coordinate(withNormalizedOffset: CGVector(dx: horizontal, dy: 0.5)).tap()
            XCTAssertTrue(app.textFields["ondevice.playerName"].waitForExistence(timeout: 5))
            app.buttons["Main menu"].tap()
        }
    }

    func testGameCenterSettingsAllowTwoThroughFourHumansWithoutSigningIn() {
        openSetup()
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

    func testDeckButtonWholeLabelRoutesToLibrary() {
        for horizontal in [0.15, 0.5, 0.85] {
            let decks = app.buttons["menu.decks"]
            reveal(decks)
            decks.coordinate(withNormalizedOffset: CGVector(dx: horizontal, dy: 0.5)).tap()
            XCTAssertTrue(app.buttons["Import"].waitForExistence(timeout: 10))
            app.navigationBars["Decks"].buttons["Done"].tap()
            XCTAssertTrue(app.navigationBars["Decks"].waitForNonExistence(timeout: 5))
        }
    }

    func testInvalidImportRetainsDraftUntilCancelled() {
        openLibrary()
        app.buttons["Import"].tap()
        let editor = app.textViews["Deck list text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let submit = app.buttons["nativeDeck.import.submit"]
        XCTAssertFalse(submit.isEnabled)
        let deckName = app.textFields["Deck name"]
        let originalName = deckName.value as? String
        let draft = "this is not a deck entry"
        editor.tap()
        editor.typeText(draft)
        // A scroll dismisses the editor keyboard and exposes the import action.
        app.swipeUp()
        reveal(submit)
        tapDiagnosed(submit)
        let error = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Line 1:")).firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.label.contains("No cards were imported."))
        reveal(editor, scrollingUp: false)
        XCTAssertEqual(editor.value as? String, draft)
        XCTAssertEqual(deckName.value as? String, originalName)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Invalid import retains draft"
        attachment.lifetime = .keepAlways
        add(attachment)
        tapDiagnosed(app.navigationBars["Import deck"].buttons["nativeDeck.import.cancel"])
        waitForImportDismissal(editor)
    }

    func testPasteValidDraftInspectEditSaveAndRelaunch() {
        let originalName = uniqueDeckName("Imported")
        let editedName = uniqueDeckName("Renamed")
        openLibrary()
        app.buttons["Import"].tap()
        let name = app.textFields["Deck name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        replaceText(name, with: originalName)
        let text = app.textViews["Deck list text"]
        text.tap()
        text.typeText("1x Emmara, Soul of the Accord (grn) [Commander{top}]\n1x Forest (m21) 274 [Land]")
        let submit = app.buttons["nativeDeck.import.submit"]
        reveal(submit); tapDiagnosed(submit)
        let confirm = app.buttons["nativeDeck.import.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        reveal(confirm); tapDiagnosed(confirm)
        waitForImportDismissal(text)
        openSavedDeck(originalName)
        let inspect = app.buttons["nativeDeck.inspect.Emmara, Soul of the Accord"]
        reveal(inspect); inspect.tap()
        XCTAssertTrue(app.navigationBars["Emmara, Soul of the Accord"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        let edit = app.buttons["Edit"]
        reveal(edit, scrollingUp: false); edit.tap()
        selectDeckBuilderPane("Deck")
        let editorName = app.textFields["Deck name"]
        XCTAssertTrue(editorName.waitForExistence(timeout: 5))
        replaceText(editorName, with: editedName)
        tapDiagnosed(app.navigationBars.buttons["nativeDeck.editor.save"])
        waitFor(editorName, predicate: "exists == false")
        app.terminate(); app.launch()
        openLibrary()
        openSavedDeck(editedName)
        XCTAssertTrue(app.staticTexts["2 cards · Saved locally"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["nativeDeck.inspect.Emmara, Soul of the Accord"].exists)
        let forest = app.buttons["nativeDeck.inspect.Forest"]
        reveal(forest)
        // Artwork/network availability is not an acceptance condition for deck persistence.
    }

    func testMoxfieldPlainTextExportPasteKeepsCardsAndQuantities() {
        let importedName = uniqueDeckName("Moxfield")
        openLibrary()
        app.buttons["Import"].tap()
        let name = app.textFields["Deck name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        replaceText(name, with: importedName)
        let text = app.textViews["Deck list text"]
        text.tap()
        text.typeText("Commander\n1 Emmara, Soul of the Accord (GRN) 168\n\nDeck\n2 Forest (M21) 274 *F*\n1 Sol Ring (CMM) 396")
        let submit = app.buttons["nativeDeck.import.submit"]
        reveal(submit); tapDiagnosed(submit)
        let confirm = app.buttons["nativeDeck.import.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        reveal(confirm); tapDiagnosed(confirm)
        waitForImportDismissal(text)
        openSavedDeck(importedName)
        XCTAssertTrue(app.staticTexts["4 cards · Saved locally"].waitForExistence(timeout: 5))
        let forest = app.buttons["nativeDeck.inspect.Forest"]
        reveal(forest)
        XCTAssertEqual(forest.value as? String, "2 copies")
        let ring = app.buttons["nativeDeck.inspect.Sol Ring"]
        reveal(ring)
        XCTAssertTrue(ring.isHittable)
        capture("Moxfield plain-text export imported")
    }

    func testIncludedDeckEditingCopyDoesNotMutateBundledDeck() {
        let copyName = uniqueDeckName("PreconCopy")
        openLibrary()
        searchLibrary("Token Triumph")
        let bundled = app.buttons["nativeDeck.bundled.Token Triumph"]
        XCTAssertTrue(bundled.waitForExistence(timeout: 5))
        reveal(bundled); bundled.tap()
        XCTAssertTrue(app.buttons["nativeDeck.inspect.Emmara, Soul of the Accord"].waitForExistence(timeout: 5))
        capture("Included Commander deck grouped cards")
        let editCopy = app.buttons["Edit a local copy"]
        reveal(editCopy); editCopy.tap()
        selectDeckBuilderPane("Deck")
        let name = app.textFields["Deck name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        replaceText(name, with: copyName)
        tapDiagnosed(app.navigationBars.buttons["nativeDeck.editor.save"])
        waitFor(name, predicate: "exists == false")
        app.terminate(); app.launch()
        openLibrary(); openSavedDeck(copyName)
        XCTAssertTrue(app.staticTexts["100 cards · Saved locally"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        openLibrary(); searchLibrary("Token Triumph")
        XCTAssertTrue(bundled.waitForExistence(timeout: 5))
        reveal(bundled); bundled.tap()
        XCTAssertTrue(app.staticTexts["100 cards · Included deck"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Edit a local copy"].exists)
        XCTAssertFalse(app.buttons["Delete local deck"].exists)
    }

    func testEDHRECManualHandoffCopiesWithoutOpeningWebsite() {
        openLibrary()
        searchLibrary("Token Triumph")
        let bundled = app.buttons["nativeDeck.bundled.Token Triumph"]
        reveal(bundled); bundled.tap()
        let info = app.segmentedControls["nativeDeck.sections"].buttons["nativeDeck.section.info"]
        reveal(info); tapDiagnosed(info)
        waitFor(info, predicate: "selected == true")
        XCTAssertTrue(app.searchFields["Find a card in this deck"].waitForNonExistence(timeout: 5))
        waitFor(app.staticTexts["EDHREC · manual recommendations"], predicate: "exists == true")
        let copy = app.buttons["nativeDeck.edhrec.copy"]
        reveal(copy)
        XCTAssertTrue(copy.isEnabled)
        tapDiagnosed(copy)
        let confirmation = app.staticTexts["Main deck copied. Paste it into EDHREC’s Decklist field."]
        reveal(confirmation)
        XCTAssertTrue(confirmation.exists)
        let website = app.buttons["nativeDeck.edhrec.open"]
        reveal(website)
        XCTAssertTrue(website.isEnabled)
        capture("EDHREC explicit manual handoff")
        // No external browser is opened and no deck is submitted by this test.
    }

    func testEmptyNamedDraftPersistsWithoutClaimingPlayLegality() {
        let draftName = uniqueDeckName("EmptyDraft")
        openLibrary()
        app.buttons["New deck"].tap()
        selectDeckBuilderPane("Deck")
        let name = app.textFields["Deck name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        replaceText(name, with: draftName)
        tapDiagnosed(app.navigationBars.buttons["nativeDeck.editor.save"])
        waitFor(name, predicate: "exists == false")
        app.terminate(); app.launch()
        openLibrary(); openSavedDeck(draftName)
        XCTAssertTrue(app.staticTexts["0 cards · Saved locally"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["XMage checks Commander legality when you start a game. Saved drafts may be incomplete."].exists)
        // Deliberately do not select/start an incomplete draft.
    }

    func testCatalogueSearchAddAndQuantityPersistInDraft() {
        let draftName = uniqueDeckName("Catalogue")
        openLibrary()
        app.buttons["New deck"].tap()
        selectDeckBuilderPane("Deck")
        let name = app.textFields["Deck name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        replaceText(name, with: draftName)
        selectDeckBuilderPane("Collection")
        let search = app.textFields["nativeDeck.cardSearch"]
        reveal(search); replaceText(search, with: "Sol Ring\n")
        let add = app.buttons["Add Sol Ring to deck"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        reveal(add); add.tap()
        selectDeckBuilderPane("Deck")
        let increase = app.buttons["Add one Sol Ring"]
        reveal(increase); increase.tap()
        assertDeckQuantity(2, card: "Sol Ring")
        tapDiagnosed(app.navigationBars.buttons["nativeDeck.editor.save"])
        waitFor(name, predicate: "exists == false")
        app.terminate(); app.launch()
        openLibrary(); openSavedDeck(draftName)
        XCTAssertTrue(app.staticTexts["2 cards · Saved locally"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["nativeDeck.inspect.Sol Ring"].exists)
        // Verify the persisted row itself, then save a decrement and relaunch again.
        let edit = app.buttons["Edit"]
        reveal(edit, scrollingUp: false); tapDiagnosed(edit)
        selectDeckBuilderPane("Deck")
        assertDeckQuantity(2, card: "Sol Ring")
        let decrease = app.buttons["Remove one Sol Ring"]
        reveal(decrease); tapDiagnosed(decrease)
        assertDeckQuantity(1, card: "Sol Ring")
        tapDiagnosed(app.navigationBars.buttons["nativeDeck.editor.save"])
        waitFor(name, predicate: "exists == false")
        app.terminate(); app.launch()
        openLibrary(); openSavedDeck(draftName)
        XCTAssertTrue(app.staticTexts["1 card · Saved locally"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["nativeDeck.inspect.Sol Ring"].exists)
    }

    func testMissingNativeLibraryReportsFailureAndKeepsSetupAvailable() {
        openSetup()
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

    func testBasicLandToolsPersistAndStatisticsUseActualQuantities() {
        let draftName = uniqueDeckName("LandTools")
        openLibrary()
        tapDiagnosed(app.buttons["New deck"])
        selectDeckBuilderPane("Deck")
        let name = app.textFields["Deck name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        replaceText(name, with: draftName + "\n")
        tapDiagnosed(app.buttons["Deck tools"])
        let basics = app.buttons["Basic lands"]
        reveal(basics); tapDiagnosed(basics)
        let tools = app.buttons["Basic lands · manual counts"]
        reveal(tools); tools.tap()
        let addForest = app.buttons["nativeDeck.basic.add.Forest"]
        let rows = app.scrollViews["nativeDeck.editor.rows"]
        for _ in 0..<5 {
            if addForest.isHittable { break }
            rows.swipeUp()
        }
        XCTAssertTrue(addForest.isHittable)
        waitFor(addForest, predicate: "enabled == true")
        addForest.tap(); addForest.tap()
        let removeForest = app.buttons["nativeDeck.basic.remove.Forest"]
        removeForest.tap()
        capture("Deck builder basic-land controls")
        tapDiagnosed(app.navigationBars.buttons["nativeDeck.editor.save"])
        waitFor(name, predicate: "exists == false")
        app.terminate(); app.launch()
        openLibrary(); openSavedDeck(draftName)
        XCTAssertTrue(app.staticTexts["1 card · Saved locally"].waitForExistence(timeout: 5))
        let stats = app.segmentedControls["nativeDeck.sections"].buttons["nativeDeck.section.stats"]
        reveal(stats); tapDiagnosed(stats)
        waitFor(stats, predicate: "selected == true")
        XCTAssertTrue(app.searchFields["Find a card in this deck"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Main deck only · 1 card"].waitForExistence(timeout: 5))
        capture("Deck statistics from saved quantities")
        let cards = app.segmentedControls["nativeDeck.sections"].buttons["nativeDeck.section.cards"]
        tapDiagnosed(cards)
        waitFor(cards, predicate: "selected == true")
        let forest = app.buttons["nativeDeck.inspect.Forest"]
        reveal(forest); forest.tap()
        XCTAssertTrue(app.navigationBars["Forest"].waitForExistence(timeout: 5))
        capture("Offline card inspection")
        app.buttons["Done"].tap()
    }

    func testLandscapeDeckBuilderSplitAddRotateAndDonePersist() {
        let draftName = uniqueDeckName("LandscapeSplit")
        openLibrary()
        tapDiagnosed(app.buttons["New deck"])
        selectDeckBuilderPane("Deck")
        let name = app.textFields["Deck name"]
        replaceText(name, with: draftName + "\n")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let split = app.otherElements["nativeDeck.builder.split"]
        XCTAssertTrue(split.waitForExistence(timeout: 10))
        let search = app.textFields["nativeDeck.cardSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(name.isHittable, "Deck editor remains visible beside collection.")
        XCTAssertLessThan(search.frame.midX, name.frame.minX)
        replaceText(search, with: "Sol Ring\n")
        let add = app.buttons["nativeDeck.collection.add.Sol Ring"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        let collection = app.scrollViews["nativeDeck.collection.scroll"]
        XCTAssertTrue(collection.waitForExistence(timeout: 5))
        for _ in 0..<5 {
            if add.isHittable { break }
            collection.swipeUp()
        }
        capture("Landscape collection before adding card")
        tapDiagnosed(add)
        let row = app.buttons["nativeDeck.inspect.Sol Ring"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.isHittable, "Collapsed deck tools leave the first card visible without scrolling.")
        XCTAssertGreaterThan(row.frame.minX, search.frame.midX)
        assertDeckQuantity(1, card: "Sol Ring")
        let deckScroll = app.scrollViews["nativeDeck.editor.rows"]
        let increase = app.buttons["Add one Sol Ring"]
        for _ in 0..<4 {
            if increase.isHittable { break }
            deckScroll.swipeUp()
        }
        XCTAssertTrue(increase.isHittable)
        tapDiagnosed(increase)
        assertDeckQuantity(2, card: "Sol Ring")
        let decrease = app.buttons["Remove one Sol Ring"]
        XCTAssertTrue(decrease.isHittable)
        tapDiagnosed(decrease)
        assertDeckQuantity(1, card: "Sol Ring")
        let done = app.navigationBars.buttons["nativeDeck.editor.save"]
        XCTAssertTrue(done.isHittable, "Save stays visible outside the scrolling deck list.")
        capture("Landscape collection and persistent deck pane")
        XCUIDevice.shared.orientation = .portrait
        selectDeckBuilderPane("Deck")
        XCTAssertEqual(name.value as? String, draftName)
        assertDeckQuantity(1, card: "Sol Ring")
        tapDiagnosed(done)
        waitFor(name, predicate: "exists == false")
        app.terminate(); app.launch()
        openLibrary(); openSavedDeck(draftName)
        XCTAssertTrue(app.staticTexts["1 card · Saved locally"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["nativeDeck.inspect.Sol Ring"].exists)
    }

    func testLandscapePartnerDeckKeepsQuantityControlsReachable() {
        let draftName = uniqueDeckName("PartnerLayout")
        openLibrary()
        app.buttons["Import"].tap()
        replaceText(app.textFields["Deck name"], with: draftName)
        let text = app.textViews["Deck list text"]
        text.tap()
        text.typeText("Commander\n1 Rograkh, Son of Rohgahh\n1 Ardenn, Intrepid Archaeologist\n\nDeck\n1 Sol Ring")
        let submit = app.buttons["nativeDeck.import.submit"]
        reveal(submit); tapDiagnosed(submit)
        let confirm = app.buttons["nativeDeck.import.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        reveal(confirm); tapDiagnosed(confirm)
        waitForImportDismissal(text)
        openSavedDeck(draftName)
        let edit = app.buttons["Edit"]
        reveal(edit, scrollingUp: false); tapDiagnosed(edit)
        selectDeckBuilderPane("Deck")
        waitFor(app.textFields["Deck name"], predicate: "exists == true AND hittable == true")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let landscape = NSPredicate { _, _ in self.app.frame.width > self.app.frame.height }
        let rotationResult = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: landscape, object: app)], timeout: 10)
        if rotationResult != .completed {
            captureTransitionDiagnostics("Editor rotation before restoring portrait", control: app.otherElements["nativeDeck.builder.split"])
        }
        XCTAssertEqual(rotationResult, .completed)
        waitFor(app.otherElements["nativeDeck.builder.split"], predicate: "exists == true")
        let rows = app.scrollViews["nativeDeck.editor.rows"]
        let card = rows.buttons["nativeDeck.inspect.Sol Ring"]
        let increase = rows.buttons["Add one Sol Ring"]
        let decrease = rows.buttons["Remove one Sol Ring"]
        for _ in 0..<10 {
            if card.isHittable && increase.isHittable && rows.frame.contains(card.frame) && rows.frame.contains(increase.frame) { break }
            rows.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                .press(forDuration: 0.05, thenDragTo: rows.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
        }
        XCTAssertTrue(rows.frame.contains(card.frame), "A complete row must fit, not just its quantity buttons.")
        XCTAssertTrue(rows.frame.contains(increase.frame))
        XCTAssertTrue(increase.isHittable && decrease.isHittable)
        tapDiagnosed(increase)
        assertDeckQuantity(2, card: "Sol Ring")
        tapDiagnosed(decrease)
        XCTAssertTrue(app.navigationBars.buttons["nativeDeck.editor.save"].isHittable)
        capture("Two commanders with complete editable landscape row")
        tapDiagnosed(app.navigationBars.buttons["nativeDeck.editor.save"])
        XCTAssertTrue(rows.waitForNonExistence(timeout: 5))
    }

    func testDeckFilterKeyboardDismissalKeepsFilterText() {
        openLibrary()
        tapDiagnosed(app.buttons["New deck"])
        selectDeckBuilderPane("Deck")
        tapDiagnosed(app.buttons["Deck tools"])
        let filters = app.buttons["Filter, sort & group"]
        reveal(filters); tapDiagnosed(filters)
        let filter = app.textFields["nativeDeck.deckFilter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        tapDiagnosed(filter)
        filter.typeText("Forest")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        tapDiagnosed(app.buttons["Hide keyboard"])
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(filter.value as? String, "Forest")
        tapDiagnosed(filter)
        filter.typeText("\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(filter.value as? String, "Forest")
    }

    private func selectDeckBuilderPane(_ pane: String) {
        let drawerDone = app.buttons["nativeDeck.searchDrawer.done"]
        if pane == "Deck" {
            if drawerDone.exists {
                tapDiagnosed(drawerDone)
                XCTAssertTrue(drawerDone.waitForNonExistence(timeout: 5))
            }
            XCTAssertTrue(app.textFields["Deck name"].waitForExistence(timeout: 5))
        } else {
            // Landscape already exposes collection search. Portrait opens its drawer.
            if !app.otherElements["nativeDeck.builder.split"].exists && !drawerDone.exists {
                let name = app.textFields["Deck name"]
                if app.keyboards.firstMatch.exists { name.typeText("\n") }
                let addCards = app.buttons["nativeDeck.builder.searchDrawer"]
                XCTAssertTrue(addCards.waitForExistence(timeout: 5))
                tapDiagnosed(addCards)
            }
            XCTAssertTrue(app.textFields["nativeDeck.cardSearch"].waitForExistence(timeout: 5))
        }
    }

    private func assertDeckQuantity(_ quantity: Int, card: String) {
        let row = app.scrollViews["nativeDeck.editor.rows"].buttons["nativeDeck.inspect.\(card)"]
        waitFor(row, predicate: "exists == true AND value == '\(quantity) copies'")
    }

    private func capture(_ title: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = title
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openSetup() {
        let play = app.buttons["menu.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        reveal(play); play.tap()
        XCTAssertTrue(app.textFields["ondevice.playerName"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Gather your table"].exists)
    }

    private func openLibrary() {
        let decks = app.buttons["menu.decks"]
        XCTAssertTrue(decks.waitForExistence(timeout: 15))
        reveal(decks); tapDiagnosed(decks)
        waitFor(app.buttons["Import"], predicate: "exists == true AND hittable == true")
    }

    private func uniqueDeckName(_ suffix: String) -> String {
        let name = "UI-\(UUID().uuidString)-\(suffix)"
        createdDeckNames.append(name)
        return name
    }

    private func searchLibrary(_ name: String) {
        let search = app.searchFields["Find a deck or commander"]
        reveal(search, scrollingUp: false)
        replaceText(search, with: name + "\n")
    }

    private func openSavedDeck(_ name: String) {
        searchLibrary(name)
        let deck = app.buttons["nativeDeck.saved.\(name)"]
        XCTAssertTrue(deck.waitForExistence(timeout: 5))
        reveal(deck); deck.tap()
        XCTAssertTrue(app.navigationBars["Deck details"].waitForExistence(timeout: 5))
    }

    private func replaceText(_ field: XCUIElement, with text: String) {
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let existing = field.value as? String ?? ""
        if !existing.isEmpty && existing != field.placeholderValue {
            // Exercise the visible iPhone edit menu. Hardware Command-A can be
            // ignored by the simulator; backspace depends on the caret position.
            field.press(forDuration: 1.2)
            let selectAll = app.menuItems["Select All"]
            XCTAssertTrue(selectAll.waitForExistence(timeout: 5))
            selectAll.tap()
        }
        field.typeText(text)
        let expected = text.trimmingCharacters(in: .newlines)
        XCTAssertEqual(field.value as? String, expected, "Verify the entered value before saving or searching.")
    }

    /// Never clears the library, defaults, app container, or another test/user's decks.
    /// Relaunch also recovers from a failed test leaving an editor/confirmation open.
    private func cleanupCreatedDecks() {
        for name in createdDeckNames {
            app.terminate(); app.launch()
            let menu = app.buttons["menu.decks"]
            guard menu.waitForExistence(timeout: 15) else {
                XCTFail("Cleanup could not reach library; retained test deck: \(name)"); continue
            }
            menu.tap()
            // Wait for the sheet's actual destination before scrolling. A swipe
            // during presentation can dismiss the sheet instead of revealing search.
            guard app.buttons["Import"].waitForExistence(timeout: 10) else {
                capture("Cleanup library navigation failure")
                XCTFail("Cleanup library did not open; retained test deck: \(name)"); continue
            }
            let search = app.searchFields["Find a deck or commander"]
            guard search.waitForExistence(timeout: 10) else {
                capture("Cleanup library search failure")
                XCTFail("Cleanup search did not appear; retained test deck: \(name)"); continue
            }
            for _ in 0..<5 {
                if search.exists && search.isHittable { break }
                app.swipeDown()
            }
            guard search.exists && search.isHittable else {
                XCTFail("Cleanup search unavailable; retained test deck: \(name)"); continue
            }
            replaceText(search, with: name + "\n")
            let deck = app.buttons["nativeDeck.saved.\(name)"]
            guard deck.waitForExistence(timeout: 3) else { continue } // Never saved, or renamed.
            deck.tap()
            // Filter card rows away so deleting a 100-card copy does not require
            // an unbounded scroll through its artwork. This only changes UI search.
            let cardSearch = app.searchFields["Find a card in this deck"]
            for _ in 0..<5 {
                if cardSearch.exists && cardSearch.isHittable { break }
                app.swipeDown()
            }
            guard cardSearch.exists && cardSearch.isHittable else {
                XCTFail("Cleanup card search unavailable; retained test deck: \(name)"); continue
            }
            replaceText(cardSearch, with: name + "\n")
            let delete = app.buttons["Delete local deck"]
            for _ in 0..<5 {
                if delete.exists && delete.isHittable { break }
                app.swipeUp()
            }
            guard delete.exists && delete.isHittable else {
                XCTFail("Cleanup delete unavailable; retained test deck: \(name)"); continue
            }
            delete.tap()
            // iOS 26 exposes the confirmation action as nested buttons with the
            // same identifier; both represent this one destructive action.
            let confirm = app.buttons.matching(identifier: "nativeDeck.confirmDelete").firstMatch
            guard confirm.waitForExistence(timeout: 5) else {
                XCTFail("Cleanup confirmation unavailable; retained test deck: \(name)"); continue
            }
            confirm.tap()
            waitFor(deck, predicate: "exists == false")
        }
        createdDeckNames.removeAll()
    }

    private func waitFor(_ element: XCUIElement, predicate: String,
                         file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: 10)
        if result != .completed {
            captureTransitionDiagnostics("Failed transition: \(predicate)", control: element)
        }
        XCTAssertEqual(result, .completed, file: file, line: line)
    }

    private func waitForImportDismissal(_ editor: XCUIElement,
                                        file: StaticString = #filePath, line: UInt = #line) {
        waitFor(editor, predicate: "exists == false", file: file, line: line)
        waitFor(app.navigationBars["Import deck"], predicate: "exists == false", file: file, line: line)
        waitFor(app.searchFields["Find a deck or commander"], predicate: "exists == true AND hittable == true",
                file: file, line: line)
    }

    private func tapDiagnosed(_ control: XCUIElement,
                              file: StaticString = #filePath, line: UInt = #line) {
        waitFor(control, predicate: "exists == true AND enabled == true AND hittable == true", file: file, line: line)
        // Historical diagnostics may outlive the screen that made this query unique.
        // Keep the actual tap strict, but do not fail a later action while describing
        // a prior card that now appears in both the catalogue and the deck.
        lastTappedControl = control.firstMatch
        captureTransitionDiagnostics("Before tap: \(control.identifier)", control: control)
        control.tap() // Exactly one tap; a failed transition is never retried.
    }

    private func captureTransitionDiagnostics(_ title: String, control: XCUIElement) {
        func describe(_ element: XCUIElement) -> String {
            guard element.exists else { return "\(element): absent" }
            return "id=\(element.identifier) label=\(element.label) frame=\(element.frame) enabled=\(element.isEnabled) selected=\(element.isSelected) hittable=\(element.isHittable)"
        }
        var lines = ["App frame: \(app.frame)", "Control: \(describe(control))"]
        if let lastTappedControl { lines.append("Last tapped: \(describe(lastTappedControl))") }
        // One hierarchy snapshot includes windows and offscreen error labels;
        // querying every card label separately makes a 100-card deck prohibitively slow.
        lines.append(app.debugDescription)
        let details = XCTAttachment(string: lines.joined(separator: "\n"))
        details.name = title; details.lifetime = .keepAlways; add(details)
        let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screen.name = title + " — whole screen"; screen.lifetime = .keepAlways; add(screen)
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
