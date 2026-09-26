package io.magicmobile.android.board

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.magicmobile.android.CardArtwork
import io.magicmobile.android.R
import io.magicmobile.android.game.BattlefieldAbilityBadgePlan
import io.magicmobile.android.game.BoardFXLevel
import io.magicmobile.android.game.BoardSize
import io.magicmobile.android.game.CardCounterBadge
import io.magicmobile.android.game.CardPlayAffordance
import io.magicmobile.android.game.CombatKeyword
import io.magicmobile.android.game.CombatKeywordBadgePlan
import io.magicmobile.android.game.combatKeywords
import io.magicmobile.android.game.isInCombat
import io.magicmobile.android.game.NativeCardArtworkPolicy
import io.magicmobile.android.game.TokenCopyFrameLayout
import io.magicmobile.android.game.TokenCopyPresentation
import io.magicmobile.android.game.XmageCardIcon
import io.magicmobile.android.game.ZoneCard
import io.magicmobile.android.game.tokenCopySourceName
import io.magicmobile.android.ui.FitText
import io.magicmobile.android.ui.MagicPalette
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.colorAdjust
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.glowingStroke
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.sf

/**
 * Ports of ContentView.swift's CardTile, CardArtPlaceholder, TokenCopyCardFace, CardCounterBadgeStrip,
 * XmageCardIconStrip, TargetingStatusPill, ManaSymbolView and ArenaBoardPresentation.swift's
 * ArenaBattlefieldCard, BattlefieldAbilityBadges and HandManaCost.
 */
