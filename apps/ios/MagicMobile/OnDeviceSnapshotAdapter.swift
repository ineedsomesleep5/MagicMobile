import Foundation
import MagicMobileOnDevice

/// Converts only the engine's authenticated, seat-scoped client DTO. Never reconstructs hidden cards.
enum OnDeviceSnapshotAdapter {
    private typealias J = MagicMobileOnDevice.JSONValue

    static func snapshot(_ poll: MatchPoll, expectedSeatID: String, log: [GameLogEntry] = []) throws -> GameSnapshot {
        guard poll.seatID == expectedSeatID, let root = poll.snapshot,
              root["schema"]?.string == "xmage-gameview-v1", let view = root["gameView"],
              let viewer = root["enginePlayerId"]?.string, UUID(uuidString: viewer) != nil,
              view["myPlayerId"]?.string == viewer,
              let rawPlayers = view["players"]?.array, (2...4).contains(rawPlayers.count) else {
            throw EngineError.invalidMessage("Missing or mismatched seat-scoped game view")
        }
        let ids = rawPlayers.compactMap { $0["playerId"]?.string }
        guard ids.count == rawPlayers.count, Set(ids).count == ids.count,
              ids.contains(viewer), ids.allSatisfy({ UUID(uuidString: $0) != nil }) else {
            throw EngineError.invalidMessage("Invalid engine player identities")
        }
        var players: [J] = []
        var enginePlayers: [J] = []
        for player in rawPlayers {
            let id = player["playerId"]!.string!
            guard player["life"]?.integer != nil, player["handCount"]?.integer != nil,
                  player["libraryCount"]?.integer != nil, player["name"]?.string != nil else {
                throw EngineError.invalidMessage("Incomplete player state")
            }
            let hand = id == viewer ? view["myHand"] : root["controlledPlayerViews"]?[id]?["myHand"]
            var zones: [String: J] = [:]
            for zone in ["battlefield", "graveyard", "exile"] {
                let mapped = try cards(player[zone])
                zones[zone] = .array(zone == "battlefield" ? combatCards(mapped, groups: view["combat"]) : mapped)
            }
            zones["command"] = .array(try cards(player["commandList"]))
            zones["hand"] = .array(try cards(hand))
            zones["library"] = .array([])
            zones["stack"] = .array([])
            zones["handCount"] = player["handCount"]
            zones["libraryCount"] = player["libraryCount"]
            let poison = (player["counters"]?.array ?? []).first { $0["name"]?.string?.lowercased() == "poison" }?["count"] ?? .integer(0)
            let commanders: [J] = (root["commanders"]?.object ?? [:]).sorted(by: { $0.key < $1.key }).compactMap { cardID, metadata in
                guard metadata["ownerPlayerId"]?.string == id, var fields = metadata.object else { return nil }
                fields["id"] = .string(cardID)
                let visibleCard = zones.values.compactMap(\.array).flatMap { $0 }.first { $0["instanceId"]?.string == cardID }
                if fields["name"] == nil { fields["name"] = visibleCard?["card"]?["name"] }
                return .object(fields)
            }
            // Partners have independent tax and damage. Never combine them into one HUD value.
            let singleCommander = commanders.count == 1 ? commanders.first : nil
            players.append(.object([
                "playerId": .string(id), "displayName": player["name"]!, "life": player["life"]!,
                "poison": poison, "commanderTax": singleCommander?["commanderTax"] ?? .integer(0),
                "commanderTaxKnown": .bool(singleCommander?["commanderTax"]?.integer != nil),
                "commanderDamage": singleCommander?["damageToPlayers"] ?? .null, "commanders": .array(commanders),
                "manaPool": manaPool(player["manaPool"]), "zones": .object(zones)
            ]))
            var skips: [String: J] = [:]
            for key in ["passedTurn", "passedUntilEndOfTurn", "passedUntilNextMain", "passedUntilStackResolved", "passedAllTurns", "passedUntilEndStepBeforeMyTurn"] {
                skips[key] = player[key] ?? .bool(false)
            }
            enginePlayers.append(.object([
                "playerId": .string(id), "xmagePlayerId": .string(id), "name": player["name"]!,
                "active": player["isActive"] ?? .bool(false), "hasPriority": player["hasPriority"] ?? .bool(false),
                "timerActive": player["timerActive"] ?? .bool(false), "skipState": .object(skips),
                "manaPool": manaPool(player["manaPool"]), "command": zones["command"]!,
                "zones": .object(["battlefield": zones["battlefield"]!, "graveyard": zones["graveyard"]!,
                                  "exile": zones["exile"]!, "sideboard": .array(try cards(player["sideboard"]))])
            ]))
        }
        let stackMap = view["stack"]?.object ?? [:]
        let order = root["stackOrder"]?.array?.compactMap(\.string) ?? (stackMap.count <= 1 ? Array(stackMap.keys) : [])
        guard order.count == stackMap.count, Set(order) == Set(stackMap.keys) else {
            throw EngineError.invalidMessage("The engine did not supply an unambiguous stack order")
        }
        let stack: [J] = try order.map { id in
            let object = stackMap[id]!
            let isSpell = object["mageObjectType"]?.string == "SPELL"
            let source = object["sourceCard"] ?? (isSpell ? object : .null)
            var fields: [String: J] = [
                "id": .string(id), "objectId": .string(id), "objectType": object["mageObjectType"] ?? .null,
                "name": object["displayName"] ?? object["name"] ?? .string("Stack object"),
                "rulesText": .string((object["rules"]?.array ?? []).compactMap(\.string).joined(separator: "\n")),
                "targetIds": object["targets"] ?? .array([]), "paid": object["paid"] ?? .null
            ]
            if source != .null {
                fields["sourceCard"] = try card(source)
                fields["sourceName"] = source["displayName"] ?? source["name"]
                // A spell's stack UUID is not necessarily its physical card UUID.
                if !isSpell { fields["sourceInstanceId"] = source["id"] }
            }
            return .object(fields)
        }
        let combat: [J] = try (view["combat"]?.array ?? []).map { group in
            guard let defender = group["defenderId"]?.string else { throw EngineError.invalidMessage("Missing combat defender") }
            let kind: J = ids.contains(defender) ? .string("player") : .null
            return .object(["defenderId": .string(defender), "defenderName": group["defenderName"] ?? .string(defender),
                            "defenderKind": kind, "blocked": group["isBlocked"] ?? .bool(false),
                            "attackers": .array(combatCards(try cards(group["attackers"]), groups: view["combat"])),
                            "blockers": .array(combatCards(try cards(group["blockers"]), groups: view["combat"]))])
        }
        let exileZones = try namedZones(root["namedExiles"], prefix: "exile")
        let revealed = try namedZones(view["revealed"], prefix: "revealed")
        let companions = try namedZones(view["companion"], prefix: "companion")
        let lookedAt = try disclosedGroups(root["authorizedLookedAt"], prefix: "looked-at")
            + disclosedGroups(root["authorizedOpponentHands"], prefix: "controlled-hand")
        let extraZones: [(String, [J])] = [
            ("exile", exileZones), ("revealed", revealed), ("looked_at", lookedAt), ("companion", companions)
        ].map { name, groups in (name, groups.flatMap { $0["cards"]?.array ?? [] }) }
            + [("stack", stack.compactMap { $0["sourceCard"] })]
        let playability = try playableObjects(view: view, players: players, extraZones: extraZones, prompt: poll.prompt, viewer: viewer)
        let xmage: J = .object([
            "schemaVersion": .integer(1), "gameId": .string(poll.matchID), "bridgeRevision": .integer(poll.revision),
            "xmageCycle": view["gameCycle"] ?? .null, "callbackCoverage": .array([]),
            "players": .array(enginePlayers), "stack": .array(stack), "combat": .array(combat),
            "exileZones": .array(exileZones), "revealed": .array(revealed), "lookedAt": .array(lookedAt), "companion": .array(companions),
            "playableObjects": .array(playability.objects), "panels": .object([
                "stack": .bool(!stack.isEmpty), "command": .bool(true), "graveyard": .bool(true),
                "exile": .bool(true), "revealed": .bool(!revealed.isEmpty), "lookedAt": .bool(!lookedAt.isEmpty), "search": .bool(!lookedAt.isEmpty)
            ])
        ])
        let priority = rawPlayers.first { $0["hasPriority"]?.bool == true }?["playerId"]
        let decodedPlayers: [PlayerGameState] = try decode(.array(players))
        let decodedXmage: XmageMobileSnapshot = try decode(xmage)
        let allCards = decodedPlayers.flatMap { player in
            player.zones.hand + player.zones.battlefield + player.zones.graveyard + player.zones.exile + player.zones.command
        } + decodedXmage.stack.compactMap(\.sourceCard)
            + (decodedXmage.exileZones + decodedXmage.revealed + decodedXmage.lookedAt + decodedXmage.companion).flatMap(\.cards)
        let prompt = poll.prompt.flatMap { $0.submitted ? nil : $0 }
        let presentation = try prompt.map { prompt in
            var attackerID: String?
            if prompt.kind == "SELECT", prompt.payload["selectMode"]?.string == "attackers" {
                guard let active = view["activePlayerId"]?.string, ids.contains(active),
                      active == viewer || (root["controlledPlayerViews"]?[active]?["myPlayerId"]?.string == active
                        && root["controlledPlayerViews"]?[active]?["activePlayerId"]?.string == active) else {
                    throw EngineError.invalidMessage("Missing or unauthorized acting attacker identity")
                }
                // ViewProjector emits this map only for the current, non-nested controller.
                attackerID = active
            }
            return try OnDevicePromptAdapter.presentation(prompt, viewerPlayerID: viewer, cards: allCards,
                                                          players: decodedPlayers, actingAttackerPlayerID: attackerID)
        }
        let cardActions: [LegalAction] = try decode(.array(playability.actions))
        return GameSnapshot(
            id: poll.matchID, source: "xmage-ondevice", activePlayerId: view["activePlayerId"]?.string,
            phase: view["phase"]?.string ?? poll.phase, step: view["step"]?.string,
            turn: Int(view["turn"]?.integer ?? 0), priorityPlayerId: priority?.string,
            waitingOnPlayerId: prompt == nil ? nil : viewer, promptText: presentation?.envelope.message,
            players: decodedPlayers, log: log, legalActions: cardActions + (presentation?.legalActions ?? []),
            choicePrompt: nil, promptEnvelope: nil, promptEnvelopeV2: presentation?.envelope,
            startupOpeningPrompts: nil, xmage: decodedXmage, engineHealth: nil,
            bridgeRevision: Int(poll.revision), xmageCycle: view["gameCycle"]?.integer.map(Int.init),
            pendingStatus: poll.prompt?.submitted == true ? "waiting_for_xmage" : nil,
            manaPayment: presentation?.manaPayment, gameStatus: root["outcome"]?["ended"]?.bool == true ? .completed : .inProgress,
            winnerPlayerIds: root["outcome"]?["winnerPlayerIds"]?.array?.compactMap(\.string),
            endReason: nil, viewerPlayerId: viewer
        )
    }

