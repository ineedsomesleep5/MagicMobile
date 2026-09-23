import Foundation

enum GameBoardPreviewFixtures {
    static func snapshot(_ state: GameBoardDesignPreviewState, step: String? = nil, life: Int? = nil, specialStateAdvanced: Bool = false) -> GameSnapshot {
        var root = try! JSONSerialization.jsonObject(with: Data(json(for: state).utf8)) as! [String: Any]
        enrich(&root, for: state)
        if state == .attachedPermanents, specialStateAdvanced, var players = root["players"] as? [[String: Any]] {
            for index in players.indices {
                players[index]["poison"] = 5
                players[index]["counters"] = ["Poison": 5, "Energy": 4]
                var zones = players[index]["zones"] as! [String: Any]
                var cards = zones["battlefield"] as! [[String: Any]]
                for card in cards.indices {
                    if cards[card]["instanceId"] as? String == "human-sol-ring" { cards[card]["phasedIn"] = true }
                    if cards[card]["instanceId"] as? String == "player-curse" { cards[card]["attachedToInstanceId"] = "human" }
                }
                zones["battlefield"] = cards; players[index]["zones"] = zones
            }
            root["players"] = players
        }
        if let step {
            root["step"] = step
            root["activePlayerId"] = "ai-1"
        }
        if let life, var players = root["players"] as? [[String: Any]],
           let viewer = players.firstIndex(where: { $0["playerId"] as? String == "human" }) {
            players[viewer]["life"] = life
            root["players"] = players
        }
        if let prompt = root["promptEnvelopeV2"] as? [String: Any] { root["promptText"] = prompt["message"] }
        let data = try! JSONSerialization.data(withJSONObject: root)
        return try! JSONDecoder.magicMobile.decode(GameSnapshot.self, from: data)
    }

    #if DEBUG
    static let boardFXStepCount = 7

