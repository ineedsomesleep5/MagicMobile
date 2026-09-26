package io.magicmobile.android.ondevice

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import io.magicmobile.android.game.GameResumeText
import io.magicmobile.android.ui.BrandButton
import io.magicmobile.android.ui.BrandButtonKind
import io.magicmobile.android.ui.BrandButtonText
import io.magicmobile.android.ui.BrandDivider
import io.magicmobile.android.ui.BrandTheme
import io.magicmobile.android.ui.BrandTitle
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfText
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.brandPanel
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.sf
import kotlinx.coroutines.delay

/**
 * "Resume your game?" over the main menu, in the menu brand (charcoal, ember, cream). The player
 * must choose: there is no automatic resume and no dismissal by tapping outside.
 */
@Composable
fun ResumeGamePrompt(detail: String, enabled: Boolean, resume: () -> Unit, abandon: () -> Unit) {
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.62f))
        .clickable(remember { MutableInteractionSource() }, null) {}
        .windowInsetsPadding(WindowInsets.safeDrawing).padding(16.dp), contentAlignment = Alignment.Center) {
        Column(Modifier.widthIn(max = 400.dp).fillMaxWidth().brandPanel(22.dp).semantics { paneTitle = GameResumeText.PROMPT_TITLE },
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
            BrandDivider(Modifier.fillMaxWidth())
            BrandTitle(GameResumeText.PROMPT_TITLE, 28f, textAlign = TextAlign.Center)
            Text(detail, color = BrandTheme.inkSecondary, style = SfText.subheadline(), textAlign = TextAlign.Center)
            Column(Modifier.fillMaxWidth().padding(top = 6.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                BrandButton(resume, Modifier.semantics { contentDescription = GameResumeText.RESUME }, enabled = enabled) {
                    BrandButtonText(GameResumeText.RESUME)
                }
                BrandButton(abandon, Modifier.semantics { contentDescription = GameResumeText.ABANDON }, kind = BrandButtonKind.SECONDARY, enabled = enabled) {
                    Text(GameResumeText.ABANDON, color = rgb(1.0, 0.27, 0.23), style = sf(17f, SfWeight.bold))
                }
            }
        }
    }
}

/** A one-time save/resume notice at the top of the screen; it dismisses itself after 6 s, or with its close button. */
@Composable
fun ResumeNoticeBanner(message: String, modifier: Modifier = Modifier, dismiss: () -> Unit) {
    LaunchedEffect(message) { delay(GameResumeText.NOTICE_MILLIS); dismiss() }
    Box(modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.safeDrawing).padding(horizontal = 16.dp, vertical = 8.dp),
        contentAlignment = Alignment.TopCenter) {
        Row(Modifier.widthIn(max = 480.dp).brandPanel(12.dp).semantics { liveRegion = LiveRegionMode.Polite },
            horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(message, Modifier.weight(1f, fill = false), color = BrandTheme.ink, style = SfText.callout(SfWeight.semibold))
            Box(Modifier.size(44.dp).clickable(onClick = dismiss).semantics { contentDescription = GameResumeText.DISMISS },
                contentAlignment = Alignment.Center) { SfImage("xmark", BrandTheme.inkSecondary, 12.dp) }
        }
    }
}
