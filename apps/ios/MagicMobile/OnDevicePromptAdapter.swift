import Foundation
import MagicMobileOnDevice

struct OnDevicePromptPresentation {
    let envelope: PromptEnvelopeV2
    let legalActions: [LegalAction]
    let manaPayment: ManaPayment?
}

enum OnDevicePromptAdapter {
    static func presentation(_ prompt: MagicMobileOnDevice.EnginePrompt, viewerPlayerID: String, cards: [ZoneCard], players: [PlayerGameState] = [], actingAttackerPlayerID: String? = nil) throws -> OnDevicePromptPresentation {
        try validate(prompt, viewer: viewerPlayerID)
        let revision = Int(prompt.revision)
        var fields: [String: Any] = [
            "id": prompt.id, "method": "GAME_\(prompt.kind)", "messageId": revision, "playerId": viewerPlayerID,
            "responseKind": "unsupported", "message": EngineDisplayText.text(prompt.payload["message"]?.string ?? ""),
            "required": prompt.payload["required"]?.bool ?? true
        ]
        var actions: [LegalAction] = []
        var payment: ManaPayment?
        fields["options"] = try prompt.payload["options"].map { try JSONSerialization.jsonObject(with: $0.encoded()) }
        func response(_ type: String) -> [String: Any] { ["type": type, "promptId": prompt.id, "messageId": revision] }
        func action(_ type: String, _ label: String, _ extras: [String: Any] = [:]) throws -> LegalAction {
            var value: [String: Any] = ["id": "\(prompt.id):\(type)", "type": type, "label": EngineDisplayText.label(label), "playerId": viewerPlayerID, "promptId": prompt.id, "messageId": revision]
            value.merge(extras) { _, value in value }
            return try decode(value)
        }
        func targetLabel(_ id: String) -> String {
            if id == viewerPlayerID { return "You" }
            return EngineDisplayText.label(players.first(where: { $0.playerId == id })?.displayName
                ?? cards.first(where: { $0.id == id })?.card.name
                ?? id)
        }
        switch prompt.kind {
        case "ASK":
            guard prompt.responseTypes.contains("boolean") else { throw invalid("ASK requires boolean responses") }
            let command = response("answer_yes_no")
            var yes = command; yes["confirmed"] = true
            var no = command; no["confirmed"] = false
            fields["responseKind"] = "confirmation"; fields["responseCommand"] = command
            fields["confirmation"] = [
                "yesLabel": plainLabel(prompt.payload["options"]?["UI.left.btn.text"]?.string, fallback: "Yes"),
                "noLabel": plainLabel(prompt.payload["options"]?["UI.right.btn.text"]?.string, fallback: "No"),
                "yesCommand": yes, "noCommand": no
            ]
        case "SELECT":
            switch prompt.payload["selectMode"]?.string {
            case "priority":
                fields["responseKind"] = "priority"; fields["responseCommand"] = response("pass_priority")
                if prompt.responseTypes.contains("boolean") { actions.append(try action("pass_priority", "Pass priority")) }
            case "attackers", "blockers":
                let key = prompt.payload["selectMode"]?.string == "attackers" ? "possibleAttackers" : "possibleBlockers"
                guard prompt.responseTypes.contains("uuid"), let candidates = prompt.payload["options"]?[key]?.array else { throw invalid("Missing combat candidates") }
                fields["responseKind"] = "target"; fields["responseCommand"] = response("choose_target")
                fields["minChoices"] = 1; fields["maxChoices"] = 1
                var targets = try candidates.map { item -> [String: String] in
                    guard let id = item.string, UUID(uuidString: id) != nil else { throw invalid("Invalid combat UUID") }
                    return ["id": id, "label": targetLabel(id)]
                }
                // Upstream removes declared attackers from its possible-attacker highlights.
                // The snapshot adapter authorizes a controlled acting player separately;
                // command identity remains the authenticated viewer throughout.
                if key == "possibleAttackers", let actingAttackerPlayerID {
                    guard UUID(uuidString: actingAttackerPlayerID) != nil,
                          players.contains(where: { $0.playerId == actingAttackerPlayerID }) else { throw invalid("Invalid acting attacker identity") }
                }
                let attackerID = actingAttackerPlayerID ?? viewerPlayerID
                let battlefield = key == "possibleAttackers" ? players.first { $0.playerId == attackerID }?.zones.battlefield ?? [] : []
                for card in battlefield where card.isAttacking == true {
                    guard UUID(uuidString: card.id) != nil else { throw invalid("Invalid combat UUID") }
                    if !targets.contains(where: { $0["id"] == card.id }) {
                        targets.append(["id": card.id, "label": EngineDisplayText.label(card.card.name)])
                    }
                }
                fields["targets"] = targets
                if prompt.responseTypes.contains("boolean") { actions.append(try action("answer_yes_no", "Done", ["confirmed": true])) }
            default: throw invalid("Unsupported SELECT mode")
            }
            if prompt.responseTypes.contains("string"), let label = prompt.payload["options"]?["specialButton"]?.string {
                actions.append(try action("resolve_choice", label, ["choiceIds": ["special"]]))
            }
        case "PLAY_MANA", "PLAY_X_MANA":
            guard prompt.responseTypes.contains("mana"), let player = prompt.payload["manaPlayerId"]?.string, UUID(uuidString: player) != nil else { throw invalid("Missing mana player UUID") }
            fields["responseKind"] = prompt.kind == "PLAY_MANA" ? "mana" : "x_mana"
            fields["responseCommand"] = response(prompt.kind == "PLAY_MANA" ? "play_mana" : "play_x_mana")
            if prompt.kind == "PLAY_X_MANA" { fields["minChoices"] = prompt.minimum; fields["maxChoices"] = prompt.maximum }
            if let pool = players.first(where: { $0.playerId == player })?.manaPool {
                fields["manaChoices"] = [("W", pool.W), ("U", pool.U), ("B", pool.B), ("R", pool.R), ("G", pool.G), ("C", pool.C)]
                    .filter { $0.1 > 0 }.map { symbol, amount -> [String: Any] in
                        ["id": symbol, "manaType": symbol, "label": "Pay {\(symbol)}", "amount": amount]
                    }
            }
            payment = try decode(["active": true, "remainingText": EngineDisplayText.text(prompt.payload["message"]?.string ?? "")])
            if prompt.responseTypes.contains("boolean") { actions.append(try action("cancel_payment", "Cancel", ["confirmed": false])) }
            if prompt.kind == "PLAY_MANA", prompt.responseTypes.contains("string") {
                // The pinned PLAY_MANA protocol publishes exactly the string "special".
                // HumanPlayer sends empty options even when convoke/delve are available;
                // XMage opens its own special-action chooser after this response.
                actions.append(try action("resolve_choice", prompt.payload["options"]?["specialButton"]?.string ?? "Special payment", ["choiceIds": ["special"]]))
            }
        case "MULTI_AMOUNT":
            guard prompt.responseTypes.contains("integers"), let rows = prompt.payload["allocations"]?.array else { throw invalid("Missing allocation rows") }
            fields["method"] = "GAME_GET_MULTI_AMOUNT"; fields["responseKind"] = "multi_amount"; fields["responseCommand"] = response("choose_multi_amount")
            fields["totalMin"] = prompt.minimum; fields["totalMax"] = prompt.maximum
            fields["multiAmounts"] = try rows.enumerated().map { index, row -> [String: Any] in
                guard let min = row["min"]?.integer, let max = row["max"]?.integer, min <= max,
                      let label = row["message"]?.string else { throw invalid("Malformed allocation row") }
                var value: [String: Any] = ["id": String(index), "label": EngineDisplayText.label(label), "min": min, "max": max]
                if let initial = row["defaultValue"]?.integer { value["defaultValue"] = initial }
                return value
            }
            if prompt.responseTypes.contains("boolean"), prompt.payload["options"]?["canCancel"]?.bool == true {
                actions.append(try action("answer_yes_no", "Cancel", ["confirmed": false]))
            }
        case "AMOUNT":
            guard prompt.responseTypes.contains("integer") else { throw invalid("Amount requires integer responses") }
            fields["method"] = "GAME_GET_AMOUNT"; fields["responseKind"] = "amount"; fields["responseCommand"] = response("choose_amount")
            fields["minChoices"] = prompt.minimum; fields["maxChoices"] = prompt.maximum
            guard prompt.minimum <= prompt.maximum, Int32(exactly: prompt.minimum) != nil, Int32(exactly: prompt.maximum) != nil else { throw invalid("Invalid amount bounds") }
            // Narrow ranges use quick buttons; wider ranges retain the authoritative
            // bounds for the existing manual amount UI, including signed values.
            if prompt.maximum - prompt.minimum < 64 {
                fields["amounts"] = Array(Int(prompt.minimum)...Int(prompt.maximum))
            }
        case "CHOOSE_PILE":
            guard prompt.responseTypes.contains("boolean"), let one = prompt.payload["pile1"]?.array, let two = prompt.payload["pile2"]?.array else { throw invalid("Missing boolean pile choices") }
            fields["responseKind"] = "pile"; fields["responseCommand"] = response("choose_pile")
            fields["piles"] = try [one, two].enumerated().map { index, pile -> [String: Any] in
                ["id": String(index + 1), "label": "Pile \(index + 1)", "cards": try pile.map(promptCard)]
            }
        case "CHOOSE_ABILITY", "PICK_ABILITY":
            guard prompt.responseTypes.contains("uuid"), let abilities = prompt.payload["abilities"]?.array else { throw invalid("Missing UUID ability choices") }
            fields["responseKind"] = "ability"; fields["responseCommand"] = response("choose_ability")
            fields["minChoices"] = 1; fields["maxChoices"] = 1
            fields["abilities"] = try abilities.map { item -> [String: String] in
                guard let id = item["id"]?.string, UUID(uuidString: id) != nil, let label = item["label"]?.string else { throw invalid("Malformed ability choice") }
                return ["id": id, "label": EngineDisplayText.label(label)]
            }
            if prompt.responseTypes.contains("boolean"), prompt.payload["required"]?.bool == false {
                actions.append(try action("answer_yes_no", "Cancel", ["confirmed": false]))
            }
        case "CHOOSE_CHOICE":
            guard prompt.responseTypes.contains("string") else { throw invalid("Choice requires string responses") }
            if prompt.payload["specialEnabled"]?.bool == true, prompt.payload["specialCanBeEmpty"]?.bool == true {
                actions.append(try action("choose_empty_special", plainLabel(prompt.payload["specialText"]?.string, fallback: "Choose no item")))
            }
            fields["responseKind"] = "choice"; fields["responseCommand"] = response("resolve_choice")
            fields["minChoices"] = 1; fields["maxChoices"] = 1
            var rows = try choices(prompt)
            if prompt.payload["specialEnabled"]?.bool == true {
                for row in rows {
                    let key = "#" + row["id"]!
                    if let label = prompt.payload["specialChoices"]?[key]?.string {
                        rows.append(["id": key, "label": EngineDisplayText.label("\(prompt.payload["specialText"]?.string ?? "Special"): \(label)")])
                    }
                }
            }
            if prompt.payload["required"]?.bool == false { rows.append(["id": "", "label": "Cancel"]) }
            // Preserve engine hints, sorting, and exact choice metadata for callers.
            fields["options"] = try JSONSerialization.jsonObject(with: prompt.payload.encoded())
            fields["choices"] = rows
        case "CHOOSE_MODE":
            guard prompt.responseTypes.contains("uuid") else { throw invalid("Mode requires UUID responses") }
            fields["responseKind"] = "mode"; fields["responseCommand"] = response("choose_mode")
            fields["minChoices"] = 1; fields["maxChoices"] = 1
            fields["modes"] = try choices(prompt)
        case "PICK_TARGET":
            guard prompt.responseTypes.contains("uuid") else { throw invalid("Target requires UUID responses") }
            let candidates = try selectableTargetIDs(prompt)
            fields["responseKind"] = "target"; fields["responseCommand"] = response("choose_target")
            fields["minChoices"] = 1; fields["maxChoices"] = 1
            fields["targetIds"] = candidates
            fields["targets"] = candidates.map { id in ["id": id, "label": targetLabel(id)] }
            // QueryEncoder explicitly serializes CardViews in payload.cards and in
            // options.orderedViews. Do not turn the viewer's other zone cards into choices.
            let suppliedCards = ((prompt.payload["options"]?["orderedViews"]?.array ?? []) + (prompt.payload["cards"]?.array ?? [])).flatMap { card in
                // The candidate/responseAliases filter below still governs face IDs.
                card["hideInfo"]?.bool != true && card["secondCardFace"]?.object != nil ? [card, card["secondCardFace"]!] : [card]
            }
            var seen: Set<String> = []
            var mapped = try suppliedCards.filter {
                guard let id = $0["id"]?.string else { return false }
                return seen.insert(id).inserted
            }.map { value -> [String: Any] in
                var card = try promptCard(value)
                let legal = candidates.contains(value["id"]!.string!)
                card["selectable"] = legal
                if !legal { card["disabledReason"] = "Not a legal choice" }
                return card
            }
            // A query may supply only IDs (e.g. graveyard/hand selections). Recover
            // only matching cards from the current authenticated view, never a deck
            // list or a cached lookup. Battlefield targets remain direct board taps.
            let boardIDs = Set(players.flatMap { $0.zones.battlefield }.map(\.id))
            for card in cards where candidates.contains(card.id) && !boardIDs.contains(card.id) && seen.insert(card.id).inserted {
                var identity: [String: Any] = ["name": card.card.name, "typeLine": card.card.typeLine]
                identity["oracleText"] = card.card.oracleText
                mapped.append(["instanceId": card.id, "card": identity, "selectable": true])
            }
            fields["cards"] = mapped
            let shownIDs = Set(mapped.compactMap { $0["instanceId"] as? String })
            fields["targets"] = candidates.filter { !shownIDs.contains($0) }.map { id in
                ["id": id, "label": targetLabel(id)]
            }
            if prompt.responseTypes.contains("boolean"), prompt.payload["required"]?.bool == false {
                actions.append(try action("answer_yes_no", prompt.payload["options"]?["UI.right.btn.text"]?.string ?? "Done", ["confirmed": false]))
            }
        default: throw invalid("Unsupported prompt: \(prompt.kind)")
        }
        return OnDevicePromptPresentation(envelope: try decode(fields), legalActions: actions, manaPayment: payment)
    }

