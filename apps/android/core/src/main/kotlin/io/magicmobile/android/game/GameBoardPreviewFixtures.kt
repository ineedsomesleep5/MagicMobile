package io.magicmobile.android.game

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Port of GameBoardScreen.swift's preview states and GameBoardPreviewFixtures.swift. Development
 * fixtures only: they never enter a live engine session. The same state names render the same
 * boards on both platforms, for side-by-side comparison.
 */
enum class GameBoardDesignPreviewState(val rawValue: String) {
    NORMAL_BATTLEFIELD("normal-battlefield"), SELECTED_CARD_ACTION_TRAY("selected-card-action-tray"),
    MANA_PAYMENT_PROMPT("mana-payment-prompt"), SEARCH_SELECT_PROMPT("search-select-prompt"),
    STACK_RESPONSE_PROMPT("stack-response-prompt"), COMMANDER_REPLACEMENT_PROMPT("commander-replacement-prompt"),
    DAMAGE_ASSIGNMENT_PROMPT("damage-assignment-prompt"), UNSUPPORTED_PROMPT_FALLBACK("unsupported-prompt-fallback"),
    AI_THINKING("ai-thinking"), BRIDGE_UNAVAILABLE("bridge-unavailable"), MISSING_CARD_ART("missing-card-art"),
    CROWDED_BATTLEFIELD("crowded-battlefield"), ATTACHED_PERMANENTS("attached-permanents"), FOUR_PLAYER_FOCUS("four-player-focus"),
    PLAYER_TARGET_PROMPT("player-target-prompt"), CARD_TARGET_PROMPT("card-target-prompt"), COMBAT_ARROWS("combat-arrows"),
    FULL_HAND_INSPECTION("full-hand-inspection"), SCRY_CHOICE("scry-choice"), LIBRARY_CHOICE("library-choice"),
    EMPTY_LIBRARY_CHOICE("empty-library-choice"), MIXED_CARD_CHOICE("mixed-card-choice"), HAND_DRAG("hand-drag"),
    HAND_SCRUBBER("hand-scrubber"), ZONE_INSPECTION("zone-inspection"), ABILITY_CHOICE("ability-choice"), MODE_CHOICE("mode-choice"),
    PHASE_ANNOUNCEMENT("phase-announcement"), LIFE_CHANGE("life-change"), LARGE_TEXT("large-text"), STACK_TRAY("stack-tray"),
    VICTORY("victory"), SPECTATING("spectating"), FOUR_PLAYER_SPECTATING("four-player-spectating"), OPENING_HAND("opening-hand"),
    TOKEN_COPY_INSPECTION("token-copy-inspection"), ABILITY_SHOWCASE("ability-showcase"), FIRST_STRIKE("first-strike");

    val title: String get() = capitalizedWords(rawValue.replace("-", " "))

    companion object {
        fun of(raw: String?): GameBoardDesignPreviewState? = entries.firstOrNull { it.rawValue == raw }
    }
}

object GameBoardPreviewFixtures {
    private val parser = Json { isLenient = false }

    fun snapshot(state: GameBoardDesignPreviewState, step: String? = null, life: Int? = null, specialStateAdvanced: Boolean = false,
                 environment: Map<String, String> = emptyMap()): GameSnapshot {
        @Suppress("UNCHECKED_CAST")
        val root = toKotlin(parser.parseToJsonElement(json(state))) as MutableMap<String, Any?>
        enrich(root, state, environment)
        if (state == GameBoardDesignPreviewState.ATTACHED_PERMANENTS && specialStateAdvanced) {
            for (player in players(root)) {
                player["poison"] = 5
                player["counters"] = mutableMapOf("Poison" to 5, "Energy" to 4)
                for (card in list(zones(player)["battlefield"])) {
                    if (card["instanceId"] == "human-sol-ring") card["phasedIn"] = true
                    if (card["instanceId"] == "player-curse") card["attachedToInstanceId"] = "human"
                }
            }
        }
        if (state == GameBoardDesignPreviewState.ABILITY_SHOWCASE && specialStateAdvanced) {
            // Prodigal Pyromancer's ability goes on the stack, as XMage names it: "Ability".
            val xmage = map(root["xmage"])
            val source = card("ai-1-ability-source", "Prodigal Pyromancer", "Creature — Human Wizard", "{2}{R}", "{T}: This creature deals 1 damage to any target.", 1)
            xmage["stack"] = mutableListOf(mutableMapOf("id" to "stack-ability-showcase", "objectId" to "stack-ability-showcase",
                "objectType" to "ACTIVATED_ABILITY", "name" to "Ability", "rulesText" to "Prodigal Pyromancer deals 1 damage to any target.",
                "sourceInstanceId" to "ai-1-ability-source", "sourceName" to "Prodigal Pyromancer", "sourceZone" to "battlefield",
                "sourceCard" to source, "controllerId" to "ai-1", "targetIds" to mutableListOf("human"), "paid" to true))
            map(xmage["panels"])["stack"] = true
            xmage["bridgeRevision"] = 100
            root["bridgeRevision"] = 100
        }
        if (state == GameBoardDesignPreviewState.FIRST_STRIKE && specialStateAdvanced) advanceToFirstStrikeDamage(root)
        if (step != null) { root["step"] = step; root["activePlayerId"] = "ai-1" }
        if (life != null) players(root).firstOrNull { it["playerId"] == "human" }?.set("life", life)
        (root["promptEnvelopeV2"] as? Map<*, *>)?.let { root["promptText"] = it["message"] }
        return EngineJson.format.decodeFromJsonElement(GameSnapshot.serializer(), toJson(root))
    }

    fun selectedCard(state: GameBoardDesignPreviewState, snapshot: GameSnapshot): ZoneCard? =
        if (state in setOf(GameBoardDesignPreviewState.SELECTED_CARD_ACTION_TRAY, GameBoardDesignPreviewState.MISSING_CARD_ART,
                GameBoardDesignPreviewState.FULL_HAND_INSPECTION)) snapshot.human?.zones?.hand?.firstOrNull() else null

    const val TOKEN_COPY_ID = "human-token-copy"
    /** First-strike preview: UUIDs, so the public log can name these cards. */
    const val ATARKA_ID = "a7a4ca00-6d1e-4c2a-9f10-0000000000a1"
    const val DEATHTOUCH_BLOCKER_ID = "7e9a0000-5b1d-4d2e-8f00-0000000000b2"

