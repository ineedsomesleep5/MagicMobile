package io.magicmobile.android.game

/**
 * Ports of the presentation rules inside apps/ios/MagicMobile/ContentView.swift: the compact
 * prompt popup's rules, payment state, prompt guidance, combat selection and arrows, portrait
 * row planning, the hand fan and the action display text. The composables live in the app
 * module under the same names.
 */
object NativeCardArtworkPolicy {
    fun permitsLookup(card: ZoneCard): Boolean =
        permitsLookup(card.card.name) && (card.cardIcons ?: emptyList()).none { it.iconType.uppercase() == "OTHER_FACEDOWN" }
    fun permitsLookup(name: String): Boolean = OnDeviceSnapshotAdapter.permitsSourceName(name)
}

object CompactPromptPopup {
    fun shouldShow(snapshot: GameSnapshot, pendingActionId: String?): Boolean {
        if (InlinePaymentPromptState.isActive(snapshot)) return false
        if (pendingActionId != null) return true
        snapshot.promptEnvelopeV2?.let { prompt ->
            val presentation = MobilePromptPresentation.make(snapshot, snapshot.legalActions ?: emptyList())
            if (presentation?.kind == MobilePromptKind.PAYMENT || isManaPaymentPrompt(prompt)) return false
            if (isPassivePriorityPrompt(prompt, snapshot)) return false
            if (compactLegalPromptActions(snapshot).isNotEmpty()) return true
            if (presentation?.requiresDetail == true || needsDetails(snapshot)) return true
            if (prompt.confirmation != null || PromptCommandBuilder.isCommanderReplacement(prompt)) return true
            if (prompt.choices?.isNotEmpty() == true) return true
            return prompt.required == true && !isPassivePriorityMessage(prompt.message)
        }
        snapshot.choicePrompt?.let { return it.choices.isNotEmpty() || compactLegalPromptActions(snapshot).isNotEmpty() }
        snapshot.promptEnvelope?.let { return it.choices?.isNotEmpty() == true || compactLegalPromptActions(snapshot).isNotEmpty() }
        return false
    }

    fun shouldShowStackPaymentTray(snapshot: GameSnapshot): Boolean {
        // Authoritative: manaPayment.active only while the viewer is paying for a spell or ability.
        if (snapshot.manaPayment?.active == true) return true
        if (!(snapshot.isViewer(snapshot.waitingOnPlayerId) || snapshot.isViewer(snapshot.priorityPlayerId))) return false
        val actions = snapshot.legalActions ?: emptyList()
        if (actions.none { it.type == "make_mana" && (it.sourceInstanceId != null || it.cardInstanceId != null) }) return false
        val allowed = setOf("make_mana", "undo_mana", "cancel_payment", "cancel_mana_payment", "concede")
        if (!actions.all { allowed.contains(it.type) }) return false
        return snapshot.xmage?.stack?.isNotEmpty() == true || snapshot.human?.zones?.stack?.isNotEmpty() == true
    }

    fun syntheticStackPaymentPrompt(snapshot: GameSnapshot): PromptEnvelopeV2 = PromptEnvelopeV2(
        id = "xmage-stack-payment-${snapshot.bridgeRevision ?: snapshot.turn}", method = "GAME_PLAY_MANA", messageId = -1,
        playerId = snapshot.viewerID, responseKind = "mana", message = stackPaymentMessage(snapshot), required = false)

    private fun stackPaymentMessage(snapshot: GameSnapshot): String {
        snapshot.xmage?.stack?.firstOrNull()?.let { return "Tap mana for ${it.displayName}" }
        snapshot.human?.zones?.stack?.firstOrNull()?.let { return "Tap mana for ${it.card.name}" }
        return "Tap mana for the spell"
    }

    fun needsDetails(snapshot: GameSnapshot): Boolean {
        val prompt = snapshot.promptEnvelopeV2
        if (snapshot.source == "xmage-ondevice" && prompt != null) {
            if (prompt.cards?.isNotEmpty() == true || prompt.targets?.isNotEmpty() == true || prompt.players?.isNotEmpty() == true) return true
            if (prompt.piles?.isNotEmpty() == true || prompt.abilities?.isNotEmpty() == true || prompt.modes?.isNotEmpty() == true) return true
            if (prompt.amounts?.isNotEmpty() == true || prompt.multiAmounts?.isNotEmpty() == true || prompt.orderedItems?.isNotEmpty() == true) return true
            if ((prompt.choices?.size ?: 0) > 3 || prompt.responseCommand?.type == "choose_amount") return true
        }
        if (compactLegalPromptActions(snapshot).isNotEmpty()) return false
        MobilePromptPresentation.make(snapshot, snapshot.legalActions ?: emptyList())?.let { return it.requiresDetail }
        prompt ?: return false
        if (prompt.cards?.isNotEmpty() == true || prompt.targets?.isNotEmpty() == true || prompt.players?.isNotEmpty() == true) return true
        if (prompt.piles?.isNotEmpty() == true || prompt.abilities?.isNotEmpty() == true || prompt.modes?.isNotEmpty() == true) return true
        if (prompt.amounts?.isNotEmpty() == true || prompt.multiAmounts?.isNotEmpty() == true || prompt.orderedItems?.isNotEmpty() == true) return true
        return (prompt.choices?.size ?: 0) > 3
    }

