package io.magicmobile.android.game

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** Port of apps/ios/MagicMobile/OnDevicePromptAdapter.swift. */
data class OnDevicePromptPresentation(val envelope: PromptEnvelopeV2, val legalActions: List<LegalAction>, val manaPayment: ManaPayment?)

object OnDevicePromptAdapter {
    private fun s(value: String) = JsonPrimitive(value)
    private fun n(value: Long) = JsonPrimitive(value)
    private fun n(value: Int) = JsonPrimitive(value)
    private fun b(value: Boolean) = JsonPrimitive(value)

    fun presentation(prompt: EnginePrompt, viewerPlayerID: String, cards: List<ZoneCard>, players: List<PlayerGameState> = emptyList(),
                     actingAttackerPlayerID: String? = null): OnDevicePromptPresentation {
        validate(prompt, viewerPlayerID)
        val revision = prompt.revision.toInt()
        val fields = linkedMapOf<String, J>(
            "id" to s(prompt.id), "method" to s("GAME_${prompt.kind}"), "messageId" to n(revision), "playerId" to s(viewerPlayerID),
            "responseKind" to s("unsupported"), "message" to s(EngineDisplayText.text(prompt.payload["message"].string ?: "")),
            "required" to b(prompt.payload["required"].bool ?: true))
        val actions = mutableListOf<LegalAction>()
        var payment: ManaPayment? = null
        prompt.payload["options"]?.let { fields["options"] = it }
        fun response(type: String): JsonObject = jsonObject("type" to s(type), "promptId" to s(prompt.id), "messageId" to n(revision))
        fun action(type: String, label: String, extras: Map<String, J> = emptyMap()): LegalAction {
            val value = linkedMapOf<String, J>("id" to s("${prompt.id}:$type"), "type" to s(type), "label" to s(EngineDisplayText.label(label)),
                "playerId" to s(viewerPlayerID), "promptId" to s(prompt.id), "messageId" to n(revision))
            value.putAll(extras)
            return EngineJson.format.decodeFromJsonElement(LegalAction.serializer(), JsonObject(value))
        }
        fun targetLabel(id: String): String {
            if (id == viewerPlayerID) return "You"
            return EngineDisplayText.label(players.firstOrNull { it.playerId == id }?.displayName
                ?: cards.firstOrNull { it.id == id }?.card?.name ?: id)
        }
        fun command(base: JsonObject, vararg extra: Pair<String, J>): JsonObject = JsonObject(base + extra)
        when (prompt.kind) {
            "ASK" -> {
                if (!prompt.responseTypes.contains("boolean")) throw invalid("ASK requires boolean responses")
                val base = response("answer_yes_no")
                fields["responseKind"] = s("confirmation"); fields["responseCommand"] = base
                fields["confirmation"] = jsonObject(
                    "yesLabel" to s(plainLabel(prompt.payload["options"]["UI.left.btn.text"].string, "Yes")),
                    "noLabel" to s(plainLabel(prompt.payload["options"]["UI.right.btn.text"].string, "No")),
                    "yesCommand" to command(base, "confirmed" to b(true)), "noCommand" to command(base, "confirmed" to b(false)))
            }
            "SELECT" -> {
                when (prompt.payload["selectMode"].string) {
                    "priority" -> {
                        fields["responseKind"] = s("priority"); fields["responseCommand"] = response("pass_priority")
                        if (prompt.responseTypes.contains("boolean")) actions += action("pass_priority", "Pass priority")
                    }
                    "attackers", "blockers" -> {
                        val key = if (prompt.payload["selectMode"].string == "attackers") "possibleAttackers" else "possibleBlockers"
                        val candidates = prompt.payload["options"][key].array
                        if (!prompt.responseTypes.contains("uuid") || candidates == null) throw invalid("Missing combat candidates")
                        fields["responseKind"] = s("target"); fields["responseCommand"] = response("choose_target")
                        fields["minChoices"] = n(1); fields["maxChoices"] = n(1)
                        val targets = candidates.map { item ->
                            val id = item.string
                            if (!isUuid(id)) throw invalid("Invalid combat UUID")
                            id!! to targetLabel(id)
                        }.toMutableList()
                        // Upstream removes declared attackers from its highlights; the snapshot adapter
                        // authorizes a controlled acting player separately.
                        if (key == "possibleAttackers" && actingAttackerPlayerID != null) {
                            if (!isUuid(actingAttackerPlayerID) || players.none { it.playerId == actingAttackerPlayerID }) throw invalid("Invalid acting attacker identity")
                        }
                        val attackerID = actingAttackerPlayerID ?: viewerPlayerID
                        val battlefield = if (key == "possibleAttackers") players.firstOrNull { it.playerId == attackerID }?.zones?.battlefield ?: emptyList() else emptyList()
                        for (card in battlefield) {
                            if (card.isAttacking != true) continue
                            if (!isUuid(card.id)) throw invalid("Invalid combat UUID")
                            if (targets.none { it.first == card.id }) targets += card.id to EngineDisplayText.label(card.card.name)
                        }
                        fields["targets"] = JsonArray(targets.map { jsonObject("id" to s(it.first), "label" to s(it.second)) })
                        if (prompt.responseTypes.contains("boolean")) actions += action("answer_yes_no", "Done", mapOf("confirmed" to b(true)))
                    }
                    else -> throw invalid("Unsupported SELECT mode")
                }
                val special = prompt.payload["options"]["specialButton"].string
                if (prompt.responseTypes.contains("string") && special != null) {
                    actions += action("resolve_choice", special, mapOf("choiceIds" to JsonArray(listOf(s("special")))))
                }
            }
            "PLAY_MANA", "PLAY_X_MANA" -> {
                val player = prompt.payload["manaPlayerId"].string
                if (!prompt.responseTypes.contains("mana") || !isUuid(player)) throw invalid("Missing mana player UUID")
                val x = prompt.kind == "PLAY_X_MANA"
                fields["responseKind"] = s(if (x) "x_mana" else "mana")
                fields["responseCommand"] = response(if (x) "play_x_mana" else "play_mana")
                if (x) { fields["minChoices"] = n(prompt.minimum); fields["maxChoices"] = n(prompt.maximum) }
                players.firstOrNull { it.playerId == player }?.manaPool?.let { pool ->
                    fields["manaChoices"] = JsonArray(listOf("W" to pool.W, "U" to pool.U, "B" to pool.B, "R" to pool.R, "G" to pool.G, "C" to pool.C)
                        .filter { it.second > 0 }.map { (symbol, amount) ->
                            jsonObject("id" to s(symbol), "manaType" to s(symbol), "label" to s("Pay {$symbol}"), "amount" to n(amount))
                        })
                }
                payment = ManaPayment(active = true, remainingText = EngineDisplayText.text(prompt.payload["message"].string ?: ""))
                if (prompt.responseTypes.contains("boolean")) actions += action("cancel_payment", "Cancel", mapOf("confirmed" to b(false)))
                if (!x && prompt.responseTypes.contains("string")) {
                    // The pinned PLAY_MANA protocol publishes exactly the string "special"; XMage opens its
                    // own special-action chooser (convoke, delve) after this response.
                    actions += action("resolve_choice", prompt.payload["options"]["specialButton"].string ?: "Special payment",
                        mapOf("choiceIds" to JsonArray(listOf(s("special")))))
                }
            }
            "MULTI_AMOUNT" -> {
                val rows = prompt.payload["allocations"].array
                if (!prompt.responseTypes.contains("integers") || rows == null) throw invalid("Missing allocation rows")
                fields["method"] = s("GAME_GET_MULTI_AMOUNT"); fields["responseKind"] = s("multi_amount")
                fields["responseCommand"] = response("choose_multi_amount")
                fields["totalMin"] = n(prompt.minimum); fields["totalMax"] = n(prompt.maximum)
                fields["multiAmounts"] = JsonArray(rows.mapIndexed { index, row ->
                    val min = row["min"].integer; val max = row["max"].integer; val label = row["message"].string
                    if (min == null || max == null || min > max || label == null) throw invalid("Malformed allocation row")
                    val value = linkedMapOf<String, J>("id" to s(index.toString()), "label" to s(EngineDisplayText.label(label)), "min" to n(min), "max" to n(max))
                    row["defaultValue"].integer?.let { value["defaultValue"] = n(it) }
                    JsonObject(value)
                })
                if (prompt.responseTypes.contains("boolean") && prompt.payload["options"]["canCancel"].bool == true) {
                    actions += action("answer_yes_no", "Cancel", mapOf("confirmed" to b(false)))
                }
            }
            "AMOUNT" -> {
                if (!prompt.responseTypes.contains("integer")) throw invalid("Amount requires integer responses")
                fields["method"] = s("GAME_GET_AMOUNT"); fields["responseKind"] = s("amount"); fields["responseCommand"] = response("choose_amount")
                fields["minChoices"] = n(prompt.minimum); fields["maxChoices"] = n(prompt.maximum)
                if (prompt.minimum > prompt.maximum || prompt.minimum !in Int.MIN_VALUE..Int.MAX_VALUE || prompt.maximum !in Int.MIN_VALUE..Int.MAX_VALUE) {
                    throw invalid("Invalid amount bounds")
                }
                // Narrow ranges use quick buttons; wider ranges keep the bounds for the manual amount UI.
                if (prompt.maximum - prompt.minimum < 64) fields["amounts"] = JsonArray((prompt.minimum..prompt.maximum).map { n(it) })
            }
            "CHOOSE_PILE" -> {
                val one = prompt.payload["pile1"].array; val two = prompt.payload["pile2"].array
                if (!prompt.responseTypes.contains("boolean") || one == null || two == null) throw invalid("Missing boolean pile choices")
                fields["responseKind"] = s("pile"); fields["responseCommand"] = response("choose_pile")
                fields["piles"] = JsonArray(listOf(one, two).mapIndexed { index, pile ->
                    jsonObject("id" to s("${index + 1}"), "label" to s("Pile ${index + 1}"), "cards" to JsonArray(pile.map(::promptCard)))
                })
            }
            "CHOOSE_ABILITY", "PICK_ABILITY" -> {
                val abilities = prompt.payload["abilities"].array
                if (!prompt.responseTypes.contains("uuid") || abilities == null) throw invalid("Missing UUID ability choices")
                fields["responseKind"] = s("ability"); fields["responseCommand"] = response("choose_ability")
                fields["minChoices"] = n(1); fields["maxChoices"] = n(1)
                fields["abilities"] = JsonArray(abilities.map { item ->
                    val id = item["id"].string; val label = item["label"].string
                    if (!isUuid(id) || label == null) throw invalid("Malformed ability choice")
                    val row = linkedMapOf<String, J>("id" to s(id!!), "label" to s(EngineDisplayText.label(label)))
                    val sourceID = item["sourceId"].string
                    if (isUuid(sourceID)) {
                        row["sourceInstanceId"] = s(sourceID!!)
                        val source = item["sourceCard"]
                        if (source != null && source["id"].string == sourceID && source["hideInfo"].bool != true) {
                            row["sourceCard"] = promptCard(source)
                            row["sourceName"] = s(EngineDisplayText.label(source["displayName"].string ?: source["name"].string ?: "Card details unavailable"))
                        }
                    }
                    if (row["sourceCard"] == null) row["sourceUnavailableReason"] = s("Source details unavailable")
                    JsonObject(row)
                })
                if (prompt.responseTypes.contains("boolean") && prompt.payload["required"].bool == false) {
                    actions += action("answer_yes_no", "Cancel", mapOf("confirmed" to b(false)))
                }
            }
            "CHOOSE_CHOICE" -> {
                if (!prompt.responseTypes.contains("string")) throw invalid("Choice requires string responses")
                if (prompt.payload["specialEnabled"].bool == true && prompt.payload["specialCanBeEmpty"].bool == true) {
                    actions += action("choose_empty_special", plainLabel(prompt.payload["specialText"].string, "Choose no item"))
                }
                fields["responseKind"] = s("choice"); fields["responseCommand"] = response("resolve_choice")
                fields["minChoices"] = n(1); fields["maxChoices"] = n(1)
                val rows = choices(prompt).toMutableList()
                if (prompt.payload["specialEnabled"].bool == true) {
                    for (row in rows.toList()) {
                        val key = "#" + row.first
                        prompt.payload["specialChoices"][key].string?.let { label ->
                            rows += key to EngineDisplayText.label("${prompt.payload["specialText"].string ?: "Special"}: $label")
                        }
                    }
                }
                if (prompt.payload["required"].bool == false) rows += "" to "Cancel"
                // Preserve engine hints, sorting, and exact choice metadata for callers.
                fields["options"] = prompt.payload
                fields["choices"] = JsonArray(rows.map { jsonObject("id" to s(it.first), "label" to s(it.second)) })
            }
            "CHOOSE_MODE" -> {
                if (!prompt.responseTypes.contains("uuid")) throw invalid("Mode requires UUID responses")
                fields["responseKind"] = s("mode"); fields["responseCommand"] = response("choose_mode")
                fields["minChoices"] = n(1); fields["maxChoices"] = n(1)
                fields["modes"] = JsonArray(choices(prompt).map { jsonObject("id" to s(it.first), "label" to s(it.second)) })
            }
            "PICK_TARGET" -> {
                if (!prompt.responseTypes.contains("uuid")) throw invalid("Target requires UUID responses")
                val candidates = selectableTargetIDs(prompt)
                val aliases = prompt.payload["responseAliases"].obj ?: emptyMap()
                fun canonical(id: String): String = aliases[id].string ?: id
                val canonicalCandidates = mutableListOf<String>()
                for (id in candidates.map(::canonical)) if (!canonicalCandidates.contains(id)) canonicalCandidates += id
                fields["responseKind"] = s("target"); fields["responseCommand"] = response("choose_target")
                fields["minChoices"] = n(1); fields["maxChoices"] = n(1)
                fields["targetIds"] = JsonArray(canonicalCandidates.map(::s))
                // QueryEncoder serializes CardViews in payload.cards and options.orderedViews only.
                val supplied = (prompt.payload["options"]["orderedViews"].array ?: emptyList()) + (prompt.payload["cards"].array ?: emptyList())
                val seen = mutableSetOf<String>()
                val mapped = supplied.filter { value -> value["id"].string?.let { seen.add(canonical(it)) } ?: false }.map { value ->
                    val card = promptCard(value).toMutableMap()
                    val id = canonical(value["id"].string!!)
                    card["instanceId"] = s(id)
                    val legal = canonicalCandidates.contains(id)
                    card["selectable"] = b(legal)
                    if (!legal) card["disabledReason"] = s("Not a legal choice")
                    JsonObject(card)
                }.toMutableList()
                // A query may supply only IDs (graveyard/hand selections). Recover only matching cards
                // from this authenticated view; battlefield targets remain direct board taps.
                val boardIDs = players.flatMap { it.zones.battlefield }.map { it.id }.toSet()
                for (card in cards) {
                    if (!canonicalCandidates.contains(canonical(card.id)) || boardIDs.contains(card.id) || !seen.add(canonical(card.id))) continue
                    val identity = linkedMapOf<String, J>("name" to s(card.card.name), "typeLine" to s(card.card.typeLine))
                    card.card.oracleText?.let { identity["oracleText"] = s(it) }
                    card.card.manaCost?.let { identity["manaCost"] = s(it) }
                    mapped += jsonObject("instanceId" to s(canonical(card.id)), "card" to JsonObject(identity), "selectable" to b(true))
                }
                fields["cards"] = JsonArray(mapped)
                val shown = mapped.mapNotNull { it["instanceId"].string }.toSet()
                fields["targets"] = JsonArray(canonicalCandidates.filter { !shown.contains(it) }.map { id ->
                    val label = targetLabel(id)
                    jsonObject("id" to s(id), "label" to s(if (label == id) "Card details unavailable" else label))
                })
                val options = (fields["options"].obj ?: emptyMap()).toMutableMap()
                prompt.payload["options"]["chosenTargets"].array?.let { chosen ->
                    val unique = mutableListOf<String>()
                    for (id in chosen.mapNotNull { it.string }.map(::canonical)) if (!unique.contains(id)) unique += id
                    options["chosenTargets"] = JsonArray(unique.map(::s))
                }
                fields["options"] = JsonObject(options)
                if (prompt.responseTypes.contains("boolean") && prompt.payload["required"].bool == false) {
                    actions += action("answer_yes_no", prompt.payload["options"]["UI.right.btn.text"].string ?: "Cancel", mapOf("confirmed" to b(false)))
                }
            }
            else -> throw invalid("Unsupported prompt: ${prompt.kind}")
        }
        val envelope = EngineJson.format.decodeFromJsonElement(PromptEnvelopeV2.serializer(), JsonObject(fields))
        return OnDevicePromptPresentation(envelope, actions, payment)
    }

