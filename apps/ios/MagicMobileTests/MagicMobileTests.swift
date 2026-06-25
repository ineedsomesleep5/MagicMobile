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
            counters: nil,
            power: nil,
            toughness: nil,
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
            counters: nil,
            power: nil,
            toughness: nil,
            damage: nil,
            isAttacking: nil,
            blocking: nil,
            attachedToInstanceId: nil
        )

        XCTAssertEqual(card.accessibilityIdentifier(zoneName: "Command Zone"), "card-command-zone-arcane-signet-abcdef12")
    }

    func testCardImageURLCanForcePlaceholdersForVisualQA() {
        XCTAssertNil(CardImageURL.normal("Sol Ring", forcePlaceholder: true))
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
        XCTAssertEqual("precombat-main".compactPhaseTitle, "Main 1")
        XCTAssertEqual("postcombat-main".compactPhaseTitle, "Main 2")
        XCTAssertEqual("declare-attackers".compactPhaseTitle, "Attackers")
        XCTAssertEqual("combat-damage".compactPhaseTitle, "Damage")
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
          "paid": false
        }
        """.data(using: .utf8)!

        let object = try JSONDecoder.magicMobile.decode(XmageStackObject.self, from: data)

        XCTAssertNil(object.sourceCard)
        XCTAssertEqual(object.displayName, "Activated ability")
        XCTAssertEqual(object.displaySourceName, "Source unavailable")
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

    func testPromptCommandBuilderBuildsOrderedAndAmountCommands() throws {
        let prompt = try promptEnvelopeV2(responseType: "order_triggers", responsePromptId: "prompt-order", responseMessageId: 12)

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

        XCTAssertEqual(ordered["orderedIds"] as? [String], ["trigger-2", "trigger-1"])
        XCTAssertEqual(ordered["messageId"] as? Int, 12)
        XCTAssertEqual(amount["amount"] as? Int, 3)
        XCTAssertEqual(multiAmount["amounts"] as? [Int], [1, 2])
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
        XCTAssertGreaterThan(metrics.centerStripRect.height, 24)
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

    private func decodeAction(type: String, extra: String? = nil) throws -> LegalAction {
        let extraFields = extra.map { ",\n          \($0)" } ?? ""
        let data = """
        {
          "id": "\(type)-action",
          "type": "\(type)",
          "playerId": "human",
          "label": "\(type)",
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
            counters: nil,
            power: nil,
            toughness: nil,
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

        XCTAssertFalse(metrics.boardColumnRect.intersects(metrics.rightDockRect), file: file, line: line)
        XCTAssertFalse(metrics.boardColumnRect.intersects(metrics.rightActionPanelRect), file: file, line: line)
        XCTAssertFalse(metrics.handRect.intersects(metrics.playerBattlefieldRect), file: file, line: line)
        XCTAssertFalse(metrics.centerStripRect.intersects(metrics.opponentBattlefieldRect), file: file, line: line)
        XCTAssertFalse(metrics.centerStripRect.intersects(metrics.opponentLandsRect), file: file, line: line)
        XCTAssertFalse(metrics.centerStripRect.intersects(metrics.playerBattlefieldRect), file: file, line: line)
        XCTAssertFalse(metrics.centerStripRect.intersects(metrics.playerLandsRect), file: file, line: line)
        XCTAssertFalse(metrics.phaseRailRect.intersects(metrics.bottomActionRect), file: file, line: line)

        XCTAssertGreaterThanOrEqual(metrics.rightDockRect.minX - metrics.boardColumnRect.maxX, 10, file: file, line: line)
        XCTAssertGreaterThanOrEqual(metrics.handRect.height, metrics.handCardHeight, file: file, line: line)
        XCTAssertGreaterThanOrEqual(metrics.opponentBattlefieldRect.height, 52, file: file, line: line)
        XCTAssertGreaterThanOrEqual(metrics.playerBattlefieldRect.height, 52, file: file, line: line)
        XCTAssertGreaterThanOrEqual(metrics.opponentLandsRect.height, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(metrics.playerLandsRect.height, 44, file: file, line: line)
    }
}