@Composable
fun CardTile(card: ZoneCard, selected: Boolean, modifier: Modifier = Modifier, pending: Boolean = false, legal: Boolean = false,
             castOffered: Boolean = false, targetable: Boolean = false, zoneName: String? = null, width: Dp = 82.dp, height: Dp = 112.dp,
             ignoreTappedRotation: Boolean = false, reduceMotion: Boolean = BoardMotion.reduceMotion) {
    val tapped = card.tapped == true && !ignoreTappedRotation
    val rotation by animateFloatAsState(if (tapped) 90f else 0f,
        if (reduceMotion) tween(0) else spring(dampingRatio = 0.7f, stiffness = 320f), label = "tap")
    val strokeColor = when {
        pending -> MagicPalette.warningAmber
        selected -> MagicPalette.antiqueGold
        targetable -> Color.Red
        legal -> MagicPalette.legalEmerald.copy(alpha = 0.72f)
        castOffered -> Color.White
        else -> Color.Black.copy(alpha = 0.55f)
    }
    val strokeWidth = when { selected || pending || targetable -> 3.dp; legal || castOffered -> 2.2.dp; else -> 1.dp }
    val glowRadius = playableGlowRadius(legal, selected, pending, targetable, width)
    val shadowColor = when {
        pending -> MagicPalette.warningAmber.copy(alpha = 0.75f)
        selected -> MagicPalette.antiqueGold.copy(alpha = 0.55f)
        targetable -> Color.Red.copy(alpha = 0.64f)
        legal -> MagicPalette.legalEmerald.copy(alpha = 0.58f)
        else -> Color.Transparent
    }
    val shadowRadius = if (selected || pending) 11.dp else glowRadius
    val pulse = zoneName == "Hand" && (legal || castOffered) && !selected && !pending && !targetable
    val pulseAlpha = if (pulse && BoardFXSettings.level == BoardFXLevel.FULL && !reduceMotion) {
        val transition = rememberInfiniteTransition(label = "playable")
        transition.animateFloat(0.5f, 1f, infiniteRepeatable(tween(1200), RepeatMode.Reverse), label = "pulse").value
    } else 1f
    Box(modifier
        .requiredSize(width, height)
        .rotate(rotation)
        .glow(shadowColor, shadowRadius, 6.dp)
        .semantics { contentDescription = card.accessibilityLabel(zoneName, selected, legal, pending) }) {
        Box(Modifier.fillMaxSize().clip(RoundedCornerShape(6.dp)).colorAdjust(if (tapped) 0.3f else 1f, if (tapped) -0.12f else 0f)) {
            CardArtworkOrPlaceholder(card, width, height)
        }
        if (!ignoreTappedRotation) {
            XmageCardIconStrip(card.visibleXmageIcons, width, Modifier.align(Alignment.CenterStart).padding(start = 2.dp))
        }
        // A token copy's frame prints its live P/T itself.
        if (!ignoreTappedRotation && card.showsPowerToughness && card.tokenCopySourceName == null) {
            Text("${card.displayPower}/${card.displayToughness}", Modifier.align(Alignment.BottomEnd).padding(3.dp)
                .background(Color.White.copy(alpha = 0.92f), CircleShape).padding(horizontal = 5.dp, vertical = 2.dp),
                color = Color.Black, style = sf(10f, SfWeight.black))
        }
        if (tapped) {
            Box(Modifier.align(Alignment.CenterEnd).padding(3.dp).background(Color.Black.copy(alpha = 0.72f), CircleShape).padding(4.dp)) {
                SfImage("arrow.turn.down.right", Color.White, maxOf(10.dp, width * 0.15f))
            }
        }
        if (!ignoreTappedRotation && card.isCreature && card.summoningSickness == true) {
            val size = maxOf(width * 0.22f, 13.dp)
            Box(Modifier.align(Alignment.CenterEnd).padding(3.dp).size(size).background(MagicPalette.warningAmber.copy(alpha = 0.92f), CircleShape)
                .border(0.7.dp, Color.Black.copy(alpha = 0.32f), CircleShape), contentAlignment = Alignment.Center) {
                SfImage("hourglass", MagicPalette.iron, maxOf(width * 0.105f, 7.dp))
            }
        }
        if (!ignoreTappedRotation && card.counterBadges.isNotEmpty()) {
            CardCounterBadgeStrip(card.counterBadges.take(3), width, Modifier.align(Alignment.BottomStart).padding(3.dp))
        }
        Box(Modifier.fillMaxSize().border(strokeWidth, strokeColor, RoundedCornerShape(6.dp)))
        if (castOffered && !pending) {
            Box(Modifier.align(Alignment.TopStart).padding(3.dp).background(Color.Black.copy(alpha = 0.85f), CircleShape).padding(4.dp)) {
                SfImage("arrow.up", Color.White, 10.dp)
            }
        }
        // Playable and target outlines drawn just outside the card.
        Box(Modifier.fillMaxSize().alpha(pulseAlpha).drawWithContent {
            drawContent()
            val outset = 3.dp.toPx()
            val corner = CornerRadius(8.dp.toPx())
            val topLeft = Offset(-outset, -outset)
            val outer = androidx.compose.ui.geometry.Size(size.width + outset * 2, size.height + outset * 2)
            if (castOffered && legal && !selected && !pending && !targetable) {
                val brush = Brush.horizontalGradient(0f to MagicPalette.legalEmerald, 0.49f to MagicPalette.legalEmerald, 0.51f to Color.White, 1f to Color.White)
                drawRoundRect(brush, topLeft, outer, corner, style = Stroke(3.dp.toPx()))
            } else if (castOffered && !selected && !pending && !targetable) {
                drawRoundRect(Color.White.copy(alpha = 0.98f), Offset(-2.dp.toPx(), -2.dp.toPx()),
                    androidx.compose.ui.geometry.Size(size.width + 4.dp.toPx(), size.height + 4.dp.toPx()), corner, style = Stroke(2.8.dp.toPx()))
            }
            if (legal && !castOffered && !selected && !pending && !targetable) {
                drawRoundRect(MagicPalette.legalEmerald.copy(alpha = 0.92f), topLeft, outer, corner, style = Stroke(maxOf(width.toPx() * 0.030f, 2.1.dp.toPx())))
            }
            if (targetable) drawRoundRect(Color.Red.copy(alpha = 0.94f), topLeft, outer, corner, style = Stroke(2.8.dp.toPx()))
        }.then(
            when {
                castOffered && !selected && !pending && !targetable -> Modifier.glow(Color.White.copy(alpha = 0.6f), 8.dp, 8.dp, 2.dp)
                legal && !castOffered && !selected && !pending && !targetable -> Modifier.glow(MagicPalette.legalEmerald.copy(alpha = 0.6f), glowRadius, 8.dp, 3.dp)
                targetable -> Modifier.glow(Color.Red.copy(alpha = 0.55f), 11.dp, 8.dp, 3.dp)
                else -> Modifier
            }))
    }
}

fun playableGlowRadius(legal: Boolean, selected: Boolean, pending: Boolean, targetable: Boolean, width: Dp): Dp =
    if (legal && !selected && !pending && !targetable) maxOf(width * 0.18f, 10.dp) else 0.dp

fun cardPlayHint(legal: Boolean, castOffered: Boolean): String = when (CardPlayAffordance.of(legal, castOffered)) {
    CardPlayAffordance.LAND_AND_SPELL -> "Land play and spell cast available. Select to choose a face. Hold to inspect."
    CardPlayAffordance.SPELL -> "Spell cast available. Drag upward to start casting. The engine will ask for payment and choices. Hold to inspect."
    else -> "Tap to select. Long press to inspect."
}

