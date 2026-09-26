package io.magicmobile.android.game

import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test
import java.io.File

/**
 * The Android port must adapt the same engine polls and prompt cases to exactly what iOS
 * produces. Goldens come from apps/ios/MagicMobileTests/ParityGoldenTests.swift; this summary
 * mirrors its ParitySummary field for field.
 */
class ParityGoldenTest {
    private val repo = File(System.getProperty("magicmobile.repo") ?: "../../..")
    private val parity = File(repo, "apps/android/core/src/test/resources/parity")
    private val fixtures = File(repo, "apps/ios/MagicMobileTests/Fixtures/OnDevice")

    @Test fun engineFixturesMatchIOS() {
        val names = fixtures.listFiles { f -> f.name.endsWith(".json") && f.name != "manifest.json" }!!.map { it.name }.sorted()
        check(names.isNotEmpty())
        for (name in names) {
            val poll = MatchPoll(EngineJson.decode(File(fixtures, name).readBytes()))
            val log = OnDeviceMessageLog().apply { ingest(poll) }
            val snapshot = OnDeviceSnapshotAdapter.snapshot(poll, poll.seatID, log.entries)
            val summary = ParitySummary.snapshot(snapshot).toMutableMap()
            summary["answers"] = JsonArray(ParitySummary.answers(snapshot, poll.prompt))
            compare(JsonObject(summary), "fixture-$name")
        }
    }

    @Test fun promptCasesMatchIOS() {
        val root = Json.parseToJsonElement(File(parity, "prompt-cases.json").readText())
        val viewer = root["viewer"].string!!
        val players = EngineJson.format.decodeFromJsonElement(ListSerializer(PlayerGameState.serializer()), root["players"]!!)
        val cards = players.flatMap { it.zones.hand + it.zones.battlefield + it.zones.graveyard + it.zones.exile + it.zones.command }
        val results = root["cases"].array!!.map { item ->
            val prompt = EnginePrompt(item["prompt"]!!)
            val result = linkedMapOf<String, J>("name" to (item["name"] ?: JsonPrimitive("")))
            try {
                val view = OnDevicePromptAdapter.presentation(prompt, viewer, cards, players)
                result["envelope"] = ParitySummary.envelope(view.envelope)
                result["actions"] = JsonArray(view.legalActions.map(ParitySummary::action))
                result["manaPayment"] = view.manaPayment?.let { jsonObject("active" to JsonPrimitive(it.active), "remainingText" to ParitySummary.o(it.remainingText)) } ?: JsonNull
            } catch (error: Exception) { result["error"] = JsonPrimitive(ParitySummary.message(error)) }
            result["answers"] = JsonArray((item["commands"].array ?: emptyList()).map { fields ->
                val command = ParitySummary.command(fields, "match", viewer, prompt.id, prompt.revision.toInt())
                ParitySummary.answer(command, prompt, viewer)
            })
            JsonObject(result)
        }
        compare(jsonObject("cases" to JsonArray(results)), "prompt-cases.json")
    }

    @Test fun textFormattingMatchesIOS() {
        val root = Json.parseToJsonElement(File(parity, "text-cases.json").readText())
        val logs = root["log"].array!!.map { message ->
            val presentation = GameLogPresentation(message.string!!)
            jsonObject("plain" to JsonPrimitive(presentation.plainText), "spans" to JsonArray(presentation.spans.map { span ->
                jsonObject("text" to JsonPrimitive(span.text), "role" to JsonPrimitive(span.role.name.lowercase()), "bold" to JsonPrimitive(span.bold),
                    "italic" to JsonPrimitive(span.italic), "card" to ParitySummary.o(span.cardReference?.name))
            }))
        }
        val rules = root["rules"].array!!.map { item ->
            val presentation = GameRulesPresentation(item["source"].string ?: "", item["cardName"].string, item["hidden"].bool ?: false)
            val symbols = GameRulesSymbols(presentation)
            jsonObject("plain" to JsonPrimitive(presentation.plainText), "spoken" to JsonPrimitive(symbols.accessibilityText),
                "fragments" to JsonArray(symbols.fragments.map { jsonObject("literal" to JsonPrimitive(it.literal), "code" to ParitySummary.o(it.code)) }))
        }
        val prompts = root["prompts"].array!!.map { JsonPrimitive(PromptDisplayText.clean(it.string!!)) }
        compare(jsonObject("log" to JsonArray(logs), "rules" to JsonArray(rules), "prompts" to JsonArray(prompts)), "text-cases.json")
    }

