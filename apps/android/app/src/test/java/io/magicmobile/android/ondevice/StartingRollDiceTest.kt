package io.magicmobile.android.ondevice

import io.magicmobile.android.ui.Vec3
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import kotlin.math.abs

/**
 * The starting roll's dice on Android (StartingRollDice.kt), against the real assets from scripts/brand/d20.py:
 * the one landing rule, and the same numbers as the Swift tests (StartingRollDiceTests.swift).
 */
class StartingRollDiceTest {
    private val resources = File("../../ios/MagicMobile/Resources/D20")
    private val model by lazy { D20Model.parse(File(resources, "d20.json").readText()) }
    private val bank by lazy { D20Throw.parseBank(File(resources, "d20-throws.json").readText()) }
    private val up = Vec3(0f, 1f, 0f)

    @Test fun oppositeFacesSumToTwentyOne() {
        assertEquals((1..20).toList(), model.faces.map { it.number }.sorted())
        for (face in model.faces) {
            val opposite = model.faces.first { (it.normal dot face.normal) < -0.99f }
            assertEquals(21, opposite.number + face.number)
        }
    }

    @Test fun symmetriesCarryTheDieOntoItself() {
        for (target in model.faces) for (resting in model.faces) for (k in 0 until 3) {
            val s = D20Landing.symmetry(target, resting, k)
            assertTrue((s.rotate(target.normal) - resting.normal).length < 1e-4f)
            for (v in model.vertices) {
                val moved = s.rotate(v)
                assertTrue("a symmetry must map every corner to a corner", model.vertices.any { (it - moved).length < 1e-4f })
            }
        }
    }

    @Test fun everyThrowEndsWithTheChosenNumberOnTop() {
        assertTrue(bank.size >= 6)
        for (recorded in bank) for (number in 1..20) {
            val plan = D20ThrowPlan(model, recorded, number, jitter = D20Landing.jitter(number, 1, 0.2f))
            val pose = plan.restPose
            val top = model.faces.maxByOrNull { pose.orientation.rotate(it.normal) dot up }!!
            assertEquals("throw ending on face ${recorded.faceUp} should land $number", number, top.number)
            assertTrue((pose.orientation.rotate(top.normal) dot up) > 0.9999f)
            assertEquals(model.inradius, pose.position.y, 1e-3f)
        }
    }

    @Test fun theSamePathServesEveryNumber() {
        val a = D20ThrowPlan(model, bank[0], 3)
        val b = D20ThrowPlan(model, bank[0], 17)
        var t = 0f
        while (t <= a.duration) {
            val pa = a.pose(t).position
            val pb = b.pose(t).position
            assertTrue((pa - pb).length < 1e-6f)
            t += 0.1f
        }
    }

    @Test fun theNumeralEndsNearlyUpright() {
        for (recorded in bank) for (number in listOf(1, 6, 9, 14, 20)) {
            val plan = D20ThrowPlan(model, recorded, number)
            val face = model.face(number)!!
            val v = plan.restPose.orientation.rotate(face.corner(0))
            assertTrue(abs(D20Landing.yaw(Vec3(v.x, 0f, v.z), Vec3(0f, 0f, -1f))) < 0.02f)
        }
    }

    @Test fun throwsStayInTheirLaneAndHitTheRailLow() {
        for (recorded in bank) {
            assertTrue(recorded.railTime > 0.3f && recorded.railTime < recorded.duration)
            for (frame in 0 until recorded.frames) assertTrue(abs(recorded.position(frame).x) < 0.4f)
            assertTrue(recorded.position(recorded.frames - 1).z > 1.2f)
        }
    }

    @Test fun layoutPutsTheRailAtTheTopOfTheRollAreaAndSpacesLanes() {
        val layout = D20TableLayout(390f, 844f, 419f, 354f, 338f, 3, 15.2f)
        assertEquals(3, layout.laneX.size)
        assertEquals(0f, layout.laneX[1], 1e-5f)
        assertEquals(layout.laneX[2] - layout.laneX[1], layout.laneX[1] - layout.laneX[0], 1e-5f)
        assertEquals(-7.6f, layout.railZ, 1e-5f)
        assertTrue(layout.footprint in 0.5f..1f)
        assertTrue(layout.cameraForward.y < 0 && layout.cameraForward.z < 0)
        assertTrue(layout.cameraPosition.y > 5f)
        val four = D20TableLayout(390f, 844f, 419f, 354f, 338f, 4, 15.2f)
        val two = D20TableLayout(390f, 844f, 419f, 354f, 338f, 2, 15.2f)
        assertTrue(four.pointsPerUnit < two.pointsPerUnit)
        assertEquals(4, four.laneX.size)
    }

    @Test fun platformsAgreeOnTheDeterministicJitter() {
        assertEquals(0.01317f, D20Landing.jitter(0, 0, 1f), 1e-3f)
        assertEquals(0.76104f, D20Landing.jitter(1, 2, 1f), 1e-3f)
        assertEquals(-0.55721f, D20Landing.jitter(3, 1, 1f), 1e-3f)
        assertEquals(0, D20Landing.throwIndex(0, 0, 12))
        assertEquals(0, D20Landing.throwIndex(1, 2, 12))
        assertEquals(9, D20Landing.throwIndex(0, 3, 12))
    }
}