/** The consent-aware artwork route (Android's CardArtwork) with the iOS placeholder while art is missing or loading. */
@Composable
fun CardArtworkOrPlaceholder(card: ZoneCard, width: Dp, height: Dp, artOnly: Boolean = false) {
    if (!NativeCardArtworkPolicy.permitsLookup(card)) {
        CardArtPlaceholder(card, width, height)
        return
    }
    val copySource = card.tokenCopySourceName
    if (copySource != null && !artOnly) {
        TokenCopyCardFace(card, copySource, width, height)
        return
    }
    if (BoardArtwork.forcePlaceholders) {
        // iOS previews request no image at all, so their placeholder stays in its loading state.
        CardArtPlaceholder(card, width, height, loading = true)
        return
    }
    val isToken = card.card.isToken == true
    val identity = if (isToken) boardTokenIdentity(card) else null
    CardArtwork(card.card.copySourceArtworkName?.takeIf { isToken } ?: card.card.name, Modifier.fillMaxSize(), token = isToken && card.card.copySourceArtworkName == null,
        tokenIdentity = identity, artOnly = artOnly) {
        CardArtPlaceholder(card, width, height)
    }
}

/**
 * Port of ContentView.swift's TokenCopyCardFace: a token copy drawn as its own card, with the token's
 * live name, type line, rules and P/T around the copied card's illustration and a tag naming the source.
 * The printed source card is never shown, because its name or stats can differ from the token's.
 */
@Composable
fun TokenCopyCardFace(card: ZoneCard, source: String, width: Dp, height: Dp) {
    val frame = TokenCopyFrameLayout(BoardSize(width.value, height.value))
    val rules = card.card.oracleText?.trim().orEmpty()
    val barShape = RoundedCornerShape(3.dp)
    Box(Modifier.requiredSize(width, height)
        .background(Brush.linearGradient(listOf(MagicPalette.parchment, rgb(0.72, 0.59, 0.38), MagicPalette.parchmentShadow)))
        .border(maxOf(width * 0.035f, 1.dp), Brush.linearGradient(listOf(MagicPalette.borderBronze.copy(alpha = 0.70f), MagicPalette.borderIron.copy(alpha = 0.62f))),
            RoundedCornerShape(6.dp))) {
        Box(Modifier.place(frame.nameBar).background(MagicPalette.parchment.copy(alpha = 0.72f), barShape)
            .padding(horizontal = maxOf(width * 0.03f, 2.dp)), contentAlignment = Alignment.CenterStart) {
            FitText(card.card.name, sf(frame.nameFontSize, SfWeight.black, SfDesign.SERIF), color = MagicPalette.iron, minimumScale = 0.5f)
        }
        Box(Modifier.place(frame.art).clip(barShape).border(maxOf(width * 0.006f, 0.5.dp), MagicPalette.iron.copy(alpha = 0.55f), barShape)) {
            val placeholder: @Composable (Boolean) -> Unit = { loading -> TokenCopyArtPlaceholder(width, loading) }
            // The source's illustration only, cropped from the printed card.
            if (BoardArtwork.forcePlaceholders) placeholder(true)
            else CardArtwork(source, Modifier.fillMaxSize(), artOnly = true) { placeholder(false) }
        }
        Box(Modifier.place(frame.typeBar).background(MagicPalette.parchment.copy(alpha = 0.72f), barShape)
            .padding(horizontal = maxOf(width * 0.03f, 2.dp)), contentAlignment = Alignment.CenterStart) {
            FitText(card.card.typeLine.ifEmpty { "Token" }, sf(frame.typeFontSize, SfWeight.bold, SfDesign.SERIF),
                color = MagicPalette.iron.copy(alpha = 0.85f), minimumScale = 0.5f)
        }
        Box(Modifier.place(frame.textBox).background(MagicPalette.parchment.copy(alpha = 0.42f), barShape))
        if (frame.showsRules && rules.isNotEmpty()) {
            GameRulesText(rules, Modifier.place(frame.rulesArea(card.showsPowerToughness)).clipToBounds(), cardName = card.card.name,
                symbolSize = frame.rulesFontSize.dp, style = sf(frame.rulesFontSize, SfWeight.medium, SfDesign.SERIF), color = MagicPalette.iron,
                maxLines = frame.rulesLineLimit(card.showsPowerToughness))
        }
        if (card.showsPowerToughness) {
            val box = frame.powerToughnessBox
            Box(Modifier.place(box).background(MagicPalette.parchment, barShape).border(maxOf(width * 0.01f, 0.8.dp), MagicPalette.borderBronze, barShape),
                contentAlignment = Alignment.Center) {
                FitText("${card.displayPower}/${card.displayToughness}", sf(frame.powerToughnessFontSize, SfWeight.black),
                    color = MagicPalette.iron, minimumScale = 0.5f)
            }
        }
        val slot = frame.tagSlot
        Box(Modifier.place(slot), contentAlignment = Alignment.CenterStart) {
            Box(Modifier.height(slot.height.dp).background(MagicPalette.iron.copy(alpha = 0.88f), CircleShape)
                .border(0.7.dp, MagicPalette.antiqueGold.copy(alpha = 0.6f), CircleShape).padding(horizontal = (slot.height * 0.45f).dp),
                contentAlignment = Alignment.Center) {
                FitText(TokenCopyPresentation.tag(source, width.value), sf(frame.tagFontSize, SfWeight.black, tracking = 0.3f),
                    color = MagicPalette.antiqueGold, minimumScale = 0.6f)
            }
        }
    }
}