    /// Combat membership comes only from the public GameView groups, never card-type guesses.
    private static func combatCards(_ cards: [J], groups: J?) -> [J] {
        cards.map { card in
            guard let id = card["instanceId"]?.string, var fields = card.object else { return card }
            var attacking = false
            var blocking: Set<String> = []
            for group in groups?.array ?? [] {
                let attackers = cardValues(group["attackers"]).compactMap { $0["id"]?.string }
                attacking = attacking || attackers.contains(id)
                if cardValues(group["blockers"]).contains(where: { $0["id"]?.string == id }) {
                    blocking.formUnion(attackers)
                }
            }
            fields["isAttacking"] = .bool(attacking)
            fields["blocking"] = .array(blocking.sorted().map(J.string))
            return .object(fields)
        }
    }

    private static func namedZones(_ value: J?, prefix: String) throws -> [J] {
        try (value?.array ?? []).enumerated().map { index, zone in
            .object(["id": zone["id"] ?? .string("\(prefix):\(index)"),
                     "name": zone["name"] ?? .string(prefix.capitalized), "cards": .array(try cards(zone["cards"]))])
        }
    }

    private static func disclosedGroups(_ value: J?, prefix: String) throws -> [J] {
        try (value?.object ?? [:]).sorted(by: { $0.key < $1.key }).map { name, contents in
            .object(["id": .string("\(prefix):\(name)"), "name": .string(name), "cards": .array(try cards(contents))])
        }
    }

