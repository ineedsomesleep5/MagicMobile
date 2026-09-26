package io.magicmobile.android.game

/**
 * Port of apps/ios/MagicMobile/BoardEventTimeline.swift. Board FX: turn successive public
 * snapshots into presentation events. XMage stays the source of truth; these events only
 * decorate a transition the client already applied. Times are seconds; dates are
 * milliseconds since the epoch (Swift `Date`).
 */
enum class BoardFXZone { HAND, LIBRARY, BATTLEFIELD, GRAVEYARD, EXILE, COMMAND, STACK }

enum class BoardFXTint {
    WHITE, BLUE, BLACK, RED, GREEN, MULTICOLOR, COLORLESS;

    companion object {
        fun of(card: CardIdentity): BoardFXTint {
            val colors = mutableSetOf<String>()
            card.manaCost?.uppercase()?.let { cost -> for (symbol in listOf("W", "U", "B", "R", "G")) if (cost.contains(symbol)) colors += symbol }
            if (colors.isEmpty()) {
                for (color in card.tokenColors ?: emptyList()) when (color.lowercase()) {
                    "w", "white" -> colors += "W"; "u", "blue" -> colors += "U"; "b", "black" -> colors += "B"
                    "r", "red" -> colors += "R"; "g", "green" -> colors += "G"
                }
            }
            return when (colors.size) {
                0 -> COLORLESS
                1 -> when (colors.first()) { "W" -> WHITE; "U" -> BLUE; "B" -> BLACK; "R" -> RED; else -> GREEN }
                else -> MULTICOLOR
            }
        }
    }
}

/** Printed mana value from a visible cost such as "{3}{B}{B}". X counts as zero. */
object BoardFXManaValue {
    private val symbol = Regex("\\{([^}]+)\\}")
    fun of(cost: String?): Int {
        cost ?: return 0
        return symbol.findAll(cost).sumOf { match ->
            val s = match.groupValues[1].uppercase()
            s.toIntOrNull() ?: when {
                s == "X" || s == "Y" || s == "Z" -> 0
                s.startsWith("2/") -> 2 // {2/W} costs two; other hybrid and Phyrexian symbols cost one.
                else -> 1
            }
        }
    }
}

/** Cheap change key: the board recomputes FX state only when this moves. */
data class BoardFXRevisionKey(val gameID: String, val bridgeRevision: Int?, val xmageCycle: Int?, val turn: Int, val lives: List<Int>) {
    constructor(snapshot: GameSnapshot) : this(snapshot.id, snapshot.bridgeRevision, snapshot.xmageCycle, snapshot.turn, snapshot.players.map { it.life })
}

