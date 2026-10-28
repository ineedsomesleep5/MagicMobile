package io.magicmobile.android.ui

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.background
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import io.magicmobile.android.game.GuidedGameText
import io.magicmobile.android.game.GuidedGameTip

/**
 * The guided game's note (iOS GuidedGameCoachCard): a leather slip in brass trim at the top of the
 * table, with the moment's title, a sentence or two, Got it and Turn off tips. The rest of the table
 * stays live under it.
 */
@Composable
fun GuidedGameCoachCard(tip: GuidedGameTip, dismiss: () -> Unit, turnOff: () -> Unit, modifier: Modifier = Modifier) {
    Column(modifier.padding(horizontal = 16.dp).widthIn(max = 420.dp).fillMaxWidth()
        .glow(Color.Black.copy(alpha = 0.55f), 10.dp, 12.dp)
        .tavernPanelChrome(tavern = true, cornerRadius = 12.dp)
        .testTag("guided.tip.${tip.id}")
        .padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            TavernTag("GUIDE", accent = TavernPalette.ember)
            TavernPanelTitle(GuidedGameText.title(tip), Modifier.semantics { heading() })
        }
        Text(GuidedGameText.body(tip), Modifier.testTag("guided.tip.body"), color = TavernPalette.parchment,
            style = sf(14f, SfWeight.medium, SfDesign.SERIF))
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            TavernPlaqueButton(GuidedGameText.TURN_OFF, turnOff, Modifier.testTag("guided.turnOff"), TavernButtonKind.SECONDARY)
            Spacer(Modifier.weight(1f))
            TavernPlaqueButton(GuidedGameText.GOT_IT, dismiss, Modifier.testTag("guided.gotIt"))
        }
    }
}

/** The first launch's welcome (iOS GuidedGameWelcomeView): a guided game, the How to Play slideshow, or straight to the menu. */
@Composable
fun GuidedGameWelcomeView(playGuided: () -> Unit, readHowToPlay: () -> Unit, skip: () -> Unit, modifier: Modifier = Modifier) {
    CompositionLocalProvider(LocalTavernBoard provides true) {
        Box(modifier, contentAlignment = Alignment.TopCenter) {
            Column(Modifier.verticalScroll(rememberScrollState()).padding(24.dp).widthIn(max = 460.dp).fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp)) {
                // Dark glass in the gold hairline, as the Arena menus draw it (it was a leather coin).
                Box(Modifier.size(60.dp).background(Color.Black.copy(alpha = 0.55f), CircleShape).border(1.dp, io.magicmobile.android.menus.ArenaGlass.hairline, CircleShape),
                    contentAlignment = Alignment.Center) {
                    SfImage("graduationcap.fill", TavernPalette.brass, 26.dp)
                }
                TavernPanelTitle(GuidedGameText.WELCOME_TITLE, Modifier.semantics { heading() })
                Text(GuidedGameText.WELCOME_BODY, color = TavernPalette.parchment, textAlign = TextAlign.Center,
                    style = sf(16f, SfWeight.medium, SfDesign.SERIF))
                Column(Modifier.fillMaxWidth().padding(top = 6.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    TavernPlaqueButton(io.magicmobile.android.game.LessonText.START, playGuided, Modifier.testTag("guided.welcome.play"), compact = false, fullWidth = true)
                    TavernPlaqueButton(GuidedGameText.READ_HOW_TO_PLAY, readHowToPlay, Modifier.testTag("guided.welcome.howToPlay"),
                        TavernButtonKind.SECONDARY, compact = false, fullWidth = true)
                    TavernPlaqueButton(GuidedGameText.SKIP, skip, Modifier.testTag("guided.welcome.skip"),
                        TavernButtonKind.SECONDARY, compact = false, fullWidth = true)
                }
            }
        }
    }
}
