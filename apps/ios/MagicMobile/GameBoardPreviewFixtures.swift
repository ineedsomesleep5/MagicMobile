import Foundation

enum GameBoardPreviewFixtures {
    static func snapshot(_ state: GameBoardDesignPreviewState) -> GameSnapshot {
        let data = json(for: state).data(using: .utf8)!
        return try! JSONDecoder.magicMobile.decode(GameSnapshot.self, from: data)
    }

    static func selectedCard(for state: GameBoardDesignPreviewState, snapshot: GameSnapshot) -> ZoneCard? {
        guard state == .selectedCardActionTray || state == .missingCardArt else { return nil }
        return snapshot.human?.zones.hand.first
    }

    private static func json(for state: GameBoardDesignPreviewState) -> String {
        let prompt = promptEnvelope(for: state)
        let pendingStatus = state == .aiThinking ? "waiting_for_xmage" : "ready"
        let priorityPlayerId = state == .aiThinking ? "ai-1" : "human"
        let promptText = prompt == nil ? (state == .aiThinking ? "AI thinking" : "Your priority") : "Design preview prompt"
        let extraActions = actions(for: state)
        let health = state == .bridgeUnavailable
            ? #""engineHealth":{"status":"unavailable","reason":"Design preview bridge unavailable.","checkedAt":"preview","recoveryAction":"reconnect"},"#
            : #""engineHealth":{"status":"ready","reason":"Design preview only. Not gameplay proof.","checkedAt":"preview","recoveryAction":"none"},"#

        return """
        {
          "id":"design-preview-\(state.rawValue)",
          "source":"design-preview",
          "activePlayerId":"human",
          "phase":"precombat-main",
          "step":"precombat-main",
          "turn":3,
          "priorityPlayerId":"\(priorityPlayerId)",
          "waitingOnPlayerId":"\(priorityPlayerId)",
          "promptText":"\(promptText)",
          "players":[
            {
              "playerId":"human",
              "life":37,
              "poison":0,
              "commanderTax":2,
              "manaPool":{"W":1,"U":0,"B":0,"R":0,"G":1,"C":2},
              "zones":\(humanZones(missingArt: state == .missingCardArt)),
              "commanderDamage":{"ai-1":4,"human":0}
            },
            {
              "playerId":"ai-1",
              "life":31,
              "poison":0,
              "commanderTax":0,
              "manaPool":{"W":0,"U":0,"B":0,"R":0,"G":0,"C":0},
              "zones":\(opponentZones()),
              "commanderDamage":{"human":2,"ai-1":0}
            }
          ],
          "log":[
            {"id":"log-1","message":"Design preview only: do not use as gameplay proof.","createdAt":"preview"},
            {"id":"log-2","message":"XMage remains the source of truth in real games.","createdAt":"preview"}
          ],
          "legalActions":\(extraActions),
          "choicePrompt":null,
          "promptEnvelope":null,
          "promptEnvelopeV2":\(prompt ?? "null"),
          "xmage":null,
          \(health)
          "bridgeRevision":99,
          "xmageCycle":144,
          "pendingStatus":"\(pendingStatus)"
        }
        """
    }

    private static func humanZones(missingArt: Bool) -> String {
        """
        {
          "library":[\(hiddenCard("library-human-1")), \(hiddenCard("library-human-2"))],
          "hand":[
            \(zoneCard("hand-sol-ring", "Sol Ring", "Artifact", "{T}: Add {C}{C}.", nil, nil)),
            \(zoneCard("hand-forest", "Forest", "Basic Land - Forest", "{T}: Add {G}.", nil, nil)),
            \(zoneCard("hand-spell", missingArt ? "Unknown Preview Card" : "Swords to Plowshares", "Instant", "Exile target creature.", nil, nil))
          ],
          "battlefield":[
            \(zoneCard("human-plains-1", "Plains", "Basic Land - Plains", "{T}: Add {W}.", true, nil)),
            \(zoneCard("human-forest-1", "Forest", "Basic Land - Forest", "{T}: Add {G}.", false, nil)),
            \(zoneCard("human-commander", "Isamaru, Hound of Konda", "Legendary Creature - Dog", "Commander", false, "2"))
          ],
          "graveyard":[\(zoneCard("human-grave-1", "Spirited Companion", "Enchantment Creature - Dog", "When this enters, draw a card.", nil, "1"))],
          "exile":[],
          "command":[\(zoneCard("human-command-1", "Isamaru, Hound of Konda", "Legendary Creature - Dog", "Commander", nil, "2"))],
          "stack":[]
        }
        """
    }

    private static func opponentZones() -> String {
        """
        {
          "library":[\(hiddenCard("library-ai-1")), \(hiddenCard("library-ai-2"))],
          "hand":[\(hiddenCard("ai-hand-1")), \(hiddenCard("ai-hand-2"))],
          "battlefield":[
            \(zoneCard("ai-wastes-1", "Wastes", "Basic Land", "{T}: Add {C}.", true, nil)),
            \(zoneCard("ai-creature-1", "Memnite", "Artifact Creature - Construct", "", false, "1"))
          ],
          "graveyard":[],
          "exile":[],
          "command":[\(zoneCard("ai-command-1", "Kozilek, Butcher of Truth", "Legendary Creature - Eldrazi", "Commander", nil, "12"))],
          "stack":[]
        }
        """
    }

