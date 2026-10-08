package io.magicmobile.android.game

/*
 * The Walnut Tavern table's geometry and rules (iOS Board/BoardChrome.swift TavernDesign,
 * TavernSockets, TavernPhaseTrack, PlayerStatusSummary and ArenaBoardPresentation.swift
 * TavernFrameKind). The numbers are the iOS ones and scripts/brand/tavern_layout.json's:
 * change all three together.
 */

/**
 * Where the tavern table's sockets are, in points on the 440 x 956 design canvas the portrait
 * plate is painted for. The plate fills the whole screen, so other sizes scale both axes.
 */
object TavernDesign {
    val canvas = BoardSize(440f, 956f)
    val opponentMedallion = BoardPoint(219.2f, 95f)
    const val opponentHoleRadius = 31f
    /** Mirrors the pass button: 74 pt from its edge. */
    val lifeMedallion = BoardPoint(74f, 882.6f)
    const val lifeHoleRadius = 35.5f
    val passButton = BoardPoint(366f, 877f)
    /** The stack tray's slot below the mana rail, between your medallion and the pass button. */
    val stackTray = BoardPoint(211f, 893f)
    const val passHoleRadius = 48f
    val manaSocketXs = listOf(146.0f, 175.4f, 204.8f, 234.7f, 264.1f, 293.5f)
    const val manaSocketY = 846.9f
    const val manaSocketRadius = 12.9f
    const val matTop = 138.6f
    const val matBottom = 723f

    /** The pass button's frame: its brass ring matches the life medallion's frame. */
    fun passDiameter(canvas: BoardSize?): Float {
        val design = passHoleRadius * 2 * 1.04f
        return canvas?.tavernLength(design) ?: design
    }
}

/** The design canvas this screen maps from: portrait 440 x 956 or landscape 956 x 440. */
val BoardSize.tavernDesignCanvas: BoardSize get() = if (width > height) TavernSockets.landscape.canvas else TavernDesign.canvas

/** A design-canvas point on this screen. */
fun BoardSize.tavernPoint(point: BoardPoint): BoardPoint =
    BoardPoint(point.x * width / tavernDesignCanvas.width, point.y * height / tavernDesignCanvas.height)

fun BoardSize.tavernLength(value: Float): Float = value * width / tavernDesignCanvas.width

/** A design-canvas rectangle on this screen. */
fun BoardSize.tavernRect(rect: BoardRect): BoardRect {
    val origin = tavernPoint(BoardPoint(rect.minX, rect.minY))
    val end = tavernPoint(BoardPoint(rect.maxX, rect.maxY))
    return BoardRect(origin.x, origin.y, end.x - origin.x, end.y - origin.y)
}

/**
 * Where the tavern table's live controls sit, in design points: the portrait plate's sockets
 * (TavernDesign, tavern_layout.json "portrait") or the landscape plate's ("landscape").
 */
data class TavernSockets(
    val canvas: BoardSize, val opponentMedallion: BoardPoint, val opponentHoleRadius: Float, val opponentNameplate: BoardPoint,
    val opponentHand: BoardPoint, val phasePlate: BoardPoint, val opponentGlance: BoardPoint, val lifeMedallion: BoardPoint,
    val lifeHoleRadius: Float, val chat: BoardPoint, val passButton: BoardPoint, val skip: BoardPoint, val menu: BoardPoint,
    val stackTray: BoardPoint, val manaSocketXs: List<Float>, val manaSocketY: Float,
    /** The leather mat; in landscape the battlefield column is laid on it down to `handBottom`. */
    val mat: BoardRect, val handBottom: Float,
) {
    val isLandscape: Boolean get() = canvas.width > canvas.height

    companion object {
        val portrait: TavernSockets = run {
            val center = TavernDesign.opponentMedallion
            val pass = TavernDesign.passButton
            TavernSockets(
                canvas = TavernDesign.canvas, opponentMedallion = center, opponentHoleRadius = TavernDesign.opponentHoleRadius,
                opponentNameplate = BoardPoint(center.x - 110, center.y + 8), opponentHand = BoardPoint(center.x, center.y - 40),
                phasePlate = BoardPoint(center.x + 110, center.y + 8), opponentGlance = BoardPoint(center.x + 110, center.y + 46),
                lifeMedallion = TavernDesign.lifeMedallion, lifeHoleRadius = TavernDesign.lifeHoleRadius,
                chat = BoardPoint(TavernDesign.lifeMedallion.x + 42, TavernDesign.lifeMedallion.y + 52),
                passButton = pass, skip = BoardPoint(pass.x - 71, pass.y + 10), menu = BoardPoint(pass.x - 51, pass.y + 51),
                stackTray = TavernDesign.stackTray, manaSocketXs = TavernDesign.manaSocketXs, manaSocketY = TavernDesign.manaSocketY,
                mat = BoardRect(26f, TavernDesign.matTop, 388f, TavernDesign.matBottom - TavernDesign.matTop), handBottom = 830f)
        }

        /**
         * The landscape plate (956 x 440, a phone held sideways): the opponent's medallion and nameplate up
         * the left walnut column with your medallion at its foot; the phase plate, stack tray and pass button
         * down the right; the mat between them, as big as the screen allows (Caleb, 2026-10-02); the hand
         * resting over the mat's foot and the mana rail below. Skip and the controls ring orbit the pass
         * button's upper left.
         */
        val landscape: TavernSockets = run {
            val pass = BoardPoint(846f, 344f)
            TavernSockets(
                canvas = BoardSize(956f, 440f), opponentMedallion = BoardPoint(118f, 76f), opponentHoleRadius = 30f,
                opponentNameplate = BoardPoint(118f, 144f), opponentHand = BoardPoint(118f, 34f),
                phasePlate = BoardPoint(840f, 42f), opponentGlance = BoardPoint(118f, 188f),
                lifeMedallion = BoardPoint(118f, 344f), lifeHoleRadius = 34f,
                chat = BoardPoint(160f, 404f),
                passButton = pass, skip = BoardPoint(pass.x - 40, pass.y - 60), menu = BoardPoint(pass.x + 20, pass.y - 70),
                stackTray = BoardPoint(840f, 180f),
                manaSocketXs = listOf(407f, 435f, 463f, 491f, 519f, 547f), manaSocketY = 416f,
                mat = BoardRect(172f, 8f, 610f, 392f), handBottom = 404f)
        }

        fun current(canvas: BoardSize?): TavernSockets = if (canvas != null && canvas.width > canvas.height) landscape else portrait
    }
}