    fun answer(command: GameCommand, prompt: EnginePrompt, viewerPlayerID: String): J {
        validate(prompt, viewerPlayerID)
        // messageId carries this prompt's revision, never the aggregate poll revision.
        if (command.playerId != viewerPlayerID || command.promptId != prompt.id || command.messageId?.toLong() != prompt.revision) {
            throw invalid("Stale prompt or mismatched viewer")
        }
        val selectMode = prompt.payload["selectMode"].string ?: ""
        return when (prompt.kind to command.type) {
            "SELECT" to "choose_amount" -> {
                val value = command.amount
                if (selectMode !in setOf("priority", "attackers", "blockers") || value == null) throw invalid("Missing SELECT integer response")
                checkAmount(value, prompt.minimum, prompt.maximum)
                answer("integer", n(value.toLong()), prompt)
            }
            "SELECT" to "choose_target" -> {
                if (selectMode !in setOf("attackers", "blockers")) throw invalid("Not a combat selection")
                val id = single(command.targetIds)
                // Combat metadata is a highlight list. XMage also accepts UUIDs to deselect.
                if (!isUuid(id)) throw invalid("Invalid combat UUID")
                answer("uuid", s(id), prompt)
            }
            "SELECT" to "answer_yes_no" -> {
                if (selectMode !in setOf("attackers", "blockers") || command.confirmed != true) throw invalid("Expected combat completion")
                answer("boolean", b(true), prompt)
            }
            "PLAY_MANA" to "play_mana", "PLAY_X_MANA" to "play_mana", "SELECT" to "play_mana" -> {
                val color = mapOf("W" to "WHITE", "U" to "BLUE", "B" to "BLACK", "R" to "RED", "G" to "GREEN", "C" to "COLORLESS")[command.manaType]
                val player = prompt.payload["manaPlayerId"].string
                if (color == null || !isUuid(player)) throw invalid("Invalid mana symbol or missing player identity")
                answer("mana", jsonObject("playerId" to s(player!!), "manaType" to s(color)), prompt)
            }
            "PLAY_X_MANA" to "play_x_mana" -> {
                val value = command.amount ?: throw invalid("Missing X amount")
                checkAmount(value, prompt.minimum, prompt.maximum)
                answer("integer", n(value.toLong()), prompt)
            }
            "PLAY_MANA" to "cancel_payment", "PLAY_X_MANA" to "cancel_payment" -> {
                if (command.confirmed == true) throw invalid("Payment cancellation cannot confirm payment")
                answer("boolean", b(false), prompt)
            }
            "PLAY_MANA" to "answer_yes_no", "PLAY_X_MANA" to "answer_yes_no" -> {
                if (command.confirmed != false) throw invalid("Expected mana cancellation")
                answer("boolean", b(false), prompt)
            }
            "PLAY_MANA" to "activate_ability", "PLAY_X_MANA" to "activate_ability", "PLAY_MANA" to "make_mana", "PLAY_X_MANA" to "make_mana" -> {
                val id = command.sourceInstanceId ?: command.cardInstanceId
                if (!isUuid(id)) throw invalid("Missing mana source UUID")
                answer("uuid", s(id!!), prompt)
            }
            "MULTI_AMOUNT" to "choose_multi_amount" -> {
                val values = command.amounts; val rows = prompt.payload["allocations"].array
                if (values == null || rows == null || values.size != rows.size) throw invalid("Allocation count mismatch")
                var sum = 0L
                for ((value, row) in values.zip(rows)) {
                    val min = row["min"].integer; val max = row["max"].integer
                    if (min == null || max == null) throw invalid("Malformed allocation bounds")
                    checkAmount(value, min, max)
                    sum = Math.addExact(sum, value.toLong())
                }
                if (sum < prompt.minimum || sum > prompt.maximum) throw invalid("Allocation total out of bounds")
                answer("integers", JsonArray(values.map { n(it.toLong()) }), prompt)
            }
            "MULTI_AMOUNT" to "answer_yes_no" -> {
                if (command.confirmed != false || prompt.payload["options"]["canCancel"].bool != true) throw invalid("Allocation cannot be cancelled")
                answer("boolean", b(false), prompt)
            }
            "AMOUNT" to "choose_amount" -> {
                val amount = command.amount ?: throw invalid("Missing amount")
                checkAmount(amount, prompt.minimum, prompt.maximum)
                answer("integer", n(amount.toLong()), prompt)
            }
            "CHOOSE_PILE" to "choose_pile" -> {
                val pile = command.pile
                if (pile != 1 && pile != 2) throw invalid("Pile must be 1 or 2")
                // HumanPlayer.choosePile / DoOrDie: true selects pile1, false selects pile2.
                answer("boolean", b(pile == 1), prompt)
            }
            "CHOOSE_ABILITY" to "choose_ability", "PICK_ABILITY" to "choose_ability" -> {
                val id = command.abilityId
                if (!isUuid(id) || prompt.payload["abilities"].array?.any { it["id"].string == id } != true) throw invalid("Ability is not a candidate")
                answer("uuid", s(id!!), prompt)
            }
            "CHOOSE_CHOICE" to "choose_empty_special" -> {
                if (prompt.payload["specialEnabled"].bool != true || prompt.payload["specialCanBeEmpty"].bool != true || command.choiceIds != null) {
                    throw invalid("Empty special choice is not available or contains a selected key")
                }
                answer("string", JsonNull, prompt)
            }
            "CHOOSE_CHOICE" to "resolve_choice" -> {
                val key = single(command.choiceIds)
                val normal = prompt.payload["choices"][key].string != null
                val special = prompt.payload["specialEnabled"].bool == true && prompt.payload["specialChoices"][key].string != null
                if (key.toByteArray().size > 8192 || !(normal || special || (key.isEmpty() && prompt.payload["required"].bool == false))) {
                    throw invalid("Choice is not an exact engine key")
                }
                answer("string", s(key), prompt)
            }
            "CHOOSE_MODE" to "choose_mode" -> {
                val id = single(command.modeIds)
                if (!isUuid(id) || prompt.payload["choices"][id].string == null) throw invalid("Mode is not a candidate")
                answer("uuid", s(id), prompt)
            }
            "PICK_TARGET" to "choose_target", "PICK_TARGET" to "choose_card", "PICK_TARGET" to "choose_player",
            "PICK_TARGET" to "search_select", "PICK_TARGET" to "order_items" -> {
                val selections = when (command.type) {
                    "choose_target" -> command.targetIds
                    "choose_card", "search_select" -> command.cardInstanceIds
                    "choose_player" -> command.playerIds
                    else -> command.orderedIds
                }
                val id = single(selections)
                val aliases = prompt.payload["responseAliases"].obj ?: emptyMap()
                if (!selectableTargetIDs(prompt).contains(id) || aliases[id] != null) throw invalid("Target is not a canonical legal choice")
                answer("uuid", s(id), prompt)
            }
            "PICK_TARGET" to "answer_yes_no", "CHOOSE_ABILITY" to "answer_yes_no", "PICK_ABILITY" to "answer_yes_no" -> {
                if (prompt.payload["required"].bool != false || command.confirmed != false) throw invalid("Target choice cannot be cancelled")
                answer("boolean", b(false), prompt)
            }
            "ASK" to "answer_yes_no" -> answer("boolean", b(command.confirmed ?: throw invalid("Missing confirmation")), prompt)
            "SELECT" to "pass_priority" -> {
                if (selectMode != "priority") throw invalid("Not a priority prompt")
                answer("boolean", b(true), prompt)
            }
            "PLAY_MANA" to "resolve_choice" -> {
                if (command.choiceIds != listOf("special")) throw invalid("Invalid special payment token")
                answer("string", s("special"), prompt)
            }
            "SELECT" to "resolve_choice" -> {
                if (command.choiceIds != listOf("special") || prompt.payload["options"]["specialButton"].string == null) throw invalid("Missing special control")
                answer("string", s("special"), prompt)
            }
            "SELECT" to "cast_spell", "SELECT" to "play_land", "SELECT" to "activate_ability", "SELECT" to "make_mana" -> {
                val id = command.sourceInstanceId ?: command.cardInstanceId
                if (selectMode != "priority" || !isUuid(id)) throw invalid("Missing source UUID")
                answer("uuid", s(id!!), prompt)
            }
            else -> throw invalid("Incompatible command ${command.type} for ${prompt.kind}")
        }
    }