    /**
     * `first-strike`: Atarka gave itself double strike when it attacked, and a deathtouch Typhoid Rats
     * blocks. Advanced, XMage is in its first-strike damage step: Atarka's first hit killed the Rats
     * before they could deal damage.
     */
    private fun firstStrikeCombat(root: MutableMap<String, Any?>, players: MutableList<MutableMap<String, Any?>>) {
        val atarka = card(ATARKA_ID, "Atarka, World Render", "Legendary Creature — Dragon", "{5}{R}{R}",
            "Flying\nTrample\nWhenever a Dragon you control attacks, it gains double strike until end of turn.\nDouble strike", 6)
        atarka["toughness"] = 4; atarka["tapped"] = true; atarka["isAttacking"] = true; atarka["summoningSickness"] = false
        atarka["cardIcons"] = listOf("ABILITY_FLYING", "ABILITY_TRAMPLE", "ABILITY_DOUBLE_STRIKE")
            .map { mutableMapOf<String, Any?>("iconType" to it, "category" to "ABILITY") }.toMutableList()
        val rats = card(DEATHTOUCH_BLOCKER_ID, "Typhoid Rats", "Creature — Rat", "{B}", "Deathtouch", 1)
        rats["blocking"] = mutableListOf(ATARKA_ID); rats["summoningSickness"] = false
        rats["cardIcons"] = mutableListOf(mutableMapOf<String, Any?>("iconType" to "ABILITY_DEATHTOUCH", "category" to "ABILITY"))
        list(zones(players[1])["battlefield"]).add(0, atarka)
        list(zones(players[0])["battlefield"]).add(0, rats)
        root["phase"] = "combat"; root["step"] = "declare-blockers"
        root["activePlayerId"] = "ai-1"
        root["log"] = mutableListOf(
            mutableMapOf("id" to "fs-log-1", "message" to "TURN 3 for <font color='#20B2AA'>Aurelia</font> (31 - 37)"),
            mutableMapOf("id" to "fs-log-2", "message" to "<font color='#20B2AA'>Aurelia</font> attacks <font color='#20B2AA'>You</font> with 1 creature"))
    }

    private fun advanceToFirstStrikeDamage(root: MutableMap<String, Any?>) {
        val human = zones(players(root)[0])
        val battlefield = list(human["battlefield"])
        val index = battlefield.indexOfFirst { it["instanceId"] == DEATHTOUCH_BLOCKER_ID }
        if (index >= 0) {
            val rats = battlefield.removeAt(index)
            rats.remove("blocking")
            list(human["graveyard"]).add(0, rats)
        }
        root["step"] = "first-combat-damage"
        root["bridgeRevision"] = 100
        val xmage = map(root["xmage"])
        list(xmage["combat"]).firstOrNull()?.let { it["blockers"] = mutableListOf<Any?>() }
        xmage["bridgeRevision"] = 100
        val atarka = "<font color='#FF6347' object_id='$ATARKA_ID'>Atarka, World Render</font> [a7a]"
        val rats = "<font color='#696969' object_id='$DEATHTOUCH_BLOCKER_ID'>Typhoid Rats</font> [7e9]"
        list(root["log"]).addAll(listOf(mutableMapOf("id" to "fs-log-3", "message" to "$atarka deals 6 damage to $rats"),
            mutableMapOf("id" to "fs-log-4", "message" to "$rats died")))
    }

    /** The card a preview opens held in the inspector. */
    fun inspectedCard(state: GameBoardDesignPreviewState, snapshot: GameSnapshot): ZoneCard? = when (state) {
        GameBoardDesignPreviewState.FULL_HAND_INSPECTION -> snapshot.human?.zones?.hand?.firstOrNull()
        GameBoardDesignPreviewState.TOKEN_COPY_INSPECTION -> snapshot.human?.zones?.battlefield?.firstOrNull { it.instanceId == TOKEN_COPY_ID }
        else -> null
    }

    const val boardFXStepCount = 10

    /**
     * Scripted board FX walkthrough: 0 base, 1 cast Swords, 2 Swords resolves (exile Angel, AI life -5),
     * 3 Sol Ring enters with a counter on Isamaru, 4 AI casts Kozilek, 5 Kozilek enters, 6 Isamaru attacks,
     * 7 Kozilek blocks, 8 combat damage, 9 Isamaru dies.
     */
    fun boardFXStep(step: Int): GameSnapshot {
        @Suppress("UNCHECKED_CAST")
        val root = toKotlin(parser.parseToJsonElement(json(GameBoardDesignPreviewState.NORMAL_BATTLEFIELD))) as MutableMap<String, Any?>
        root["id"] = "design-preview-board-fx"
        root["bridgeRevision"] = 1_000 + step
        root["legalActions"] = mutableListOf<Any?>()
        val steps = mapOf(6 to "declare-attackers", 7 to "declare-blockers", 8 to "combat-damage", 9 to "end-combat")
        root["phase"] = if (step >= 6) "combat" else "precombat-main"
        root["step"] = steps[step] ?: "precombat-main"
        val players = players(root)
        val costs = mapOf("Swords to Plowshares" to "{W}", "Sol Ring" to "{1}", "Isamaru, Hound of Konda" to "{W}", "Serra Angel" to "{3}{W}{W}",
            "Kozilek, Butcher of Truth" to "{10}")
        fun zone(player: Int, name: String): MutableList<MutableMap<String, Any?>> = list(zones(players[player])[name])
        fun setZone(player: Int, name: String, cards: List<MutableMap<String, Any?>>) {
            zones(players[player])[name] = cards.map { card ->
                val identity = map(card["card"])
                costs[identity["name"]]?.let { identity["manaCost"] = it }
                card
            }.toMutableList()
        }
        fun move(id: String, from: Pair<Int, String>, to: Pair<Int, String>, edit: (MutableMap<String, Any?>) -> Unit = {}) {
            val source = zone(from.first, from.second)
            val index = source.indexOfFirst { it["instanceId"] == id }
            if (index < 0) return
            val card = source.removeAt(index)
            edit(card)
            setZone(from.first, from.second, source)
            setZone(to.first, to.second, zone(to.first, to.second) + card)
        }
        fun editCard(id: String, player: Int, edit: (MutableMap<String, Any?>) -> Unit) =
            setZone(player, "battlefield", zone(player, "battlefield").onEach { if (it["instanceId"] == id) edit(it) })
        val human = 0; val ai = 1
        val aiID = players[ai]["playerId"] as String
        for (zoneName in listOf("hand", "battlefield", "graveyard", "exile", "command")) {
            setZone(human, zoneName, zone(human, zoneName)); setZone(ai, zoneName, zone(ai, zoneName))
        }
        var stack = mutableListOf<Any?>()
        if (step >= 1) {
            move("hand-spell", human to "hand", human to "stack")
            if (step == 1) {
                val source = zone(human, "stack").first()
                stack = mutableListOf(mutableMapOf("id" to "stack-swords", "name" to "Swords to Plowshares", "sourceCard" to source,
                    "controllerId" to "human", "sourceZone" to "hand", "rulesText" to "Exile target creature."))
            }
        }
        if (step >= 2) {
            move("hand-spell", human to "stack", human to "graveyard")
            move("ai-creature-1", ai to "battlefield", ai to "exile")
            players[ai]["life"] = 35
        }
        if (step >= 3) {
            move("hand-sol-ring", human to "hand", human to "battlefield")
            editCard("human-commander", human) { it["counters"] = mutableMapOf("+1/+1" to 1); it["summoningSickness"] = false }
        }
        val kozilek = mutableMapOf<String, Any?>("instanceId" to "ai-kozilek", "tapped" to false, "power" to 12, "toughness" to 12,
            "isCreaturePermanent" to true, "card" to mutableMapOf("name" to "Kozilek, Butcher of Truth", "typeLine" to "Legendary Creature - Eldrazi",
                "manaCost" to "{10}", "oracleText" to "When you cast this spell, draw four cards. Annihilator 4"))
        if (step >= 4) {
            setZone(ai, "command", emptyList())
            if (step == 4) {
                stack = mutableListOf(mutableMapOf("id" to "stack-kozilek", "name" to "Kozilek, Butcher of Truth", "sourceCard" to kozilek,
                    "controllerId" to aiID, "sourceZone" to "command", "objectType" to "SPELL"))
            } else setZone(ai, "battlefield", zone(ai, "battlefield") + kozilek)
        }
        if (step >= 6) editCard("human-commander", human) { it["isAttacking"] = true; it["tapped"] = true }
        if (step >= 7) editCard("ai-kozilek", ai) { it["blocking"] = mutableListOf("human-commander") }
        if (step >= 8) {
            editCard("human-commander", human) { it["damage"] = 12 }
            editCard("ai-kozilek", ai) { it["damage"] = 3 }
            players[human]["life"] = 37
        }
        if (step >= 9) move("human-commander", human to "battlefield", human to "graveyard")
        var combat = mutableListOf<Any?>()
        if (step in 6..8) {
            val attacker = zone(human, "battlefield").first { it["instanceId"] == "human-commander" }
            val blockers = if (step >= 7) zone(ai, "battlefield").filter { it["instanceId"] == "ai-kozilek" } else emptyList()
            combat = mutableListOf(mutableMapOf("defenderId" to aiID, "defenderName" to "AI", "defenderKind" to "player", "blocked" to (step >= 7),
                "attackers" to mutableListOf(attacker), "blockers" to blockers.toMutableList()))
        }
        root["xmage"] = mutableMapOf("schemaVersion" to 1, "gameId" to "design-preview-board-fx", "bridgeRevision" to 1_000 + step,
            "xmageCycle" to 1_000 + step, "callbackCoverage" to mutableListOf<Any?>(), "stack" to stack, "combat" to combat,
            "players" to mutableListOf<Any?>(), "exileZones" to mutableListOf<Any?>(), "revealed" to mutableListOf<Any?>(),
            "lookedAt" to mutableListOf<Any?>(), "companion" to mutableListOf<Any?>(), "playableObjects" to mutableListOf<Any?>(),
            "panels" to panels(stack = true))
        return EngineJson.format.decodeFromJsonElement(GameSnapshot.serializer(), toJson(root))
    }

