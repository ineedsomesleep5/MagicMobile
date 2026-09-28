package io.magicmobile.android.board

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import io.magicmobile.android.game.GameSnapshot
import io.magicmobile.android.game.TableChatFilter
import io.magicmobile.android.game.TableChatText
import io.magicmobile.android.ui.AppPreferences
import io.magicmobile.android.ui.IosSheetHeader
import io.magicmobile.android.ui.IosToggle
import io.magicmobile.android.ui.MagicPalette
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.sf

/** TableChatButton (GameEmotes.swift): opens the table's chat, with an unread badge. Tables with other people only. */
@Composable
fun TableChatButton(center: EmoteCenter) {
    if (!center.canChat) return
    Box(Modifier.defaultMinSize(44.dp, 44.dp).clickable { center.openChat(true) }
        .semantics { contentDescription = if (center.unread > 0) "Chat, ${center.unread} unread" else "Chat" },
        contentAlignment = Alignment.Center) {
        SfImage("bubble.left.and.bubble.right.fill", MagicPalette.parchment.copy(alpha = 0.9f), 15.dp)
        if (center.unread > 0) {
            Box(Modifier.align(Alignment.TopEnd).offset(x = 2.dp, y = 2.dp).defaultMinSize(18.dp, 18.dp)
                .background(MagicPalette.oxblood, CircleShape).border(1.dp, Color.Black.copy(alpha = 0.6f), CircleShape)
                .padding(horizontal = 5.dp), contentAlignment = Alignment.Center) {
                Text(if (center.unread > 99) "99+" else "${center.unread}", color = Color.White, style = sf(10f, SfWeight.black))
            }
        }
    }
}

/** TableChatPanel (GameEmotes.swift): typed messages and quick chat, newest at the bottom. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun TableChatPanel(center: EmoteCenter, snapshot: GameSnapshot?, report: ((EmoteCenter.ChatLine) -> Unit)?, block: ((String) -> Unit)? = null,
                   done: () -> Unit) {
    var filterLanguage by AppPreferences.boolean("magicmobile.chat.filterLanguage", true)
    var draft by remember { mutableStateOf("") }
    var actionsFor by remember { mutableStateOf<EmoteCenter.ChatLine?>(null) }
    var reported by remember { mutableStateOf(setOf<String>()) }
    var showOptions by remember { mutableStateOf(false) }
    val listState = rememberLazyListState()
    DisposableEffect(Unit) { center.openChat(true); onDispose { center.openChat(false) } }
    LaunchedEffect(center.lines.size) { if (center.lines.isNotEmpty()) listState.animateScrollToItem(center.lines.size - 1) }
    fun send() { if (center.sayText(draft)) draft = "" }

    Column(Modifier.fillMaxWidth().imePadding()) {
        IosSheetHeader("Table chat", done, leading = {
            Box(Modifier.defaultMinSize(44.dp, 44.dp).clickable { showOptions = true }.semantics { contentDescription = "Chat options" },
                contentAlignment = Alignment.Center) { SfImage("ellipsis.circle", MagicPalette.parchment, 18.dp) }
        })
        LazyColumn(Modifier.fillMaxWidth().heightIn(min = 160.dp, max = 380.dp), state = listState,
            verticalArrangement = Arrangement.spacedBy(10.dp), contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp)) {
            if (center.lines.isEmpty()) item {
                Text("Say hi to the table. Messages last for this game only.", Modifier.fillMaxWidth().padding(top = 24.dp),
                    color = Color.White.copy(alpha = 0.55f), style = sf(15f))
            }
            items(center.lines, key = { it.id }) { line ->
                Column(Modifier.fillMaxWidth().combinedClickable(onClick = {}, onLongClick = { if (!line.isLocal) actionsFor = line }),
                    horizontalAlignment = if (line.isLocal) Alignment.End else Alignment.Start, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(line.name, color = Color.White.copy(alpha = 0.55f), style = sf(12f, SfWeight.semibold))
                    Row(Modifier.background(if (line.isLocal) MagicPalette.antiqueGold.copy(alpha = 0.28f) else Color.White.copy(alpha = 0.08f),
                        RoundedCornerShape(14.dp)).padding(horizontal = 12.dp, vertical = 8.dp),
                        horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        line.emote?.let { SfImage(it.symbol, MagicPalette.antiqueGold, 13.dp) }
                        Text(if (filterLanguage && !line.isLocal) TableChatFilter.filtered(line.text) else line.text, color = Color.White, style = sf(16f))
                    }
                    if (line.id in reported) Text("Reported", color = Color.White.copy(alpha = 0.55f), style = sf(11f))
                }
            }
        }
        if (snapshot != null) {
            Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                GameEmote.entries.forEach { emote ->
                    Row(Modifier.defaultMinSize(minHeight = 36.dp).background(Color.White.copy(alpha = if (center.canSend) 0.1f else 0.04f), RoundedCornerShape(10.dp))
                        .clickable(enabled = center.canSend) { center.say(emote, snapshot) }.padding(horizontal = 10.dp),
                        horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        SfImage(emote.symbol, MagicPalette.antiqueGold, 12.dp)
                        Text(emote.text, color = Color.White, style = sf(13f, SfWeight.heavy))
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 8.dp, bottom = 12.dp, top = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(draft, { draft = it }, Modifier.weight(1f).semantics { contentDescription = "chat.field" },
                placeholder = { Text("Message") }, maxLines = 3, textStyle = sf(16f),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send), keyboardActions = KeyboardActions(onSend = { send() }),
                colors = OutlinedTextFieldDefaults.colors(focusedTextColor = Color.White, unfocusedTextColor = Color.White))
            val canSend = TableChatText.sanitize(draft) != null
            Box(Modifier.size(44.dp).clickable(enabled = canSend) { send() }.semantics { contentDescription = "Send" }, contentAlignment = Alignment.Center) {
                SfImage("paperplane.fill", if (canSend) MagicPalette.antiqueGold else Color.White.copy(alpha = 0.3f), 18.dp)
            }
        }
    }

    actionsFor?.let { line ->
        val actions = buildList {
            add(ConfirmationAction("Mute ${line.name}") { center.mute(line.name) })
            if (block != null) add(ConfirmationAction("Block ${line.name}") { block(line.name) })
            if (report != null && line.id !in reported) add(ConfirmationAction("Report message", destructive = true) { report(line); reported = reported + line.id })
        }
        ConfirmationDialog(line.name, TableChatFilter.filtered(line.text), actions) { actionsFor = null }
    }
    if (showOptions) {
        BoardSheet({ showOptions = false }) {
            Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                IosToggle(filterLanguage, { filterLanguage = it }) { Text("Filter language", color = Color.White, style = sf(17f)) }
                center.muted.toList().forEach { name ->
                    Text("Unmute $name", Modifier.fillMaxWidth().clickable { center.unmute(name) }.padding(vertical = 8.dp),
                        color = MagicPalette.antiqueGold, style = sf(17f))
                }
            }
        }
    }
}
