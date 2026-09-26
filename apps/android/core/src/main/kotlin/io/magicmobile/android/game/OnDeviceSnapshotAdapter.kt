package io.magicmobile.android.game

import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Port of apps/ios/MagicMobile/OnDeviceSnapshotAdapter.swift. Converts only the engine's
 * authenticated, seat-scoped client DTO. Never reconstructs hidden cards.
 */
object OnDeviceSnapshotAdapter {
    private fun s(value: String) = JsonPrimitive(value)
    private fun b(value: Boolean) = JsonPrimitive(value)

    fun snapshot(poll: MatchPoll, expectedSeatID: String, log: List<GameLogEntry> = emptyList()): GameSnapshot {
        val root = poll.snapshot
        val view = root["gameView"]
        val viewer = root["enginePlayerId"].string
        val rawPlayers = view["players"].array
        if (poll.seatID != expectedSeatID || root == null || root["schema"].string != "xmage-gameview-v1" || view == null ||
            !isUuid(viewer) || view["myPlayerId"].string != viewer || rawPlayers == null || rawPlayers.size !in 2..4) {
            throw EngineError.InvalidMessage("Missing or mismatched seat-scoped game view")
        }
        viewer!!
        val ids = rawPlayers.mapNotNull { it["playerId"].string }
        if (ids.size != rawPlayers.size || ids.toSet().size != ids.size || !ids.contains(viewer) || !ids.all(::isUuid)) {
            throw EngineError.InvalidMessage("Invalid engine player identities")
        }
        val players = mutableListOf<J>()
        val enginePlayers = mutableListOf<J>()
        for (player in rawPlayers) {
            val id = player["playerId"].string!!
            if (player["life"].integer == null || player["handCount"].integer == null || player["libraryCount"].integer == null ||
                player["name"].string == null) throw EngineError.InvalidMessage("Incomplete player state")
            val hand = if (id == viewer) view["myHand"] else root["controlledPlayerViews"][id]["myHand"]
            val zones = linkedMapOf<String, J>()
            for (zone in listOf("battlefield", "graveyard", "exile")) {
                val mapped = cards(player[zone])
                zones[zone] = JsonArray(if (zone == "battlefield") combatCards(mapped, view["combat"]) else mapped)
            }
            zones["command"] = JsonArray(cards(player["commandList"]))
            zones["hand"] = JsonArray(cards(hand))
            zones["library"] = JsonArray(emptyList())
            zones["stack"] = JsonArray(emptyList())
            zones["handCount"] = player["handCount"] ?: JsonNull
            zones["libraryCount"] = player["libraryCount"] ?: JsonNull
            val poison = (player["counters"].array ?: emptyList()).firstOrNull { it["name"].string?.lowercase() == "poison" }?.get("count") ?: JsonPrimitive(0)
            val commanders = (root["commanders"].obj ?: emptyMap()).toSortedMap().mapNotNull { (cardID, metadata) ->
                val fields = metadata.obj?.toMutableMap()
                if (metadata["ownerPlayerId"].string != id || fields == null) return@mapNotNull null
                fields["id"] = s(cardID)
                val visibleCard = zones.values.mapNotNull { it.array }.flatten().firstOrNull { it["instanceId"].string == cardID }
                if (fields["name"] == null) visibleCard?.get("card")?.get("name")?.let { fields["name"] = it }
                JsonObject(fields)
            }
            // Partners have independent tax and damage. Never combine them into one HUD value.
            val singleCommander = if (commanders.size == 1) commanders.first() else null
            val counters = linkedMapOf<String, J>()
            for (counter in player["counters"].array ?: emptyList()) {
                val name = counter["name"].string ?: continue
                val count = counter["count"].integer ?: continue
                counters[name] = JsonPrimitive(count)
            }
            val fields = linkedMapOf<String, J>(
                "playerId" to s(id), "displayName" to player["name"]!!, "life" to player["life"]!!,
                "poison" to poison, "commanderTax" to (singleCommander?.get("commanderTax") ?: JsonPrimitive(0)),
                "counters" to JsonObject(counters),
                "monarch" to (player["monarch"] ?: JsonNull), "initiative" to (player["initiative"] ?: JsonNull),
                "commanderTaxKnown" to b(singleCommander?.get("commanderTax").integer != null),
                "commanderDamage" to (singleCommander?.get("damageToPlayers") ?: JsonNull), "commanders" to JsonArray(commanders),
                "manaPool" to manaPool(player["manaPool"]), "zones" to JsonObject(zones))
            // Players XMage removed (conceded or lost in a pod), and which seats are AI.
            fields["hasLeft"] = player["hasLeft"] ?: b(false)
            fields["isHuman"] = player["isHuman"] ?: JsonNull
            players += JsonObject(fields)
            val skips = linkedMapOf<String, J>()
            for (key in listOf("passedTurn", "passedUntilEndOfTurn", "passedUntilNextMain", "passedUntilStackResolved", "passedAllTurns", "passedUntilEndStepBeforeMyTurn")) {
                skips[key] = player[key] ?: b(false)
            }
            enginePlayers += jsonObject(
                "playerId" to s(id), "xmagePlayerId" to s(id), "name" to player["name"]!!,
                "active" to (player["isActive"] ?: b(false)), "hasPriority" to (player["hasPriority"] ?: b(false)),
                "timerActive" to (player["timerActive"] ?: b(false)), "skipState" to JsonObject(skips),
                "manaPool" to manaPool(player["manaPool"]), "command" to zones["command"]!!,
                "zones" to jsonObject("battlefield" to zones["battlefield"]!!, "graveyard" to zones["graveyard"]!!,
                    "exile" to zones["exile"]!!, "sideboard" to JsonArray(cards(player["sideboard"]))))
        }
        val stackMap = view["stack"].obj ?: emptyMap()
        val order = root["stackOrder"].array?.mapNotNull { it.string } ?: if (stackMap.size <= 1) stackMap.keys.toList() else emptyList()
        if (order.size != stackMap.size || order.toSet() != stackMap.keys) {
            throw EngineError.InvalidMessage("The engine did not supply an unambiguous stack order")
        }
        val stack = order.map { id ->
            val item = stackMap[id]!!
            val isSpell = item["mageObjectType"].string == "SPELL"
            val source = item["sourceCard"] ?: if (isSpell) item else JsonNull
            val fields = linkedMapOf<String, J>(
                "id" to s(id), "objectId" to s(id), "objectType" to (item["mageObjectType"] ?: JsonNull),
                "name" to (item["displayName"] ?: item["name"] ?: s("Stack object")),
                "rulesText" to s((item["rules"].array ?: emptyList()).mapNotNull { it.string }.joinToString("\n")),
                "targetIds" to (item["targets"] ?: JsonArray(emptyList())), "paid" to (item["paid"] ?: JsonNull))
            if (source !is JsonNull) {
                fields["sourceCard"] = card(source)
                (source["displayName"] ?: source["name"])?.let { fields["sourceName"] = it }
                // A spell's stack UUID is not necessarily its physical card UUID.
                if (!isSpell) source["id"]?.let { fields["sourceInstanceId"] = it }
            }
            JsonObject(fields) as J
        }
        val combat = (view["combat"].array ?: emptyList()).map { group ->
            val defender = group["defenderId"].string ?: throw EngineError.InvalidMessage("Missing combat defender")
            val kind: J = if (ids.contains(defender)) s("player") else JsonNull
            jsonObject("defenderId" to s(defender), "defenderName" to (group["defenderName"] ?: s(defender)),
                "defenderKind" to kind, "blocked" to (group["isBlocked"] ?: b(false)),
                "attackers" to JsonArray(combatCards(cards(group["attackers"]), view["combat"])),
                "blockers" to JsonArray(combatCards(cards(group["blockers"]), view["combat"]))) as J
        }
        val exileZones = namedZones(root["namedExiles"], "exile")
        val revealed = namedZones(view["revealed"], "revealed")
        val companions = namedZones(view["companion"], "companion")
        val lookedAt = disclosedGroups(root["authorizedLookedAt"], "looked-at") + disclosedGroups(root["authorizedOpponentHands"], "controlled-hand")
        val extraZones = listOf("exile" to exileZones, "revealed" to revealed, "looked_at" to lookedAt, "companion" to companions)
            .map { (name, groups) -> name to groups.flatMap { it["cards"].array ?: emptyList() } } +
            listOf("stack" to stack.mapNotNull { it["sourceCard"] })
        val playability = playableObjects(view, players, extraZones, poll.prompt, viewer)
        val xmage = jsonObject(
            "schemaVersion" to JsonPrimitive(1), "gameId" to s(poll.matchID), "bridgeRevision" to JsonPrimitive(poll.revision),
            "xmageCycle" to (view["gameCycle"] ?: JsonNull), "callbackCoverage" to JsonArray(emptyList()),
            "players" to JsonArray(enginePlayers), "stack" to JsonArray(stack), "combat" to JsonArray(combat),
            "exileZones" to JsonArray(exileZones), "revealed" to JsonArray(revealed), "lookedAt" to JsonArray(lookedAt),
            "companion" to JsonArray(companions), "playableObjects" to JsonArray(playability.first),
            "panels" to jsonObject("stack" to b(stack.isNotEmpty()), "command" to b(true), "graveyard" to b(true), "exile" to b(true),
                "revealed" to b(revealed.isNotEmpty()), "lookedAt" to b(lookedAt.isNotEmpty()), "search" to b(lookedAt.isNotEmpty())))
        val priority = rawPlayers.firstOrNull { it["hasPriority"].bool == true }?.get("playerId")
        val decodedPlayers = EngineJson.format.decodeFromJsonElement(ListSerializer(PlayerGameState.serializer()), JsonArray(players))
        val decodedXmage = EngineJson.format.decodeFromJsonElement(XmageMobileSnapshot.serializer(), xmage)
        val allCards = decodedPlayers.flatMap { it.zones.hand + it.zones.battlefield + it.zones.graveyard + it.zones.exile + it.zones.command } +
            decodedXmage.stack.mapNotNull { it.sourceCard } +
            (decodedXmage.exileZones + decodedXmage.revealed + decodedXmage.lookedAt + decodedXmage.companion).flatMap { it.cards }
        val prompt = poll.prompt?.takeUnless { it.submitted }
        val presentation = prompt?.let {
            var attackerID: String? = null
            if (it.kind == "SELECT" && it.payload["selectMode"].string == "attackers") {
                val active = view["activePlayerId"].string
                val controlled = root["controlledPlayerViews"][active ?: ""]
                if (active == null || !ids.contains(active) ||
                    !(active == viewer || (controlled["myPlayerId"].string == active && controlled["activePlayerId"].string == active))) {
                    throw EngineError.InvalidMessage("Missing or unauthorized acting attacker identity")
                }
                // ViewProjector emits this map only for the current, non-nested controller.
                attackerID = active
            }
            OnDevicePromptAdapter.presentation(it, viewer, allCards, decodedPlayers, attackerID)
        }
        val cardActions = EngineJson.format.decodeFromJsonElement(ListSerializer(LegalAction.serializer()), JsonArray(playability.second))
        return GameSnapshot(
            id = poll.matchID, source = "xmage-ondevice", activePlayerId = view["activePlayerId"].string,
            phase = view["phase"].string ?: poll.phase, step = view["step"].string,
            turn = (view["turn"].integer ?: 0).toInt(), priorityPlayerId = priority.string,
            waitingOnPlayerId = if (prompt == null) null else viewer, promptText = presentation?.envelope?.message,
            players = decodedPlayers, log = log, legalActions = cardActions + (presentation?.legalActions ?: emptyList()),
            promptEnvelopeV2 = presentation?.envelope, xmage = decodedXmage,
            bridgeRevision = poll.revision.toInt(), xmageCycle = view["gameCycle"].integer?.toInt(),
            pendingStatus = if (poll.prompt?.submitted == true) "waiting_for_xmage" else null,
            manaPayment = presentation?.manaPayment,
            gameStatus = if (root["outcome"]["ended"].bool == true) GameStatus.COMPLETED else GameStatus.IN_PROGRESS,
            winnerPlayerIds = root["outcome"]["winnerPlayerIds"].array?.mapNotNull { it.string },
            viewerPlayerId = viewer)
    }

