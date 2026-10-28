package io.magicmobile.android.game

/**
 * The guided first game (Caleb, 2026-10-11): a real game against one easy AI, with a coach that
 * explains each moment the first time it comes up. iOS GuidedGame.swift holds the same rules and
 * words; both platforms' parity tests read them from parity/guided-game-cases.json.
 */
enum class GuidedGameTip(val id: String) {
    FIRST_PLAYER("firstPlayer"),
    MULLIGAN("mulligan"),
    ATTACK("attack"),
    BLOCK("block"),
    PAY("pay"),
    TARGET("target"),
    OPPONENT_SPELL("opponentSpell"),
    COMMANDER("commander"),
    LAND("land"),
    CAST("cast"),
    PASS("pass"),
    INSPECT("inspect"),
    BASICS("basics");

    /** Tips that ask for something on the table go away once it's done; the others wait for Got it. */
    val isActionable: Boolean get() = this != INSPECT && this != BASICS

    companion object {
        fun fromId(id: String): GuidedGameTip? = entries.firstOrNull { it.id == id }
    }
}

/** The match and its words: Android's copy of iOS GuidedGameText. */
object GuidedGameText {
    const val TITLE = "Guided first game"
    const val SUBTITLE = "A real game against an easy AI, with tips as each moment comes up."
    const val START = "Play a guided game"
    const val GOT_IT = "Got it"
    const val TURN_OFF = "Turn off tips"
    const val WELCOME_TITLE = "Welcome to the tavern"
    const val WELCOME_BODY = "New to Magic or to MagicMobile? Learn by playing, one short lesson at a time."
    const val READ_HOW_TO_PLAY = "Read How to Play"
    const val SKIP = "I know Magic"

    fun title(tip: GuidedGameTip): String = when (tip) {
        GuidedGameTip.FIRST_PLAYER -> "Who goes first"
        GuidedGameTip.MULLIGAN -> "Your opening hand"
        GuidedGameTip.ATTACK -> "Attack"
        GuidedGameTip.BLOCK -> "Block"
        GuidedGameTip.PAY -> "Pay the cost"
        GuidedGameTip.TARGET -> "Choose a target"
        GuidedGameTip.OPPONENT_SPELL -> "A spell on the stack"
        GuidedGameTip.COMMANDER -> "Cast your commander"
        GuidedGameTip.LAND -> "Play a land"
        GuidedGameTip.CAST -> "Cast a spell"
        GuidedGameTip.PASS -> "Pass with the hourglass"
        GuidedGameTip.INSPECT -> "Read a card"
        GuidedGameTip.BASICS -> "You know the basics"
    }

    fun body(tip: GuidedGameTip): String = when (tip) {
        GuidedGameTip.FIRST_PLAYER ->
            "Welcome to your guided game. I'll explain each moment the first time it comes up. Choose yourself to take the first turn."
        GuidedGameTip.MULLIGAN ->
            "These are your first seven cards. A good hand has two to five lands. Tap Keep, or Mulligan for a fresh seven."
        GuidedGameTip.ATTACK ->
            "Tap each creature you want to send into combat, then Done Attacking. Creatures that arrived this turn can't attack yet."
        GuidedGameTip.BLOCK ->
            "You're being attacked. Tap your creature, then the attacker it should block, and tap Done Blocking. Unblocked attackers hit you."
        GuidedGameTip.PAY ->
            "Tap your lands to pay for the spell. The tray shows how much mana is still owed."
        GuidedGameTip.TARGET ->
            "This needs a target. Anything glowing red can be chosen: tap it."
        GuidedGameTip.OPPONENT_SPELL ->
            "Your opponent's spell waits on the stack until everyone passes. You could answer with an instant; for now, tap the hourglass to let it resolve."
        GuidedGameTip.COMMANDER ->
            "Your commander is ready in the command zone, and its medallion glows. Tap the medallion to cast it."
        GuidedGameTip.LAND ->
            "Lands make the mana you cast spells with. Drag a land from your hand up onto the mat. You can play one each turn."
        GuidedGameTip.CAST ->
            "A green glow means a card can be played now. Drag it from your hand onto the mat to cast it."
        GuidedGameTip.PASS ->
            "Nothing left to play? Tap the hourglass to move on. Skip jumps to your next turn and still stops when you're needed."
        GuidedGameTip.INSPECT ->
            "Press and hold any card, yours or your opponent's, to read its full rules text."
        GuidedGameTip.BASICS ->
            "That's everything you need. Bring your opponent from 40 life to 0 to win, or leave from the game menu any time."
    }
}