    static func answer(for command: GameCommand, prompt: MagicMobileOnDevice.EnginePrompt, viewerPlayerID: String) throws -> MagicMobileOnDevice.JSONValue {
        try validate(prompt, viewer: viewerPlayerID)
        // messageId carries this prompt's revision, never the aggregate poll revision.
        guard command.playerId == viewerPlayerID, command.promptId == prompt.id,
              command.messageId == Int(exactly: prompt.revision) else { throw invalid("Stale prompt or mismatched viewer") }
        switch (prompt.kind, command.type) {
        case ("SELECT", "choose_amount"):
            guard ["priority", "attackers", "blockers"].contains(prompt.payload["selectMode"]?.string ?? ""), let value = command.amount else { throw invalid("Missing SELECT integer response") }
            try checkAmount(value, min: prompt.minimum, max: prompt.maximum)
            return try answer("integer", .integer(Int64(value)), prompt: prompt)
        case ("SELECT", "choose_target"):
            guard ["attackers", "blockers"].contains(prompt.payload["selectMode"]?.string ?? "") else { throw invalid("Not a combat selection") }
            let id = try single(command.targetIds)
            // Combat metadata is a highlight list. XMage also accepts UUIDs to deselect.
            guard UUID(uuidString: id) != nil else { throw invalid("Invalid combat UUID") }
            return try answer("uuid", .string(id), prompt: prompt)
        case ("SELECT", "answer_yes_no"):
            guard ["attackers", "blockers"].contains(prompt.payload["selectMode"]?.string ?? ""), command.confirmed == true else { throw invalid("Expected combat completion") }
            return try answer("boolean", .bool(true), prompt: prompt)
        case ("PLAY_MANA", "play_mana"), ("PLAY_X_MANA", "play_mana"), ("SELECT", "play_mana"):
            guard let symbol = command.manaType,
                  let color = ["W": "WHITE", "U": "BLUE", "B": "BLACK", "R": "RED", "G": "GREEN", "C": "COLORLESS"][symbol],
                  let player = prompt.payload["manaPlayerId"]?.string, UUID(uuidString: player) != nil else { throw invalid("Invalid mana symbol or missing player identity") }
            return try answer("mana", .object(["playerId": .string(player), "manaType": .string(color)]), prompt: prompt)
        case ("PLAY_X_MANA", "play_x_mana"):
            guard let value = command.amount else { throw invalid("Missing X amount") }
            try checkAmount(value, min: prompt.minimum, max: prompt.maximum)
            return try answer("integer", .integer(Int64(value)), prompt: prompt)
        case ("PLAY_MANA", "cancel_payment"), ("PLAY_X_MANA", "cancel_payment"):
            guard command.confirmed != true else { throw invalid("Payment cancellation cannot confirm payment") }
            return try answer("boolean", .bool(false), prompt: prompt)
        case ("PLAY_MANA", "answer_yes_no"), ("PLAY_X_MANA", "answer_yes_no"):
            guard command.confirmed == false else { throw invalid("Expected mana cancellation") }
            return try answer("boolean", .bool(false), prompt: prompt)
        case ("PLAY_MANA", "activate_ability"), ("PLAY_X_MANA", "activate_ability"), ("PLAY_MANA", "make_mana"), ("PLAY_X_MANA", "make_mana"):
            guard let id = command.sourceInstanceId ?? command.cardInstanceId, UUID(uuidString: id) != nil else { throw invalid("Missing mana source UUID") }
            return try answer("uuid", .string(id), prompt: prompt)
        case ("MULTI_AMOUNT", "choose_multi_amount"):
            guard let values = command.amounts, let rows = prompt.payload["allocations"]?.array, values.count == rows.count else { throw invalid("Allocation count mismatch") }
            var sum: Int64 = 0
            for (value, row) in zip(values, rows) {
                guard let min = row["min"]?.integer, let max = row["max"]?.integer else { throw invalid("Malformed allocation bounds") }
                try checkAmount(value, min: min, max: max)
                let (total, overflow) = sum.addingReportingOverflow(Int64(value))
                guard !overflow else { throw invalid("Allocation overflow") }; sum = total
            }
            guard sum >= prompt.minimum, sum <= prompt.maximum else { throw invalid("Allocation total out of bounds") }
            return try answer("integers", .array(values.map { .integer(Int64($0)) }), prompt: prompt)
        case ("MULTI_AMOUNT", "answer_yes_no"):
            guard command.confirmed == false, prompt.payload["options"]?["canCancel"]?.bool == true else { throw invalid("Allocation cannot be cancelled") }
            return try answer("boolean", .bool(false), prompt: prompt)
        case ("AMOUNT", "choose_amount"):
            guard let amount = command.amount else { throw invalid("Missing amount") }
            try checkAmount(amount, min: prompt.minimum, max: prompt.maximum)
            return try answer("integer", .integer(Int64(amount)), prompt: prompt)
        case ("CHOOSE_PILE", "choose_pile"):
            guard let pile = command.pile, [1, 2].contains(pile) else { throw invalid("Pile must be 1 or 2") }
            // HumanPlayer.choosePile / DoOrDie: true selects pile1, false selects pile2.
            return try answer("boolean", .bool(pile == 1), prompt: prompt)
        case ("CHOOSE_ABILITY", "choose_ability"), ("PICK_ABILITY", "choose_ability"):
            guard let id = command.abilityId, UUID(uuidString: id) != nil,
                  prompt.payload["abilities"]?.array?.contains(where: { $0["id"]?.string == id }) == true else { throw invalid("Ability is not a candidate") }
            return try answer("uuid", .string(id), prompt: prompt)
        case ("CHOOSE_CHOICE", "choose_empty_special"):
            guard prompt.payload["specialEnabled"]?.bool == true,
                  prompt.payload["specialCanBeEmpty"]?.bool == true, command.choiceIds == nil else { throw invalid("Empty special choice is not available or contains a selected key") }
            return try answer("string", .null, prompt: prompt)
        case ("CHOOSE_CHOICE", "resolve_choice"):
            let key = try single(command.choiceIds)
            let normal = prompt.payload["choices"]?[key]?.string != nil
            let special = prompt.payload["specialEnabled"]?.bool == true && prompt.payload["specialChoices"]?[key]?.string != nil
            guard key.utf8.count <= 8192, normal || special || (key.isEmpty && prompt.payload["required"]?.bool == false) else { throw invalid("Choice is not an exact engine key") }
            return try answer("string", .string(key), prompt: prompt)
        case ("CHOOSE_MODE", "choose_mode"):
            let id = try single(command.modeIds)
            guard UUID(uuidString: id) != nil, prompt.payload["choices"]?[id]?.string != nil else { throw invalid("Mode is not a candidate") }
            return try answer("uuid", .string(id), prompt: prompt)
        case ("PICK_TARGET", "choose_target"), ("PICK_TARGET", "choose_card"), ("PICK_TARGET", "choose_player"), ("PICK_TARGET", "search_select"), ("PICK_TARGET", "order_items"):
            let selections: [String]?
            switch command.type {
            case "choose_target": selections = command.targetIds
            case "choose_card", "search_select": selections = command.cardInstanceIds
            case "choose_player": selections = command.playerIds
            default: selections = command.orderedIds
            }
            let id = try single(selections)
            guard try selectableTargetIDs(prompt).contains(id) else { throw invalid("Target is not a legal choice") }
            return try answer("uuid", .string(id), prompt: prompt)
        case ("PICK_TARGET", "answer_yes_no"), ("CHOOSE_ABILITY", "answer_yes_no"), ("PICK_ABILITY", "answer_yes_no"):
            guard prompt.payload["required"]?.bool == false, command.confirmed == false else { throw invalid("Target choice cannot be cancelled") }
            return try answer("boolean", .bool(false), prompt: prompt)
        case ("ASK", "answer_yes_no"):
            guard let value = command.confirmed else { throw invalid("Missing confirmation") }
            return try answer("boolean", .bool(value), prompt: prompt)
        case ("SELECT", "pass_priority"):
            guard prompt.payload["selectMode"]?.string == "priority" else { throw invalid("Not a priority prompt") }
            return try answer("boolean", .bool(true), prompt: prompt)
        case ("PLAY_MANA", "resolve_choice"):
            guard command.choiceIds == ["special"] else { throw invalid("Invalid special payment token") }
            return try answer("string", .string("special"), prompt: prompt)
        case ("SELECT", "resolve_choice"):
            guard command.choiceIds == ["special"], prompt.payload["options"]?["specialButton"]?.string != nil else { throw invalid("Missing special control") }
            return try answer("string", .string("special"), prompt: prompt)
        case ("SELECT", "cast_spell"), ("SELECT", "play_land"), ("SELECT", "activate_ability"), ("SELECT", "make_mana"):
            guard prompt.payload["selectMode"]?.string == "priority", let id = command.sourceInstanceId ?? command.cardInstanceId, UUID(uuidString: id) != nil else { throw invalid("Missing source UUID") }
            return try answer("uuid", .string(id), prompt: prompt)
        default: throw invalid("Incompatible command \(command.type) for \(prompt.kind)")
        }
    }