/** Minimal public board state used for diffing. */
data class BoardFXState(val gameID: String, val step: String, val lives: Map<String, Int>, val cards: Map<String, Card>,
                        val stack: List<StackItem> = emptyList(), val defenders: Map<String, String> = emptyMap(),
                        val commandNames: Set<String> = emptySet(),
                        /** Attackers whose combat group is blocked, even if every blocker has since left. */
                        val blockedAttackers: Set<String> = emptySet()) {
    /** `keywords`: combat keywords, read only for cards attacking or blocking. */
    data class Card(val id: String, val playerID: String, val zone: BoardFXZone, val name: String, val tint: BoardFXTint, val damage: Int,
                    val counters: Int, val attacking: Boolean, val blocking: List<String> = emptyList(), val isLand: Boolean = false,
                    val isToken: Boolean = false, val keywords: Set<CombatKeyword> = emptySet())
    data class StackItem(val id: String, val name: String, val controllerID: String?, val tint: BoardFXTint, val isAbility: Boolean = false,
                         val manaValue: Int = 0)

    companion object {
        fun of(snapshot: GameSnapshot): BoardFXState {
            val lives = LinkedHashMap<String, Int>()
            snapshot.players.forEach { lives.putIfAbsent(it.playerId, it.life) }
            val cards = LinkedHashMap<String, Card>()
            val commandNames = mutableSetOf<String>()
            for (player in snapshot.players) {
                val z = player.zones
                val zones = listOf(BoardFXZone.HAND to z.hand, BoardFXZone.LIBRARY to z.library, BoardFXZone.BATTLEFIELD to z.battlefield,
                    BoardFXZone.GRAVEYARD to z.graveyard, BoardFXZone.EXILE to z.exile, BoardFXZone.COMMAND to z.command, BoardFXZone.STACK to z.stack)
                for ((zone, zoneCards) in zones) for (card in zoneCards) {
                    if (cards.containsKey(card.instanceId)) continue
                    cards[card.instanceId] = Card(card.instanceId, player.playerId, zone, card.card.name, BoardFXTint.of(card.card), card.damage ?: 0,
                        (card.counters ?: emptyMap()).values.sum(), card.isAttacking == true, card.blocking ?: emptyList(), card.card.isLand,
                        card.card.isToken == true, if (zone == BoardFXZone.BATTLEFIELD && card.isInCombat) card.combatKeywords.toSet() else emptySet())
                }
                for (card in z.command) if (card.card.isToken != true) commandNames += card.card.name
            }
            val stack = snapshot.stackTopFirst.map { item ->
                val source = item.displaySourceCard
                val tint = item.sourceCard?.let { BoardFXTint.of(it.card) } ?: BoardFXTint.COLORLESS
                val ability = item.objectType?.contains("ability", ignoreCase = true) == true || item.displayName.contains("ability", ignoreCase = true)
                StackItem(item.id, item.displayName, item.controllerId, tint, ability, BoardFXManaValue.of(source?.card?.manaCost))
            }
            val defenders = LinkedHashMap<String, String>()
            val blocked = mutableSetOf<String>()
            for (group in snapshot.xmage?.combat ?: emptyList()) for (attacker in group.attackers) {
                defenders[attacker.instanceId] = group.defenderId
                if (group.blocked) blocked += attacker.instanceId
            }
            return BoardFXState(snapshot.id, (snapshot.step ?: snapshot.phase).lowercase().replace("_", "-"), lives, cards, stack, defenders,
                commandNames, blocked)
        }
    }
}

/** How much ceremony a stack object gets. */
enum class BoardFXSpellWeight { ABILITY, SPELL, BIG, COMMANDER }

/** How a permanent arrives: straight to its slot, or shown at the center first. */
enum class BoardFXEntrance { PLAIN, SHOWCASE, COMMANDER }

sealed class BoardFXStrikeTarget {
    data class Card(val id: String) : BoardFXStrikeTarget()
    data class Player(val id: String) : BoardFXStrikeTarget()
}

sealed class BoardFXEvent {
    data class SpellCast(val stackID: String, val name: String, val controllerID: String?, val tint: BoardFXTint, val weight: BoardFXSpellWeight) : BoardFXEvent()
    data class AttackDeclared(val cardID: String, val tint: BoardFXTint) : BoardFXEvent()
    data class BlockDeclared(val cardID: String, val attackerID: String) : BoardFXEvent()
    /**
     * XMage's first-strike combat damage step: a "First strike" label spans its strikes, damage
     * and deaths, and the regular damage waits for it (see BoardFXScheduler).
     */
    data object FirstStrikeBeat : BoardFXEvent()
    /** `firstStrike` marks a strike in the first-strike damage step. */
    data class CombatStrike(val attackerID: String, val target: BoardFXStrikeTarget, val tint: BoardFXTint, val firstStrike: Boolean = false) : BoardFXEvent()
    data class DamageMarked(val cardID: String, val amount: Int) : BoardFXEvent()
    data class LeftBattlefield(val cardID: String, val playerID: String, val to: BoardFXZone?, val tint: BoardFXTint) : BoardFXEvent()
    data class EnteredBattlefield(val cardID: String, val playerID: String, val from: BoardFXZone?, val tint: BoardFXTint, val entrance: BoardFXEntrance) : BoardFXEvent()
    data class CountersAdded(val cardID: String, val amount: Int) : BoardFXEvent()
    data class LifeChanged(val playerID: String, val delta: Int) : BoardFXEvent()