@Composable
private fun TokenCopyArtPlaceholder(width: Dp, loading: Boolean) {
    Box(Modifier.fillMaxSize().background(Brush.linearGradient(listOf(MagicPalette.leather.copy(alpha = 0.78f), MagicPalette.moss.copy(alpha = 0.62f),
        MagicPalette.iron.copy(alpha = 0.86f)))), contentAlignment = Alignment.Center) {
        SfImage(if (loading) "hourglass" else "sparkles", MagicPalette.antiqueGold.copy(alpha = if (loading) 0.34f else 0.42f), maxOf(width * 0.18f, 10.dp))
    }
}

/** Tells an inspector that a card view is showing the drawn placeholder (Swift CardArtPlaceholderShownKey). */
val LocalCardArtPlaceholderShown = androidx.compose.runtime.compositionLocalOf<((Boolean) -> Unit)?> { null }

@Composable
fun CardArtPlaceholder(card: ZoneCard, width: Dp, height: Dp, loading: Boolean = false) {
    LocalCardArtPlaceholderShown.current?.let { report ->
        androidx.compose.runtime.DisposableEffect(Unit) { report(true); onDispose { report(false) } }
    }
    Box(Modifier.requiredSize(width, height)
        .background(Brush.linearGradient(listOf(MagicPalette.parchment, rgb(0.72, 0.59, 0.38), MagicPalette.parchmentShadow)))
        .border(maxOf(width * 0.035f, 1.dp), Brush.linearGradient(listOf(MagicPalette.borderBronze.copy(alpha = 0.70f), MagicPalette.borderIron.copy(alpha = 0.62f))),
            RoundedCornerShape(6.dp))) {
        Column(Modifier.fillMaxSize().padding(maxOf(width * 0.07f, 3.5.dp)), verticalArrangement = Arrangement.spacedBy(maxOf(height * 0.025f, 2.dp))) {
            Row(Modifier.fillMaxWidth().background(MagicPalette.parchment.copy(alpha = 0.72f), RoundedCornerShape(3.dp))
                .padding(horizontal = maxOf(width * 0.03f, 2.dp), vertical = maxOf(height * 0.018f, 1.5.dp)),
                horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                FitText(card.card.name, sf(maxOf(width.value * 0.115f, 6f), SfWeight.black, SfDesign.SERIF), Modifier.weight(1f, fill = false),
                    color = MagicPalette.iron, maxLines = 2, minimumScale = 0.58f)
                Spacer(Modifier.width(2.dp))
            }
            Box(Modifier.fillMaxWidth().height(maxOf(height * 0.38f, 22.dp)).clip(RoundedCornerShape(4.dp))
                .background(Brush.linearGradient(listOf(MagicPalette.leather.copy(alpha = 0.78f), MagicPalette.moss.copy(alpha = 0.62f), MagicPalette.iron.copy(alpha = 0.86f)))),
                contentAlignment = Alignment.Center) {
                SfImage(if (loading) "hourglass" else "sparkles", MagicPalette.antiqueGold.copy(alpha = if (loading) 0.34f else 0.42f), maxOf(width * 0.18f, 10.dp))
            }
            Box(Modifier.fillMaxWidth().background(MagicPalette.parchmentShadow.copy(alpha = 0.14f), RoundedCornerShape(3.dp))
                .padding(horizontal = maxOf(width * 0.035f, 2.dp), vertical = maxOf(height * 0.012f, 1.dp))) {
                FitText(card.card.typeLine.ifEmpty { "Card" }, sf(maxOf(width.value * 0.075f, 5f), SfWeight.bold, SfDesign.SERIF),
                    color = MagicPalette.iron.copy(alpha = 0.78f), maxLines = 2, minimumScale = 0.55f)
            }
        }
        if (loading) {
            CircularProgressIndicator(Modifier.align(Alignment.BottomEnd).padding(maxOf(width * 0.07f, 4.dp)).size(12.dp),
                color = MagicPalette.antiqueGold, strokeWidth = 1.5.dp)
        }
    }
}

