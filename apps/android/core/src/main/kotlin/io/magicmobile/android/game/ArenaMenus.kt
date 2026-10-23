package io.magicmobile.android.game

/**
 * The rules behind the Arena menus (iOS Menus/ArenaMenuKit.swift, ArenaPlayPanel.swift, ArenaDeckBox.swift, ArenaHomeView.swift
 * and OnDeviceRootView.swift's Arena shell), kept here so the JVM tests cover them. The app's `menus/` files draw them.
 */

/** The tabs along the top of every menu page (ArenaMenuTab). `identifier` keeps the older menu's test tags. */
enum class ArenaMenuTab(val title: String, val symbol: String, val identifier: String) {
    HOME("Home", "house.fill", "menu.tab.home"),
    PROFILE("Profile", "person.fill", "menu.profile"),
    DECKS("Decks", "rectangle.stack.fill", "menu.decks"),
    RANKED("Ranked", "trophy.fill", "menu.tab.ranked"),
    LEARN("Learn", "book.fill", "menu.howToPlay");

    companion object {
        /**
         * The lit tab for what the menu shows (OnDeviceRootView.menuTab): a utility panel (Options, news, downloads, friends)
         * lights its own icon instead, Decks and How to Play their tabs, then the lobby page.
         */
        fun lit(utilityOpen: Boolean, decksOpen: Boolean, learnOpen: Boolean, lobby: String?): ArenaMenuTab? = when {
            utilityOpen -> null
            decksOpen -> DECKS
            learnOpen -> LEARN
            lobby == "profile" -> PROFILE
            lobby == "rankedHall" || lobby == "leaderboard" -> RANKED
            lobby == null -> HOME
            else -> null
        }
    }
}

/** The utility a panel is open for, by the top bar icon's identifier (ArenaTopBar `lit`). */
object ArenaTopBarLit {
    fun of(options: Boolean, updates: Boolean, downloads: Boolean, friends: Boolean): String? = when {
        options -> "menu.settings"
        updates -> "menu.updates"
        downloads -> "menu.downloads"
        friends -> "menu.friends"
        else -> null
    }
}

/** Arena's type (ArenaMenuStyle.font): from 17 pt up a size is a title in the serif; smaller sizes are the sans. */
object ArenaMenuType {
    const val TITLE_FROM = 17f
    fun isTitle(size: Float): Boolean = size >= TITLE_FROM
}

/** The Play panel's three ways to play from Find Match (ArenaPlayMode). */
enum class ArenaPlayMode(val raw: String, val title: String, val heading: String) {
    QUICK("quick", "Quick", "Quick Match"), RANKED("ranked", "Ranked", "Ranked"), CUSTOM("custom", "Custom", "Custom Table");

    companion object {
        const val STORAGE_KEY = "magicmobile.play.mode"
        fun of(raw: String): ArenaPlayMode = entries.firstOrNull { it.raw == raw } ?: QUICK
        /** The way to play a recorded game used. */
        fun of(mode: PlayMode): ArenaPlayMode = when (mode) { PlayMode.QUICK -> QUICK; PlayMode.RANKED -> RANKED; PlayMode.CASUAL -> CUSTOM }
    }
}

/** The tabs along the top of the Play panel (ArenaPlayTab). */
enum class ArenaPlayTab(val raw: String, val title: String, val symbol: String) {
    FIND("find", "Find Match", "shield.lefthalf.filled"),
    FRIENDS("friends", "Friends", "person.2.fill"),
    RECENT("recent", "Recently Played", "clock.arrow.circlepath");
}

/** The ways to play with friends in the Friends tab (ArenaFriendWay). Android has no Game Center: relay tables only. */
enum class ArenaFriendWay(val raw: String, val title: String) {
    CHALLENGE("challenge", "Challenge a friend"), HOST("host", "Host an online table"), JOIN("join", "Join with a code");
}

/** What the blade's plaque does. */
enum class ArenaPlayAction { CHALLENGE, HOST, JOIN, FIND_MATCH_TAB, START_QUICK, FIND_RANKED, OPEN_CUSTOM }

/** The blade's plaque: its word, test tag, whether it may be pressed, and what it does. */
data class ArenaPlayPrimary(val title: String, val identifier: String, val enabled: Boolean, val action: ArenaPlayAction)