    private fun answer(kind: String, value: J, prompt: EnginePrompt): J {
        if (!prompt.responseTypes.contains(kind)) throw invalid("Response type $kind is not accepted")
        return EnginePrompt.answer(kind, value)
    }

    private fun invalid(message: String) = EngineError.InvalidMessage(message)

    private fun validate(prompt: EnginePrompt, viewer: String) {
        if (!isUuid(viewer)) throw invalid("Viewer must be the engine player UUID")
        if (prompt.submitted || prompt.id.isEmpty() || prompt.revision > Int.MAX_VALUE) throw invalid("Prompt is submitted or invalid")
    }

    private fun single(values: List<String>?): String {
        if (values == null || values.size != 1) throw invalid("Exactly one choice is required per upstream prompt")
        return values[0]
    }

    private fun targetIDs(prompt: EnginePrompt): List<String> {
        val values = prompt.payload["candidates"].array ?: throw invalid("Missing target candidates")
        val ids = values.map { value -> value.string?.takeIf(::isUuid) ?: throw invalid("Invalid target UUID") }.toMutableList()
        for (id in (prompt.payload["responseAliases"].obj ?: emptyMap()).keys.sorted()) {
            if (!isUuid(id)) throw invalid("Invalid target alias")
            if (!ids.contains(id)) ids += id
        }
        return ids
    }