    fun compactLegalPromptActions(snapshot: GameSnapshot): List<LegalAction> {
        val legalActions = snapshot.legalActions ?: emptyList()
        val v2 = snapshot.promptEnvelopeV2
        val promptId = v2?.responseCommand?.promptId ?: v2?.id ?: snapshot.promptEnvelope?.id ?: snapshot.choicePrompt?.id
        val responseType = v2?.responseCommand?.type?.lowercase()
        val responseKind = v2?.responseKind?.lowercase() ?: snapshot.promptEnvelope?.responseKind?.lowercase()
        val message = (v2?.message ?: snapshot.promptEnvelope?.message ?: snapshot.choicePrompt?.message ?: snapshot.promptText ?: "").lowercase()
        val allowed = mutableSetOf("resolve_choice", "answer_yes_no", "pay_cost", "commander_replacement")
        if (message.contains("mulligan")) allowed += setOf("keep_hand", "mulligan")
        if (message.contains("starting player") || message.contains("starts") || responseKind == "player") allowed += "choose_player"
        if (responseType == "resolve_choice" || responseKind == "choice") allowed += "resolve_choice"
        return PortraitInteractionPolicy.dockActions(legalActions).filter { action ->
            if (action.type == "concede") return@filter false
            // The card-backed picker owns ability choices; do not repeat them as compact text.
            if (snapshot.source == "xmage-ondevice" && v2?.abilities?.isNotEmpty() == true && action.type == "choose_ability") return@filter false
            if (promptId != null && action.promptId == promptId) return@filter true
            if (responseType != null && action.type == responseType) return@filter true
            allowed.contains(action.type)
        }.sortedBy(::compactActionPriority)
    }

    fun shouldPreferCompactActionsBeforeRawChoices(snapshot: GameSnapshot): Boolean {
        if (compactLegalPromptActions(snapshot).none { it.type == "choose_player" }) return false
        val v2 = snapshot.promptEnvelopeV2
        val responseType = v2?.responseCommand?.type?.lowercase()
        val responseKind = v2?.responseKind?.lowercase() ?: snapshot.promptEnvelope?.responseKind?.lowercase()
        val message = (v2?.message ?: snapshot.promptEnvelope?.message ?: snapshot.choicePrompt?.message ?: snapshot.promptText ?: "").lowercase()
        return responseType == "choose_player" || responseKind == "player" || message.contains("starting player")
    }

    fun supplementalChoiceActions(snapshot: GameSnapshot): List<LegalAction> {
        val prompt = snapshot.promptEnvelopeV2 ?: return emptyList()
        val choices = prompt.choices
        if (snapshot.source != "xmage-ondevice" || choices.isNullOrEmpty() || choices.size > 3) return emptyList()
        val choiceIDs = choices.map { it.id }.toSet()
        return compactLegalPromptActions(snapshot).filter { action ->
            if (action.promptId != (prompt.responseCommand?.promptId ?: prompt.id) ||
                action.messageId != (prompt.responseCommand?.messageId ?: prompt.messageId) || action.playerId != prompt.playerId) return@filter false
            !(action.type == "resolve_choice" && action.choiceIds?.size == 1 && choiceIDs.contains(action.choiceIds.first()))
        }
    }

    fun isManaPaymentPrompt(prompt: PromptEnvelopeV2): Boolean {
        val type = prompt.responseCommand?.type?.lowercase() ?: ""
        val kind = prompt.responseKind.lowercase()
        return type in setOf("play_mana", "choose_mana", "pay_cost", "play_x_mana") || kind in setOf("mana", "pay_cost", "cost", "x_mana") ||
            prompt.method == "GAME_PLAY_MANA" || prompt.method == "GAME_PLAY_XMANA"
    }

    fun isConfirmationPrompt(prompt: PromptEnvelopeV2): Boolean =
        prompt.responseCommand?.type?.lowercase() == "answer_yes_no" || prompt.responseKind.lowercase() == "confirmation"

    fun compactActionLabel(action: LegalAction): String = when (action.type) {
        "keep_hand" -> "Keep"; "mulligan" -> "Mulligan"; else -> action.compactPromptTitle
    }

    fun yesNoIcon(label: String): String? {
        val lower = label.trim().lowercase()
        if (lower in setOf("yes", "ok", "accept", "keep")) return "checkmark.circle"
        if (lower in setOf("no", "cancel", "decline", "mulligan")) return "xmark.circle"
        return null
    }

    private fun compactActionPriority(action: LegalAction): Int {
        if (action.isPrimary == true) return 0
        return when (action.type) {
            "keep_hand" -> 1; "mulligan" -> 2; "choose_player" -> 3; "resolve_choice", "answer_yes_no" -> 4
            "pay_cost", "commander_replacement" -> 5; else -> 8
        }
    }

    private fun isPassivePriorityPrompt(prompt: PromptEnvelopeV2, snapshot: GameSnapshot): Boolean {
        if (prompt.method != "GAME_SELECT") return false
        if (prompt.responseKind == "priority" && prompt.responseCommand?.type == "pass_priority") return true
        val type = prompt.responseCommand?.type?.lowercase() ?: prompt.responseKind.lowercase()
        if (type != "choose_card" && type != "card") return false
        if (prompt.cards?.isNotEmpty() == true || prompt.targets?.isNotEmpty() == true || prompt.players?.isNotEmpty() == true) return false
        if (prompt.choices?.isNotEmpty() == true || prompt.modes?.isNotEmpty() == true || prompt.abilities?.isNotEmpty() == true) return false
        return isPassivePriorityMessage(prompt.message) || isPassivePriorityMessage(snapshot.promptText ?: "")
    }

