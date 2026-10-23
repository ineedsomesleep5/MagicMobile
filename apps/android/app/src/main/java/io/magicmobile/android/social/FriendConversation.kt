package io.magicmobile.android.social

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import io.magicmobile.android.game.FriendMessage
import io.magicmobile.android.game.FriendMessageRules
import io.magicmobile.android.game.MessageConversation
import io.magicmobile.android.game.PlayerAccountRules
import io.magicmobile.android.ranked.ProfileEmptyNote
import io.magicmobile.android.ranked.ProfileSectionTitle
import io.magicmobile.android.ranked.PublicProfileScreen
import io.magicmobile.android.ranked.SocialNotice
import io.magicmobile.android.ranked.SocialPlayerHeading
import io.magicmobile.android.ranked.SocialRowCard
import io.magicmobile.android.ranked.SocialWaiting
import io.magicmobile.android.ranked.TavernScreenHeader
import io.magicmobile.android.ranked.leatherCard
import io.magicmobile.android.ranked.ArenaConfirmation
import io.magicmobile.android.menus.ArenaButton
import io.magicmobile.android.menus.ArenaButtonKind
import io.magicmobile.android.menus.ArenaButtonText
import io.magicmobile.android.menus.ArenaCaps
import io.magicmobile.android.menus.ArenaGlass
import io.magicmobile.android.menus.ArenaMenuStyle
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.draw.drawBehind
import io.magicmobile.android.ranked.socialButton
import io.magicmobile.android.ui.BrandBackdrop
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.TavernConfirmationDialog
import io.magicmobile.android.ui.TavernDialogAction
import io.magicmobile.android.ui.TavernMaterial
import io.magicmobile.android.ui.TavernMenu
import io.magicmobile.android.ui.TavernMenuEdge
import io.magicmobile.android.ui.TavernMenuItem
import io.magicmobile.android.ui.TavernPalette
import io.magicmobile.android.ui.TavernPanelTitle
import io.magicmobile.android.ui.TavernSealButton
import io.magicmobile.android.ui.TavernTextField
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.sf
import io.magicmobile.android.ui.tavernCapsuleRim
import io.magicmobile.android.ui.tavernFill
import io.magicmobile.android.ui.tavernTitleBar
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

// Port of Ranked/FriendConversationView.swift: messages between friends, in Friends and in games.

private val brassFill = Brush.verticalGradient(listOf(rgb(1.0, 0.88, 0.56), rgb(0.80, 0.56, 0.22)))
private val darkBrassInk = rgb(0.25, 0.12, 0.04)

private val quickReplies = listOf("Want to play?", "Hello!", "Good game!", "Well played!", "Thanks!")

/**
 * A conversation with a friend: parchment bubbles for theirs, brass for yours, a send box with quick replies, and new messages
 * every few seconds while it's open. Their words show with strong language masked, like table chat.
 */
