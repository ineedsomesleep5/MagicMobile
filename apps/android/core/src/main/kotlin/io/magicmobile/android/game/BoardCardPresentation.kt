package io.magicmobile.android.game

/**
 * Port of BoardCardPresentation.swift: pure presentation rules for board cards, namely the
 * token copy frame, the held-card inspector's fit and the showcase banner. Views live in
 * app board/CardViews.kt, board/InspectorViews.kt and board/BoardFXOverlay.kt.
 */

/**
 * A token that copies a visible card. It is drawn as its own card frame (name, type line and
 * live power/toughness) around the source card's illustration, never as the printed source
 * card, whose name or stats can differ from the token's.
 */
object TokenCopyPresentation {
    /** Below this width the tag cannot name the source legibly. */
    const val NAMED_TAG_MINIMUM_WIDTH = 120f

    /** The copied card's name, only for a face-up token the engine explicitly marked as a copy. */
    fun sourceName(isToken: Boolean?, copySourceArtworkName: String?): String? {
        if (isToken != true) return null
        return copySourceArtworkName?.trim()?.takeIf { it.isNotEmpty() }
    }

    fun tag(source: String, cardWidth: Float): String =
        if (cardWidth >= NAMED_TAG_MINIMUM_WIDTH) "Token copy · $source" else "Token copy"
}

/** Non-null when this card renders as a token copy frame. */
val ZoneCard.tokenCopySourceName: String?
    get() = TokenCopyPresentation.sourceName(card.isToken, card.copySourceArtworkName)

/**
 * Regions of the token copy frame, in the card's own coordinates. Proportions follow a printed
 * card, so the compact battlefield face (which crops the tile to its art) still shows the art.
 */
data class TokenCopyFrameLayout(
    val size: BoardSize,
    /** Room the tag leaves free at the frame's trailing edge, for badges drawn over it. */
    val tagTrailingReserve: Float = 0f,
) {
    val border: Float get() = maxOf(size.width * 0.045f, 2f)
    private val gap: Float get() = maxOf(size.height * 0.012f, 1f)

    val nameBar: BoardRect get() = BoardRect(border, border, size.width - border * 2, maxOf(size.height * 0.085f, 8f))

    val art: BoardRect get() {
        val top = nameBar.maxY + gap
        return BoardRect(border, top, size.width - border * 2, maxOf(size.height * 0.555f - top, 1f))
    }

    val typeBar: BoardRect get() = BoardRect(border, art.maxY + gap, size.width - border * 2, maxOf(size.height * 0.07f, 7f))

    val textBox: BoardRect get() {
        val top = typeBar.maxY + gap
        return BoardRect(border, top, size.width - border * 2, maxOf(size.height - border - top, 1f))
    }

    /** Bottom-right, over the text box's corner like a printed P/T box. */
    val powerToughnessBox: BoardRect get() {
        val width = maxOf(size.width * 0.27f, 16f)
        val height = maxOf(size.height * 0.075f, 8f)
        return BoardRect(size.width - border - width, size.height - border - height, width, height)
    }

    /** Rules text area: the text box above the P/T box. */
    fun rulesArea(showsPowerToughness: Boolean): BoardRect {
        val dx = maxOf(size.width * 0.03f, 1.5f)
        val dy = maxOf(size.height * 0.01f, 1f)
        val box = textBox
        val height = if (showsPowerToughness) maxOf(powerToughnessBox.minY - (box.minY + dy) - gap, 1f) else box.height - dy * 2
        return BoardRect(box.minX + dx, box.minY + dy, box.width - dx * 2, height)
    }

    /**
     * Where the token copy tag sits: the art's top-leading corner, which the compact battlefield face
     * (ArenaBattlefieldCard) keeps in view just under its name header. The art's bottom edge falls behind
     * that face's P/T footer. The tag ends before [tagTrailingReserve]; its text shrinks, then truncates, to fit.
     */
    val tagSlot: BoardRect get() {
        val height = maxOf(size.height * 0.06f, 9f)
        val inset = maxOf(size.width * 0.04f, 2f)
        val minX = art.minX + inset
        val width = minOf(art.width - inset * 2, size.width - maxOf(tagTrailingReserve, 0f) - minX)
        return BoardRect(minX, art.minY + inset * 0.6f, maxOf(width, 1f), height)
    }

    val nameFontSize: Float get() = maxOf(size.width * 0.085f, 6f)
    val typeFontSize: Float get() = maxOf(size.width * 0.062f, 5f)
    val rulesFontSize: Float get() = maxOf(size.width * 0.052f, 4f)
    val powerToughnessFontSize: Float get() = maxOf(size.width * 0.085f, 6f)
    val tagFontSize: Float get() = maxOf(tagSlot.height * 0.52f, 4.5f)
    /** Rules are drawn only where they could be read. */
    val showsRules: Boolean get() = size.width >= 60f

    /** Whole rules lines that fit the text box; the rest is truncated. The inspector shows the full text beside the card. */
    fun rulesLineLimit(showsPowerToughness: Boolean): Int =
        maxOf(1, (rulesArea(showsPowerToughness).height / (rulesFontSize * 1.25f)).toInt())
}

