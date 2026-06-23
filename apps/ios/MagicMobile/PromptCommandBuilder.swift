import Foundation

enum PromptCommandBuilder {
    static func command(
        gameId: String,
        promptEnvelope: PromptEnvelopeV2?,
        type rawType: String,
        promptId: String,
        playerId: String,
        ids: [String] = [],
        amount: Int? = nil,
        amounts: [Int]? = nil,
        pile: Int? = nil,
        useCommandZone: Bool? = nil,
        manaType: String? = nil,
        pay: Bool? = nil
    ) -> GameCommand? {
        let type = rawType.lowercased()
        let promptMessageId = resolvedMessageId(promptEnvelope: promptEnvelope, promptId: promptId)
        switch type {
        case "resolve_choice":
            return GameCommand(type: type, gameId: gameId, playerId: playerId, promptId: promptId, messageId: promptMessageId, choiceIds: ids)
        case "choose_target":
            return GameCommand(type: type, gameId: gameId, playerId: playerId, promptId: promptId, messageId: promptMessageId, targetIds: ids)
        case "choose_card":
            return GameCommand(type: type, gameId: gameId, playerId: playerId, promptId: promptId, messageId: promptMessageId, cardInstanceIds: ids)
        case "choose_player":
            return GameCommand(type: type, gameId: gameId, playerId: playerId, promptId: promptId, messageId: promptMessageId, playerIds: ids)
        case "choose_mode":
            return GameCommand(type: type, gameId: gameId, playerId: playerId, promptId: promptId, messageId: promptMessageId, modeIds: ids)
        case "choose_ability":
            guard let abilityId = ids.first else { return nil }
            return GameCommand(type: type, gameId: gameId, playerId: playerId, abilityId: abilityId, promptId: promptId, messageId: promptMessageId)
        case "choose_pile":
            guard let pileChoice = pile ?? ids.first.flatMap(Int.init), [1, 2].contains(pileChoice) else { return nil }
            return GameCommand(type: type, gameId: gameId, playerId: playerId, promptId: promptId, messageId: promptMessageId, pile: pileChoice)
        case "choose_amount", "play_x_mana":
            guard let amountChoice = amount ?? ids.first.flatMap(Int.init) else { return nil }
            return GameCommand(type: type, gameId: gameId, playerId: playerId, promptId: promptId, messageId: promptMessageId, amount: amountChoice)
        case "choose_multi_amount":
            let amountChoices = amounts ?? ids.compactMap(Int.init)
            guard !amountChoices.isEmpty, amounts != nil || amountChoices.count == ids.count else { return nil }
            return GameCommand(type: type, gameId: gameId, playerId: playerId, promptId: promptId, messageId: promptMessageId, amounts: amountChoices)
        case "play_mana":
            guard let manaType = exactManaSymbol(manaType) else { return nil }
            return GameCommand(type: type, gameId: gameId, playerId: playerId, promptId: promptId, messageId: promptMessageId, manaType: manaType)
        case "choose_mana":
            let manaChoices = manaType.map { [$0] } ?? ids
            let exactChoices = manaChoices.compactMap(exactManaSymbol)
            guard !exactChoices.isEmpty, exactChoices.count == manaChoices.count else { return nil }
            return GameCommand(type: type, gameId: gameId, playerId: playerId, promptId: promptId, messageId: promptMessageId, manaTypes: exactChoices)
        case "search_select":
            return GameCommand(type: type, gameId: gameId, playerId: playerId, promptId: promptId, messageId: promptMessageId, cardInstanceIds: ids)
        case "order_triggers", "order_items":
            return GameCommand(type: type, gameId: gameId, playerId: playerId, promptId: promptId, messageId: promptMessageId, orderedIds: ids)
        case "commander_replacement":
            guard let useCommandZone else { return nil }
            return GameCommand(type: type, gameId: gameId, playerId: playerId, promptId: promptId, messageId: promptMessageId, useCommandZone: useCommandZone)
        case "pay_cost":
            guard let shouldPay = pay ?? boolChoice(ids.first) else { return nil }
            return GameCommand(type: type, gameId: gameId, playerId: playerId, promptId: promptId, messageId: promptMessageId, confirmed: shouldPay, pay: shouldPay)
        case "answer_yes_no":
            guard let confirmed = boolChoice(ids.first) else { return nil }
            return GameCommand(type: type, gameId: gameId, playerId: playerId, promptId: promptId, messageId: promptMessageId, confirmed: confirmed)
        default:
            return nil
        }
    }

    static func idCommandType(preferred: String?, fallback: String) -> String {
        guard let preferred = preferred?.lowercased() else { return fallback }
        if ["resolve_choice", "choose_target", "choose_card", "choose_player", "choose_mode", "choose_ability", "search_select", "order_triggers", "order_items", "answer_yes_no"].contains(preferred) {
            return preferred
        }
        return fallback
    }

    static func amountCommandType(preferred: String?) -> String {
        guard let preferred = preferred?.lowercased() else { return "choose_amount" }
        return ["choose_amount", "choose_multi_amount", "play_x_mana"].contains(preferred) ? preferred : "choose_amount"
    }

    static func exactManaSymbol(_ value: String?) -> String? {
        guard let value, ["W", "U", "B", "R", "G", "C"].contains(value) else { return nil }
        return value
    }

    static func boolChoice(_ value: String?) -> Bool? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["true", "yes"].contains(normalized) { return true }
        if ["false", "no"].contains(normalized) { return false }
        return nil
    }

    static func canSubmitShownOrder(ids: [String]) -> Bool {
        ids.count == 1
    }

    static func hasPrebuiltCombatPayload(_ action: LegalAction) -> Bool {
        switch action.type {
        case "declare_attackers":
            return action.attackers?.isEmpty == false || jsonArrayHasItems(action.commandTemplate?["attackers"])
        case "declare_blockers":
            return action.blockers?.isEmpty == false || jsonArrayHasItems(action.commandTemplate?["blockers"])
        default:
            return false
        }
    }

    private static func resolvedMessageId(promptEnvelope: PromptEnvelopeV2?, promptId: String) -> Int? {
        guard let prompt = promptEnvelope else { return nil }
        if prompt.id == promptId || prompt.responseCommand?.promptId == promptId {
            return prompt.responseCommand?.messageId ?? prompt.messageId
        }
        return nil
    }

    private static func jsonArrayHasItems(_ value: JSONValue?) -> Bool {
        guard case .array(let values) = value else { return false }
        return !values.isEmpty
    }
}
