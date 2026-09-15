import Foundation

enum GameBoardPreviewFixtures {
    static func snapshot(_ state: GameBoardDesignPreviewState) -> GameSnapshot {
        var root = try! JSONSerialization.jsonObject(with: Data(json(for: state).utf8)) as! [String: Any]
        enrich(&root, for: state)
        if let prompt = root["promptEnvelopeV2"] as? [String: Any] { root["promptText"] = prompt["message"] }
        let data = try! JSONSerialization.data(withJSONObject: root)
        return try! JSONDecoder.magicMobile.decode(GameSnapshot.self, from: data)
    }

    static func selectedCard(for state: GameBoardDesignPreviewState, snapshot: GameSnapshot) -> ZoneCard? {
        guard state == .selectedCardActionTray || state == .missingCardArt || state == .fullHandInspection else { return nil }
        return snapshot.human?.zones.hand.first
    }

    // Development fixture projection only. These actions never enter a live engine session.
    private static func enrich(_ root: inout [String: Any], for state: GameBoardDesignPreviewState) {
        func card(_ id: String, _ name: String, _ type: String, _ cost: String, _ rules: String, power: Int? = nil) -> [String: Any] {
            var value: [String: Any] = ["instanceId": id, "card": ["name": name, "typeLine": type, "manaCost": cost, "oracleText": rules], "tapped": false]
            if let power { value.merge(["power": power, "toughness": power, "isCreaturePermanent": true]) { _, new in new } }
            return value
        }
        let creatures = [("Silvercoat Lion", "{1}{W}", 2), ("Serra Angel", "{3}{W}{W}", 4), ("Grizzly Bears", "{1}{G}", 2), ("Llanowar Elves", "{G}", 1), ("Spirited Companion", "{1}{W}", 1), ("Sun Titan", "{4}{W}{W}", 6)]
        let crowded = [GameBoardDesignPreviewState.crowdedBattlefield, .fourPlayerFocus, .manaPaymentPrompt, .combatArrows, .largeText].contains(state)
        var players = root["players"] as! [[String: Any]]
        if state == .fourPlayerFocus || state == .playerTargetPrompt {
            for number in 2...3 {
                var opponent = players[1]
                opponent["playerId"] = "ai-\(number)"
                opponent["life"] = 40 - number * 3
                var zones = opponent["zones"] as! [String: Any]
                for (zone, contents) in zones {
                    guard let cards = contents as? [[String: Any]] else { continue }
                    zones[zone] = cards.map { original in
                        var copy = original; copy["instanceId"] = "ai-\(number)-\(original["instanceId"]!)"; return copy
                    }
                }
                opponent["zones"] = zones; players.append(opponent)
            }
        }
        for index in players.indices {
            let seat = players[index]["playerId"] as! String
            players[index]["displayName"] = index == 0 ? "You" : ["", "Aurelia", "Kozilek", "Meren"][index]
            var zones = players[index]["zones"] as! [String: Any]
            var battlefield = zones["battlefield"] as! [[String: Any]]
            for (number, creature) in creatures.prefix(crowded ? 6 : 2).enumerated() {
                var permanent = card("\(seat)-preview-creature-\(number)", creature.0, "Creature", creature.1, "Development fixture permanent.", power: creature.2)
                permanent["tapped"] = number == 2; battlefield.append(permanent)
            }
            for number in 2...(crowded ? 5 : 2) {
                battlefield.append(card("\(seat)-preview-land-\(number)", "Forest", "Basic Land — Forest", "", "{T}: Add {G}."))
            }
            if state == .stackResponsePrompt && index == 1 {
                battlefield.append(card("ai-1-ability-source", "Prodigal Pyromancer", "Creature — Human Wizard", "{2}{R}", "{T}: This creature deals 1 damage to any target.", power: 1))
            }
            if index == 0 {
                battlefield.append(card("human-sol-ring", "Sol Ring", "Artifact", "{1}", "{T}: Add {C}{C}."))
                var hand = zones["hand"] as! [[String: Any]]
                for (number, creature) in creatures.prefix(5).enumerated() {
                    hand.append(card("hand-preview-\(number)", creature.0, "Creature", creature.1, "Development inspection fixture.", power: creature.2))
                }
                zones["hand"] = hand
                zones["exile"] = [card("human-exile-1", "Swords to Plowshares", "Instant", "{W}", "Exile target creature. Its controller gains life equal to its power.")]
            }
            if state == .combatArrows {
                let id = index == 0 ? "human-preview-creature-0" : "ai-1-preview-creature-0"
                if let offset = battlefield.firstIndex(where: { $0["instanceId"] as? String == id }) {
                    if index == 0 { battlefield[offset]["isAttacking"] = true; battlefield[offset]["tapped"] = true }
                    else { battlefield[offset]["blocking"] = ["human-preview-creature-0"] }
                }
            }
            if state == .manaPaymentPrompt, index == 0, let ring = battlefield.firstIndex(where: { $0["instanceId"] as? String == "human-sol-ring" }) {
                battlefield.insert(battlefield.remove(at: ring), at: 0)
            }
            zones["battlefield"] = battlefield; players[index]["zones"] = zones
        }
        root["players"] = players
        var actions = root["legalActions"] as! [[String: Any]]
        if ![GameBoardDesignPreviewState.aiThinking, .bridgeUnavailable, .unsupportedPromptFallback].contains(state) {
            actions.append(["id": "make-mana-sol-ring", "type": "make_mana", "playerId": "human", "label": "Tap Sol Ring", "sourceInstanceId": "human-sol-ring", "cardName": "Sol Ring", "sourceZone": "battlefield", "producedMana": ["C", "C"]])
        }
        root["legalActions"] = actions
        let skip = Dictionary(uniqueKeysWithValues: ["passedTurn", "passedUntilEndOfTurn", "passedUntilNextMain", "passedUntilStackResolved", "passedAllTurns", "passedUntilEndStepBeforeMyTurn"].map { ($0, false) })
        let enginePlayers: [[String: Any]] = players.map { player in
            let zones = player["zones"] as! [String: Any]
            return ["playerId": player["playerId"]!, "name": player["displayName"]!, "active": player["playerId"] as? String == "human", "hasPriority": (player["playerId"] as? String) == (root["priorityPlayerId"] as? String), "timerActive": false, "skipState": skip, "manaPool": player["manaPool"]!, "command": zones["command"]!, "zones": ["battlefield": zones["battlefield"]!, "graveyard": zones["graveyard"]!, "exile": zones["exile"]!, "sideboard": []]]
        }
        var xmage: [String: Any] = ["schemaVersion": 1, "gameId": root["id"]!, "bridgeRevision": 99, "callbackCoverage": [], "players": enginePlayers, "stack": [], "combat": [], "exileZones": [], "revealed": [], "lookedAt": [], "companion": [], "playableObjects": [], "panels": ["stack": state == .stackResponsePrompt, "command": true, "graveyard": true, "exile": true, "revealed": false, "lookedAt": false, "search": false]]
        if state == .stackResponsePrompt {
            let source = card("ai-1-ability-source", "Prodigal Pyromancer", "Creature — Human Wizard", "{2}{R}", "{T}: This creature deals 1 damage to any target.", power: 1)
            let spell = card("stack-swords-card", "Swords to Plowshares", "Instant", "{W}", "Exile target creature. Its controller gains life equal to its power.")
            xmage["stack"] = [
                ["id": "stack-ability-object", "objectId": "stack-ability-object", "objectType": "ACTIVATED_ABILITY", "name": "Deal 1 damage", "rulesText": "Prodigal Pyromancer deals 1 damage to any target.", "sourceInstanceId": "ai-1-ability-source", "sourceName": "Prodigal Pyromancer", "sourceZone": "battlefield", "sourceCard": source, "controllerId": "ai-1", "targetIds": ["human"], "paid": true],
                ["id": "stack-spell-object", "objectId": "stack-spell-object", "objectType": "SPELL", "name": "Swords to Plowshares", "sourceName": "Swords to Plowshares", "sourceCard": spell, "controllerId": "human", "targetIds": ["ai-creature-1"], "paid": true]
            ]
        }
        if state == .combatArrows {
            let own = (players[0]["zones"] as! [String: Any])["battlefield"] as! [[String: Any]]
            let opposing = (players[1]["zones"] as! [String: Any])["battlefield"] as! [[String: Any]]
            xmage["combat"] = [["defenderId": "ai-1", "defenderName": "Aurelia", "defenderKind": "player", "blocked": true, "attackers": own.filter { $0["isAttacking"] as? Bool == true }, "blockers": opposing.filter { $0["blocking"] != nil }]]
            root["phase"] = "combat"; root["step"] = "declare-blockers"
        }
        if state == .zoneInspection {
            for key in ["exileZones", "revealed", "lookedAt", "companion"] {
                xmage[key] = [["id": "preview-\(key)", "name": "Development \(key)", "cards": [card("preview-\(key)-card", "Forest", "Basic Land — Forest", "", "{T}: Add {G}.")]]]
            }
        }
        root["xmage"] = xmage
        if state == .playerTargetPrompt || state == .cardTargetPrompt {
            root["legalActions"] = []
            let ids = state == .playerTargetPrompt ? players.map { $0["playerId"] as! String } : ["ai-creature-1", "human-commander"]
            let labels = state == .playerTargetPrompt ? players.map { $0["displayName"] as! String } : ["Serra Angel", "Isamaru, Hound of Konda"]
            root["promptEnvelopeV2"] = ["id": "preview-target", "method": "GAME_PICK_TARGET", "messageId": 9, "playerId": "human", "responseKind": "target", "message": state == .playerTargetPrompt ? "Choose a player to take the first turn" : "Choose target creature", "required": true, "minChoices": 1, "maxChoices": 1, "targetIds": ids, "targets": zip(ids, labels).map { ["id": $0.0, "label": $0.1] }, "responseCommand": ["type": "choose_target", "promptId": "preview-target", "messageId": 9]]
        }
        if state == .manaPaymentPrompt {
            root["legalActions"] = actions.filter { $0["type"] as? String == "make_mana" }
            var paymentPrompt = root["promptEnvelopeV2"] as! [String: Any]
            paymentPrompt["message"] = "Pay {2}{W}"
            root["promptEnvelopeV2"] = paymentPrompt
            root["manaPayment"] = ["active": true, "spellName": "Serra Angel", "manaCostText": "{3}{W}{W}", "remainingText": "{2}{W}", "remaining": ["generic": 2, "W": 1, "U": 0, "B": 0, "R": 0, "G": 0, "C": 0, "total": 3]]
        }
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
            \(zoneCard("human-commander", "Isamaru, Hound of Konda", "Legendary Creature - Dog", "Commander", false, "2", summoningSickness: true))
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
            \(zoneCard("ai-creature-1", "Serra Angel", "Creature - Angel", "Flying, vigilance", false, "4", summoningSickness: true, icons: #"""
              [
                {"iconType":"ABILITY_FLYING","resourceName":"prepared/feather-alt.svg","category":"ABILITY","hint":"Flying"},
                {"iconType":"ABILITY_VIGILANCE","resourceName":"prepared/eye.svg","category":"ABILITY","hint":"Vigilance"}
              ]
              """#))
          ],
          "graveyard":[],
          "exile":[],
          "command":[\(zoneCard("ai-command-1", "Kozilek, Butcher of Truth", "Legendary Creature - Eldrazi", "Commander", nil, "12"))],
          "stack":[]
        }
        """
    }

    private static func zoneCard(_ id: String, _ name: String, _ typeLine: String, _ oracleText: String, _ tapped: Bool?, _ power: String?, summoningSickness: Bool? = nil, icons: String? = nil) -> String {
        let tappedText = tapped.map { #","tapped":\#($0)"# } ?? ""
        let sicknessText = summoningSickness.map { #","summoningSickness":\#($0)"# } ?? ""
        let iconsText = icons.map { #","cardIcons":\#($0)"# } ?? ""
        let stats = power.map { #","power":\#($0),"toughness":\#($0)"# } ?? ""
        return #"""
        {"instanceId":"\#(id)","card":{"name":"\#(name)","typeLine":"\#(typeLine)","oracleText":"\#(oracleText)"}\#(tappedText)\#(sicknessText)\#(iconsText)\#(stats)}
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