    private static func zoneCard(_ id: String, _ name: String, _ typeLine: String, _ oracleText: String, _ tapped: Bool?, _ power: String?) -> String {
        let tappedText = tapped.map { #","tapped":\#($0)"# } ?? ""
        let stats = power.map { #","power":\#($0),"toughness":\#($0)"# } ?? ""
        return #"""
        {"instanceId":"\#(id)","card":{"name":"\#(name)","typeLine":"\#(typeLine)","oracleText":"\#(oracleText)"}\#(tappedText)\#(stats)}
        """#
    }

    private static func hiddenCard(_ id: String) -> String {
        #"""
        {"instanceId":"\#(id)","card":{"name":"Hidden card","typeLine":"Hidden","oracleText":null}}
        """#
    }

    private static func actions(for state: GameBoardDesignPreviewState) -> String {
        switch state {
        case .aiThinking, .bridgeUnavailable, .unsupportedPromptFallback:
            return #"[{"id":"concede","type":"concede","playerId":"human","label":"Concede"}]"#
        default:
            return #"""
            [
              {"id":"cast-sol-ring","type":"cast_spell","playerId":"human","label":"Cast Sol Ring","cardInstanceId":"hand-sol-ring","cardName":"Sol Ring","sourceZone":"hand","isPrimary":true},
              {"id":"make-mana-forest","type":"make_mana","playerId":"human","label":"Tap Forest","sourceInstanceId":"human-forest-1","cardName":"Forest","producedMana":["G"]},
              {"id":"pass-priority","type":"pass_priority","playerId":"human","label":"Done"}
            ]
            """#
        }
    }

    private static func promptEnvelope(for state: GameBoardDesignPreviewState) -> String? {
        switch state {
        case .manaPaymentPrompt:
            return #"""
            {"id":"preview-mana","method":"GAME_PLAY_MANA","messageId":1,"playerId":"human","responseKind":"mana","message":"Pay {1}{W}","required":true,"minChoices":1,"maxChoices":1,"manaChoices":[{"id":"W","label":"Pay {W}","manaType":"W"},{"id":"C","label":"Pay {C}","manaType":"C"}],"choices":[{"id":"W","label":"Pay {W}"},{"id":"C","label":"Pay {C}"}],"responseCommand":{"type":"play_mana","promptId":"preview-mana","messageId":1}}
            """#
        case .searchSelectPrompt:
            return #"""
            {"id":"preview-search","method":"GAME_SELECT","messageId":2,"playerId":"human","responseKind":"choose_card","message":"Search your library for a basic land card.","required":true,"minChoices":1,"maxChoices":1,"cards":[{"instanceId":"search-plains","card":{"name":"Plains","typeLine":"Basic Land - Plains","oracleText":"{T}: Add {W}."}},{"instanceId":"search-forest","card":{"name":"Forest","typeLine":"Basic Land - Forest","oracleText":"{T}: Add {G}."}}],"choices":[{"id":"search-plains","label":"Plains","cardInstanceId":"search-plains"},{"id":"search-forest","label":"Forest","cardInstanceId":"search-forest"}],"responseCommand":{"type":"choose_card","promptId":"preview-search","messageId":2}}
            """#
        case .stackResponsePrompt:
            return #"""
            {"id":"preview-stack","method":"GAME_PRIORITY","messageId":3,"playerId":"human","responseKind":"pass_priority","message":"Respond to the spell on the stack.","required":false,"minChoices":0,"maxChoices":0,"choices":[{"id":"pass","label":"Pass priority"}],"responseCommand":{"type":"pass_priority","promptId":"preview-stack","messageId":3}}
            """#
        case .commanderReplacementPrompt:
            return #"""
            {"id":"preview-commander-replacement","method":"GAME_ASK","messageId":4,"playerId":"human","responseKind":"commander_replacement","message":"Move your commander to the command zone instead?","required":true,"minChoices":1,"maxChoices":1,"confirmation":{"yesLabel":"Command Zone","noLabel":"Original Zone","defaultValue":null},"choices":[{"id":"true","label":"Command Zone"},{"id":"false","label":"Original Zone"}],"responseCommand":{"type":"commander_replacement","promptId":"preview-commander-replacement","messageId":4}}
            """#
        case .damageAssignmentPrompt:
            return #"""
            {"id":"preview-damage","method":"GAME_GET_MULTI_AMOUNT","messageId":5,"playerId":"human","responseKind":"multi_amount","message":"Assign 6 combat damage among blockers.","required":true,"minChoices":2,"maxChoices":2,"totalMin":6,"totalMax":6,"multiAmounts":[{"id":"blocker-a","label":"Silvercoat Lion","min":1,"max":5,"defaultValue":1},{"id":"blocker-b","label":"Memnite","min":1,"max":5,"defaultValue":1}],"responseCommand":{"type":"choose_multi_amount","promptId":"preview-damage","messageId":5}}
            """#
        case .unsupportedPromptFallback:
            return #"""
            {"id":"preview-unsupported","method":"GAME_UNSUPPORTED_ROUTE","messageId":6,"playerId":"human","responseKind":"unsupported_mobile_prompt","message":"XMage is asking for a route the mobile client must not answer by default.","required":true,"minChoices":1,"maxChoices":1,"responseCommand":{"type":"unsupported_mobile_prompt","promptId":"preview-unsupported","messageId":6}}
            """#
        default:
            return nil
        }
    }
}