    fun isPassivePriorityMessage(message: String): Boolean = message.trim().lowercase() in
        setOf("play spells and abilities", "play instants and activated abilities", "play spells or abilities", "select a card")
}

object InlinePaymentPromptState {
    fun isActive(snapshot: GameSnapshot): Boolean = paymentPrompt(snapshot) != null
    fun paymentPrompt(snapshot: GameSnapshot): PromptEnvelopeV2? {
        snapshot.promptEnvelopeV2?.let { if (CompactPromptPopup.isManaPaymentPrompt(it)) return it }
        if (CompactPromptPopup.shouldShowStackPaymentTray(snapshot)) return CompactPromptPopup.syntheticStackPaymentPrompt(snapshot)
        return null
    }
}

object TargetingHelperVisibility {
    fun shouldShow(snapshot: GameSnapshot, pendingActionId: String?, mode: GameBoardInteractionMode, targetableIds: Set<String>): Boolean {
        if (mode !is GameBoardInteractionMode.Targeting || targetableIds.isEmpty()) return false
        if (InlinePaymentPromptState.isActive(snapshot)) return false
        // The opening player choice arrives as PICK_TARGET but is not a battlefield target.
        if (snapshot.promptEnvelopeV2?.message?.lowercase()?.contains("starting player") == true) return false
        if (CompactPromptPopup.shouldShow(snapshot, pendingActionId)) {
            return snapshot.promptEnvelopeV2?.responseKind?.lowercase() == "target" && CompactPromptPopup.compactLegalPromptActions(snapshot).isEmpty()
        }
        return true
    }
}

object GameplayAffordances {
    fun dismissesZone(action: LegalAction): Boolean = action.type == "cast_spell"

    fun commanderCastAvailable(player: PlayerGameState, snapshot: GameSnapshot, pendingActionID: String?): Boolean {
        if (pendingActionID != null || snapshot.human?.playerId != player.playerId) return false
        return player.zones.command.any { card ->
            GameBoardInteractionState.cardActions(card, snapshot.legalActions ?: emptyList()).any { it.type == "cast_spell" && it.playerId == player.playerId }
        }
    }

    fun floatingManaSymbols(snapshot: GameSnapshot, pendingActionID: String?): Set<String> {
        if (pendingActionID != null) return emptySet()
        return listOf("W", "U", "B", "R", "G", "C").filter { floatingManaCommand(it, snapshot) != null }.toSet()
    }

    fun floatingManaCommand(symbol: String, snapshot: GameSnapshot): GameCommand? {
        val human = snapshot.human ?: return null
        val pool = human.manaPool ?: return null
        val prompt = snapshot.promptEnvelopeV2 ?: return null
        if (prompt.playerId != human.playerId || !CompactPromptPopup.isManaPaymentPrompt(prompt)) return null
        val choice = prompt.manaChoices?.firstOrNull { (it.manaType ?: it.id) == symbol } ?: return null
        if (snapshot.source == "xmage-ondevice" && (choice.amount ?: 0) <= 0) return null
        val counts = mapOf("W" to pool.W, "U" to pool.U, "B" to pool.B, "R" to pool.R, "G" to pool.G, "C" to pool.C)
        if ((counts[symbol] ?: 0) <= 0) return null
        return UniversalPromptResponseCommandBuilder.command(snapshot.id, snapshot.bridgeRevision, prompt,
            if (snapshot.source == "xmage-ondevice") "play_mana" else prompt.responseCommand?.type ?: "play_mana",
            prompt.responseCommand?.promptId ?: prompt.id, prompt.playerId, listOf(symbol), manaType = symbol)
    }
}

/** The tone of the guidance pill; the app maps it to the palette. */
enum class GuidanceTone { GOLD, OXBLOOD, AMBER, EMERALD, ARCANE }

class PromptGuidance(snapshot: GameSnapshot, isWaitingOnHuman: Boolean, combatSelection: CombatSelectionState = CombatSelectionState()) {
    val label: String
    val message: String
    val tone: GuidanceTone
    val isUrgent: Boolean

