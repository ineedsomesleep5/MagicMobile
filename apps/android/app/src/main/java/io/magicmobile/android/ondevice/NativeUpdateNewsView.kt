package io.magicmobile.android.ondevice

import android.content.Intent
import android.net.Uri
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import io.magicmobile.android.BuildConfig
import io.magicmobile.android.CardArtwork
import io.magicmobile.android.game.UpdateNews
import io.magicmobile.android.game.UpdateNewsMessage
import io.magicmobile.android.menus.ArenaCaps
import io.magicmobile.android.menus.ArenaColorGlass
import io.magicmobile.android.menus.ArenaGlass
import io.magicmobile.android.menus.ArenaMenuStyle
import io.magicmobile.android.menus.ArenaPanelHeader
import io.magicmobile.android.menus.arenaScrollFade
import io.magicmobile.android.ui.BoardMotionFlags
import io.magicmobile.android.ui.BrandPressable
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight

/*
 * Port of NativeUpdateNewsView.swift: Arena's inbox (inbox-1), a blade on the right over the dimmed menu with one column of
 * messages, each a ◆, its title and its date, the newest tagged New in orange; a tap opens the message in place (its art as a
 * banner, then what it brought). The build, XMage news and the links sit in the last message, About & links. Bundled release
 * notes stay readable offline; upstream links never imply installed support.
 */

@Composable
fun NativeUpdateNewsView(upstreamCommit: String?) {
    var expanded by rememberSaveable { mutableStateOf<String?>(null) }
    Column(Modifier.fillMaxWidth()) {
        ArenaPanelHeader("Inbox", closeIdentifier = "updates.close")
        Column(Modifier.fillMaxWidth().arenaScrollFade().verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            ArenaCaps("What's new", 9.5f, Modifier.padding(horizontal = 14.dp).padding(top = 10.dp, bottom = 6.dp))
            UpdateNews.messages.forEachIndexed { index, message ->
                InboxRow(message.id, message.title, message.date, UpdateNews.isNew(index), expanded, { expanded = it }) { ArenaInboxMessage(message) }
            }
            InboxRow(UpdateNews.ABOUT_ID, "About & links", null, false, expanded, { expanded = it }) {
                Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    InstalledBuild(upstreamCommit)
                    LinkSections()
                }
            }
        }
    }
}

/** One message: a ◆ (lit gold while it is the newest), New in orange over its title, its date, and the message under it once tapped. */
@Composable
private fun InboxRow(id: String, title: String, date: String?, new: Boolean, expanded: String?, setExpanded: (String?) -> Unit,
                     content: @Composable ColumnScope.() -> Unit) {
    val open = expanded == id
    val reduce = BoardMotionFlags.reduceMotion
    Column(Modifier.fillMaxWidth()) {
        BrandPressable({ GameAudio.play(if (open) GameSound.UI_BACK else GameSound.UI_OPEN); setExpanded(UpdateNews.toggle(expanded, id)) },
            Modifier.fillMaxWidth().testTag("updates.inbox.$id").semantics(mergeDescendants = true) {
                selected = open; role = Role.Button
                onClick(if (open) "Closes the message" else "Opens the message") { setExpanded(UpdateNews.toggle(expanded, id)); true }
            }) {
            Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 52.dp).background(if (open) Color.White.copy(alpha = 0.06f) else Color.Transparent)
                .padding(horizontal = 14.dp, vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.width(16.dp), contentAlignment = Alignment.Center) {
                    Box(Modifier.size(9.dp).rotate(45f)
                        .then(if (new) Modifier.background(ArenaMenuStyle.goldFill) else Modifier)
                        .border(1.3.dp, if (new) ArenaMenuStyle.gold else ArenaMenuStyle.text.copy(alpha = 0.55f)))
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                    if (new) Text("New", color = ArenaMenuStyle.ember, style = ArenaMenuStyle.font(11f, SfWeight.bold))
                    Text(title, color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(14.5f, if (new || open) SfWeight.bold else SfWeight.semibold))
                    date?.let { Text(it, color = if (new) ArenaMenuStyle.ember else ArenaMenuStyle.dim, style = ArenaMenuStyle.font(11f, SfWeight.semibold)) }
                }
            }
        }
        AnimatedVisibility(open, enter = fadeIn(tween(if (reduce) 0 else 220)), exit = fadeOut(tween(if (reduce) 0 else 160))) {
            Column(Modifier.fillMaxWidth().padding(horizontal = 14.dp).padding(top = 4.dp, bottom = 16.dp), content = content)
        }
        Box(Modifier.fillMaxWidth().height(1.dp).alpha(0.35f).background(ArenaGlass.hairline))
    }
}