    /** Presentation order inside one snapshot transition. */
    val order: Int get() = when (this) {
        is SpellCast -> 0; is AttackDeclared -> 1; is BlockDeclared -> 2; FirstStrikeBeat -> 3
        is CombatStrike -> if (firstStrike) 4 else 5; is DamageMarked -> 6
        is LeftBattlefield -> 7; is EnteredBattlefield -> 8; is CountersAdded -> 9; is LifeChanged -> 10
    }

    /** Card, stack object or player the effect is about. */
    val subjectID: String get() = when (this) {
        is SpellCast -> stackID; is LeftBattlefield -> cardID; is DamageMarked -> cardID; is EnteredBattlefield -> cardID
        is CountersAdded -> cardID; is AttackDeclared -> cardID; is BlockDeclared -> cardID; is CombatStrike -> attackerID; is LifeChanged -> playerID
        FirstStrikeBeat -> FIRST_STRIKE_SUBJECT
    }

    /** Life totals and the first-strike label are always shown; they carry game information. */
    val isEssential: Boolean get() = this is LifeChanged || this == FirstStrikeBeat

    /** A strike in the regular combat damage step. */
    val isRegularStrike: Boolean get() = this is CombatStrike && !firstStrike

    companion object {
        /** Subject of the first-strike label, which is about the step, not a card. */
        const val FIRST_STRIKE_SUBJECT = "first-strike"
    }
}

object BoardEventDiffer {
    /** Steps before combat damage; leaving them with attackers present means damage was dealt. */
    val preDamageSteps = setOf("combat", "begin-combat", "declare-attackers", "declare-blockers")
    /** Spells at or above this printed mana value get the big-spell flash. */
    const val bigSpellManaValue = 6

    fun events(old: BoardFXState, new: BoardFXState, commanders: Set<String> = emptySet()): List<BoardFXEvent> {
        // A new game, reconnect or design preview swap is a cut, not a transition.
        if (old.gameID != new.gameID) return emptyList()
        val events = mutableListOf<BoardFXEvent>()
        val oldStackIDs = old.stack.map { it.id }.toSet()
        val castNames = mutableSetOf<String>()
        for (item in new.stack) {
            if (oldStackIDs.contains(item.id)) continue
            val weight = when {
                item.isAbility -> BoardFXSpellWeight.ABILITY
                commanders.contains(item.name) -> BoardFXSpellWeight.COMMANDER
                item.manaValue >= bigSpellManaValue -> BoardFXSpellWeight.BIG
                else -> BoardFXSpellWeight.SPELL
            }
            if (!item.isAbility) castNames += item.name
            events += BoardFXEvent.SpellCast(item.id, item.name, item.controllerID, item.tint, weight)
        }
        // A permanent spell that was on the stack flies from there, without a second showcase.
        val resolvedNames = old.stack.filter { !it.isAbility }.map { it.name }.toSet() + castNames
        val claimedArrivals = mutableSetOf<String>()
        for (card in old.cards.values.sortedBy { it.id }) {
            if (card.zone != BoardFXZone.BATTLEFIELD) continue
            val next = new.cards[card.id]
            if (next != null) {
                if (next.zone != BoardFXZone.BATTLEFIELD) events += BoardFXEvent.LeftBattlefield(card.id, card.playerID, next.zone, card.tint)
                continue
            }
            // XMage can assign a new object ID on a zone change. Match the same name arriving in a public zone of the same player.
            val arrival = new.cards.values.filter { it.playerID == card.playerID && it.name == card.name && old.cards[it.id] == null && !claimedArrivals.contains(it.id) }
                .filter { it.zone in setOf(BoardFXZone.GRAVEYARD, BoardFXZone.EXILE, BoardFXZone.COMMAND) }.minByOrNull { it.id }
            arrival?.let { claimedArrivals += it.id }
            events += BoardFXEvent.LeftBattlefield(card.id, card.playerID, arrival?.zone, card.tint)
        }
        for (card in new.cards.values.sortedBy { it.id }) {
            if (card.zone != BoardFXZone.BATTLEFIELD) continue
            val previous = old.cards[card.id]
            if (previous == null || previous.zone != BoardFXZone.BATTLEFIELD) {
                var source = previous?.zone
                val entrance: BoardFXEntrance
                if (!card.isToken && commanders.contains(card.name)) {
                    entrance = BoardFXEntrance.COMMANDER
                    if (resolvedNames.contains(card.name)) source = BoardFXZone.STACK
                } else if (resolvedNames.contains(card.name) && source != BoardFXZone.HAND) {
                    entrance = BoardFXEntrance.PLAIN
                    source = BoardFXZone.STACK
                } else if (!card.isLand && !card.isToken && (source == null || source == BoardFXZone.HAND)) {
                    // Cast and resolved between two snapshots: nobody saw it on the stack.
                    entrance = BoardFXEntrance.SHOWCASE
                } else entrance = BoardFXEntrance.PLAIN
                events += BoardFXEvent.EnteredBattlefield(card.id, card.playerID, source, card.tint, entrance)
                continue
            }
            if (card.attacking && !previous.attacking) events += BoardFXEvent.AttackDeclared(card.id, card.tint)
            val attacker = card.blocking.firstOrNull()
            if (attacker != null && previous.blocking.isEmpty()) events += BoardFXEvent.BlockDeclared(card.id, attacker)
            if (card.damage > previous.damage) events += BoardFXEvent.DamageMarked(card.id, card.damage - previous.damage)
            if (card.counters > previous.counters) events += BoardFXEvent.CountersAdded(card.id, card.counters - previous.counters)
        }
        events += combatStrikes(old, new)
        for ((playerID, life) in new.lives.toSortedMap()) {
            val previous = old.lives[playerID]
            if (previous != null && previous != life) events += BoardFXEvent.LifeChanged(playerID, life - previous)
        }
        return events.withIndex().sortedWith(compareBy({ it.value.order }, { it.index })).map { it.value }
    }