/** The step of the turn in plain words, and which of the five phases it belongs to. */
object TavernPhaseTrack {
    val phases = listOf("Beginning", "Main 1", "Combat", "Main 2", "End")

    fun describe(raw: String?): Pair<String, Int?> {
        if (raw.isNullOrEmpty()) return "" to null
        return when (raw.lowercase().replace("_", "-")) {
            "beginning", "untap" -> "Untap step" to 0
            "upkeep" -> "Upkeep" to 0
            "draw" -> "Draw step" to 0
            "precombat-main", "main1" -> "Main phase 1" to 1
            "combat", "begin-combat" -> "Beginning of combat" to 2
            "declare-attackers" -> "Declare attackers" to 2
            "declare-blockers" -> "Declare blockers" to 2
            "first-combat-damage", "first-strike-damage" -> "First-strike damage" to 2
            "combat-damage" -> "Combat damage" to 2
            "end-combat" -> "End of combat" to 2
            "postcombat-main", "main2" -> "Main phase 2" to 3
            "ending", "end", "end-turn" -> "End step" to 4
            "cleanup" -> "Cleanup" to 4
            else -> EngineDisplayText.phaseLabel(raw) to null
        }
    }
}

/**
 * Which tavern frame a permanent wears (Caleb, 2026-10-02): creatures gold, creature tokens walnut,
 * artifacts silver, enchantments rose-gold, lands stone. A creature of any other type (an artifact
 * creature, an animated land) is framed as the creature it is now.
 */
enum class TavernFrameKind(val rawValue: String) {
    CREATURE("creature"), TOKEN("token"), ARTIFACT("artifact"), ENCHANTMENT("enchantment"), LAND("land"), SPELL("spell");

    /**
     * The arched art window's bounding box in each frame image, as fractions of the tile (printed by
     * scripts/brand/card_frames.sh, widened 1% under the rim). The frame covers the art outside the arch.
     */
    val window: BoardRect get() = when (this) {
        CREATURE -> BoardRect(0.078f, 0.156f, 0.847f, 0.75f)
        TOKEN -> BoardRect(0.087f, 0.142f, 0.835f, 0.762f)
        ARTIFACT -> BoardRect(0.093f, 0.164f, 0.829f, 0.728f)
        ENCHANTMENT -> BoardRect(0.084f, 0.17f, 0.829f, 0.733f)
        LAND -> BoardRect(0.09f, 0.15f, 0.82f, 0.756f)
        SPELL -> BoardRect(0.093f, 0.164f, 0.814f, 0.736f)
    }

    /** Basic lands are known by their art; every other permanent names itself on the ribbon. */
    fun showsRibbon(card: ZoneCard): Boolean = this != LAND || !card.card.typeLine.contains("basic", ignoreCase = true)

