package io.magicmobile.android.studio

import kotlin.math.floor

/**
 * The rules of Deck Studio's Decks page in the Arena menus (DeckStudioRootView.swift, Arena's decks-1): every deck as a deck
 * box across the page, the "+" tile in the first cell, the chosen box standing open, and the chosen deck on a strip along the
 * foot. Sizes are in points (dp).
 */
object ArenaDecksPage {
    /** The gap between boxes, across and down. */
    const val GAP = 12f
    /** The narrowest a box may be; the columns follow from it. */
    const val MIN_BOX = 112f

    data class Grid(val columns: Int, val boxWidth: Float)

    /** At least two columns of boxes at least [MIN_BOX] wide, filling [usableWidth] with [GAP] between them. */
    fun grid(usableWidth: Float): Grid {
        val columns = maxOf(2, ((usableWidth + GAP) / (MIN_BOX + GAP)).toInt())
        return Grid(columns, maxOf(0f, floor((usableWidth - GAP * (columns - 1)) / columns)))
    }

    /** The cell a deck takes: the "+" tile is the first. */
    fun cell(deckIndex: Int): Int = deckIndex + 1

    /** The row a cell sits in. */
    fun row(cell: Int, columns: Int): Int = cell / maxOf(1, columns)

    /** The rows the page holds for this many decks (with the "+" tile). */
    fun rows(decks: Int, columns: Int): Int = (decks + 1 + maxOf(1, columns) - 1) / maxOf(1, columns)

    /** Only a box open in the first row needs room above it (the "+" tile takes the row's first place). */
    fun firstRowOpen(deckIndex: Int?, columns: Int): Boolean = deckIndex != null && deckIndex >= 0 && deckIndex < columns - 1

    /**
     * Whether the page scrolls on arrival so the playing deck's open box rests above the strip: only past the first row. A
     * deck that is not shown counts as the first.
     */
    fun scrollsOnArrival(deckIndex: Int?, columns: Int): Boolean = (deckIndex ?: 0) + 1 >= columns

    /** What a tap on a box does, Arena's way: the first opens the box and shows the deck, a second opens it for editing. */
    enum class Tap { OPEN_BOX, EDIT }

    fun tap(chosen: Boolean): Tap = if (chosen) Tap.EDIT else Tap.OPEN_BOX

    /** The word on a shut box's corner: a deck that needs fixes says so, else the playing deck. */
    fun tag(needsFixes: Boolean, playing: Boolean): String? = when {
        needsFixes -> "FIX"
        playing -> "PLAYING"
        else -> null
    }

    /** The deck whose details show on the strip: the one the player chose here, else the playing deck, else the first shown. */
    fun focusedID(focused: String?, selected: String, ids: Collection<String>, visible: List<String>): String? =
        (focused ?: selected).takeIf { it in ids } ?: visible.firstOrNull()
}

/**
 * The small mana curve that closes the deck list in Arena's builder (DeckStudioWorkspaceScreen.swift `deckCurve`): the main
 * deck's nonland cards by mana value, 0 to 7+.
 */
object ArenaDeckCurve {
    /** One line of the main deck: how many, its mana value (null when unknown) and whether it is a land. */
    data class Line(val quantity: Int, val manaValue: Double?, val land: Boolean)

    /** Copies per mana value 0…7, the last holding 7 and more. Lands and cards of unknown value are left out. */
    fun bins(lines: List<Line>): List<Int> {
        val bins = IntArray(8)
        for (line in lines) {
            val value = line.manaValue ?: continue
            if (line.land || !value.isFinite()) continue
            bins[value.toInt().coerceIn(0, 7)] += line.quantity
        }
        return bins.toList()
    }

    /** A bar's height out of [full]: at least 2 so an empty value still shows its place. */
    fun height(count: Int, bins: List<Int>, full: Float = 30f): Float = maxOf(2f, full * count / maxOf(1, bins.maxOrNull() ?: 1))
}