/**
 * The compact battlefield face (ArenaBattlefieldCard): a name header over a CardTile cropped to its art, with
 * counter badges in a trailing column just under the header. A token copy's tag sits in that same band, so while
 * counters show, the tag ends before their column.
 */
object BattlefieldCardFaceLayout {
    const val HEADER_HEIGHT = 15f
    /** Top of the counter badge column, just under the header. */
    const val COUNTER_TOP = 16f
    /** Clear space between the tag's end and the counter column. */
    const val COUNTER_GAP = 2f

    /** The CardTile the face shows, in the face's coordinates: 8% wider and centered, lifted so its art starts under the header. */
    fun tileFrame(cardWidth: Float): BoardRect =
        BoardRect(-cardWidth * 0.04f, HEADER_HEIGHT - cardWidth * 0.19f, cardWidth * 1.08f, cardWidth * 1.51f)

    /** The counter badges are capped to this width at the face's trailing edge. */
    fun counterColumnWidth(cardWidth: Float): Float = maxOf(28f, cardWidth * 0.36f)

    /** What the tile's token copy tag leaves free at its trailing edge (tile coordinates). */
    fun tagTrailingReserve(cardWidth: Float, showsCounters: Boolean): Float {
        if (!showsCounters) return 0f
        val columnStart = cardWidth - counterColumnWidth(cardWidth) - COUNTER_GAP
        return maxOf(0f, tileFrame(cardWidth).maxX - columnStart)
    }

    /** The token copy tag's slot in the face's coordinates. */
    fun tokenCopyTagSlot(cardWidth: Float, showsCounters: Boolean): BoardRect {
        val tile = tileFrame(cardWidth)
        val slot = TokenCopyFrameLayout(BoardSize(tile.width, tile.height), tagTrailingReserve(cardWidth, showsCounters)).tagSlot
        return BoardRect(slot.x + tile.x, slot.y + tile.y, slot.width, slot.height)
    }
}

/**
 * Held-card inspection cannot scroll (the finger is down), so the rules text gets the room it
 * needs first and the card image shrinks instead, down to a floor. Text shrinks only when even
 * the smallest card leaves too little room.
 */