    /** Combat membership comes only from the public GameView groups, never card-type guesses. */
    private fun combatCards(cards: List<J>, groups: J?): List<J> = cards.map { card ->
        val id = card["instanceId"].string
        val fields = card.obj?.toMutableMap()
        if (id == null || fields == null) return@map card
        var attacking = false
        val blocking = sortedSetOf<String>()
        for (group in groups.array ?: emptyList()) {
            val attackers = cardValues(group["attackers"]).mapNotNull { it["id"].string }
            attacking = attacking || attackers.contains(id)
            if (cardValues(group["blockers"]).any { it["id"].string == id }) blocking.addAll(attackers)
        }
        fields["isAttacking"] = b(attacking)
        fields["blocking"] = JsonArray(blocking.map(::s))
        JsonObject(fields)
    }

    private fun namedZones(value: J?, prefix: String): List<J> = (value.array ?: emptyList()).mapIndexed { index, zone ->
        jsonObject("id" to (zone["id"] ?: s("$prefix:$index")), "name" to (zone["name"] ?: s(capitalizedWords(prefix))),
            "cards" to JsonArray(cards(zone["cards"])))
    }

    private fun disclosedGroups(value: J?, prefix: String): List<J> = (value.obj ?: emptyMap()).toSortedMap().map { (name, contents) ->
        jsonObject("id" to s("$prefix:$name"), "name" to s(name), "cards" to JsonArray(cards(contents)))
    }