@Composable
fun FriendConversationScreen(account: PlayerAccount, username: String, close: () -> Unit) {
    val scope = rememberCoroutineScope()
    var messages by remember { mutableStateOf<List<FriendMessage>>(emptyList()) }
    var hasMore by remember { mutableStateOf(false) }
    var loaded by remember { mutableStateOf(false) }
    var failure by remember { mutableStateOf<String?>(null) }
    var draft by remember { mutableStateOf("") }
    var sending by remember { mutableStateOf(false) }
    var confirmBlock by remember { mutableStateOf(false) }
    var showProfile by remember { mutableStateOf(false) }
    val listState = rememberLazyListState()
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val online = account.friends.firstOrNull { it.username == username }?.online

    LaunchedEffect(username) {
        while (isActive) {
            if (lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
                try {
                    val page = account.thread(username)
                    messages = FriendMessageRules.merged(messages, page.messages)
                    if (!loaded) hasMore = page.hasMore
                    loaded = true; failure = null
                } catch (error: kotlinx.coroutines.CancellationException) { throw error
                } catch (error: Exception) { loaded = true; failure = PlayerAccountRules.message(SupabaseLite.code(error)) }
            }
            delay(FriendMessageRules.POLL_MILLIS)
        }
    }
    val lastId = messages.lastOrNull()?.id
    LaunchedEffect(lastId) { if (messages.isNotEmpty()) listState.animateScrollToItem(messages.size - 1 + if (hasMore) 1 else 0) }

    fun send(text: String) {
        if (sending || FriendMessageRules.sanitize(text) == null) return
        sending = true
        val previous = draft
        if (text == draft) draft = ""
        GameAudio.play(GameSound.UI_TAP)
        scope.launch {
            val sent = account.sendMessage(username, text)
            if (sent != null) messages = FriendMessageRules.merged(messages, listOf(sent)) else if (text == previous) draft = previous
            sending = false
        }
    }

    Box(Modifier.fillMaxSize()) {
        BrandBackdrop(Modifier.fillMaxSize(), cards = false)
        Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing).imePadding()) {
            Row(Modifier.padding(horizontal = 16.dp).padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.weight(1f)) { TavernScreenHeader(username, close, "Messages") }
                TavernMenu(Modifier.testTag("conversation.more"), TavernMenuEdge.BELOW, contentDescription = "More about $username", label = {
                    Box(Modifier.size(44.dp), contentAlignment = Alignment.Center) { SfImage("ellipsis", TavernPalette.brass, 17.dp) }
                }) {
                    TavernMenuItem("View profile", { showProfile = true }, systemImage = "person.crop.circle")
                    TavernMenuItem("Report $username", {
                        val lastTheirs = messages.lastOrNull { !it.fromMe }?.body
                        scope.launch { account.report(username, lastTheirs, "message") }
                    }, systemImage = "exclamationmark.bubble")
                    TavernMenuItem("Block", { confirmBlock = true }, systemImage = "hand.raised", destructive = true)
                }
            }
            if (online != null) Text(if (online) "Online now" else "Offline", Modifier.fillMaxWidth().padding(top = 4.dp).testTag("conversation.presence"),
                color = if (online) rgb(0.45, 0.92, 0.45) else TavernPalette.parchment.copy(alpha = 0.6f), style = ArenaMenuStyle.font(12f, SfWeight.semibold),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            LazyColumn(Modifier.weight(1f).fillMaxWidth().testTag("conversation.transcript"), state = listState, horizontalAlignment = Alignment.CenterHorizontally,
                contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                if (hasMore) item(key = "earlier") {
                    var loadingEarlier by remember { mutableStateOf(false) }
                    ArenaButton({
                        val first = messages.firstOrNull() ?: return@ArenaButton
                        loadingEarlier = true
                        scope.launch {
                            runCatching { account.thread(username, first.id) }.getOrNull()?.let { messages = FriendMessageRules.merged(messages, it.messages); hasMore = it.hasMore }
                            loadingEarlier = false
                        }
                    }, Modifier.padding(bottom = 6.dp), kind = ArenaButtonKind.SECONDARY, compact = true, enabled = !loadingEarlier, identifier = "conversation.earlier") {
                        SfImage("arrow.up.circle", androidx.compose.material3.LocalContentColor.current, 12.dp)
                        ArenaButtonText("Earlier messages")
                    }
                }
                when {
                    !loaded -> item(key = "loading") { Box(Modifier.padding(top = 40.dp)) { SocialWaiting("Opening your messages…") } }
                    failure != null && messages.isEmpty() -> item(key = "error") {
                        Row(Modifier.widthIn(max = 640.dp).leatherCard().testTag("conversation.error"), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            SfImage("wifi.exclamationmark", TavernPalette.brass, 16.dp)
                            Text(failure ?: "", color = TavernPalette.parchment, style = ArenaMenuStyle.font(14f, SfWeight.semibold))
                        }
                    }
                    messages.isEmpty() -> item(key = "empty") {
                        Column(Modifier.padding(top = 40.dp).testTag("conversation.empty"), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            SfImage("bubble.left.and.bubble.right.fill", TavernPalette.brass, 30.dp)
                            Text("Say hello to $username. Messages stay between you two.", Modifier.alpha(0.8f), color = TavernPalette.parchment,
                                style = ArenaMenuStyle.font(14f, SfWeight.regular), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                        }
                    }
                }
                val lastMine = messages.lastOrNull { it.fromMe }?.id
                itemsIndexed(messages, key = { _, m -> m.id }) { index, message ->
                    Column(Modifier.widthIn(max = 640.dp).fillMaxWidth().animateItem()) {
                        if (index == 0 || !sameDay(message.sentAt, messages[index - 1].sentAt)) Text(dayLabel(message.sentAt),
                            Modifier.fillMaxWidth().padding(top = 10.dp, bottom = 4.dp).alpha(0.55f), color = TavernPalette.parchment,
                            style = sf(11f, SfWeight.heavy, tracking = 0.8f), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                        Bubble(message, username, message.fromMe && message.id == lastMine)
                    }
                }
            }
            // Composer: quick replies, then the field and send, on Arena's glass.
            Column(Modifier.fillMaxWidth().background(Brush.verticalGradient(listOf(ArenaGlass.top, ArenaGlass.bottom)))
                .drawBehind { drawRect(ArenaGlass.hairline, size = androidx.compose.ui.geometry.Size(size.width, 1.dp.toPx()), alpha = 0.6f) }
                .padding(vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    for (reply in quickReplies) Text(reply, Modifier.defaultMinSize(minHeight = 36.dp).background(Color.Black.copy(alpha = 0.5f), CircleShape)
                        .border(0.9.dp, ArenaGlass.hairline, CircleShape)
                        .socialButton(reply, "conversation.quick.$reply") { send(reply) }.padding(horizontal = 12.dp, vertical = 9.dp),
                        color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(12f, SfWeight.heavy))
                }
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.weight(1f).defaultMinSize(minHeight = 40.dp).background(Color.Black.copy(alpha = 0.55f), RoundedCornerShape(20.dp))
                        .border(1.dp, ArenaGlass.hairline, RoundedCornerShape(20.dp)).padding(horizontal = 14.dp, vertical = 10.dp), contentAlignment = Alignment.CenterStart) {
                        if (draft.isEmpty()) Text("Message $username", color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(15f, SfWeight.regular), maxLines = 1)
                        BasicTextField(draft, { draft = it.take(FriendMessageRules.MAX_CODE_POINTS + 20) }, Modifier.fillMaxWidth().heightIn(max = 96.dp)
                            .testTag("conversation.field").semantics { contentDescription = "Message $username" }, maxLines = 4,
                            textStyle = ArenaMenuStyle.font(15f, SfWeight.regular).copy(color = ArenaMenuStyle.text), cursorBrush = SolidColor(ArenaMenuStyle.gold))
                    }
                    val enabled = !sending && FriendMessageRules.sanitize(draft) != null
                    Box(Modifier.size(46.dp).alpha(if (enabled) 1f else 0.5f).padding(2.dp).background(ArenaMenuStyle.orange, CircleShape)
                        .border(1.5.dp, ArenaMenuStyle.orangeRim, CircleShape)
                        .clickable(enabled = enabled) { send(draft) }.semantics { contentDescription = "Send"; role = Role.Button }.testTag("conversation.send"),
                        contentAlignment = Alignment.Center) { SfImage("paperplane.fill", Color.White, 17.dp) }
                }
            }
        }
        account.notice?.let { SocialNotice(it, { account.notice = null }, Modifier.align(Alignment.BottomCenter).padding(bottom = 120.dp)) }
    }
    if (showProfile) androidx.compose.ui.window.Dialog({ showProfile = false },
        androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false, dismissOnBackPress = false)) {
        PublicProfileScreen(account, username) { showProfile = false }
    }
    if (confirmBlock) ArenaConfirmation("Block $username?", "They're removed from your friends and this conversation closes. You can unblock them in Friends later.",
        "Block", destructive = true, { scope.launch { account.block(username); close() } }) { confirmBlock = false }
}