/** The guided game's decks and settings (iOS GuidedGameSetup). */
object GuidedGameSetup {
    /** Token Triumph: green-white creatures, the simplest precon to attack with. */
    const val PLAYER_DECK_ID = "precon:token-triumph"
    const val PLAYER_PRECON_ID = "token-triumph"
    /** Grave Danger: a zombie deck that plays fair at skill 1. */
    const val OPPONENT_DECK_ID = "grave-danger"
    const val AI_SKILL = 1
    /** The player picks who starts, so the first note can tell them to pick themselves. */
    const val STARTING_PLAYER_MODE = "choose"
}

/** What the coach shows: a pure function of the snapshot, the note on screen and the notes already shown. */
object GuidedGameCoach {
    /** The notes every guided game should reach before BASICS; the others only come up if the game does. */
    val core: List<GuidedGameTip> = listOf(GuidedGameTip.MULLIGAN, GuidedGameTip.LAND, GuidedGameTip.CAST, GuidedGameTip.PASS,
        GuidedGameTip.ATTACK, GuidedGameTip.INSPECT)

    /** [current]: the note to show now; [newlyShown]: the note shown for the first time, to remember. */
    data class Step(val current: GuidedGameTip?, val newlyShown: GuidedGameTip?)

    private val order = listOf(GuidedGameTip.FIRST_PLAYER, GuidedGameTip.MULLIGAN, GuidedGameTip.ATTACK, GuidedGameTip.BLOCK,
        GuidedGameTip.PAY, GuidedGameTip.TARGET, GuidedGameTip.OPPONENT_SPELL, GuidedGameTip.COMMANDER, GuidedGameTip.LAND,
        GuidedGameTip.CAST, GuidedGameTip.PASS, GuidedGameTip.INSPECT)

    /**
     * The next note: the one on screen stays while it still applies (or, for a note that asks for
     * nothing, until a note that does arrives); a finished game shows none.
     */
    fun advance(current: GuidedGameTip?, snapshot: GameSnapshot, shown: Set<GuidedGameTip>): Step {
        if (snapshot.isCompleted) return Step(null, null)
        val next = nextTip(snapshot, shown)
        if (current != null) {
            val keeps = if (current.isActionable) applies(current, snapshot) else next?.let { !it.isActionable } ?: true
            if (keeps) return Step(current, null)
        }
        return Step(next, next)
    }

    /** The first note not shown yet whose moment this is, most urgent first. */
    fun nextTip(snapshot: GameSnapshot, shown: Set<GuidedGameTip>): GuidedGameTip? {
        if (snapshot.isCompleted) return null
        order.firstOrNull { it !in shown && applies(it, snapshot) }?.let { return it }
        if (GuidedGameTip.BASICS !in shown && shown.containsAll(core) && applies(GuidedGameTip.BASICS, snapshot)) return GuidedGameTip.BASICS
        return null
    }