    /** combat-cases.json: keyword extraction, combat badges, first-strike beats and log reasons (ParityGoldenTests.swift). */
    @Test fun combatClarityCasesOnBothPlatforms() {
        val root = Json.parseToJsonElement(File(parity, "combat-cases.json").readText())
        fun strings(value: J?): List<String>? = (value as? JsonArray)?.map { it.string!! }
        fun keywords(value: J?): List<CombatKeyword> = (strings(value) ?: emptyList()).mapNotNull { CombatKeyword.of(it) }
        for (item in root["keywords"].array!!) {
            val icons = strings(item["icons"])?.map { XmageCardIcon(it) }
            assertEquals("keywords · ${item["name"].string}", strings(item["expect"]),
                CombatKeyword.of(icons, item["rules"].string).map { it.rawValue })
        }
        for (item in root["badges"].array!!) {
            val at = "badges · ${item["name"].string}"
            val plan = CombatKeywordBadgePlan(keywords(item["keywords"]), (item["width"] as JsonPrimitive).content.toFloat(),
                (item["height"] as JsonPrimitive).content.toFloat())
            assertEquals(at, strings(item["visible"]), plan.visible.map { it.rawValue })
            assertEquals(at, (item["hidden"] as JsonPrimitive).content.toInt(), plan.hiddenCount)
            assertEquals(at, strings(item["labels"]), plan.visible.map { plan.label(it) })
        }
        fun state(json: J): BoardFXState {
            val cards = json["cards"].array!!.map { card ->
                val id = card["id"].string!!
                BoardFXState.Card(id, card["player"].string!!, BoardFXZone.valueOf((card["zone"].string ?: "battlefield").uppercase()), id,
                    BoardFXTint.RED, 0, 0, card["attacking"].bool ?: false, strings(card["blocking"]) ?: emptyList(),
                    keywords = keywords(card["keywords"]).toSet())
            }
            val lives = (json["lives"] as JsonObject).mapValues { (it.value as JsonPrimitive).content.toInt() }
            val defenders = (json["defenders"] as? JsonObject)?.mapValues { it.value.string!! } ?: emptyMap()
            return BoardFXState("combat", json["step"].string!!, lives, cards.associateBy { it.id }, defenders = defenders,
                blockedAttackers = (strings(json["blocked"]) ?: emptyList()).toSet())
        }
        fun summary(event: BoardFXEvent): String = when (event) {
            BoardFXEvent.FirstStrikeBeat -> "first-strike"
            is BoardFXEvent.CombatStrike -> {
                val aim = when (val target = event.target) { is BoardFXStrikeTarget.Card -> "card:${target.id}"; is BoardFXStrikeTarget.Player -> "player:${target.id}" }
                "strike ${event.attackerID} -> $aim ${if (event.firstStrike) "first" else "regular"}"
            }
            is BoardFXEvent.DamageMarked -> "damage ${event.cardID} ${event.amount}"
            is BoardFXEvent.LeftBattlefield -> "left ${event.cardID} ${event.to?.name?.lowercase() ?: "nil"}"
            is BoardFXEvent.LifeChanged -> "life ${event.playerID} ${event.delta}"
            else -> "other"
        }
        for (item in root["beats"].array!!) {
            val at = "beats · ${item["name"].string}"
            val events = BoardEventDiffer.events(state(item["old"]!!), state(item["new"]!!))
            assertEquals(at, strings(item["events"]), events.map(::summary))
            for ((level, key) in listOf(BoardFXLevel.FULL to "full", BoardFXLevel.REDUCED to "reduced")) {
                val planned = BoardFXScheduler.schedule(events, level).map {
                    "${summary(it.event)} @${"%.3f".format(java.util.Locale.US, it.delay)} +${"%.3f".format(java.util.Locale.US, it.duration)}"
                }
                assertEquals("$at · $key", strings(item[key]), planned)
            }
        }
        val log = root["log"]!!
        val fighters = (log["fighters"] as JsonObject).mapValues { (_, value) ->
            CombatLogReasons.Fighter(value["name"].string!!, keywords(value["keywords"]).toSet())
        }
        for (item in log["cases"].array!!) {
            val step = CombatLogReasons.DamageStep.of(item["previous"].string, item["step"].string!!)
            assertEquals("log · ${item["name"].string}", item["reason"].string, CombatLogReasons.reason(item["message"].string!!, step, fighters))
        }
    }