@Composable
private fun Bubble(message: FriendMessage, friend: String, lastMine: Boolean) {
    val shape = RoundedCornerShape(14.dp)
    val text = FriendMessageRules.shown(message)
    Column(Modifier.fillMaxWidth().padding(start = if (message.fromMe) 48.dp else 0.dp, end = if (message.fromMe) 0.dp else 48.dp)
        .semantics(mergeDescendants = true) { contentDescription = "${if (message.fromMe) "You" else friend}: $text" }
        .testTag("conversation.message.${message.id}"),
        horizontalAlignment = if (message.fromMe) Alignment.End else Alignment.Start, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        SelectionContainer {
            Text(text, Modifier.glow(Color.Black.copy(alpha = 0.4f), 3.dp, 14.dp)
                .then(if (message.fromMe) Modifier.background(brassFill, shape)
                    else Modifier.background(Color.White.copy(alpha = 0.1f), shape).border(0.8.dp, ArenaGlass.hairline, shape))
                .padding(horizontal = 12.dp, vertical = 8.dp),
                color = if (message.fromMe) rgb(0.16, 0.08, 0.03) else ArenaMenuStyle.text, style = ArenaMenuStyle.font(15f, SfWeight.regular))
        }
        Text(timeLabel(message.sentAt) + if (lastMine && message.read) " · Read" else "", Modifier.alpha(0.55f), color = TavernPalette.parchment,
            style = ArenaMenuStyle.font(10f, SfWeight.regular))
    }
}

private fun sameDay(a: Long, b: Long): Boolean {
    val zone = ZoneId.systemDefault()
    return Instant.ofEpochMilli(a).atZone(zone).toLocalDate() == Instant.ofEpochMilli(b).atZone(zone).toLocalDate()
}

private fun dayLabel(millis: Long): String = DateTimeFormatter.ofPattern("EEEE, MMM d").format(Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()))

private fun timeLabel(millis: Long): String = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).format(Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()))

/**
 * The Messages list: friends you've written to by their last message (newest first, unread counts in ember), then friends you
 * haven't written to yet. Shown in Friends and, through FriendMessagesHub, from the game menu.
 */