    init {
        val v2 = snapshot.promptEnvelopeV2
        val promptType = v2?.responseCommand?.type?.lowercase() ?: v2?.responseKind?.lowercase() ?: ""
        val method = v2?.method?.uppercase() ?: ""
        when {
            snapshot.manaPayment?.active == true || v2?.let(CompactPromptPopup::isManaPaymentPrompt) == true -> {
                label = "PAY COST"; message = snapshot.manaPayment?.remainingText ?: "Tap mana sources"; tone = GuidanceTone.GOLD; isUrgent = true
            }
            promptType == "choose_target" || method.contains("TARGET") -> {
                label = "SELECT TARGET"; message = snapshot.promptText ?: "Choose a highlighted target"; tone = GuidanceTone.OXBLOOD; isUrgent = true
            }
            CombatSelectionState.isDeclareAttackers(snapshot) -> {
                val selectable = combatSelection.attackerHighlightIds(snapshot.legalActions ?: emptyList())
                label = if (combatSelection.selectedAttackerIds.isEmpty()) "SELECT ATTACKERS" else "SELECT DEFENDER"
                message = if (combatSelection.selectedAttackerIds.isEmpty())
                    (if (selectable.isEmpty()) "No creatures can attack — choose No Attacks" else "Choose a highlighted attacker")
                else "Choose who to attack"
                tone = GuidanceTone.OXBLOOD; isUrgent = true
            }
            CombatSelectionState.isDeclareBlockers(snapshot) -> {
                val selectable = combatSelection.blockerHighlightIds(snapshot.legalActions ?: emptyList())
                label = if (combatSelection.selectedBlockerId == null) "SELECT BLOCKERS" else "SELECT ATTACKER"
                message = if (combatSelection.selectedBlockerId == null)
                    (if (selectable.isEmpty()) "No creatures can block — choose No Blocks" else "Choose a highlighted blocker")
                else "Choose attacker to block"
                tone = GuidanceTone.AMBER; isUrgent = true
            }
            isWaitingOnHuman -> {
                label = "YOUR DECISION"; message = snapshot.promptText ?: "Play spells and abilities"; tone = GuidanceTone.EMERALD; isUrgent = false
            }
            else -> {
                label = "${snapshot.playerLabel(snapshot.waitingOnPlayerId ?: snapshot.priorityPlayerId).uppercase()} DECISION"
                message = snapshot.promptText ?: "Waiting for XMage"; tone = GuidanceTone.ARCANE; isUrgent = false
            }
        }
    }
}

object BoardDecisionPresentation {
    fun showsGuidance(snapshot: GameSnapshot): Boolean = PromptGuidance(snapshot, snapshot.isViewer(snapshot.waitingOnPlayerId)).isUrgent
    fun needsCenterSpace(snapshot: GameSnapshot, hasRejection: Boolean = false): Boolean = showsGuidance(snapshot) || hasRejection ||
        snapshot.xmage?.revealed?.any { it.cards.isNotEmpty() } == true || snapshot.xmage?.lookedAt?.any { it.cards.isNotEmpty() } == true
}

class CombatHighlightSet(selection: CombatSelectionState, actions: List<LegalAction>, combatGroups: List<XmageCombatGroup>) {
    val cardIds: Set<String>
    val defenderIds: Set<String>

    init {
        val cards = mutableSetOf<String>()
        cards += selection.attackerHighlightIds(actions)
        cards += selection.blockerHighlightIds(actions)
        cards += selection.attackingCreatureHighlightIds(actions, combatGroups)
        cards += selection.selectedAttackerIds
        selection.selectedBlockerId?.let { cards += it }
        val defenders = selection.defenderHighlightIds(actions)
        cards += defenders
        cardIds = cards; defenderIds = defenders
    }

    fun matches(card: ZoneCard): Boolean = CombatSelectionState.matchingCardId(card, cardIds) != null
    fun matches(id: String): Boolean = cardIds.contains(id) || defenderIds.contains(id)
}