data class CardInspectorFit(
    val cardSize: BoardSize,
    /** Zero when there is nothing to show beside the card. */
    val footerSize: BoardSize,
    val horizontal: Boolean,
    /** The footer's natural height fits its room at full text size. */
    val footerFits: Boolean,
) {
    companion object {
        const val SPACING = 8f
        const val COLUMN_SPACING = 16f
        /** Portrait: the card keeps at least this share of the height. */
        const val MINIMUM_CARD_FRACTION = 0.34f
        /** Landscape: the card column is at most this share of the width. */
        const val LANDSCAPE_CARD_FRACTION = 0.55f
        /** Landscape: card sizes to try (shares of the largest card), largest first. */
        val landscapeCardScales = listOf(1f, 0.86f, 0.74f, 0.64f)
        /** Text sizes to try when the footer still does not fit, largest first. */
        val textScales = listOf(1f, 0.9f, 0.8f, 0.7f, 0.6f)

        /** [footerHeight] is the footer's natural height at full text size for a width. */
        fun plan(available: BoardSize, cardAspect: Float = BattlefieldLayoutMetrics.magicCardHeightToWidth, hasFooter: Boolean,
                 footerHeight: (Float) -> Float): CardInspectorFit {
            val width = maxOf(available.width, 1f)
            val height = maxOf(available.height, 1f)
            if (width > height) {
                val largestCard = minOf(width * LANDSCAPE_CARD_FRACTION, height / cardAspect)
                if (!hasFooter) return CardInspectorFit(BoardSize(largestCard, largestCard * cardAspect), BoardSize(0f, 0f), true, true)
                var cardWidth = largestCard
                var footerWidth = 1f
                var needed = 0f
                for (scale in landscapeCardScales) {
                    cardWidth = largestCard * scale
                    footerWidth = maxOf(width - cardWidth - COLUMN_SPACING, 1f)
                    needed = footerHeight(footerWidth)
                    if (needed <= height) break
                }
                return CardInspectorFit(BoardSize(cardWidth, cardWidth * cardAspect), BoardSize(footerWidth, minOf(needed, height)),
                    true, needed <= height)
            }
            if (!hasFooter) {
                val cardHeight = minOf(height, width * cardAspect)
                return CardInspectorFit(BoardSize(cardHeight / cardAspect, cardHeight), BoardSize(0f, 0f), false, true)
            }
            val needed = footerHeight(width)
            val room = maxOf(height - SPACING, 1f)
            val maximumCard = minOf(width * cardAspect, room)
            val minimumCard = minOf(maximumCard, height * MINIMUM_CARD_FRACTION)
            val cardHeight = maxOf(minimumCard, minOf(maximumCard, room - needed))
            val footerRoom = maxOf(room - cardHeight, 0f)
            return CardInspectorFit(BoardSize(cardHeight / cardAspect, cardHeight), BoardSize(width, minOf(needed, footerRoom)),
                false, needed <= footerRoom)
        }

        /** The largest text scale whose footer fits [height]; the smallest when none does. */
        fun textScale(height: Float, heightAtScale: (Float) -> Float): Float =
            textScales.firstOrNull { heightAtScale(it) <= height } ?: textScales.last()
    }
}

/** The name banner under a showcased stack object. */
object BoardFXBannerPlan {
    /** Reduced effects draw no card, so the banner sits just under the stack point. */
    const val REDUCED_OFFSET = 54f

    /** Distance from the stack point to the banner's center; with motion, below the showcased card, abilities included. */
    fun offset(showcaseHeight: Float, motion: Boolean): Float = if (motion) showcaseHeight / 2 + 22 else REDUCED_OFFSET

    /** Abilities read as "<source> · ability"; spells keep their own name. */
    fun title(name: String, isAbility: Boolean, sourceName: String?): String {
        if (!isAbility) return name
        val source = sourceName?.trim().orEmpty()
        if (source.isNotEmpty()) return "$source · ability"
        return if (name.contains("ability", ignoreCase = true)) name else "$name · ability"
    }
}

/**
 * Combat keywords a battlefield card shows while it attacks or blocks (CombatKeyword in
 * BoardCardPresentation.swift). They come from the permanent's current engine view: XMage's
 * keyword icons and bare keyword rules lines are built from its live abilities, so keywords
 * gained from other effects are included. The view carries no printed/gained provenance.
 * Entry order is badge priority; `rawValue` matches Swift's case names (combat-cases.json).
 */
enum class CombatKeyword(val rawValue: String, val label: String, val iconType: String) {
    DOUBLE_STRIKE("doubleStrike", "Double strike", "ABILITY_DOUBLE_STRIKE"),
    FIRST_STRIKE("firstStrike", "First strike", "ABILITY_FIRST_STRIKE"),
    DEATHTOUCH("deathtouch", "Deathtouch", "ABILITY_DEATHTOUCH"),
    TRAMPLE("trample", "Trample", "ABILITY_TRAMPLE"),
    LIFELINK("lifelink", "Lifelink", "ABILITY_LIFELINK"),
    INDESTRUCTIBLE("indestructible", "Indestructible", "ABILITY_INDESTRUCTIBLE"),
    MENACE("menace", "Menace", "ABILITY_MENACE"),
    FLYING("flying", "Flying", "ABILITY_FLYING"),
    REACH("reach", "Reach", "ABILITY_REACH"),
    VIGILANCE("vigilance", "Vigilance", "ABILITY_VIGILANCE");