    private static func cards(_ value: J?) throws -> [J] {
        try cardValues(value).map(card)
    }

    private static func cardValues(_ value: J?) -> [J] {
        value?.array ?? value?.object?.sorted(by: { $0.key < $1.key }).map(\.value) ?? []
    }

    private static func card(_ value: J) throws -> J {
        guard let id = value["id"]?.string, UUID(uuidString: id) != nil else {
            throw EngineError.invalidMessage("Card view has no engine UUID")
        }
        // Do not consult original, source images, or a catalogue to undo an upstream redaction.
        let hidden = value["hideInfo"]?.bool == true
        let name = hidden ? "Face-down card" : value["displayName"]?.string ?? value["name"]?.string ?? "Card details unavailable"
        let types = hidden ? [] : (value["cardTypes"]?.array ?? []).compactMap(\.string)
        let supers = hidden ? [] : (value["superTypes"]?.array ?? []).compactMap(\.string)
        let subs = hidden ? [] : (value["subTypes"]?.array ?? []).compactMap(\.string)
        var typeLine = (supers + types).map { $0.capitalized }.joined(separator: " ")
        if !subs.isEmpty { typeLine += " — " + subs.map { $0.capitalized }.joined(separator: " ") }
        let rules = hidden ? "" : (value["rules"]?.array ?? []).compactMap(\.string).joined(separator: "\n")
        var result: [String: J] = ["instanceId": .string(id), "card": .object([
            "name": .string(name), "typeLine": .string(typeLine), "oracleText": .string(rules)
        ])]
        for key in ["tapped", "summoningSickness", "damage"] { result[key] = value[key] }
        result["attachedToInstanceId"] = value["attachedTo"]
        result["cardIcons"] = .array((value["cardIcons"]?.array ?? []).map { icon in
            .object(["iconType": icon["cardIconType"] ?? .string(""), "text": icon["text"] ?? .null, "hint": icon["hint"] ?? .null])
        })
        if !hidden {
            if let power = value["power"]?.string, !power.isEmpty { result["reportedPower"] = .string(power) }
            if let toughness = value["toughness"]?.string, !toughness.isEmpty { result["reportedToughness"] = .string(toughness) }
        }
        if let counters = value["counters"]?.array {
            var mapped: [String: J] = [:]
            for counter in counters { if let name = counter["name"]?.string { mapped[name] = counter["count"] } }
            result["counters"] = .object(mapped)
        }
        return .object(result)
    }