    /** XMage's first-strike combat damage step, normalized like `BoardFXState.step`. */
    const val firstStrikeStep = "first-combat-damage"

    /**
     * Combat damage, one beat per damage step. XMage reports its first-strike step when a creature
     * in combat has first or double strike: entering it plays the "First strike" beat with the
     * attackers that strike first; leaving it plays the regular strikes. A transition that skips
     * the first-strike snapshot plays both beats, first strikers first, but cannot tell which damage
     * came from which step, so damage and deaths follow the regular strikes.
     */
    fun combatStrikes(old: BoardFXState, new: BoardFXState): List<BoardFXEvent> {
        val afterDamage = !preDamageSteps.contains(new.step) && new.step != firstStrikeStep
        val attackers = old.cards.values.sortedBy { it.id }.filter { it.zone == BoardFXZone.BATTLEFIELD && it.attacking }
        fun strikes(cards: List<BoardFXState.Card>, firstStrike: Boolean): List<BoardFXEvent> = cards.mapNotNull { attacker ->
            strikeTarget(attacker, old, new)?.let { BoardFXEvent.CombatStrike(attacker.id, it, attacker.tint, firstStrike) }
        }
        val first = attackers.filter { CombatKeyword.strikesFirst(keywords(it.id, old, new)) }
        val regular = attackers.filter { CombatKeyword.strikesInRegularStep(keywords(it.id, old, new)) }
        if (preDamageSteps.contains(old.step) && new.step == firstStrikeStep) return listOf(BoardFXEvent.FirstStrikeBeat) + strikes(first, true)
        if (old.step == firstStrikeStep && afterDamage) return strikes(regular, false)
        if (!(preDamageSteps.contains(old.step) && afterDamage)) return emptyList()
        val firstStrikes = strikes(first, true)
        if (firstStrikes.isEmpty()) return strikes(attackers, false)
        return listOf(BoardFXEvent.FirstStrikeBeat) + firstStrikes + strikes(regular, false)
    }

    fun keywords(id: String, old: BoardFXState, new: BoardFXState): Set<CombatKeyword> =
        (old.cards[id]?.keywords ?: emptySet()) + (new.cards[id]?.keywords ?: emptySet())