    private fun panels(stack: Boolean) = mutableMapOf("stack" to stack, "command" to true, "graveyard" to true, "exile" to true,
        "revealed" to false, "lookedAt" to false, "search" to false)

    private fun card(id: String, name: String, type: String, cost: String, rules: String, power: Int? = null): MutableMap<String, Any?> {
        val value = mutableMapOf<String, Any?>("instanceId" to id,
            "card" to mutableMapOf("name" to name, "typeLine" to type, "manaCost" to cost, "oracleText" to rules), "tapped" to false)
        if (power != null) { value["power"] = power; value["toughness"] = power; value["isCreaturePermanent"] = true }
        return value
    }

    // Development fixture projection only. These actions never enter a live engine session.
    private fun enrich(root: MutableMap<String, Any?>, state: GameBoardDesignPreviewState, environment: Map<String, String>) {
        val creatures = listOf(Triple("Silvercoat Lion", "{1}{W}", 2), Triple("Serra Angel", "{3}{W}{W}", 4), Triple("Grizzly Bears", "{1}{G}", 2),
            Triple("Llanowar Elves", "{G}", 1), Triple("Spirited Companion", "{1}{W}", 1), Triple("Sun Titan", "{4}{W}{W}", 6))
        val crowded = state in setOf(GameBoardDesignPreviewState.CROWDED_BATTLEFIELD, GameBoardDesignPreviewState.FOUR_PLAYER_FOCUS,
            GameBoardDesignPreviewState.MANA_PAYMENT_PROMPT, GameBoardDesignPreviewState.COMBAT_ARROWS, GameBoardDesignPreviewState.LARGE_TEXT)
        val resourceLayoutMode = if (state == GameBoardDesignPreviewState.CROWDED_BATTLEFIELD) environment["MAGICMOBILE_BOARD_RESOURCE_LAYOUT_UI_TEST"] else null
        val players = players(root)
        val watching = state == GameBoardDesignPreviewState.SPECTATING || state == GameBoardDesignPreviewState.FOUR_PLAYER_SPECTATING
        if (state in setOf(GameBoardDesignPreviewState.FOUR_PLAYER_FOCUS, GameBoardDesignPreviewState.PLAYER_TARGET_PROMPT) || watching) {
            for (number in 2..3) {
                @Suppress("UNCHECKED_CAST")
                val opponent = deepCopy(players[1]) as MutableMap<String, Any?>
                opponent["playerId"] = "ai-$number"
                opponent["life"] = 40 - number * 3
                val zones = zones(opponent)
                for ((zone, contents) in zones.toMap()) {
                    val cards = contents as? MutableList<*> ?: continue
                    zones[zone] = cards.map { original ->
                        @Suppress("UNCHECKED_CAST")
                        val copy = deepCopy(original) as MutableMap<String, Any?>
                        copy["instanceId"] = "ai-$number-${(original as Map<*, *>)["instanceId"]}"; copy
                    }.toMutableList()
                }
                players += opponent
            }
        }
        if (state == GameBoardDesignPreviewState.SPECTATING) {
            // You conceded: XMage removed your cards; one opponent is out too.
            players[0]["hasLeft"] = true
            players[0]["life"] = 0
            players[2]["hasLeft"] = true
        }
        if (state == GameBoardDesignPreviewState.FOUR_PLAYER_SPECTATING) {
            // You conceded in a pod of four: Aurelia, next in turn order, takes your seat while
            // the top follows Kozilek's turn.
            players[0]["hasLeft"] = true
            players[0]["life"] = 0
            root["turn"] = 6
            root["activePlayerId"] = "ai-2"
            root["priorityPlayerId"] = "ai-2"
            root.remove("waitingOnPlayerId")
            root.remove("promptText")
        }
        for ((index, player) in players.withIndex()) {
            val seat = player["playerId"] as String
            player["displayName"] = if (index == 0) "You" else listOf("", "Aurelia", "Kozilek", "Meren")[index]
            player["isHuman"] = index == 0
            if (index > 0) {
                player["commanders"] = mutableListOf(mutableMapOf("id" to "$seat-commander",
                    "name" to listOf("", "Aurelia, the Warleader", "Kozilek, the Great Distortion", "Meren of Clan Nel Toth")[index], "ownerPlayerId" to seat))
            }
            val zones = zones(player)
            val battlefield = list(zones["battlefield"])
            val previewCreatures = if (state == GameBoardDesignPreviewState.COMBAT_ARROWS) List(3) { creatures }.flatten() else creatures.take(if (crowded) 6 else 2)
            for ((number, creature) in previewCreatures.withIndex()) {
                val power = creature.third + if (state == GameBoardDesignPreviewState.COMBAT_ARROWS) number / creatures.size else 0
                val permanent = card("$seat-preview-creature-$number", creature.first, "Creature", creature.second, "Development fixture permanent.", power)
                permanent["tapped"] = number == 2; battlefield += permanent
            }
            for (number in 2..(if (crowded) 5 else 2)) {
                battlefield += card("$seat-preview-land-$number", "Forest", "Basic Land — Forest", "", "{T}: Add {G}.")
            }
            if (state == GameBoardDesignPreviewState.COMBAT_ARROWS) {
                for (number in 0 until 12) battlefield += card("$seat-overflow-land-$number", "Fixture Land $number", "Land", "", "Development scrolling fixture.")
            }
            if (state == GameBoardDesignPreviewState.ZONE_INSPECTION && index == 0) {
                val graveyard = list(zones["graveyard"])
                for (number in 0 until 24) graveyard += card("graveyard-overflow-$number", "Fixture Graveyard $number", "Creature", "", "Development scrolling fixture.", 1)
            }
            if ((state == GameBoardDesignPreviewState.STACK_RESPONSE_PROMPT || state == GameBoardDesignPreviewState.ABILITY_SHOWCASE) && index == 1) {
                battlefield += card("ai-1-ability-source", "Prodigal Pyromancer", "Creature — Human Wizard", "{2}{R}", "{T}: This creature deals 1 damage to any target.", 1)
            }
            if (state == GameBoardDesignPreviewState.FIRST_STRIKE && index == 1) firstStrikeCombat(root, players)
            if (state == GameBoardDesignPreviewState.TOKEN_COPY_INSPECTION && index == 0) {
                // A token copy of Sun Titan that has grown: its frame shows the live 7/7, never the printed 6/6.
                val copy = card(TOKEN_COPY_ID, "Sun Titan", "Creature — Giant", "{4}{W}{W}",
                    "Vigilance\nWhenever Sun Titan enters or attacks, you may return target permanent card with mana value 3 or less from your graveyard to the battlefield.", 7)
                val identity = map(copy["card"])
                identity["isToken"] = true
                identity["copySourceArtworkName"] = "Sun Titan"
                identity["tokenColors"] = mutableListOf("W")
                copy["counters"] = mutableMapOf("+1/+1" to 1)
                copy["summoningSickness"] = false
                battlefield += copy
            }
            if (state == GameBoardDesignPreviewState.ATTACHED_PERMANENTS) {
                player["poison"] = if (index == 0) 2 else 3
                player["counters"] = mutableMapOf("Poison" to (if (index == 0) 2 else 3), "Energy" to 4)
                player["monarch"] = index == 1
                val aura = card("$seat-attached-aura", "Karametra's Favor", "Enchantment — Aura", "{1}{G}", "Enchant creature. Enchanted creature has {T}: Add one mana of any color.")
                aura["attachedToInstanceId"] = "ai-1-preview-creature-0"
                battlefield += aura
                if (index == 1) {
                    val equipment = card("attached-equipment", "Short Sword", "Artifact — Equipment", "{1}", "Equipped creature gets +1/+1.")
                    equipment["attachedToInstanceId"] = "ai-1-preview-creature-0"
                    battlefield += equipment
                } else {
                    val curse = card("player-curse", "Curse of Opulence", "Enchantment — Aura Curse", "{R}", "Enchant player.")
                    curse["attachedToInstanceId"] = "ai-1"
                    battlefield += curse
                }
            }
            if (index == 0) {
                battlefield += card("human-sol-ring", "Sol Ring", "Artifact", "{1}", "{T}: Add {C}{C}.")
                if (state == GameBoardDesignPreviewState.ATTACHED_PERMANENTS) battlefield.firstOrNull { it["instanceId"] == "human-sol-ring" }?.set("phasedIn", false)
                val hand = list(zones["hand"])
                val handCreatures = if (state == GameBoardDesignPreviewState.HAND_SCRUBBER) List(4) { creatures.take(5) }.flatten() else creatures.take(5)
                for ((number, creature) in handCreatures.withIndex()) {
                    val id = if (state == GameBoardDesignPreviewState.HAND_SCRUBBER && number == handCreatures.size - 1) "last-hand-card" else "hand-preview-$number"
                    hand += card(id, creature.first, "Creature", creature.second, "Development inspection fixture.", creature.third)
                }
                zones["exile"] = mutableListOf(card("human-exile-1", "Swords to Plowshares", "Instant", "{W}", "Exile target creature. Its controller gains life equal to its power."))
            }
            if (resourceLayoutMode in setOf("rocks", "lands-only")) {
                if (resourceLayoutMode == "lands-only") battlefield.removeAll { it["instanceId"] == "human-sol-ring" }
                for (number in 0 until 12) battlefield += card("$seat-resource-land-$number", "Fixture Land $number", "Basic Land", "", "{T}: Add {G}.")
                if (resourceLayoutMode == "rocks") {
                    for (number in 0 until 10) {
                        val rock = card("$seat-resource-rock-$number", "Fixture Rock $number", "Artifact", "{2}", "{T}: Add {C}.")
                        rock["tapped"] = number == 1
                        battlefield += rock
                    }
                    battlefield += listOf(
                        card("$seat-resource-signet", "Dimir Signet", "Artifact", "{2}", "{1}, {T}: Add {U}{B}."),
                        card("$seat-resource-talisman", "Talisman of Dominance", "Artifact", "{2}", "{T}: Add {C}.\n{T}: Add {U} or {B}."),
                        card("$seat-resource-treasure", "Treasure token", "Token Artifact — Treasure", "", "{T}, Sacrifice this token: Add one mana of any color."),
                        card("$seat-resource-altar", "Ashnod's Altar", "Artifact", "{3}", "Sacrifice a creature: Add {C}{C}."))
                }
                battlefield.addAll(0, listOf(card("$seat-resource-sword", "Fixture Sword", "Artifact — Equipment", "{1}", "Equip {1}."),
                    card("$seat-resource-oath", "Fixture Oath", "Enchantment", "{2}", "Creatures you control get +1/+1.")))
            }
            if (state == GameBoardDesignPreviewState.COMBAT_ARROWS) {
                val id = if (index == 0) "human-preview-creature-0" else "ai-1-preview-creature-0"
                battlefield.firstOrNull { it["instanceId"] == id }?.let {
                    if (index == 0) { it["isAttacking"] = true; it["tapped"] = true } else it["blocking"] = mutableListOf("human-preview-creature-0")
                }
            }
            if (state == GameBoardDesignPreviewState.MANA_PAYMENT_PROMPT && index == 0) {
                val ring = battlefield.indexOfFirst { it["instanceId"] == "human-sol-ring" }
                if (ring >= 0) battlefield.add(0, battlefield.removeAt(ring))
            }
            if (watching && player["hasLeft"] == true) {
                // A player who left takes their cards out of the game (CR 800.4a).
                zones["battlefield"] = mutableListOf<Any?>(); zones["hand"] = mutableListOf<Any?>()
            }
        }
        var actions = list(root["legalActions"])
        if (watching) actions = mutableListOf()
        if (state !in setOf(GameBoardDesignPreviewState.AI_THINKING, GameBoardDesignPreviewState.BRIDGE_UNAVAILABLE,
                GameBoardDesignPreviewState.UNSUPPORTED_PROMPT_FALLBACK, GameBoardDesignPreviewState.SPECTATING,
                GameBoardDesignPreviewState.FOUR_PLAYER_SPECTATING)) {
            actions += mutableMapOf("id" to "make-mana-sol-ring", "type" to "make_mana", "playerId" to "human", "label" to "Tap Sol Ring",
                "sourceInstanceId" to "human-sol-ring", "cardName" to "Sol Ring", "sourceZone" to "battlefield", "producedMana" to mutableListOf("C", "C"))
        }
        root["legalActions"] = actions
        if (state == GameBoardDesignPreviewState.NORMAL_BATTLEFIELD && environment["MAGICMOBILE_MDFC_UI_TEST"] == "1") {
            zones(players[0])["hand"] = (0 until 3).map { card("modal-$it", "Revitalizing Repast", "Instant", "{B/G}",
                "Development fixture: Put a +1/+1 counter on target creature.") }.toMutableList()
            for ((index, types) in listOf(listOf("play_land", "cast_spell"), listOf("cast_spell"), listOf("play_land")).withIndex()) {
                for (type in types) actions += mutableMapOf("id" to "modal-$index-$type", "type" to type, "playerId" to "human",
                    "label" to (if (type == "play_land") "Play Old-Growth Grove" else "Cast Revitalizing Repast"), "cardInstanceId" to "modal-$index", "sourceZone" to "hand")
            }
            root["legalActions"] = actions
        }
        val skip = listOf("passedTurn", "passedUntilEndOfTurn", "passedUntilNextMain", "passedUntilStackResolved", "passedAllTurns",
            "passedUntilEndStepBeforeMyTurn").associateWith { false }.toMutableMap<String, Any?>()
        val enginePlayers = players.map { player ->
            val zones = zones(player)
            mutableMapOf("playerId" to player["playerId"], "name" to player["displayName"], "active" to (player["playerId"] == "human"),
                "hasPriority" to (player["playerId"] == root["priorityPlayerId"]), "timerActive" to false, "skipState" to skip,
                "manaPool" to player["manaPool"], "command" to zones["command"],
                "zones" to mutableMapOf("battlefield" to zones["battlefield"], "graveyard" to zones["graveyard"], "exile" to zones["exile"],
                    "sideboard" to mutableListOf<Any?>()))
        }.toMutableList<Any?>()
        val xmage = mutableMapOf<String, Any?>("schemaVersion" to 1, "gameId" to root["id"], "bridgeRevision" to 99,
            "callbackCoverage" to mutableListOf<Any?>(), "players" to enginePlayers, "stack" to mutableListOf<Any?>(), "combat" to mutableListOf<Any?>(),
            "exileZones" to mutableListOf<Any?>(), "revealed" to mutableListOf<Any?>(), "lookedAt" to mutableListOf<Any?>(),
            "companion" to mutableListOf<Any?>(), "playableObjects" to mutableListOf<Any?>(),
            "panels" to panels(stack = state == GameBoardDesignPreviewState.STACK_RESPONSE_PROMPT))
        if (state == GameBoardDesignPreviewState.STACK_RESPONSE_PROMPT) {
            val source = card("ai-1-ability-source", "Prodigal Pyromancer", "Creature — Human Wizard", "{2}{R}", "{T}: This creature deals 1 damage to any target.", 1)
            val spell = card("stack-swords-card", "Swords to Plowshares", "Instant", "{W}", "Exile target creature. Its controller gains life equal to its power.")
            xmage["stack"] = mutableListOf(
                mutableMapOf("id" to "stack-ability-object", "objectId" to "stack-ability-object", "objectType" to "ACTIVATED_ABILITY",
                    "name" to "Deal 1 damage", "rulesText" to "Prodigal Pyromancer deals 1 damage to any target.", "sourceInstanceId" to "ai-1-ability-source",
                    "sourceName" to "Prodigal Pyromancer", "sourceZone" to "battlefield", "sourceCard" to source, "controllerId" to "ai-1",
                    "targetIds" to mutableListOf("human"), "paid" to true),
                mutableMapOf("id" to "stack-spell-object", "objectId" to "stack-spell-object", "objectType" to "SPELL", "name" to "Swords to Plowshares",
                    "sourceName" to "Swords to Plowshares", "sourceCard" to spell, "controllerId" to "human", "targetIds" to mutableListOf("ai-creature-1"), "paid" to true))
        }
        if (state == GameBoardDesignPreviewState.STACK_TRAY) {
            // Roaming Throne doubling Chatterfang: twelve identical triggers above a spell. Preview stacks list the bottom first.
            val chatterfang = card("ai-1-chatterfang", "Chatterfang, Squirrel General", "Legendary Creature — Squirrel Warrior", "{2}{G}", "Forestwalk", 3)
            val spell = card("stack-bolt-card", "Lightning Bolt", "Instant", "{R}", "Lightning Bolt deals 3 damage to any target.")
            xmage["stack"] = (mutableListOf<Any?>(mutableMapOf("id" to "stack-bolt", "objectId" to "stack-bolt", "objectType" to "SPELL", "name" to "Lightning Bolt",
                "sourceName" to "Lightning Bolt", "sourceCard" to spell, "controllerId" to "human", "targetIds" to mutableListOf("ai-1"), "paid" to true)) +
                (0 until 12).map { index -> mutableMapOf("id" to "stack-trigger-$index", "objectId" to "stack-trigger-$index", "objectType" to "TRIGGERED_ABILITY",
                    "name" to "Chatterfang trigger", "rulesText" to "Create a 1/1 green Squirrel creature token.", "sourceInstanceId" to "ai-1-chatterfang",
                    "sourceName" to "Chatterfang, Squirrel General", "sourceZone" to "battlefield", "sourceCard" to deepCopy(chatterfang), "controllerId" to "ai-1", "paid" to true) })
                .toMutableList()
        }
        if (state == GameBoardDesignPreviewState.VICTORY) {
            root["gameStatus"] = "completed"; root["winnerPlayerIds"] = mutableListOf("human"); root["endReason"] = "opponent_lost"
        }
        if (state == GameBoardDesignPreviewState.FIRST_STRIKE) {
            val own = list(zones(players[0])["battlefield"])
            val opposing = list(zones(players[1])["battlefield"])
            xmage["combat"] = mutableListOf(mutableMapOf("defenderId" to "human", "defenderName" to "You", "defenderKind" to "player", "blocked" to true,
                "attackers" to opposing.filter { it["isAttacking"] == true }.toMutableList(), "blockers" to own.filter { it["blocking"] != null }.toMutableList()))
        }
        if (state == GameBoardDesignPreviewState.COMBAT_ARROWS) {
            val own = list(zones(players[0])["battlefield"])
            val opposing = list(zones(players[1])["battlefield"])
            xmage["combat"] = mutableListOf(mutableMapOf("defenderId" to "ai-1", "defenderName" to "Aurelia", "defenderKind" to "player", "blocked" to true,
                "attackers" to own.filter { it["isAttacking"] == true }.toMutableList(), "blockers" to opposing.filter { it["blocking"] != null }.toMutableList()))
            root["phase"] = "combat"; root["step"] = "declare-blockers"
        }
        if (state == GameBoardDesignPreviewState.ZONE_INSPECTION) {
            actions += mutableMapOf("id" to "cast-preview-commander", "type" to "cast_spell", "playerId" to "human", "label" to "Cast commander",
                "cardInstanceId" to "human-command-1", "cardName" to "Isamaru, Hound of Konda", "sourceZone" to "command")
            root["legalActions"] = actions
            for (key in listOf("exileZones", "revealed", "lookedAt", "companion")) {
                xmage[key] = mutableListOf(mutableMapOf("id" to "preview-$key", "name" to "Development $key",
                    "cards" to mutableListOf(card("preview-$key-card", "Forest", "Basic Land — Forest", "", "{T}: Add {G}."))))
            }
        }
        root["xmage"] = xmage
        if (state == GameBoardDesignPreviewState.ABILITY_CHOICE) {
            val source = card("human-sol-ring", "Sol Ring", "Artifact", "{1}", "{T}: Add {C}{C}.")
            root["legalActions"] = mutableListOf<Any?>()
            root["promptEnvelopeV2"] = mutableMapOf("id" to "preview-ability", "method" to "PICK_ABILITY", "messageId" to 12, "playerId" to "human",
                "responseKind" to "ability", "message" to "Choose which triggered ability goes on the stack first", "required" to true,
                "minChoices" to 1, "maxChoices" to 1, "abilities" to mutableListOf(
                    mutableMapOf("id" to "11111111-1111-4111-8111-111111111111", "label" to "Add {C}{C}.", "sourceName" to "Sol Ring", "sourceCard" to source),
                    mutableMapOf("id" to "22222222-2222-4222-8222-222222222222", "label" to "Add {C}{C}.", "sourceName" to "Sol Ring", "sourceCard" to deepCopy(source))),
                "responseCommand" to mutableMapOf("type" to "choose_ability", "promptId" to "preview-ability", "messageId" to 12))
        }
        if (state == GameBoardDesignPreviewState.SEARCH_SELECT_PROMPT) {
            (root["promptEnvelopeV2"] as? MutableMap<String, Any?>)?.let { prompt ->
                val types = listOf("Angel", "Artifact Creature", "Bear", "Beast", "Bird", "Cat", "Cleric", "Dragon", "Druid", "Elemental", "Elf", "Faerie",
                    "Giant", "Goblin", "Human", "Knight", "Merfolk", "Pirate", "Rogue", "Soldier", "Spirit", "Vampire", "Warrior", "Wizard", "Zombie")
                prompt["id"] = "preview-creature-types"
                prompt["message"] = "Development choice fixture: choose a creature type"
                prompt["responseKind"] = "choice"
                prompt["cards"] = mutableListOf<Any?>()
                prompt["choices"] = types.map { mutableMapOf("id" to it.lowercase().replace(" ", "-"), "label" to it) }.toMutableList()
                prompt["responseCommand"] = mutableMapOf("type" to "resolve_choice", "promptId" to "preview-creature-types", "messageId" to 2)
            }
        }
        if (state in setOf(GameBoardDesignPreviewState.SCRY_CHOICE, GameBoardDesignPreviewState.LIBRARY_CHOICE, GameBoardDesignPreviewState.EMPTY_LIBRARY_CHOICE,
                GameBoardDesignPreviewState.MIXED_CARD_CHOICE)) {
            val count = if (state == GameBoardDesignPreviewState.SCRY_CHOICE) 3 else if (state == GameBoardDesignPreviewState.MIXED_CARD_CHOICE) 2 else 12
            val options = (0 until count).map { index ->
                val value = card("choice-$index", if (index % 2 == 0) "Forest" else "Serra Angel", if (index % 2 == 0) "Basic Land" else "Creature", "",
                    if (index == 0) "Development choice fixture: graveyard keyword." else "Development choice fixture.")
                value["selectable"] = state != GameBoardDesignPreviewState.EMPTY_LIBRARY_CHOICE && (state == GameBoardDesignPreviewState.SCRY_CHOICE || index % 2 == 0)
                value
            }
            root["promptEnvelopeV2"] = mutableMapOf("id" to "preview-card-choice", "method" to "GAME_PICK_TARGET", "messageId" to 10, "playerId" to "human",
                "responseKind" to "target", "message" to (if (state == GameBoardDesignPreviewState.SCRY_CHOICE) "Select up to two cards to put on the bottom of your library (Scry)" else "Search your library for a land card"),
                "required" to false, "minChoices" to 1, "maxChoices" to 1, "cards" to options.toMutableList(), "targets" to mutableListOf<Any?>(),
                "options" to (if (state == GameBoardDesignPreviewState.SCRY_CHOICE) mutableMapOf<String, Any?>("chosenTargets" to mutableListOf<Any?>()) else mutableMapOf()),
                "targetIds" to options.filter { it["selectable"] == true }.map { it["instanceId"] }.toMutableList(),
                "responseCommand" to mutableMapOf("type" to "choose_target", "promptId" to "preview-card-choice", "messageId" to 10))
            root["legalActions"] = mutableListOf<Any?>(mutableMapOf("id" to "choice-done", "type" to "answer_yes_no", "playerId" to "human", "label" to "Done",
                "promptId" to "preview-card-choice", "messageId" to 10, "confirmed" to false))
            if (state == GameBoardDesignPreviewState.MIXED_CARD_CHOICE) {
                @Suppress("UNCHECKED_CAST")
                val mixed = root["promptEnvelopeV2"] as MutableMap<String, Any?>
                mixed["message"] = "Choose a card or a player"
                mixed["targets"] = mutableListOf(mutableMapOf("id" to "ai-1", "label" to "AI 1"))
                mixed["targetIds"] = mutableListOf("choice-0", "ai-1")
            }
        }
        if (state == GameBoardDesignPreviewState.NORMAL_BATTLEFIELD) {
            root["log"] = mutableListOf(
                mutableMapOf("id" to "log-1", "message" to "TURN 1 for <font color='#20B2AA'>Caleb</font> (40 - 40)", "createdAt" to "preview"),
                mutableMapOf("id" to "log-2", "message" to "<font color='#20B2AA'>Caleb</font> plays <font color='#B0C4DE' object_id='36fc54d7-1afc-4506-92f8-a4f8cceace1c'>Temple of Plenty</font> [36f]", "createdAt" to "preview"))
        }
        if (state == GameBoardDesignPreviewState.PLAYER_TARGET_PROMPT || state == GameBoardDesignPreviewState.CARD_TARGET_PROMPT) {
            root["legalActions"] = mutableListOf<Any?>()
            val playerPrompt = state == GameBoardDesignPreviewState.PLAYER_TARGET_PROMPT
            val ids = if (playerPrompt) players.map { it["playerId"] as String } else listOf("ai-creature-1", "human-commander")
            val labels = if (playerPrompt) players.map { it["displayName"] as String } else listOf("Serra Angel", "Isamaru, Hound of Konda")
            root["promptEnvelopeV2"] = mutableMapOf("id" to "preview-target", "method" to "GAME_PICK_TARGET", "messageId" to 9, "playerId" to "human",
                "responseKind" to "target", "message" to (if (playerPrompt) "Choose a player to take the first turn" else "Choose target creature"),
                "required" to true, "minChoices" to 1, "maxChoices" to 1, "targetIds" to ids.toMutableList(),
                "targets" to ids.zip(labels).map { mutableMapOf("id" to it.first, "label" to it.second) }.toMutableList(),
                "responseCommand" to mutableMapOf("type" to "choose_target", "promptId" to "preview-target", "messageId" to 9))
        }
        if (state == GameBoardDesignPreviewState.MANA_PAYMENT_PROMPT) {
            root["legalActions"] = actions.filter { it["type"] == "make_mana" }.toMutableList()
            @Suppress("UNCHECKED_CAST")
            (root["promptEnvelopeV2"] as MutableMap<String, Any?>)["message"] = "Pay {2}{W}"
            root["manaPayment"] = mutableMapOf("active" to true, "spellName" to "Serra Angel", "manaCostText" to "{3}{W}{W}", "remainingText" to "{2}{W}",
                "remaining" to mutableMapOf("generic" to 2, "W" to 1, "U" to 0, "B" to 0, "R" to 0, "G" to 0, "C" to 0, "total" to 3))
        }
    }