    /** Shared behavior cases: both apps must meet every expectation in the file (no goldens). */
    @Test fun opponentFocusCasesOnBothPlatforms() = runSeatCases("focus-cases.json")

    @Test fun spectatorSeatCasesOnBothPlatforms() = runSeatCases("spectator-cases.json")

    @Test fun priorityStatusCasesOnBothPlatforms() {
        val root = Json.parseToJsonElement(File(parity, "focus-cases.json").readText())
        val base = root["base"] as JsonObject
        val cases = root["status"].array!!
        check(cases.isNotEmpty())
        for (item in cases) {
            val json = base.toMutableMap()
            json["turn"] = item["turn"] ?: JsonNull
            json["priorityPlayerId"] = item["priority"] ?: JsonNull
            json["waitingOnPlayerId"] = item["waitingOn"] ?: JsonNull
            val snapshot = EngineJson.format.decodeFromJsonElement(GameSnapshot.serializer(), JsonObject(json))
            assertEquals("status · ${item["name"].string}", item["text"].string, snapshot.priorityStatusText)
        }
    }

    /**
     * Runs focus-cases.json or spectator-cases.json the way NativeGameView applies them: every
     * poll feeds BoardFocusTracker, then BoardOpponentFocus.snapshot picks the seats.
     */
    private fun runSeatCases(name: String) {
        val root = Json.parseToJsonElement(File(parity, name).readText())
        val base = root["base"] as JsonObject
        val cases = root["cases"].array!!
        check(cases.isNotEmpty())
        for (item in cases) {
            val state = linkedMapOf<String, J>("followTurns" to JsonPrimitive(item["followTurns"].bool ?: true))
            var tracker = BoardFocusTracker()
            (item["steps"].array ?: emptyList()).forEachIndexed { index, step ->
                val at = "$name · ${item["name"].string} · step ${index + 1}"
                val fields = step as JsonObject
                for (key in SeatCase.stateKeys) fields[key]?.let { state[key] = it }
                val snapshot = EngineJson.format.decodeFromJsonElement(GameSnapshot.serializer(), SeatCase.snapshot(base, state))
                fields["tap"].string?.let { tracker = tracker.select(it) }
                tracker = tracker.observe(snapshot, state["followTurns"].bool ?: true)
                val board = BoardOpponentFocus.snapshot(snapshot, tracker.focusedID)
                if (fields.containsKey("top")) assertEquals(at, fields["top"].string, board.opponent?.playerId)
                fields["topChoices"].array?.let { ids -> assertEquals(at, ids.map { it.string }, BoardOpponentFocus.opponents(board).map { it.playerId }) }
                fields["seat"].string?.let { assertEquals(at, it, board.seat?.playerId) }
                fields["seatHand"].array?.let { ids -> assertEquals(at, ids.map { it.string }, BoardOpponentFocus.seatHand(board).map { it.instanceId }) }
                fields["seatHandCount"].integer?.let { assertEquals(at, it.toInt(), board.seat?.zones?.visibleHandCount) }
                fields["viewer"].string?.let {
                    assertEquals(at, it, board.viewerID)
                    assertEquals(at, it, board.human?.playerId)
                }
                fields["viewerLabel"].string?.let { assertEquals(at, it, board.playerLabel(board.viewerID)) }
                fields["seatLabel"].string?.let { assertEquals(at, it, board.playerLabel(board.seatID)) }
                fields["spectating"].bool?.let { assertEquals(at, it, board.isSpectating) }
                fields["title"].string?.let { assertEquals(at, it, SpectatorSeatPresentation.title(board)) }
                fields["detail"].string?.let { assertEquals(at, it, SpectatorSeatPresentation.detail(board)) }
            }
        }
    }

