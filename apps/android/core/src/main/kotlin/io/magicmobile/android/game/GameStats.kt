package io.magicmobile.android.game

import kotlin.math.roundToInt

/**
 * Port of GameStats.swift: what happened in one game, gathered from consecutive snapshots for
 * the result screen. Only public information is used: life totals, combat groups and zones.
 */
class GameStats {
    var gameID = ""; private set
    var turns = 0; private set
    var startingLife: Int? = null; private set
    var finalLife: Int? = null; private set
    /** Combat damage your unblocked attackers dealt to players. */
    var combatDamage = 0; private set
    /** The largest combat hit you landed on one player at once. */
    var biggestHit = 0; private set
    val damageByCard = LinkedHashMap<String, Int>()
    var creaturesDestroyed = 0; private set
    var creaturesLost = 0; private set
    private var previous: Capture? = null

    private data class Attack(val defender: String, val attackers: List<Pair<String, Int>>)
    private data class Capture(val life: Map<String, Int>, val battlefieldCreatures: Map<String, Set<String>>, val attacks: List<Attack>)

    fun record(snapshot: GameSnapshot) {
        if (snapshot.id != gameID) reset(snapshot.id)
        turns = maxOf(turns, snapshot.turn)
        val viewer = snapshot.viewerID
        snapshot.human?.life?.let { life ->
            if (startingLife == null) startingLife = life
            finalLife = life
        }
        val yours = snapshot.human?.zones?.battlefield?.map { it.instanceId }?.toSet() ?: emptySet()
        val life = LinkedHashMap<String, Int>(); snapshot.players.forEach { life.putIfAbsent(it.playerId, it.life) }
        val creatures = LinkedHashMap<String, Set<String>>()
        snapshot.players.forEach { player -> creatures.putIfAbsent(player.playerId, player.zones.battlefield.filter { it.isCreature }.map { it.instanceId }.toSet()) }
        val attacks = (snapshot.xmage?.combat ?: emptyList()).mapNotNull { group ->
            if (group.blocked || group.defenderId == viewer) return@mapNotNull null
            val mine = group.attackers.filter { it.instanceId in yours }
                .map { it.card.name to maxOf(0, it.displayPower?.toIntOrNull() ?: it.power ?: 0) }
                .filter { it.second > 0 }
            if (mine.isEmpty()) null else Attack(group.defenderId, mine)
        }
        val capture = Capture(life, creatures, attacks)
        previous?.let { compare(it, capture, snapshot) }
        previous = capture
    }

    private fun reset(id: String) {
        gameID = id; turns = 0; startingLife = null; finalLife = null; combatDamage = 0; biggestHit = 0
        damageByCard.clear(); creaturesDestroyed = 0; creaturesLost = 0; previous = null
    }

    private fun compare(old: Capture, new: Capture, snapshot: GameSnapshot) {
        // Credit a defender's life loss to the unblocked attackers that were swinging at them.
        for (attack in old.attacks) {
            val before = old.life[attack.defender] ?: continue
            val after = new.life[attack.defender] ?: continue
            if (after >= before) continue
            val total = attack.attackers.sumOf { it.second }
            val credited = minOf(total, before - after)
            if (total <= 0 || credited <= 0) continue
            combatDamage += credited
            biggestHit = maxOf(biggestHit, credited)
            for ((name, power) in attack.attackers) {
                damageByCard[name] = (damageByCard[name] ?: 0) + (power.toDouble() * credited / total).roundToInt()
            }
        }
        // A creature that left the battlefield for its owner's graveyard died (tokens just vanish).
        for (player in snapshot.players) {
            val gone = (old.battlefieldCreatures[player.playerId] ?: emptySet()) - (new.battlefieldCreatures[player.playerId] ?: emptySet())
            if (gone.isEmpty()) continue
            val graveyard = player.zones.graveyard.map { it.instanceId }.toSet()
            val died = gone.count { it in graveyard }
            if (snapshot.isViewer(player.playerId)) creaturesLost += died else creaturesDestroyed += died
        }
    }

    /** The card of yours that dealt the most combat damage to players. */
    val topCard: Pair<String, Int>? get() = damageByCard.entries
        .maxWithOrNull { a, b -> if (a.value != b.value) a.value.compareTo(b.value) else b.key.compareTo(a.key) }
        ?.takeIf { it.value > 0 }?.let { it.key to it.value }
}

/** Port of OpeningHandChoice: XMage's mulligan question, answered from the opening-hand screen. */
class OpeningHandChoice private constructor(val message: String, val keepLabel: String, val mulliganLabel: String, val keep: GameCommand,
                                            val mulligan: GameCommand, val promptID: String) {
    companion object {
        private val tags = Regex("<[^>]+>")

        fun of(snapshot: GameSnapshot): OpeningHandChoice? {
            val prompt = snapshot.promptEnvelopeV2 ?: return null
            val confirmation = prompt.confirmation ?: return null
            if (!prompt.message.contains("mulligan", ignoreCase = true)) return null
            val yes = confirmation.yesCommand ?: return null
            val no = confirmation.noCommand ?: return null
            fun command(response: XmageResponseCommand): GameCommand? {
                val type = response.type ?: return null
                val promptId = response.promptId ?: return null
                val confirmed = response.confirmed ?: response.pay ?: return null
                return UniversalPromptResponseCommandBuilder.command(snapshot.id, snapshot.bridgeRevision, prompt, type, promptId, prompt.playerId,
                    listOf(if (confirmed) "true" else "false"), pay = response.pay ?: confirmed)
            }
            // XMage's left button (yes) mulligans; the right one (no) keeps.
            val mulligan = command(yes) ?: return null
            val keep = command(no) ?: return null
            return OpeningHandChoice(prompt.message.replace(tags, ""), confirmation.noLabel ?: "Keep", confirmation.yesLabel ?: "Mulligan",
                keep, mulligan, prompt.id)
        }
    }
}
