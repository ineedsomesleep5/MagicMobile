package io.magicmobile.android.game

import java.io.File
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.float
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The Walnut Tavern geometry stays identical to scripts/brand/tavern_layout.json (and so to iOS TavernDesign / TavernSockets). */
class TavernSocketsTest {
    private val repo = File(System.getProperty("magicmobile.repo") ?: "../../..")
    private val layout = Json.parseToJsonElement(File(repo, "scripts/brand/tavern_layout.json").readText()).jsonObject

    private fun JsonObject.point(key: String): BoardPoint = this.getValue(key).jsonArray.let { BoardPoint(it[0].jsonPrimitive.float, it[1].jsonPrimitive.float) }
    private fun JsonObject.number(key: String): Float = this.getValue(key).jsonPrimitive.float
    private fun JsonArray.floats(): List<Float> = map { it.jsonPrimitive.float }

    private fun assertPoint(expected: BoardPoint, actual: BoardPoint) {
        assertEquals(expected.x, actual.x, 0.001f)
        assertEquals(expected.y, actual.y, 0.001f)
    }

    private fun check(name: String, sockets: TavernSockets) {
        val plate = layout.getValue(name).jsonObject
        val screen = plate.getValue("screen").jsonArray.floats()
        assertEquals(BoardSize(screen[0], screen[1]), sockets.canvas)
        val opponent = plate.getValue("opponentMedallion").jsonObject
        assertPoint(opponent.point("center"), sockets.opponentMedallion)
        assertEquals(opponent.number("radius"), sockets.opponentHoleRadius, 0.001f)
        val life = plate.getValue("lifeMedallion").jsonObject
        assertPoint(life.point("center"), sockets.lifeMedallion)
        assertEquals(life.number("radius"), sockets.lifeHoleRadius, 0.001f)
        assertPoint(plate.getValue("passButton").jsonObject.point("center"), sockets.passButton)
        val rail = plate.getValue("manaRail").jsonObject
        assertEquals(rail.getValue("socketXs").jsonArray.floats(), sockets.manaSocketXs)
        assertEquals(rail.number("socketY"), sockets.manaSocketY, 0.001f)
        val mat = plate.getValue("mat").jsonArray.floats()
        assertEquals(mat[0], sockets.mat.minX, 0.001f)
        assertEquals(mat[1], sockets.mat.minY, 0.001f)
        // The portrait mat's right and bottom edges are its stitched edge (414, 723); landscape lists them too.
        assertEquals(mat[2], sockets.mat.maxX, 0.001f)
        assertEquals(mat[3], if (name == "portrait") TavernDesign.matBottom else sockets.mat.maxY, 0.001f)
    }

    @Test fun portraitSocketsMatchTheLayout() {
        check("portrait", TavernSockets.portrait)
        val plate = layout.getValue("portrait").jsonObject
        assertEquals(plate.getValue("passButton").jsonObject.number("radius"), TavernDesign.passHoleRadius, 0.001f)
        assertEquals(plate.getValue("manaRail").jsonObject.number("socketRadius"), TavernDesign.manaSocketRadius, 0.001f)
    }

    @Test fun landscapeSocketsMatchTheLayout() = check("landscape", TavernSockets.landscape)

    @Test fun socketsFollowTheScreensOrientation() {
        assertEquals(TavernSockets.portrait, TavernSockets.current(BoardSize(412f, 915f)))
        assertEquals(TavernSockets.landscape, TavernSockets.current(BoardSize(915f, 412f)))
        assertEquals(TavernSockets.portrait, TavernSockets.current(null))
        // Both axes scale: the pass socket lands on the plate on a screen of another shape.
        val point = BoardSize(412f, 915f).tavernPoint(TavernDesign.passButton)
        assertEquals(366f * 412f / 440f, point.x, 0.001f)
        assertEquals(877f * 915f / 956f, point.y, 0.001f)
        assertEquals(96f * 1.04f * 412f / 440f, TavernDesign.passDiameter(BoardSize(412f, 915f)), 0.001f)
    }

    @Test fun lanesSitInsideTheMatOnTheTavernTable() {
        val classic = PortraitBattlefieldLayoutMetrics(BoardSize(440f, 900f))
        val tavern = PortraitBattlefieldLayoutMetrics(BoardSize(440f, 900f), tavernDock = true)
        assertEquals(10f, classic.laneInset, 0.001f)
        assertEquals(26f, tavern.laneInset, 0.001f)
        assertEquals(84f, tavern.bottomControlsRect.height, 0.001f)
        assertEquals(tavern.handCardHeight + 22, tavern.handRowHeight, 0.001f)
        assertEquals(classic.safeFrame.minX + 6, tavern.handRect.minX, 0.001f)
    }