    /** Transport candidates also include browseable, nonmatching search cards. */
    private fun selectableTargetIDs(prompt: EnginePrompt): List<String> {
        val candidates = targetIDs(prompt)
        val options = prompt.payload["options"]
        val hasCardSelection = prompt.payload["cards"].array?.isNotEmpty() == true && options["chosenTargets"] != null
        if (options["possibleTargets"] == null && !hasCardSelection) return candidates
        val legal = mutableSetOf<String>()
        for (key in listOf("possibleTargets", "chosenTargets")) {
            val value = options[key] ?: continue
            val values = value.array ?: throw invalid("Malformed target eligibility")
            for (item in values) {
                val id = item.string
                if (!isUuid(id) || !candidates.contains(id)) throw invalid("Invalid selectable target")
                legal += id!!
            }
        }
        for ((alias, base) in prompt.payload["responseAliases"].obj ?: emptyMap()) {
            if (base.string?.let(legal::contains) == true) legal += alias
        }
        return candidates.filter(legal::contains)
    }

    private fun choices(prompt: EnginePrompt): List<Pair<String, String>> {
        val values = prompt.payload["choices"].obj; val order = prompt.payload["choiceOrder"].array
        if (values == null || order == null) throw invalid("Missing ordered choices")
        return order.map { item ->
            val id = item.string; val label = id?.let { values[it].string }
            if (id == null || label == null) throw invalid("Invalid choice key or label")
            id to EngineDisplayText.label(label)
        }
    }

