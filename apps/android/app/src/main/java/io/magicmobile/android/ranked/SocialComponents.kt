package io.magicmobile.android.ranked

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import io.magicmobile.android.game.PlayerSearchResult
import io.magicmobile.android.game.RankPosition
import io.magicmobile.android.menus.ArenaButton
import io.magicmobile.android.menus.ArenaButtonFace
import io.magicmobile.android.menus.arenaGlassPanel
import io.magicmobile.android.menus.arenaShadow
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.widthIn
import io.magicmobile.android.menus.ArenaButtonKind
import io.magicmobile.android.menus.ArenaButtonText
import io.magicmobile.android.menus.ArenaGlass
import io.magicmobile.android.menus.ArenaMenuStyle
import io.magicmobile.android.ui.FitText
import io.magicmobile.android.ui.LaunchEnvironment
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.rgb

// The small pieces the friends panel and public profiles share, in Arena's glass and gold (SocialComponents.swift).

/** A notice that floats at the bottom: a dark glass capsule in the hairline. Tap to dismiss. */
@Composable
fun SocialNotice(text: String, dismiss: () -> Unit, modifier: Modifier = Modifier) {
    Box(modifier.padding(horizontal = 20.dp).padding(bottom = 10.dp).glow(Color.Black.copy(alpha = 0.6f), 8.dp, 22.dp)
        .defaultMinSize(minHeight = 44.dp).padding(1.5.dp)
        .background(Color.Black.copy(alpha = 0.55f), CircleShape).border(0.9.dp, ArenaGlass.hairline, CircleShape)
        .clickable(onClick = dismiss).semantics { contentDescription = text }.testTag("friends.notice")
        .padding(horizontal = 18.dp, vertical = 10.dp), contentAlignment = Alignment.Center) {
        Text(text, color = rgb(1.0, 0.91, 0.66), style = ArenaMenuStyle.font(13f, SfWeight.heavy), textAlign = TextAlign.Center)
    }
}

/** A line of waiting, drawn without a system spinner: three gold pips that breathe in turn. */
@Composable
fun SocialWaiting(text: String) {
    val transition = rememberInfiniteTransition(label = "waiting")
    Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 36.dp).clearAndSetSemantics { contentDescription = text },
        horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            for (index in 0 until 3) {
                val phase by transition.animateFloat(0.35f, 1f, infiniteRepeatable(tween(700 + index * 120), RepeatMode.Reverse), label = "pip$index")
                Box(Modifier.size(7.dp).alpha(if (LaunchEnvironment.reduceMotion) 0.8f else phase).background(ArenaMenuStyle.gold, CircleShape))
            }
        }
        Text(text, color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(13f, SfWeight.semibold))
    }
}

/**
 * A player's name in a list: their commander's art in a ring (a dot for who is online), the name, a line under it, and their
 * rank. `compact` is the one-line row of Arena's social panel: a smaller picture and the rank's emblem alone.
 */
@Composable
fun SocialPlayerHeading(username: String, commander: String?, line: String, online: Boolean?, rank: RankPosition?, modifier: Modifier = Modifier,
                        compact: Boolean = false) {
    Row(modifier.fillMaxWidth().defaultMinSize(minHeight = if (compact) 48.dp else 56.dp), horizontalArrangement = Arrangement.spacedBy(if (compact) 10.dp else 12.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(if (compact) 40.dp else 52.dp), contentAlignment = Alignment.Center) {
            CommanderArtMedallion(commander, if (compact) 32.dp else 40.dp)
            if (online != null) Box(Modifier.align(Alignment.BottomEnd).size(if (compact) 10.dp else 12.dp)
                .background(if (online) rgb(0.4, 0.85, 0.4) else Color.Gray.copy(alpha = 0.6f), CircleShape)
                .border(1.5.dp, Color.Black.copy(alpha = 0.7f), CircleShape))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            FitText(username, ArenaMenuStyle.font(if (compact) 15f else 16f, SfWeight.bold), color = ArenaMenuStyle.text, minimumScale = 0.75f)
            Text(line, color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(12f, SfWeight.medium), maxLines = 1)
        }
        if (compact) Box(Modifier.width(28.dp).clearAndSetSemantics { }, contentAlignment = Alignment.Center) {
            if (rank != null) RankEmblem(rank.tier, 24.dp) else SfImage("shield.lefthalf.filled", ArenaMenuStyle.gold.copy(alpha = 0.4f), 15.dp)
        } else Column(Modifier.width(62.dp).clearAndSetSemantics { }, horizontalAlignment = Alignment.CenterHorizontally) {
            if (rank != null) {
                RankEmblem(rank.tier, 34.dp)
                FitText(rank.title, ArenaMenuStyle.font(10f, SfWeight.heavy), color = ArenaMenuStyle.text, minimumScale = 0.7f, textAlign = TextAlign.Center)
            } else {
                Box(Modifier.size(34.dp), contentAlignment = Alignment.Center) { SfImage("shield.lefthalf.filled", ArenaMenuStyle.gold.copy(alpha = 0.4f), 20.dp) }
                Text("Unranked", color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(10f, SfWeight.semibold))
            }
        }
    }
}