/** A game from the profile's history, offered again from Recently Played (ArenaRecentGame). */
data class ArenaRecentGame(val id: String, val mode: PlayMode, val deckID: String, val deckName: String, val commander: String?,
                           val colors: List<String>, val detail: String, val won: Boolean?) {
    val modeTitle: String get() = when (mode) { PlayMode.QUICK -> "Quick Match"; PlayMode.RANKED -> "Ranked"; PlayMode.CASUAL -> "Custom Table" }
}

/** The Play panel's rules (ArenaPlayPanelModel and ArenaPlayBlade). */
object ArenaPlayRules {
    /** The opponents' bracket Quick Match resolves to (0 is "match my deck", at most Optimized). */
    fun quickResolvedBracket(quickBracket: Int, deckBracket: CommanderBracket?): Int =
        if (quickBracket == 0) minOf(4, deckBracket?.level ?: 2) else quickBracket

    /** Ranked allows the deck at this tier. */
    fun rankedEligible(deckBracket: CommanderBracket?, tier: RankTier): Boolean = (deckBracket?.level ?: 99) <= tier.maxDeckBracket

    /** The deck picker's heading. */
    fun heading(tab: ArenaPlayTab, mode: ArenaPlayMode): String = when (tab) {
        ArenaPlayTab.FRIENDS -> "Play with Friends"
        ArenaPlayTab.RECENT -> "Recently Played"
        ArenaPlayTab.FIND -> mode.heading
    }

    /** The table's size, shown on Find Match only (Quick and Ranked one opponent, Custom up to four). */
    fun rulesLine(mode: ArenaPlayMode): String = if (mode == ArenaPlayMode.CUSTOM) "100 cards · up to 4 players" else "100 cards · 1v1"

    /** Quick Match's bracket heading word for "match my deck". */
    fun matchedLabel(deckBracket: CommanderBracket?): String =
        deckBracket?.let { "Match my deck · B${minOf(4, it.level)}" } ?: "Match my deck"

    /** The plaque for the tab, way and mode (ArenaPlayBlade.primary). */
    fun primary(tab: ArenaPlayTab, friendWay: ArenaFriendWay, mode: ArenaPlayMode, recentEmpty: Boolean, mayStart: Boolean,
                rankedEligible: Boolean): ArenaPlayPrimary = when {
        tab == ArenaPlayTab.FRIENDS -> when (friendWay) {
            ArenaFriendWay.CHALLENGE -> ArenaPlayPrimary("Challenge", "play.friends", true, ArenaPlayAction.CHALLENGE)
            ArenaFriendWay.HOST -> ArenaPlayPrimary("Host Table", "play.friends", true, ArenaPlayAction.HOST)
            ArenaFriendWay.JOIN -> ArenaPlayPrimary("Join Table", "play.friends", true, ArenaPlayAction.JOIN)
        }
        tab == ArenaPlayTab.RECENT && recentEmpty -> ArenaPlayPrimary("Find Match", "play.recent", true, ArenaPlayAction.FIND_MATCH_TAB)
        else -> when (mode) {
            ArenaPlayMode.QUICK -> ArenaPlayPrimary("Play", "quick.start", mayStart, ArenaPlayAction.START_QUICK)
            ArenaPlayMode.RANKED -> ArenaPlayPrimary("Find Match", "ranked.find", mayStart && rankedEligible, ArenaPlayAction.FIND_RANKED)
            ArenaPlayMode.CUSTOM -> ArenaPlayPrimary("Set Up Table", "play.start", true, ArenaPlayAction.OPEN_CUSTOM)
        }
    }

    /** The last few tables to set up again: newest first, one per way and deck, only decks still on the phone. */
    fun recentGames(matches: List<MatchRecord>, deckIDs: Set<String>, limit: Int = 6): List<ArenaRecentGame> {
        val seen = HashSet<String>()
        return matches.sortedByDescending { it.date }.mapNotNull { match ->
            if (match.deckID !in deckIDs || !seen.add("${match.mode.raw}|${match.deckID}")) return@mapNotNull null
            val foe = match.opponents.firstOrNull()?.name ?: "the table"
            ArenaRecentGame(match.id, match.mode, match.deckID, match.deckName, match.commander, match.colors, "vs $foe",
                if (match.outcome == RankOutcome.DRAW) null else match.outcome == RankOutcome.WIN)
        }.take(limit)
    }