    private fun compare(actual: J, name: String) {
        val expected = Json.parseToJsonElement(File(parity, "golden/$name").readText())
        val difference = difference(expected, actual, name)
        if (difference != null) fail("Android differs from iOS: $difference")
        assertEquals(expected, actual)
    }

    private fun difference(expected: J, actual: J, path: String): String? {
        if (expected is JsonObject && actual is JsonObject) {
            for (key in (expected.keys + actual.keys).sorted()) {
                if (!expected.containsKey(key)) return "$path.$key only on Android: ${actual[key]}"
                if (!actual.containsKey(key)) return "$path.$key missing on Android (iOS: ${expected[key]})"
                difference(expected[key]!!, actual[key]!!, "$path.$key")?.let { return it }
            }
            return null
        }
        if (expected is JsonArray && actual is JsonArray) {
            if (expected.size != actual.size) return "$path: iOS has ${expected.size} items, Android ${actual.size}"
            expected.indices.forEach { i -> difference(expected[i], actual[i], "$path[$i]")?.let { return it } }
            return null
        }
        return if (expected == actual) null else "$path: iOS $expected, Android $actual"
    }
}

/** Builds a case step's snapshot from the file's base (Swift SeatCase). */
object SeatCase {
    val stateKeys = listOf("turn", "step", "active", "prompt", "out", "game", "viewer", "completed", "followTurns")

    fun snapshot(base: JsonObject, state: Map<String, J>): JsonObject {
        val json = base.toMutableMap()
        state["game"].string?.let { json["id"] = JsonPrimitive(it) }
        state["turn"].integer?.let { json["turn"] = JsonPrimitive(it) }
        state["step"].string?.let { json["step"] = JsonPrimitive(it) }
        state["viewer"].string?.let { json["viewerPlayerId"] = JsonPrimitive(it) }
        json["activePlayerId"] = state["active"].string?.let(::JsonPrimitive) ?: JsonNull
        if (state["completed"].bool == true) json["gameStatus"] = JsonPrimitive("completed")
        state["prompt"].string?.let { owner ->
            json["promptEnvelopeV2"] = jsonObject("id" to JsonPrimitive("case-prompt"), "method" to JsonPrimitive("GAME_SELECT"),
                "messageId" to JsonPrimitive(1), "playerId" to JsonPrimitive(owner), "responseKind" to JsonPrimitive("priority"),
                "message" to JsonPrimitive("Respond"))
        }
        val out = state["out"].array?.mapNotNull { it.string }?.toSet() ?: emptySet()
        json["players"] = JsonArray((base["players"].array ?: emptyList()).map { player ->
            JsonObject((player as JsonObject) + ("hasLeft" to JsonPrimitive(out.contains(player["playerId"].string))))
        })
        return JsonObject(json)
    }
}

/** Kotlin twin of the Swift ParitySummary. */
object ParitySummary {
    fun o(value: String?): J = value?.let(::JsonPrimitive) ?: JsonNull
    fun o(value: Int?): J = value?.let(::JsonPrimitive) ?: JsonNull
    fun o(value: Boolean?): J = value?.let(::JsonPrimitive) ?: JsonNull
    private fun strings(value: List<String>?): J = value?.let { JsonArray(it.map(::JsonPrimitive)) } ?: JsonNull
    private fun ints(value: Map<String, Int>?): J = value?.let { map -> JsonObject(map.mapValues { JsonPrimitive(it.value) }) } ?: JsonNull
    private fun <T> list(value: List<T>?, transform: (T) -> J): J = value?.let { JsonArray(it.map(transform)) } ?: JsonNull

    fun message(error: Throwable): String = (error as? EngineError)?.message ?: "decoding failed"