@Composable
fun CardCounterBadgeStrip(badges: List<CardCounterBadge>, cardWidth: Dp, modifier: Modifier = Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(maxOf(cardWidth * 0.012f, 1.dp))) {
        for (badge in badges) {
            Row(Modifier.glow(Color.Black.copy(alpha = 0.35f), 2.dp, 99.dp).background(counterColor(badge).copy(alpha = 0.90f), CircleShape)
                .border(0.7.dp, Color.Black.copy(alpha = 0.38f), CircleShape)
                .padding(horizontal = maxOf(cardWidth * 0.035f, 2.5.dp), vertical = maxOf(cardWidth * 0.015f, 1.dp)),
                horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(badge.label, color = Color.White, style = sf(maxOf(cardWidth.value * 0.065f, 5.5f), SfWeight.black))
                Text("${badge.count}", color = Color.White, style = sf(maxOf(cardWidth.value * 0.083f, 6.5f), SfWeight.black))
            }
        }
    }
}

private fun counterColor(badge: CardCounterBadge): Color = when (badge.label) {
    "+1/+1" -> MagicPalette.legalEmerald; "-1/-1" -> MagicPalette.oxblood; "LOY" -> MagicPalette.arcaneBlue; "SHD" -> MagicPalette.antiqueGold
    else -> MagicPalette.leather
}

/** Drawable for an XMage ability icon (Swift `XmageCardIcon.assetName`). */
fun xmageIconDrawable(iconType: String): Int? = when (XmageCardIcon.assetName(iconType)) {
    "xmage-icon-playable-count" -> R.drawable.xmage_icon_playable_count
    "xmage-icon-flying" -> R.drawable.xmage_icon_flying
    "xmage-icon-defender" -> R.drawable.xmage_icon_defender
    "xmage-icon-deathtouch" -> R.drawable.xmage_icon_deathtouch
    "xmage-icon-lifelink" -> R.drawable.xmage_icon_lifelink
    "xmage-icon-double-strike" -> R.drawable.xmage_icon_double_strike
    "xmage-icon-first-strike" -> R.drawable.xmage_icon_first_strike
    "xmage-icon-crew" -> R.drawable.xmage_icon_crew
    "xmage-icon-trample" -> R.drawable.xmage_icon_trample
    "xmage-icon-hexproof" -> R.drawable.xmage_icon_hexproof
    "xmage-icon-infect" -> R.drawable.xmage_icon_infect
    "xmage-icon-indestructible" -> R.drawable.xmage_icon_indestructible
    "xmage-icon-vigilance" -> R.drawable.xmage_icon_vigilance
    "xmage-icon-class-level" -> R.drawable.xmage_icon_class_level
    "xmage-icon-reach" -> R.drawable.xmage_icon_reach
    "xmage-icon-facedown" -> R.drawable.xmage_icon_facedown
    "xmage-icon-cost-x" -> R.drawable.xmage_icon_cost_x
    "xmage-icon-restrictions" -> R.drawable.xmage_icon_restrictions
    "xmage-icon-targets" -> R.drawable.xmage_icon_targets
    "xmage-icon-ringbearer" -> R.drawable.xmage_icon_ringbearer
    "xmage-icon-commander" -> R.drawable.xmage_icon_commander
    "xmage-icon-combined" -> R.drawable.xmage_icon_combined
    else -> null
}