    private fun json(state: GameBoardDesignPreviewState): String {
        val prompt = promptEnvelope(state)
        val pendingStatus = if (state == GameBoardDesignPreviewState.AI_THINKING) "waiting_for_xmage" else "ready"
        val priorityPlayerId = if (state == GameBoardDesignPreviewState.AI_THINKING) "ai-1" else "human"
        val promptText = if (prompt == null) (if (state == GameBoardDesignPreviewState.AI_THINKING) "AI thinking" else "Your priority") else "Design preview prompt"
        val health = if (state == GameBoardDesignPreviewState.BRIDGE_UNAVAILABLE)
            """"engineHealth":{"status":"unavailable","reason":"Design preview bridge unavailable.","checkedAt":"preview","recoveryAction":"reconnect"},"""
        else """"engineHealth":{"status":"ready","reason":"Design preview only. Not gameplay proof.","checkedAt":"preview","recoveryAction":"none"},"""
        return """
        {"id":"design-preview-${state.rawValue}","source":"design-preview","activePlayerId":"human","phase":"precombat-main","step":"precombat-main",
         "turn":3,"priorityPlayerId":"$priorityPlayerId","waitingOnPlayerId":"$priorityPlayerId","promptText":"$promptText",
         "players":[
          {"playerId":"human","life":37,"poison":0,"commanderTax":2,"manaPool":{"W":1,"U":0,"B":0,"R":0,"G":1,"C":2},
           "zones":${humanZones(state == GameBoardDesignPreviewState.MISSING_CARD_ART)},"commanderDamage":{"ai-1":4,"human":0}},
          {"playerId":"ai-1","life":31,"poison":0,"commanderTax":0,"manaPool":{"W":0,"U":0,"B":0,"R":0,"G":0,"C":0},
           "zones":${opponentZones()},"commanderDamage":{"human":2,"ai-1":0}}],
         "log":[{"id":"log-1","message":"Design preview only: do not use as gameplay proof.","createdAt":"preview"},
                {"id":"log-2","message":"XMage remains the source of truth in real games.","createdAt":"preview"}],
         "legalActions":${actions(state)},"choicePrompt":null,"promptEnvelope":null,"promptEnvelopeV2":${prompt ?: "null"},"xmage":null,
         $health "bridgeRevision":99,"xmageCycle":144,"pendingStatus":"$pendingStatus"}
        """
    }