    fun card(c: ZoneCard): J = jsonObject(
        "instanceId" to JsonPrimitive(c.instanceId), "name" to JsonPrimitive(c.card.name), "typeLine" to JsonPrimitive(c.card.typeLine),
        "oracleText" to o(c.card.oracleText), "manaCost" to o(c.card.manaCost), "isToken" to o(c.card.isToken),
        "tokenColors" to strings(c.card.tokenColors), "copySourceArtworkName" to o(c.card.copySourceArtworkName),
        "tokenArtwork" to (c.card.tokenArtwork?.let { jsonObject("name" to JsonPrimitive(it.name), "typeLine" to JsonPrimitive(it.typeLine),
            "oracleText" to JsonPrimitive(it.oracleText), "power" to o(it.power), "toughness" to o(it.toughness), "colors" to strings(it.colors)) } ?: JsonNull),
        "tapped" to o(c.tapped), "summoningSickness" to o(c.summoningSickness), "damage" to o(c.damage), "phasedIn" to o(c.phasedIn),
        "isAttacking" to o(c.isAttacking), "blocking" to strings(c.blocking), "attachedToInstanceId" to o(c.attachedToInstanceId),
        "reportedPower" to o(c.reportedPower), "reportedToughness" to o(c.reportedToughness), "counters" to ints(c.counters),
        "icons" to JsonArray((c.cardIcons ?: emptyList()).map { jsonObject("iconType" to JsonPrimitive(it.iconType), "category" to o(it.category),
            "text" to o(it.text), "hint" to o(it.hint)) }),
        "visibleIcons" to JsonArray(c.visibleXmageIcons.map { JsonPrimitive(it.iconType) }),
        "selectable" to o(c.selectable), "disabledReason" to o(c.disabledReason),
        "displayPower" to o(c.displayPower), "displayToughness" to o(c.displayToughness))

    fun player(p: PlayerGameState): J {
        val z = p.zones
        return jsonObject(
            "playerId" to JsonPrimitive(p.playerId), "displayName" to o(p.displayName), "life" to JsonPrimitive(p.life), "poison" to JsonPrimitive(p.poison),
            "commanderTax" to JsonPrimitive(p.commanderTax), "commanderTaxKnown" to o(p.commanderTaxKnown), "hasLeft" to o(p.hasLeft),
            "isHuman" to o(p.isHuman), "monarch" to o(p.monarch), "initiative" to o(p.initiative), "counters" to ints(p.counters),
            "commanderDamage" to ints(p.commanderDamage),
            "commanders" to JsonArray((p.commanders ?: emptyList()).map { jsonObject("id" to JsonPrimitive(it.id), "name" to o(it.name),
                "ownerPlayerId" to JsonPrimitive(it.ownerPlayerId), "commanderTax" to o(it.commanderTax),
                "castsFromCommandZone" to o(it.castsFromCommandZone), "damageToPlayers" to ints(it.damageToPlayers)) }),
            "manaPool" to (p.manaPool?.let { jsonObject("W" to JsonPrimitive(it.W), "U" to JsonPrimitive(it.U), "B" to JsonPrimitive(it.B),
                "R" to JsonPrimitive(it.R), "G" to JsonPrimitive(it.G), "C" to JsonPrimitive(it.C)) } ?: JsonNull),
            "handCount" to o(z.handCount), "libraryCount" to o(z.libraryCount),
            "hand" to JsonArray(z.hand.map(::card)), "battlefield" to JsonArray(z.battlefield.map(::card)), "graveyard" to JsonArray(z.graveyard.map(::card)),
            "exile" to JsonArray(z.exile.map(::card)), "command" to JsonArray(z.command.map(::card)), "library" to JsonArray(z.library.map(::card)),
            "stack" to JsonArray(z.stack.map(::card)))
    }