    private fun cards(value: J?): List<J> = cardValues(value).map(::card)

    private fun cardValues(value: J?): List<J> = value.array ?: value.obj?.toSortedMap()?.values?.toList() ?: emptyList()

    private val colorNames = listOf("white" to "W", "blue" to "U", "black" to "B", "red" to "R", "green" to "G")

    private fun card(value: J): J {
        val id = value["id"].string
        if (!isUuid(id)) throw EngineError.InvalidMessage("Card view has no engine UUID")
        // Do not consult original, source images, or a catalogue to undo an upstream redaction.
        val hidden = value["hideInfo"].bool == true
        val name = if (hidden) "Face-down card" else value["displayName"].string ?: value["name"].string ?: "Card details unavailable"
        fun strings(key: String) = if (hidden) emptyList() else (value[key].array ?: emptyList()).mapNotNull { it.string }
        var typeLine = (strings("superTypes") + strings("cardTypes")).joinToString(" ") { capitalizedWords(it) }
        val subs = strings("subTypes")
        if (subs.isNotEmpty()) typeLine += " — " + subs.joinToString(" ") { capitalizedWords(it) }
        val rules = if (hidden) "" else (value["rules"].array ?: emptyList()).mapNotNull { it.string }.joinToString("\n")
        val tokenIdentityVisible = !hidden && value["faceDown"].bool != true
        val isToken = value["isToken"].bool == true
        val hasTokenColors = tokenIdentityVisible && isToken && colorNames.all { value["color"][it.first].bool != null }
        val tokenColors: J = if (hasTokenColors) JsonArray(colorNames.filter { value["color"][it.first].bool == true }.map { s(it.second) }) else JsonNull
        val sourceArt: J = if (tokenIdentityVisible && isToken && value["copy"].bool == true && value["copySourceArtworkName"].string == name &&
            value["name"].string == name && permitsSourceName(name)) s(name) else JsonNull
        val template = value["tokenArtwork"]
        val baseName = template["name"].string
        fun baseStrings(key: String) = (template[key].array ?: emptyList()).mapNotNull { it.string }
        val hasBaseColors = colorNames.all { template["color"][it.first].bool != null }
        val baseColors = colorNames.filter { template["color"][it.first].bool == true }.map { it.second }
        var baseTypeLine = (baseStrings("superTypes") + baseStrings("cardTypes")).joinToString(" ") { capitalizedWords(it) }
        val baseSubs = baseStrings("subTypes")
        if (baseSubs.isNotEmpty()) baseTypeLine += " — " + baseSubs.joinToString(" ") { capitalizedWords(it) }
        val baseArt: J = if (tokenIdentityVisible && isToken && baseName == name && hasBaseColors && baseTypeLine.isNotEmpty() &&
            template["rules"].array != null && template["power"].string != null && template["toughness"].string != null) {
            jsonObject("name" to s(name), "typeLine" to s(baseTypeLine),
                "oracleText" to s((template["rules"].array ?: emptyList()).mapNotNull { it.string }.joinToString("\n")),
                "power" to (template["power"] ?: JsonNull), "toughness" to (template["toughness"] ?: JsonNull),
                "colors" to JsonArray(baseColors.map(::s)))
        } else JsonNull
        val result = linkedMapOf<String, J>("instanceId" to s(id!!), "card" to jsonObject(
            "name" to s(name), "typeLine" to s(typeLine), "oracleText" to s(rules),
            "manaCost" to (printedManaCost(value)?.let(::s) ?: JsonNull),
            "isToken" to (if (tokenIdentityVisible) value["isToken"].bool?.let(::b) ?: JsonNull else JsonNull),
            "tokenColors" to tokenColors, "copySourceArtworkName" to sourceArt, "tokenArtwork" to baseArt))
        for (key in listOf("tapped", "summoningSickness", "damage", "phasedIn")) value[key]?.let { result[key] = it }
        value["attachedTo"]?.let { result["attachedToInstanceId"] = it }
        result["cardIcons"] = JsonArray((value["cardIcons"].array ?: emptyList()).map { icon ->
            val type = icon["cardIconType"].string ?: ""
            jsonObject("iconType" to (icon["cardIconType"] ?: s("")),
                "category" to (icon["category"] ?: XmageCardIcon.nativeCategory(type)?.let(::s) ?: JsonNull),
                "resourceName" to (icon["resourceName"] ?: JsonNull), "text" to (icon["text"] ?: JsonNull), "hint" to (icon["hint"] ?: JsonNull))
        })
        if (!hidden) {
            value["power"].string?.takeIf { it.isNotEmpty() }?.let { result["reportedPower"] = s(it) }
            value["toughness"].string?.takeIf { it.isNotEmpty() }?.let { result["reportedToughness"] = s(it) }
        }
        value["counters"].array?.let { counters ->
            val mapped = linkedMapOf<String, J>()
            for (counter in counters) counter["name"].string?.let { mapped[it] = counter["count"] ?: JsonNull }
            result["counters"] = JsonObject(mapped)
        }
        return JsonObject(result)
    }

