package io.magicmobile.android

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import io.magicmobile.android.ondevice.MultiplayerD20View
import io.magicmobile.android.ondevice.OnDeviceStartingRoll
import io.magicmobile.android.ondevice.StartingRollCover
import io.magicmobile.android.ui.LaunchEnvironment
import kotlin.math.min

/**
 * Debug builds only (MAGICMOBILE_DESIGN_PREVIEW=starting-roll, like the iOS D20 fixtures): the starting roll
 * on the tavern table with made-up seats and dice. It never creates a match. Each roll waits for a tap, or runs
 * by itself with MAGICMOBILE_STARTING_ROLL_AUTO=1; MAGICMOBILE_STARTING_ROLL_SEATS picks 2, 3 or 4 seats.
 */
@Composable
fun StartingRollPreview() {
    val seats = (LaunchEnvironment["MAGICMOBILE_STARTING_ROLL_SEATS"]?.toIntOrNull() ?: 3).coerceIn(2, 4)
    val auto = LaunchEnvironment["MAGICMOBILE_STARTING_ROLL_AUTO"] == "1"
    val seatIDs = (1..seats).map { "player$it" }
    val names = mapOf("player1" to "Caleb", "player2" to "Ruthie", "player3" to "AI 1", "player4" to "AI 2")
    val roll = remember(seats) {
        val draws = when (seats) {
            2 -> listOf(17, 6)
            3 -> listOf(12, 12, 7, 20, 14)
            else -> listOf(8, 15, 15, 3, 15, 11)
        }.iterator()
        OnDeviceStartingRoll.generate(seatIDs) { if (draws.hasNext()) draws.next() else 1 }
    }
    var revealed by remember { mutableIntStateOf(if (auto) 1 else 0) }
    var dismissed by remember { mutableStateOf(false) }
    if (dismissed) {
        Box(Modifier.fillMaxSize()) { Text("Starting roll preview complete", color = Color.White) }
        return
    }
    StartingRollCover {
        MultiplayerD20View(roll, names.filterKeys { it in seatIDs }, true, revealed, roll.steps.getOrNull(revealed)?.seatID,
            onRollTap = { revealed = min(revealed + 1, roll.steps.size) },
            onStepPlayed = { if (auto) revealed = min(revealed + 1, roll.steps.size) }) { dismissed = true }
    }
}