    /** Only CardViews explicitly supplied to this viewer's query enter this mapper. */
    private fun promptCard(value: J): JsonObject {
        val id = value["id"].string
        if (!isUuid(id)) throw invalid("Unrepresentable prompt card")
        val hidden = value["hideInfo"].bool == true
        val name = if (hidden) "Face-down card" else value["displayName"].string ?: value["name"].string ?: "Card details unavailable"
        val types = if (hidden) emptyList() else value["cardTypes"].array?.mapNotNull { it.string } ?: emptyList()
        val card = linkedMapOf<String, J>("name" to s(EngineDisplayText.label(name)), "typeLine" to s(types.joinToString(" ")))
        OnDeviceSnapshotAdapter.printedManaCost(value)?.let { card["manaCost"] = s(it) }
        if (!hidden) value["rules"].array?.mapNotNull { it.string }?.let { card["oracleText"] = s(EngineDisplayText.text(it.joinToString("\n"))) }
        return jsonObject("instanceId" to s(id!!), "card" to JsonObject(card))
    }

    private fun checkAmount(value: Int, min: Long, max: Long) {
        if (value.toLong() < min || value.toLong() > max) throw invalid("Amount out of engine bounds")
    }

    /** Plain display text only. Never render markup or alter the response tokens. */
    private fun plainLabel(value: String?, fallback: String): String = EngineDisplayText.label(value ?: "", fallback)
}

