import Foundation
import MagicMobileOnDevice

struct OnDevicePromptPresentation {
    let envelope: PromptEnvelopeV2
    let legalActions: [LegalAction]
    let manaPayment: ManaPayment?
}

enum OnDevicePromptAdapter {
    static func presentation(_ prompt: MagicMobileOnDevice.EnginePrompt, viewerPlayerID: String, cards: [ZoneCard], players: [PlayerGameState] = []) throws -> OnDevicePromptPresentation {
        try validate(prompt, viewer: viewerPlayerID)
        let revision = Int(prompt.revision)
        var fields: [String: Any] = [
            "id": prompt.id, "method": "GAME_\(prompt.kind)", "messageId": revision, "playerId": viewerPlayerID,
            "responseKind": "unsupported", "message": prompt.payload["message"]?.string ?? "",
            "required": prompt.payload["required"]?.bool ?? true
        ]
        var actions: [LegalAction] = []
        var payment: ManaPayment?
        fields["options"] = try prompt.payload["options"].map { try JSONSerialization.jsonObject(with: $0.encoded()) }
        func response(_ type: String) -> [String: Any] { ["type": type, "promptId": prompt.id, "messageId": revision] }
        func action(_ type: String, _ label: String, _ extras: [String: Any] = [:]) throws -> LegalAction {
            var value: [String: Any] = ["id": "\(prompt.id):\(type)", "type": type, "label": label, "playerId": viewerPlayerID, "promptId": prompt.id, "messageId": revision]
            value.merge(extras) { _, value in value }
            return try decode(value)
        }
        func targetLabel(_ id: String) -> String {
            if id == viewerPlayerID { return "You" }
            return players.first(where: { $0.playerId == id })?.displayName
                ?? cards.first(where: { $0.id == id })?.card.name
                ?? id
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
                fields["targets"] = try candidates.map { item -> [String: String] in
                    guard let id = item.string, UUID(uuidString: id) != nil else { throw invalid("Invalid combat UUID") }
                    return ["id": id, "label": targetLabel(id)]
                }
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
            payment = try decode(["active": true, "remainingText": prompt.payload["message"]?.string ?? ""])
            if prompt.responseTypes.contains("boolean") { actions.append(try action("cancel_payment", "Cancel", ["confirmed": false])) }
            if prompt.responseTypes.contains("string"), let label = prompt.payload["options"]?["specialButton"]?.string {
                actions.append(try action("resolve_choice", label, ["choiceIds": ["special"]]))
            }
        case "MULTI_AMOUNT":
            guard prompt.responseTypes.contains("integers"), let rows = prompt.payload["allocations"]?.array else { throw invalid("Missing allocation rows") }
            fields["method"] = "GAME_GET_MULTI_AMOUNT"; fields["responseKind"] = "multi_amount"; fields["responseCommand"] = response("choose_multi_amount")
            fields["totalMin"] = prompt.minimum; fields["totalMax"] = prompt.maximum
            fields["multiAmounts"] = try rows.enumerated().map { index, row -> [String: Any] in
                guard let min = row["min"]?.integer, let max = row["max"]?.integer, min <= max,
                      let label = row["message"]?.string else { throw invalid("Malformed allocation row") }
                var value: [String: Any] = ["id": String(index), "label": label, "min": min, "max": max]
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
                return ["id": id, "label": label]
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
                        rows.append(["id": key, "label": "\(prompt.payload["specialText"]?.string ?? "Special"): \(label)"])
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
            let candidates = try targetIDs(prompt)
            fields["responseKind"] = "target"; fields["responseCommand"] = response("choose_target")
            fields["minChoices"] = 1; fields["maxChoices"] = 1
            fields["targetIds"] = candidates
            fields["targets"] = candidates.map { id in ["id": id, "label": targetLabel(id)] }
            // QueryEncoder explicitly serializes CardViews in payload.cards and in
            // options.orderedViews. Do not turn the viewer's other zone cards into choices.
            let suppliedCards = ((prompt.payload["options"]?["orderedViews"]?.array ?? []) + (prompt.payload["cards"]?.array ?? [])).flatMap { card in
                // The candidate/responseAliases filter below still governs face IDs.
                card["secondCardFace"]?.object != nil ? [card, card["secondCardFace"]!] : [card]
            }
            if !suppliedCards.isEmpty {
                var seen: Set<String> = []
                let mapped = try suppliedCards.filter {
                    guard let id = $0["id"]?.string, candidates.contains(id) else { return false }
                    return seen.insert(id).inserted
                }.map(promptCard)
                fields["cards"] = mapped
                let shownIDs = Set(mapped.compactMap { $0["instanceId"] as? String })
                fields["targets"] = candidates.filter { !shownIDs.contains($0) }.map { id in
                    ["id": id, "label": targetLabel(id)]
                }
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
        case ("PLAY_MANA", "activate_ability"), ("PLAY_X_MANA", "activate_ability"):
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
            guard try targetIDs(prompt).contains(id) else { throw invalid("Target is not a candidate") }
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
        case ("SELECT", "resolve_choice"), ("PLAY_MANA", "resolve_choice"):
            guard command.choiceIds == ["special"], prompt.payload["options"]?["specialButton"]?.string != nil else { throw invalid("Missing special control") }
            return try answer("string", .string("special"), prompt: prompt)
        case ("SELECT", "cast_spell"), ("SELECT", "play_land"), ("SELECT", "activate_ability"):
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

    private static func choices(_ prompt: MagicMobileOnDevice.EnginePrompt) throws -> [[String: String]] {
        guard let values = prompt.payload["choices"]?.object, let order = prompt.payload["choiceOrder"]?.array else { throw invalid("Missing ordered choices") }
        return try order.map { item in
            guard let id = item.string, let label = values[id]?.string else { throw invalid("Invalid choice key or label") }
            return ["id": id, "label": label]
        }
    }

    /// Only CardViews explicitly supplied to this viewer's query enter this mapper.
    private static func promptCard(_ value: MagicMobileOnDevice.JSONValue) throws -> [String: Any] {
        guard let id = value["id"]?.string, UUID(uuidString: id) != nil, let name = value["name"]?.string else { throw invalid("Unrepresentable prompt card") }
        let types = value["cardTypes"]?.array?.compactMap(\.string) ?? []
        var card: [String: Any] = ["name": name, "typeLine": types.joined(separator: " ")]
        if let rules = value["rules"]?.array?.compactMap(\.string) { card["oracleText"] = rules.joined(separator: "\n") }
        return ["instanceId": id, "card": card]
    }

    private static func checkAmount(_ value: Int, min: Int64, max: Int64) throws {
        guard Int32(exactly: value) != nil, Int64(value) >= min, Int64(value) <= max else { throw invalid("Amount out of engine bounds") }
    }

    /// Plain display text only. Never render markup or alter the response tokens.
    private static func plainLabel(_ value: String?, fallback: String) -> String {
        guard let value else { return fallback }
        var text = value.replacingOccurrences(of: "(?is)<(script|style)\\b[^>]*>.*?</\\1\\s*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
        let entities = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " "]
        if let pattern = try? NSRegularExpression(pattern: "&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos|nbsp);") {
            let decoded = NSMutableString(string: text)
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                let token = (text as NSString).substring(with: match.range(at: 1))
                let replacement: String?
                if token.hasPrefix("#") {
                    let hexadecimal = token.hasPrefix("#x")
                    let number = UInt32(token.dropFirst(hexadecimal ? 2 : 1), radix: hexadecimal ? 16 : 10)
                    replacement = number.flatMap(UnicodeScalar.init).map(String.init)
                } else { replacement = entities[token] }
                if let replacement { decoded.replaceCharacters(in: match.range, with: replacement) }
            }
            text = decoded as String
        }
        let label = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return label.isEmpty ? fallback : label
    }
}
