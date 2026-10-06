import XCTest

/// Real setup views and Deck Studio in a presentation-only build; no native gameplay or Game Center login.
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
        app.launchArguments = ["-magicmobile.boardAppearance", "arena", "-deckStudio.cards.layout.v1", "List", 
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "--ondevice-setup-ui-test"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["menu.play"].waitForExistence(timeout: 15))
        UITestHarness.settleFirstTouch(app)
    }

    override func tearDownWithError() throws {
        if let app {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            XCUIDevice.shared.orientation = .portrait
            cleanupCreatedDecks()
            app.terminate()
        }
        app = nil
    }

    func testAISkillCanChangeAndSurvivesRelaunch() {
        openSetup()
        let skill = app.steppers["onDevice.aiSkill"]
        reveal(skill)
        waitFor(skill, predicate: "label == 'AI skill: 2'")
        skill.buttons["onDevice.aiSkill-Increment"].tap()
        waitFor(skill, predicate: "label == 'AI skill: 3'")
        capture("AI skill selection")
        app.terminate()
        app.launch()
        openSetup()
        reveal(app.steppers["onDevice.aiSkill"])
        waitFor(app.steppers["onDevice.aiSkill"], predicate: "label == 'AI skill: 3'")
        app.steppers["onDevice.aiSkill"].buttons["onDevice.aiSkill-Decrement"].tap()
        waitFor(app.steppers["onDevice.aiSkill"], predicate: "label == 'AI skill: 2'")
    }

    func testUpdatesShowsInstalledBuildAndSeparatesUpstreamNews() {
        app.buttons["menu.updates"].tap()
        XCTAssertTrue(app.navigationBars["Updates"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Installed build"].exists)
        XCTAssertTrue(app.staticTexts["What's new"].exists)
        // What's new grows with each release: scroll until the upstream note shows.
        let upstreamNote = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "not installed automatically")).firstMatch
        reveal(upstreamNote)
        XCTAssertTrue(upstreamNote.exists)
        let notice = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Independent fan project. Not affiliated with Wizards of the Coast.")).firstMatch
        reveal(notice)
        XCTAssertTrue(notice.label.hasSuffix("Magic: The Gathering and card artwork belong to their respective owners."))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Scryfall")).firstMatch.exists,
                      "Card images must credit Scryfall")
        capture("Updates about and fan-content notice")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["menu.play"].exists)
    }

    /// Every sheet the menu opens wears the tavern (Caleb, 2026-10-03): Updates, Friends, Downloads and
    /// Settings each open over the leather backing and close from their Done button; each is captured.
    func testMenuSheetsOpenAndCloseFromTheirDoneButton() {
        for control in ["menu.updates", "menu.friends", "menu.downloads", "menu.settings"] {
            app.buttons[control].tap()
            let done = app.buttons["Done"].firstMatch
            XCTAssertTrue(done.waitForExistence(timeout: 8), "\(control) must open a sheet")
            capture("tavern sheet \(control)")
            done.tap()
            XCTAssertTrue(app.buttons["menu.play"].waitForExistence(timeout: 5), "\(control)'s sheet must close")
        }
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

    /// Held sideways the main menu is a fixed screen: every action is on screen at once and
    /// nothing scrolls (Caleb, 2026-10-02).
    func testLandscapeMainMenuFitsWithoutScrolling() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = NSPredicate { [app] _, _ in (app?.frame.width ?? 0) > (app?.frame.height ?? 0) }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: landscape, object: nil)], timeout: 10), .completed)
        let screen = app.frame
        for id in ["menu.play", "menu.decks", "menu.settings", "menu.updates", "menu.downloads", "menu.howToPlay"] {
            let control = app.buttons[id]
            guard control.waitForExistence(timeout: 5) else { continue }
            XCTAssertTrue(screen.contains(control.frame), "\(id) must be fully on screen without scrolling")
        }
        XCTAssertFalse(app.scrollViews.containing(.button, identifier: "menu.play").firstMatch.exists,
                       "The landscape menu does not scroll")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "landscape-main-menu"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testPlayButtonWholeLabelRoutesToSetup() {
        for horizontal in [0.15, 0.5, 0.85] {
            let play = app.buttons["menu.play"]
            XCTAssertTrue(play.waitForExistence(timeout: 10))
            reveal(play)
            play.coordinate(withNormalizedOffset: CGVector(dx: horizontal, dy: 0.5)).tap()
            UITestHarness.chooseCustomTable(app)
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
        // The player-mode picker reads AI / Game Center / Online since the relay tables.
        let ai = app.segmentedControls.buttons["AI"]
        reveal(ai, scrollingUp: false)
        ai.tap()
        XCTAssertTrue(app.buttons["Start game"].waitForExistence(timeout: 5))
    }

    func testDeckButtonWholeLabelRoutesToLibrary() {
        for horizontal in [0.15, 0.5, 0.85] {
            let decks = app.buttons["menu.decks"]
            reveal(decks)
            decks.coordinate(withNormalizedOffset: CGVector(dx: horizontal, dy: 0.5)).tap()
            XCTAssertTrue(app.buttons["deckStudio.create"].waitForExistence(timeout: 10))
            tapDiagnosed(app.buttons["deckStudio.library.close"])
            XCTAssertTrue(app.buttons["deckStudio.create"].waitForNonExistence(timeout: 5))
        }
    }

    func testInvalidImportRetainsDraftUntilCancelled() {
        openLibrary()
        tapDiagnosed(app.buttons["deckStudio.import"])
        let editor = app.textViews["Decklist text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let review = app.buttons["deckStudio.import.review"]
        XCTAssertFalse(review.isEnabled)
        let deckName = app.textFields["Deck name"]
        let originalName = deckName.value as? String
        let draft = "this is not a deck entry"
        tapDiagnosed(editor)
        editor.typeText(draft)
        revealOutsideEditor(review)
        tapDiagnosed(review)
        let error = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Line 1:")).firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.label.contains("No cards were imported."))
        XCTAssertFalse(app.buttons["deckStudio.import.confirm"].exists, "An invalid list offers nothing to save")
        revealOutsideEditor(editor, scrollingUp: false)
        XCTAssertEqual(editor.value as? String, draft)
        XCTAssertEqual(deckName.value as? String, originalName)
        capture("Invalid import retains draft")
        tapDiagnosed(app.buttons["deckStudio.import.cancel"])
        waitForImportDismissal(editor)
    }

    func testPasteValidDraftInspectEditSaveAndRelaunch() {
        let originalName = uniqueDeckName("Imported")
        let editedName = uniqueDeckName("Renamed")
        importDeck(named: originalName,
                   text: "1x Emmara, Soul of the Accord (grn) [Commander{top}]\n1x Forest (m21) 274 [Land]")
        openSavedDeck(originalName)
        let inspect = deckRow("Emmara, Soul of the Accord", quantity: 1)
        reveal(inspect); tapDiagnosed(inspect)
        let close = app.buttons["deckStudio.inspector.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Emmara, Soul of the Accord"].exists)
        tapDiagnosed(close)
        renameDeck(editedName)
        saveAndCloseDeck()
        app.terminate(); app.launch()
        openLibrary()
        openSavedDeck(editedName)
        assertSavedDeck(cards: 2)
        XCTAssertTrue(deckRow("Emmara, Soul of the Accord", quantity: 1).exists)
        let forest = deckRow("Forest", quantity: 1)
        reveal(forest)
        // Artwork/network availability is not an acceptance condition for deck persistence.
    }

    func testMoxfieldPlainTextExportPasteKeepsCardsAndQuantities() {
        let importedName = uniqueDeckName("Moxfield")
        importDeck(named: importedName,
                   text: "Commander\n1 Emmara, Soul of the Accord (GRN) 168\n\nDeck\n2 Forest (M21) 274 *F*\n1 Sol Ring (CMM) 396")
        openSavedDeck(importedName)
        assertSavedDeck(cards: 4)
        let forest = deckRow("Forest", quantity: 2)
        reveal(forest)
        XCTAssertTrue(forest.exists, "Forest keeps its imported quantity of 2")
        let ring = deckRow("Sol Ring", quantity: 1)
        reveal(ring)
        XCTAssertTrue(ring.isHittable)
        capture("Moxfield plain-text export imported")
    }

    func testIncludedDeckEditingCopyDoesNotMutateBundledDeck() {
        let copyName = uniqueDeckName("PreconCopy")
        openLibrary()
        searchLibrary("Token Triumph")
        let bundled = app.buttons["deckStudio.deck.precon:token-triumph"].firstMatch
        XCTAssertTrue(bundled.waitForExistence(timeout: 5))
        reveal(bundled); tapDiagnosed(bundled)
        XCTAssertTrue(deckRow("Emmara, Soul of the Accord", quantity: 1).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["deckStudio.save"].exists, "An included deck is read-only")
        capture("Included Commander deck grouped cards")
        tapDiagnosed(app.buttons["Edit a copy"])
        waitFor(app.buttons["deckStudio.save"], predicate: "exists == true")
        renameDeck(copyName)
        saveAndCloseDeck()
        app.terminate(); app.launch()
        openLibrary(); openSavedDeck(copyName)
        assertSavedDeck(cards: 100)
        app.terminate(); app.launch()
        openLibrary(); searchLibrary("Token Triumph")
        XCTAssertTrue(bundled.waitForExistence(timeout: 5))
        reveal(bundled); tapDiagnosed(bundled)
        XCTAssertTrue(deckCount(100).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Included / read-only"].exists)
        XCTAssertTrue(app.staticTexts["Token Triumph"].exists)
        XCTAssertTrue(app.buttons["Edit a copy"].exists)
        XCTAssertFalse(app.buttons["deckStudio.save"].exists)
        tapDiagnosed(app.buttons["deckStudio.close"])
        let options = app.buttons["Options for Token Triumph"].firstMatch
        reveal(options); tapDiagnosed(options)
        XCTAssertTrue(menuItem("Duplicate locally").waitForExistence(timeout: 5))
        XCTAssertFalse(menuItem("Delete local deck").exists, "Included decks cannot be deleted")
    }

    func testEDHRECManualHandoffCopiesWithoutOpeningWebsite() {
        openLibrary()
        searchLibrary("Token Triumph")
        let bundled = app.buttons["deckStudio.deck.precon:token-triumph"].firstMatch
        reveal(bundled); tapDiagnosed(bundled)
        selectWorkspaceTab("Ideas")
        let edhrec = app.buttons["EDHREC"].firstMatch
        tapDiagnosed(edhrec)
        waitFor(edhrec, predicate: "selected == true")
        let copy = app.buttons["Copy commander names"]
        // Ideas scrolls in one list with the deck header, below the pinned tabs.
        let panel = app.scrollViews["deckStudio.ideas.list"]
        UITestHarness.reveal(copy, in: panel)
        XCTAssertTrue(copy.isEnabled)
        tapDiagnosed(copy)
        let confirmation = app.buttons["Commander names copied"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        let website = app.buttons["Browse commanders on EDHREC"]
        UITestHarness.reveal(website, in: panel)
        XCTAssertTrue(website.isEnabled)
        XCTAssertEqual(app.webViews.count, 0, "Copying must not open the website")
        XCTAssertFalse(app.buttons["Reload EDHREC"].exists)
        capture("EDHREC explicit manual handoff")
        // No external browser is opened and no deck is submitted by this test.
    }

    func testEmptyNamedDraftPersistsWithoutClaimingPlayLegality() {
        let draftName = uniqueDeckName("EmptyDraft")
        openLibrary()
        createDeck()
        renameDeck(draftName)
        saveAndCloseDeck()
        app.terminate(); app.launch()
        openLibrary(); openSavedDeck(draftName)
        assertSavedDeck(cards: 0)
        XCTAssertTrue(app.staticTexts["Add your commander and cards. Incomplete drafts are welcome."].exists)
        // The quick check is advisory: it flags the missing commander and names XMage as the authority.
        XCTAssertTrue(app.staticTexts["Quick check · XMage confirms when you play"].exists)
        XCTAssertTrue(app.buttons["Missing commander"].exists)
        // The header's primary action is Play; checking alone moved to the options menu.
        let play = app.buttons["deckStudio.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        XCTAssertEqual(play.label, "Play this deck")
        XCTAssertFalse(app.buttons["This is your playing deck"].exists, "An empty draft is never presented as playing")
        openDeckActions()
        XCTAssertTrue(menuItem("Validate & playtest").waitForExistence(timeout: 5))
        XCTAssertTrue(menuItem("Play this deck").exists)
        // Deliberately do not select/start an incomplete draft.
    }

    func testCommanderFirstDeckQuickAddUndoAndQuickCheck() {
        openLibrary()
        tapDiagnosed(app.buttons["deckStudio.create"])
        let search = app.textFields["deckStudio.commanderFirst.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        replaceText(search, with: "Atraxa")
        let choice = app.buttons["Choose Atraxa, Praetors' Voice as commander"]
        XCTAssertTrue(choice.waitForExistence(timeout: 10))
        tapDiagnosed(choice)
        waitFor(app.buttons["deckStudio.close"], predicate: "exists == true AND hittable == true")
        // The commander leads the deck and names it until the player renames it.
        XCTAssertTrue(deckCount(1).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "Atraxa, Praetors' Voice")).firstMatch.exists)
        XCTAssertFalse(app.buttons["Missing commander"].exists)
        // Quick Add takes a count, ignores a tag with a note, and keeps going.
        let quickAdd = app.textFields["deckStudio.quickAdd"]
        reveal(quickAdd)
        tapDiagnosed(quickAdd)
        quickAdd.typeText("2x Sol Ring [Ramp]\n")
        // The Undo toast lives four seconds (as on Android). Find it first and read the
        // rest of the result from the same screen, so the checks do not outlast it.
        let undo = app.buttons["deckStudio.quickAdd.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        // With the keyboard up the new row lies further down the page than there is room for; the toast
        // says what was added, and the count and the quick check confirm it.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "Added 2", "Sol Ring")).firstMatch.exists)
        XCTAssertTrue(deckCount(3).exists)
        XCTAssertTrue(app.staticTexts["Ignored [Ramp] · sets and tags aren't saved"].exists)
        // Two Sol Rings break singleton; the live check says so without blocking anything.
        XCTAssertTrue(app.buttons["Duplicates, 1 card"].exists)
        XCTAssertTrue(undo.isHittable)
        undo.tap() // Exactly one tap, without the diagnostic capture that would outlast the toast.
        waitFor(deckCount(1), predicate: "exists == true")
        XCTAssertFalse(app.buttons["Duplicates, 1 card"].exists)
        tapDiagnosed(app.buttons["deckStudio.close"])
        let discard = app.buttons["Discard unsaved changes and close"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        tapDiagnosed(discard)
        waitFor(app.buttons["deckStudio.create"], predicate: "exists == true")
    }

    func testCatalogueSearchAddAndQuantityPersistInDraft() {
        let draftName = uniqueDeckName("Catalogue")
        openLibrary()
        createDeck()
        renameDeck(draftName)
        tapDiagnosed(app.buttons["deckStudio.addCards"])
        let search = app.textFields["Card name or rules text"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        replaceText(search, with: "Sol Ring\n")
        let add = app.buttons["Add Sol Ring to deck"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        reveal(add); tapDiagnosed(add)
        XCTAssertTrue(app.buttons["Remove one Sol Ring from deck"].waitForExistence(timeout: 5))
        tapDiagnosed(app.buttons["deckStudio.search.close"])
        let increase = app.buttons["Add one Sol Ring"]
        reveal(increase); tapDiagnosed(increase)
        assertDeckQuantity(2, card: "Sol Ring")
        saveAndCloseDeck()
        app.terminate(); app.launch()
        openLibrary(); openSavedDeck(draftName)
        assertSavedDeck(cards: 2)
        // Verify the persisted row itself, then save a decrement and relaunch again.
        assertDeckQuantity(2, card: "Sol Ring")
        let decrease = app.buttons["Remove one Sol Ring"]
        reveal(decrease); tapDiagnosed(decrease)
        assertDeckQuantity(1, card: "Sol Ring")
        saveAndCloseDeck()
        app.terminate(); app.launch()
        openLibrary(); openSavedDeck(draftName)
        assertSavedDeck(cards: 1)
        assertDeckQuantity(1, card: "Sol Ring")
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
        createDeck()
        renameDeck(draftName)
        openDeckActions()
        tapDiagnosed(menuItem("Basic lands"))
        let apply = app.buttons["deckStudio.basics.apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        // The binder's brass steppers: one element named for the count, holding Decrease and Increase.
        let forest = app.otherElements.matching(NSPredicate(format: "label BEGINSWITH %@", "Forest:")).firstMatch
        reveal(forest)
        waitFor(forest, predicate: "label == 'Forest: 0'")
        let addForest = stepperButton(forest, increment: true)
        tapDiagnosed(addForest); tapDiagnosed(addForest)
        waitFor(forest, predicate: "label == 'Forest: 2'")
        tapDiagnosed(stepperButton(forest, increment: false))
        waitFor(forest, predicate: "label == 'Forest: 1'")
        capture("Deck builder basic-land controls")
        tapDiagnosed(apply)
        waitFor(forest, predicate: "exists == false")
        assertDeckQuantity(1, card: "Forest")
        saveAndCloseDeck()
        app.terminate(); app.launch()
        openLibrary(); openSavedDeck(draftName)
        assertSavedDeck(cards: 1)
        selectWorkspaceTab("Analysis")
        XCTAssertTrue(metric("Main deck", "1").waitForExistence(timeout: 5))
        XCTAssertTrue(metric("Lands in main", "1").exists)
        capture("Deck statistics from saved quantities")
        selectWorkspaceTab("Cards")
        let row = deckRow("Forest", quantity: 1)
        reveal(row); tapDiagnosed(row)
        let close = app.buttons["deckStudio.inspector.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Forest"].exists)
        capture("Offline card inspection")
        tapDiagnosed(close)
    }

    func testLandscapeDeckBuilderSplitAddRotateAndDonePersist() {
        let draftName = uniqueDeckName("LandscapeSplit")
        openLibrary()
        createDeck()
        renameDeck(draftName)
        rotate(to: .landscapeLeft)
        defer { XCUIDevice.shared.orientation = .portrait }
        // Sideways the binder's left page holds the rail, the right page the cards: the All cards shelf
        // puts every card to add where the deck's own cards are.
        // The simulator cancels the first touch after the rotation's system gesture change (see
        // UITestHarness.settleFirstTouch): spend it on the binder's bare leather at the screen's left edge.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5)).tap()
        let allCards = app.buttons["All cards"]
        XCTAssertTrue(allCards.waitForExistence(timeout: 10), "Landscape shows the rail beside the deck")
        let deck = app.scrollViews["deckStudio.cards.list"]
        XCTAssertTrue(deck.waitForExistence(timeout: 5))
        XCTAssertTrue(deck.isHittable, "The deck's page remains visible beside the rail.")
        XCTAssertLessThan(allCards.frame.midX, deck.frame.minX)
        tapDiagnosed(allCards)
        let search = app.textFields["deckStudio.catalogue.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        replaceText(search, with: "Sol Ring\n")
        let add = app.buttons["Add Sol Ring to deck"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(add.frame.minX, search.frame.maxX, "Cards to add are on the right page")
        capture("Landscape collection before adding card")
        tapDiagnosed(add)
        XCTAssertTrue(app.buttons["Remove one Sol Ring from deck"].waitForExistence(timeout: 5))
        // The rail's search changes with the shelf; measure the left page before turning back to My deck.
        let leftPageMid = search.frame.midX
        tapDiagnosed(app.buttons["My deck"])
        let row = deckRow("Sol Ring", quantity: 1)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.isHittable, "The first card is visible without scrolling.")
        XCTAssertGreaterThan(row.frame.minX, leftPageMid)
        let increase = app.buttons["Add one Sol Ring"]
        for _ in 0..<4 {
            if increase.isHittable { break }
            deck.swipeUp()
        }
        XCTAssertTrue(increase.isHittable)
        tapDiagnosed(increase)
        assertDeckQuantity(2, card: "Sol Ring")
        let decrease = app.buttons["Remove one Sol Ring"]
        XCTAssertTrue(decrease.isHittable)
        tapDiagnosed(decrease)
        assertDeckQuantity(1, card: "Sol Ring")
        let save = app.buttons["deckStudio.save"]
        XCTAssertTrue(save.isHittable, "Save stays visible outside the scrolling deck list.")
        capture("Landscape collection and persistent deck pane")
        rotate(to: .portrait)
        XCTAssertTrue(app.staticTexts[draftName].firstMatch.waitForExistence(timeout: 5))
        assertDeckQuantity(1, card: "Sol Ring")
        saveAndCloseDeck()
        app.terminate(); app.launch()
        openLibrary(); openSavedDeck(draftName)
        assertSavedDeck(cards: 1)
        assertDeckQuantity(1, card: "Sol Ring")
    }

    func testLandscapePartnerDeckKeepsQuantityControlsReachable() {
        let draftName = uniqueDeckName("PartnerLayout")
        importDeck(named: draftName,
                   text: "Commander\n1 Rograkh, Son of Rohgahh\n1 Ardenn, Intrepid Archaeologist\n\nDeck\n1 Sol Ring")
        openSavedDeck(draftName)
        rotate(to: .landscapeLeft)
        defer { XCUIDevice.shared.orientation = .portrait }
        let rows = app.scrollViews["deckStudio.cards.list"]
        XCTAssertTrue(rows.waitForExistence(timeout: 10))
        let card = rows.buttons["Inspect Sol Ring, quantity 1"]
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
        assertDeckQuantity(1, card: "Sol Ring")
        let save = app.buttons["deckStudio.save"]
        XCTAssertTrue(save.isHittable)
        capture("Two commanders with complete editable landscape row")
        tapDiagnosed(save)
        tapDiagnosed(app.buttons["deckStudio.close"])
        XCTAssertTrue(rows.waitForNonExistence(timeout: 5))
    }

    func testDeckFilterKeyboardDismissalKeepsFilterText() {
        openLibrary()
        createDeck()
        let filter = app.textFields["deckStudio.cards.search"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        tapDiagnosed(filter)
        filter.typeText("Forest")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        // Dragging the deck list down dismisses the keyboard interactively.
        let list = app.scrollViews["deckStudio.cards.list"]
        list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(filter.value as? String, "Forest")
        tapDiagnosed(filter)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        filter.typeText("\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(filter.value as? String, "Forest")
    }

    // MARK: - Deck Studio helpers

    private func openLibrary() {
        let decks = app.buttons["menu.decks"]
        XCTAssertTrue(decks.waitForExistence(timeout: 15))
        reveal(decks); waitForStableFrame(decks)
        UITestHarness.settleFirstTouch(app) // Tests relaunch before opening the library.
        tapDiagnosed(decks)
        waitFor(app.buttons["deckStudio.create"], predicate: "exists == true AND hittable == true")
    }

    private func createDeck() {
        tapDiagnosed(app.buttons["deckStudio.create"])
        // A new deck opens on the commander picker. These tests start from an empty draft.
        let skip = app.buttons["deckStudio.commanderFirst.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10))
        tapDiagnosed(skip)
        waitFor(skip, predicate: "exists == false")
        waitFor(app.buttons["deckStudio.close"], predicate: "exists == true AND hittable == true")
    }

    private func importDeck(named name: String, text: String) {
        openLibrary()
        tapDiagnosed(app.buttons["deckStudio.import"])
        let field = app.textFields["Deck name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        replaceText(field, with: name)
        let editor = app.textViews["Decklist text"]
        tapDiagnosed(editor)
        editor.typeText(text)
        let review = app.buttons["deckStudio.import.review"]
        revealOutsideEditor(review)
        tapDiagnosed(review)
        let confirm = app.buttons["deckStudio.import.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        tapDiagnosed(confirm)
        // A saved import opens its own workspace, with Play one tap away, and does not
        // change the playing deck. Close it to continue from the library.
        waitFor(editor, predicate: "exists == false")
        let close = app.buttons["deckStudio.close"]
        waitFor(close, predicate: "exists == true AND hittable == true")
        XCTAssertTrue(app.buttons["deckStudio.play"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["This is your playing deck"].exists, "Importing never selects the deck for play")
        tapDiagnosed(close)
        waitFor(close, predicate: "exists == false")
        waitFor(app.textFields["deckStudio.library.search"], predicate: "exists == true")
    }

    private func searchLibrary(_ name: String) {
        let search = app.textFields["deckStudio.library.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        reveal(search, scrollingUp: false)
        replaceText(search, with: name + "\n")
    }

    private func savedDeck(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                         "deckStudio.deck.local:", name)).firstMatch
    }

    private func openSavedDeck(_ name: String) {
        searchLibrary(name)
        let deck = savedDeck(name)
        XCTAssertTrue(deck.waitForExistence(timeout: 5))
        reveal(deck); tapDiagnosed(deck)
        waitFor(app.buttons["deckStudio.close"], predicate: "exists == true AND hittable == true")
    }

    private func openDeckActions() {
        // The workspace's ellipsis menu, a brass plaque on the binder's head.
        let actions = app.buttons["deckStudio.more"]
        tapDiagnosed(actions)
    }

    private func renameDeck(_ name: String) {
        openDeckActions()
        tapDiagnosed(menuItem("Rename deck"))
        let field = app.textFields["Deck name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        replaceText(field, with: name)
        tapDiagnosed(app.buttons["deckStudio.rename.done"])
        waitFor(field, predicate: "exists == false")
    }

    private func saveAndCloseDeck() {
        tapDiagnosed(app.buttons["deckStudio.save"])
        // Closing needs no confirmation once the draft matches what was saved.
        let close = app.buttons["deckStudio.close"]
        tapDiagnosed(close)
        waitFor(close, predicate: "exists == false")
        waitFor(app.buttons["deckStudio.create"], predicate: "exists == true")
    }

    private func selectWorkspaceTab(_ tab: String) {
        let button = app.buttons.matching(NSPredicate(format: "label == %@", tab)).firstMatch
        reveal(button, scrollingUp: false)
        tapDiagnosed(button)
        waitFor(button, predicate: "selected == true")
    }

    private func deckCount(_ cards: Int) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "^\(cards) cards? · Commander$")).firstMatch
    }

    private func assertSavedDeck(cards: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(deckCount(cards).waitForExistence(timeout: 5), "Expected \(cards) cards", file: file, line: line)
        XCTAssertTrue(app.staticTexts["Saved on this device"].exists, file: file, line: line)
    }

    private func deckRow(_ card: String, quantity: Int) -> XCUIElement {
        app.buttons["Inspect \(card), quantity \(quantity)"].firstMatch
    }

    private func assertDeckQuantity(_ quantity: Int, card: String) {
        waitFor(deckRow(card, quantity: quantity), predicate: "exists == true")
    }

    private func metric(_ title: String, _ value: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "\(title), \(value)")).firstMatch
    }

    private func menuItem(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "(elementType == %d OR elementType == %d) AND label == %@",
            XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.menuItem.rawValue, label)).firstMatch
    }

    private func stepperButton(_ stepper: XCUIElement, increment: Bool) -> XCUIElement {
        let name = increment ? "Increment" : "Decrement"
        return stepper.buttons.matching(NSPredicate(format: "label == %@ OR identifier ENDSWITH %@", name, name)).firstMatch
    }

    private func rotate(to orientation: UIDeviceOrientation) {
        XCUIDevice.shared.orientation = orientation
        let wide = orientation.isLandscape
        let settled = NSPredicate { _, _ in (self.app.frame.width > self.app.frame.height) == wide }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: settled, object: app)], timeout: 10)
        if result != .completed {
            captureTransitionDiagnostics("Rotation to \(wide ? "landscape" : "portrait")", control: app)
        }
        XCTAssertEqual(result, .completed)
    }

    /// The menu settles once the selected deck's name and artwork load; a tap before then can miss.
    private func waitForStableFrame(_ element: XCUIElement) {
        var previous = CGRect.null
        for _ in 0..<20 {
            let frame = element.exists && element.isHittable ? element.frame : .null
            if !frame.isNull && frame == previous { return }
            previous = frame
            Thread.sleep(forTimeInterval: 0.25)
        }
    }

    /// The decklist editor scrolls its own text, so drag the page from its margin instead.
    private func revealOutsideEditor(_ element: XCUIElement, scrollingUp: Bool = true,
                                     file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            // Just inside the binder's page, left of the decklist editor (the screen's very edge is the
            // binder's leather, outside the page's scroll).
            let high = app.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.2))
            let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5))
            if scrollingUp { low.press(forDuration: 0.05, thenDragTo: high) }
            else { high.press(forDuration: 0.05, thenDragTo: low) }
        }
        XCTAssertTrue(element.exists && element.isHittable, "Expected accessible control: \(element)", file: file, line: line)
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
        reveal(play)
        UITestHarness.settleFirstTouch(app)
        tapDiagnosed(play)
        UITestHarness.chooseCustomTable(app)
        waitFor(app.textFields["ondevice.playerName"], predicate: "exists == true AND hittable == true")
        XCTAssertTrue(app.staticTexts["Your next game."].exists)
    }

    private func uniqueDeckName(_ suffix: String) -> String {
        let name = "UI-\(UUID().uuidString)-\(suffix)"
        createdDeckNames.append(name)
        return name
    }

    private func replaceText(_ field: XCUIElement, with text: String) {
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        // Delete the old value a few keys at a time: iOS 27 dropped part of an 18-key burst.
        // A long value can leave the caret mid-text; when nothing more deletes, move the
        // caret to the trailing edge and continue until the field is empty.
        for _ in 0..<60 {
            let existing = field.value as? String ?? ""
            if existing.isEmpty || existing == field.placeholderValue { break }
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: min(5, existing.count)))
            if field.value as? String == existing {
                field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
            }
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
            waitForStableFrame(menu)
            UITestHarness.settleFirstTouch(app)
            menu.tap()
            // Wait for the library itself before scrolling. A swipe during
            // presentation can dismiss it instead of revealing search.
            guard app.buttons["deckStudio.create"].waitForExistence(timeout: 10) else {
                capture("Cleanup library navigation failure")
                XCTFail("Cleanup library did not open; retained test deck: \(name)"); continue
            }
            let search = app.textFields["deckStudio.library.search"]
            for _ in 0..<5 {
                if search.exists && search.isHittable { break }
                app.swipeDown()
            }
            guard search.exists && search.isHittable else {
                XCTFail("Cleanup search unavailable; retained test deck: \(name)"); continue
            }
            replaceText(search, with: name + "\n")
            let options = app.buttons["Options for \(name)"].firstMatch
            guard options.waitForExistence(timeout: 3) else { continue } // Never saved, or renamed.
            for _ in 0..<5 {
                if options.isHittable { break }
                app.swipeUp()
            }
            guard options.isHittable else {
                XCTFail("Cleanup options unavailable; retained test deck: \(name)"); continue
            }
            options.tap()
            let delete = menuItem("Delete local deck")
            guard delete.waitForExistence(timeout: 5) else {
                XCTFail("Cleanup delete unavailable; retained test deck: \(name)"); continue
            }
            delete.tap()
            let confirm = app.buttons["Delete \(name)"].firstMatch
            guard confirm.waitForExistence(timeout: 5) else {
                XCTFail("Cleanup confirmation unavailable; retained test deck: \(name)"); continue
            }
            confirm.tap()
            // Cleanup only: after the search keyboard and the menu, this tap can move keyboard
            // focus again and meet the cancelling system-gesture change described at
            // UITestHarness.settleFirstTouch (seen in a real run). A dialog still offering the
            // same button proves the tap was not handled, so confirm it once more.
            if !options.waitForNonExistence(timeout: 3), confirm.exists, confirm.isHittable {
                confirm.tap()
            }
            waitFor(options, predicate: "exists == false")
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
        waitFor(app.buttons["deckStudio.import.cancel"], predicate: "exists == false", file: file, line: line)
        waitFor(app.textFields["deckStudio.library.search"], predicate: "exists == true", file: file, line: line)
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