    /**
     * Blocker first, then the public combat defender, then the first opponent. A blocked attacker
     * whose blockers have all left deals no combat damage unless it has trample.
     */
    fun strikeTarget(attacker: BoardFXState.Card, old: BoardFXState, new: BoardFXState): BoardFXStrikeTarget? {
        val blockers = (old.cards.values.filter { it.zone == BoardFXZone.BATTLEFIELD && it.blocking.contains(attacker.id) } +
            new.cards.values.filter { it.zone == BoardFXZone.BATTLEFIELD && it.blocking.contains(attacker.id) }).map { it.id }.sorted()
        blockers.firstOrNull()?.let { return BoardFXStrikeTarget.Card(it) }
        if ((old.blockedAttackers.contains(attacker.id) || new.blockedAttackers.contains(attacker.id)) &&
            CombatKeyword.TRAMPLE !in keywords(attacker.id, old, new)) return null
        val defender = old.defenders[attacker.id] ?: new.defenders[attacker.id]
        if (defender != null) {
            if (old.lives[defender] != null) return BoardFXStrikeTarget.Player(defender)
            if (old.cards[defender] != null) return BoardFXStrikeTarget.Card(defender)
        }
        val opponent = old.lives.keys.sorted().firstOrNull { it != attacker.playerID }
        return BoardFXStrikeTarget.Player(opponent ?: attacker.playerID)
    }
}

enum class BoardFXLevel(val rawValue: String, val title: String) {
    FULL("full", "Full"), REDUCED("reduced", "Reduced"), OFF("off", "Off");

    companion object {
        const val key = "magicmobile.boardEffectsLevel"
        val defaultValue = FULL.rawValue
        fun of(raw: String?): BoardFXLevel? = entries.firstOrNull { it.rawValue == raw }
        /** System reduced motion always caps the level at REDUCED. */
        fun resolved(stored: String, reduceMotion: Boolean): BoardFXLevel {
            val level = of(stored) ?: FULL
            return if (reduceMotion && level == FULL) REDUCED else level
        }
    }
}

data class ScheduledBoardFX(val id: Int, val event: BoardFXEvent, val delay: Double, val duration: Double, val usesMotion: Boolean) {
    val end: Double get() = delay + duration

    /** When a card arriving with this effect lands in its slot (the tile appears). */
    val landing: Double get() {
        val entered = event as? BoardFXEvent.EnteredBattlefield
        if (!usesMotion || entered == null) return delay
        return delay + duration * BoardFXScheduler.landingFraction(entered.entrance)
    }

    /** When the next group may begin: showcases finish first, strikes hand over at impact, arrivals once they land. */
    val handoff: Double get() = when (event) {
        is BoardFXEvent.SpellCast -> if (!usesMotion) delay + 0.4 else if (event.weight == BoardFXSpellWeight.ABILITY) delay + 0.55 else end - 0.3
        is BoardFXEvent.CombatStrike -> if (usesMotion) delay + duration * BoardFXScheduler.strikeImpactFraction else delay + 0.06
        // The label opens the beat; its strikes follow at once.
        BoardFXEvent.FirstStrikeBeat -> delay + if (usesMotion) 0.15 else 0.06
        is BoardFXEvent.EnteredBattlefield -> if (usesMotion && event.entrance != BoardFXEntrance.PLAIN) landing else delay + if (usesMotion) 0.16 else 0.06
        else -> delay + if (usesMotion) 0.16 else 0.06
    }

    /**
     * Until when a later snapshot's effects wait: a showcase until it hands off, and the
     * first-strike beat until it ends, so the regular damage never overlaps it.
     */
    val holdsLaterBatchesUntil: Double? get() = if (event == BoardFXEvent.FirstStrikeBeat) end else if (isSequential) handoff else null

    /** Showcases share the center of the board, so they play one after another. */
    val isSequential: Boolean get() {
        if (!usesMotion) return false
        return when (event) {
            is BoardFXEvent.SpellCast -> event.weight != BoardFXSpellWeight.ABILITY
            is BoardFXEvent.EnteredBattlefield -> event.entrance != BoardFXEntrance.PLAIN
            else -> false
        }
    }
}