    private static func answer(_ kind: String, _ value: MagicMobileOnDevice.JSONValue, prompt: MagicMobileOnDevice.EnginePrompt) throws -> MagicMobileOnDevice.JSONValue {
        guard prompt.responseTypes.contains(kind) else { throw invalid("Response type \(kind) is not accepted") }
        return MagicMobileOnDevice.EnginePrompt.answer(kind, value)
    }

    private static func decode<T: Decodable>(_ fields: [String: Any]) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: fields))
    }

    private static func invalid(_ message: String) -> MagicMobileOnDevice.EngineError { .invalidMessage(message) }

    private static func validate(_ prompt: MagicMobileOnDevice.EnginePrompt, viewer: String) throws {
        guard UUID(uuidString: viewer) != nil else { throw invalid("Viewer must be the engine player UUID") }
        guard !prompt.submitted, !prompt.id.isEmpty, Int(exactly: prompt.revision) != nil else { throw invalid("Prompt is submitted or invalid") }
    }

    private static func single(_ values: [String]?) throws -> String {
        guard let values, values.count == 1, let id = values.first else { throw invalid("Exactly one choice is required per upstream prompt") }
        return id
    }

    private static func targetIDs(_ prompt: MagicMobileOnDevice.EnginePrompt) throws -> [String] {
        guard let values = prompt.payload["candidates"]?.array else { throw invalid("Missing target candidates") }
        var ids = try values.map { value -> String in
            guard let id = value.string, UUID(uuidString: id) != nil else { throw invalid("Invalid target UUID") }
            return id
        }
        for id in (prompt.payload["responseAliases"]?.object ?? [:]).keys.sorted() {
            guard UUID(uuidString: id) != nil else { throw invalid("Invalid target alias") }
            if !ids.contains(id) { ids.append(id) }
        }
        return ids
    }

    /// Transport candidates also include browseable, nonmatching search cards.
    /// HumanPlayer's Cards overload omits possibleTargets when that set is empty.
    private static func selectableTargetIDs(_ prompt: MagicMobileOnDevice.EnginePrompt) throws -> [String] {
        let candidates = try targetIDs(prompt)
        let options = prompt.payload["options"]
        let hasCardSelection = prompt.payload["cards"]?.array?.isEmpty == false && options?["chosenTargets"] != nil
        guard options?["possibleTargets"] != nil || hasCardSelection else { return candidates }
        var legal = Set<String>()
        for key in ["possibleTargets", "chosenTargets"] {
            if let value = options?[key] {
                guard let values = value.array else { throw invalid("Malformed target eligibility") }
                for value in values {
                    guard let id = value.string, UUID(uuidString: id) != nil, candidates.contains(id) else { throw invalid("Invalid selectable target") }
                    legal.insert(id)
                }
            }
        }
        for (alias, base) in prompt.payload["responseAliases"]?.object ?? [:] {
            if let base = base.string, legal.contains(base) { legal.insert(alias) }
        }
        return candidates.filter { legal.contains($0) }
    }

    private static func choices(_ prompt: MagicMobileOnDevice.EnginePrompt) throws -> [[String: String]] {
        guard let values = prompt.payload["choices"]?.object, let order = prompt.payload["choiceOrder"]?.array else { throw invalid("Missing ordered choices") }
        return try order.map { item in
            guard let id = item.string, let label = values[id]?.string else { throw invalid("Invalid choice key or label") }
            return ["id": id, "label": EngineDisplayText.label(label)]
        }
    }

    /// Only CardViews explicitly supplied to this viewer's query enter this mapper.
    private static func promptCard(_ value: MagicMobileOnDevice.JSONValue) throws -> [String: Any] {
        guard let id = value["id"]?.string, UUID(uuidString: id) != nil else { throw invalid("Unrepresentable prompt card") }
        let hidden = value["hideInfo"]?.bool == true
        let name = hidden ? "Face-down card" : value["displayName"]?.string ?? value["name"]?.string ?? "Card details unavailable"
        let types = hidden ? [] : value["cardTypes"]?.array?.compactMap(\.string) ?? []
        var card: [String: Any] = ["name": EngineDisplayText.label(name), "typeLine": types.joined(separator: " ")]
        if !hidden, let rules = value["rules"]?.array?.compactMap(\.string) { card["oracleText"] = EngineDisplayText.text(rules.joined(separator: "\n")) }
        return ["instanceId": id, "card": card]
    }

    private static func checkAmount(_ value: Int, min: Int64, max: Int64) throws {
        guard Int32(exactly: value) != nil, Int64(value) >= min, Int64(value) <= max else { throw invalid("Amount out of engine bounds") }
    }

    /// Plain display text only. Never render markup or alter the response tokens.
    private static func plainLabel(_ value: String?, fallback: String) -> String {
        EngineDisplayText.label(value ?? "", fallback: fallback)
    }
}