data class CombatSelectionState(val selectedAttackerIds: Set<String> = emptySet(), val selectedBlockerId: String? = null,
                                val blockerPairs: List<BlockDeclaration> = emptyList()) {
    val hasPendingBlockers: Boolean get() = blockerPairs.isNotEmpty()
    val blockerPairCount: Int get() = blockerPairs.size
    val selectedAttackerId: String? get() = if (selectedAttackerIds.size == 1) selectedAttackerIds.first() else null

    fun toggleAttacker(id: String) = copy(selectedAttackerIds = if (selectedAttackerIds.contains(id)) selectedAttackerIds - id else selectedAttackerIds + id)
    fun selectAttacker(id: String) = copy(selectedAttackerIds = setOf(id))
    fun selectBlocker(id: String) = copy(selectedBlockerId = id)
    fun pairSelectedBlocker(attackerId: String): CombatSelectionState {
        val blockerId = selectedBlockerId ?: return this
        val pair = BlockDeclaration(blockerId, attackerId)
        return copy(blockerPairs = if (blockerPairs.contains(pair)) blockerPairs else blockerPairs + pair, selectedBlockerId = null)
    }
    fun clearAttackers() = copy(selectedAttackerIds = emptySet())
    fun clearBlockers() = copy(selectedBlockerId = null, blockerPairs = emptyList())
    fun resetIfInactive(snapshot: GameSnapshot): CombatSelectionState {
        var next = this
        if (!isDeclareAttackers(snapshot)) next = next.clearAttackers()
        if (!isDeclareBlockers(snapshot)) next = next.clearBlockers()
        return next
    }

    fun attackerHighlightIds(actions: List<LegalAction>): Set<String> {
        val declare = actions.filter { it.type == "declare_attackers" }
        return declare.flatMap { attackers(it).map { a -> a.attackerId } }.toSet() +
            declare.mapNotNull { it.effectiveCardInstanceId ?: it.effectiveSourceInstanceId }
    }

    fun defenderHighlightIds(actions: List<LegalAction>): Set<String> = actions.filter { it.type == "declare_attackers" }.flatMap { action ->
        attackers(action).mapNotNull { it.defenderId } + (action.validTargetIds ?: emptyList()) + (action.validPlayerIds ?: emptyList()) +
            (action.playerIds ?: emptyList()) + (action.targetIds ?: emptyList())
    }.toSet()

    fun defenderIds(attackerId: String, actions: List<LegalAction>): Set<String> = actions.filter { it.type == "declare_attackers" }.flatMap { action ->
        val ids = attackers(action).map { it.attackerId }.toSet()
        val actionCardId = action.effectiveCardInstanceId ?: action.effectiveSourceInstanceId
        if (!ids.contains(attackerId) && actionCardId != attackerId) emptyList()
        else attackers(action).mapNotNull { it.defenderId } + (action.validTargetIds ?: emptyList()) + (action.validPlayerIds ?: emptyList()) +
            (action.playerIds ?: emptyList()) + (action.targetIds ?: emptyList())
    }.toSet()

    fun defenderKind(defenderId: String, actions: List<LegalAction>): String? =
        actions.firstOrNull { it.type == "declare_attackers" && attackers(it).any { a -> a.defenderId == defenderId } }?.defenderKind

    fun blockerHighlightIds(actions: List<LegalAction>): Set<String> {
        val declare = actions.filter { it.type == "declare_blockers" }
        return declare.flatMap { blockers(it).map { b -> b.blockerId } }.toSet() +
            declare.mapNotNull { it.effectiveCardInstanceId ?: it.effectiveSourceInstanceId }
    }

    fun attackingCreatureHighlightIds(actions: List<LegalAction>, combatGroups: List<XmageCombatGroup>): Set<String> =
        actions.filter { it.type == "declare_blockers" }.flatMap { blockers(it).mapNotNull { b -> b.attackerId } }.toSet() +
            combatGroups.flatMap { g -> g.attackers.map { it.instanceId } }

    fun attackingCreatureIds(blockerId: String, actions: List<LegalAction>, combatGroups: List<XmageCombatGroup>): Set<String> {
        val ids = actions.filter { it.type == "declare_blockers" }.flatMap { action ->
            blockers(action).filter { it.blockerId == blockerId }.mapNotNull { it.attackerId }
        }.toMutableSet()
        if (ids.isEmpty()) ids += combatGroups.flatMap { g -> g.attackers.map { it.instanceId } }
        return ids
    }

    fun attackCommand(gameId: String, playerId: String, defenderId: String, actions: List<LegalAction>, expectedBridgeRevision: Int?): GameCommand? {
        val legal = attackerHighlightIds(actions)
        if (selectedAttackerIds.isEmpty() || !legal.containsAll(selectedAttackerIds)) return null
        return GameCommand(type = "declare_attackers", gameId = gameId, playerId = playerId,
            attackers = selectedAttackerIds.sorted().map { AttackDeclaration(it, defenderId) }, combatComplete = false,
            expectedBridgeRevision = expectedBridgeRevision)
    }

    fun pendingBlockActionPayload(playerId: String, gameId: String, expectedBridgeRevision: Int? = null): GameCommand? {
        if (blockerPairs.isEmpty()) return null
        return GameCommand(type = "declare_blockers", gameId = gameId, playerId = playerId, blockers = blockerPairs, combatComplete = false,
            expectedBridgeRevision = expectedBridgeRevision)
    }

    companion object {
        fun matchingCardId(card: ZoneCard, ids: Set<String>): String? = when {
            ids.contains(card.instanceId) -> card.instanceId
            ids.contains(card.id) -> card.id
            else -> null
        }

        fun finishAttackCommand(gameId: String, playerId: String, expectedBridgeRevision: Int?) = GameCommand(type = "declare_attackers",
            gameId = gameId, playerId = playerId, attackers = emptyList(), combatComplete = true, expectedBridgeRevision = expectedBridgeRevision)

        fun finishBlockCommand(gameId: String, playerId: String, expectedBridgeRevision: Int?) = GameCommand(type = "declare_blockers",
            gameId = gameId, playerId = playerId, blockers = emptyList(), combatComplete = true, expectedBridgeRevision = expectedBridgeRevision)

        fun isDeclareAttackers(snapshot: GameSnapshot): Boolean = snapshot.legalActions?.any { it.type == "declare_attackers" } == true
        fun isDeclareBlockers(snapshot: GameSnapshot): Boolean = snapshot.legalActions?.any { it.type == "declare_blockers" } == true

        private fun attackers(action: LegalAction): List<AttackDeclaration> {
            action.attackers?.takeIf { it.isNotEmpty() }?.let { return it }
            val values = action.commandTemplate?.get("attackers").array ?: return emptyList()
            return values.mapNotNull { value -> value["attackerId"].stringValue?.let { AttackDeclaration(it, value["defenderId"].stringValue) } }
        }

        private fun blockers(action: LegalAction): List<BlockDeclaration> {
            action.blockers?.takeIf { it.isNotEmpty() }?.let { return it }
            val values = action.commandTemplate?.get("blockers").array ?: return emptyList()
            return values.mapNotNull { value -> value["blockerId"].stringValue?.let { BlockDeclaration(it, value["attackerId"].stringValue) } }
        }
    }
}

/** The key that resets a pending combat selection when the game moves (Swift `combatSelectionResetKey`). */
val GameSnapshot.combatSelectionResetKey: String get() = "$id|${bridgeRevision ?: -1}|$turn|$phase|${step ?: ""}"

val GameSnapshot.visibleBattlefield: List<ZoneCard> get() = players.flatMap { it.zones.battlefield }