    @Test fun phaseTrackNamesTheStepAndItsPhase() {
        assertEquals("Declare blockers" to 2, TavernPhaseTrack.describe("DECLARE_BLOCKERS"))
        assertEquals("Main phase 2" to 3, TavernPhaseTrack.describe("postcombat-main"))
        assertEquals("" to null, TavernPhaseTrack.describe(null))
        assertNull(TavernPhaseTrack.describe("something-new").second)
    }

    private fun card(type: String, token: Boolean = false, creature: Boolean = type.contains("Creature")): ZoneCard =
        ZoneCard("card", CardIdentity("Card", type, isToken = token), isCreaturePermanent = creature)

    @Test fun framesFollowTheCardsCurrentType() {
        assertEquals(TavernFrameKind.CREATURE, TavernFrameKind.of(card("Creature — Bear")))
        assertEquals(TavernFrameKind.TOKEN, TavernFrameKind.of(card("Token Creature — Squirrel", token = true)))
        assertEquals(TavernFrameKind.ARTIFACT, TavernFrameKind.of(card("Artifact")))
        assertEquals(TavernFrameKind.ENCHANTMENT, TavernFrameKind.of(card("Enchantment — Aura")))
        assertEquals(TavernFrameKind.LAND, TavernFrameKind.of(card("Basic Land — Forest")))
        // A creature of any other type is framed as the creature it is now.
        assertEquals(TavernFrameKind.CREATURE, TavernFrameKind.of(card("Artifact Creature — Golem")))
        assertEquals(TavernFrameKind.CREATURE, TavernFrameKind.of(card("Land Creature — Elemental", creature = true)))
        assertFalse(TavernFrameKind.LAND.showsRibbon(card("Basic Land — Forest")))
        assertTrue(TavernFrameKind.LAND.showsRibbon(card("Land")))
    }

    @Test fun effectsCurveAroundTheOpponentMedallionStartingUnderIt() {
        val radius = TavernEffectOrbit.radius(TavernSockets.portrait.opponentHoleRadius)
        val slots = TavernEffectOrbit.offsets(5, radius, TavernSockets.portrait.opponentEffectsBearing)
        // First straight under the portrait, then alternating either side.
        assertPoint(BoardPoint(0f, radius), slots[0])
        assertEquals(-slots[1].x, slots[2].x, 0.001f)
        assertEquals(slots[1].y, slots[2].y, 0.001f)
        assertTrue(slots[3].y < slots[1].y)
        // Every badge stays between the nameplate and the phase plate (each 118 wide, 110 either side of the medallion).
        val badge = radius * TavernEffectOrbit.BADGE_SHARE
        for (slot in slots) assertTrue(kotlin.math.abs(slot.x) + badge / 2 <= 110 - 59)
        // Neighbours do not overlap.
        for (index in 2 until slots.size) {
            val a = slots[index]; val b = slots[index - 2]
            assertTrue(kotlin.math.hypot((a.x - b.x).toDouble(), (a.y - b.y).toDouble()) >= badge - 0.5)
        }
    }

    @Test fun commanderDamageLeadsTheOrbitAndOverflowBecomesAMarker() {
        val opponent = PlayerGameState("p2", "AI 1", 29, 0, 2, zones = PlayerZones(emptyList(), emptyList(), emptyList(), emptyList(), emptyList(), emptyList(), emptyList()),
            counters = mapOf("poison" to 3, "energy" to 2, "experience" to 1), monarch = true, initiative = true)
        val me = PlayerGameState("p1", "You", 40, 0, 0, zones = opponent.zones,
            commanders = listOf(CommanderPublicState("c1", "Gishath", "p1", damageToPlayers = mapOf("p2" to 9))))
        val snapshot = GameSnapshot(id = "g", phase = "combat", turn = 14, players = listOf(me, opponent), log = emptyList())
        val summary = PlayerStatusSummary(opponent, snapshot)
        assertTrue(summary.orbit.first().icon is PlayerStatusSummary.Icon.Commander)
        assertTrue(summary.orbit[1].icon is PlayerStatusSummary.Icon.Poison)
        assertEquals(listOf("29 life", "0 in hand", "0 in library", "Tax 2"), summary.facts)
        val (shown, more) = TavernEffectOrbit.shown(summary, 5)
        assertEquals(4, shown.size)
        assertEquals(summary.badges.size - 4, more)
        assertEquals(summary.badges.size to 0, TavernEffectOrbit.shown(summary, 99).let { it.first.size to it.second })
    }
}