    fun applies(tip: GuidedGameTip, snapshot: GameSnapshot): Boolean {
        val viewer = snapshot.viewerID
        val prompt = snapshot.promptEnvelopeV2?.takeIf { it.playerId == viewer }
        val actions = snapshot.legalActions ?: emptyList()
        val types = actions.map { it.type }.toSet()
        val myTurn = snapshot.activePlayerId == viewer
        val myPriority = snapshot.priorityPlayerId == viewer
        val opponentStack = snapshot.players.any { it.playerId != viewer && it.zones.stack.isNotEmpty() }
        val anyStack = snapshot.players.any { it.zones.stack.isNotEmpty() }
        val main = "${snapshot.phase} ${snapshot.step ?: ""}".lowercase().contains("main")
        // Free to act: holding priority with no question beyond "what next?".
        val free = myPriority && !isMana(prompt) && !isTarget(prompt) && "declare_attackers" !in types && "declare_blockers" !in types
        return when (tip) {
            GuidedGameTip.FIRST_PLAYER -> prompt?.message?.lowercase()?.contains("starting player") == true
            GuidedGameTip.MULLIGAN -> prompt != null && prompt.confirmation != null && prompt.message.lowercase().contains("mulligan")
            GuidedGameTip.ATTACK -> "declare_attackers" in types
            GuidedGameTip.BLOCK -> "declare_blockers" in types
            GuidedGameTip.PAY -> isMana(prompt) || snapshot.manaPayment?.active == true
            GuidedGameTip.TARGET -> isTarget(prompt) && !isMana(prompt)
            GuidedGameTip.OPPONENT_SPELL -> free && opponentStack
            GuidedGameTip.COMMANDER -> free && actions.any { it.type == "cast_spell" && it.sourceZone == "command" }
            GuidedGameTip.LAND -> free && myTurn && "play_land" in types
            GuidedGameTip.CAST -> free && myTurn && actions.any { it.type == "cast_spell" && it.sourceZone != "command" }
            GuidedGameTip.PASS -> free && myTurn && main && !anyStack && "play_land" !in types && "cast_spell" !in types &&
                "pass_priority" in types
            GuidedGameTip.INSPECT, GuidedGameTip.BASICS -> free && myTurn && snapshot.turn >= 3
        }
    }

    private fun isMana(prompt: PromptEnvelopeV2?): Boolean {
        if (prompt == null) return false
        val type = prompt.responseCommand?.type?.lowercase() ?: ""
        val kind = prompt.responseKind.lowercase()
        return type in setOf("play_mana", "choose_mana", "pay_cost", "play_x_mana") ||
            kind in setOf("mana", "pay_cost", "cost", "x_mana") || prompt.method in setOf("GAME_PLAY_MANA", "GAME_PLAY_XMANA")
    }

    private fun isTarget(prompt: PromptEnvelopeV2?): Boolean {
        if (prompt == null || prompt.message.lowercase().contains("starting player")) return false
        val type = prompt.responseCommand?.type?.lowercase() ?: prompt.responseKind.lowercase()
        return type == "choose_target" || prompt.responseKind.lowercase() == "target" || prompt.method.uppercase().contains("TARGET")
    }
}

/**
 * What the guided game remembers on this phone (iOS GuidedGameLaunch, same keys): the notes already
 * shown (a comma-separated list here), whether a guided game is under way, and whether the welcome
 * was answered.
 */
object GuidedGameLaunch {
    const val SHOWN_TIPS_KEY = "magicmobile.guidedGame.shownTips"
    const val ACTIVE_KEY = "magicmobile.guidedGame.active"
    const val WELCOME_SEEN_KEY = "magicmobile.guidedGame.welcomeSeen"

    fun shownTips(stored: String): Set<GuidedGameTip> =
        stored.split(',').mapNotNull { GuidedGameTip.fromId(it.trim()) }.toSet()

    fun remember(tip: GuidedGameTip, stored: String): String {
        val ids = stored.split(',').map { it.trim() }.filter { it.isNotEmpty() }
        return if (tip.id in ids) stored else (ids + tip.id).joinToString(",")
    }

    /** The welcome replaces the walkthrough's automatic first opening, and never shows again once answered. */
    fun shouldShowWelcome(welcomeSeen: Boolean, howToPlaySeenVersion: Int, launch: Map<String, String>): Boolean =
        !welcomeSeen && HowToPlayLaunch.shouldShowAutomatically(howToPlaySeenVersion, launch)
}