enum class CombatArrowKind { ATTACK, BLOCKED_ATTACK, BLOCK, PREVIEW_ATTACK, PREVIEW_BLOCK }
data class CombatArrow(val kind: CombatArrowKind, val fromId: String, val toId: String, val toKind: String?)

object CombatArrowModel {
    fun arrows(groups: List<XmageCombatGroup>): List<CombatArrow> = groups.flatMap { group ->
        val kind = if (group.blocked) CombatArrowKind.BLOCKED_ATTACK else CombatArrowKind.ATTACK
        group.attackers.map { CombatArrow(kind, it.instanceId, group.defenderId, group.defenderKind) } +
            group.blockers.flatMap { blocker -> group.attackers.map { attacker -> CombatArrow(CombatArrowKind.BLOCK, blocker.instanceId, attacker.instanceId, null) } }
    }
    fun arrows(groups: List<XmageCombatGroup>, previewArrows: List<CombatArrow>): List<CombatArrow> = arrows(groups) + previewArrows
}

object VisibleCombatAnchors {
    fun resolve(bounds: Map<String, BoardRect>, authorizedIDs: Set<String>, viewports: List<BoardRect>): Map<String, BoardPoint> =
        bounds.filter { (id, rect) -> authorizedIDs.contains(id) && !rect.isEmpty && viewports.any { it.contains(rect) } }
            .mapValues { BoardPoint(it.value.midX, it.value.midY) }
}

object CombatPlayerIdentity {
    enum class Side { VIEWER, OPPONENT }

    fun ids(playerID: String, snapshot: GameSnapshot): List<String> =
        listOf(playerID) + (snapshot.xmage?.players?.filter { it.playerId == playerID }?.mapNotNull { it.xmagePlayerId } ?: emptyList())

    fun targetID(playerID: String, snapshot: GameSnapshot, candidates: Set<String>): String? = ids(playerID, snapshot).firstOrNull { candidates.contains(it) }

    fun side(defenderID: String, kind: String?, snapshot: GameSnapshot): Side? {
        // A permanent must use its card anchor, even if its ID resembles a seat ID.
        if (kind != null && kind.lowercase() != "player") return null
        if (ids(snapshot.viewerID, snapshot).contains(defenderID)) return Side.VIEWER
        val opponentID = snapshot.opponent?.playerId
        if (opponentID != null && ids(opponentID, snapshot).contains(defenderID)) return Side.OPPONENT
        return null
    }

    fun defenderAnchor(defenderID: String, kind: String?, metrics: BattlefieldLayoutMetrics, snapshot: GameSnapshot): BoardPoint? {
        val side = side(defenderID, kind, snapshot) ?: return null
        val rect = if (side == Side.VIEWER) metrics.playerBattlefieldRect else metrics.opponentBattlefieldRect
        return BoardPoint(metrics.boardColumnRect.minX + 10, rect.midY)
    }
}

object PortraitCombatAnchorResolver {
    fun cardAnchors(metrics: PortraitBattlefieldLayoutMetrics, humanBattlefield: List<ZoneCard>, opponentBattlefield: List<ZoneCard>): Map<String, BoardPoint> {
        val anchors = HashMap<String, BoardPoint>()
        add(opponentBattlefield.filter { !it.card.isLand }, metrics.opponentBattlefieldRect, metrics.permanentCardWidth, anchors)
        add(opponentBattlefield.filter { it.card.isLand }, metrics.opponentLandsRect, metrics.landCardWidth, anchors)
        add(humanBattlefield.filter { !it.card.isLand }, metrics.playerBattlefieldRect, metrics.permanentCardWidth, anchors)
        add(humanBattlefield.filter { it.card.isLand }, metrics.playerLandsRect, metrics.landCardWidth, anchors)
        return anchors
    }

    fun defenderAnchor(defenderId: String, kind: String?, metrics: PortraitBattlefieldLayoutMetrics, snapshot: GameSnapshot): BoardPoint? {
        val side = CombatPlayerIdentity.side(defenderId, kind, snapshot) ?: return null
        val rect = if (side == CombatPlayerIdentity.Side.VIEWER) metrics.bottomHUDRect else metrics.topHUDRect
        return BoardPoint(rect.midX, rect.midY)
    }

    private fun add(cards: List<ZoneCard>, rect: BoardRect, cardWidth: Float, into: MutableMap<String, BoardPoint>) {
        if (cards.isEmpty()) return
        val spacing = 4f
        val total = cards.size * cardWidth + maxOf(cards.size - 1, 0) * spacing
        val startX = rect.midX - total / 2 + cardWidth / 2
        cards.forEachIndexed { index, card -> into[card.instanceId] = BoardPoint(startX + index * (cardWidth + spacing), rect.midY) }
    }
}

data class PortraitBattlefieldRowPlan(val rows: List<List<ZoneCard>>, val cardsPerRow: Int, val overflowsHorizontally: Boolean)