object BoardFXScheduler {
    /** Decorative effects per transition; board wipes collapse to the first few. */
    const val decorativeLimit = 10
    const val stagger = 0.07
    /** Effects never wait more than this for a showcase from an earlier snapshot. */
    const val maximumHold = 3.0
    /** Share of a plain arrival spent flying before the card lands (Full level only). */
    const val arrivalFlightFraction = 0.42
    /** Share of a strike spent winding up and charging before impact. */
    const val strikeImpactFraction = 0.42

    fun schedule(events: List<BoardFXEvent>, level: BoardFXLevel, firstID: Int = 0, hold: Double = 0.0): List<ScheduledBoardFX> {
        if (level == BoardFXLevel.OFF) return emptyList()
        val motion = level == BoardFXLevel.FULL
        var decorativeCount = 0
        val kept = mutableListOf<BoardFXEvent>()
        for (event in events) {
            if (event.isEssential) kept += event
            else if (decorativeCount < decorativeLimit) { decorativeCount += 1; kept += event }
        }
        val result = mutableListOf<ScheduledBoardFX>()
        var groupStart = minOf(maxOf(hold, 0.0), maximumHold)
        var sequentialCursor = groupStart
        var previousOrder: Int? = null
        var indexInGroup = 0
        for (event in kept) {
            if (previousOrder != null && previousOrder != event.order) {
                groupStart = result.maxOfOrNull { it.handoff } ?: groupStart
                // Regular damage waits a short beat after the first strikers' hits.
                if (event.isRegularStrike) firstStrikeBeatEnd(result, motion)?.let { groupStart = maxOf(groupStart, it) }
                sequentialCursor = groupStart
                indexInGroup = 0
            }
            previousOrder = event.order
            val duration = duration(event, motion)
            val id = firstID + result.size
            val probe = ScheduledBoardFX(id, event, 0.0, duration, motion)
            val fx = if (probe.isSequential) {
                ScheduledBoardFX(id, event, sequentialCursor, duration, motion).also { sequentialCursor = it.handoff + 0.1 }
            } else {
                ScheduledBoardFX(id, event, groupStart + indexInGroup * (if (motion) stagger else 0.02), duration, motion).also { indexInGroup += 1 }
            }
            result += fx
        }
        // The label spans its beat, so a later snapshot's regular damage waits for it too.
        val index = result.indexOfFirst { it.event == BoardFXEvent.FirstStrikeBeat }
        if (index >= 0) {
            val label = result[index]
            val end = firstStrikeBeatEnd(result, motion) ?: label.end
            result[index] = label.copy(duration = maxOf(label.duration, end - label.delay))
        }
        return result
    }

    /** The pause between the first-strike beat and the regular damage. */
    fun firstStrikeBeatPause(motion: Boolean): Double = if (motion) 0.3 else 0.15

    /**
     * When the first-strike beat is over: a short pause after its strikes, and, when the batch
     * holds only that step, after its damage and deaths too.
     */
    fun firstStrikeBeatEnd(scheduled: List<ScheduledBoardFX>, motion: Boolean): Double? {
        val combined = scheduled.any { it.event.isRegularStrike }
        val beat = scheduled.filter { fx ->
            when (val event = fx.event) {
                is BoardFXEvent.CombatStrike -> event.firstStrike
                is BoardFXEvent.DamageMarked, is BoardFXEvent.LeftBattlefield -> !combined
                else -> false
            }
        }
        if (scheduled.none { it.event == BoardFXEvent.FirstStrikeBeat }) return null
        val end = beat.maxOfOrNull { it.end } ?: return null
        return end + firstStrikeBeatPause(motion)
    }

    fun landingFraction(entrance: BoardFXEntrance): Double = when (entrance) {
        BoardFXEntrance.PLAIN -> arrivalFlightFraction; BoardFXEntrance.SHOWCASE -> 0.82; BoardFXEntrance.COMMANDER -> 0.8
    }

