package io.magicmobile.android.game

/** One page of a "How to play" tutorial: a title, one to three short sentences and an animated tavern scene chosen by [id]. */
data class HowToPlayPage(val id: String, val title: String, val body: String)

/**
 * One tutorial: a short one on how MagicMobile's table works, and a longer one on the rules of Commander
 * (Caleb, 2026-10-03). Both use the tavern's own pieces for their scenes.
 */
data class HowToPlayTutorial(val id: String, val title: String, val subtitle: String, val pages: List<HowToPlayPage>)

/**
 * The tutorials' words, the same as iOS HowToPlayText (HowToPlay.swift). Both platforms' parity
 * tests read them from apps/android/core/src/test/resources/parity/tutorial-cases.json.
 */
object HowToPlayText {
    const val TITLE = "How to play"
    const val BACK = "Back"
    const val NEXT = "Next"
    const val SKIP = "Skip"
    const val DONE = "Done"
    /** The chooser's button on each tutorial. */
    const val BEGIN = "Begin"

    /** The progress indicator's spoken value, e.g. "Page 3 of 12". */
    fun progress(page: Int, count: Int): String = "Page $page of $count"

    val tutorials = listOf(
        HowToPlayTutorial("table", "How MagicMobile works", "Twelve short pages on the table and its controls.", listOf(
            HowToPlayPage("welcome", "Welcome to the tavern",
                "Play Commander against AI opponents or your friends, right on your phone. The XMage rules engine runs on this device and handles every rule for you."),
            HowToPlayPage("decks", "Choose your deck",
                "Tap Decks to open Deck Studio. Paste, link or scan a deck list, or tap Create deck to build your own. Tap Play this deck to check it against the Commander rules; your pick then shows the Playing badge."),
            HowToPlayPage("start", "Start a game",
                "Tap Play Commander, then pick your deck, one to three AI opponents and their skill. Under Who goes first?, choose the starting player or roll a D20: the highest roll starts. Then keep your opening hand or take a mulligan."),
            HowToPlayPage("board", "Know the table",
                "Your hand rests along the bottom, with your battlefield on the mat above it. Opponents sit across the table: tap a medallion for that player's zones, counters, poison and commander damage, and swap between opponents. The plate at the top right shows the turn and the current step."),
            HowToPlayPage("casting", "Cast a spell",
                "Drag a card from your hand up onto the mat to play it. When a spell needs mana, the Pay cost tray shows what's left, so tap your lands to pay. The spell rises to the centre of the table while it waits on the stack."),
            HowToPlayPage("glow", "Follow the glow",
                "A green glow means a card can be played or chosen; a red glow marks something you can target, even when it's tapped. Tapped permanents turn grey until they untap. Your commander's medallion glows whenever you can cast it."),
            HowToPlayPage("priority", "Pass with the hourglass",
                "When you're done, tap the hourglass to pass priority and let this step continue. With a spell on the stack, respond with an instant or ability, or pass to let it resolve. Skip ends your turn or jumps to your next one, and still stops when a choice needs you."),
            HowToPlayPage("combat", "Attack and block",
                "To attack, tap each creature you want to send, then the player to attack if there's a choice, and tap Done Attacking. To block, tap your creature, then the attacker it blocks, and tap Done Blocking. Back lets you change your mind before you confirm."),
            HowToPlayPage("piles", "Big boards",
                "Once you have eight or more identical tokens, they stack into one pile with a count. Tap the pile to pick the next token, or hold it to spread them out."),
            HowToPlayPage("reading", "Read a card",
                "Press and hold any card to see it up close with its full rules text. Open the game log to look back at every play."),
            HowToPlayPage("resume", "Leave and come back",
                "Games against the AI are saved when you leave the app. Come back within 10 minutes and tap Resume to pick up at your last decision. Quitting from the game menu ends the game for good."),
            HowToPlayPage("friends", "Play with friends",
                "In game setup, choose Online to host a table and share its code, or join a friend's table with their code. Online works between iPhone and Android. On iPhone, Game Center can find players too."),
        )),
        HowToPlayTutorial("commander", "Commander basics", "Nine pages on the rules of the format.", listOf(
            HowToPlayPage("format", "The format",
                "Commander is Magic for a table of friends: usually three or four players, each with a 100-card deck led by a legendary creature. Every card but basic lands is a single copy, and everyone starts at 40 life."),
            HowToPlayPage("commander", "Your commander",
                "Your commander starts in the command zone, and you can cast it from there whenever you could cast a creature. If it would leave the battlefield, you may send it back to the command zone instead. Each time you cast it again, it costs two more mana: the commander tax."),
            HowToPlayPage("colors", "Colour identity",
                "Your commander's colours decide your deck. Every card may only use mana symbols that appear on your commander, in its cost or its rules text. A colourless commander means a deck of colourless cards."),
            HowToPlayPage("turn", "A turn",
                "Each turn untaps your permanents, then you draw a card. In your main phases you may play one land and cast your spells, and combat comes between them. Then the turn passes to the player on your left."),
            HowToPlayPage("mana", "Mana and costs",
                "Lands tap for mana, shown as gems on the rail, and a card's cost sits in its corner. Creatures, sorceries and other permanents are cast in your main phase with nothing on the stack. Instants and abilities can be used whenever you have priority, even on another player's turn."),
            HowToPlayPage("stack", "The stack",
                "Spells and abilities don't happen at once: they wait on the stack, and everyone may respond. The last thing added resolves first. When every player passes in a row, the top of the stack resolves."),
            HowToPlayPage("combat", "Combat",
                "Attacking creatures tap, and each one attacks a player or a planeswalker. The defender chooses blockers, and an unblocked creature deals its damage to the player. Flying creatures can only be blocked by flying or reach, and trample pushes extra damage through a blocker."),
            HowToPlayPage("permanents", "Permanents",
                "Creatures, artifacts, enchantments, planeswalkers and lands stay on the battlefield. A creature can't attack or tap for an ability on the turn it arrives unless it has haste. Hold any card to read its keywords and rules in full."),
            HowToPlayPage("winning", "Winning",
                "A player loses at 0 life, with 10 poison counters, or when they must draw from an empty library. Taking 21 combat damage from one commander over the game loses too. The last player at the table wins."),
        )),
    )