object PortraitBattlefieldRowPlanner {
    fun plan(cards: List<ZoneCard>, rowWidth: Float, cardWidth: Float, maxRows: Int = 3): PortraitBattlefieldRowPlan {
        if (cards.isEmpty()) return PortraitBattlefieldRowPlan(listOf(emptyList()), 1, false)
        val visible = cards.take(10)
        val rowCount = when {
            visible.size <= 4 -> 1
            visible.size <= 7 -> minOf(maxRows, 2)
            else -> minOf(maxRows, 3)
        }
        val base = maxOf(rowCount, 1)
        val baseSize = visible.size / base
        val remainder = visible.size % base
        val rows = mutableListOf<MutableList<ZoneCard>>()
        var index = 0
        for (rowIndex in 0 until base) {
            val size = baseSize + if (rowIndex < remainder) 1 else 0
            if (size <= 0) continue
            rows += visible.subList(index, index + size).toMutableList()
            index += size
        }
        if (cards.size > 10 && rows.isNotEmpty()) rows.last().addAll(cards.drop(10))
        return PortraitBattlefieldRowPlan(rows, rows.maxOfOrNull { it.size } ?: 1, cards.size > 10)
    }
}

data class PortraitOverlapLayoutPlan(val count: Int, val cardWidth: Float, val containerWidth: Float, val visibleLimit: Int,
                                     val stride: Float, val contentWidth: Float, val needsScrolling: Boolean) {
    fun xOffset(index: Int): Float {
        val start = if (contentWidth > containerWidth) 8f else maxOf((containerWidth - visibleContentWidth) / 2, 0f)
        return start + maxOf(index, 0) * stride
    }
    private val visibleContentWidth: Float get() = if (count <= 0) 0f else cardWidth + maxOf(minOf(count, visibleLimit) - 1, 0) * stride
}

object PortraitOverlapLayout {
    fun plan(count: Int, containerWidth: Float, cardWidth: Float, visibleLimit: Int = 10, minVisibleWidth: Float = 30f, spacing: Float = 6f): PortraitOverlapLayoutPlan {
        if (count <= 0) return PortraitOverlapLayoutPlan(0, cardWidth, containerWidth, visibleLimit, cardWidth + spacing, maxOf(containerWidth, 0f), false)
        val visibleCount = minOf(count, maxOf(visibleLimit, 1))
        val naturalStride = cardWidth + spacing
        val fittingStride = if (visibleCount > 1) maxOf((containerWidth - cardWidth) / (visibleCount - 1), 1f) else naturalStride
        val stride = minOf(naturalStride, maxOf(fittingStride, minVisibleWidth))
        val visibleContentWidth = cardWidth + maxOf(visibleCount - 1, 0) * stride
        val needsScrolling = count > visibleLimit || visibleContentWidth > containerWidth
        val contentWidth = if (needsScrolling && count > visibleLimit) cardWidth + maxOf(count - 1, 0) * stride
        else minOf(maxOf(visibleContentWidth, cardWidth), maxOf(containerWidth, cardWidth))
        return PortraitOverlapLayoutPlan(count, cardWidth, containerWidth, visibleLimit, stride, contentWidth, needsScrolling)
    }
}

object LandscapeActionDockLayout {
    const val horizontalPadding = 6f
    const val bottomPadding = 4f
    const val controlSpacing = 4f
    const val primaryLineLimit = 1
    fun sidebarWidth(hasStack: Boolean): Float = if (hasStack) 176f else 160f
}

object StackTargetPresentation {
    fun labels(ids: List<String>, snapshot: GameSnapshot): List<String> {
        val cards = PortraitInteractionPolicy.authorizedCards(snapshot)
        return ids.map { id ->
            snapshot.players.firstOrNull { CombatPlayerIdentity.ids(it.playerId, snapshot).contains(id) }?.let { return@map snapshot.playerLabel(it.playerId) }
            cards.firstOrNull { it.id == id }?.let { return@map if (NativeCardArtworkPolicy.permitsLookup(it)) it.card.name else "Hidden card" }
            snapshot.xmage?.stack?.firstOrNull { it.id == id || it.objectId == id }?.let { return@map it.displayName }
            "Unavailable target"
        }
    }
}

object HandFanLayout {
    fun card(point: BoardPoint, cards: List<ZoneCard>, metrics: BattlefieldLayoutMetrics, selectedCardId: String?, draggingCardId: String?,
             dragOffset: BoardSize): ZoneCard? {
        if (cards.isEmpty()) return null
        for (index in cards.indices.reversed()) {
            val frame = cardFrame(index, cards[index], cards, metrics, selectedCardId, draggingCardId, dragOffset)
            if (BoardRect(frame.x - 8, frame.y - 8, frame.width + 16, frame.height + 16).contains(point)) return cards[index]
        }
        return cards.last()
    }

    fun cardFrame(index: Int, card: ZoneCard, cards: List<ZoneCard>, metrics: BattlefieldLayoutMetrics, selectedCardId: String?,
                  draggingCardId: String?, dragOffset: BoardSize): BoardRect {
        val center = (cards.size - 1) / 2f
        val distance = index - center
        val maxSpread = maxOf((metrics.boardColumnRect.width - metrics.handCardWidth) / maxOf(cards.size - 1, 1), 0f)
        val spread = minOf(metrics.handCardWidth * 0.56f, maxSpread)
        val isSelected = selectedCardId == card.id
        val isDragging = draggingCardId == card.id
        val midX = metrics.boardColumnRect.width / 2 + distance * spread + if (isDragging) dragOffset.width else 0f
        val midY = metrics.handFrameHeight / 2 + (if (isSelected) -30f else 10f) + if (isDragging) dragOffset.height else 0f
        return BoardRect(midX - metrics.handCardWidth / 2, midY - metrics.handCardHeight / 2, metrics.handCardWidth, metrics.handCardHeight)
    }
}