    fun duration(event: BoardFXEvent, motion: Boolean): Double = when (event) {
        // Long enough to read the card at the center before it moves on.
        is BoardFXEvent.SpellCast -> when (event.weight) {
            BoardFXSpellWeight.ABILITY -> if (motion) 1.3 else 1.1
            BoardFXSpellWeight.SPELL -> if (motion) 2.4 else 1.5
            BoardFXSpellWeight.BIG -> if (motion) 2.7 else 1.5
            BoardFXSpellWeight.COMMANDER -> if (motion) 3.1 else 1.6
        }
        is BoardFXEvent.EnteredBattlefield -> if (!motion) 0.9 else when (event.entrance) {
            BoardFXEntrance.PLAIN -> 1.0; BoardFXEntrance.SHOWCASE -> 2.5; BoardFXEntrance.COMMANDER -> 3.1
        }
        is BoardFXEvent.LeftBattlefield -> if (motion) 0.95 else 0.9
        is BoardFXEvent.DamageMarked -> 0.8
        is BoardFXEvent.CountersAdded -> 0.7
        is BoardFXEvent.AttackDeclared -> if (motion) 0.7 else 0.6
        is BoardFXEvent.BlockDeclared -> if (motion) 0.8 else 0.6
        is BoardFXEvent.CombatStrike -> if (motion) 0.95 else 0.6
        BoardFXEvent.FirstStrikeBeat -> if (motion) 1.2 else 1.0
        is BoardFXEvent.LifeChanged -> if (motion) 1.3 else 0.9
    }
}

/** An effect in flight; `start` is epoch milliseconds (Swift `Date`). */
data class ActiveBoardFX(val scheduled: ScheduledBoardFX, val start: Long) {
    val id: Int get() = scheduled.id
    val endDate: Long get() = start + (scheduled.end * 1000).toLong()
}

/** `hidden`: windows per card, in the order their effects were scheduled (a double striker flies twice). */
data class BoardFXCardMotion(val hidden: Map<String, List<Hidden>> = emptyMap(), val lunges: Map<String, Lunge> = emptyMap(),
                             val stances: Map<String, Stance> = emptyMap()) {
    /** -1 moves up the screen (the viewer's creatures), +1 moves down. */
    data class Lunge(val token: Int, val direction: Double)
    /** A window, timed from the batch's first drawn frame, in which a flight draws the card instead of its tile. */
    data class Hidden(val batch: Long, val from: Double, val until: Double)
    /** Combat posture held for as long as the snapshot says so. Reduced level keeps the glow but not the offset. */
    data class Stance(val kind: Kind, val direction: Double, val moves: Boolean) { enum class Kind { ATTACKING, BLOCKING } }
}

/** Owns the previous FX state and the effects currently playing (Swift `BoardFXDirector`). */
class BoardFXDirector {
    var previous: BoardFXState? = null; private set
    var active: List<ActiveBoardFX> = emptyList(); private set
    /** Card faces for flights, keyed by event subject; departed cards come from the previous snapshot. */
    var subjects: Map<String, ZoneCard> = emptyMap(); private set
    /** Every commander name seen in a command zone this game. */
    var commanderNames: Set<String> = emptySet(); private set
    var level = BoardFXLevel.FULL; private set
    private var previousBattlefield: Map<String, ZoneCard> = emptyMap()
    private var nextID = 0