@Composable
fun XmageCardIconStrip(icons: List<XmageCardIcon>, cardWidth: Dp, modifier: Modifier = Modifier) {
    val visible = icons.take(5)
    val iconSize = maxOf(cardWidth * 0.18f, 11.dp)
    Column(modifier, verticalArrangement = Arrangement.spacedBy(maxOf(cardWidth * 0.018f, 1.dp))) {
        for (icon in visible) {
            if (icon.textBadge == "Menace") {
                Box(Modifier.size(iconSize + 4.dp).background(MagicPalette.iron.copy(alpha = 0.9f), CircleShape), contentAlignment = Alignment.Center) {
                    SfImage("person.2.fill", MagicPalette.parchment, iconSize * 0.75f, contentDescription = "Menace: requires two or more blockers")
                }
            } else {
                val drawable = xmageIconDrawable(icon.iconType) ?: continue
                Box(Modifier.glow(Color.Black.copy(alpha = 0.35f), 2.dp, 99.dp).background(MagicPalette.iron.copy(alpha = 0.72f), CircleShape)
                    .border(0.7.dp, MagicPalette.antiqueGold.copy(alpha = 0.45f), CircleShape).padding(maxOf(cardWidth * 0.025f, 1.5.dp))) {
                    Image(painterResource(drawable), icon.displayText ?: icon.iconType, Modifier.size(iconSize),
                        colorFilter = ColorFilter.tint(MagicPalette.parchment))
                }
            }
        }
        if (icons.size > visible.size) {
            Box(Modifier.size(iconSize).background(MagicPalette.antiqueGold.copy(alpha = 0.9f), CircleShape), contentAlignment = Alignment.Center) {
                Text("+${icons.size - visible.size}", color = MagicPalette.iron, style = sf(maxOf(cardWidth.value * 0.08f, 6f), SfWeight.black))
            }
        }
    }
}

@Composable
fun TargetingStatusPill(count: Int, modifier: Modifier = Modifier) {
    Row(modifier.glow(MagicPalette.legalEmerald.copy(alpha = 0.24f), 14.dp, 8.dp).background(MagicPalette.iron.copy(alpha = 0.90f), RoundedCornerShape(8.dp))
        .border(1.3.dp, MagicPalette.legalEmerald.copy(alpha = 0.56f), RoundedCornerShape(8.dp)).padding(horizontal = 13.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        SfImage("scope", MagicPalette.parchment, 14.dp)
        Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text("Choose a glowing target", color = MagicPalette.parchment, style = sf(11f, SfWeight.black))
            Text("$count eligible target${if (count == 1) "" else "s"}", Modifier.alpha(0.75f), color = MagicPalette.parchment, style = sf(8f, SfWeight.bold))
        }
    }
}

/** Mana symbol: the bundled WUBRGC drawings, otherwise a lettered disc (Swift ManaSymbolView fallback). */
@Composable
fun ManaSymbolView(symbol: String, size: Dp, modifier: Modifier = Modifier) {
    val drawable = when (symbol) {
        "W" -> R.drawable.mana_w; "U" -> R.drawable.mana_u; "B" -> R.drawable.mana_b; "R" -> R.drawable.mana_r
        "G" -> R.drawable.mana_g; "C" -> R.drawable.mana_c; else -> null
    }
    if (drawable != null) {
        Image(painterResource(drawable), symbol, modifier.size(size))
    } else {
        val background = when (symbol) {
            "W" -> rgb(0.92, 0.86, 0.66); "U" -> rgb(0.32, 0.55, 0.78); "B" -> rgb(0.18, 0.16, 0.15); "R" -> rgb(0.78, 0.25, 0.16)
            "G" -> rgb(0.25, 0.52, 0.25); else -> rgb(0.60, 0.57, 0.50)
        }
        Box(modifier.size(size).background(background, CircleShape).border(1.dp, Color.Black.copy(alpha = 0.45f), CircleShape), contentAlignment = Alignment.Center) {
            Text(symbol, color = if (symbol == "B") Color.White else Color.Black, style = sf(size.value * 0.58f, SfWeight.black))
        }
    }
}

/** Presentation only. Printed costs never substitute for XMage's payment prompt. */
@Composable
fun HandManaCost(cost: String?, modifier: Modifier = Modifier) {
    if (cost.isNullOrEmpty()) return
    Row(modifier.background(Color.Black.copy(alpha = 0.88f), CircleShape).padding(horizontal = 3.dp, vertical = 2.dp),
        horizontalArrangement = Arrangement.spacedBy(1.dp), verticalAlignment = Alignment.CenterVertically) {
        for (symbol in io.magicmobile.android.game.HandManaCostSymbols.symbols(cost)) {
            if (symbol == "//") Text("/", color = Color.White, style = sf(11f, SfWeight.bold)) else ManaSymbolView(symbol, 15.dp)
        }
    }
}