/** Swift `String.phaseTitle`, `compactPhaseTitle` and `arenaPhaseTitle`. */
object PhaseTitles {
    fun phaseTitle(value: String): String = value.split("-").joinToString(" ") { capitalizedWords(it) }

    fun compactPhaseTitle(value: String): String = when (value.lowercase()) {
        "beginning", "untap", "upkeep", "draw" -> capitalizedWords(value)
        "precombat-main" -> "Main 1"
        "postcombat-main" -> "Main 2"
        "combat", "begin-combat" -> "Combat"
        "declare-attackers" -> "Attackers"
        "declare-blockers" -> "Blockers"
        "first-strike-damage" -> "First Damage"
        "combat-damage" -> "Damage"
        "end-combat" -> "End Combat"
        "ending", "end", "cleanup" -> capitalizedWords(value)
        else -> phaseTitle(value)
    }

    fun arenaPhaseTitle(value: String): String = when (value.lowercase().replace("_", "-")) {
        "beginning" -> "BEGIN"; "untap" -> "UNTAP"; "upkeep" -> "UPKEEP"; "draw" -> "DRAW"
        "precombat-main" -> "MAIN 1"; "postcombat-main" -> "MAIN 2"; "combat", "begin-combat" -> "COMBAT"
        "declare-attackers" -> "ATTACK"; "declare-blockers" -> "BLOCK"
        "first-combat-damage", "first-strike-damage", "combat-damage" -> "DAMAGE"
        "end-combat" -> "END C"; "ending", "end", "end-turn" -> "END"; "cleanup" -> "CLEANUP"
        else -> EngineDisplayText.phaseLabel(value)
    }
}

/** Display text for a legal action (the private LegalAction extension in ContentView.swift). */
object LegalActionDisplay {
    fun displayLabel(action: LegalAction): String {
        if (action.type == "choose_ability" || action.type == "activate_ability") return action.compactPromptTitle
        action.shortLabel?.takeIf { it.isNotEmpty() }?.let { return it }
        return when (action.type) {
            "pass_priority" -> "Pass Priority"; "pass_until_response" -> "Pass Until Response"
            "resolve_stack", "pass_until_stack_resolved" -> "Resolve Stack"; "end_turn" -> "End Turn"
            "pass_until_end_of_turn" -> "Yield Until End Step"; "yield_until_next_turn", "pass_until_next_turn" -> "Yield Until Next Turn"
            "play_land" -> "Play"; "cast_spell" -> "Cast"; "activate_ability" -> "Ability"; "make_mana" -> "Mana"
            else -> action.label
        }
    }

    fun actionDetail(action: LegalAction): String? {
        if (action.type == "cast_spell") {
            val cost = action.manaCost
            if (!cost.isNullOrEmpty()) return if (action.requiresPayment == true) "$cost · XMage will ask for payment" else cost
            if (action.requiresPayment == true) return "XMage will ask for payment"
        }
        if (action.type == "make_mana" && !action.producedMana.isNullOrEmpty()) return action.producedMana.joinToString(" ") { "{$it}" }
        if (!action.zoneContext.isNullOrEmpty()) return action.zoneContext
        if (!action.sourceZone.isNullOrEmpty()) return action.sourceZone
        val count = action.validTargetIds?.size ?: action.targetIds?.size ?: 0
        return if (count > 0) "$count choices" else null
    }

    fun actionPriority(action: LegalAction): Int {
        if (action.isPrimary == true) return 0
        return when (action.type) {
            "keep_hand", "resolve_choice", "play_land", "cast_spell" -> 1
            "choose_target", "choose_card", "choose_mode", "choose_ability", "choose_amount", "play_mana" -> 2
            "make_mana", "activate_ability", "pay_cost" -> 3
            "pass_priority" -> 4
            "pass_until_response", "resolve_stack", "pass_until_stack_resolved", "end_turn", "pass_until_end_of_turn",
            "yield_until_next_turn", "pass_until_next_turn", "advance_phase" -> 5
            "concede" -> 9
            else -> 6
        }
    }

    /** The SF Symbol name iOS shows; the app maps it to an Android icon. */
    fun systemImage(action: LegalAction): String = when (action.type) {
        "keep_hand" -> "hand.thumbsup.fill"; "mulligan" -> "arrow.counterclockwise"; "play_land" -> "leaf.fill"; "cast_spell" -> "sparkles"
        "activate_ability", "choose_ability" -> "bolt.fill"; "make_mana", "play_mana", "play_x_mana" -> "circle.hexagongrid.fill"
        "choose_target" -> "scope"; "choose_card", "search_select" -> "rectangle.stack.fill"; "choose_mode" -> "square.stack.3d.up"
        "choose_amount", "choose_multi_amount" -> "number"; "order_triggers" -> "arrow.up.arrow.down"; "commander_replacement" -> "crown.fill"
        "pass_priority", "pass_until_response", "resolve_stack", "pass_until_stack_resolved", "end_turn", "pass_until_end_of_turn",
        "yield_until_next_turn", "pass_until_next_turn", "advance_phase" -> "forward.fill"
        "concede" -> "flag.fill"
        else -> "circle.fill"
    }
}

val AiDifficulty.menuLabel: String get() = displayName