    /** A recent table is chosen when its deck and way are the panel's. */
    fun isChosen(game: ArenaRecentGame, selectedDeckID: String, mode: ArenaPlayMode): Boolean =
        game.deckID == selectedDeckID && ArenaPlayMode.of(game.mode) == mode

    /** The deck picker's grid: how many boxes fit across, and each box's width (ArenaDeckPicker.deckShelves). */
    fun deckGrid(width: Float, compact: Boolean): Pair<Int, Float> {
        val gap = if (compact) 10f else 12f
        val usable = width - if (compact) 32f else 48f
        val columns = maxOf(2, ((usable + gap) / ((if (compact) 118f else 112f) + gap)).toInt())
        val boxWidth = kotlin.math.floor((usable - gap * (columns - 1)) / columns)
        return columns to boxWidth
    }
}

/** The deck box's proportions from the reference (ArenaBoxGeometry): the front 1.34 times as wide as tall, a narrow side, a thin top. */
data class ArenaBoxGeometry(val width: Float) {
    val side: Float get() = width * 0.095f
    val top: Float get() = width * 0.035f
    val frontWidth: Float get() = width - side
    val frontHeight: Float get() = frontWidth / 1.34f
    val boxHeight: Float get() = top + frontHeight
    /** The lid's front edge across the top of the front. */
    val lidBand: Float get() = frontHeight * 0.1f
    /** How far the front folds down when the box opens. */
    val cut: Float get() = frontHeight * 0.48f
    /** How far the lid and the back rise when the box opens. */
    val rise: Float get() = frontHeight * 0.36f
    val plateHeight: Float get() = maxOf(24f, width * 0.17f)
    val plateOverlap: Float get() = width * 0.05f
    val pip: Float get() = maxOf(13f, width * 0.115f)
    /** Where the front's top edge stands for `openness` 0 (shut) to 1 (open). */
    fun frontTop(openness: Float): Float = top + lidBand + (cut - lidBand) * openness
}

/** A deck's colours in W U B R G order, from its commanders' colour identities; empty while any is unknown. */
object ArenaDeckColors {
    private val order = listOf("W", "U", "B", "R", "G")
    fun colors(commanders: List<String>, identity: (String) -> List<String>?): List<String> {
        if (commanders.isEmpty()) return emptyList()
        val union = HashSet<String>()
        for (name in commanders) union += identity(name) ?: return emptyList()
        return order.filter { it in union }
    }
}

/**
 * Shipped home art cropped around its focus point (ArenaFocusedArt): the picture scaled to cover the frame, moved so the
 * focus sits at the frame's centre, but never so far that the frame shows past the picture's edge.
 */
object ArenaHomeArtCrop {
    data class Placement(val width: Float, val height: Float, val x: Float, val y: Float)

    fun place(imageWidth: Float, imageHeight: Float, frameWidth: Float, frameHeight: Float, focusX: Float, focusY: Float): Placement {
        val scale = maxOf(frameWidth / imageWidth, frameHeight / imageHeight)
        val width = imageWidth * scale; val height = imageHeight * scale
        val x = minOf(0f, maxOf(frameWidth - width, frameWidth / 2 - width * focusX))
        val y = minOf(0f, maxOf(frameHeight - height, frameHeight / 2 - height * focusY))
        return Placement(width, height, x, y)
    }
}

/** The featured panel's turning (ArenaFeaturePanel): pages wrap, and a swipe past 60 pt turns one. */
object ArenaFeatureTurn {
    const val SWIPE = 60f
    const val AUTO_SECONDS = 8L
    fun step(index: Int, delta: Int, count: Int): Int = if (count <= 0) 0 else ((index + delta) % count + count) % count
    /** -1, 0 or 1 for a horizontal swipe's predicted travel. */
    fun swipe(travel: Float): Int = when { travel < -SWIPE -> 1; travel > SWIPE -> -1; else -> 0 }
}