@Composable
private fun BattlefieldAbilityBadges(icons: List<XmageCardIcon>, cardWidth: Dp, modifier: Modifier = Modifier) {
    val plan = BattlefieldAbilityBadgePlan(icons, cardWidth.value)
    val size = BattlefieldAbilityBadgePlan.iconSize(cardWidth.value).dp
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(1.dp)) {
        for (icon in plan.visible) {
            Box(Modifier.size(size + 4.dp).background(MagicPalette.iron.copy(alpha = 0.88f), CircleShape), contentAlignment = Alignment.Center) {
                if (icon.textBadge == "Menace") SfImage("person.2.fill", MagicPalette.parchment, size * 0.72f)
                else xmageIconDrawable(icon.iconType)?.let {
                    Image(painterResource(it), null, Modifier.padding(2.dp).size(size), colorFilter = ColorFilter.tint(MagicPalette.parchment))
                }
            }
        }
        if (plan.hiddenCount > 0) {
            Box(Modifier.size(size + 4.dp).background(MagicPalette.antiqueGold, CircleShape), contentAlignment = Alignment.Center) {
                Text("+${plan.hiddenCount}", color = MagicPalette.iron, style = sf(maxOf(7f, size.value * 0.55f), SfWeight.black))
            }
        }
    }
}

/**
 * Named combat keywords on an attacking or blocking card (CombatKeywordBadgePlan). Strike keywords are
 * filled red and deathtouch violet, the pair that decides most trades (ArenaBoardPresentation.swift).
 */
