package io.magicmobile.android.game

/*
 * The inbox's messages (NativeUpdateNewsView.swift `UpdateNews`): one per release, newest first, each with a card's art,
 * its title, the day it came and what it brought. The words follow iOS; the sign-in line names Google, Android's provider.
 */

/** One release's message in the inbox. `day` is the day in October 2026 the release notes were written. */
data class UpdateNewsMessage(val id: String, val title: String, val day: Int, val art: String, val colors: List<String>,
                             val lede: String, val notes: List<String> = emptyList()) {
    /** The date as iOS's `.long` style writes it in English ("October 22, 2026"). */
    val date: String get() = "October $day, 2026"
}

object UpdateNews {
    /** The last row's id: the build, XMage news and the links. */
    const val ABOUT_ID = "about"

    /** Only the newest message is lit and tagged New. */
    fun isNew(index: Int): Boolean = index == 0

    val messages: List<UpdateNewsMessage> = listOf(
        UpdateNewsMessage("own-art", "Your own card art", 27, "Zur the Enchanter", listOf("W", "U", "B"),
            "Put your own picture on any card in Deck Studio. It becomes the whole card, follows you to every phone and browser you sign in on, and only you see it.",
            listOf("The art you chose shows from a game's first moment, without the default art swapping in.",
                "Smart Auto-Pass waits on your own trigger when you have an ability that can use it, like Gogo copying Zur's attack trigger.",
                "The starting roll says \"You roll\" when it's your turn to roll.")),
        UpdateNewsMessage("arena-menus", "The menus follow the Arena board", 22, "Rhystic Study", listOf("U"),
            "Every menu now matches the Arena board: Play opens a panel beside your deck boxes, and the boxes open when you choose one.",
            listOf(
                "Your decks stand in boxes with the commander on the front; the one you choose opens and its commander rises out.",
                "Play is a panel on the right with Find Match, Friends and Recently Played, and a search waits in it with a timer.",
                "Decks, Options, Updates, Downloads and How to Play open as panels over the room.",
                "Held sideways, the deck builder shows the cards to add beside your deck as a list.",
            )),
        UpdateNewsMessage("messages", "Messages and the Ranked Hall", 17, "Kynaios and Tiro of Meletis", listOf("W", "U", "R", "G"),
            "Message your friends from Friends, or from the game menu in the middle of a game. A banner shows a new message.",
            listOf(
                "Repeat a combo: do the same thing three times in a turn and the game offers to repeat it, as many times as you pick, until you can't, or until they lose. It waits for your triggers and keeps choosing the same kind of target.",
                "Ranked opens the Ranked Hall, with a live leaderboard of this season's players and who's online.",
                "Spread-out token piles stack back up with the Stack chip.",
            )),
        UpdateNewsMessage("sign-in", "Keep your profile", 8, "Atraxa, Praetors' Voice", listOf("W", "U", "B", "G"),
            "Sign in with Google on the Profile screen, and your name, friends and rank follow you to any phone."),
        UpdateNewsMessage("turns", "Smoother turns", 7, "Thousand-Year Storm", listOf("U", "R"),
            "Your spells resolve without an extra tap. Turn off Pass After Casting in Options to hold priority.",
            listOf(
                "Don't ask again: tick it on a card's \"you may\" question and the game answers it for you for the rest of the game. Change your mind in the game menu.",
                "Resolve all: one tap lets a pile of triggers on the stack resolve, and it stops if an opponent responds.",
                "Pick any number of cards at once with Select all, and remember which of your triggers goes first.",
                "The AI waits less while your triggers resolve, and XMage is updated with 78 new cards and many card fixes.",
            )),
        UpdateNewsMessage("table", "More on the table", 7, "Courser of Kruphix", listOf("G"),
            "When you can see the top of your library, it sits beside your portrait. Tap it to see it large and cast or play it.",
            listOf(
                "The stack shows what resolves next, whose it is, its targets, and Resolve all.",
                "Your portrait glows when you can cast from your graveyard, exile or the top of your library, not only your commander, and the zone menu says which.",
                "A small sun or moon shows when it's day or night, the storm count shows under the turn plate, and City's Blessing shows on your medallion.",
                "The starting roll has more table: the header sits at the top and the dice get the room below it.",
            )),
        UpdateNewsMessage("art", "Choose your card art", 7, "Krenko, Mob Boss", listOf("R"),
            "Choose the artwork for any card in Deck Studio. Your pick shows in games and offline, survives export and import, and online images match it.",
            listOf("The offline download now includes every token and emblem.")),
        UpdateNewsMessage("profile", "Your games at a glance", 6, "Edgar Markov", listOf("W", "B", "R"),
            "Your profile shows win rate, favourite commanders, colours and rank history. Your game history lives there now.",
            listOf(
                "Find friends as you type their name, and open any player's profile. Choose whether yours is public, friends only or private.",
                "The starting roll happens on the table: every player's d20 tumbles across it and lands.",
            )),
        UpdateNewsMessage("battery", "Easier on your battery", 5, "Lightning Greaves", emptyList(),
            "The game rests while it waits for you, and the app is a smaller download."),
        UpdateNewsMessage("ranked", "Ranked seasons", 4, "Elesh Norn, Grand Cenobite", listOf("W"),
            "Climb from Bronze to Mythic in monthly seasons, against players near your rank or an AI at your tier.",
            listOf(
                "Quick Match: one AI at your deck's bracket, or choose its bracket, deck and skill.",
                "Challenge a friend to a Quick Match, or to Ranked when you're in the same tier. Friend ranked games count.",
                "Every deck shows its Commander bracket, with the Game Changers and combos behind it.",
                "Your profile: rank, season history, stats, achievements, titles and match history. Your profile picture is your favorite commander's art.",
                "21 new included decks from Bracket 1 to 4, for you and for the AI.",
                "A real 3D tavern room behind the menu that shifts as you tilt your phone, with flickering candles.",
            )),
        UpdateNewsMessage("tavern", "A new table", 3, "Prossh, Skyraider of Kher", listOf("B", "R", "G"),
            "A new table with painted card frames, in portrait and landscape, and every spell cast with its own moment at the centre of it.",
            listOf(
                "Tap a player's medallion for their counters, poison and commander damage, and swap between opponents.",
                "Big boards run smoother: identical tokens stack once there are eight.",
                "A Back button while declaring attackers and blockers.",
                "Friends, table chat and invite links that open straight into your table.",
            )),
    )

    /** A tap on a row: opens it, or closes it when it is the open one (one message open at a time). */
    fun toggle(expanded: String?, id: String): String? = if (expanded == id) null else id
}