    private fun humanZones(missingArt: Boolean) = """
        {"library":[${hiddenCard("library-human-1")},${hiddenCard("library-human-2")}],
         "hand":[${zoneCard("hand-sol-ring", "Sol Ring", "Artifact", "{T}: Add {C}{C}.", null, null)},
                 ${zoneCard("hand-forest", "Forest", "Basic Land - Forest", "{T}: Add {G}.", null, null)},
                 ${zoneCard("hand-spell", if (missingArt) "Unknown Preview Card" else "Swords to Plowshares", "Instant", "Exile target creature.", null, null)}],
         "battlefield":[${zoneCard("human-plains-1", "Plains", "Basic Land - Plains", "{T}: Add {W}.", true, null)},
                        ${zoneCard("human-forest-1", "Forest", "Basic Land - Forest", "{T}: Add {G}.", false, null)},
                        ${zoneCard("human-commander", "Isamaru, Hound of Konda", "Legendary Creature - Dog", "Commander", false, "2", summoningSickness = true)}],
         "graveyard":[${zoneCard("human-grave-1", "Spirited Companion", "Enchantment Creature - Dog", "When this enters, draw a card.", null, "1")}],
         "exile":[],
         "command":[${zoneCard("human-command-1", "Isamaru, Hound of Konda", "Legendary Creature - Dog", "Commander", null, "2")}],
         "stack":[]}
    """