@Composable
private fun CombatKeywordBadges(plan: CombatKeywordBadgePlan, cardWidth: Dp, modifier: Modifier = Modifier) {
    val size = CombatKeywordBadgePlan.fontSize(cardWidth.value)
    @Composable
    fun badge(text: String, fill: Color, textColor: Color) {
        Box(Modifier.height((size + 5).dp).shadow(1.5.dp, CircleShape).background(fill, CircleShape)
            .border(0.5.dp, Color.Black.copy(alpha = 0.5f), CircleShape).padding(horizontal = 3.5.dp), contentAlignment = Alignment.Center) {
            FitText(text, sf(size, SfWeight.black), color = textColor, minimumScale = 0.6f)
        }
    }
    // Keywords that do not fit keep their icon in the card's ability row.
    Column(modifier.widthIn(max = cardWidth - 4.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        for (keyword in plan.visible) {
            val (fill, text) = combatKeywordStyle(keyword)
            badge(plan.label(keyword).uppercase(), fill, text)
        }
    }
}

private fun combatKeywordStyle(keyword: CombatKeyword): Pair<Color, Color> = when (keyword) {
    CombatKeyword.DOUBLE_STRIKE, CombatKeyword.FIRST_STRIKE -> rgb(0.86, 0.28, 0.12) to Color.White
    CombatKeyword.DEATHTOUCH -> rgb(0.24, 0.1, 0.3) to rgb(0.86, 0.7, 1.0)
    else -> Color.Black.copy(alpha = 0.8f) to MagicPalette.parchment
}

/** Compact public permanent face; the complete printed card remains in inspection. */
@Composable
fun ArenaBattlefieldCard(card: ZoneCard, zoneName: String, width: Dp, height: Dp, modifier: Modifier = Modifier, selected: Boolean = false,
                         legal: Boolean = false, targetable: Boolean = false, reduceMotion: Boolean = BoardMotion.reduceMotion) {
    val accent = when {
        card.isPhasedOut -> Color.Gray; targetable -> Color.Red; selected -> MagicPalette.antiqueGold; legal -> MagicPalette.legalEmerald
        else -> Color.White.copy(alpha = 0.35f)
    }
    val isLegendary = card.card.typeLine.contains("legendary", ignoreCase = true)
    val showsFooter = card.showsPowerToughness || (card.isCreature && card.summoningSickness == true)
    val tapped = card.tapped == true
    // Labeled combat keywords while the card attacks or blocks, gained ones included.
    val combatPlan = if (card.isInCombat && !card.isPhasedOut) CombatKeywordBadgePlan(card.combatKeywords, width.value, height.value)
        .takeIf { it.visible.isNotEmpty() } else null
    // The icon row leaves out keywords the combat badges already name.
    val abilityIcons = if (combatPlan == null) card.visibleXmageIcons else {
        val named = combatPlan.visible.map { it.iconType }.toMutableSet()
        if (CombatKeyword.DOUBLE_STRIKE in combatPlan.visible) named += CombatKeyword.FIRST_STRIKE.iconType
        card.visibleXmageIcons.filter { it.iconType.uppercase() !in named }
    }
    val rotation by animateFloatAsState(if (tapped) -7f else 0f, if (reduceMotion) tween(0) else tween(220), label = "tapTilt")
    val phasedAlpha by animateFloatAsState(if (card.isPhasedOut) 0.42f else 1f, if (reduceMotion) tween(0) else tween(200), label = "phase")
    val shape = RoundedCornerShape(7.dp)
    Box(modifier.requiredSize(width, height)
        .rotate(rotation)
        .glow(accent.copy(alpha = if (legal || targetable) 0.45f else 0.1f), 5.dp, 7.dp)
        .alpha(phasedAlpha)
        .semantics { contentDescription = card.accessibilityLabel(zoneName, selected, legal) + card.visibleXmageIcons.filter { it.displayText == null }
            .joinToString("") { ", " + BattlefieldAbilityBadgePlan.accessibleName(it) } }) {
        Column(Modifier.fillMaxSize().clip(shape).background(rgb(0.07, 0.08, 0.10)).colorAdjust(if (tapped) 0.15f else 1f, if (tapped) -0.16f else 0f)) {
            Box(Modifier.fillMaxWidth().height(15.dp).padding(horizontal = 3.dp), contentAlignment = Alignment.CenterStart) {
                FitText(card.card.name, sf(maxOf(8f, width.value * 0.115f), SfWeight.semibold, SfDesign.SERIF), color = Color.White, minimumScale = 0.62f)
            }
            Box(Modifier.width(width).height(maxOf(12.dp, height - 15.dp - if (showsFooter) 20.dp else 0.dp)).clipToBounds(), contentAlignment = Alignment.TopCenter) {
                // Pinned to the top like SwiftUI's `.frame(alignment: .top)`; Compose would otherwise center the overflow.
                Box(Modifier.wrapContentSize(Alignment.TopCenter, unbounded = true).offset(y = -(width * 0.19f)).requiredSize(width * 1.08f, width * 1.51f)) {
                    CardTile(card, selected = false, zoneName = zoneName, width = width * 1.08f, height = width * 1.51f, ignoreTappedRotation = true)
                }
            }
            if (showsFooter) {
                Row(Modifier.fillMaxWidth().height(20.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (card.isCreature && card.summoningSickness == true) SfImage("hourglass", MagicPalette.warningAmber, 12.dp)
                    Spacer(Modifier.weight(1f))
                    if (card.showsPowerToughness) {
                        Text("${card.displayPower}/${card.displayToughness}", color = Color.White,
                            style = sf(maxOf(11f, width.value * 0.17f), SfWeight.black, SfDesign.ROUNDED))
                    }
                }
            }
        }
        BattlefieldAbilityBadges(abilityIcons, width, Modifier.align(Alignment.BottomStart).padding(start = 2.dp, bottom = if (showsFooter) 22.dp else 2.dp))
        combatPlan?.let { CombatKeywordBadges(it, width, Modifier.align(Alignment.TopStart).padding(start = 2.dp, top = 17.dp)) }
        if (card.counterBadges.isNotEmpty()) {
            CardCounterBadgeStrip(card.counterBadges.take(2), width, Modifier.align(Alignment.TopEnd).padding(top = 16.dp))
        }
        if (tapped) {
            val size = maxOf(15.dp, width * 0.24f)
            Box(Modifier.align(Alignment.BottomEnd).padding(end = 3.dp, bottom = if (showsFooter) 23.dp else 3.dp).size(size)
                .background(Color.Black.copy(alpha = 0.78f), CircleShape).border(1.dp, MagicPalette.antiqueGold.copy(alpha = 0.7f), CircleShape),
                contentAlignment = Alignment.Center) {
                SfImage("arrow.turn.down.right", MagicPalette.parchment, maxOf(8.dp, width * 0.12f))
            }
        }
        Box(Modifier.fillMaxSize().border(if (legal || targetable || selected) 2.dp else 1.dp, accent, shape))
        if (isLegendary && !(legal || targetable || selected) && !card.isPhasedOut) {
            // Legendary permanents wear a gold edge unless a play/target state owns the border.
            Box(Modifier.fillMaxSize().glowingStroke(Color.Transparent, 0.dp, MagicPalette.antiqueGold.copy(alpha = 0.45f), 4.dp, 7.dp)
                .border(2.dp, Brush.sweepGradient(listOf(MagicPalette.antiqueGold, rgb(1.0, 0.93, 0.62), rgb(0.62, 0.44, 0.14), MagicPalette.antiqueGold)), shape))
        }
        if (card.isPhasedOut) {
            Text("Phased out", Modifier.align(Alignment.Center).graphicsLayer { alpha = 1f / phasedAlpha.coerceAtLeast(0.1f) }
                .background(Color.Black.copy(alpha = 0.88f), CircleShape).padding(3.dp), color = Color.White, style = sf(10f, SfWeight.bold))
        }
    }
}
