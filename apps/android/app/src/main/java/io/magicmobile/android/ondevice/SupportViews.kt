package io.magicmobile.android.ondevice

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import io.magicmobile.android.board.tavernSettingsPanel
import io.magicmobile.android.ui.AppPreferences
import io.magicmobile.android.ui.FitText
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.TavernButton
import io.magicmobile.android.ui.TavernButtonKind
import io.magicmobile.android.ui.TavernButtonText
import io.magicmobile.android.ui.TavernPalette
import io.magicmobile.android.ui.TavernPanelTitle
import io.magicmobile.android.ui.sf

/**
 * The tip jar (SupportProject in NativeUpdateNewsView.swift). Every support link opens the download site's support
 * page in the browser, never an in-app purchase or a payment page. That page (apps/site/public/support) holds the
 * donation link, so changing the provider never needs an app update.
 */
object SupportProject {
    const val URL = "https://magicmobile-downloads.vercel.app/support/"
    const val DISMISSED_KEY = "magicmobile.supportBanner.dismissed"
    const val PITCH = "Enjoying MagicMobile? Help cover server costs."
    const val ACTION = "Help cover server costs"
    const val NOTE = "MagicMobile is free with no ads. Tips help pay for the servers and open in your browser. Unofficial fan app, not affiliated with Wizards of the Coast."
}

@Composable
private fun openSupport(): () -> Unit {
    val context = LocalContext.current
    return { runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(SupportProject.URL))) } }
}

/** SupportSettingsPanel: the always-on support panel at the foot of Settings. */
@Composable
fun SupportSettingsPanel() {
    val open = openSupport()
    // Options' Support page (NativeUpdateNewsView.swift SupportSettingsPanel): gold capitals, the note, a lit pill.
    if (io.magicmobile.android.menus.LocalArenaBoard.current) {
        Column(Modifier.tavernSettingsPanel(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            io.magicmobile.android.menus.ArenaCaps("Support MagicMobile")
            Text(SupportProject.NOTE, color = io.magicmobile.android.menus.ArenaMenuStyle.dim,
                style = io.magicmobile.android.menus.ArenaMenuStyle.font(12f, SfWeight.medium))
            io.magicmobile.android.menus.ArenaPillButton(SupportProject.ACTION, open, lit = true, identifier = "settings.support", symbol = "heart.fill")
        }
        return
    }
    Column(Modifier.tavernSettingsPanel(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        TavernPanelTitle("Support MagicMobile")
        Text(SupportProject.NOTE, color = TavernPalette.parchment.copy(alpha = 0.65f), style = sf(12f, design = SfDesign.SERIF))
        TavernButton(open, Modifier.testTag("settings.support"), kind = TavernButtonKind.SECONDARY, compact = true, fullWidth = true) {
            SfImage("heart.fill", TavernPalette.ember, 13.dp)
            TavernButtonText(SupportProject.ACTION)
        }
    }
}