/// Plain-text presentation only: never use these results as engine IDs or answers.
/// No HTML renderer, network requests, attributed links, or hidden-card lookup.
enum EngineDisplayText {
    static func label(_ source: String, fallback: String = "") -> String {
        let value = text(source).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return value.isEmpty ? fallback : value
    }

    static func phaseLabel(_ source: String) -> String {
        let value = label(source)
        let known = ["PRECOMBAT_MAIN": "Precombat main", "POSTCOMBAT_MAIN": "Postcombat main",
                     "BEGIN_COMBAT": "Beginning of combat", "END_COMBAT": "End of combat",
                     "DECLARE_ATTACKERS": "Declare attackers", "DECLARE_BLOCKERS": "Declare blockers",
                     "FIRST_COMBAT_DAMAGE": "First-strike damage", "COMBAT_DAMAGE": "Combat damage",
                     "END_TURN": "End step", "CLEANUP": "Cleanup", "UNTAP": "Untap",
                     "UPKEEP": "Upkeep", "DRAW": "Draw", "BEGINNING": "Beginning", "COMBAT": "Combat",
                     "ENDING": "Ending"]
        if let name = known[value] { return name }
        // Preserve already-human text; only reformat enum-style all-caps identifiers.
        guard !value.isEmpty, value == value.uppercased(),
              value.allSatisfy({ $0.isLetter || $0 == "_" || $0.isWhitespace }) else { return value }
        let words = value.replacingOccurrences(of: "_", with: " ").lowercased()
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    static func text(_ source: String) -> String {
        var current = source
        // Decode before parsing and reach a fixed point, including nested entities.
        // This prevents a second display pass from exposing previously encoded markup.
        while true {
            let next = stripMarkup(decodeEntities(current)).components(separatedBy: .newlines)
                .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
                .filter { !$0.isEmpty }.joined(separator: "\n")
            if next == current { return next }
            current = next
        }
    }

    private static func decodeEntities(_ source: String) -> String {
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
                     "ndash": "–", "mdash": "—", "hellip": "…", "lsquo": "‘", "rsquo": "’", "times": "×"]
        let pattern = try! NSRegularExpression(pattern: "&(#(?:[xX][0-9a-fA-F]+|[0-9]+)|[A-Za-z]+);")
        let result = NSMutableString(string: source)
        for match in pattern.matches(in: source, range: NSRange(source.startIndex..., in: source)).reversed() {
            let token = (source as NSString).substring(with: match.range(at: 1))
            var replacement = named[token]
            if token.hasPrefix("#") {
                let hexadecimal = token.lowercased().hasPrefix("#x")
                if let number = UInt32(token.dropFirst(hexadecimal ? 2 : 1), radix: hexadecimal ? 16 : 10),
                   let scalar = UnicodeScalar(number) {
                    // Never introduce control or bidirectional-override characters.
                    replacement = ((number < 32 && ![9, 10, 13].contains(number)) || (127...159).contains(number) || (0x202A...0x202E).contains(number)
                                   || (0x2066...0x2069).contains(number)) ? "" : String(scalar)
                }
            }
            if let replacement { result.replaceCharacters(in: match.range, with: replacement) }
        }
        return result as String
    }

