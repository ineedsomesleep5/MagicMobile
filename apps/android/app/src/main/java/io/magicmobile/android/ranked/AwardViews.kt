package io.magicmobile.android.ranked

import android.graphics.BitmapFactory
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import io.magicmobile.android.game.Award
import io.magicmobile.android.menus.ArenaButton
import io.magicmobile.android.menus.ArenaButtonKind
import io.magicmobile.android.menus.ArenaButtonText
import io.magicmobile.android.menus.ArenaCaps
import io.magicmobile.android.menus.ArenaMenuStyle
import io.magicmobile.android.social.PlayerAccount
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.LaunchEnvironment
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.sf
import java.net.HttpURLConnection
import java.net.URL
import java.text.DateFormat
import java.util.Date
import kotlin.math.max
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private val gold = Color(0xFFFFCC5C)
private val metal = listOf(Color(0xFFFFEDAD), gold, Color(0xFF8C5C1F))

private val Award.color get() = Color(0xFF000000 or tint.toLong())

/** The award's note and the day it was earned. */
private val Award.caption get() = listOfNotNull(note, awardedAt?.let { DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(it)) }).joinToString(" · ")

/** Award art, downloaded once a launch (Android has no image loader here; iOS uses AsyncImage). */
private object AwardArt {
    private const val MAX_BYTES = 4L * 1024 * 1024
    private val loaded = mutableMapOf<String, ImageBitmap>()

    suspend fun load(url: String): ImageBitmap? = synchronized(loaded) { loaded[url] } ?: withContext(Dispatchers.IO) {
        runCatching {
            val connection = URL(url).openConnection() as HttpURLConnection
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            try {
                if (connection.responseCode != 200 || connection.contentLengthLong > MAX_BYTES) return@runCatching null
                val bytes = connection.inputStream.use { it.readBytes() }
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap()?.also { synchronized(loaded) { loaded[url] = it } }
            } finally { connection.disconnect() }
        }.getOrNull()
    }
}

/** An award's art, or a star medal in its tint when it has none or it can't load. */
@Composable
fun AwardMedal(award: Award, size: Dp = 60.dp) {
    val art by produceState<ImageBitmap?>(null, award.imageUrl) { value = award.imageUrl?.let { AwardArt.load(it) } }
    val glow = when (award.rarity) { 3 -> award.color.copy(alpha = 0.8f); 2 -> award.color.copy(alpha = 0.45f); else -> Color.Transparent }
    Box(Modifier.size(size).glow(glow, size * (if (award.rarity == 3) 0.2f else 0.12f), size / 2), contentAlignment = Alignment.Center) {
        val image = art
        if (image != null) Image(image, null, Modifier.size(size)) else {
            Canvas(Modifier.matchParentSize()) {
                val radius = this.size.minDimension / 2
                val line = radius * 0.1f
                drawCircle(Brush.radialGradient(listOf(award.color, award.color.copy(alpha = 0.45f), Color.Black), Offset(radius, radius), radius * 1.12f), radius)
                if (award.rarity == 3) drawCircle(Brush.verticalGradient(metal), radius - line / 2, style = Stroke(line))
                else drawCircle(award.color.copy(alpha = 0.8f), radius - line / 2, style = Stroke(line))
            }
            SfImage("star.fill", gold, size * 0.44f)
        }
    }
}

/** A row of awards, best first. Tapping one opens it. */
@Composable
fun AwardShelf(awards: List<Award>, size: Dp = 60.dp) {
    var open by remember { mutableStateOf<Award?>(null) }
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 2.dp, vertical = size * 0.1f).testTag("awards"),
        horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
        for (award in awards) {
            Column(Modifier.width(size * 1.55f).clickable { GameAudio.play(GameSound.UI_OPEN); open = award }
                .semantics(mergeDescendants = true) { contentDescription = "${award.name}. ${award.detail}"; role = Role.Button }
                .testTag("award.${award.id}"), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(size * 0.08f)) {
                AwardMedal(award, size)
                Text(award.name, color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(max(10f, size.value * 0.18f), SfWeight.semibold), textAlign = TextAlign.Center, maxLines = 2)
            }
        }
    }
    open?.let { award ->
        Dialog({ open = null }, DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) { AwardCeremony(award) { open = null } }
    }
}

/** One award, large: over the menu when it is new, or opened from a shelf. Only Continue closes it. */
@Composable
fun AwardCeremony(award: Award, isNew: Boolean = false, close: () -> Unit) {
    val pop = remember { Animatable(0f) }
    LaunchedEffect(Unit) {
        if (isNew) GameAudio.play(GameSound.VICTORY)
        if (LaunchEnvironment.reduceMotion) pop.animateTo(1f, tween(120))
        else pop.animateTo(1f, spring(dampingRatio = 0.6f, stiffness = Spring.StiffnessLow))
    }
    BackHandler(isNew) {}
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.9f)).clickable(remember { MutableInteractionSource() }, null) {}.testTag("award.ceremony")) {
        Column(Modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = 24.dp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Spacer(Modifier.weight(1f))
            if (isNew) ArenaCaps("New award")
            Box(Modifier.padding(vertical = 14.dp).scale(0.6f + 0.4f * pop.value).alpha(pop.value.coerceIn(0f, 1f))) { AwardMedal(award, 170.dp) }
            Text(award.name, Modifier.semantics { heading() }, style = sf(28f, SfWeight.black, SfDesign.SERIF).copy(brush = Brush.verticalGradient(listOf(Color(0xFFFFE69E), award.color))),
                textAlign = TextAlign.Center)
            if (award.detail.isNotEmpty()) Text(award.detail, color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(15f, SfWeight.medium), textAlign = TextAlign.Center)
            if (award.caption.isNotEmpty()) Text(award.caption, color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(12f, SfWeight.semibold), textAlign = TextAlign.Center)
            Spacer(Modifier.weight(1f))
            ArenaButton(close, Modifier.padding(bottom = 28.dp).width(220.dp), kind = ArenaButtonKind.PRIMARY, fontSize = 18f, label = "Continue",
                identifier = "award.ceremony.continue") { ArenaButtonText("Continue") }
        }
    }
}

/** Keeps the player's awards fresh on the menu and opens a new one there, never over a game. */
@Composable
fun AwardCeremonyHost(account: PlayerAccount, ready: Boolean, busy: Boolean) {
    LaunchedEffect(ready, busy) { if (ready && !busy) account.refreshAwards() }
    if (busy) return
    val award = account.awards.firstOrNull { !it.seen } ?: return
    androidx.compose.runtime.key(award.id) { AwardCeremony(award, isNew = true) { account.markAwardSeen(award) } }
}