/**
 * Plain-text presentation only: never use these results as engine IDs or answers.
 * No HTML renderer, network requests, attributed links, or hidden-card lookup.
 */
object EngineDisplayText {
    fun label(source: String, fallback: String = ""): String {
        val value = text(source).split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
        return value.ifEmpty { fallback }
    }

    private val knownPhases = mapOf("PRECOMBAT_MAIN" to "Precombat main", "POSTCOMBAT_MAIN" to "Postcombat main",
        "BEGIN_COMBAT" to "Beginning of combat", "END_COMBAT" to "End of combat", "DECLARE_ATTACKERS" to "Declare attackers",
        "DECLARE_BLOCKERS" to "Declare blockers", "FIRST_COMBAT_DAMAGE" to "First-strike damage", "COMBAT_DAMAGE" to "Combat damage",
        "END_TURN" to "End step", "CLEANUP" to "Cleanup", "UNTAP" to "Untap", "UPKEEP" to "Upkeep", "DRAW" to "Draw",
        "BEGINNING" to "Beginning", "COMBAT" to "Combat", "ENDING" to "Ending")

    fun phaseLabel(source: String): String {
        val value = label(source)
        knownPhases[value]?.let { return it }
        // Preserve already-human text; only reformat enum-style all-caps identifiers.
        if (value.isEmpty() || value != value.uppercase() || !value.all { it.isLetter() || it == '_' || it.isWhitespace() }) return value
        val words = value.replace("_", " ").lowercase()
        return words.take(1).uppercase() + words.drop(1)
    }

