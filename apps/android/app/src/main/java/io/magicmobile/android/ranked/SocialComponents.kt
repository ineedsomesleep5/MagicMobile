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
import io.magicmobile.android.ui.FitText
import io.magicmobile.android.ui.LaunchEnvironment
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.TavernMaterial
import io.magicmobile.android.ui.TavernPalette
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.sf
import io.magicmobile.android.ui.tavernCapsuleRim
import io.magicmobile.android.ui.tavernFill

// The small pieces the friends sheet and public profiles share, in the tavern's leather and brass (SocialComponents.swift).

/** A notice that floats at the bottom: a leather capsule in brass. Tap to dismiss. */
@Composable
fun SocialNotice(text: String, dismiss: () -> Unit, modifier: Modifier = Modifier) {
    Box(modifier.padding(horizontal = 20.dp).padding(bottom = 10.dp).glow(Color.Black.copy(alpha = 0.6f), 8.dp, 22.dp)
        .defaultMinSize(minHeight = 44.dp).tavernCapsuleRim(thin = true).padding(1.5.dp)
        .tavernFill(TavernMaterial.LEATHER, CircleShape, overlay = Color.Black.copy(alpha = 0.25f))
        .clickable(onClick = dismiss).semantics { contentDescription = text }.testTag("friends.notice")
        .padding(horizontal = 18.dp, vertical = 10.dp), contentAlignment = Alignment.Center) {
        Text(text, color = rgb(1.0, 0.91, 0.66), style = sf(13f, SfWeight.heavy, SfDesign.SERIF), textAlign = TextAlign.Center)
    }
}

/** A line of waiting, drawn without a system spinner: three brass pips that breathe in turn. */
@Composable
fun SocialWaiting(text: String) {
    val transition = rememberInfiniteTransition(label = "waiting")
    Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 36.dp).clearAndSetSemantics { contentDescription = text },
        horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            for (index in 0 until 3) {
                val phase by transition.animateFloat(0.35f, 1f, infiniteRepeatable(tween(700 + index * 120), RepeatMode.Reverse), label = "pip$index")
                Box(Modifier.size(7.dp).alpha(if (LaunchEnvironment.reduceMotion) 0.8f else phase).background(TavernPalette.brass, CircleShape))
            }
        }
        Text(text, Modifier.alpha(0.75f), color = TavernPalette.parchment, style = sf(13f, SfWeight.semibold, SfDesign.SERIF))
    }
}

/** A player's name in a list: their commander's art in a brass ring (a dot for who is online), the name, a line under it, their rank. */
@Composable
fun SocialPlayerHeading(username: String, commander: String?, line: String, online: Boolean?, rank: RankPosition?, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().defaultMinSize(minHeight = 56.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(52.dp), contentAlignment = Alignment.Center) {
            CommanderArtMedallion(commander, 40.dp)
            if (online != null) Box(Modifier.align(Alignment.BottomEnd).size(12.dp).background(if (online) rgb(0.4, 0.85, 0.4) else Color.Gray.copy(alpha = 0.6f), CircleShape)
                .border(1.5.dp, Color.Black.copy(alpha = 0.7f), CircleShape))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            FitText(username, sf(16f, SfWeight.heavy, SfDesign.SERIF), color = TavernPalette.parchment, minimumScale = 0.75f)
            Text(line, Modifier.alpha(0.7f), color = TavernPalette.parchment, style = sf(12f, SfWeight.regular, SfDesign.SERIF), maxLines = 1)
        }
        Column(Modifier.width(62.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            if (rank != null) {
                RankEmblem(rank.tier, 34.dp)
                FitText(rank.title, sf(10f, SfWeight.heavy, SfDesign.SERIF), color = TavernPalette.parchment, minimumScale = 0.7f, textAlign = TextAlign.Center)
            } else {
                Box(Modifier.size(34.dp), contentAlignment = Alignment.Center) { SfImage("shield.lefthalf.filled", TavernPalette.brass.copy(alpha = 0.5f), 20.dp) }
                Text("Unranked", Modifier.alpha(0.55f), color = TavernPalette.parchment, style = sf(10f, SfWeight.semibold, SfDesign.SERIF))
            }
        }
    }
}

/** A dark leather row card, for one player or one request in a list. */
@Composable
fun SocialRowCard(content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().background(Color.Black.copy(alpha = 0.32f), RoundedCornerShape(12.dp))
        .border(1.dp, TavernPalette.brass.copy(alpha = 0.4f), RoundedCornerShape(12.dp)).padding(10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) { content() }
}

/** The face of an ember plaque without its own tap (it sits inside a menu button). */
@Composable
fun TavernFacePlaque(title: String, compact: Boolean = true) {
    Row(Modifier.defaultMinSize(minHeight = 44.dp).tavernCapsuleRim().padding(3.dp).tavernFill(TavernMaterial.EMBER, CircleShape)
        .padding(horizontal = if (compact) 16.dp else 22.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
        Text(title, color = rgb(1.0, 0.91, 0.66), style = sf(if (compact) 12f else 14f, SfWeight.heavy, SfDesign.SERIF))
    }
}

/** The result with its relation changed (a request was sent or accepted). */
fun PlayerSearchResult.withRelation(relation: String) = copy(relation = relation, online = if (relation == "friend") online else null)

/** A tappable region that reads as one button. */
fun Modifier.socialButton(label: String, tag: String, onClick: () -> Unit): Modifier =
    this.clickable(onClick = onClick).semantics(mergeDescendants = true) { contentDescription = label; role = Role.Button }.testTag(tag)