    fun snapshot(s: GameSnapshot): Map<String, J> {
        val result = linkedMapOf<String, J>(
            "id" to JsonPrimitive(s.id), "source" to o(s.source), "activePlayerId" to o(s.activePlayerId), "phase" to JsonPrimitive(s.phase),
            "step" to o(s.step), "turn" to JsonPrimitive(s.turn), "priorityPlayerId" to o(s.priorityPlayerId),
            "waitingOnPlayerId" to o(s.waitingOnPlayerId), "promptText" to o(s.promptText), "bridgeRevision" to o(s.bridgeRevision),
            "xmageCycle" to o(s.xmageCycle), "pendingStatus" to o(s.pendingStatus),
            "gameStatus" to o(s.gameStatus?.let { if (it == GameStatus.COMPLETED) "completed" else "in_progress" }),
            "winnerPlayerIds" to strings(s.winnerPlayerIds), "viewerPlayerId" to o(s.viewerPlayerId), "isSpectating" to JsonPrimitive(s.isSpectating),
            "thinkingPlayerID" to o(s.thinkingPlayerID),
            "log" to JsonArray(s.log.map { jsonObject("id" to JsonPrimitive(it.id), "message" to JsonPrimitive(it.message)) }),
            "players" to JsonArray(s.players.map(::player)), "legalActions" to JsonArray((s.legalActions ?: emptyList()).map(::action)),
            "promptEnvelopeV2" to (s.promptEnvelopeV2?.let(::envelope) ?: JsonNull),
            "manaPayment" to (s.manaPayment?.let { jsonObject("active" to JsonPrimitive(it.active), "remainingText" to o(it.remainingText)) } ?: JsonNull))
        val x = s.xmage
        result["xmage"] = if (x == null) JsonNull else jsonObject(
            "gameId" to JsonPrimitive(x.gameId), "bridgeRevision" to JsonPrimitive(x.bridgeRevision), "xmageCycle" to o(x.xmageCycle),
            "stack" to JsonArray(x.stack.map { jsonObject("id" to JsonPrimitive(it.id), "objectType" to o(it.objectType), "name" to JsonPrimitive(it.name),
                "rulesText" to o(it.rulesText), "sourceInstanceId" to o(it.sourceInstanceId), "sourceName" to o(it.sourceName),
                "sourceCard" to (it.sourceCard?.let(::card) ?: JsonNull), "targetIds" to strings(it.targetIds), "paid" to o(it.paid)) }),
            "combat" to JsonArray(x.combat.map { jsonObject("defenderId" to JsonPrimitive(it.defenderId), "defenderName" to JsonPrimitive(it.defenderName),
                "defenderKind" to o(it.defenderKind), "blocked" to JsonPrimitive(it.blocked), "attackers" to JsonArray(it.attackers.map(::card)),
                "blockers" to JsonArray(it.blockers.map(::card))) }),
            "players" to JsonArray(x.players.map { jsonObject("playerId" to JsonPrimitive(it.playerId), "name" to JsonPrimitive(it.name),
                "active" to JsonPrimitive(it.active), "hasPriority" to JsonPrimitive(it.hasPriority), "timerActive" to JsonPrimitive(it.timerActive),
                "passedTurn" to JsonPrimitive(it.skipState.passedTurn), "passedAllTurns" to JsonPrimitive(it.skipState.passedAllTurns),
                "sideboard" to JsonArray(it.zones.sideboard.map(::card))) }),
            "playableObjects" to JsonArray(x.playableObjects.map { obj -> jsonObject("sourceInstanceId" to JsonPrimitive(obj.sourceInstanceId),
                "sourceZone" to o(obj.sourceZone), "cardName" to JsonPrimitive(obj.cardName), "categories" to strings(obj.categories),
                "abilities" to JsonArray(obj.abilities.map { jsonObject("id" to JsonPrimitive(it.id), "label" to JsonPrimitive(it.label), "category" to JsonPrimitive(it.category)) })) }),
            "zones" to JsonArray((x.exileZones + x.revealed + x.lookedAt + x.companion).map { jsonObject("id" to JsonPrimitive(it.id),
                "name" to JsonPrimitive(it.name), "cards" to JsonArray(it.cards.map(::card))) }),
            "panels" to jsonObject("stack" to JsonPrimitive(x.panels.stack), "command" to JsonPrimitive(x.panels.command),
                "graveyard" to JsonPrimitive(x.panels.graveyard), "exile" to JsonPrimitive(x.panels.exile), "revealed" to JsonPrimitive(x.panels.revealed),
                "lookedAt" to JsonPrimitive(x.panels.lookedAt), "search" to JsonPrimitive(x.panels.search)))
        return result
    }