    /// Scripted board FX walkthrough for `MAGICMOBILE_DESIGN_PREVIEW=board-fx`.
    /// 0 base, 1 cast Swords, 2 Swords resolves (exile Angel, AI gains 4),
    /// 3 Sol Ring enters with a counter on Isamaru, 4 Isamaru attacks,
    /// 5 combat damage (AI -2, you -3, Isamaru marked), 6 Isamaru dies.
    static func boardFXStep(_ step: Int) -> GameSnapshot {
        var root = try! JSONSerialization.jsonObject(with: Data(json(for: .normalBattlefield).utf8)) as! [String: Any]
        root["id"] = "design-preview-board-fx"
        root["bridgeRevision"] = 1_000 + step
        root["legalActions"] = []
        var players = root["players"] as! [[String: Any]]
        let costs = ["Swords to Plowshares": "{W}", "Sol Ring": "{1}", "Isamaru, Hound of Konda": "{W}", "Serra Angel": "{3}{W}{W}"]
        func zone(_ player: Int, _ name: String) -> [[String: Any]] { (players[player]["zones"] as! [String: Any])[name] as! [[String: Any]] }
        func setZone(_ player: Int, _ name: String, _ cards: [[String: Any]]) {
            var zones = players[player]["zones"] as! [String: Any]
            zones[name] = cards.map { card in
                var card = card
                if var identity = card["card"] as? [String: Any], let name = identity["name"] as? String, let cost = costs[name] {
                    identity["manaCost"] = cost; card["card"] = identity
                }
                return card
            }
            players[player]["zones"] = zones
        }
        func move(_ id: String, from: (Int, String), to: (Int, String), edit: (inout [String: Any]) -> Void = { _ in }) {
            var source = zone(from.0, from.1)
            guard let index = source.firstIndex(where: { $0["instanceId"] as? String == id }) else { return }
            var card = source.remove(at: index)
            edit(&card)
            setZone(from.0, from.1, source)
            setZone(to.0, to.1, zone(to.0, to.1) + [card])
        }
        func editCard(_ id: String, player: Int, _ edit: (inout [String: Any]) -> Void) {
            setZone(player, "battlefield", zone(player, "battlefield").map { var card = $0; if card["instanceId"] as? String == id { edit(&card) }; return card })
        }
        let human = 0, ai = 1
        for zoneName in ["hand", "battlefield", "graveyard", "exile", "command"] {
            setZone(human, zoneName, zone(human, zoneName)); setZone(ai, zoneName, zone(ai, zoneName))
        }
        var stack: [[String: Any]] = []
        if step >= 1 {
            move("hand-spell", from: (human, "hand"), to: (human, "stack"))
            if step == 1 {
                let source = zone(human, "stack").first!
                stack = [["id": "stack-swords", "name": "Swords to Plowshares", "sourceCard": source,
                          "controllerId": "human", "sourceZone": "hand", "rulesText": "Exile target creature."]]
            }
        }
        if step >= 2 {
            move("hand-spell", from: (human, "stack"), to: (human, "graveyard"))
            move("ai-creature-1", from: (ai, "battlefield"), to: (ai, "exile"))
            players[ai]["life"] = 35
        }
        if step >= 3 {
            move("hand-sol-ring", from: (human, "hand"), to: (human, "battlefield"))
            editCard("human-commander", player: human) { $0["counters"] = ["+1/+1": 1]; $0["summoningSickness"] = false }
        }
        if step >= 4 { editCard("human-commander", player: human) { $0["isAttacking"] = true; $0["tapped"] = true } }
        if step >= 5 {
            players[ai]["life"] = 33
            players[human]["life"] = 34
            editCard("human-commander", player: human) { $0["damage"] = 2 }
        }
        if step >= 6 { move("human-commander", from: (human, "battlefield"), to: (human, "graveyard")) }
        root["players"] = players
        root["xmage"] = [
            "schemaVersion": 1, "gameId": "design-preview-board-fx", "bridgeRevision": 1_000 + step, "xmageCycle": 1_000 + step,
            "callbackCoverage": [], "stack": stack, "combat": [], "players": [], "exileZones": [], "revealed": [],
            "lookedAt": [], "companion": [], "playableObjects": [],
            "panels": ["stack": true, "command": true, "graveyard": true, "exile": true, "revealed": false, "lookedAt": false, "search": false],
        ] as [String: Any]
        let data = try! JSONSerialization.data(withJSONObject: root)
        return try! JSONDecoder.magicMobile.decode(GameSnapshot.self, from: data)
    }
    #endif

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
        let resourceLayoutMode = state == .crowdedBattlefield
            ? ProcessInfo.processInfo.environment["MAGICMOBILE_BOARD_RESOURCE_LAYOUT_UI_TEST"] : nil
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
            let previewCreatures = state == .combatArrows
                ? Array(repeating: creatures, count: 3).flatMap { $0 }
                : Array(creatures.prefix(crowded ? 6 : 2))
            for (number, creature) in previewCreatures.enumerated() {
                let power = creature.2 + (state == .combatArrows ? number / creatures.count : 0)
                var permanent = card("\(seat)-preview-creature-\(number)", creature.0, "Creature", creature.1, "Development fixture permanent.", power: power)
                permanent["tapped"] = number == 2; battlefield.append(permanent)
            }
            for number in 2...(crowded ? 5 : 2) {
                battlefield.append(card("\(seat)-preview-land-\(number)", "Forest", "Basic Land — Forest", "", "{T}: Add {G}."))
            }
            if state == .combatArrows {
                // Distinct development names prevent land grouping from hiding overflow.
                for number in 0..<12 {
                    battlefield.append(card("\(seat)-overflow-land-\(number)", "Fixture Land \(number)", "Land", "", "Development scrolling fixture."))
                }
            }
            if state == .zoneInspection && index == 0 {
                var graveyard = zones["graveyard"] as! [[String: Any]]
                for number in 0..<24 {
                    graveyard.append(card("graveyard-overflow-\(number)", "Fixture Graveyard \(number)", "Creature", "", "Development scrolling fixture.", power: 1))
                }
                zones["graveyard"] = graveyard
            }
            if state == .stackResponsePrompt && index == 1 {
                battlefield.append(card("ai-1-ability-source", "Prodigal Pyromancer", "Creature — Human Wizard", "{2}{R}", "{T}: This creature deals 1 damage to any target.", power: 1))
            }
            if state == .attachedPermanents {
                players[index]["poison"] = index == 0 ? 2 : 3
                players[index]["counters"] = ["Poison": index == 0 ? 2 : 3, "Energy": 4]
                players[index]["monarch"] = index == 1
                var aura = card("\(seat)-attached-aura", "Karametra's Favor", "Enchantment — Aura", "{1}{G}", "Enchant creature. Enchanted creature has {T}: Add one mana of any color.")
                aura["attachedToInstanceId"] = "ai-1-preview-creature-0"
                battlefield.append(aura)
                if index == 1 {
                    var equipment = card("attached-equipment", "Short Sword", "Artifact — Equipment", "{1}", "Equipped creature gets +1/+1.")
                    equipment["attachedToInstanceId"] = "ai-1-preview-creature-0"
                    battlefield.append(equipment)
                } else {
                    var curse = card("player-curse", "Curse of Opulence", "Enchantment — Aura Curse", "{R}", "Enchant player.")
                    curse["attachedToInstanceId"] = "ai-1"
                    battlefield.append(curse)
                }
            }
            if index == 0 {
                battlefield.append(card("human-sol-ring", "Sol Ring", "Artifact", "{1}", "{T}: Add {C}{C}."))
                if state == .attachedPermanents, let ring = battlefield.firstIndex(where: { $0["instanceId"] as? String == "human-sol-ring" }) {
                    battlefield[ring]["phasedIn"] = false
                }
                var hand = zones["hand"] as! [[String: Any]]
                let handCreatures = state == .handScrubber
                    ? Array(repeating: Array(creatures.prefix(5)), count: 4).flatMap { $0 }
                    : Array(creatures.prefix(5))
                for (number, creature) in handCreatures.enumerated() {
                    let id = state == .handScrubber && number == handCreatures.count - 1 ? "last-hand-card" : "hand-preview-\(number)"
                    hand.append(card(id, creature.0, "Creature", creature.1, "Development inspection fixture.", power: creature.2))
                }
                zones["hand"] = hand
                zones["exile"] = [card("human-exile-1", "Swords to Plowshares", "Instant", "{W}", "Exile target creature. Its controller gains life equal to its power.")]
            }
            if let resourceLayoutMode, ["rocks", "lands-only"].contains(resourceLayoutMode) {
                // Opt-in layout fixtures only. Distinct names keep density grouping from
                // hiding either row's independent horizontal overflow.
                if resourceLayoutMode == "lands-only" {
                    battlefield.removeAll { $0["instanceId"] as? String == "human-sol-ring" }
                }
                for number in 0..<12 {
                    battlefield.append(card("\(seat)-resource-land-\(number)", "Fixture Land \(number)",
                                            "Basic Land", "", "{T}: Add {G}."))
                }
                if resourceLayoutMode == "rocks" {
                    for number in 0..<10 {
                        var rock = card("\(seat)-resource-rock-\(number)", "Fixture Rock \(number)",
                                        "Artifact", "{2}", "{T}: Add {C}.")
                        rock["tapped"] = number == 1
                        battlefield.append(rock)
                    }
                    battlefield.append(contentsOf: [
                        card("\(seat)-resource-signet", "Dimir Signet", "Artifact", "{2}", "{1}, {T}: Add {U}{B}."),
                        card("\(seat)-resource-talisman", "Talisman of Dominance", "Artifact", "{2}", "{T}: Add {C}.\n{T}: Add {U} or {B}."),
                        card("\(seat)-resource-treasure", "Treasure token", "Token Artifact — Treasure", "", "{T}, Sacrifice this token: Add one mana of any color."),
                        card("\(seat)-resource-altar", "Ashnod's Altar", "Artifact", "{3}", "Sacrifice a creature: Add {C}{C}.")
                    ])
                }
                battlefield.insert(contentsOf: [
                    card("\(seat)-resource-sword", "Fixture Sword", "Artifact — Equipment", "{1}", "Equip {1}."),
                    card("\(seat)-resource-oath", "Fixture Oath", "Enchantment", "{2}", "Creatures you control get +1/+1.")
                ], at: 0)
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
        if state == .normalBattlefield, ProcessInfo.processInfo.environment["MAGICMOBILE_MDFC_UI_TEST"] == "1" {
            var zones = players[0]["zones"] as! [String: Any]
            zones["hand"] = (0..<3).map { index in
                card("modal-\(index)", "Revitalizing Repast", "Instant", "{B/G}", "Development fixture: Put a +1/+1 counter on target creature.")
            }
            players[0]["zones"] = zones
            root["players"] = players
            for (index, types) in [["play_land", "cast_spell"], ["cast_spell"], ["play_land"]].enumerated() {
                for type in types {
                    actions.append(["id": "modal-\(index)-\(type)", "type": type, "playerId": "human", "label": type == "play_land" ? "Play Old-Growth Grove" : "Cast Revitalizing Repast", "cardInstanceId": "modal-\(index)", "sourceZone": "hand"])
                }
            }
            root["legalActions"] = actions
        }
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
            actions.append(["id": "cast-preview-commander", "type": "cast_spell", "playerId": "human", "label": "Cast commander", "cardInstanceId": "human-command-1", "cardName": "Isamaru, Hound of Konda", "sourceZone": "command"])
            root["legalActions"] = actions
            for key in ["exileZones", "revealed", "lookedAt", "companion"] {
                xmage[key] = [["id": "preview-\(key)", "name": "Development \(key)", "cards": [card("preview-\(key)-card", "Forest", "Basic Land — Forest", "", "{T}: Add {G}.")]]]
            }
        }
        root["xmage"] = xmage
        if state == .abilityChoice {
            let source = card("human-sol-ring", "Sol Ring", "Artifact", "{1}", "{T}: Add {C}{C}.")
            root["legalActions"] = []
            root["promptEnvelopeV2"] = ["id": "preview-ability", "method": "PICK_ABILITY", "messageId": 12,
                "playerId": "human", "responseKind": "ability", "message": "Choose which triggered ability goes on the stack first",
                "required": true, "minChoices": 1, "maxChoices": 1,
                "abilities": [
                    ["id": "11111111-1111-4111-8111-111111111111", "label": "Add {C}{C}.", "sourceName": "Sol Ring", "sourceCard": source],
                    ["id": "22222222-2222-4222-8222-222222222222", "label": "Add {C}{C}.", "sourceName": "Sol Ring", "sourceCard": source]],
                "responseCommand": ["type": "choose_ability", "promptId": "preview-ability", "messageId": 12]]
        }
        if state == .searchSelectPrompt, var prompt = root["promptEnvelopeV2"] as? [String: Any] {
            let types = ["Angel", "Artifact Creature", "Bear", "Beast", "Bird", "Cat", "Cleric", "Dragon",
                         "Druid", "Elemental", "Elf", "Faerie", "Giant", "Goblin", "Human", "Knight",
                         "Merfolk", "Pirate", "Rogue", "Soldier", "Spirit", "Vampire", "Warrior", "Wizard", "Zombie"]
            prompt["id"] = "preview-creature-types"
            prompt["message"] = "Development choice fixture: choose a creature type"
            prompt["responseKind"] = "choice"
            prompt["cards"] = []
            prompt["choices"] = types.map { ["id": $0.lowercased().replacingOccurrences(of: " ", with: "-"), "label": $0] }
            prompt["responseCommand"] = ["type": "resolve_choice", "promptId": "preview-creature-types", "messageId": 2]
            root["promptEnvelopeV2"] = prompt
        }
        if [.scryChoice, .libraryChoice, .emptyLibraryChoice, .mixedCardChoice].contains(state) {
            let count = state == .scryChoice ? 3 : (state == .mixedCardChoice ? 2 : 12)
            let options = (0..<count).map { index -> [String: Any] in
                var value = card("choice-\(index)", index.isMultiple(of: 2) ? "Forest" : "Serra Angel",
                                 index.isMultiple(of: 2) ? "Basic Land" : "Creature", "",
                                 index == 0 ? "Development choice fixture: graveyard keyword." : "Development choice fixture.")
                value["selectable"] = state != .emptyLibraryChoice && (state == .scryChoice || index.isMultiple(of: 2))
                return value
            }
            root["promptEnvelopeV2"] = ["id": "preview-card-choice", "method": "GAME_PICK_TARGET", "messageId": 10,
                "playerId": "human", "responseKind": "target", "message": state == .scryChoice ? "Select up to two cards to put on the bottom of your library (Scry)" : "Search your library for a land card",
                "required": false, "minChoices": 1, "maxChoices": 1, "cards": options, "targets": [],
                "options": state == .scryChoice ? ["chosenTargets": []] : [:],
                "targetIds": options.filter { $0["selectable"] as? Bool == true }.map { $0["instanceId"]! },
                "responseCommand": ["type": "choose_target", "promptId": "preview-card-choice", "messageId": 10]]
            root["legalActions"] = [["id": "choice-done", "type": "answer_yes_no", "playerId": "human", "label": "Done",
                                     "promptId": "preview-card-choice", "messageId": 10, "confirmed": false]]
            if state == .mixedCardChoice, var mixed = root["promptEnvelopeV2"] as? [String: Any] {
                mixed["message"] = "Choose a card or a player"
                mixed["targets"] = [["id": "ai-1", "label": "AI 1"]]
                mixed["targetIds"] = ["choice-0", "ai-1"]
                root["promptEnvelopeV2"] = mixed
            }
        }
        if state == .normalBattlefield {
            root["log"] = [
                ["id": "log-1", "message": "TURN 1 for <font color='#20B2AA'>Caleb</font> (40 - 40)", "createdAt": "preview"],
                ["id": "log-2", "message": "<font color='#20B2AA'>Caleb</font> plays <font color='#B0C4DE' object_id='36fc54d7-1afc-4506-92f8-a4f8cceace1c'>Temple of Plenty</font> [36f]", "createdAt": "preview"]
            ]
        }
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
            {"id":"preview-stack","method":"GAME_SELECT","messageId":3,"playerId":"human","responseKind":"priority","message":"Respond to the spell on the stack.","required":false,"minChoices":0,"maxChoices":0,"responseCommand":{"type":"pass_priority","promptId":"preview-stack","messageId":3}}
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
