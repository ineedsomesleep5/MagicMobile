package io.magicmobile.android.laws

import io.magicmobile.android.game.ArenaCanvas
import io.magicmobile.android.game.BoardRect
import io.magicmobile.android.game.BoardSize
import io.magicmobile.android.laws.Laws.forAll
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Every Arena board control stays fully on screen on every phone, in both orientations. Build 57's landscape gear sat 1 pt
 * above the top edge on a 402 pt tall iPhone; this law covers the whole range of phone sizes, not one.
 */
class ArenaLayoutLawsTest {
    /** The gear's touch target (NativeGameView+Arena.swift: 44 × 44 around its point). */
    private val gearTarget = 44f

    private fun assertOnScreen(label: String, rect: BoardRect, screen: BoardSize) =
        assertTrue("$label $rect leaves the ${screen.width}×${screen.height} screen",
            rect.minX >= 0 && rect.minY >= 0 && rect.maxX <= screen.width && rect.maxY <= screen.height)

    @Test fun everyControlStaysOnScreenOnEveryPhone() = forAll("Arena controls on screen") { random ->
        // Phones from a small 360 × 740 Android to a 440 × 956 Pro Max, held either way.
        val short = random.nextInt(360, 441).toFloat(); val long = random.nextInt(740, 957).toFloat()
        val screen = if (random.nextBoolean()) BoardSize(long, short) else BoardSize(short, long)
        val canvas = ArenaCanvas(screen); val layout = canvas.layout
        val gear = canvas.point(layout.menu)
        assertOnScreen("gear", BoardRect(gear.x - gearTarget / 2, gear.y - gearTarget / 2, gearTarget, gearTarget), screen)
        assertOnScreen("primary button", canvas.rect(layout.primary), screen)
        assertOnScreen("secondary button", canvas.rect(layout.secondary), screen)
        assertOnScreen("pass ahead", canvas.rect(layout.passAhead), screen)
        assertOnScreen("undo", canvas.rect(layout.undo), screen)
    }
}