/** One player or one request in a list: a dark glass row edged with the hairline. */
@Composable
fun SocialRowCard(content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().background(Color.Black.copy(alpha = 0.32f), RoundedCornerShape(10.dp))
        .border(0.8.dp, ArenaGlass.hairline, RoundedCornerShape(10.dp)).padding(horizontal = 10.dp, vertical = 6.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)) { content() }
}

/** The face of an orange Arena pill without its own tap (it sits inside a menu button). */
@Composable
fun TavernFacePlaque(title: String, compact: Boolean = true) {
    ArenaButtonFace(ArenaButtonKind.PRIMARY, ArenaMenuStyle.title(if (compact) 14f else 15f, SfWeight.bold), pressed = false,
        Modifier.defaultMinSize(minHeight = 44.dp), fills = false, inset = 10.dp, glow = 0.7f) { ArenaButtonText(title) }
}

/**
 * A confirmation in the Arena menus (BoardChrome.swift tavernConfirmation over Arena's glass): the title in gold capitals, a few
 * words, the action as a red (destructive) or orange pill and Cancel as the dark one, over the dimmed page. A tap outside cancels.
 */
@Composable
fun ArenaConfirmation(title: String, message: String?, actionTitle: String, destructive: Boolean, confirm: () -> Unit, dismiss: () -> Unit) {
    androidx.compose.ui.window.Dialog(dismiss, androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false)) {
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.55f))
            .clickable(androidx.compose.runtime.remember { androidx.compose.foundation.interaction.MutableInteractionSource() }, null, onClick = dismiss),
            contentAlignment = Alignment.Center) {
            Column(Modifier.padding(horizontal = 24.dp).widthIn(max = 330.dp).fillMaxWidth().arenaGlassPanel(16.dp)
                .clickable(androidx.compose.runtime.remember { androidx.compose.foundation.interaction.MutableInteractionSource() }, null) {}.padding(22.dp),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Text(title.uppercase(), color = ArenaMenuStyle.gold, style = ArenaMenuStyle.title(17f, SfWeight.heavy).arenaShadow(1f, 0.7f), textAlign = TextAlign.Center)
                message?.let { Text(it, color = ArenaMenuStyle.text.copy(alpha = 0.9f), style = ArenaMenuStyle.font(14f, SfWeight.regular), textAlign = TextAlign.Center) }
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    ArenaButton({ dismiss(); confirm() }, kind = if (destructive) ArenaButtonKind.DANGER else ArenaButtonKind.PRIMARY, fullWidth = true) { ArenaButtonText(actionTitle) }
                    ArenaButton(dismiss, kind = ArenaButtonKind.SECONDARY, fullWidth = true) { ArenaButtonText("Cancel") }
                }
            }
        }
    }
}

/** The result with its relation changed (a request was sent or accepted). */
fun PlayerSearchResult.withRelation(relation: String) = copy(relation = relation, online = if (relation == "friend") online else null)

/** A tappable region that reads as one button. */
fun Modifier.socialButton(label: String, tag: String, onClick: () -> Unit): Modifier =
    this.clickable(onClick = onClick).semantics(mergeDescendants = true) { contentDescription = label; role = Role.Button }.testTag(tag)