    fun action(a: LegalAction): J = jsonObject(
        "id" to JsonPrimitive(a.id), "type" to JsonPrimitive(a.type), "playerId" to JsonPrimitive(a.playerId), "label" to JsonPrimitive(a.label),
        "promptId" to o(a.promptId), "messageId" to o(a.messageId), "cardInstanceId" to o(a.cardInstanceId),
        "sourceInstanceId" to o(a.sourceInstanceId), "sourceZone" to o(a.sourceZone), "cardName" to o(a.cardName),
        "abilityId" to o(a.abilityId), "confirmed" to o(a.confirmed), "choiceIds" to strings(a.choiceIds),
        "compactPromptTitle" to JsonPrimitive(a.compactPromptTitle))

    private val swiftKind = mapOf(MobilePromptKind.PAYMENT to "payment", MobilePromptKind.TARGET to "target",
        MobilePromptKind.CONFIRMATION to "confirmation", MobilePromptKind.CARD_CHOICE to "cardChoice",
        MobilePromptKind.PLAYER_CHOICE to "playerChoice", MobilePromptKind.ABILITY_CHOICE to "abilityChoice", MobilePromptKind.ORDER to "order",
        MobilePromptKind.AMOUNT to "amount", MobilePromptKind.MULTI_AMOUNT to "multiAmount", MobilePromptKind.PILE to "pile",
        MobilePromptKind.SEARCH to "search", MobilePromptKind.COMBAT to "combat", MobilePromptKind.UNSUPPORTED to "unsupported")

    fun envelope(e: PromptEnvelopeV2): J {
        fun options(values: List<ChoicePromptOption>?): J = list(values) { jsonObject("id" to JsonPrimitive(it.id), "label" to JsonPrimitive(it.label)) }
        fun command(c: XmageResponseCommand?): J = c?.let { jsonObject("type" to o(it.type), "promptId" to o(it.promptId),
            "messageId" to o(it.messageId), "confirmed" to o(it.confirmed), "pay" to o(it.pay)) } ?: JsonNull
        val chosen = (e.options?.get("chosenTargets") as? JsonArray)?.let { values -> JsonArray(values.mapNotNull { it.stringValue }.map(::JsonPrimitive)) } ?: JsonNull
        return jsonObject(
            "id" to JsonPrimitive(e.id), "method" to JsonPrimitive(e.method), "messageId" to JsonPrimitive(e.messageId),
            "playerId" to JsonPrimitive(e.playerId), "responseKind" to JsonPrimitive(e.responseKind), "message" to JsonPrimitive(e.message),
            "required" to o(e.required), "minChoices" to o(e.minChoices), "maxChoices" to o(e.maxChoices), "totalMin" to o(e.totalMin),
            "totalMax" to o(e.totalMax), "targetIds" to strings(e.targetIds), "choices" to options(e.choices),
            "responseCommand" to command(e.responseCommand), "cards" to list(e.cards, ::card), "targets" to options(e.targets),
            "players" to list(e.players) { jsonObject("id" to JsonPrimitive(it.id), "label" to JsonPrimitive(it.label), "playerId" to JsonPrimitive(it.playerId)) },
            "piles" to list(e.piles) { jsonObject("id" to JsonPrimitive(it.id), "label" to JsonPrimitive(it.label), "cards" to JsonArray(it.cards.map(::card)),
                "number" to o(it.explicitPileNumber)) },
            "abilities" to list(e.abilities) { jsonObject("id" to JsonPrimitive(it.id), "label" to JsonPrimitive(it.label),
                "sourceInstanceId" to o(it.sourceInstanceId), "sourceName" to o(it.sourceName),
                "sourceUnavailableReason" to o(it.sourceUnavailableReason), "sourceCard" to (it.sourceCard?.let(::card) ?: JsonNull)) },
            "modes" to options(e.modes), "amounts" to list(e.amounts) { JsonPrimitive(it) },
            "multiAmounts" to list(e.multiAmounts) { jsonObject("id" to JsonPrimitive(it.id), "label" to JsonPrimitive(it.label),
                "min" to JsonPrimitive(it.min), "max" to JsonPrimitive(it.max), "defaultValue" to o(it.defaultValue)) },
            "manaChoices" to list(e.manaChoices) { jsonObject("id" to JsonPrimitive(it.id), "label" to JsonPrimitive(it.label),
                "manaType" to o(it.manaType), "amount" to o(it.amount)) },
            "orderedItems" to options(e.orderedItems),
            "confirmation" to (e.confirmation?.let { jsonObject("yesLabel" to o(it.yesLabel), "noLabel" to o(it.noLabel),
                "yesCommand" to command(it.yesCommand), "noCommand" to command(it.noCommand)) } ?: JsonNull),
            "optionKeys" to (e.options?.let { JsonArray(it.keys.sorted().map(::JsonPrimitive)) } ?: JsonNull), "chosenTargets" to chosen,
            "kind" to JsonPrimitive(swiftKind.getValue(MobilePromptPresentation.kind(e))))
    }