    private fun manaPool(value: J?): J = JsonObject(listOf("W" to "white", "U" to "blue", "B" to "black", "R" to "red", "G" to "green", "C" to "colorless")
        .associate { (symbol, name) -> symbol to (value[name] ?: JsonPrimitive(0)) })

    /** Swift `NativeDeckArtwork.permitsSourceName`. */
    fun permitsSourceName(name: String): Boolean = name.trim().lowercase() !in
        setOf("", "hidden card", "face-down card", "face down card", "face-down", "face down", "card details unavailable")

    /**
     * The pinned CardView stores ordered symbol arrays, not a `manaCost` string. Keep the two
     * printed halves separate; never consult rules, mana value or payment text.
     */
    fun printedManaCost(value: J): String? {
        if (value["hideInfo"].bool == true || value["faceDown"].bool == true) return null
        val halves = mutableListOf<String>()
        for (key in listOf("manaCostLeftStr", "manaCostRightStr")) {
            val raw = value[key] ?: continue
            val symbols = raw.array
            if (symbols == null || !symbols.all { it.string != null }) return null
            val cost = symbols.mapNotNull { it.string }.joinToString("")
            if (cost.isNotEmpty()) halves += cost
        }
        return if (halves.isEmpty()) null else halves.joinToString(" // ")
    }