/** An open message, under its row: its art as a banner the width of the row, then all it brought. */
@Composable
private fun ArenaInboxMessage(message: UpdateNewsMessage) {
    Column(Modifier.fillMaxWidth().testTag("updates.message.${message.id}"), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        val shape = RoundedCornerShape(10.dp)
        Box(Modifier.fillMaxWidth().height(110.dp).clip(shape).border(0.9.dp, ArenaGlass.hairlineTop.copy(alpha = 0.6f), shape).clearAndSetSemantics { }) {
            CardArtwork(message.art, Modifier.fillMaxSize(), artOnly = true) { ArenaColorGlass(message.colors, Modifier.fillMaxSize()) }
        }
        Text(message.lede, color = ArenaMenuStyle.text.copy(alpha = 0.9f), style = ArenaMenuStyle.font(13.5f, SfWeight.medium))
        message.notes.forEach { note ->
            Text(note, Modifier.padding(top = 2.dp), color = ArenaMenuStyle.text.copy(alpha = 0.8f), style = ArenaMenuStyle.font(13f, SfWeight.medium))
        }
    }
}

@Composable
private fun InstalledBuild(upstreamCommit: String?) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            ArenaCaps("Installed build")
            Spacer(Modifier.weight(1f).width(8.dp))
            Text("MagicMobile ${BuildConfig.VERSION_NAME} (${BuildConfig.RELEASE_BUILD})", color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(13f, SfWeight.semibold))
        }
        // The engine's revision, which Android showed before; iOS keeps it on Options' About page.
        upstreamCommit?.let {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                ArenaCaps("XMage revision")
                Spacer(Modifier.weight(1f).width(8.dp))
                Text(it.take(12), color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(13f, SfWeight.semibold).copy(fontFeatureSettings = "tnum"))
            }
        }
    }
}

@Composable
private fun LinkSections() {
    val context = LocalContext.current
    fun open(url: String) { runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) } }
    ArenaNewsSection("XMage news", "Opens GitHub. Upstream changes are not installed automatically. New cards and abilities become available only after a compatible MagicMobile build is tested and released.") {
        NewsLink("XMage release notes") { open("https://github.com/magefree/mage/releases") }
        NewsLink("Latest upstream changes") { open("https://github.com/magefree/mage/commits/master/") }
    }
    ArenaNewsSection("About", "Independent fan project. Not affiliated with Wizards of the Coast. Magic: The Gathering and card artwork belong to their respective owners.",
        "updates.fanContentNotice") {
        Text("Card images from Scryfall", Modifier.padding(vertical = 8.dp), color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(14f, SfWeight.medium))
        NewsLink("Privacy", "updates.privacy") { open("https://magicmobile-downloads.vercel.app/privacy/") }
    }
    ArenaNewsSection("Support MagicMobile", SupportProject.NOTE) {
        NewsLink(SupportProject.ACTION, "updates.support") { open(SupportProject.URL) }
    }
}

/** A section of the news: gold capitals over its rows on a lighter pane in the hairline, and a line under it. */
@Composable
private fun ArenaNewsSection(title: String, footer: String? = null, footerIdentifier: String? = null, content: @Composable ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(12.dp)
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        ArenaCaps(title)
        Column(Modifier.fillMaxWidth().background(Color.White.copy(alpha = 0.045f), shape).border(0.8.dp, ArenaGlass.hairlineTop.copy(alpha = 0.47f), shape)
            .padding(horizontal = 12.dp), content = content)
        footer?.let {
            Text(it, (if (footerIdentifier != null) Modifier.testTag(footerIdentifier) else Modifier), color = ArenaMenuStyle.dim,
                style = ArenaMenuStyle.font(11.5f, SfWeight.medium))
        }
    }
}

/** A link in the news: the words, and its arrow in gold at the end of the line. */
@Composable
private fun NewsLink(title: String, identifier: String? = null, action: () -> Unit) {
    BrandPressable(action, Modifier.fillMaxWidth().then(if (identifier != null) Modifier.testTag(identifier) else Modifier)
        .semantics(mergeDescendants = true) { contentDescription = title; role = Role.Button }) {
        Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).padding(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Text(title, Modifier.weight(1f), color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(14f, SfWeight.medium))
            SfImage("arrow.up.right", ArenaMenuStyle.gold, 12.dp)
        }
    }
}