    private static func manaPool(_ value: J?) -> J {
        .object(Dictionary(uniqueKeysWithValues: [("W", "white"), ("U", "blue"), ("B", "black"),
                                                 ("R", "red"), ("G", "green"), ("C", "colorless")]
            .map { ($0.0, value?[$0.1] ?? .integer(0)) }))
    }

    private static func playableObjects(view: J, players: [J], extraZones: [(String, [J])], prompt: EnginePrompt?, viewer: String) throws -> (objects: [J], actions: [J]) {
        var objects: [J] = [], actions: [J] = []
        var known: [String: (J, String)] = [:]
        for player in players {
            for (zone, contents) in player["zones"]?.object ?? [:] {
                for card in contents.array ?? [] {
                    if let id = card["instanceId"]?.string { known[id] = (card, zone) }
                }
            }
        }
        for (zone, cards) in extraZones {
            for card in cards {
                if let id = card["instanceId"]?.string, known[id] == nil { known[id] = (card, zone) }
            }
        }
        let categories = [("basicPlayAbilities", "play_land"), ("basicCastAbilities", "cast_spell"),
                          ("basicManaAbilities", "make_mana"), ("other", "activate_ability")]
        for (id, stats) in (view["canPlayObjects"]?["objects"]?.object ?? [:]).sorted(by: { $0.key < $1.key }) {
            guard let (card, zone) = known[id] else { continue }
            var abilities: [J] = [], activeCategories: [J] = []
            for (category, commandType) in categories {
                let rows = stats[category]?.array ?? []
                if !rows.isEmpty { activeCategories.append(.string(category)) }
                for row in rows {
                    guard let abilityID = row["id"]?.string, let label = row["value"]?.string else {
                        throw EngineError.invalidMessage("Incomplete engine playable ability")
                    }
                    abilities.append(.object(["id": .string(abilityID), "label": .string(EngineDisplayText.label(label)), "category": .string(category)]))
                }
                guard !rows.isEmpty, let prompt, !prompt.submitted, prompt.responseTypes.contains("uuid"),
                      (prompt.kind == "SELECT" && prompt.payload["selectMode"]?.string == "priority") ||
                      (["PLAY_MANA", "PLAY_X_MANA"].contains(prompt.kind) && category == "basicManaAbilities") else { continue }
                // Selecting an object lets XMage ask for the exact ability when needed.
                // Never turn an ability label or card type into an invented response UUID.
                actions.append(.object([
                    "id": .string("\(prompt.id):\(category):\(id)"), "type": .string(commandType),
                    "playerId": .string(viewer), "label": .string(EngineDisplayText.label(rows[0]["value"]!.string!)),
                    "cardInstanceId": .string(id), "sourceInstanceId": .string(id), "sourceZone": .string(zone),
                    "cardName": card["card"]?["name"] ?? .string("Card"),
                    "promptId": .string(prompt.id), "messageId": .integer(prompt.revision)
                ]))
            }
            if !abilities.isEmpty {
                objects.append(.object(["sourceInstanceId": .string(id), "sourceZone": .string(zone),
                                        "cardName": card["card"]?["name"] ?? .string("Card"),
                                        "categories": .array(activeCategories), "abilities": .array(abilities)]))
            }
        }
        return (objects, actions)
    }

    private static func decode<T: Decodable>(_ value: J) throws -> T {
        try JSONDecoder().decode(T.self, from: value.encoded())
    }
}