    private val newline = Regex("\r\n|[\n\r\u000B\u000C\u0085\u2028\u2029]")
    /** Swift `Character.isWhitespace`: the Unicode White_Space set, not only ASCII. */
    private val whitespace = Regex("[\\s\\u0085\\u00A0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000]+")

    fun text(source: String): String {
        var current = source
        // Decode before parsing and reach a fixed point, including nested entities.
        while (true) {
            val next = stripMarkup(decodeEntities(current)).split(newline)
                .map { line -> line.split(whitespace).filter { it.isNotEmpty() }.joinToString(" ") }
                .filter { it.isNotEmpty() }.joinToString("\n")
            if (next == current) return next
            current = next
        }
    }

    private val entity = Regex("&(#(?:[xX][0-9a-fA-F]+|[0-9]+)|[A-Za-z]+);")
    private val named = mapOf("amp" to "&", "lt" to "<", "gt" to ">", "quot" to "\"", "apos" to "'", "nbsp" to " ",
        "ndash" to "–", "mdash" to "—", "hellip" to "…", "lsquo" to "‘", "rsquo" to "’", "times" to "×")

    private fun decodeEntities(source: String): String = entity.replace(source) { match ->
        val token = match.groupValues[1]
        var replacement = named[token]
        if (token.startsWith("#")) {
            val hexadecimal = token.lowercase().startsWith("#x")
            val number = token.drop(if (hexadecimal) 2 else 1).toLongOrNull(if (hexadecimal) 16 else 10)
            if (number != null && number <= 0x10FFFF && number !in 0xD800..0xDFFF) {
                val n = number.toInt()
                // Never introduce control or bidirectional-override characters.
                replacement = if ((n < 32 && n !in listOf(9, 10, 13)) || n in 127..159 || n in 0x202A..0x202E || n in 0x2066..0x2069) ""
                else String(Character.toChars(n))
            }
        }
        replacement ?: match.value
    }