    /** Returns only the newly scheduled effects, for haptics and sound. */
    fun ingest(snapshot: GameSnapshot, level: BoardFXLevel, now: Long): List<ScheduledBoardFX> {
        val state = BoardFXState.of(snapshot)
        val battlefield = LinkedHashMap<String, ZoneCard>()
        snapshot.players.flatMap { it.zones.battlefield }.forEach { battlefield.putIfAbsent(it.instanceId, it) }
        val departedFaces = previousBattlefield
        this.level = level
        try {
            // Lenient: only drop effects that are surely finished.
            prune(now - (renderGrace * 1000).toLong())
            val previous = previous
            if (previous == null || previous.gameID != state.gameID) {
                active = emptyList(); subjects = emptyMap(); commanderNames = state.commandNames
                return emptyList()
            }
            commanderNames = commanderNames + state.commandNames
            val events = BoardEventDiffer.events(previous, state, commanderNames)
            // Let a showcase or first-strike beat from an earlier snapshot finish before this batch plays.
            val showcaseEnd = active.mapNotNull { effect -> effect.scheduled.holdsLaterBatchesUntil?.let { effect.start + (it * 1000).toLong() } }.maxOrNull()
            val hold = showcaseEnd?.let { (it - now) / 1000.0 } ?: 0.0
            val scheduled = BoardFXScheduler.schedule(events, level, nextID, hold)
            nextID += scheduled.size
            active = active + scheduled.map { ActiveBoardFX(it, now) }
            val nextSubjects = subjects.toMutableMap()
            for (fx in scheduled) when (val event = fx.event) {
                is BoardFXEvent.EnteredBattlefield -> battlefield[event.cardID]?.let { nextSubjects[event.cardID] = it }
                is BoardFXEvent.LeftBattlefield -> departedFaces[event.cardID]?.let { nextSubjects[event.cardID] = it }
                is BoardFXEvent.CombatStrike -> (departedFaces[event.attackerID] ?: battlefield[event.attackerID])?.let { nextSubjects[event.attackerID] = it }
                is BoardFXEvent.SpellCast -> snapshot.stackTopFirst.firstOrNull { it.id == event.stackID }?.displaySourceCard?.let { nextSubjects[event.stackID] = it }
                else -> {}
            }
            subjects = nextSubjects
            return scheduled
        } finally {
            this.previous = state; previousBattlefield = battlefield
        }
    }

    fun prune(now: Long) {
        active = active.filter { it.endDate > now }
        val live = active.map { it.scheduled.event.subjectID }.toSet()
        subjects = subjects.filterKeys { live.contains(it) }
    }

    /** Per-card motion for the real board tiles: hide cards while a flight stands in, lunge attackers, hold stances. */
    fun cardMotion(viewerID: String): BoardFXCardMotion {
        if (level == BoardFXLevel.OFF) return BoardFXCardMotion()
        val hidden = HashMap<String, MutableList<BoardFXCardMotion.Hidden>>()
        val lunges = HashMap<String, BoardFXCardMotion.Lunge>()
        val stances = HashMap<String, BoardFXCardMotion.Stance>()
        for (effect in active) {
            if (!effect.scheduled.usesMotion) continue
            val fx = effect.scheduled
            when (val event = fx.event) {
                is BoardFXEvent.EnteredBattlefield -> if (subjects[event.cardID] != null)
                    hidden.getOrPut(event.cardID) { mutableListOf() } += BoardFXCardMotion.Hidden(effect.start, 0.0, fx.landing)
                // A double striker flies twice; each strike hides its tile only while it flies.
                is BoardFXEvent.CombatStrike -> if (subjects[event.attackerID] != null)
                    hidden.getOrPut(event.attackerID) { mutableListOf() } += BoardFXCardMotion.Hidden(effect.start, fx.delay, fx.end)
                is BoardFXEvent.AttackDeclared -> {
                    val owner = previous?.cards?.get(event.cardID)?.playerID
                    lunges[event.cardID] = BoardFXCardMotion.Lunge(effect.id, if (owner == viewerID) -1.0 else 1.0)
                }
                else -> {}
            }
        }
        for (card in previous?.cards?.values?.sortedBy { it.id } ?: emptyList()) {
            if (card.zone != BoardFXZone.BATTLEFIELD) continue
            val direction = if (card.playerID == viewerID) -1.0 else 1.0
            if (card.attacking) stances[card.id] = BoardFXCardMotion.Stance(BoardFXCardMotion.Stance.Kind.ATTACKING, direction, level == BoardFXLevel.FULL)
            else if (card.blocking.isNotEmpty()) stances[card.id] = BoardFXCardMotion.Stance(BoardFXCardMotion.Stance.Kind.BLOCKING, direction, level == BoardFXLevel.FULL)
        }
        return BoardFXCardMotion(hidden, lunges, stances)
    }

    val latestEnd: Long? get() = active.maxOfOrNull { it.endDate }

    companion object { const val renderGrace = 2.0 }
}
