package io.magicmobile.android.game

/** One page of the "How to play" walkthrough: a title, one to three short sentences and a drawn illustration chosen by [id]. */
data class HowToPlayPage(val id: String, val title: String, val body: String)

/**
 * The walkthrough's words, the same as iOS HowToPlayText (HowToPlay.swift). Both platforms' parity
 * tests read them from apps/android/core/src/test/resources/parity/tutorial-cases.json.
 */
object HowToPlayText {
    const val TITLE = "How to play"
    const val BACK = "Back"
    const val NEXT = "Next"
    const val SKIP = "Skip"
    const val DONE = "Done"

    /** The progress indicator's spoken value, e.g. "Page 3 of 10". */
    fun progress(page: Int, count: Int): String = "Page $page of $count"

    val pages = listOf(
        HowToPlayPage("welcome", "Welcome to MagicMobile",
            "Play Commander against AI opponents right on your phone. The XMage rules engine runs on this device and handles the rules for you."),
        HowToPlayPage("decks", "Choose your deck",
            "Tap Decks to open Deck Studio. Paste, link or scan a deck list, or tap Create deck to build your own. Tap Play this deck to check it against the Commander rules; your pick then shows the Playing badge."),
        HowToPlayPage("start", "Start a game",
            "Tap Play Commander, then pick your deck, one to three AI opponents and their skill. Under Who goes first?, choose the starting player or roll a D20: the highest roll starts. Then keep your opening hand or take a mulligan."),
        HowToPlayPage("board", "Know the board",
            "Your hand runs along the bottom, with your battlefield above it. Opponents and their life totals sit at the top; with more than one, tap the people button to watch another. The turn bar shows whose turn it is and the current step."),
        HowToPlayPage("casting", "Play your cards",
            "Drag a card from your hand up onto the battlefield to play it. When a spell needs mana, the Pay cost tray shows what's left, so tap your lands to pay. If it needs a target, tap a highlighted card or player."),
        HowToPlayPage("priority", "Pass priority",
            "When you're done, tap Pass Priority to let this step continue. With a spell on the stack, respond with an instant or ability, or pass to let it resolve. Skip ends your turn or jumps to your next one, and still stops when a choice needs you."),
        HowToPlayPage("combat", "Attack and block",
            "To attack, tap each creature you want to send, then the player to attack if there's a choice. Tap Done Attacking when you're ready. To block, tap your creature, then the attacker it blocks, and tap Done Blocking."),
        HowToPlayPage("reading", "Read the cards",
            "Press and hold any card to see it up close with its full rules text. Open the game log to look back at every play."),
        HowToPlayPage("resume", "Leave and come back",
            "Games against the AI are saved when you leave the app. Come back within 10 minutes and tap Resume to pick up at your last decision. Quitting from the game menu ends the game for good."),
        HowToPlayPage("friends", "Play with friends",
            "In game setup, choose Online to host a table and share its code, or join a friend's table with their code. Online works between iPhone and Android. On iPhone, Game Center can find players too."),
    )
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
    const val CONTENT_VERSION = 1
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
