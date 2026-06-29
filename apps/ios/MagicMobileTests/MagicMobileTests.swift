import XCTest
import SwiftUI
@testable import MagicMobile

final class MagicMobileTests: XCTestCase {
    
    func testDeckImporter() {
        let deckText = """
        Commander
        1 Sol Ring
        Deck
        4 Island
        4 Forest
        """
        let list = DeckImporter.parse(text: deckText, source: "Test source")
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.commander?.cardName, "Sol Ring")
        XCTAssertEqual(list?.entries.count, 2)
    }
    
    func testCardIdentityHelpers() {
        let landCard = CardIdentity(name: "Island", typeLine: "Basic Land — Island", oracleText: "{T}: Add {U}.")
        XCTAssertTrue(landCard.isLand)
        XCTAssertFalse(landCard.isCreature)
        
        let creatureCard = CardIdentity(name: "Grizzly Bears", typeLine: "Creature — Bear", oracleText: nil)
        XCTAssertFalse(creatureCard.isLand)
        XCTAssertTrue(creatureCard.isCreature)
    }

    func testZoneCardAccessibilityLabelIncludesGameplayState() {
        let card = ZoneCard(
            instanceId: "sol-ring-instance-1234",
            card: CardIdentity(name: "Sol Ring", typeLine: "Artifact", oracleText: "{T}: Add {C}{C}."),
            tapped: true,
            summoningSickness: nil,
            cardIcons: nil,
            counters: nil,
            power: nil,
            toughness: nil,
            isCreaturePermanent: nil,
            damage: nil,
            isAttacking: nil,
            blocking: nil,
            attachedToInstanceId: nil
        )

        XCTAssertEqual(
            card.accessibilityLabel(zoneName: "Hand", selected: true, legal: true, pending: true),
            "Hand card, Sol Ring, Artifact, tapped, playable, pending, selected"
        )
    }

    func testZoneCardAccessibilityIdentifierIsStableAndZoneScoped() {
        let card = ZoneCard(
            instanceId: "ABCDEF12-3456",
            card: CardIdentity(name: "Arcane Signet", typeLine: "Artifact", oracleText: nil),
            tapped: nil,
            summoningSickness: nil,
            cardIcons: nil,
            counters: nil,
            power: nil,
            toughness: nil,
            isCreaturePermanent: nil,
            damage: nil,
            isAttacking: nil,
            blocking: nil,
            attachedToInstanceId: nil
        )

        XCTAssertEqual(card.accessibilityIdentifier(zoneName: "Command Zone"), "card-command-zone-arcane-signet-abcdef12")
    }

    func testPromptCardSelectionRequiresCardFromPromptChoices() {
        let promptCard = ZoneCard(
            instanceId: "discard-forest",
            card: CardIdentity(name: "Forest", typeLine: "Basic Land — Forest", oracleText: nil),
            tapped: nil,
            summoningSickness: nil,
            cardIcons: nil,
            counters: nil,
            power: nil,
            toughness: nil,
            isCreaturePermanent: nil,
            damage: nil,
            isAttacking: nil,
            blocking: nil,
            attachedToInstanceId: nil
        )
        let unrelatedCard = ZoneCard(
            instanceId: "hand-mountain",
            card: CardIdentity(name: "Mountain", typeLine: "Basic Land — Mountain", oracleText: nil),
            tapped: nil,
            summoningSickness: nil,
            cardIcons: nil,
            counters: nil,
            power: nil,
            toughness: nil,
            isCreaturePermanent: nil,
            damage: nil,
            isAttacking: nil,
            blocking: nil,
            attachedToInstanceId: nil
        )

        XCTAssertEqual(PromptSelectionRules.selectedPromptCardId(selectedCard: promptCard, validCards: [promptCard]), "discard-forest")
        XCTAssertNil(PromptSelectionRules.selectedPromptCardId(selectedCard: unrelatedCard, validCards: [promptCard]))
    }

    func testZoneCardDecodesSummoningSicknessFromXMageSnapshot() throws {
        let data = """
        {
          "instanceId": "creature-1",
          "card": {
            "name": "Memnite",
            "typeLine": "Artifact Creature - Construct",
            "oracleText": ""
          },
          "tapped": false,
          "summoningSickness": true,
          "power": 1,
          "toughness": 1
        }
        """.data(using: .utf8)!

        let card = try JSONDecoder.magicMobile.decode(ZoneCard.self, from: data)

        XCTAssertTrue(card.isCreature)
        XCTAssertEqual(card.summoningSickness, true)
        XCTAssertTrue(card.accessibilityLabel(zoneName: "Battlefield").contains("summoning sick"))
    }

    func testZoneCardHidesPowerToughnessForNonCreaturePermanent() throws {
        let data = """
        {
          "instanceId": "sol-ring-1",
          "card": {
            "name": "Sol Ring",
            "typeLine": "Artifact",
            "oracleText": "{T}: Add {C}{C}."
          },
          "isCreaturePermanent": false,
          "power": 0,
          "toughness": 0
        }
        """.data(using: .utf8)!

        let card = try JSONDecoder.magicMobile.decode(ZoneCard.self, from: data)

        XCTAssertFalse(card.isCreature)
        XCTAssertFalse(card.showsPowerToughness)
        XCTAssertFalse(card.accessibilityLabel(zoneName: "Battlefield").contains("0/0"))
    }

    func testZoneCardShowsPowerToughnessForAnimatedPermanent() throws {
        let data = """
        {
          "instanceId": "forest-creature-1",
          "card": {
            "name": "Forest",
            "typeLine": "Basic Land - Forest",
            "oracleText": "{T}: Add {G}."
          },
          "isCreaturePermanent": true,
          "power": 3,
          "toughness": 3
        }
        """.data(using: .utf8)!

        let card = try JSONDecoder.magicMobile.decode(ZoneCard.self, from: data)

        XCTAssertTrue(card.isCreature)
        XCTAssertTrue(card.showsPowerToughness)
        XCTAssertTrue(card.accessibilityLabel(zoneName: "Battlefield").contains("3/3"))
    }

    func testZoneCardDecodesAndFiltersXMageAbilityIcons() throws {
        let data = """
        {
          "instanceId": "creature-1",
          "card": {
            "name": "Serra Angel",
            "typeLine": "Creature - Angel",
            "oracleText": "Flying, vigilance"
          },
          "cardIcons": [
            {
              "iconType": "ABILITY_FLYING",
              "resourceName": "prepared/feather-alt.svg",
              "category": "ABILITY",
              "hint": "Flying"
            },
            {
              "iconType": "ABILITY_VIGILANCE",
              "resourceName": "prepared/eye.svg",
              "category": "ABILITY",
              "hint": "Vigilance"
            }
          ]
        }
        """.data(using: .utf8)!

        let card = try JSONDecoder.magicMobile.decode(ZoneCard.self, from: data)

        XCTAssertEqual(card.visibleXmageIcons.map(\.iconType), ["ABILITY_FLYING", "ABILITY_VIGILANCE"])
        XCTAssertEqual(CardImageURL.xmageIconAssetName(for: "ABILITY_FLYING"), "xmage-icon-flying")
        XCTAssertTrue(card.accessibilityLabel(zoneName: "Battlefield").contains("Flying"))
        XCTAssertTrue(card.accessibilityLabel(zoneName: "Battlefield").contains("Vigilance"))
    }

    func testZoneCardDecodesPermanentCounterBadgesFromXMageSnapshot() throws {
        let data = """
        {
          "instanceId": "creature-1",
          "card": {
            "name": "Furnace Whelp",
            "typeLine": "Creature - Dragon",
            "oracleText": "Flying"
          },
          "counters": {
            "+1/+1": 2,
            "shield": 1,
            "charge": 3
          },
          "power": 2,
          "toughness": 2
        }
        """.data(using: .utf8)!

        let card = try JSONDecoder.magicMobile.decode(ZoneCard.self, from: data)

        XCTAssertEqual(card.counterBadges.map(\.label), ["+1/+1", "SHD", "CHARGE"])
        XCTAssertEqual(card.counterBadges.map(\.count), [2, 1, 3])
        XCTAssertTrue(card.accessibilityLabel(zoneName: "Battlefield").contains("+1/+1 counter 2"))
        XCTAssertTrue(card.accessibilityLabel(zoneName: "Battlefield").contains("SHD counter 1"))
    }

    func testGameplayBoardBackgroundAssetIsBundled() {
        XCTAssertNotNil(UIImage(named: MagicMobileAssetName.boardBackground))
        XCTAssertNotNil(UIImage(named: MagicMobileAssetName.menuBackground))
        XCTAssertNotNil(UIImage(named: MagicMobileAssetName.portraitBoardBackground))
        XCTAssertNotNil(UIImage(named: MagicMobileAssetName.portraitMenuBackground))
    }

    func testPortraitOrientationModeDefaultsToLandscapeOnlyMask() {
        UserDefaults.standard.removeObject(forKey: PortraitModePreference.key)
        defer { UserDefaults.standard.removeObject(forKey: PortraitModePreference.key) }

        XCTAssertFalse(UserDefaults.standard.bool(forKey: PortraitModePreference.key))
        XCTAssertEqual(GameOrientationMode.supportedOrientations(portraitEnabled: false), [.landscapeLeft, .landscapeRight])
        XCTAssertTrue(GameOrientationMode.supportedOrientations(portraitEnabled: true).contains(.portrait))
        XCTAssertTrue(GameOrientationMode.supportedOrientations(portraitEnabled: true).contains(.landscapeLeft))
        XCTAssertTrue(GameOrientationMode.supportedOrientations(portraitEnabled: true).contains(.landscapeRight))
    }

    func testPortraitLayoutSelectionRequiresSettingAndTallGeometry() {
        XCTAssertFalse(GameOrientationMode.isPortraitLayout(size: CGSize(width: 430, height: 932), portraitEnabled: false))
        XCTAssertTrue(GameOrientationMode.isPortraitLayout(size: CGSize(width: 430, height: 932), portraitEnabled: true))
        XCTAssertFalse(GameOrientationMode.isPortraitLayout(size: CGSize(width: 932, height: 430), portraitEnabled: true))
    }

    func testPlayerNameIsCleanedBeforeCommanderStartupConfig() {
        XCTAssertNil(MagicMobileAPI.cleanPlayerName("   "))
        XCTAssertEqual(MagicMobileAPI.cleanPlayerName(" Caleb "), "Caleb")
        XCTAssertEqual(MagicMobileAPI.cleanPlayerName("1234567890123456789012345678"), "123456789012345678901234")
    }

    func testCommanderConfigEncodesHumanDisplayName() throws {
        let config = CommanderGameConfig(
            roomId: "room-1",
            humanPlayerId: "human",
            humanDisplayName: "Caleb",
            humanDeck: PreconCatalog.all[0].deckList,
            aiPlayers: [],
            startingLife: 40,
            commanderDamageEnabled: true
        )
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder.magicMobile.encode(config)) as? [String: Any]
        XCTAssertEqual(encoded?["humanDisplayName"] as? String, "Caleb")
    }

    func testHTMLServerErrorsAreSanitizedForPhoneAlerts() {
        let html = """
        <!DOCTYPE html><html><head><title>MagicMobile</title></head><body>Not the API</body></html>
        """.data(using: .utf8)!

        let message = MagicMobileAPI.sanitizedServerMessage(
            data: html,
            statusCode: 502,
            contentType: "text/html; charset=utf-8"
        )

        XCTAssertTrue(message.contains("HTTP 502"))
        XCTAssertTrue(message.contains("expected a JSON XMage gateway response"))
        XCTAssertFalse(message.contains("<!DOCTYPE html>"))
    }

    func testBattlefieldCardMetricsPreserveMagicCardAspectRatio() {
        let metrics = BattlefieldLayoutMetrics(
            size: CGSize(width: 932, height: 430),
            safeArea: EdgeInsets(top: 0, leading: 47, bottom: 21, trailing: 47)
        )

        XCTAssertEqual(metrics.handCardHeight / metrics.handCardWidth, BattlefieldLayoutMetrics.magicCardHeightToWidth, accuracy: 0.01)
        XCTAssertEqual(metrics.permanentCardHeight / metrics.permanentCardWidth, BattlefieldLayoutMetrics.magicCardHeightToWidth, accuracy: 0.01)
        XCTAssertEqual(metrics.landCardHeight / metrics.landCardWidth, BattlefieldLayoutMetrics.magicCardHeightToWidth, accuracy: 0.01)
    }

    func testCardImageURLCanForcePlaceholdersForVisualQA() {
        XCTAssertNil(CardImageURL.normal("Sol Ring", forcePlaceholder: true))
    }

    func testCardImageManifestDecodesInspectionUrlsCompatibly() throws {
        let response = try JSONDecoder.magicMobile.decode(CardImageManifestResponse.self, from: #"""
        {
          "metadata": {
            "provider": "scryfall",
            "status": "ready",
            "cardCount": 1,
            "imageCount": 1,
            "missingImageCount": 0,
            "symbolCount": 0
          },
          "images": [
            {
              "name": "Sol Ring",
              "url": "https://cards.scryfall.io/small/front/a/b/sol-ring.jpg",
              "normalUrl": "https://cards.scryfall.io/normal/front/a/b/sol-ring.jpg",
              "inspectionUrl": "https://cards.scryfall.io/large/front/a/b/sol-ring.jpg"
            }
          ]
        }
        """#.data(using: .utf8)!)

        XCTAssertEqual(response.images.first?.url, "https://cards.scryfall.io/small/front/a/b/sol-ring.jpg")
        XCTAssertEqual(response.images.first?.normalUrl, "https://cards.scryfall.io/normal/front/a/b/sol-ring.jpg")
        XCTAssertEqual(response.images.first?.inspectionUrl, "https://cards.scryfall.io/large/front/a/b/sol-ring.jpg")
    }

    func testManaSymbolBundledFallbackNamesAreDeterministic() {
        XCTAssertEqual(CardImageURL.bundledSymbolAssetName(for: "{W}"), "mana-w")
        XCTAssertEqual(CardImageURL.bundledSymbolAssetName(for: "U"), "mana-u")
        XCTAssertEqual(CardImageURL.bundledSymbolAssetName(for: "{B}"), "mana-b")
        XCTAssertEqual(CardImageURL.bundledSymbolAssetName(for: "{R}"), "mana-r")
        XCTAssertEqual(CardImageURL.bundledSymbolAssetName(for: "{G}"), "mana-g")
        XCTAssertEqual(CardImageURL.bundledSymbolAssetName(for: "{C}"), "mana-c")
        XCTAssertNil(CardImageURL.bundledSymbolAssetName(for: "{2}"))
    }

    func testCommanderHudSummaryUsesLiveSnapshotCounts() {
        let player = PlayerGameState(
            playerId: "human",
            displayName: nil,
            life: 37,
            poison: 0,
            commanderTax: 2,
            manaPool: nil,
            zones: PlayerZones(
                library: [zoneCard(id: "library-1", name: "Forest", typeLine: "Basic Land"), zoneCard(id: "library-2", name: "Island", typeLine: "Basic Land")],
                hand: [
                    zoneCard(id: "hand-1", name: "Sol Ring", typeLine: "Artifact"),
                    zoneCard(id: "hand-2", name: "Forest", typeLine: "Basic Land"),
                    zoneCard(id: "hand-3", name: "Swords to Plowshares", typeLine: "Instant")
                ],
                battlefield: [],
                graveyard: [zoneCard(id: "grave-1", name: "Memnite", typeLine: "Artifact Creature")],
                exile: [],
                command: [zoneCard(id: "command-1", name: "Isamaru", typeLine: "Legendary Creature")],
                stack: []
            ),
            commanderDamage: ["ai": 4]
        )

        let summary = CommanderHudSummary(player: player, opponentId: "ai")

        XCTAssertEqual(summary.life, 37)
        XCTAssertEqual(summary.commanderTax, 2)
        XCTAssertEqual(summary.handCount, 3)
        XCTAssertEqual(summary.libraryCount, 2)
        XCTAssertEqual(summary.graveyardCount, 1)
        XCTAssertEqual(summary.exileCount, 0)
        XCTAssertEqual(summary.commanderDamage, 4)
    }

    func testWebSocketEndpointUsesExplicitGatewayOverride() throws {
        let url = try XCTUnwrap(MagicMobileWebSocketEndpoint.url(
            gameId: "game/with/slash",
            httpBaseURL: try XCTUnwrap(URL(string: "http://127.0.0.1:3002")),
            overrideBaseText: "http://127.0.0.1:17171"
        ))

        XCTAssertEqual(url.absoluteString, "ws://127.0.0.1:17171/ws/games/game%2Fwith%2Fslash")
    }

    func testWebSocketEndpointFallsBackToHTTPBaseWhenNoOverrideIsSet() throws {
        let url = try XCTUnwrap(MagicMobileWebSocketEndpoint.url(
            gameId: "game-1",
            httpBaseURL: try XCTUnwrap(URL(string: "https://example.com/mobile")),
            overrideBaseText: nil
        ))

        XCTAssertEqual(url.absoluteString, "wss://example.com/mobile/ws/games/game-1")
    }

    func testCompactPhaseTitlesFitLandscapeStatusRail() {
        XCTAssertEqual("untap".compactPhaseTitle, "Untap")
        XCTAssertEqual("upkeep".compactPhaseTitle, "Upkeep")
        XCTAssertEqual("draw".compactPhaseTitle, "Draw")
        XCTAssertEqual("precombat-main".compactPhaseTitle, "Main 1")
        XCTAssertEqual("postcombat-main".compactPhaseTitle, "Main 2")
        XCTAssertEqual("begin-combat".compactPhaseTitle, "Combat")
        XCTAssertEqual("declare-attackers".compactPhaseTitle, "Attackers")
        XCTAssertEqual("declare-blockers".compactPhaseTitle, "Blockers")
        XCTAssertEqual("combat-damage".compactPhaseTitle, "Damage")
        XCTAssertEqual("end".compactPhaseTitle, "End")
        XCTAssertEqual("cleanup".compactPhaseTitle, "Cleanup")
    }

    func testSkipTurnLabelAdaptsToActivePlayer() throws {
        let action = try decodeAction(type: "pass_until_next_turn")
        let humanActive = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: minimalSnapshotJSON(id: "human-active"))
        let aiActiveData = String(data: try minimalSnapshotJSON(id: "ai-active"), encoding: .utf8)!
            .replacingOccurrences(of: #""activePlayerId": "human""#, with: #""activePlayerId": "ai-1""#)
            .data(using: .utf8)!
        let aiActive = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: aiActiveData)

        XCTAssertEqual(MagicPathPhaseRail.skipButtonLabel(snapshot: humanActive, action: action), "SKIP")
        XCTAssertEqual(MagicPathPhaseRail.skipButtonLabel(snapshot: aiActive, action: action), "SKIP")
    }

    func testCastSubmissionClassifierRecognizesPaymentPrompt() throws {
        let before = try snapshotWithHumanHand(cardId: "sol-ring-1", cardName: "Sol Ring")
        let action = try decodeAction(type: "cast_spell", extra: #""sourceInstanceId": "sol-ring-1""#)
        let afterData = String(data: try minimalSnapshotJSON(id: "payment"), encoding: .utf8)!
            .replacingOccurrences(of: #""hand": []"#, with: #""hand": [{ "instanceId": "sol-ring-1", "card": { "name": "Sol Ring", "typeLine": "Artifact", "oracleText": "" } }]"#)
            .replacingOccurrences(of: #""legalActions": []"#, with: #""promptEnvelopeV2": { "id": "mana-1", "method": "GAME_PLAY_MANA", "messageId": 1, "playerId": "human", "responseKind": "mana", "message": "Pay {1}", "responseCommand": { "type": "play_mana", "promptId": "mana-1", "messageId": 1 } }, "legalActions": []"#)
            .data(using: .utf8)!
        let after = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: afterData)

        XCTAssertEqual(CastSubmissionClassifier.classify(action: action, before: before, after: after), .payment)
    }

    func testCastSubmissionClassifierFlagsRejectedStillInHand() throws {
        let before = try snapshotWithHumanHand(cardId: "jaspera-1", cardName: "Jaspera Sentinel")
        let action = try decodeAction(type: "cast_spell", extra: #""sourceInstanceId": "jaspera-1""#)
        let after = try snapshotWithHumanHand(cardId: "jaspera-1", cardName: "Jaspera Sentinel")

        XCTAssertEqual(CastSubmissionClassifier.classify(action: action, before: before, after: after), .rejectedStillInHand)
    }

    func testCastSubmissionClassifierPollsBeforeRejectingDelayedPaymentCast() throws {
        let before = try snapshotWithHumanHand(cardId: "arcane-signet-1", cardName: "Arcane Signet")
        let action = try decodeAction(type: "cast_spell", extra: #""sourceInstanceId": "arcane-signet-1", "requiresPayment": true"#)
        let afterData = String(data: try minimalSnapshotJSON(id: "arcane-delayed-payment"), encoding: .utf8)!
            .replacingOccurrences(of: #""hand": []"#, with: #""hand": [{ "instanceId": "arcane-signet-1", "card": { "name": "Arcane Signet", "typeLine": "Artifact", "oracleText": "" } }]"#)
            .data(using: .utf8)!
        let after = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: afterData)

        XCTAssertTrue(CastSubmissionClassifier.shouldPollForDelayedOutcome(action: action, before: before, after: after))
    }

    func testCastSubmissionClassifierKeepsWaitingThroughIntermediateCastSnapshots() throws {
        let before = try snapshotWithHumanHand(cardId: "arcane-signet-1", cardName: "Arcane Signet")
        let action = try decodeAction(type: "cast_spell", extra: #""sourceInstanceId": "arcane-signet-1", "requiresPayment": true"#)
        let intermediateData = String(data: try minimalSnapshotJSON(id: "arcane-intermediate"), encoding: .utf8)!
            .replacingOccurrences(of: #""bridgeRevision": 1"#, with: #""bridgeRevision": 2"#)
            .replacingOccurrences(of: #""hand": []"#, with: #""hand": [{ "instanceId": "arcane-signet-1", "card": { "name": "Arcane Signet", "typeLine": "Artifact", "oracleText": "" } }]"#)
            .data(using: .utf8)!
        let intermediate = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: intermediateData)

        XCTAssertTrue(CastSubmissionClassifier.shouldKeepPollingForCastOutcome(action: action, before: before, after: intermediate))
    }

    func testCastSubmissionClassifierDoesNotTreatPassivePriorityAsCastProgress() throws {
        let before = try snapshotWithHumanHand(cardId: "arcane-signet-1", cardName: "Arcane Signet")
        let action = try decodeAction(type: "cast_spell", extra: #""sourceInstanceId": "arcane-signet-1", "requiresPayment": true"#)
        let passiveData = String(data: try minimalSnapshotJSON(id: "passive-after-cast"), encoding: .utf8)!
            .replacingOccurrences(of: #""bridgeRevision": 1"#, with: #""bridgeRevision": 6"#)
            .replacingOccurrences(of: #""promptText": "Your priority""#, with: #""promptText": "Play spells and abilities""#)
            .replacingOccurrences(of: #""hand": []"#, with: #""hand": [{ "instanceId": "arcane-signet-1", "card": { "name": "Arcane Signet", "typeLine": "Artifact", "oracleText": "" } }]"#)
            .replacingOccurrences(of: #""legalActions": []"#, with: #""promptEnvelopeV2": { "id": "passive-priority", "method": "GAME_SELECT", "messageId": 14, "playerId": "human", "responseKind": "card", "message": "Play spells and abilities" }, "legalActions": []"#)
            .data(using: .utf8)!
        let passive = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: passiveData)

        XCTAssertTrue(CastSubmissionClassifier.shouldKeepPollingForCastOutcome(action: action, before: before, after: passive))
        XCTAssertEqual(CastSubmissionClassifier.classify(action: action, before: before, after: passive), .rejectedStillInHand)
    }

    func testCastSubmissionClassifierPollsDelayedLandPlay() throws {
        let before = try snapshotWithHumanHand(cardId: "forest-1", cardName: "Forest")
        let action = try decodeAction(type: "play_land", extra: #""sourceInstanceId": "forest-1", "cardInstanceId": "forest-1", "sourceZone": "hand""#)
        let passiveData = String(data: try minimalSnapshotJSON(id: "passive-after-land"), encoding: .utf8)!
            .replacingOccurrences(of: #""bridgeRevision": 1"#, with: #""bridgeRevision": 3"#)
            .replacingOccurrences(of: #""promptText": "Your priority""#, with: #""promptText": "Play spells and abilities""#)
            .replacingOccurrences(of: #""hand": []"#, with: #""hand": [{ "instanceId": "forest-1", "card": { "name": "Forest", "typeLine": "Basic Land - Forest", "oracleText": "" } }]"#)
            .data(using: .utf8)!
        let passive = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: passiveData)

        XCTAssertTrue(CastSubmissionClassifier.shouldKeepPollingForCastOutcome(action: action, before: before, after: passive))
        XCTAssertEqual(CastSubmissionClassifier.classify(action: action, before: before, after: passive), .rejectedStillInHand)
    }

    func testCastSubmissionClassifierStopsWaitingWhenPaymentPromptArrives() throws {
        let before = try snapshotWithHumanHand(cardId: "arcane-signet-1", cardName: "Arcane Signet")
        let action = try decodeAction(type: "cast_spell", extra: #""sourceInstanceId": "arcane-signet-1", "requiresPayment": true"#)
        let paymentData = String(data: try minimalSnapshotJSON(id: "arcane-payment"), encoding: .utf8)!
            .replacingOccurrences(of: #""bridgeRevision": 1"#, with: #""bridgeRevision": 3"#)
            .replacingOccurrences(of: #""hand": []"#, with: #""hand": [{ "instanceId": "arcane-signet-1", "card": { "name": "Arcane Signet", "typeLine": "Artifact", "oracleText": "" } }]"#)
            .replacingOccurrences(of: #""legalActions": []"#, with: #""promptEnvelopeV2": { "id": "mana-arcane", "method": "GAME_PLAY_MANA", "messageId": 8, "playerId": "human", "responseKind": "mana", "message": "Pay {2}", "responseCommand": { "type": "play_mana", "promptId": "mana-arcane", "messageId": 8 } }, "legalActions": []"#)
            .data(using: .utf8)!
        let payment = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: paymentData)

        XCTAssertFalse(CastSubmissionClassifier.shouldKeepPollingForCastOutcome(action: action, before: before, after: payment))
        XCTAssertEqual(CastSubmissionClassifier.classify(action: action, before: before, after: payment), .payment)
    }

    func testCastSubmissionClassifierTreatsChoicePromptAsCastProgress() throws {
        let before = try snapshotWithHumanHand(cardId: "frontier-siege-1", cardName: "Frontier Siege")
        let action = try decodeAction(type: "cast_spell", extra: #""sourceInstanceId": "frontier-siege-1", "requiresPayment": false"#)
        let promptData = String(data: try minimalSnapshotJSON(id: "mode-after-cast"), encoding: .utf8)!
            .replacingOccurrences(of: #""bridgeRevision": 1"#, with: #""bridgeRevision": 4"#)
            .replacingOccurrences(of: #""hand": []"#, with: #""hand": [{ "instanceId": "frontier-siege-1", "card": { "name": "Frontier Siege", "typeLine": "Enchantment", "oracleText": "" } }]"#)
            .replacingOccurrences(of: #""legalActions": []"#, with: #""promptEnvelopeV2": { "id": "mode-1", "method": "GAME_SELECT", "messageId": 12, "playerId": "human", "responseKind": "mode", "message": "Choose one", "responseCommand": { "type": "choose_mode", "promptId": "mode-1", "messageId": 12 } }, "legalActions": []"#)
            .data(using: .utf8)!
        let after = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: promptData)

        XCTAssertFalse(CastSubmissionClassifier.shouldKeepPollingForCastOutcome(action: action, before: before, after: after))
        XCTAssertEqual(CastSubmissionClassifier.classify(action: action, before: before, after: after), .waiting)
    }

    func testStartupOpeningPromptDiagnosticsDecodeFromBridgeSnapshot() throws {
        let snapshotData = String(data: try minimalSnapshotJSON(id: "game-startup-diagnostics"), encoding: .utf8)!
            .replacingOccurrences(of: #""pendingStatus": null"#, with: #""pendingStatus": null, "startupOpeningPrompts": [{ "promptId": "xmage-prompt-start", "method": "GAME_SELECT", "responseKind": "player", "message": "Choose starting player", "playerId": "human", "bridgeRevision": 12, "xmageCycle": 34 }]"#)
            .data(using: .utf8)!

        let snapshot = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: snapshotData)

        XCTAssertEqual(snapshot.startupOpeningPrompts?.first?.method, "GAME_SELECT")
        XCTAssertEqual(snapshot.startupOpeningPrompts?.first?.responseKind, "player")
        XCTAssertEqual(snapshot.startupOpeningPrompts?.first?.message, "Choose starting player")
    }

    func testMagicPathLayerCatalogIncludesRequiredBoardLayers() {
        let layers = GameBoardZoneCatalog.requiredLayerNames

        XCTAssertTrue(layers.contains(.handRail))
        XCTAssertTrue(layers.contains(.promptPanel))
        XCTAssertTrue(layers.contains(.phasePriorityBar))
        XCTAssertTrue(layers.contains(.unsupportedPromptFallback))
        XCTAssertEqual(GameBoardLayoutSpec.magicPathLandscape.canvasSize.width, 956)
        XCTAssertEqual(GameBoardLayoutSpec.magicPathLandscape.canvasSize.height, 440)
    }

    func testDesignPreviewSnapshotIsClearlyNotGameplayProof() {
        let snapshot = GameBoardPreviewFixtures.snapshot(.manaPaymentPrompt)

        XCTAssertEqual(snapshot.source, "design-preview")
        XCTAssertEqual(snapshot.promptEnvelopeV2?.responseKind, "mana")
        XCTAssertEqual(snapshot.engineHealth?.reason, "Design preview only. Not gameplay proof.")
    }

    func testLegalActionPreservesCommandTemplateValues() throws {
        let data = """
        {
          "id": "mana-action",
          "type": "make_mana",
          "playerId": "human",
          "label": "Add {G}",
          "sourceInstanceId": "forest-instance",
          "commandTemplate": {
            "type": "make_mana",
            "sourceInstanceId": "forest-instance",
            "abilityId": "mana-ability",
            "expectedBridgeRevision": 42
          }
        }
        """.data(using: .utf8)!

        let action = try JSONDecoder.magicMobile.decode(LegalAction.self, from: data)

        XCTAssertEqual(action.commandTemplate?["sourceInstanceId"]?.stringValue, "forest-instance")
        XCTAssertEqual(action.commandTemplate?["abilityId"]?.stringValue, "mana-ability")
        XCTAssertEqual(action.commandTemplate?["expectedBridgeRevision"]?.stringValue, "42")
    }

    func testGameCommandEncodesExpectedBridgeRevision() throws {
        let command = GameCommand(
            type: "make_mana",
            gameId: "game-1",
            playerId: "human",
            sourceInstanceId: "forest-instance",
            abilityId: "mana-ability",
            expectedBridgeRevision: 42
        )

        let payload = try JSONSerialization.jsonObject(with: JSONEncoder.magicMobile.encode(command)) as? [String: Any]

        XCTAssertEqual(payload?["expectedBridgeRevision"] as? Int, 42)
        XCTAssertEqual(payload?["sourceInstanceId"] as? String, "forest-instance")
        XCTAssertEqual(payload?["abilityId"] as? String, "mana-ability")
    }

    func testPreparedDragCastCommandUsesCommandTemplateSourceAndRevision() throws {
        let action = try decodeAction(
            type: "cast_spell",
            extra: #"""
            "cardInstanceId": "local-card-id",
            "sourceInstanceId": "local-source-id",
            "commandTemplate": {
              "type": "cast_spell",
              "cardInstanceId": "xmage-card-id",
              "sourceInstanceId": "xmage-source-id",
              "sourceZone": "hand"
            }
            """#
        )

        let command = try MagicMobileAPI(baseURL: URL(string: "http://localhost")!)
            .preparedCommand(for: action, gameId: "game-1", expectedBridgeRevision: 17)
        let payload = try JSONSerialization.jsonObject(with: JSONEncoder.magicMobile.encode(command)) as? [String: Any]

        XCTAssertEqual(payload?["type"] as? String, "cast_spell")
        XCTAssertEqual(payload?["cardInstanceId"] as? String, "xmage-card-id")
        XCTAssertEqual(payload?["sourceInstanceId"] as? String, "xmage-source-id")
        XCTAssertEqual(payload?["sourceZone"] as? String, "hand")
        XCTAssertEqual(payload?["expectedBridgeRevision"] as? Int, 17)
    }

    func testPreparedCommanderCastCommandPreservesCommandZoneSourceAndFromZone() throws {
        let action = try decodeAction(
            type: "cast_spell",
            label: "Cast Isamaru, Hound of Konda",
            extra: #"""
            "cardInstanceId": "local-command-id",
            "sourceInstanceId": "local-command-id",
            "commandTemplate": {
              "type": "cast_spell",
              "cardInstanceId": "xmage-commander-id",
              "sourceInstanceId": "xmage-commander-id",
              "sourceZone": "command"
            }
            """#
        )

        let command = try MagicMobileAPI(baseURL: URL(string: "http://localhost")!)
            .preparedCommand(for: action, gameId: "game-1", expectedBridgeRevision: 18)
        let payload = try JSONSerialization.jsonObject(with: JSONEncoder.magicMobile.encode(command)) as? [String: Any]

        XCTAssertEqual(payload?["type"] as? String, "cast_spell")
        XCTAssertEqual(payload?["cardInstanceId"] as? String, "xmage-commander-id")
        XCTAssertEqual(payload?["sourceInstanceId"] as? String, "xmage-commander-id")
        XCTAssertEqual(payload?["sourceZone"] as? String, "command")
        XCTAssertEqual(payload?["fromZone"] as? String, "command")
        XCTAssertEqual(payload?["expectedBridgeRevision"] as? Int, 18)
    }

    func testPromptActionCommandPreservesMessageIdWithoutTemplate() throws {
        let data = """
        {
          "id": "target-action",
          "type": "choose_target",
          "playerId": "human",
          "label": "Choose target",
          "promptId": "xmage-prompt-77",
          "messageId": 77,
          "targetIds": ["target-1"]
        }
        """.data(using: .utf8)!

        let action = try JSONDecoder.magicMobile.decode(LegalAction.self, from: data)
        let command = try MagicMobileAPI(baseURL: URL(string: "http://localhost")!)
            .command(for: action, gameId: "game-1")
        let payload = try JSONSerialization.jsonObject(with: JSONEncoder.magicMobile.encode(command)) as? [String: Any]

        XCTAssertEqual(payload?["promptId"] as? String, "xmage-prompt-77")
        XCTAssertEqual(payload?["messageId"] as? Int, 77)
        XCTAssertEqual(payload?["targetIds"] as? [String], ["target-1"])
    }

    func testPromptActionsFailClosedWhenRequiredValuesAreMissing() throws {
        let api = MagicMobileAPI(baseURL: URL(string: "http://localhost")!)
        for type in ["choose_pile", "choose_amount", "play_x_mana", "play_mana", "choose_mana", "answer_yes_no", "commander_replacement", "choose_ability"] {
            let action = try decodeAction(type: type)
            XCTAssertThrowsError(try api.command(for: action, gameId: "game-1"), "Expected \(type) to require explicit XMage prompt data")
        }
    }

    func testManaUndoIsOnlyAvailableFromExactXmageLegalActions() throws {
        let snapshotData = String(data: try minimalSnapshotJSON(id: "game-mana-undo"), encoding: .utf8)!
            .replacingOccurrences(of: #""manaPool": { "W": 0, "U": 0, "B": 0, "R": 0, "G": 0, "C": 0 }"#, with: #""manaPool": { "W": 0, "U": 0, "B": 0, "R": 0, "G": 1, "C": 0 }"#)
            .data(using: .utf8)!
        let snapshot = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: snapshotData)

        XCTAssertTrue(ManaPaymentTray.manaUndoActions(in: snapshot).isEmpty)
        XCTAssertEqual(ManaPaymentTray.manaUndoUnavailableText(in: snapshot), "XMage has not exposed mana undo")

        let undoAction = try decodeAction(type: "cancel_payment")
        let command = try MagicMobileAPI(baseURL: URL(string: "http://localhost")!)
            .command(for: undoAction, gameId: "game-1")

        XCTAssertEqual(command.type, "cancel_payment")
    }

    func testManaPaymentTrayExposesCancelCastLabelForPaymentCancelActions() throws {
        let cancelAction = try decodeAction(type: "cancel_payment")
        let undoAction = try decodeAction(type: "undo_mana")

        XCTAssertEqual(ManaPaymentTray.paymentCancelTitle(for: cancelAction), "Cancel cast")
        XCTAssertEqual(ManaPaymentTray.paymentCancelTitle(for: undoAction), "Undo mana")
    }

    func testManaPaymentTrayFiltersManaChoicesByFloatingPool() throws {
        let snapshotData = String(data: try minimalSnapshotJSON(id: "game-floating-mana"), encoding: .utf8)!
            .replacingOccurrences(of: #""manaPool": { "W": 0, "U": 0, "B": 0, "R": 0, "G": 0, "C": 0 }"#, with: #""manaPool": { "W": 1, "U": 0, "B": 0, "R": 0, "G": 1, "C": 0 }"#)
            .data(using: .utf8)!
        let snapshot = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: snapshotData)
        let prompt = try JSONDecoder.magicMobile.decode(PromptEnvelopeV2.self, from: #"""
        {
          "id": "xmage-mana-prompt",
          "method": "GAME_PLAY_MANA",
          "messageId": 77,
          "playerId": "human",
          "responseKind": "mana",
          "message": "Pay {W}",
          "manaChoices": [
            { "id": "W", "label": "Pay {W}", "manaType": "W" },
            { "id": "U", "label": "Pay {U}", "manaType": "U" },
            { "id": "G", "label": "Pay {G}", "manaType": "G" }
          ],
          "responseCommand": {
            "type": "play_mana",
            "promptId": "xmage-mana-prompt",
            "messageId": 77
          }
        }
        """#.data(using: .utf8)!)

        XCTAssertEqual(ManaPaymentTray.payableManaChoiceSymbols(in: snapshot, prompt: prompt), ["W", "G"])
        XCTAssertTrue(ManaPaymentTray.canPay(symbol: "W", in: snapshot))
        XCTAssertFalse(ManaPaymentTray.canPay(symbol: "U", in: snapshot))
    }

    func testChooseAbilityUsesExplicitAbilityIdOnly() throws {
        let action = try decodeAction(
            type: "choose_ability",
            extra: #""abilityId": "ability-1""#
        )
        let command = try MagicMobileAPI(baseURL: URL(string: "http://localhost")!)
            .command(for: action, gameId: "game-1")
        let payload = try JSONSerialization.jsonObject(with: JSONEncoder.magicMobile.encode(command)) as? [String: Any]

        XCTAssertEqual(payload?["abilityId"] as? String, "ability-1")
    }

    func testPromptPileRequiresExplicitPileNumber() throws {
        let explicit = try JSONDecoder.magicMobile.decode(XmagePromptPile.self, from: #"""
        {
          "id": "pile-2",
          "label": "Pile 2",
          "cards": []
        }
        """#.data(using: .utf8)!)
        let ambiguous = try JSONDecoder.magicMobile.decode(XmagePromptPile.self, from: #"""
        {
          "id": "choice-alpha",
          "label": "Take this pile",
          "cards": []
        }
        """#.data(using: .utf8)!)

        XCTAssertEqual(explicit.explicitPileNumber, 2)
        XCTAssertNil(ambiguous.explicitPileNumber)
    }

    func testBlockedCommanderFixtureResponseIsNotPlayable() throws {
        let data = """
        {
          "error": "xmage_fixture_state_seeding_unavailable",
          "enabled": true,
          "fixtureName": "commander-gauntlet",
          "productionDisabled": true,
          "directStateSeeded": false,
          "setupMethod": "bridge_fixture_without_real_seed_proof",
          "blockedReason": "Fixture endpoint did not return seed proof.",
          "nextImplementationStep": "Add an in-server fixture hook."
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.magicMobile.decode(CommanderFixtureResponse.self, from: data)

        XCTAssertNil(response.playableSnapshot)
        XCTAssertEqual(response.statusMessage, "Fixture blocked: Fixture endpoint did not return seed proof.")
        XCTAssertEqual(response.fixtureName, "commander-gauntlet")
        XCTAssertTrue(response.productionDisabled)
    }

    func testCommanderFixtureDecoderAcceptsRawSnapshotSuccess() throws {
        let snapshot = try MagicMobileAPI.decodeCommanderFixtureSnapshot(from: minimalSnapshotJSON(id: "fixture-game-1"))

        XCTAssertEqual(snapshot.id, "fixture-game-1")
        XCTAssertEqual(snapshot.source, "xmage-java-bridge")
        XCTAssertEqual(snapshot.bridgeRevision, 7)
    }

    func testCommanderFixtureDecoderRejectsBlockedResponseWithClearMessage() throws {
        let data = """
        {
          "error": "xmage_fixture_state_seeding_unavailable",
          "fixtureName": "commander-gauntlet",
          "directStateSeeded": false,
          "blockedReason": "Fixture endpoint did not return seed proof.",
          "nextImplementationStep": "Run the fixture inside XMage."
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try MagicMobileAPI.decodeCommanderFixtureSnapshot(from: data)) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Fixture blocked: Fixture endpoint did not return seed proof."
            )
        }
    }

    func testDeclareAttackersCommandPreservesTypedPayload() throws {
        let action = try decodeAction(
            type: "declare_attackers",
            extra: #"""
            "commandTemplate": {
              "type": "declare_attackers",
              "attackers": [{ "attackerId": "attacker-1", "defenderId": "ai-1" }]
            }
            """#
        )

        let command = try MagicMobileAPI(baseURL: URL(string: "http://localhost")!)
            .command(for: action, gameId: "game-1")
        let payload = try JSONSerialization.jsonObject(with: JSONEncoder.magicMobile.encode(command)) as? [String: Any]
        let attackers = payload?["attackers"] as? [[String: Any]]

        XCTAssertEqual(attackers?.count, 1)
        XCTAssertEqual(attackers?.first?["attackerId"] as? String, "attacker-1")
        XCTAssertEqual(attackers?.first?["defenderId"] as? String, "ai-1")
    }

    func testDeclareBlockersCommandPreservesTypedPayload() throws {
        let action = try decodeAction(
            type: "declare_blockers",
            extra: #"""
            "commandTemplate": {
              "type": "declare_blockers",
              "blockers": [{ "blockerId": "blocker-1", "attackerId": "attacker-1" }]
            }
            """#
        )

        let command = try MagicMobileAPI(baseURL: URL(string: "http://localhost")!)
            .command(for: action, gameId: "game-1")
        let payload = try JSONSerialization.jsonObject(with: JSONEncoder.magicMobile.encode(command)) as? [String: Any]
        let blockers = payload?["blockers"] as? [[String: Any]]

        XCTAssertEqual(blockers?.count, 1)
        XCTAssertEqual(blockers?.first?["blockerId"] as? String, "blocker-1")
        XCTAssertEqual(blockers?.first?["attackerId"] as? String, "attacker-1")
    }

    func testStackObjectWithoutSourceCardKeepsDisplayText() throws {
        let data = """
        {
          "id": "stack-1",
          "name": "Activated ability",
          "rulesText": "Draw a card.",
          "paid": false,
          "sourceCardUnavailableReason": "XMage exposed a synthetic stack object without source card metadata."
        }
        """.data(using: .utf8)!

        let object = try JSONDecoder.magicMobile.decode(XmageStackObject.self, from: data)

        XCTAssertNil(object.sourceCard)
        XCTAssertEqual(object.displayName, "Activated ability")
        XCTAssertEqual(object.displaySourceName, "Source unavailable")
        XCTAssertEqual(object.sourceCardUnavailableReason, "XMage exposed a synthetic stack object without source card metadata.")
        XCTAssertEqual(object.compactFallbackDetail, "XMage exposed a synthetic stack object without source card metadata.")
        XCTAssertEqual(object.syntheticTileTitle, "Activated ability")
        XCTAssertEqual(object.syntheticTileSubtitle, "Stack")
        XCTAssertEqual(object.syntheticTileDetail, "Draw a card.")
    }

    func testStackObjectDecodesRealSourceCardForSyntheticAbility() throws {
        let data = """
        {
          "id": "stack-ability-1",
          "objectId": "stack-ability-1",
          "objectType": "ability",
          "name": "Activated ability",
          "rulesText": "{T}: Add {G}.",
          "sourceInstanceId": "jaspera-1",
          "sourceName": "Jaspera Sentinel",
          "sourceZone": "battlefield",
          "sourceCard": {
            "instanceId": "jaspera-1",
            "card": {
              "name": "Jaspera Sentinel",
              "typeLine": "Creature - Elf Rogue",
              "oracleText": "Reach. Tap an untapped creature you control: Add one mana of any color."
            },
            "power": 1,
            "toughness": 2,
            "isCreaturePermanent": true
          },
          "paid": true
        }
        """.data(using: .utf8)!

        let object = try JSONDecoder.magicMobile.decode(XmageStackObject.self, from: data)

        XCTAssertEqual(object.objectId, "stack-ability-1")
        XCTAssertEqual(object.objectType, "ability")
        XCTAssertEqual(object.displayName, "Activated ability")
        XCTAssertEqual(object.displaySourceName, "Jaspera Sentinel")
        XCTAssertEqual(object.sourceCard?.card.name, "Jaspera Sentinel")
        XCTAssertNil(object.sourceCardUnavailableReason)
        XCTAssertNil(object.compactFallbackDetail)
    }

    func testStackObjectDecodesControllerSourceAndTargets() throws {
        let data = """
        {
          "id": "stack-2",
          "name": "Activated ability",
          "rulesText": "Destroy target artifact.",
          "sourceInstanceId": "source-1",
          "sourceName": "Seal of Cleansing",
          "sourceZone": "battlefield",
          "controllerId": "human",
          "controllerXmageId": "controller-xmage-1",
          "targetIds": ["target-1", "target-2"],
          "paid": true
        }
        """.data(using: .utf8)!

        let object = try JSONDecoder.magicMobile.decode(XmageStackObject.self, from: data)

        XCTAssertEqual(object.displayName, "Activated ability")
        XCTAssertEqual(object.displaySourceName, "Seal of Cleansing")
        XCTAssertEqual(object.sourceInstanceId, "source-1")
        XCTAssertEqual(object.sourceZone, "battlefield")
        XCTAssertEqual(object.controllerId, "human")
        XCTAssertEqual(object.controllerXmageId, "controller-xmage-1")
        XCTAssertEqual(object.targetIds ?? [], ["target-1", "target-2"])
        XCTAssertEqual(object.displayMetadata, "Controller: human | From: battlefield | Targets: 2")
        XCTAssertEqual(object.syntheticTileTitle, "Activated ability")
        XCTAssertEqual(object.syntheticTileSubtitle, "Seal of Cleansing")
        XCTAssertEqual(object.syntheticTileDetail, "Destroy target artifact.")
    }

    func testPromptCommandBuilderPreservesResponsePromptAndMessageId() throws {
        let prompt = try promptEnvelopeV2(responseType: "choose_mode", responsePromptId: "response-prompt-9", responseMessageId: 91)

        let mode = try payload(
            for: PromptCommandBuilder.command(
                gameId: "game-1",
                promptEnvelope: prompt,
                type: "choose_mode",
                promptId: "response-prompt-9",
                playerId: "human",
                ids: ["mode-1"]
            )
        )
        let ability = try payload(
            for: PromptCommandBuilder.command(
                gameId: "game-1",
                promptEnvelope: prompt,
                type: "choose_ability",
                promptId: "response-prompt-9",
                playerId: "human",
                ids: ["ability-1"]
            )
        )
        let replacement = try payload(
            for: PromptCommandBuilder.command(
                gameId: "game-1",
                promptEnvelope: prompt,
                type: "commander_replacement",
                promptId: "response-prompt-9",
                playerId: "human",
                useCommandZone: true
            )
        )

        XCTAssertEqual(mode["promptId"] as? String, "response-prompt-9")
        XCTAssertEqual(mode["messageId"] as? Int, 91)
        XCTAssertEqual(mode["modeIds"] as? [String], ["mode-1"])
        XCTAssertEqual(ability["abilityId"] as? String, "ability-1")
        XCTAssertEqual(ability["messageId"] as? Int, 91)
        XCTAssertEqual(replacement["useCommandZone"] as? Bool, true)
        XCTAssertEqual(replacement["messageId"] as? Int, 91)
    }

    func testUniversalPromptResponseCommandBuilderPreservesPromptEnvelopeAndBridgeRevision() throws {
        let prompt = try promptEnvelopeV2(responseType: "choose_mode", responsePromptId: "response-prompt-9", responseMessageId: 91)

        let mode = try payload(
            for: UniversalPromptResponseCommandBuilder.command(
                gameId: "game-1",
                bridgeRevision: 44,
                promptEnvelope: prompt,
                type: "choose_mode",
                promptId: "response-prompt-9",
                playerId: "human",
                ids: ["mode-1"]
            )
        )
        let ability = try payload(
            for: UniversalPromptResponseCommandBuilder.command(
                gameId: "game-1",
                bridgeRevision: 44,
                promptEnvelope: prompt,
                type: "choose_ability",
                promptId: "response-prompt-9",
                playerId: "human",
                ids: ["ability-1"]
            )
        )

        XCTAssertEqual(mode["promptId"] as? String, "response-prompt-9")
        XCTAssertEqual(mode["messageId"] as? Int, 91)
        XCTAssertEqual(mode["expectedBridgeRevision"] as? Int, 44)
        XCTAssertEqual(mode["modeIds"] as? [String], ["mode-1"])
        XCTAssertEqual(ability["abilityId"] as? String, "ability-1")
        XCTAssertEqual(ability["messageId"] as? Int, 91)
        XCTAssertEqual(ability["expectedBridgeRevision"] as? Int, 44)
    }

    func testMobilePromptPresentationClassifiesPromptKindsAndCombatSteps() throws {
        let cases: [(String, MobilePromptKind)] = [
            ("play_mana", .payment),
            ("choose_target", .target),
            ("answer_yes_no", .confirmation),
            ("choose_card", .cardChoice),
            ("choose_player", .playerChoice),
            ("choose_ability", .abilityChoice),
            ("order_triggers", .order),
            ("choose_amount", .amount),
            ("choose_multi_amount", .multiAmount),
            ("choose_pile", .pile),
            ("search_select", .search),
            ("unsupported_mobile_prompt", .unsupported)
        ]

        for (responseType, expectedKind) in cases {
            let prompt = try promptEnvelopeV2(responseType: responseType, responsePromptId: "prompt-\(responseType)", responseMessageId: 91)
            XCTAssertEqual(MobilePromptPresentation.kind(for: prompt), expectedKind, responseType)
        }

        let attackersStepData = String(data: try minimalSnapshotJSON(id: "prompt-combat"), encoding: .utf8)!
            .replacingOccurrences(of: #""step": "precombat-main""#, with: #""step": "declare-attackers""#)
            .replacingOccurrences(of: #""promptText": "Your priority""#, with: #""promptText": "Your priority""#)
            .data(using: .utf8)!
        let snapshot = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: attackersStepData)
        let presentation = try XCTUnwrap(MobilePromptPresentation.make(snapshot: snapshot, legalActions: []))

        XCTAssertEqual(presentation.kind, .combat)
        XCTAssertEqual(presentation.title, "Select attackers")
        XCTAssertFalse(presentation.requiresDetail)
    }

    func testPromptCommandBuilderBuildsOrderedAndAmountCommands() throws {
        let prompt = try promptEnvelopeV2(responseType: "order_triggers", responsePromptId: "prompt-order", responseMessageId: 12)
        let xPrompt = try promptEnvelopeV2(responseType: "play_x_mana", responsePromptId: "prompt-x-mana", responseMessageId: 13)

        let ordered = try payload(
            for: PromptCommandBuilder.command(
                gameId: "game-1",
                promptEnvelope: prompt,
                type: "order_triggers",
                promptId: "prompt-order",
                playerId: "human",
                ids: ["trigger-2", "trigger-1"]
            )
        )
        let amount = try payload(
            for: PromptCommandBuilder.command(
                gameId: "game-1",
                promptEnvelope: prompt,
                type: "choose_amount",
                promptId: "prompt-order",
                playerId: "human",
                amount: 3
            )
        )
        let multiAmount = try payload(
            for: PromptCommandBuilder.command(
                gameId: "game-1",
                promptEnvelope: prompt,
                type: "choose_multi_amount",
                promptId: "prompt-order",
                playerId: "human",
                amounts: [1, 2]
            )
        )
        let xMana = try payload(
            for: PromptCommandBuilder.command(
                gameId: "game-1",
                promptEnvelope: xPrompt,
                type: "play_x_mana",
                promptId: "prompt-x-mana",
                playerId: "human",
                amount: 3
            )
        )

        XCTAssertEqual(ordered["orderedIds"] as? [String], ["trigger-2", "trigger-1"])
        XCTAssertEqual(ordered["messageId"] as? Int, 12)
        XCTAssertEqual(amount["amount"] as? Int, 3)
        XCTAssertEqual(multiAmount["amounts"] as? [Int], [1, 2])
        XCTAssertEqual(xMana["type"] as? String, "play_x_mana")
        XCTAssertEqual(xMana["amount"] as? Int, 3)
        XCTAssertEqual(xMana["messageId"] as? Int, 13)
    }

    func testPromptEnvelopeV2DecodesMultiAmountBounds() throws {
        let data = """
        {
          "id": "multi-1",
          "method": "GAME_GET_MULTI_AMOUNT",
          "messageId": 12,
          "playerId": "human",
          "responseKind": "multi_amount",
          "message": "Choose mana",
          "totalMin": 2,
          "totalMax": 2,
          "multiAmounts": [
            { "id": "0", "label": "W", "min": 0, "max": 2, "defaultValue": 0 },
            { "id": "1", "label": "U", "min": 0, "max": 2, "defaultValue": 0 }
          ],
          "responseCommand": {
            "type": "choose_multi_amount",
            "promptId": "multi-1",
            "messageId": 12
          }
        }
        """.data(using: .utf8)!

        let prompt = try JSONDecoder.magicMobile.decode(PromptEnvelopeV2.self, from: data)

        XCTAssertEqual(prompt.totalMin, 2)
        XCTAssertEqual(prompt.totalMax, 2)
        XCTAssertEqual(prompt.multiAmounts?.map(\.label), ["W", "U"])
    }

    func testCombatDamageMultiAmountPromptIsRecognizedAsDamageAllocation() throws {
        let data = """
        {
          "id": "damage-1",
          "method": "GAME_GET_MULTI_AMOUNT",
          "messageId": 460,
          "playerId": "human",
          "responseKind": "multi_amount",
          "message": "GAME_GET_MULTI_AMOUNT",
          "totalMin": 10,
          "totalMax": 10,
          "multiAmounts": [
            { "id": "0", "label": "Silvercoat Lion, P/T: 2/2", "min": 0, "max": 10, "defaultValue": 9 },
            { "id": "1", "label": "Savannah Lions, P/T: 2/1", "min": 0, "max": 10, "defaultValue": 1 }
          ],
          "responseCommand": {
            "type": "choose_multi_amount",
            "promptId": "damage-1",
            "messageId": 460
          }
        }
        """.data(using: .utf8)!

        let prompt = try JSONDecoder.magicMobile.decode(PromptEnvelopeV2.self, from: data)

        XCTAssertTrue(PromptCommandBuilder.isCombatDamageAllocationPrompt(prompt, phase: "Combat", step: "Combat Damage"))
        XCTAssertFalse(PromptCommandBuilder.isCombatDamageAllocationPrompt(prompt, phase: "Main", step: "Precombat Main"))
    }

    func testInteractionStateFindsOnlyExactDragPlayableActions() throws {
        let card = zoneCard(id: "hand-sol-ring", name: "Sol Ring", typeLine: "Artifact")
        let cast = try decodeAction(
            type: "cast_spell",
            extra: #""sourceInstanceId": "hand-sol-ring""#
        )
        let unrelatedCast = try decodeAction(
            type: "cast_spell",
            extra: #""sourceInstanceId": "other-card""#
        )
        let targetResponse = try decodeAction(
            type: "choose_target",
            extra: #""validTargetIds": ["hand-sol-ring"]"#
        )

        let actions = GameBoardInteractionState.legalPlayActions(
            for: card,
            actions: [cast, unrelatedCast, targetResponse]
        )

        XCTAssertEqual(actions.map(\.id), ["cast_spell-action"])
    }

    func testInteractionStateMatchesDragPlayableActionsFromCommandTemplate() throws {
        let card = zoneCard(id: "hand-arcane-signet", name: "Arcane Signet", typeLine: "Artifact")
        let cast = try decodeAction(
            type: "cast_spell",
            extra: #"""
            "commandTemplate": {
              "type": "cast_spell",
              "sourceInstanceId": "hand-arcane-signet",
              "cardInstanceId": "hand-arcane-signet",
              "sourceZone": "hand"
            }
            """#
        )
        let unrelatedCast = try decodeAction(
            type: "cast_spell",
            extra: #"""
            "commandTemplate": {
              "type": "cast_spell",
              "sourceInstanceId": "other-card",
              "cardInstanceId": "other-card",
              "sourceZone": "hand"
            }
            """#
        )

        let actions = GameBoardInteractionState.legalPlayActions(
            for: card,
            actions: [cast, unrelatedCast]
        )

        XCTAssertEqual(actions.map(\.id), ["cast_spell-action"])
    }

    func testInteractionStateMatchesCommanderCastActionsFromCommandZoneTemplate() throws {
        let commander = zoneCard(id: "commander-isamaru", name: "Isamaru, Hound of Konda", typeLine: "Legendary Creature")
        let cast = try decodeAction(
            type: "cast_spell",
            label: "Cast Isamaru, Hound of Konda",
            extra: #"""
            "commandTemplate": {
              "type": "cast_spell",
              "sourceInstanceId": "commander-isamaru",
              "cardInstanceId": "commander-isamaru",
              "sourceZone": "command"
            }
            """#
        )
        let actions = GameBoardInteractionState.cardActions(for: commander, actions: [cast])

        XCTAssertEqual(actions.map(\.id), ["cast_spell-action"])
        XCTAssertEqual(GameBoardInteractionState.legalPlayActions(for: commander, actions: [cast]).map(\.id), ["cast_spell-action"])
    }

    func testDragDropResolverRejectsNoLegalActionBeforeSubmitting() throws {
        let card = zoneCard(id: "hand-dragon", name: "Hoard-Smelter Dragon", typeLine: "Creature - Dragon")

        let result = DragCastDropResolver.resolve(card: card, legalActions: [], droppedInPlayArea: true)

        XCTAssertEqual(result, .rejected("Hoard-Smelter Dragon is not currently playable"))
    }

    func testDragDropResolverRequiresChoiceForMultipleLegalActions() throws {
        let card = zoneCard(id: "hand-vandalblast", name: "Vandalblast", typeLine: "Sorcery")
        let normal = try decodeAction(
            type: "cast_spell",
            extra: #""id": "normal-cast", "sourceInstanceId": "hand-vandalblast", "label": "Cast""#
        )
        let overload = try decodeAction(
            type: "cast_spell",
            extra: #""id": "overload-cast", "sourceInstanceId": "hand-vandalblast", "label": "Cast with overload""#
        )

        let result = DragCastDropResolver.resolve(card: card, legalActions: [normal, overload], droppedInPlayArea: true)

        XCTAssertEqual(result, .requiresChoice([normal, overload], "Choose how to play Vandalblast"))
    }

    func testDragDropResolverSubmitsExactSingleLegalAction() throws {
        let card = zoneCard(id: "hand-servant", name: "Dragonlord's Servant", typeLine: "Creature - Goblin Shaman")
        let cast = try decodeAction(
            type: "cast_spell",
            extra: #""sourceInstanceId": "hand-servant", "cardInstanceId": "hand-servant", "sourceZone": "hand""#
        )

        let result = DragCastDropResolver.resolve(card: card, legalActions: [cast], droppedInPlayArea: true)

        XCTAssertEqual(result, .submit(cast))
    }

    func testDragDropResolverRejectsAmbiguousCardNameWithoutMatchingId() throws {
        let card = zoneCard(id: "hand-frontier-siege", name: "Frontier Siege", typeLine: "Enchantment")
        let wrongCardAction = try decodeAction(
            type: "cast_spell",
            extra: #""id": "wrong-card-cast", "label": "Cast Frontier Siege", "cardName": "Frontier Siege", "sourceInstanceId": "other-card", "cardInstanceId": "other-card", "sourceZone": "hand""#
        )

        let result = DragCastDropResolver.resolve(card: card, legalActions: [wrongCardAction], droppedInPlayArea: true)

        XCTAssertEqual(result, .rejected("Frontier Siege is not currently playable"))
    }

    func testHandFanHitTestingPrefersVisibleTopCardFrame() throws {
        let metrics = BattlefieldLayoutMetrics(size: CGSize(width: 956, height: 440), safeArea: EdgeInsets())
        let cards = [
            zoneCard(id: "hand-forest", name: "Forest", typeLine: "Basic Land - Forest"),
            zoneCard(id: "hand-mountain", name: "Mountain", typeLine: "Basic Land - Mountain"),
            zoneCard(id: "hand-frontier-siege", name: "Frontier Siege", typeLine: "Enchantment")
        ]

        let hit = HandFanLayout.card(
            at: CGPoint(x: metrics.playWidth / 2 + 35, y: metrics.handFrameHeight / 2),
            cards: cards,
            metrics: metrics,
            selectedCardId: Optional<String>.none,
            draggingCardId: Optional<String>.none,
            dragOffset: CGSize.zero
        )

        XCTAssertEqual(hit?.id, "hand-frontier-siege")
    }

    func testInteractionStateUsesOnlyExposedTargetIdsForGlow() throws {
        let prompt = try JSONDecoder.magicMobile.decode(PromptEnvelopeV2.self, from: #"""
        {
          "id": "xmage-prompt-target",
          "method": "GAME_TARGET",
          "messageId": 44,
          "playerId": "human",
          "responseKind": "target",
          "message": "Choose target artifact.",
          "responseCommand": {
            "type": "choose_target",
            "promptId": "xmage-prompt-target",
            "messageId": 44
          },
          "targets": [
            { "id": "target-sol-ring", "label": "Sol Ring" }
          ],
          "targetIds": ["target-player"]
        }
        """#.data(using: .utf8)!)
        let action = try decodeAction(
            type: "choose_target",
            extra: #""validTargetIds": ["target-arcane-signet"]"#
        )

        let ids = GameBoardInteractionState.validTargetIds(from: prompt, actions: [action])

        XCTAssertEqual(ids, ["target-sol-ring", "target-player", "target-arcane-signet"])
        XCTAssertTrue(GameBoardInteractionState(mode: .targeting(promptId: prompt.id, sourceCardId: nil, validTargetIds: ids)).isTargetable(zoneCard(id: "target-sol-ring", name: "Sol Ring", typeLine: "Artifact")))
        XCTAssertFalse(GameBoardInteractionState(mode: .targeting(promptId: prompt.id, sourceCardId: nil, validTargetIds: ids)).isTargetable(zoneCard(id: "not-exposed", name: "Island", typeLine: "Basic Land - Island")))
    }

    func testInteractionStateDerivesUnsupportedPromptWithoutAutopicking() throws {
        let snapshot = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: #"""
        {
          "id": "game-unknown",
          "source": "xmage-java-bridge",
          "activePlayerId": "human",
          "phase": "precombat-main",
          "step": "precombat-main",
          "turn": 1,
          "priorityPlayerId": "human",
          "waitingOnPlayerId": "human",
          "promptText": "Choose something weird",
          "players": [],
          "log": [],
          "legalActions": [{ "id": "concede", "type": "concede", "playerId": "human", "label": "Concede" }],
          "promptEnvelopeV2": {
            "id": "xmage-prompt-weird",
            "method": "GAME_UNKNOWN_CALLBACK",
            "messageId": 91,
            "playerId": "human",
            "responseKind": "unknown",
            "message": "Choose something weird",
            "responseCommand": {
              "type": "unsupported_mobile_prompt",
              "promptId": "xmage-prompt-weird",
              "messageId": 91
            }
          }
        }
        """#.data(using: .utf8)!)

        let mode = GameBoardInteractionState.mode(for: snapshot, pendingActionId: nil, selectedCard: nil)

        XCTAssertEqual(mode, .unsupportedPrompt(promptId: "xmage-prompt-weird", method: "GAME_UNKNOWN_CALLBACK", responseKind: "unknown"))
    }

    func testInteractionStateDerivesManaPaymentPromptForCastPayment() throws {
        let snapshot = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: #"""
        {
          "id": "game-payment",
          "source": "xmage-java-bridge",
          "activePlayerId": "human",
          "phase": "precombat-main",
          "step": "precombat-main",
          "turn": 1,
          "priorityPlayerId": "human",
          "waitingOnPlayerId": "human",
          "promptText": "Pay {1}",
          "players": [],
          "log": [],
          "legalActions": [
            { "id": "tap-forest", "type": "make_mana", "playerId": "human", "label": "Tap Forest", "sourceInstanceId": "forest-1", "producedMana": ["G"] }
          ],
          "promptEnvelopeV2": {
            "id": "xmage-mana-prompt",
            "method": "GAME_PLAY_MANA",
            "messageId": 77,
            "playerId": "human",
            "responseKind": "mana",
            "message": "Pay {1}",
            "manaChoices": [
              { "id": "C", "label": "Pay {C}", "manaType": "C" }
            ],
            "responseCommand": {
              "type": "play_mana",
              "promptId": "xmage-mana-prompt",
              "messageId": 77
            }
          }
        }
        """#.data(using: .utf8)!)

        let mode = GameBoardInteractionState.mode(for: snapshot, pendingActionId: nil, selectedCard: nil)

        XCTAssertEqual(mode, .manaPayment(promptId: "xmage-mana-prompt"))
        XCTAssertFalse(CompactPromptPopup.needsDetails(snapshot))
    }

    func testInlinePaymentPromptHandlesStackSourceManaActionsWithoutFloatingPopup() throws {
        let snapshot = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: #"""
        {
          "id": "game-stack-payment",
          "source": "xmage-java-bridge",
          "activePlayerId": "human",
          "phase": "precombat-main",
          "step": "precombat-main",
          "turn": 1,
          "priorityPlayerId": "human",
          "waitingOnPlayerId": "human",
          "promptText": "Play spells and abilities",
          "players": [
            {
              "playerId": "human",
              "displayName": "Caleb",
              "life": 40,
              "poison": 0,
              "manaPool": { "W": 0, "U": 0, "B": 0, "R": 0, "G": 0, "C": 0 },
              "zones": {
                "library": [],
                "hand": [],
                "battlefield": [{ "instanceId": "mountain-1", "tapped": false, "card": { "name": "Mountain", "typeLine": "Basic Land - Mountain", "oracleText": "" } }],
                "graveyard": [],
                "exile": [],
                "command": [],
                "stack": []
              },
              "commanderTax": 0,
              "commanderDamage": {}
            }
          ],
          "xmage": {
            "schemaVersion": 1,
            "gameId": "game-stack-payment",
            "bridgeRevision": 7,
            "xmageCycle": 9,
            "callbackCoverage": [],
            "stack": [{ "id": "stack-spell", "name": "Circle of Flame" }],
            "combat": [],
            "players": [],
            "exileZones": [],
            "revealed": [],
            "lookedAt": [],
            "companion": [],
            "playableObjects": [],
            "panels": { "stack": true, "command": true, "graveyard": true, "exile": true, "revealed": false, "lookedAt": false, "search": false }
          },
          "legalActions": [
            { "id": "tap-mountain", "type": "make_mana", "playerId": "human", "label": "Tap Mountain", "sourceInstanceId": "mountain-1", "producedMana": ["R"] }
          ],
          "log": [],
          "bridgeRevision": 7,
          "xmageCycle": 9
        }
        """#.data(using: .utf8)!)

        XCTAssertTrue(InlinePaymentPromptState.isActive(in: snapshot))
        XCTAssertFalse(CompactPromptPopup.shouldShow(for: snapshot, pendingActionId: nil))
        XCTAssertTrue(CompactPromptPopup.shouldShowStackPaymentTray(in: snapshot))
        XCTAssertEqual(CompactPromptPopup.syntheticStackPaymentPrompt(in: snapshot).message, "Tap mana for Circle of Flame")
    }

    func testInlinePaymentPromptHandlesAbilityManaPaymentPipsWithoutPromptEnvelope() throws {
        let snapshot = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: #"""
        {
          "id": "game-ability-payment",
          "source": "xmage-java-bridge",
          "activePlayerId": "human",
          "phase": "precombat-main",
          "step": "precombat-main",
          "turn": 1,
          "priorityPlayerId": "human",
          "waitingOnPlayerId": "human",
          "promptText": "Pay {1} to draw a card",
          "players": [
            {
              "playerId": "human",
              "displayName": "Caleb",
              "life": 40,
              "poison": 0,
              "manaPool": { "W": 0, "U": 0, "B": 0, "R": 0, "G": 1, "C": 0 },
              "zones": {
                "library": [],
                "hand": [],
                "battlefield": [{ "instanceId": "forest-1", "tapped": false, "card": { "name": "Forest", "typeLine": "Basic Land - Forest", "oracleText": "" } }],
                "graveyard": [],
                "exile": [],
                "command": [],
                "stack": []
              },
              "commanderTax": 0,
              "commanderDamage": {}
            }
          ],
          "xmage": {
            "schemaVersion": 1,
            "gameId": "game-ability-payment",
            "bridgeRevision": 9,
            "xmageCycle": 12,
            "callbackCoverage": [],
            "stack": [{ "id": "stack-trigger", "name": "Activated ability", "sourceName": "Beast Whisperer", "rulesText": "Pay {1}. If you do, draw a card." }],
            "combat": [],
            "players": [],
            "exileZones": [],
            "revealed": [],
            "lookedAt": [],
            "companion": [],
            "playableObjects": [],
            "panels": { "stack": true, "command": true, "graveyard": true, "exile": true, "revealed": false, "lookedAt": false, "search": false }
          },
          "legalActions": [
            { "id": "tap-forest", "type": "make_mana", "playerId": "human", "label": "Tap Forest", "sourceInstanceId": "forest-1", "producedMana": ["G"] }
          ],
          "log": [],
          "bridgeRevision": 9,
          "xmageCycle": 12,
          "manaPayment": {
            "active": true,
            "spellName": "Beast Whisperer",
            "manaCostText": "{1}",
            "remainingText": "{1}",
            "remaining": { "generic": 1, "W": 0, "U": 0, "B": 0, "R": 0, "G": 0, "C": 0, "total": 1 }
          }
        }
        """#.data(using: .utf8)!)

        XCTAssertTrue(InlinePaymentPromptState.isActive(in: snapshot))
        XCTAssertFalse(CompactPromptPopup.shouldShow(for: snapshot, pendingActionId: nil))
        XCTAssertEqual(snapshot.manaPayment?.remaining?.generic, 1)
        XCTAssertEqual(InlinePaymentPromptState.paymentPrompt(in: snapshot)?.message, "Tap mana for Activated ability")
    }

    func testCompactPromptPopupDoesNotShowForPassiveGameSelectPriority() throws {
        let snapshot = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: #"""
        {
          "id": "game-priority",
          "source": "xmage-java-bridge",
          "activePlayerId": "human",
          "phase": "precombat-main",
          "step": "precombat-main",
          "turn": 1,
          "priorityPlayerId": "human",
          "waitingOnPlayerId": "human",
          "promptText": "Play instants and activated abilities",
          "players": [],
          "log": [],
          "legalActions": [
            { "id": "pass-priority", "type": "pass_priority", "playerId": "human", "label": "Pass" },
            { "id": "cast-path", "type": "cast_spell", "playerId": "human", "label": "Cast Path to Exile", "cardInstanceId": "path-1" }
          ],
          "promptEnvelopeV2": {
            "id": "xmage-priority-prompt",
            "method": "GAME_SELECT",
            "messageId": 91,
            "playerId": "human",
            "responseKind": "card",
            "message": "Play instants and activated abilities",
            "responseCommand": {
              "type": "choose_card",
              "promptId": "xmage-priority-prompt",
              "messageId": 91
            }
          }
        }
        """#.data(using: .utf8)!)

        XCTAssertFalse(CompactPromptPopup.shouldShow(for: snapshot, pendingActionId: nil))
        XCTAssertTrue(CompactPromptPopup.compactLegalPromptActions(in: snapshot).isEmpty)
    }

    func testInlinePaymentPromptHandlesManaPaymentPromptWithoutFloatingPopup() throws {
        let snapshot = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: #"""
        {
          "id": "game-payment",
          "source": "xmage-java-bridge",
          "activePlayerId": "human",
          "phase": "precombat-main",
          "step": "precombat-main",
          "turn": 1,
          "priorityPlayerId": "human",
          "waitingOnPlayerId": "human",
          "promptText": "Pay {1}",
          "players": [],
          "log": [],
          "legalActions": [
            { "id": "tap-plains", "type": "make_mana", "playerId": "human", "label": "Tap Plains", "sourceInstanceId": "plains-1", "producedMana": ["W"] }
          ],
          "promptEnvelopeV2": {
            "id": "xmage-mana-prompt",
            "method": "GAME_PLAY_MANA",
            "messageId": 77,
            "playerId": "human",
            "responseKind": "mana",
            "message": "Pay {1}",
            "manaChoices": [
              { "id": "W", "label": "Pay {W}", "manaType": "W" }
            ],
            "responseCommand": {
              "type": "play_mana",
              "promptId": "xmage-mana-prompt",
              "messageId": 77
            }
          }
        }
        """#.data(using: .utf8)!)

        XCTAssertTrue(InlinePaymentPromptState.isActive(in: snapshot))
        XCTAssertFalse(CompactPromptPopup.shouldShow(for: snapshot, pendingActionId: nil))
    }

    func testChooseAbilityActionTitlePrefersSpecificLabelOverGenericShortLabel() throws {
        let first = try decodeAction(
            type: "choose_ability",
            label: "Soul Warden - Whenever another creature enters, you gain 1 life.",
            extra: #"""
            "shortLabel": "Ability",
            "abilityId": "ability-soul-warden"
            """#
        )
        let second = try decodeAction(
            type: "choose_ability",
            label: "Beast Whisperer - Pay {1}. If you do, draw a card.",
            extra: #"""
            "shortLabel": "Ability",
            "abilityId": "ability-beast-whisperer"
            """#
        )

        XCTAssertEqual(first.compactPromptTitle, "Soul Warden - Whenever another creature enters, you gain 1 life.")
        XCTAssertEqual(second.compactPromptTitle, "Beast Whisperer - Pay {1}. If you do, draw a card.")
    }

    func testPaymentPromptSuppressesTargetableBoardIdsEvenWhenIdsArePresent() throws {
        let snapshot = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: #"""
        {
          "id": "game-payment-target-looking",
          "source": "xmage-java-bridge",
          "activePlayerId": "human",
          "phase": "precombat-main",
          "step": "precombat-main",
          "turn": 1,
          "priorityPlayerId": "human",
          "waitingOnPlayerId": "human",
          "promptText": "Pay {1}",
          "players": [],
          "log": [],
          "legalActions": [
            { "id": "tap-plains", "type": "make_mana", "playerId": "human", "label": "Tap Plains", "sourceInstanceId": "plains-1", "producedMana": ["W"] }
          ],
          "promptEnvelopeV2": {
            "id": "xmage-mana-prompt",
            "method": "GAME_PLAY_MANA",
            "messageId": 77,
            "playerId": "human",
            "responseKind": "mana",
            "message": "Pay {1}",
            "targetIds": ["plains-1"],
            "responseCommand": {
              "type": "pay_cost",
              "promptId": "xmage-mana-prompt",
              "messageId": 77
            }
          }
        }
        """#.data(using: .utf8)!)

        XCTAssertEqual(GameBoardInteractionState.boardTargetableIds(for: snapshot), [])
    }

    func testAIWaitRecoveryRefreshesThenReconnectsWithoutRecreatingGame() throws {
        let waiting = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: String(data: try minimalSnapshotJSON(id: "ai-wait"), encoding: .utf8)!
            .replacingOccurrences(of: #""priorityPlayerId": "human""#, with: #""priorityPlayerId": "ai-1""#)
            .replacingOccurrences(of: #""waitingOnPlayerId": "human""#, with: #""waitingOnPlayerId": "ai-1""#)
            .data(using: .utf8)!)

        XCTAssertEqual(AIWaitRecoveryPolicy.action(for: waiting, elapsedSeconds: 6, didRefresh: false, didReconnect: false), .none)
        XCTAssertEqual(AIWaitRecoveryPolicy.action(for: waiting, elapsedSeconds: 12, didRefresh: false, didReconnect: false), .refresh)
        XCTAssertEqual(AIWaitRecoveryPolicy.action(for: waiting, elapsedSeconds: 22, didRefresh: true, didReconnect: false), .reconnect)
        XCTAssertEqual(AIWaitRecoveryPolicy.action(for: waiting, elapsedSeconds: 32, didRefresh: true, didReconnect: true), .diagnose)
        XCTAssertEqual(AIWaitRecoveryPolicy.action(for: waiting, elapsedSeconds: 60, didRefresh: true, didReconnect: true, didDiagnose: true), .none)
    }

    func testWaitPresentationLabelsRecoveryStates() throws {
        let aiWaiting = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: String(data: try minimalSnapshotJSON(id: "ai-wait-label"), encoding: .utf8)!
            .replacingOccurrences(of: #""priorityPlayerId": "human""#, with: #""priorityPlayerId": "ai-1""#)
            .replacingOccurrences(of: #""waitingOnPlayerId": "human""#, with: #""waitingOnPlayerId": "ai-1""#)
            .data(using: .utf8)!)
        let bridgeWaiting = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: String(data: try minimalSnapshotJSON(id: "bridge-wait-label"), encoding: .utf8)!
            .replacingOccurrences(of: #""pendingStatus": null"#, with: #""pendingStatus": "waiting_for_xmage""#)
            .data(using: .utf8)!)
        let stale = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: String(data: try minimalSnapshotJSON(id: "stale-wait-label"), encoding: .utf8)!
            .replacingOccurrences(of: #""pendingStatus": null"#, with: #""pendingStatus": "stalled""#)
            .data(using: .utf8)!)

        XCTAssertEqual(XmageWaitPresentation.make(snapshot: aiWaiting, pendingActionId: nil, liveUpdateStatus: "connected").kind, .xmageThinking)
        XCTAssertEqual(XmageWaitPresentation.make(snapshot: aiWaiting, pendingActionId: "command-1", liveUpdateStatus: "connected").kind, .actionStillResolving)
        XCTAssertEqual(XmageWaitPresentation.make(snapshot: bridgeWaiting, pendingActionId: nil, liveUpdateStatus: "connected").kind, .waitingForBridge)
        XCTAssertEqual(XmageWaitPresentation.make(snapshot: aiWaiting, pendingActionId: nil, liveUpdateStatus: "disconnected").kind, .bridgeDisconnected)
        XCTAssertEqual(XmageWaitPresentation.make(snapshot: stale, pendingActionId: nil, liveUpdateStatus: "connected").kind, .snapshotStale)
        XCTAssertEqual(XmageWaitPresentation.make(snapshot: stale, pendingActionId: nil, liveUpdateStatus: "connected", elapsedSeconds: 60, didRefresh: true, didReconnect: true, didDiagnose: true).kind, .manualReconnectAvailable)
    }

    func testActionRejectionNoticeUsesStructuredCategoryAndReturnedSnapshot() throws {
        let snapshotText = try XCTUnwrap(String(data: try minimalSnapshotJSON(id: "rejection-snapshot"), encoding: .utf8))
        let rejectionData = """
        {
          "category": "stale_snapshot",
          "message": "Expected bridge revision 7 but got 9",
          "snapshot": \(snapshotText)
        }
        """.data(using: .utf8)!
        let rejection = try JSONDecoder.magicMobile.decode(MagicMobileActionRejection.self, from: rejectionData)
        let notice = ActionRejectionNotice(rejection: rejection)

        XCTAssertEqual(rejection.category, .staleSnapshot)
        XCTAssertEqual(rejection.snapshot?.id, "rejection-snapshot")
        XCTAssertEqual(notice.message, "Snapshot stale. Refreshed choices.")
        XCTAssertEqual(notice.bridgeRevision, 7)
        XCTAssertEqual(notice.xmageCycle, 11)
    }

    func testAssetDownloadStatusDistinguishesCompleteAndNewAssets() {
        let complete = CardAssetDownloadStatus(
            metadataStatus: "ready",
            serverImageCount: 100,
            serverSymbolCount: 20,
            phoneImageCount: 100,
            phoneInspectionImageCount: 100,
            phoneSymbolCount: 20,
            isSyncing: false,
            progress: nil
        )
        let partial = CardAssetDownloadStatus(
            metadataStatus: "ready",
            serverImageCount: 100,
            serverSymbolCount: 20,
            phoneImageCount: 80,
            phoneInspectionImageCount: 100,
            phoneSymbolCount: 20,
            isSyncing: false,
            progress: nil
        )
        let downloading = CardAssetDownloadStatus(
            metadataStatus: "ready",
            serverImageCount: 100,
            serverSymbolCount: 20,
            phoneImageCount: 80,
            phoneInspectionImageCount: 80,
            phoneSymbolCount: 20,
            isSyncing: true,
            progress: "images 8/100"
        )

        XCTAssertEqual(complete.stateLabel, "ALL DOWNLOADED")
        XCTAssertEqual(complete.buttonTitle, "All assets downloaded")
        XCTAssertEqual(partial.stateLabel, "NEW ASSETS")
        XCTAssertEqual(partial.buttonTitle, "Download new assets")
        XCTAssertEqual(downloading.buttonTitle, "Downloading images 8/100")
    }

    func testPlayableCardGlowIsDistinctFromNormalCardBorder() {
        XCTAssertGreaterThan(CardTile.playableGlowRadius(legal: true, selected: false, pending: false, targetable: false, width: 72), 6)
        XCTAssertEqual(CardTile.playableGlowRadius(legal: false, selected: false, pending: false, targetable: false, width: 72), 0)
    }

    func testCompactPromptUsesLegalActionsForMulliganPromptWithoutChoices() throws {
        let snapshot = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: #"""
        {
          "id": "game-mulligan",
          "source": "xmage-java-bridge",
          "activePlayerId": "ai",
          "phase": "beginning",
          "step": "untap",
          "turn": 1,
          "priorityPlayerId": "ai",
          "waitingOnPlayerId": "ai",
          "promptText": "Mulligan down to 6 cards?",
          "players": [],
          "log": [],
          "legalActions": [
            { "id": "keep-opening-hand", "type": "keep_hand", "playerId": "human", "label": "Keep", "shortLabel": "Keep", "isPrimary": true },
            { "id": "take-mulligan", "type": "mulligan", "playerId": "human", "label": "Mulligan", "shortLabel": "Mulligan" },
            { "id": "concede", "type": "concede", "playerId": "human", "label": "Concede" }
          ],
          "promptEnvelopeV2": {
            "id": "xmage-mulligan-prompt",
            "method": "GAME_ASK",
            "messageId": 52,
            "playerId": "human",
            "responseKind": "choice",
            "message": "Mulligan down to 6 cards?",
            "responseCommand": {
              "type": "resolve_choice",
              "promptId": "xmage-mulligan-prompt",
              "messageId": 52
            }
          }
        }
        """#.data(using: .utf8)!)

        let actions = CompactPromptPopup.compactLegalPromptActions(in: snapshot)

        XCTAssertEqual(actions.map(\.type), ["keep_hand", "mulligan"])
        XCTAssertFalse(CompactPromptPopup.needsDetails(snapshot))
    }

    func testCompactPromptUsesLegalActionsForStartingPlayerChoice() throws {
        let snapshot = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: #"""
        {
          "id": "game-starting-player",
          "source": "xmage-java-bridge",
          "activePlayerId": "human",
          "phase": "beginning",
          "step": "choose_starting_player",
          "turn": 0,
          "priorityPlayerId": "human",
          "waitingOnPlayerId": "human",
          "promptText": "Choose starting player",
          "players": [],
          "log": [],
          "legalActions": [
            { "id": "human-starts", "type": "choose_player", "playerId": "human", "label": "Caleb starts", "shortLabel": "Caleb starts", "promptId": "xmage-start-player" },
            { "id": "ai-starts", "type": "choose_player", "playerId": "human", "label": "Noaddrag starts", "shortLabel": "Noaddrag starts", "promptId": "xmage-start-player" },
            { "id": "concede", "type": "concede", "playerId": "human", "label": "Concede" }
          ],
          "promptEnvelopeV2": {
            "id": "xmage-start-player",
            "method": "GAME_SELECT",
            "messageId": 12,
            "playerId": "human",
            "responseKind": "player",
            "message": "Choose starting player",
            "responseCommand": {
              "type": "choose_player",
              "promptId": "xmage-start-player",
              "messageId": 12
            }
          }
        }
        """#.data(using: .utf8)!)

        let actions = CompactPromptPopup.compactLegalPromptActions(in: snapshot)

        XCTAssertEqual(actions.map(\.label), ["Caleb starts", "Noaddrag starts"])
        XCTAssertTrue(CompactPromptPopup.shouldPreferCompactActionsBeforeRawChoices(for: snapshot))
    }

    func testTargetingHelperHidesBehindButtonDrivenPrompt() throws {
        let snapshot = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: #"""
        {
          "id": "game-starting-player-targeting",
          "source": "xmage-java-bridge",
          "activePlayerId": "human",
          "phase": "beginning",
          "step": "choose_starting_player",
          "turn": 0,
          "priorityPlayerId": "human",
          "waitingOnPlayerId": "human",
          "promptText": "Select a starting player",
          "players": [],
          "log": [],
          "legalActions": [
            { "id": "human-starts", "type": "choose_player", "playerId": "human", "label": "Caleb starts", "shortLabel": "Caleb starts", "promptId": "xmage-start-player" },
            { "id": "ai-starts", "type": "choose_player", "playerId": "human", "label": "AI starts", "shortLabel": "AI starts", "promptId": "xmage-start-player" }
          ],
          "promptEnvelopeV2": {
            "id": "xmage-start-player",
            "method": "GAME_SELECT",
            "messageId": 12,
            "playerId": "human",
            "responseKind": "target",
            "message": "Select a starting player",
            "targetIds": ["human", "ai-1"],
            "responseCommand": {
              "type": "choose_target",
              "promptId": "xmage-start-player",
              "messageId": 12
            }
          }
        }
        """#.data(using: .utf8)!)
        let mode = GameBoardInteractionMode.targeting(promptId: "xmage-start-player", sourceCardId: nil, validTargetIds: ["human", "ai-1"])

        XCTAssertFalse(TargetingHelperVisibility.shouldShow(snapshot: snapshot, pendingActionId: nil, mode: mode, targetableIds: ["human", "ai-1"]))
    }

    func testTargetingHelperStillShowsForBoardTargetPrompt() throws {
        let snapshot = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: #"""
        {
          "id": "game-board-target",
          "source": "xmage-java-bridge",
          "activePlayerId": "human",
          "phase": "precombat-main",
          "step": "precombat-main",
          "turn": 1,
          "priorityPlayerId": "human",
          "waitingOnPlayerId": "human",
          "promptText": "Choose target creature",
          "players": [],
          "log": [],
          "legalActions": [],
          "promptEnvelopeV2": {
            "id": "xmage-target",
            "method": "GAME_TARGET",
            "messageId": 19,
            "playerId": "human",
            "responseKind": "target",
            "message": "Choose target creature",
            "targetIds": ["creature-1"],
            "responseCommand": {
              "type": "choose_target",
              "promptId": "xmage-target",
              "messageId": 19
            }
          }
        }
        """#.data(using: .utf8)!)
        let mode = GameBoardInteractionMode.targeting(promptId: "xmage-target", sourceCardId: nil, validTargetIds: ["creature-1"])

        XCTAssertTrue(TargetingHelperVisibility.shouldShow(snapshot: snapshot, pendingActionId: nil, mode: mode, targetableIds: ["creature-1"]))
    }

    func testPlayerSnapshotDecodesDisplayNameForHud() throws {
        let snapshot = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: #"""
        {
          "id": "game-names",
          "source": "xmage-java-bridge",
          "activePlayerId": "human",
          "phase": "beginning",
          "turn": 1,
          "players": [
            {
              "playerId": "human",
              "displayName": "Caleb",
              "life": 40,
              "poison": 0,
              "commanderTax": 0,
              "manaPool": { "W": 0, "U": 0, "B": 0, "R": 0, "G": 0, "C": 0 },
              "zones": { "library": [], "hand": [], "battlefield": [], "graveyard": [], "exile": [], "command": [], "stack": [] },
              "commanderDamage": {}
            },
            {
              "playerId": "ai-1",
              "displayName": "Noaddrag",
              "life": 40,
              "poison": 0,
              "commanderTax": 0,
              "manaPool": { "W": 0, "U": 0, "B": 0, "R": 0, "G": 0, "C": 0 },
              "zones": { "library": [], "hand": [], "battlefield": [], "graveyard": [], "exile": [], "command": [], "stack": [] },
              "commanderDamage": {}
            }
          ],
          "log": []
        }
        """#.data(using: .utf8)!)

        XCTAssertEqual(snapshot.human?.displayName, "Caleb")
        XCTAssertEqual(snapshot.opponent?.displayName, "Noaddrag")
    }

    func testCompactPromptPopupSendsComplexPromptsToDetailSheet() throws {
        let snapshot = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: #"""
        {
          "id": "game-search",
          "source": "xmage-java-bridge",
          "activePlayerId": "human",
          "phase": "precombat-main",
          "step": "precombat-main",
          "turn": 1,
          "priorityPlayerId": "human",
          "waitingOnPlayerId": "human",
          "players": [],
          "log": [],
          "legalActions": [],
          "promptEnvelopeV2": {
            "id": "xmage-search-prompt",
            "method": "GAME_SELECT",
            "messageId": 78,
            "playerId": "human",
            "responseKind": "card",
            "message": "Search your library",
            "cards": [
              { "instanceId": "forest-1", "card": { "name": "Forest", "typeLine": "Basic Land - Forest" } }
            ],
            "responseCommand": {
              "type": "search_select",
              "promptId": "xmage-search-prompt",
              "messageId": 78
            }
          }
        }
        """#.data(using: .utf8)!)

        XCTAssertTrue(CompactPromptPopup.needsDetails(snapshot))
    }

    func testPromptCommandBuilderValidatesMultiAmountRangesAndTotals() {
        let slots = [
            XmagePromptMultiAmount(id: "0", label: "W", min: 0, max: 2, defaultValue: 0),
            XmagePromptMultiAmount(id: "1", label: "U", min: 0, max: 2, defaultValue: 0)
        ]

        XCTAssertEqual(PromptCommandBuilder.defaultMultiAmountValue(for: slots[0]), 0)
        XCTAssertEqual(PromptCommandBuilder.adjustedMultiAmountValue(2, delta: 1, slot: slots[0]), 2)
        XCTAssertTrue(PromptCommandBuilder.isValidMultiAmountValues([1, 1], slots: slots, totalMin: 2, totalMax: 2))
        XCTAssertFalse(PromptCommandBuilder.isValidMultiAmountValues([1], slots: slots, totalMin: 2, totalMax: 2))
        XCTAssertFalse(PromptCommandBuilder.isValidMultiAmountValues([3, 0], slots: slots, totalMin: 2, totalMax: 2))
        XCTAssertFalse(PromptCommandBuilder.isValidMultiAmountValues([1, 0], slots: slots, totalMin: 2, totalMax: 2))
    }

    func testSearchSelectionRequiresExplicitMinMaxCount() {
        XCTAssertFalse(PromptSelectionRules.isValidSelectedCount(0, minChoices: 1, maxChoices: 2))
        XCTAssertTrue(PromptSelectionRules.isValidSelectedCount(1, minChoices: 1, maxChoices: 2))
        XCTAssertTrue(PromptSelectionRules.isValidSelectedCount(2, minChoices: 1, maxChoices: 2))
        XCTAssertFalse(PromptSelectionRules.isValidSelectedCount(3, minChoices: 1, maxChoices: 2))
    }

    func testUnsupportedPromptFallbackPreviewStateIsNotPlayable() {
        let snapshot = GameBoardPreviewFixtures.snapshot(.unsupportedPromptFallback)

        XCTAssertEqual(snapshot.source, "design-preview")
        XCTAssertEqual(snapshot.promptEnvelopeV2?.responseCommand?.type, "unsupported_mobile_prompt")
        XCTAssertEqual(snapshot.legalActions?.map(\.type), ["concede"])
        XCTAssertEqual(snapshot.engineHealth?.reason, "Design preview only. Not gameplay proof.")
    }

    func testUniversalPromptResponseCommandBuilderFailsClosedForMissingPromptValues() {
        XCTAssertNil(UniversalPromptResponseCommandBuilder.command(gameId: "game-1", bridgeRevision: 44, promptEnvelope: nil, type: "choose_pile", promptId: "prompt-1", playerId: "human"))
        XCTAssertNil(UniversalPromptResponseCommandBuilder.command(gameId: "game-1", bridgeRevision: 44, promptEnvelope: nil, type: "choose_pile", promptId: "prompt-1", playerId: "human", pile: 3))
        XCTAssertNil(UniversalPromptResponseCommandBuilder.command(gameId: "game-1", bridgeRevision: 44, promptEnvelope: nil, type: "choose_amount", promptId: "prompt-1", playerId: "human"))
        XCTAssertNil(UniversalPromptResponseCommandBuilder.command(gameId: "game-1", bridgeRevision: 44, promptEnvelope: nil, type: "choose_multi_amount", promptId: "prompt-1", playerId: "human", ids: []))
        XCTAssertNil(UniversalPromptResponseCommandBuilder.command(gameId: "game-1", bridgeRevision: 44, promptEnvelope: nil, type: "play_mana", promptId: "prompt-1", playerId: "human"))
        XCTAssertNil(UniversalPromptResponseCommandBuilder.command(gameId: "game-1", bridgeRevision: 44, promptEnvelope: nil, type: "play_mana", promptId: "prompt-1", playerId: "human", manaType: "Colorless"))
        XCTAssertNil(UniversalPromptResponseCommandBuilder.command(gameId: "game-1", bridgeRevision: 44, promptEnvelope: nil, type: "choose_mana", promptId: "prompt-1", playerId: "human", ids: []))
        XCTAssertNil(UniversalPromptResponseCommandBuilder.command(gameId: "game-1", bridgeRevision: 44, promptEnvelope: nil, type: "answer_yes_no", promptId: "prompt-1", playerId: "human"))
        XCTAssertNil(UniversalPromptResponseCommandBuilder.command(gameId: "game-1", bridgeRevision: 44, promptEnvelope: nil, type: "pay_cost", promptId: "prompt-1", playerId: "human"))
        XCTAssertNil(UniversalPromptResponseCommandBuilder.command(gameId: "game-1", bridgeRevision: 44, promptEnvelope: nil, type: "commander_replacement", promptId: "prompt-1", playerId: "human"))
        XCTAssertNil(UniversalPromptResponseCommandBuilder.command(gameId: "game-1", bridgeRevision: 44, promptEnvelope: nil, type: "choose_ability", promptId: "prompt-1", playerId: "human", ids: []))
    }

    func testPromptCommandBuilderFailsClosedForUnsafePrompts() {
        XCTAssertNil(PromptCommandBuilder.command(gameId: "game-1", promptEnvelope: nil, type: "choose_pile", promptId: "prompt-1", playerId: "human"))
        XCTAssertNil(PromptCommandBuilder.command(gameId: "game-1", promptEnvelope: nil, type: "choose_pile", promptId: "prompt-1", playerId: "human", pile: 3))
        XCTAssertNil(PromptCommandBuilder.command(gameId: "game-1", promptEnvelope: nil, type: "choose_amount", promptId: "prompt-1", playerId: "human"))
        XCTAssertNil(PromptCommandBuilder.command(gameId: "game-1", promptEnvelope: nil, type: "choose_multi_amount", promptId: "prompt-1", playerId: "human", ids: []))
        XCTAssertNil(PromptCommandBuilder.command(gameId: "game-1", promptEnvelope: nil, type: "damage_assignment", promptId: "prompt-1", playerId: "human", ids: ["auto"]))
        XCTAssertNil(PromptCommandBuilder.command(gameId: "game-1", promptEnvelope: nil, type: "play_mana", promptId: "prompt-1", playerId: "human"))
        XCTAssertNil(PromptCommandBuilder.command(gameId: "game-1", promptEnvelope: nil, type: "play_mana", promptId: "prompt-1", playerId: "human", manaType: "Colorless"))
        XCTAssertNil(PromptCommandBuilder.command(gameId: "game-1", promptEnvelope: nil, type: "answer_yes_no", promptId: "prompt-1", playerId: "human"))
        XCTAssertNil(PromptCommandBuilder.command(gameId: "game-1", promptEnvelope: nil, type: "commander_replacement", promptId: "prompt-1", playerId: "human"))
        XCTAssertNil(PromptCommandBuilder.command(gameId: "game-1", promptEnvelope: nil, type: "choose_ability", promptId: "prompt-1", playerId: "human", ids: []))
    }

    func testPromptCommandBuilderAllowsOnlySingleShownOrderSubmissionFromIOSPlaceholder() {
        XCTAssertFalse(PromptCommandBuilder.canSubmitShownOrder(ids: []))
        XCTAssertTrue(PromptCommandBuilder.canSubmitShownOrder(ids: ["trigger-1"]))
        XCTAssertFalse(PromptCommandBuilder.canSubmitShownOrder(ids: ["trigger-1", "trigger-2"]))
    }

    func testPromptCommandBuilderMovesOrderedIdsWithoutInventingChoices() {
        let ids = ["trigger-1", "trigger-2", "trigger-3"]

        XCTAssertEqual(PromptCommandBuilder.movedOrder(ids: ids, from: 2, to: 1), ["trigger-1", "trigger-3", "trigger-2"])
        XCTAssertEqual(PromptCommandBuilder.movedOrder(ids: ids, from: 0, to: 2), ["trigger-2", "trigger-3", "trigger-1"])
        XCTAssertEqual(PromptCommandBuilder.movedOrder(ids: ids, from: -1, to: 1), ids)
        XCTAssertEqual(PromptCommandBuilder.movedOrder(ids: ids, from: 0, to: 3), ids)
    }

    func testPromptCommandBuilderRecognizesPrebuiltCombatPayloads() throws {
        let attackerAction = try decodeAction(
            type: "declare_attackers",
            extra: #"""
            "commandTemplate": {
              "type": "declare_attackers",
              "attackers": [{ "attackerId": "attacker-1", "defenderId": "ai-1" }]
            }
            """#
        )
        let blockerAction = try decodeAction(
            type: "declare_blockers",
            extra: #"""
            "commandTemplate": {
              "type": "declare_blockers",
              "blockers": [{ "blockerId": "blocker-1", "attackerId": "attacker-1" }]
            }
            """#
        )
        let incompleteAction = try decodeAction(type: "declare_attackers")

        XCTAssertTrue(PromptCommandBuilder.hasPrebuiltCombatPayload(attackerAction))
        XCTAssertTrue(PromptCommandBuilder.hasPrebuiltCombatPayload(blockerAction))
        XCTAssertFalse(PromptCommandBuilder.hasPrebuiltCombatPayload(incompleteAction))
    }

    func testCombatSelectionRequiresAttackerBeforeDefender() throws {
        let action = try decodeAction(
            type: "declare_attackers",
            extra: #"""
            "validTargetIds": ["ai-1"],
            "commandTemplate": {
              "type": "declare_attackers",
              "attackers": [{ "attackerId": "creature-1", "defenderId": "ai-1" }]
            }
            """#
        )
        var selection = CombatSelectionState()

        XCTAssertNil(selection.attackAction(forDefenderId: "ai-1", actions: [action]))

        selection.toggleAttacker("creature-1")
        let chosen = selection.attackAction(forDefenderId: "ai-1", actions: [action])

        XCTAssertEqual(chosen?.id, action.id)
        XCTAssertEqual(selection.attackerHighlightIds(actions: [action]), ["creature-1"])
        XCTAssertEqual(selection.defenderHighlightIds(actions: [action]), ["ai-1"])
    }

    func testCombatSelectionDetectsDeclareAttackersFromHumanStepWithoutActions() throws {
        let attackersStepData = String(data: try minimalSnapshotJSON(id: "attackers-no-actions"), encoding: .utf8)!
            .replacingOccurrences(of: #""step": "precombat-main""#, with: #""step": "declare-attackers""#)
            .data(using: .utf8)!
        let snapshot = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: attackersStepData)

        XCTAssertTrue(CombatSelectionState.isDeclareAttackers(snapshot))
        XCTAssertFalse(CombatSelectionState.isDeclareBlockers(snapshot))
    }

    func testCombatSelectionBuildsPartialAndFinishAttackCommands() throws {
        let action = try decodeAction(
            type: "declare_attackers",
            extra: #"""
            "validTargetIds": ["ai-1"],
            "commandTemplate": {
              "type": "declare_attackers",
              "attackers": [{ "attackerId": "creature-1", "defenderId": "ai-1" }]
            }
            """#
        )
        var selection = CombatSelectionState()
        selection.selectAttacker("creature-1")

        let partial = selection.attackCommand(gameId: "game-1", playerId: "human", defenderId: "ai-1", actions: [action], expectedBridgeRevision: 7)
        let finish = CombatSelectionState.finishAttackCommand(gameId: "game-1", playerId: "human", expectedBridgeRevision: 7)

        XCTAssertEqual(partial?.type, "declare_attackers")
        XCTAssertEqual(partial?.attackers?.first?.attackerId, "creature-1")
        XCTAssertEqual(partial?.attackers?.first?.defenderId, "ai-1")
        XCTAssertEqual(partial?.combatComplete, false)
        XCTAssertEqual(finish.attackers?.count, 0)
        XCTAssertEqual(finish.combatComplete, true)
    }

    func testCombatSelectionUsesActionCardIdsForAttackerHighlights() throws {
        let action = try decodeAction(
            type: "declare_attackers",
            extra: #"""
            "cardInstanceId": "creature-1",
            "validTargetIds": ["ai-1"]
            """#
        )
        var selection = CombatSelectionState()

        XCTAssertEqual(selection.attackerHighlightIds(actions: [action]), ["creature-1"])
        XCTAssertEqual(selection.defenderIds(forAttackerId: "creature-1", actions: [action]), ["ai-1"])

        selection.selectAttacker("creature-1")
        let command = selection.attackCommand(gameId: "game-1", playerId: "human", defenderId: "ai-1", actions: [action], expectedBridgeRevision: 9)

        XCTAssertEqual(command?.attackers?.first?.attackerId, "creature-1")
        XCTAssertEqual(command?.attackers?.first?.defenderId, "ai-1")
        XCTAssertEqual(command?.expectedBridgeRevision, 9)
    }

    func testCombatSelectionBuildsPlaneswalkerAndBattleAttackCommands() throws {
        let planeswalkerAction = try decodeAction(
            type: "declare_attackers",
            extra: #"""
            "validTargetIds": ["planeswalker-1"],
            "commandTemplate": {
              "type": "declare_attackers",
              "attackers": [{ "attackerId": "creature-1", "defenderId": "planeswalker-1" }]
            }
            """#
        )
        let battleAction = try decodeAction(
            type: "declare_attackers",
            extra: #"""
            "validTargetIds": ["battle-1"],
            "commandTemplate": {
              "type": "declare_attackers",
              "attackers": [{ "attackerId": "creature-1", "defenderId": "battle-1" }]
            }
            """#
        )
        var selection = CombatSelectionState()
        selection.selectAttacker("creature-1")

        let planeswalkerCommand = selection.attackCommand(gameId: "game-1", playerId: "human", defenderId: "planeswalker-1", actions: [planeswalkerAction], expectedBridgeRevision: 7)
        let battleCommand = selection.attackCommand(gameId: "game-1", playerId: "human", defenderId: "battle-1", actions: [battleAction], expectedBridgeRevision: 7)

        XCTAssertEqual(planeswalkerCommand?.attackers?.first?.defenderId, "planeswalker-1")
        XCTAssertEqual(battleCommand?.attackers?.first?.defenderId, "battle-1")
        XCTAssertEqual(selection.defenderHighlightIds(actions: [planeswalkerAction, battleAction]), ["planeswalker-1", "battle-1"])
    }

    func testCombatSelectionBuildsBlockerPairsBeforeSubmitting() {
        var selection = CombatSelectionState()

        XCTAssertNil(selection.pendingBlockActionPayload(playerId: "human", gameId: "game-1"))

        selection.selectBlocker("blocker-1")
        selection.pairSelectedBlocker(withAttackerId: "attacker-1")
        let command = selection.pendingBlockActionPayload(playerId: "human", gameId: "game-1")

        XCTAssertEqual(command?.type, "declare_blockers")
        XCTAssertEqual(command?.blockers?.first?.blockerId, "blocker-1")
        XCTAssertEqual(command?.blockers?.first?.attackerId, "attacker-1")
        XCTAssertEqual(command?.combatComplete, false)
    }

    func testCombatSelectionUsesActionCardIdsForBlockerHighlights() throws {
        let action = try decodeAction(
            type: "declare_blockers",
            extra: #"""
            "cardInstanceId": "blocker-1",
            "validTargetIds": ["attacker-1"],
            "commandTemplate": {
              "type": "declare_blockers",
              "blockers": [{ "blockerId": "blocker-1", "attackerId": "attacker-1" }]
            }
            """#
        )
        let selection = CombatSelectionState()

        XCTAssertEqual(selection.blockerHighlightIds(actions: [action]), ["blocker-1"])
        XCTAssertEqual(selection.attackingCreatureHighlightIds(actions: [action], combatGroups: []), ["attacker-1"])
    }

    func testCombatSelectionBuildsFinishBlockCommand() {
        let command = CombatSelectionState.finishBlockCommand(gameId: "game-1", playerId: "human", expectedBridgeRevision: 7)

        XCTAssertEqual(command.type, "declare_blockers")
        XCTAssertEqual(command.blockers?.count, 0)
        XCTAssertEqual(command.combatComplete, true)
        XCTAssertEqual(command.expectedBridgeRevision, 7)
    }

    func testBlockerModeDetectsHumanStepBeforeLegalActionsArrive() throws {
        let blockersStepData = String(data: try minimalSnapshotJSON(id: "blockers-no-actions"), encoding: .utf8)!
            .replacingOccurrences(of: #""step": "precombat-main""#, with: #""step": "declare-blockers""#)
            .data(using: .utf8)!
        let noActions = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: blockersStepData)

        XCTAssertTrue(CombatSelectionState.isDeclareBlockers(noActions))

        let legalData = String(data: try minimalSnapshotJSON(id: "blockers-with-actions"), encoding: .utf8)!
            .replacingOccurrences(of: #""step": "precombat-main""#, with: #""step": "declare-blockers""#)
            .replacingOccurrences(of: #""legalActions": []"#, with: #""legalActions": [{ "id": "block-1", "type": "declare_blockers", "playerId": "human", "label": "Block", "blockers": [{ "blockerId": "blocker-1", "attackerId": "attacker-1" }] }]"#)
            .data(using: .utf8)!
        let withActions = try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: legalData)

        XCTAssertTrue(CombatSelectionState.isDeclareBlockers(withActions))
    }

    func testCombatSelectionHandlesMultipleAttackerBlockerPairs() throws {
        let firstBlock = try decodeAction(
            type: "declare_blockers",
            extra: #"""
            "blockers": [{ "blockerId": "blocker-1", "attackerId": "attacker-1" }],
            "validTargetIds": ["attacker-1"],
            "commandTemplate": {
              "type": "declare_blockers",
              "blockers": [{ "blockerId": "blocker-1", "attackerId": "attacker-1" }]
            }
            """#
        )
        let secondBlock = try decodeAction(
            type: "declare_blockers",
            extra: #"""
            "blockers": [{ "blockerId": "blocker-1", "attackerId": "attacker-2" }],
            "validTargetIds": ["attacker-2"],
            "commandTemplate": {
              "type": "declare_blockers",
              "blockers": [{ "blockerId": "blocker-1", "attackerId": "attacker-2" }]
            }
            """#
        )
        let groups = [
            XmageCombatGroup(defenderId: "human", defenderName: "Caleb", defenderKind: "player", blocked: false, attackers: [zoneCard(id: "attacker-1", name: "Attacker One", typeLine: "Creature")], blockers: []),
            XmageCombatGroup(defenderId: "human", defenderName: "Caleb", defenderKind: "player", blocked: false, attackers: [zoneCard(id: "attacker-2", name: "Attacker Two", typeLine: "Creature")], blockers: [])
        ]
        let selection = CombatSelectionState()

        XCTAssertEqual(selection.blockerHighlightIds(actions: [firstBlock, secondBlock]), ["blocker-1"])
        XCTAssertEqual(selection.attackingCreatureHighlightIds(actions: [firstBlock, secondBlock], combatGroups: groups), ["attacker-1", "attacker-2"])
    }

    func testCombatArrowModelUsesAuthoritativeCombatGroups() {
        let attacker = zoneCard(id: "attacker-1", name: "Attacker", typeLine: "Creature")
        let blocker = zoneCard(id: "blocker-1", name: "Blocker", typeLine: "Creature")
        let group = XmageCombatGroup(
            defenderId: "ai-1",
            defenderName: "AI",
            defenderKind: "player",
            blocked: true,
            attackers: [attacker],
            blockers: [blocker]
        )

        let arrows = CombatArrowModel.arrows(from: [group])

        XCTAssertEqual(arrows.map(\.kind), [.blockedAttack, .block])
        XCTAssertEqual(arrows.first?.fromId, "attacker-1")
        XCTAssertEqual(arrows.first?.toId, "ai-1")
        XCTAssertEqual(arrows.first?.toKind, "player")
        XCTAssertEqual(arrows.last?.fromId, "blocker-1")
        XCTAssertEqual(arrows.last?.toId, "attacker-1")
    }

    func testCombatArrowModelAppendsPreviewArrowsAfterAuthoritativeCombat() {
        let attacker = zoneCard(id: "attacker-1", name: "Attacker", typeLine: "Creature")
        let group = XmageCombatGroup(
            defenderId: "ai-1",
            defenderName: "AI",
            defenderKind: "player",
            blocked: false,
            attackers: [attacker],
            blockers: []
        )
        let preview = CombatArrow(kind: .previewBlock, fromId: "blocker-1", toId: "attacker-1", toKind: nil)

        let arrows = CombatArrowModel.arrows(from: [group], previewArrows: [preview])

        XCTAssertEqual(arrows.map(\.kind), [.attack, .previewBlock])
        XCTAssertEqual(arrows.last, preview)
    }

    func testBattlefieldLayoutMetricsFitProMaxLandscape() {
        let metrics = BattlefieldLayoutMetrics(
            size: CGSize(width: 932, height: 430),
            safeArea: EdgeInsets(top: 0, leading: 47, bottom: 21, trailing: 47)
        )

        assertGameplayLayout(metrics)
        XCTAssertGreaterThanOrEqual(metrics.handCardWidth, 74)
        XCTAssertGreaterThanOrEqual(metrics.permanentCardWidth, 50)
        XCTAssertGreaterThanOrEqual(metrics.landCardWidth, 44)
        XCTAssertGreaterThanOrEqual(metrics.rightActionPanelRect.width, 210)
        XCTAssertEqual(metrics.rightDockRect.maxX, metrics.safeFrame.maxX, accuracy: 0.1)
        XCTAssertLessThanOrEqual(metrics.phaseRailRect.height, 42)
        XCTAssertGreaterThanOrEqual(metrics.bottomActionRect.height, 38)
        XCTAssertGreaterThanOrEqual(metrics.centerStripRect.height, 24)
        XCTAssertEqual(metrics.playerDropZone.minX, metrics.boardColumnRect.minX, accuracy: 0.1)
        XCTAssertEqual(metrics.playerDropZone.maxX, metrics.boardColumnRect.maxX, accuracy: 0.1)
    }

    func testPlayerDropZoneAcceptsLeftCenterAndRightFieldPoints() {
        let metrics = BattlefieldLayoutMetrics(
            size: CGSize(width: 932, height: 430),
            safeArea: EdgeInsets(top: 0, leading: 47, bottom: 21, trailing: 47)
        )

        let y = metrics.playerBattlefieldRect.midY

        XCTAssertTrue(metrics.playerDropZone.contains(CGPoint(x: metrics.boardColumnRect.minX + 4, y: y)))
        XCTAssertTrue(metrics.playerDropZone.contains(CGPoint(x: metrics.boardColumnRect.midX, y: y)))
        XCTAssertTrue(metrics.playerDropZone.contains(CGPoint(x: metrics.boardColumnRect.maxX - 4, y: y)))
    }

    func testBattlefieldLayoutMetricsKeepCompactLandscapeUsable() {
        let metrics = BattlefieldLayoutMetrics(
            size: CGSize(width: 812, height: 375),
            safeArea: EdgeInsets(top: 0, leading: 44, bottom: 21, trailing: 44)
        )

        assertGameplayLayout(metrics)
        XCTAssertGreaterThanOrEqual(metrics.handCardWidth, 58)
        XCTAssertGreaterThanOrEqual(metrics.permanentCardWidth, 44)
        XCTAssertGreaterThanOrEqual(metrics.landCardHeight, 44)
        XCTAssertGreaterThanOrEqual(metrics.rightActionPanelRect.height, 190)
    }

    func testPortraitBattlefieldLayoutMetricsFitProMaxPortrait() {
        let metrics = PortraitBattlefieldLayoutMetrics(
            size: CGSize(width: 430, height: 932),
            safeArea: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
        )

        assertPortraitGameplayLayout(metrics)
        XCTAssertGreaterThanOrEqual(metrics.handCardWidth, 64)
        XCTAssertGreaterThanOrEqual(metrics.permanentCardWidth, 58)
        XCTAssertGreaterThanOrEqual(metrics.landCardWidth, 50)
        XCTAssertEqual(metrics.handCardHeight / metrics.handCardWidth, PortraitBattlefieldLayoutMetrics.magicCardHeightToWidth, accuracy: 0.01)
        XCTAssertEqual(metrics.permanentCardHeight / metrics.permanentCardWidth, PortraitBattlefieldLayoutMetrics.magicCardHeightToWidth, accuracy: 0.01)
        XCTAssertEqual(metrics.landCardHeight / metrics.landCardWidth, PortraitBattlefieldLayoutMetrics.magicCardHeightToWidth, accuracy: 0.01)
    }

    func testPortraitPlayerDropZoneCoversBattlefieldAndLands() {
        let metrics = PortraitBattlefieldLayoutMetrics(
            size: CGSize(width: 430, height: 932),
            safeArea: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
        )

        XCTAssertTrue(metrics.playerDropZone.contains(CGPoint(x: metrics.playerBattlefieldRect.midX, y: metrics.playerBattlefieldRect.midY)))
        XCTAssertTrue(metrics.playerDropZone.contains(CGPoint(x: metrics.playerLandsRect.midX, y: metrics.playerLandsRect.midY)))
        XCTAssertFalse(metrics.playerDropZone.contains(CGPoint(x: metrics.handRect.midX, y: metrics.handRect.midY)))
    }

    func testPortraitBattlefieldRowPlannerUsesVisibleRowsBeforeOverflow() {
        let cards = (0..<7).map { zoneCard(id: "creature-\($0)", name: "Creature \($0)", typeLine: "Creature") }

        let plan = PortraitBattlefieldRowPlanner.plan(cards: cards, rowWidth: 208, cardWidth: 60, maxRows: 3)

        XCTAssertEqual(plan.cardsPerRow, 4)
        XCTAssertFalse(plan.overflowsHorizontally)
        XCTAssertEqual(plan.rows.map { $0.map(\.instanceId) }, [
            ["creature-0", "creature-1", "creature-2", "creature-3"],
            ["creature-4", "creature-5", "creature-6"]
        ])
    }

    func testPortraitBattlefieldRowPlannerFitsTenCardsWithoutOverflow() {
        let cards = (0..<10).map { zoneCard(id: "creature-\($0)", name: "Creature \($0)", typeLine: "Creature") }

        let plan = PortraitBattlefieldRowPlanner.plan(cards: cards, rowWidth: 208, cardWidth: 60, maxRows: 3)

        XCTAssertEqual(plan.cardsPerRow, 4)
        XCTAssertFalse(plan.overflowsHorizontally)
        XCTAssertEqual(plan.rows.count, 3)
        XCTAssertEqual(plan.rows.map { $0.map(\.instanceId) }, [
            ["creature-0", "creature-1", "creature-2", "creature-3"],
            ["creature-4", "creature-5", "creature-6"],
            ["creature-7", "creature-8", "creature-9"]
        ])
    }

    func testPortraitBattlefieldRowPlannerKeepsOverflowOnLastScrollableRowAboveTen() {
        let cards = (0..<12).map { zoneCard(id: "creature-\($0)", name: "Creature \($0)", typeLine: "Creature") }

        let plan = PortraitBattlefieldRowPlanner.plan(cards: cards, rowWidth: 208, cardWidth: 60, maxRows: 3)

        XCTAssertTrue(plan.overflowsHorizontally)
        XCTAssertEqual(plan.rows.count, 3)
        XCTAssertEqual(plan.rows[2].map(\.instanceId), ["creature-7", "creature-8", "creature-9", "creature-10", "creature-11"])
    }

    func testPortraitOverlapLayoutFitsTenCardsWithoutScrolling() {
        let plan = PortraitOverlapLayout.plan(count: 10, containerWidth: 414, cardWidth: 66, visibleLimit: 10, minVisibleWidth: 34, spacing: 6)

        XCTAssertFalse(plan.needsScrolling)
        XCTAssertGreaterThanOrEqual(plan.stride, 34)
        XCTAssertLessThanOrEqual(plan.xOffset(for: 9) + plan.cardWidth, 414.1)
    }

    func testPortraitOverlapLayoutScrollsAboveTenCards() {
        let plan = PortraitOverlapLayout.plan(count: 11, containerWidth: 414, cardWidth: 66, visibleLimit: 10, minVisibleWidth: 34, spacing: 6)

        XCTAssertTrue(plan.needsScrolling)
        XCTAssertGreaterThan(plan.contentWidth, plan.containerWidth)
    }

    func testPortraitCombatArrowAnchorsResolveCardsAndDefenders() {
        let metrics = PortraitBattlefieldLayoutMetrics(
            size: CGSize(width: 430, height: 932),
            safeArea: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
        )
        let attacker = zoneCard(id: "attacker-1", name: "Elvish Guide", typeLine: "Creature")
        let blocker = zoneCard(id: "blocker-1", name: "Silvercoat Lion", typeLine: "Creature")

        let anchors = PortraitCombatAnchorResolver.cardAnchors(
            metrics: metrics,
            humanBattlefield: [attacker],
            opponentBattlefield: [blocker]
        )

        XCTAssertEqual(try XCTUnwrap(anchors["attacker-1"]).y, metrics.playerBattlefieldRect.midY, accuracy: 0.1)
        XCTAssertEqual(try XCTUnwrap(anchors["blocker-1"]).y, metrics.opponentBattlefieldRect.midY, accuracy: 0.1)
        XCTAssertEqual(PortraitCombatAnchorResolver.defenderAnchor(for: "ai", kind: "player", metrics: metrics).y, metrics.topHUDRect.midY, accuracy: 0.1)
        XCTAssertEqual(PortraitCombatAnchorResolver.defenderAnchor(for: "human", kind: "player", metrics: metrics).y, metrics.bottomHUDRect.midY, accuracy: 0.1)
        XCTAssertEqual(PortraitCombatAnchorResolver.defenderAnchor(for: "planeswalker-1", kind: "planeswalker", metrics: metrics).y, metrics.opponentBattlefieldRect.midY, accuracy: 0.1)
    }

    private func decodeAction(type: String, label: String? = nil, extra: String? = nil) throws -> LegalAction {
        let extraFields = extra.map { ",\n          \($0)" } ?? ""
        let data = """
        {
          "id": "\(type)-action",
          "type": "\(type)",
          "playerId": "human",
          "label": "\(label ?? type)",
          "promptId": "prompt-1",
          "messageId": 1\(extraFields)
        }
        """.data(using: .utf8)!
        return try JSONDecoder.magicMobile.decode(LegalAction.self, from: data)
    }

    private func zoneCard(id: String, name: String, typeLine: String) -> ZoneCard {
        ZoneCard(
            instanceId: id,
            card: CardIdentity(name: name, typeLine: typeLine, oracleText: nil),
            tapped: nil,
            summoningSickness: nil,
            cardIcons: nil,
            counters: nil,
            power: nil,
            toughness: nil,
            isCreaturePermanent: nil,
            damage: nil,
            isAttacking: nil,
            blocking: nil,
            attachedToInstanceId: nil
        )
    }

    private func minimalSnapshotJSON(id: String) throws -> Data {
        """
        {
          "id": "\(id)",
          "source": "xmage-java-bridge",
          "activePlayerId": "human",
          "phase": "precombat-main",
          "step": "precombat-main",
          "turn": 1,
          "priorityPlayerId": "human",
          "waitingOnPlayerId": "human",
          "promptText": "Your priority",
          "players": [
            {
              "playerId": "human",
              "life": 40,
              "poison": 0,
              "commanderTax": 0,
              "manaPool": { "W": 0, "U": 0, "B": 0, "R": 0, "G": 0, "C": 0 },
              "zones": {
                "library": [],
                "hand": [],
                "battlefield": [],
                "graveyard": [],
                "exile": [],
                "command": [],
                "stack": []
              },
              "commanderDamage": {}
            }
          ],
          "log": [],
          "legalActions": [],
          "bridgeRevision": 7,
          "xmageCycle": 11,
          "pendingStatus": null
        }
        """.data(using: .utf8)!
    }

    private func snapshotWithHumanHand(cardId: String, cardName: String) throws -> GameSnapshot {
        let json = String(data: try minimalSnapshotJSON(id: "snapshot-\(cardId)"), encoding: .utf8)!
            .replacingOccurrences(of: #""hand": []"#, with: #""hand": [{ "instanceId": "\#(cardId)", "card": { "name": "\#(cardName)", "typeLine": "Artifact", "oracleText": "" } }]"#)
        return try JSONDecoder.magicMobile.decode(GameSnapshot.self, from: json.data(using: .utf8)!)
    }

    private func promptEnvelopeV2(responseType: String, responsePromptId: String, responseMessageId: Int) throws -> PromptEnvelopeV2 {
        let data = """
        {
          "id": "visible-prompt-1",
          "method": "GAME_CHOOSE",
          "messageId": 11,
          "playerId": "human",
          "responseKind": "\(responseType)",
          "message": "Choose",
          "responseCommand": {
            "type": "\(responseType)",
            "promptId": "\(responsePromptId)",
            "messageId": \(responseMessageId)
          }
        }
        """.data(using: .utf8)!
        return try JSONDecoder.magicMobile.decode(PromptEnvelopeV2.self, from: data)
    }

    private func payload(for command: GameCommand?) throws -> [String: Any] {
        let command = try XCTUnwrap(command)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder.magicMobile.encode(command)) as? [String: Any])
    }

    private func assertGameplayLayout(_ metrics: BattlefieldLayoutMetrics, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(metrics.safeFrame.contains(metrics.rightDockRect), file: file, line: line)
        XCTAssertTrue(metrics.safeFrame.contains(metrics.boardColumnRect), file: file, line: line)
        XCTAssertTrue(metrics.safeFrame.contains(metrics.handRect), file: file, line: line)
        XCTAssertTrue(metrics.safeFrame.contains(metrics.bottomActionRect), file: file, line: line)
        XCTAssertTrue(metrics.safeFrame.contains(metrics.rightActionPanelRect), file: file, line: line)
        XCTAssertTrue(metrics.safeFrame.contains(metrics.phaseRailRect), file: file, line: line)

        XCTAssertFalse(metrics.handRect.intersects(metrics.playerBattlefieldRect), file: file, line: line)
        XCTAssertFalse(metrics.centerStripRect.intersects(metrics.opponentBattlefieldRect), file: file, line: line)
        XCTAssertFalse(metrics.centerStripRect.intersects(metrics.opponentLandsRect), file: file, line: line)
        XCTAssertFalse(metrics.centerStripRect.intersects(metrics.playerBattlefieldRect), file: file, line: line)
        XCTAssertFalse(metrics.centerStripRect.intersects(metrics.playerLandsRect), file: file, line: line)
        XCTAssertFalse(metrics.phaseRailRect.intersects(metrics.bottomActionRect), file: file, line: line)

        XCTAssertEqual(metrics.playerDropZone.minX, metrics.boardColumnRect.minX, accuracy: 0.1, file: file, line: line)
        XCTAssertEqual(metrics.playerDropZone.maxX, metrics.boardColumnRect.maxX, accuracy: 0.1, file: file, line: line)
        XCTAssertGreaterThanOrEqual(metrics.handRect.height, metrics.handCardHeight, file: file, line: line)
        XCTAssertGreaterThanOrEqual(metrics.opponentBattlefieldRect.height, 52, file: file, line: line)
        XCTAssertGreaterThanOrEqual(metrics.playerBattlefieldRect.height, 52, file: file, line: line)
        XCTAssertGreaterThanOrEqual(metrics.opponentLandsRect.height, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(metrics.playerLandsRect.height, 44, file: file, line: line)
    }

    private func assertPortraitGameplayLayout(_ metrics: PortraitBattlefieldLayoutMetrics, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(metrics.safeFrame.contains(metrics.topHUDRect), file: file, line: line)
        XCTAssertTrue(metrics.safeFrame.contains(metrics.opponentBattlefieldRect), file: file, line: line)
        XCTAssertTrue(metrics.safeFrame.contains(metrics.opponentLandsRect), file: file, line: line)
        XCTAssertTrue(metrics.safeFrame.contains(metrics.centerStripRect), file: file, line: line)
        XCTAssertTrue(metrics.safeFrame.contains(metrics.playerBattlefieldRect), file: file, line: line)
        XCTAssertTrue(metrics.safeFrame.contains(metrics.playerLandsRect), file: file, line: line)
        XCTAssertTrue(metrics.safeFrame.contains(metrics.handRect), file: file, line: line)
        XCTAssertTrue(metrics.safeFrame.contains(metrics.bottomControlsRect), file: file, line: line)
        XCTAssertTrue(metrics.safeFrame.contains(metrics.stackPanelRect), file: file, line: line)
        XCTAssertTrue(metrics.safeFrame.contains(metrics.bottomActionPanelRect), file: file, line: line)
        XCTAssertTrue(metrics.safeFrame.contains(metrics.passButtonRect), file: file, line: line)
        XCTAssertTrue(metrics.safeFrame.contains(metrics.skipButtonRect), file: file, line: line)
        XCTAssertTrue(metrics.safeFrame.contains(metrics.bottomNavRect), file: file, line: line)
        XCTAssertTrue(metrics.safeFrame.contains(metrics.settingsButtonRect), file: file, line: line)
        XCTAssertTrue(metrics.safeFrame.contains(metrics.handScrubberRect), file: file, line: line)

        XCTAssertLessThan(metrics.topHUDRect.maxY, metrics.opponentBattlefieldRect.minY, file: file, line: line)
        XCTAssertLessThan(metrics.opponentBattlefieldRect.maxY, metrics.opponentLandsRect.minY, file: file, line: line)
        XCTAssertLessThan(metrics.opponentLandsRect.maxY, metrics.centerStripRect.minY, file: file, line: line)
        XCTAssertLessThan(metrics.centerStripRect.maxY, metrics.playerBattlefieldRect.minY, file: file, line: line)
        XCTAssertLessThan(metrics.playerBattlefieldRect.maxY, metrics.playerLandsRect.minY, file: file, line: line)
        XCTAssertLessThan(metrics.playerLandsRect.maxY, metrics.handRect.minY, file: file, line: line)
        XCTAssertLessThan(metrics.handRect.maxY, metrics.bottomControlsRect.minY + 0.1, file: file, line: line)
        XCTAssertTrue(metrics.bottomControlsRect.contains(metrics.bottomHUDRect), file: file, line: line)
        XCTAssertTrue(metrics.bottomControlsRect.contains(metrics.bottomActionPanelRect), file: file, line: line)
        XCTAssertTrue(metrics.bottomControlsRect.contains(metrics.stackPanelRect), file: file, line: line)
        XCTAssertTrue(metrics.bottomActionPanelRect.contains(metrics.passButtonRect), file: file, line: line)
        XCTAssertTrue(metrics.bottomActionPanelRect.contains(metrics.skipButtonRect), file: file, line: line)
        XCTAssertLessThan(metrics.passButtonRect.maxY, metrics.skipButtonRect.minY, file: file, line: line)
        XCTAssertTrue(metrics.bottomNavRect.contains(metrics.settingsButtonRect), file: file, line: line)
        XCTAssertLessThan(metrics.bottomHUDRect.maxX, metrics.bottomActionPanelRect.minX, file: file, line: line)
        XCTAssertLessThan(metrics.bottomActionPanelRect.maxX, metrics.stackPanelRect.minX, file: file, line: line)
        XCTAssertFalse(metrics.stackPanelRect.intersects(metrics.passButtonRect), file: file, line: line)
        XCTAssertFalse(metrics.stackPanelRect.intersects(metrics.skipButtonRect), file: file, line: line)
        XCTAssertFalse(metrics.stackPanelRect.intersects(metrics.settingsButtonRect), file: file, line: line)
    }
}
