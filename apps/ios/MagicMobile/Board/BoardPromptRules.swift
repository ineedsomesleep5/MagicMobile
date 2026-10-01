import SwiftUI
import PhotosUI
import UIKit

enum UniversalPromptResponseCommandBuilder {
    static func command(
        gameId: String,
        bridgeRevision: Int?,
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
        guard let command = PromptCommandBuilder.command(
            gameId: gameId,
            promptEnvelope: promptEnvelope,
            type: rawType,
            promptId: promptId,
            playerId: playerId,
            ids: ids,
            amount: amount,
            amounts: amounts,
            pile: pile,
            useCommandZone: useCommandZone,
            manaType: manaType,
            pay: pay
        ) else { return nil }
        return withExpectedBridgeRevision(command, expectedBridgeRevision: bridgeRevision)
    }

    private static func withExpectedBridgeRevision(_ command: GameCommand, expectedBridgeRevision: Int?) -> GameCommand {
        guard let expectedBridgeRevision else { return command }
        return GameCommand(
            type: command.type,
            gameId: command.gameId,
            playerId: command.playerId,
            cardInstanceId: command.cardInstanceId,
            sourceInstanceId: command.sourceInstanceId,
            abilityId: command.abilityId,
            promptId: command.promptId,
            messageId: command.messageId,
            choiceIds: command.choiceIds,
            targetIds: command.targetIds,
            cardInstanceIds: command.cardInstanceIds,
            modeIds: command.modeIds,
            sourceInstanceIds: command.sourceInstanceIds,
            paymentId: command.paymentId,
            abilityIdChoice: command.abilityIdChoice,
            pile: command.pile,
            amount: command.amount,
            amounts: command.amounts,
            orderedIds: command.orderedIds,
            useCommandZone: command.useCommandZone,
            manaType: command.manaType,
            manaTypes: command.manaTypes,
            playerIds: command.playerIds,
            confirmed: command.confirmed,
            pay: command.pay,
            sourceZone: command.sourceZone,
            fromZone: command.fromZone,
            cardName: command.cardName,
            attackers: command.attackers,
            blockers: command.blockers,
            combatComplete: command.combatComplete,
            expectedBridgeRevision: expectedBridgeRevision
        )
    }
}

enum PromptSelectionRules {
    static func isValidSelectedCount(_ count: Int, minChoices: Int?, maxChoices: Int?) -> Bool {
        guard let minChoices, let maxChoices else { return false }
        return count >= minChoices && count <= maxChoices
    }

    static func selectedPromptCardId(selectedCard: ZoneCard?, validCards: [ZoneCard]) -> String? {
        guard let selectedCard else { return nil }
        let validIds = Set(validCards.flatMap { [$0.id, $0.instanceId] })
        guard validIds.contains(selectedCard.id) || validIds.contains(selectedCard.instanceId) else {
            return nil
        }
        return selectedCard.instanceId
    }

    static func boundsText(minChoices: Int?, maxChoices: Int?) -> String {
        guard let minChoices, let maxChoices else { return "min/max unavailable" }
        return "min \(minChoices) / max \(maxChoices)"
    }
}

enum TargetingHelperVisibility {
    static func shouldShow(
        snapshot: GameSnapshot,
        pendingActionId: String?,
        mode: GameBoardInteractionMode,
        targetableIds: Set<String>
    ) -> Bool {
        guard case .targeting = mode, !targetableIds.isEmpty else {
            return false
        }
        guard !InlinePaymentPromptState.isActive(in: snapshot) else {
            return false
        }
        // XMage routes the opening player choice through PICK_TARGET, but it is
        // not a battlefield target. The centered choice owns that decision.
        if snapshot.promptEnvelopeV2?.message.localizedLowercase.contains("starting player") == true {
            return false
        }
        guard !CompactPromptPopup.shouldShow(for: snapshot, pendingActionId: pendingActionId) else {
            let promptKind = snapshot.promptEnvelopeV2?.responseKind.lowercased()
            let hasButtonActions = !CompactPromptPopup.compactLegalPromptActions(in: snapshot).isEmpty
            return promptKind == "target" && !hasButtonActions
        }
        return true
    }
}