    fun command(f: J, gameId: String, playerId: String, promptId: String, messageId: Int): GameCommand {
        fun list(key: String) = f[key].array?.mapNotNull { it.string }
        return GameCommand(type = f["type"].string ?: "", gameId = gameId, playerId = playerId,
            cardInstanceId = f["cardInstanceId"].string, sourceInstanceId = f["sourceInstanceId"].string, abilityId = f["abilityId"].string,
            promptId = promptId, messageId = messageId, choiceIds = list("choiceIds"), targetIds = list("targetIds"),
            cardInstanceIds = list("cardInstanceIds"), modeIds = list("modeIds"), pile = f["pile"].integer?.toInt(),
            amount = f["amount"].integer?.toInt(), amounts = f["amounts"].array?.mapNotNull { it.integer?.toInt() },
            orderedIds = list("orderedIds"), manaType = f["manaType"].string, playerIds = list("playerIds"), confirmed = f["confirmed"].bool)
    }

    fun answer(command: GameCommand, prompt: EnginePrompt, viewer: String): J = try {
        OnDevicePromptAdapter.answer(command, prompt, viewer)
    } catch (error: Exception) { jsonObject("error" to JsonPrimitive(message(error))) }

    fun answers(snapshot: GameSnapshot, prompt: EnginePrompt?): List<J> {
        if (prompt == null || prompt.submitted) return emptyList()
        val commands = (snapshot.legalActions ?: emptyList()).map { a ->
            GameCommand(type = a.type, gameId = snapshot.id, playerId = a.playerId, cardInstanceId = a.cardInstanceId,
                sourceInstanceId = a.sourceInstanceId, abilityId = a.abilityId, promptId = a.promptId, messageId = a.messageId,
                choiceIds = a.choiceIds, targetIds = a.targetIds, cardInstanceIds = a.cardInstanceIds, modeIds = a.modeIds,
                pile = a.pile?.value, amount = a.amount, amounts = a.amounts, orderedIds = a.orderedIds, useCommandZone = a.useCommandZone,
                manaType = a.manaType, manaTypes = a.manaTypes, playerIds = a.playerIds, confirmed = a.confirmed, pay = a.pay,
                sourceZone = a.sourceZone, fromZone = a.sourceZone, cardName = a.cardName, attackers = a.attackers, blockers = a.blockers,
                expectedBridgeRevision = snapshot.bridgeRevision)
        }.toMutableList()
        snapshot.promptEnvelopeV2?.let { envelope ->
            for (target in envelope.targets ?: emptyList()) commands += GameCommand(type = "choose_target", gameId = snapshot.id,
                playerId = snapshot.viewerID, promptId = envelope.id, messageId = envelope.messageId, targetIds = listOf(target.id))
            for (confirmed in if (envelope.confirmation == null) emptyList() else listOf(true, false)) commands += GameCommand(
                type = "answer_yes_no", gameId = snapshot.id, playerId = snapshot.viewerID, promptId = envelope.id,
                messageId = envelope.messageId, confirmed = confirmed)
            for (choice in envelope.manaChoices ?: emptyList()) commands += GameCommand(type = "play_mana", gameId = snapshot.id,
                playerId = snapshot.viewerID, promptId = envelope.id, messageId = envelope.messageId, manaType = choice.manaType)
        }
        return commands.map { jsonObject("type" to JsonPrimitive(it.type), "answer" to answer(it, prompt, snapshot.viewerID)) }
    }
}