    private fun playableObjects(view: J, players: List<J>, extraZones: List<Pair<String, List<J>>>, prompt: EnginePrompt?, viewer: String): Pair<List<J>, List<J>> {
        val objects = mutableListOf<J>()
        val actions = mutableListOf<J>()
        val known = HashMap<String, Pair<J, String>>()
        for (player in players) {
            for ((zone, contents) in player["zones"].obj ?: emptyMap()) {
                for (card in contents.array ?: emptyList()) card["instanceId"].string?.let { known[it] = card to zone }
            }
        }
        for ((zone, cards) in extraZones) for (card in cards) {
            val id = card["instanceId"].string ?: continue
            if (known[id] == null) known[id] = card to zone
        }
        val categories = listOf("basicPlayAbilities" to "play_land", "basicCastAbilities" to "cast_spell",
            "basicManaAbilities" to "make_mana", "other" to "activate_ability")
        for ((id, stats) in (view["canPlayObjects"]["objects"].obj ?: emptyMap()).toSortedMap()) {
            val (card, zone) = known[id] ?: continue
            val abilities = mutableListOf<J>()
            val activeCategories = mutableListOf<J>()
            for ((category, commandType) in categories) {
                val rows = stats[category].array ?: emptyList()
                if (rows.isNotEmpty()) activeCategories += s(category)
                for (row in rows) {
                    val abilityID = row["id"].string; val label = row["value"].string
                    if (abilityID == null || label == null) throw EngineError.InvalidMessage("Incomplete engine playable ability")
                    abilities += jsonObject("id" to s(abilityID), "label" to s(EngineDisplayText.label(label)), "category" to s(category))
                }
                if (rows.isEmpty() || prompt == null || prompt.submitted || !prompt.responseTypes.contains("uuid")) continue
                val priority = prompt.kind == "SELECT" && prompt.payload["selectMode"].string == "priority"
                val paying = prompt.kind in setOf("PLAY_MANA", "PLAY_X_MANA")
                // New native payloads distinguish mana abilities inside `other`. Never guess from a label.
                val manaRows = rows.filter { it["manaAbility"].bool ?: (category == "basicManaAbilities") }
                val nonmanaRows = rows.filterNot { it["manaAbility"].bool ?: (category == "basicManaAbilities") }
                // Modal/split spell abilities live in upstream's `other` bucket; use native type metadata.
                val spellRows = nonmanaRows.filter { it["spellAbility"].bool ?: (category == "basicCastAbilities") }
                val otherRows = nonmanaRows.filterNot { it["spellAbility"].bool ?: (category == "basicCastAbilities") }
                for ((actionType, actionRows) in listOf("make_mana" to manaRows, "cast_spell" to spellRows, commandType to otherRows)) {
                    if (actionRows.isEmpty() || !(priority || (paying && actionType == "make_mana"))) continue
                    val baseID = "${prompt.id}:$category:$id" + if (actionType == commandType) "" else ":$actionType"
                    // One action per ability, carrying the engine's ability ID so the session can answer XMage's
                    // follow-up "which ability" prompt (MDFC land/spell, split halves, adventures) itself.
                    for (row in actionRows) {
                        val abilityID = row["id"].string!!
                        actions += jsonObject(
                            "id" to s(if (actionRows.size > 1) "$baseID:$abilityID" else baseID),
                            "type" to s(actionType), "playerId" to s(viewer),
                            "label" to s(fullAbilityLabel(row["value"].string!!, card["card"]["oracleText"].string)),
                            "cardInstanceId" to s(id), "sourceInstanceId" to s(id), "sourceZone" to s(zone),
                            "cardName" to (card["card"]["name"] ?: s("Card")),
                            "promptId" to s(prompt.id), "messageId" to JsonPrimitive(prompt.revision), "abilityId" to s(abilityID))
                    }
                }
            }
            if (abilities.isNotEmpty()) {
                objects += jsonObject("sourceInstanceId" to s(id), "sourceZone" to s(zone), "cardName" to (card["card"]["name"] ?: s("Card")),
                    "categories" to JsonArray(activeCategories), "abilities" to JsonArray(abilities))
            }
        }
        return objects to actions
    }

    /**
     * XMage shortens playable-ability labels ("… only to cast a crea..."). When the shortened
     * text starts exactly one line of the card's visible rules, show that whole line.
     */
    fun fullAbilityLabel(raw: String, rules: String?): String {
        val label = EngineDisplayText.label(raw)
        var stem = when {
            label.endsWith("...") -> label.dropLast(3)
            label.endsWith("…") -> label.dropLast(1)
            else -> return label
        }
        stem = stem.trim()
        if (stem.length < 4 || rules == null) return label
        val lines = rules.split('\n', '\r').filter { it.isNotEmpty() }.map { EngineDisplayText.label(it) }
        val matches = lines.filter { it.length > stem.length && it.startsWith(stem) }
        return if (matches.size == 1) matches[0] else label
    }
}