    /** For narrow cards. */
    val shortLabel: String get() = when (this) {
        DOUBLE_STRIKE -> "2× strike"; FIRST_STRIKE -> "1st strike"; INDESTRUCTIBLE -> "Indestr."; else -> label
    }

    companion object {
        private val byIcon = entries.associateBy { it.iconType }
        private val byWord = entries.associateBy { it.label.lowercase() }
        private val markup = Regex("<[^>]*>")
        private val reminder = Regex("\\([^)]*\\)")

        fun of(rawValue: String): CombatKeyword? = entries.firstOrNull { it.rawValue == rawValue }

        /** Deals combat damage in the first-strike damage step. */
        fun strikesFirst(keywords: Set<CombatKeyword>): Boolean = FIRST_STRIKE in keywords || DOUBLE_STRIKE in keywords

        /** Deals combat damage in the regular damage step (no first strike, or double strike). */
        fun strikesInRegularStep(keywords: Set<CombatKeyword>): Boolean = FIRST_STRIKE !in keywords || DOUBLE_STRIKE in keywords

        /**
         * Keywords from engine icons and from rules lines made only of keywords ("Double strike",
         * "Flying, trample", "Menace <i>(reminder)</i>"). Sentences that merely mention a keyword
         * never count. Badge order, no duplicates.
         */
        fun of(icons: List<XmageCardIcon>?, rules: String?): List<CombatKeyword> {
            val found = mutableSetOf<CombatKeyword>()
            for (icon in icons ?: emptyList()) byIcon[icon.iconType.uppercase()]?.let { found += it }
            for (rawLine in (rules ?: "").split('\n', '\r')) {
                val line = rawLine.replace(markup, "").replace(reminder, "").trim { it.isWhitespace() || it == '.' }
                if (line.isEmpty()) continue
                val words = line.split(',').map { it.trim().lowercase() }
                val keywords = words.mapNotNull { byWord[it] }
                if (keywords.size != words.size) continue
                found += keywords
            }
            return entries.filter { it in found }
        }
    }
}

/** Attacking or blocking in the public combat groups. */
val ZoneCard.isInCombat: Boolean get() = isAttacking == true || !blocking.isNullOrEmpty()

val ZoneCard.combatKeywords: List<CombatKeyword> get() = CombatKeyword.of(cardIcons, card.oracleText)

/**
 * Which combat keyword badges fit on a battlefield card that is attacking or blocking.
 * Double strike already says first strike, so first strike is not repeated beside it.
 */
class CombatKeywordBadgePlan(keywords: List<CombatKeyword>, cardWidth: Float, cardHeight: Float) {
    val visible: List<CombatKeyword>
    /** Keywords that do not fit; they keep their icon in the card's ability row. */
    val hiddenCount: Int
    /** Narrow cards use short labels ("2× strike"). */
    val compact: Boolean = cardWidth < COMPACT_WIDTH

    init {
        val shown = if (CombatKeyword.DOUBLE_STRIKE in keywords) keywords.filter { it != CombatKeyword.FIRST_STRIKE } else keywords
        val row = fontSize(cardWidth) + 7
        // Room between the name header and the footer with its icon row.
        val slots = maxOf(1, minOf(3, ((cardHeight - 56) / row).toInt()))
        visible = shown.take(slots)
        hiddenCount = shown.size - visible.size
    }

    fun label(keyword: CombatKeyword): String = if (compact) keyword.shortLabel else keyword.label

    companion object {
        const val COMPACT_WIDTH = 66f
        fun fontSize(cardWidth: Float): Float = minOf(9f, maxOf(6.5f, cardWidth * 0.1f))
    }
}