@Composable
fun FriendMessagesList(account: PlayerAccount, open: (String) -> Unit) {
    var conversations by remember { mutableStateOf<List<MessageConversation>>(emptyList()) }
    var loaded by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        while (isActive) {
            account.conversations()?.let { conversations = it }
            loaded = true
            delay(10_000)
        }
    }
    val friends = account.friends.filter { it.isFriend }
    val rows = FriendMessageRules.ordered(friends.map { it.username }, conversations)
    Column(Modifier.fillMaxWidth().testTag("messages.list"), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(Modifier.fillMaxWidth().padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            ArenaCaps("Messages", modifier = Modifier.weight(1f))
            if (account.unreadMessages > 0) Text("${account.unreadMessages} unread", color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(11f, SfWeight.semibold))
        }
        when {
            !account.messagesAvailable -> ProfileEmptyNote("Messages arrive with the next server update.", "hourglass")
            friends.isEmpty() -> ProfileEmptyNote("Add a friend to start a conversation. Messages stay between the two of you.", "bubble.left.and.bubble.right.fill")
            !loaded -> SocialWaiting("Opening your messages…")
            else -> for ((name, conversation) in rows) {
                val friend = friends.firstOrNull { it.username == name }
                val line = conversation?.last?.let { if (it.fromMe) "You: ${FriendMessageRules.shown(it)}" else FriendMessageRules.shown(it) } ?: "Say hello"
                val unread = conversation?.unread ?: 0
                Box(Modifier.socialButton("$name${if (unread > 0) ", $unread unread" else ""}, ${if (conversation == null) "no messages yet" else line}", "messages.row.$name") {
                    GameAudio.play(GameSound.UI_OPEN); open(name)
                }) {
                    SocialRowCard { SocialPlayerHeading(name, null, line, friend?.online, account.friendRanks[name], compact = true) }
                    if (unread > 0) Text("$unread", Modifier.align(Alignment.TopEnd).offset(4.dp, (-6).dp).defaultMinSize(minWidth = 22.dp, minHeight = 22.dp)
                        .background(ArenaMenuStyle.ember, CircleShape).border(1.dp, Color.Black.copy(alpha = 0.4f), CircleShape).padding(horizontal = 7.dp, vertical = 3.dp),
                        color = Color.White, style = sf(11f, SfWeight.black), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                }
            }
        }
    }
}

/** Messages on a sheet: the list, then a conversation in its place. Opened from the game menu and the in-game banner. */
@Composable
fun FriendMessagesHub(account: PlayerAccount, initial: String? = null, done: () -> Unit) {
    var open by remember { mutableStateOf(initial) }
    val name = open
    if (name != null) {
        FriendConversationScreen(account, name) { open = null }
        return
    }
    Box(Modifier.fillMaxSize()) {
        BrandBackdrop(Modifier.fillMaxSize(), cards = false)
        Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing)) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = 8.dp).tavernTitleBar(), verticalAlignment = Alignment.CenterVertically) {
                TavernPanelTitle("Messages", Modifier.weight(1f).semantics { heading() })
                TavernSealButton(done, Modifier.testTag("messages.done"), contentDescription = "Done")
            }
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally) {
                Box(Modifier.widthIn(max = 640.dp).padding(16.dp)) { FriendMessagesList(account) { open = it } }
            }
        }
    }
}

/** Friend messages for screens that don't hold the account (the game menu): the unread count and how to open them. */
data class FriendMessagesEntry(val unread: Int, val open: () -> Unit)

val LocalFriendMessages = androidx.compose.runtime.compositionLocalOf<FriendMessagesEntry?> { null }

/** A friend's new message during a game: a small banner at the top; a tap opens the conversation. */
@Composable
fun FriendMessageBanner(name: String, text: String, open: () -> Unit, dismiss: () -> Unit, modifier: Modifier = Modifier) {
    Row(modifier.widthIn(max = 420.dp).fillMaxWidth().glow(Color.Black.copy(alpha = 0.6f), 8.dp, 22.dp).background(Color.Black.copy(alpha = 0.5f), CircleShape)
        .border(1.dp, ArenaGlass.hairline, CircleShape).clickable(onClick = open)
        .semantics(mergeDescendants = true) { contentDescription = "New message from $name: $text"; role = Role.Button }.testTag("messages.banner")
        .padding(start = 14.dp, end = 6.dp, top = 6.dp, bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        SfImage("bubble.left.fill", TavernPalette.brass, 15.dp)
        Column(Modifier.weight(1f)) {
            Text(name, color = TavernPalette.parchment, style = ArenaMenuStyle.font(13f, SfWeight.black))
            Text(text, Modifier.alpha(0.85f), color = TavernPalette.parchment, style = ArenaMenuStyle.font(12f, SfWeight.regular), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Box(Modifier.size(32.dp).clickable(onClick = dismiss).semantics { contentDescription = "Dismiss"; role = Role.Button }, contentAlignment = Alignment.Center) {
            SfImage("xmark", TavernPalette.parchment, 11.dp)
        }
    }
}