    private fun opponentZones() = """
        {"library":[${hiddenCard("library-ai-1")},${hiddenCard("library-ai-2")}],
         "hand":[${hiddenCard("ai-hand-1")},${hiddenCard("ai-hand-2")}],
         "battlefield":[${zoneCard("ai-wastes-1", "Wastes", "Basic Land", "{T}: Add {C}.", true, null)},
                        ${zoneCard("ai-creature-1", "Serra Angel", "Creature - Angel", "Flying, vigilance", false, "4", summoningSickness = true,
                            icons = """[{"iconType":"ABILITY_FLYING","resourceName":"prepared/feather-alt.svg","category":"ABILITY","hint":"Flying"},
                                        {"iconType":"ABILITY_VIGILANCE","resourceName":"prepared/eye.svg","category":"ABILITY","hint":"Vigilance"}]""")}],
         "graveyard":[],"exile":[],
         "command":[${zoneCard("ai-command-1", "Kozilek, Butcher of Truth", "Legendary Creature - Eldrazi", "Commander", null, "12")}],
         "stack":[]}
    """

    private fun zoneCard(id: String, name: String, typeLine: String, oracleText: String, tapped: Boolean?, power: String?,
                         summoningSickness: Boolean? = null, icons: String? = null): String {
        val tappedText = tapped?.let { ""","tapped":$it""" } ?: ""
        val sicknessText = summoningSickness?.let { ""","summoningSickness":$it""" } ?: ""
        val iconsText = icons?.let { ""","cardIcons":$it""" } ?: ""
        val stats = power?.let { ""","power":$it,"toughness":$it""" } ?: ""
        return """{"instanceId":"$id","card":{"name":"$name","typeLine":"$typeLine","oracleText":"$oracleText"}$tappedText$sicknessText$iconsText$stats}"""
    }