    private val markup = Regex("(?s)<!--.*?(?:-->|$)|</?([A-Za-z][A-Za-z0-9:-]*)\\b(?:[^<>\"']|\"[^\"]*\"|'[^']*')*>")
    private val blocks = setOf("br", "p", "div", "li", "ul", "ol", "table", "tr", "td", "hr")
    private val suppressed = setOf("script", "style", "iframe", "object", "svg", "math", "head", "template")

    private fun stripMarkup(source: String): String {
        val output = StringBuilder()
        var cursor = 0
        val hidden = ArrayDeque<String>()
        for (match in markup.findAll(source)) {
            if (hidden.isEmpty()) output.append(source, cursor, match.range.first)
            cursor = match.range.last + 1
            val tag = match.value
            if (tag.startsWith("<!--")) continue
            val name = match.groupValues[1].lowercase()
            val closing = tag.startsWith("</")
            if (suppressed.contains(name)) {
                if (closing) { if (hidden.lastOrNull() == name) hidden.removeLast() }
                else if (!tag.endsWith("/>")) hidden.addLast(name)
                continue
            }
            if (hidden.isNotEmpty()) continue
            if (blocks.contains(name)) output.append("\n") else if (name == "img") output.append(imageSymbol(tag))
            // Inline/unknown tags contribute no attributes or executable markup.
        }
        if (hidden.isEmpty()) output.append(source, cursor, source.length)
        return output.toString()
    }

    private val attributes = Regex("(?i)\\s+([a-z][a-z0-9-]*)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))")
    private val symbol = Regex("^\\{(?:[0-9]+|[WUBRGCXYZSTQE]|[WUBRGC2]/[WUBRGCP])\\}$")

    private fun imageSymbol(tag: String): String {
        // Only an explicit canonical symbol alt is supported. Never infer a label from src or a URL.
        val matches = attributes.findAll(tag).filter { it.groupValues[1].lowercase() == "alt" }.toList()
        if (matches.size != 1) return ""
        val groups = matches[0].groups
        val value = (2..4).firstNotNullOfOrNull { groups[it]?.value }?.uppercase() ?: return ""
        return if (symbol.matches(value)) value else ""
    }
}