    /** The walkthrough that opens by itself on the first visit: how the table works. */
    val pages: List<HowToPlayPage> get() = tutorials[0].pages
}

/**
 * When the walkthrough opens by itself: once, on the first visit to the main menu after the update
 * that added it (or a later content version). UI tests and design previews never see it unless a run
 * asks with [FIRST_LAUNCH_EXTRA]. iOS HowToPlayLaunch applies the same rule to the same stored key.
 */
object HowToPlayLaunch {
    /** The walkthrough version the player has closed; 0 before the first time. */
    const val SEEN_VERSION_KEY = "magicmobile.howToPlay.seenVersion"
    /** Raise to show a substantially rewritten walkthrough once more. */
    const val CONTENT_VERSION = 2
    /** Debug launch extra ("1") that lets an automated run see the first-launch walkthrough. */
    const val FIRST_LAUNCH_EXTRA = "MAGICMOBILE_HOW_TO_PLAY_FIRST_LAUNCH"

    fun shouldShowAutomatically(seenVersion: Int, automated: Boolean, forced: Boolean): Boolean =
        (!automated || forced) && seenVersion < CONTENT_VERSION

    /** Launch extras from UI tests (their own preference store) and design previews. */
    fun isAutomated(launch: Map<String, String>): Boolean =
        "MAGICMOBILE_UI_TEST_PREFERENCES" in launch || "MAGICMOBILE_DESIGN_PREVIEW" in launch

    fun isForced(launch: Map<String, String>): Boolean = launch[FIRST_LAUNCH_EXTRA] == "1"

    /** The whole decision for a stored version and this launch's extras. */
    fun shouldShowAutomatically(seenVersion: Int, launch: Map<String, String>): Boolean =
        shouldShowAutomatically(seenVersion, isAutomated(launch), isForced(launch))

    /** Closing the walkthrough (Done, Skip or dismissing the sheet) stores this; a newer stored version is kept. */
    fun seenVersionAfterClosing(seenVersion: Int): Int = maxOf(seenVersion, CONTENT_VERSION)
}

/** The one-time offer, after the walkthrough, to save card art for offline play (iOS OfflineArtLaunch). */
object OfflineArtLaunch {
    const val SEEN_KEY = "magicmobile.offlineArtPrompt.seen"

    fun shouldShowAutomatically(howToPlaySeenVersion: Int, seen: Boolean, launch: Map<String, String>): Boolean =
        !HowToPlayLaunch.isAutomated(launch) && howToPlaySeenVersion >= HowToPlayLaunch.CONTENT_VERSION && !seen
}