    private fun hiddenCard(id: String) = """{"instanceId":"$id","card":{"name":"Hidden card","typeLine":"Hidden","oracleText":null}}"""

    private fun actions(state: GameBoardDesignPreviewState): String = when (state) {
        GameBoardDesignPreviewState.AI_THINKING, GameBoardDesignPreviewState.BRIDGE_UNAVAILABLE, GameBoardDesignPreviewState.UNSUPPORTED_PROMPT_FALLBACK ->
            """[{"id":"concede","type":"concede","playerId":"human","label":"Concede"}]"""
        else -> """[{"id":"cast-sol-ring","type":"cast_spell","playerId":"human","label":"Cast Sol Ring","cardInstanceId":"hand-sol-ring","cardName":"Sol Ring","sourceZone":"hand","isPrimary":true},
                    {"id":"make-mana-forest","type":"make_mana","playerId":"human","label":"Tap Forest","sourceInstanceId":"human-forest-1","cardName":"Forest","producedMana":["G"]},
                    {"id":"pass-priority","type":"pass_priority","playerId":"human","label":"Done"}]"""
    }

    private fun promptEnvelope(state: GameBoardDesignPreviewState): String? = when (state) {
        GameBoardDesignPreviewState.MANA_PAYMENT_PROMPT ->
            """{"id":"preview-mana","method":"GAME_PLAY_MANA","messageId":1,"playerId":"human","responseKind":"mana","message":"Pay {1}{W}","required":true,"minChoices":1,"maxChoices":1,"manaChoices":[{"id":"W","label":"Pay {W}","manaType":"W"},{"id":"C","label":"Pay {C}","manaType":"C"}],"choices":[{"id":"W","label":"Pay {W}"},{"id":"C","label":"Pay {C}"}],"responseCommand":{"type":"play_mana","promptId":"preview-mana","messageId":1}}"""
        GameBoardDesignPreviewState.SEARCH_SELECT_PROMPT ->
            """{"id":"preview-search","method":"GAME_SELECT","messageId":2,"playerId":"human","responseKind":"choose_card","message":"Search your library for a basic land card.","required":true,"minChoices":1,"maxChoices":1,"cards":[{"instanceId":"search-plains","card":{"name":"Plains","typeLine":"Basic Land - Plains","oracleText":"{T}: Add {W}."}},{"instanceId":"search-forest","card":{"name":"Forest","typeLine":"Basic Land - Forest","oracleText":"{T}: Add {G}."}}],"choices":[{"id":"search-plains","label":"Plains","cardInstanceId":"search-plains"},{"id":"search-forest","label":"Forest","cardInstanceId":"search-forest"}],"responseCommand":{"type":"choose_card","promptId":"preview-search","messageId":2}}"""
        GameBoardDesignPreviewState.STACK_RESPONSE_PROMPT ->
            """{"id":"preview-stack","method":"GAME_SELECT","messageId":3,"playerId":"human","responseKind":"priority","message":"Respond to the spell on the stack.","required":false,"minChoices":0,"maxChoices":0,"responseCommand":{"type":"pass_priority","promptId":"preview-stack","messageId":3}}"""
        GameBoardDesignPreviewState.OPENING_HAND ->
            """{"id":"preview-mulligan","method":"GAME_ASK","messageId":2,"playerId":"human","responseKind":"confirmation","message":"Mulligan to 6 cards?","required":true,"minChoices":1,"maxChoices":1,"confirmation":{"yesLabel":"Mulligan","noLabel":"Keep","defaultValue":null,"yesCommand":{"type":"answer_yes_no","promptId":"preview-mulligan","messageId":2,"confirmed":true},"noCommand":{"type":"answer_yes_no","promptId":"preview-mulligan","messageId":2,"confirmed":false}},"responseCommand":{"type":"answer_yes_no","promptId":"preview-mulligan","messageId":2}}"""
        GameBoardDesignPreviewState.COMMANDER_REPLACEMENT_PROMPT ->
            """{"id":"preview-commander-replacement","method":"GAME_ASK","messageId":4,"playerId":"human","responseKind":"commander_replacement","message":"Move your commander to the command zone instead?","required":true,"minChoices":1,"maxChoices":1,"confirmation":{"yesLabel":"Command Zone","noLabel":"Original Zone","defaultValue":null},"choices":[{"id":"true","label":"Command Zone"},{"id":"false","label":"Original Zone"}],"responseCommand":{"type":"commander_replacement","promptId":"preview-commander-replacement","messageId":4}}"""
        GameBoardDesignPreviewState.DAMAGE_ASSIGNMENT_PROMPT ->
            """{"id":"preview-damage","method":"GAME_GET_MULTI_AMOUNT","messageId":5,"playerId":"human","responseKind":"multi_amount","message":"Assign 6 combat damage among blockers.","required":true,"minChoices":2,"maxChoices":2,"totalMin":6,"totalMax":6,"multiAmounts":[{"id":"blocker-a","label":"Silvercoat Lion","min":1,"max":5,"defaultValue":1},{"id":"blocker-b","label":"Memnite","min":1,"max":5,"defaultValue":1}],"responseCommand":{"type":"choose_multi_amount","promptId":"preview-damage","messageId":5}}"""
        GameBoardDesignPreviewState.MODE_CHOICE ->
            """{"id":"preview-modes","method":"GAME_CHOOSE_CHOICE","messageId":7,"playerId":"human","responseKind":"mode","message":"Choose mode (selected 0 of 3, min 1)\nBlack Market Connections [4cb]","required":true,"minChoices":1,"maxChoices":3,"modes":[{"id":"mode-1","label":"1. Create a Treasure token. You lose 1 life."},{"id":"mode-2","label":"2. Draw a card. You lose 2 life."},{"id":"mode-3","label":"3. Create a 3/2 colorless Shapeshifter creature token with changeling. You lose 3 life."}],"responseCommand":{"type":"choose_mode","promptId":"preview-modes","messageId":7}}"""
        GameBoardDesignPreviewState.UNSUPPORTED_PROMPT_FALLBACK ->
            """{"id":"preview-unsupported","method":"GAME_UNSUPPORTED_ROUTE","messageId":6,"playerId":"human","responseKind":"unsupported_mobile_prompt","message":"XMage is asking for a route the mobile client must not answer by default.","required":true,"minChoices":1,"maxChoices":1,"responseCommand":{"type":"unsupported_mobile_prompt","promptId":"preview-unsupported","messageId":6}}"""
        else -> null
    }