    private static func stripMarkup(_ source: String) -> String {
        let pattern = try! NSRegularExpression(pattern: #"(?s)<!--.*?(?:-->|$)|</?([A-Za-z][A-Za-z0-9:-]*)\b(?:[^<>"']|"[^"]*"|'[^']*')*>"#)
        let blocks: Set<String> = ["br", "p", "div", "li", "ul", "ol", "table", "tr", "td", "hr"]
        let suppressed: Set<String> = ["script", "style", "iframe", "object", "svg", "math", "head", "template"]
        let ns = source as NSString
        var output = "", cursor = 0
        var hidden: [String] = []
        for match in pattern.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            if hidden.isEmpty { output += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)) }
            cursor = NSMaxRange(match.range)
            let tag = ns.substring(with: match.range)
            if tag.hasPrefix("<!--") { continue }
            let name = ns.substring(with: match.range(at: 1)).lowercased()
            let closing = tag.hasPrefix("</")
            if suppressed.contains(name) {
                if closing {
                    if hidden.last == name { hidden.removeLast() }
                } else if !tag.hasSuffix("/>") { hidden.append(name) }
                continue
            }
            guard hidden.isEmpty else { continue }
            if blocks.contains(name) { output += "\n" }
            else if name == "img" { output += imageSymbol(tag) }
            // Inline/unknown tags contribute no attributes or executable markup.
        }
        if hidden.isEmpty { output += ns.substring(from: cursor) }
        return output
    }

    private static func imageSymbol(_ tag: String) -> String {
        // Only an explicit canonical symbol alt is supported. Never infer a label
        // from src, a URL, object_id, title, CSS, or an arbitrary image description.
        let attributes = try! NSRegularExpression(pattern: #"(?i)\s+([a-z][a-z0-9-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#)
        let symbol = #"^\{(?:[0-9]+|[WUBRGCXYZSTQE]|[WUBRGC2]/[WUBRGCP])\}$"#
        let ns = tag as NSString
        let matches = attributes.matches(in: tag, range: NSRange(tag.startIndex..., in: tag))
            .filter { ns.substring(with: $0.range(at: 1)).lowercased() == "alt" }
        guard matches.count == 1, let match = matches.first,
              let range = (2...4).map({ match.range(at: $0) }).first(where: { $0.location != NSNotFound }) else { return "" }
        let value = ns.substring(with: range).uppercased()
        return value.range(of: symbol, options: .regularExpression) != nil ? value : ""
    }
}