    companion object {
        /** The name ribbon's centre, as a fraction of the tile height, across the art's lower part. */
        const val ribbonCenterY = 0.72f

        fun of(card: ZoneCard): TavernFrameKind {
            val identity = card.card
            return when {
                card.isCreature -> if (identity.isToken == true || identity.typeLine.contains("token", ignoreCase = true)) TOKEN else CREATURE
                identity.isLand -> LAND
                identity.isArtifact -> ARTIFACT
                identity.isEnchantment -> ENCHANTMENT
                // Only ever held up at the centre while it is cast: a parchment scroll.
                identity.typeLine.contains("Instant", ignoreCase = true) || identity.typeLine.contains("Sorcery", ignoreCase = true) -> SPELL
                else -> CREATURE
            }
        }
    }
}

/** The painted parts every framed tile shares (scripts/brand/card_frames.sh). */
object TavernCardParts {
    const val ribbonAspect = 164f / 846f
    const val gemAspect = 306f / 266f
}

/** Eight or more identical tokens stay one pile even while they can be chosen (Caleb, 2026-10-02). */
object BattlefieldTokenStack {
    const val threshold = 8
}

/**
 * What a player carries besides their zones (Caleb, 2026-10-02): counters, the monarch and the
 * initiative, commander damage taken and cards attached to them. Shown as icons, never words; each
 * badge still names itself to accessibility services. Tints are RGB in 0...1.
 */
class PlayerStatusSummary(player: PlayerGameState, snapshot: GameSnapshot?) {
    sealed class Icon {
        object Poison : Icon()
        data class Symbol(val name: String) : Icon()
        data class Commander(val card: ZoneCard?) : Icon()
    }

    data class Tint(val red: Double, val green: Double, val blue: Double)

    data class Badge(val id: String, val icon: Icon, val tint: Tint, val count: Int?, val label: String,
                     /** Close to losing to it: ten poison, twenty-one commander damage. */
                     val nearLethal: Boolean = false)

    val badges: List<Badge>
    val attachments: List<ZoneCard>
    val isEmpty: Boolean get() = badges.isEmpty() && attachments.isEmpty()

    init {
        val list = BoardPlayerStatus.counters(player).map { (counterName, count) ->
            val name = counterName.lowercase()
            val (icon, tint) = when (name) {
                "poison" -> Icon.Poison to Tint(0.55, 0.9, 0.35)
                "energy" -> Icon.Symbol("bolt.fill") to Tint(1.0, 0.82, 0.3)
                "experience" -> Icon.Symbol("sparkles") to Tint(0.98, 0.92, 0.7)
                "rad" -> Icon.Symbol("atom") to Tint(0.75, 1.0, 0.4)
                "ticket" -> Icon.Symbol("ticket.fill") to Tint(1.0, 0.5, 0.4)
                else -> Icon.Symbol("seal.fill") to PARCHMENT
            }
            Badge("counter-$name", icon, tint, count, "${capitalizedWords(counterName)} $count", nearLethal = name == "poison" && count >= 7)
        }.toMutableList()
        if (player.monarch == true) list += Badge("monarch", Icon.Symbol("crown.fill"), Tint(1.0, 0.8, 0.4), null, "Monarch")
        if (player.initiative == true) list += Badge("initiative", Icon.Symbol("flag.fill"), Tint(0.95, 0.55, 0.35), null, "Has the initiative")
        for (designation in player.designations ?: emptyList()) {
            if (designation.isNotEmpty()) list += Badge("designation-$designation", Icon.Symbol("building.columns.fill"), Tint(0.95, 0.85, 0.55), null, designation)
        }
        if (snapshot != null) {
            // Each opposing commander that has hit this player, with its art when it is visible.
            for (owner in snapshot.players) {
                if (owner.playerId == player.playerId) continue
                for (commander in owner.commanders ?: emptyList()) {
                    val damage = commander.damageToPlayers?.get(player.playerId) ?: continue
                    if (damage <= 0) continue
                    val zones = owner.zones
                    val card = (zones.command + zones.battlefield + zones.graveyard + zones.exile + zones.hand).firstOrNull { it.instanceId == commander.id }
                    list += Badge("commander-${commander.id}", Icon.Commander(card), EMBER, damage,
                        "${commander.name ?: "Commander"} dealt $damage commander damage", nearLethal = damage >= 15)
                }
            }
            attachments = ZoneCard.enchanting(player.playerId, snapshot.players.flatMap { it.zones.battlefield })
        } else {
            attachments = emptyList()
        }
        badges = list
    }

    val accessibilityText: String get() = (badges.map { it.label } + attachments.map { "${it.card.name} attached" }).joinToString(", ")

    /** The most pressing badges beside a medallion: poison and the worst commander damage. */
    val glance: List<Badge> get() {
        val poison = badges.filter { it.icon is Icon.Poison }
        val worstCommander = badges.filter { it.icon is Icon.Commander }.maxByOrNull { it.count ?: 0 }
        return poison + listOfNotNull(worstCommander)
    }

    companion object {
        val PARCHMENT = Tint(0.95, 0.88, 0.74)
        val EMBER = Tint(1.0, 0.50, 0.34)
    }
}