    // Swift's [String: Any] manipulation, in Kotlin collections.
    @Suppress("UNCHECKED_CAST")
    private fun players(root: MutableMap<String, Any?>): MutableList<MutableMap<String, Any?>> = root["players"] as MutableList<MutableMap<String, Any?>>
    @Suppress("UNCHECKED_CAST")
    private fun zones(player: MutableMap<String, Any?>): MutableMap<String, Any?> = player["zones"] as MutableMap<String, Any?>
    @Suppress("UNCHECKED_CAST")
    private fun list(value: Any?): MutableList<MutableMap<String, Any?>> = value as MutableList<MutableMap<String, Any?>>
    @Suppress("UNCHECKED_CAST")
    private fun map(value: Any?): MutableMap<String, Any?> = value as MutableMap<String, Any?>

    private fun deepCopy(value: Any?): Any? = when (value) {
        is Map<*, *> -> value.entries.associate { it.key as String to deepCopy(it.value) }.toMutableMap()
        is List<*> -> value.map(::deepCopy).toMutableList()
        else -> value
    }

    private fun toKotlin(element: JsonElement): Any? = when (element) {
        is JsonObject -> element.entries.associate { it.key to toKotlin(it.value) }.toMutableMap()
        is JsonArray -> element.map(::toKotlin).toMutableList()
        is JsonNull -> null
        is JsonPrimitive -> if (element.isString) element.content else element.content.toLongOrNull()?.let {
            if (it in Int.MIN_VALUE..Int.MAX_VALUE) it.toInt() else it
        } ?: element.content.toBooleanStrictOrNull() ?: element.content.toDouble()
    }

    private fun toJson(value: Any?): JsonElement = when (value) {
        null -> JsonNull
        is JsonElement -> value
        is Map<*, *> -> JsonObject(value.entries.associate { it.key as String to toJson(it.value) })
        is List<*> -> JsonArray(value.map(::toJson))
        is String -> JsonPrimitive(value)
        is Boolean -> JsonPrimitive(value)
        is Number -> JsonPrimitive(value)
        else -> throw IllegalArgumentException("Unsupported fixture value $value")
    }
}
