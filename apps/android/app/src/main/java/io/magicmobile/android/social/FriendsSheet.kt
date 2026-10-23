package io.magicmobile.android.social

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
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
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import io.magicmobile.android.game.ArenaProfileRules
import io.magicmobile.android.game.FriendChallengeRules
import io.magicmobile.android.game.PlayMode
import io.magicmobile.android.game.PlayerAccountRules
import io.magicmobile.android.game.PlayerFriend
import io.magicmobile.android.game.PlayerSearchResult
import io.magicmobile.android.game.PlayerSearchRules
import io.magicmobile.android.game.ProfileVisibility
import io.magicmobile.android.menus.ArenaCaps
import io.magicmobile.android.menus.ArenaGlass
import io.magicmobile.android.menus.ArenaMenuStyle
import io.magicmobile.android.menus.ArenaOptionRow
import io.magicmobile.android.menus.ArenaPanelHeader
import io.magicmobile.android.menus.ArenaPillButton
import io.magicmobile.android.menus.ArenaSearchField
import io.magicmobile.android.menus.ArenaTabBar
import io.magicmobile.android.menus.arenaCard
import io.magicmobile.android.menus.arenaScrollFade
import io.magicmobile.android.ranked.ArenaConfirmation
import io.magicmobile.android.ranked.ProfileEmptyNote
import io.magicmobile.android.ranked.PublicProfileScreen
import io.magicmobile.android.ranked.SocialNotice
import io.magicmobile.android.ranked.SocialPlayerHeading
import io.magicmobile.android.ranked.SocialRowCard
import io.magicmobile.android.ranked.SocialWaiting
import io.magicmobile.android.ranked.socialButton
import io.magicmobile.android.ranked.withRelation
import io.magicmobile.android.ui.BrandPressable
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.TavernMenu
import io.magicmobile.android.ui.TavernMenuEdge
import io.magicmobile.android.ui.TavernMenuItem
import io.magicmobile.android.ui.TavernTag
import io.magicmobile.android.ui.glow
import io.magicmobile.android.ui.rgb
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant

private sealed class SearchState {
    object Idle : SearchState()
    object Searching : SearchState()
    object Done : SearchState()
    data class Failed(val message: String) : SearchState()
}

/**
 * Find players as you type, add friends, see who's online and join their tables in one tap, and open anyone's profile
 * (FriendsView.swift). Arena's social panel (Caleb, 2026-10-22): it slides in from the left with your name at the top, Friends
 * and Messages as a tab strip, the search in one slim field and requests folded into a row, so your friends show first.
 */
@Composable
fun FriendsSheet(account: PlayerAccount, join: (String) -> Unit, myRankStep: Int? = null,
                 challenge: ((PlayerFriend, PlayMode) -> Unit)? = null, done: () -> Unit) {
    val scope = rememberCoroutineScope()
    var nameDraft by remember { mutableStateOf("") }
    var editingName by remember { mutableStateOf(false) }
    var query by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<PlayerSearchResult>>(emptyList()) }
    var search by remember { mutableStateOf<SearchState>(SearchState.Idle) }
    var confirmDelete by remember { mutableStateOf(false) }
    var confirmBlock by remember { mutableStateOf<PlayerFriend?>(null) }
    var profileFor by remember { mutableStateOf<String?>(null) }
    var messagesTab by remember { mutableStateOf(false) }
    var conversationWith by remember { mutableStateOf<String?>(null) }
    var showRequests by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        if (account.phase == PlayerAccount.Phase.READY) account.refresh() else account.start()
        io.magicmobile.android.ranked.SocialFixtures.openScreen?.let { screen ->
            val value = screen.substringAfter(":", "")
            if (screen.startsWith("public:") && value.isNotEmpty()) profileFor = value
            if (screen.startsWith("search:") && value.isNotEmpty()) query = value
            if (screen == "messages") messagesTab = true
            if (screen.startsWith("conversation:") && value.isNotEmpty()) { messagesTab = true; conversationWith = value }
        }
    }
    // Typing: wait a moment after the last key; a newer key cancels this effect, so a stale request never lands.
    LaunchedEffect(query, account.searchAvailable) {
        val text = PlayerSearchRules.normalized(query)
        if (!account.searchAvailable || text == null) { results = emptyList(); search = SearchState.Idle; return@LaunchedEffect }
        search = SearchState.Searching
        delay(250)
        try {
            results = account.search(text)
            search = SearchState.Done
        } catch (cancelled: CancellationException) { throw cancelled
        } catch (error: Exception) {
            results = emptyList()
            // Without the server's search the field turns into a plain "add by name" one.
            search = if (account.searchAvailable) SearchState.Failed(PlayerAccountRules.message(SupabaseLite.code(error))) else SearchState.Idle
        }
    }
    val openProfile: (String) -> Unit = { GameAudio.play(GameSound.UI_OPEN); profileFor = it }
    val ready = account.phase == PlayerAccount.Phase.READY
    val showsDeleteLink = ready && account.username != null && !editingName

    androidx.compose.foundation.layout.BoxWithConstraints(Modifier.fillMaxSize()) {
        // A landscape phone leaves the side panel little height under the top bar: a shallower fade and tighter rows, so the
        // friend rows start inside the panel's view instead of under its foot.
        val short = maxHeight < 420.dp
        Column(Modifier.fillMaxSize().imePadding()) {
            ArenaPanelHeader("Friends", closeIdentifier = "friends.done", close = done)
            // The delete link follows the list; rows fade into the panel's foot rather than being cut by it.
            Column(Modifier.fillMaxWidth().weight(1f, fill = false).arenaScrollFade(if (short) 18.dp else 36.dp).verticalScroll(rememberScrollState())
                .padding(horizontal = 14.dp).padding(top = if (short) 4.dp else 10.dp, bottom = if (short) 18.dp else 36.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Column(Modifier.widthIn(max = 640.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(if (short) 6.dp else 12.dp)) {
                    when {
                        account.phase == PlayerAccount.Phase.UNAVAILABLE -> Column(Modifier.arenaCard(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            Text(account.notice ?: PlayerAccountRules.message("offline"), color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(14f, SfWeight.medium))
                            ArenaPillButton("Try again", { scope.launch { account.start() } }, identifier = "friends.retry")
                        }
                        !ready -> Box(Modifier.arenaCard()) { SocialWaiting("Loading your profile…") }
                        account.username == null || editingName -> NameCard(nameDraft, { nameDraft = it }, editingName,
                            save = { scope.launch { if (account.claim(nameDraft)) editingName = false } }, cancel = { editingName = false })
                        else -> {
                            ProfileRow(account, open = { account.username?.let { profileFor = it } }) { nameDraft = account.username ?: ""; editingName = true }
                            FriendsTabPicker(messagesTab, account.unreadMessages) { messagesTab = it }
                            if (messagesTab) FriendMessagesList(account) { conversationWith = it } else {
                                SearchRow(account, query, { query = it.take(40) }, search, results, openProfile,
                                    addByName = { val name = query; query = ""; scope.launch { account.addFriend(name) } },
                                    add = { result ->
                                        results = results.map { if (it.username == result.username) it.withRelation("outgoing") else it }
                                        scope.launch {
                                            account.addFriend(result.username); account.refresh()
                                            // A request they had already sent you makes you friends at once.
                                            account.friends.firstOrNull { it.username == result.username }?.let { now ->
                                                results = results.map { if (it.username == result.username) it.withRelation(now.relation) else it }
                                            }
                                        }
                                    },
                                    accept = { result ->
                                        account.friends.firstOrNull { it.username == result.username }?.let { friend ->
                                            results = results.map { if (it.username == result.username) it.withRelation("friend") else it }
                                            scope.launch { account.respond(friend, true) }
                                        }
                                    })
                                val incoming = account.friends.filter { it.isIncoming }
                                if (incoming.isNotEmpty()) RequestsRow(account, incoming, showRequests, { showRequests = !showRequests }, openProfile, scope)
                                val friends = account.friends.filter { it.isFriend }
                                Column(Modifier.fillMaxWidth().testTag("friends.list"), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                    CapsHeading("Friends", if (friends.isEmpty()) null else "${account.onlineFriendCount} online", Modifier.padding(top = 4.dp))
                                    if (friends.isEmpty()) ProfileEmptyNote("Search for a player above to add your first friend. You'll see when they're online and can join their tables.", "person.2.fill")
                                    for (friend in friends) FriendRow(friend, account, myRankStep, challenge, { openProfile(friend.username) }, join, done, { confirmBlock = friend }, scope) {
                                        conversationWith = friend.username
                                    }
                                }
                                val outgoing = account.friends.filter { it.isOutgoing }
                                if (outgoing.isNotEmpty()) Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                    CapsHeading("Sent", "${outgoing.size}", Modifier.padding(top = 8.dp))
                                    for (friend in outgoing) Row(Modifier.fillMaxWidth().rowRule(), verticalAlignment = Alignment.CenterVertically) {
                                        Text(friend.username, Modifier.weight(1f).defaultMinSize(minHeight = 44.dp)
                                            .socialButton("${friend.username}, request sent", "friends.sent.${friend.username}") { openProfile(friend.username) }
                                            .padding(vertical = 12.dp), color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(15f, SfWeight.semibold))
                                        ArenaPillButton("Cancel", { scope.launch { account.remove(friend) } }, identifier = "friends.cancel.${friend.username}")
                                    }
                                }
                                if (account.blocked.isNotEmpty()) Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                    CapsHeading("Blocked", "${account.blocked.size}", Modifier.padding(top = 8.dp))
                                    for (name in account.blocked) Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).rowRule(), verticalAlignment = Alignment.CenterVertically) {
                                        Text(name, Modifier.weight(1f), color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(15f, SfWeight.semibold))
                                        ArenaPillButton("Unblock", { scope.launch { account.unblock(name) } }, identifier = "friends.unblock.$name")
                                    }
                                }
                            }
                        }
                    }
                    // Out of the way at the very foot, as small type (the judge, 2026-10-22: not a plaque in the social panel).
                    if (showsDeleteLink) Box(Modifier.padding(top = 18.dp).defaultMinSize(minHeight = 44.dp)
                        .socialButton("Delete my profile", "friends.deleteAccount") { confirmDelete = true }, contentAlignment = Alignment.CenterStart) {
                        Text("Delete my profile", color = ArenaMenuStyle.loss, style = ArenaMenuStyle.font(12f, SfWeight.semibold))
                    }
                }
            }
        }
        account.notice?.takeIf { ready }?.let { SocialNotice(it, { account.notice = null }, Modifier.align(Alignment.BottomCenter)) }
    }

    conversationWith?.let { name ->
        Dialog({ conversationWith = null }, DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false, dismissOnBackPress = false)) {
            androidx.activity.compose.BackHandler { conversationWith = null }
            FriendConversationScreen(account, name) { conversationWith = null }
        }
    }
    profileFor?.let { name ->
        Dialog({ profileFor = null }, DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false, dismissOnBackPress = false)) {
            PublicProfileScreen(account, name, challenge?.let { handler -> { friendName, mode -> account.friends.firstOrNull { it.username == friendName }?.let { handler(it, mode) } } },
                myRankStep) { profileFor = null }
        }
    }
    confirmBlock?.let { friend ->
        ArenaConfirmation("Block ${friend.username}?", "They're removed from your friends and can't send you requests. You can unblock them here later.",
            "Block", destructive = true, { scope.launch { account.block(friend.username) } }) { confirmBlock = null }
    }
    if (confirmDelete) {
        ArenaConfirmation("Delete your profile?", ArenaProfileRules.DELETE_PROFILE_MESSAGE, "Delete profile", destructive = true,
            { scope.launch { if (account.deleteAccount()) done() } }) { confirmDelete = false }
    }
}

/** A hairline under a list row. */
private fun Modifier.rowRule(): Modifier = drawBehind {
    drawRect(Color.White.copy(alpha = 0.07f), Offset(0f, size.height - 1.dp.toPx()), Size(size.width, 1.dp.toPx()))
}

/** A list's gold caps heading with a quiet count at the right. */
@Composable
private fun CapsHeading(title: String, trailing: String?, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        ArenaCaps(title, modifier = Modifier.weight(1f))
        trailing?.let { Text(it, color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(11f, SfWeight.semibold)) }
    }
}

@Composable
private fun NameCard(draft: String, setDraft: (String) -> Unit, editing: Boolean, save: () -> Unit, cancel: () -> Unit) {
    Column(Modifier.arenaCard(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        ArenaCaps("Your player name")
        Box(Modifier.fillMaxWidth().height(40.dp).background(Color.Black.copy(alpha = 0.55f), CircleShape)
            .border(1.dp, ArenaGlass.hairline, CircleShape).padding(horizontal = 14.dp), contentAlignment = Alignment.CenterStart) {
            if (draft.isEmpty()) Text("Player name", color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(15f, SfWeight.semibold))
            BasicTextField(draft, { value -> setDraft(value.filter { it in 'a'..'z' || it in 'A'..'Z' || it in '0'..'9' || it == '_' }.take(20)) },
                Modifier.fillMaxWidth().testTag("friends.nameField").semantics { contentDescription = "Player name" }, singleLine = true,
                textStyle = ArenaMenuStyle.font(15f, SfWeight.semibold).copy(color = ArenaMenuStyle.text), cursorBrush = SolidColor(ArenaMenuStyle.gold))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            ArenaPillButton(if (editing) "Save name" else "Choose name", save, lit = true, enabled = PlayerAccountRules.isValidUsername(draft), identifier = "friends.saveName")
            if (editing) ArenaPillButton("Cancel", cancel)
        }
        Text("Used at every table, and friends add you by it. 3–20 letters, numbers or underscores.", color = ArenaMenuStyle.dim,
            style = ArenaMenuStyle.font(12f, SfWeight.medium))
    }
}

/** You, at the top of the panel as in Arena's: your picture, name and who can see your profile. */
@Composable
private fun ProfileRow(account: PlayerAccount, open: () -> Unit, change: () -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        Row(Modifier.weight(1f).defaultMinSize(minHeight = 44.dp).socialButton("Your profile, ${account.username}", "friends.myProfile", open),
            horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            SfImage("person.crop.circle.fill", ArenaMenuStyle.gold, 30.dp)
            Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                io.magicmobile.android.ui.FitText(account.username ?: "", ArenaMenuStyle.font(17f, SfWeight.bold), color = ArenaMenuStyle.text, minimumScale = 0.75f)
                Text(if (account.visibilityKnown) "Profile: ${account.visibility.title}" else "Your name at every table", color = ArenaMenuStyle.dim,
                    style = ArenaMenuStyle.font(12f, SfWeight.medium), maxLines = 1)
            }
        }
        ArenaPillButton("Change", change, identifier = "friends.changeName")
    }
}

/** One slim field: live search, or add by exact name until the server has search. What it finds shows under it. */
@Composable
private fun SearchRow(account: PlayerAccount, query: String, setQuery: (String) -> Unit, search: SearchState, results: List<PlayerSearchResult>,
                      openProfile: (String) -> Unit, addByName: () -> Unit, add: (PlayerSearchResult) -> Unit, accept: (PlayerSearchResult) -> Unit) {
    Column(Modifier.fillMaxWidth().testTag("friends.searchCard"), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            ArenaSearchField(if (account.searchAvailable) "Find players" else "Their exact player name", query, setQuery, Modifier.weight(1f),
                identifier = if (account.searchAvailable) "friends.search" else "friends.addField")
            if (!account.searchAvailable) ArenaPillButton("Add", addByName, lit = true, enabled = query.isNotBlank(), identifier = "friends.add")
        }
        val trimmed = query.trim()
        if (account.searchAvailable) {
            // Nothing under an empty field, so the friends list stays at the top of the panel.
            if (trimmed.isNotEmpty() && PlayerSearchRules.normalized(trimmed) == null) Text(
                if (trimmed.length < PlayerSearchRules.MINIMUM_LENGTH) "Keep typing: two letters at least." else "Player names have letters, numbers and underscores only.",
                Modifier.testTag("friends.search.hint"), color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(12f, SfWeight.medium))
            else when (search) {
                is SearchState.Failed -> Text(search.message, Modifier.testTag("friends.search.error"), color = ArenaMenuStyle.loss, style = ArenaMenuStyle.font(13f, SfWeight.semibold))
                SearchState.Searching -> if (results.isEmpty()) SocialWaiting("Looking for players…")
                SearchState.Done -> if (results.isEmpty()) Box(Modifier.testTag("friends.search.empty")) { ProfileEmptyNote("No players found starting with “$trimmed”.", "magnifyingglass") }
                SearchState.Idle -> {}
            }
            if (results.isNotEmpty() && PlayerSearchRules.normalized(trimmed) != null) Column(Modifier.alpha(if (search == SearchState.Searching) 0.6f else 1f)
                .testTag("friends.search.results"), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                for (result in results) ResultRow(result, { openProfile(result.username) }, { add(result) }, { accept(result) })
            }
        } else if (query.isNotEmpty()) {
            Text("Live search arrives with the next server update. Until then, add a friend by their exact player name.", Modifier.testTag("friends.searchUnavailable"),
                color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(12f, SfWeight.medium))
        }
    }
}

@Composable
private fun ResultRow(result: PlayerSearchResult, openProfile: () -> Unit, add: () -> Unit, accept: () -> Unit) {
    val rank = result.position
    val relation = when (result.relation) {
        "friend" -> ", friend" + if (result.online == true) ", online" else ""
        "outgoing" -> ", request sent"; "incoming" -> ", wants to be your friend"; else -> ""
    }
    SocialRowCard {
        SocialPlayerHeading(result.username, result.favoriteCommander, result.favoriteCommander ?: if (result.visibility == ProfileVisibility.PUBLIC) "No games to show yet" else "Profile hidden",
            if (result.relation == "friend") result.online else null, rank,
            Modifier.socialButton("${result.username}${rank?.let { ", ${it.title}" } ?: ", unranked"}$relation", "friends.result.${result.username}") { openProfile() },
            compact = true)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            if (result.visibility != ProfileVisibility.PUBLIC) TavernTag(if (result.visibility == ProfileVisibility.FRIENDS) "FRIENDS ONLY" else "PRIVATE", leather = true)
            Spacer(Modifier.weight(1f))
            ArenaPillButton("Profile", openProfile, identifier = "friends.result.profile.${result.username}")
            when (result.relation) {
                "friend" -> TavernTag("FRIENDS", leather = true, accent = if (result.online == true) rgb(0.4, 0.85, 0.4) else null)
                "outgoing" -> TavernTag("REQUESTED", leather = true)
                "incoming" -> ArenaPillButton("Accept", accept, lit = true, identifier = "friends.result.accept.${result.username}")
                else -> ArenaPillButton("Add friend", add, lit = true, identifier = "friends.result.add.${result.username}")
            }
        }
    }
}

/** Requests fold into one row with their count; it opens them in place. */
@Composable
private fun RequestsRow(account: PlayerAccount, incoming: List<PlayerFriend>, open: Boolean, toggle: () -> Unit, openProfile: (String) -> Unit,
                        scope: kotlinx.coroutines.CoroutineScope) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        ArenaOptionRow("Requests", toggle, Modifier.semantics { stateDescription = if (open) "Expanded" else "Collapsed" }, value = "${incoming.size}",
            chevron = true, identifier = "friends.requests")
        if (open) for (friend in incoming) SocialRowCard {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.weight(1f)) {
                    SocialPlayerHeading(friend.username, null, "Wants to be your friend", null, account.friendRanks[friend.username],
                        Modifier.socialButton("${friend.username} wants to be your friend", "friends.request.${friend.username}") { openProfile(friend.username) }, compact = true)
                }
                Box(Modifier.size(36.dp, 44.dp).socialButton("Decline", "friends.decline.${friend.username}") { scope.launch { account.respond(friend, false) } },
                    contentAlignment = Alignment.Center) { SfImage("xmark", ArenaMenuStyle.dim, 12.dp) }
                ArenaPillButton("Accept", { scope.launch { account.respond(friend, true) } }, lit = true, identifier = "friends.accept.${friend.username}")
            }
        }
    }
}

/**
 * A friend as Arena lists them: one line (picture, name, status, rank), with Join or Challenge, Message and ⋯ as small buttons at
 * the end of the line (the judge, 2026-10-22).
 */
@Composable
private fun FriendRow(friend: PlayerFriend, account: PlayerAccount, myRankStep: Int?, challenge: ((PlayerFriend, PlayMode) -> Unit)?, openProfile: () -> Unit,
                      join: (String) -> Unit, done: () -> Unit, block: () -> Unit, scope: kotlinx.coroutines.CoroutineScope, message: () -> Unit) {
    val rank = account.friendRanks[friend.username]
    Row(Modifier.fillMaxWidth().padding(vertical = 1.dp).rowRule(), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.weight(1f)) {
            SocialPlayerHeading(friend.username, null, friendStatus(friend), friend.online, rank,
                Modifier.socialButton("${friend.username}${rank?.let { ", ${it.title}" } ?: ""}, ${friendStatus(friend)}", "friends.card.${friend.username}") { openProfile() },
                compact = true)
        }
        val code = friend.joinableCode
        if (code != null) BrandPressable({ join(code); done() }, Modifier.testTag("friends.join.${friend.username}")
            .semantics { contentDescription = "Join ${friend.username}'s table"; role = Role.Button }) { FriendRowAction("arrow.right.circle.fill") }
        else if (challenge != null && friend.online) {
            val mayRank = myRankStep?.let { FriendChallengeRules.mayRank(it, rank?.step) } ?: false
            TavernMenu(Modifier.testTag("friends.challenge.${friend.username}"), TavernMenuEdge.BELOW, contentDescription = "Challenge ${friend.username}",
                label = { FriendRowAction("flag.2.crossed.fill") }) {
                TavernMenuItem("Quick Match", { challenge(friend, PlayMode.QUICK); done() }, systemImage = "bolt.fill")
                TavernMenuItem(if (mayRank) "Ranked" else "Ranked · same tier only", { if (mayRank) { challenge(friend, PlayMode.RANKED); done() } }, systemImage = "shield.lefthalf.filled")
            }
        }
        if (account.messagesAvailable) Box(Modifier.size(34.dp, 44.dp).socialButton("Message ${friend.username}", "friends.message.${friend.username}") {
            GameAudio.play(GameSound.UI_OPEN); message()
        }, contentAlignment = Alignment.Center) { SfImage("bubble.left.fill", ArenaMenuStyle.gold, 15.dp) }
        TavernMenu(Modifier.testTag("friends.more.${friend.username}"), TavernMenuEdge.BELOW, contentDescription = "More about ${friend.username}", label = {
            Box(Modifier.size(30.dp, 44.dp), contentAlignment = Alignment.Center) { SfImage("ellipsis", ArenaMenuStyle.gold, 16.dp) }
        }) {
            TavernMenuItem("View profile", openProfile, systemImage = "person.crop.circle")
            TavernMenuItem("Message", message, systemImage = "bubble.left")
            TavernMenuItem("Remove friend", { scope.launch { account.remove(friend) } }, systemImage = "xmark.circle", destructive = true)
            TavernMenuItem("Block", block, systemImage = "hand.raised", destructive = true)
        }
    }
}

/** A friend row's own action (Join a table, Challenge) as a small lit ember disc with a gold rim, at the end of the line. */
@Composable
private fun FriendRowAction(symbol: String) {
    Box(Modifier.size(36.dp, 44.dp), contentAlignment = Alignment.Center) {
        Box(Modifier.size(28.dp).glow(ArenaMenuStyle.ember.copy(alpha = 0.5f), 4.dp, 14.dp).background(ArenaMenuStyle.orange, CircleShape)
            .border(1.2.dp, ArenaMenuStyle.orangeRim, CircleShape), contentAlignment = Alignment.Center) {
            SfImage(symbol, Color.White, 13.dp)
        }
    }
}

/** Short enough to show whole on one line beside the row's buttons. */
private fun friendStatus(friend: PlayerFriend): String {
    if (friend.joinableCode != null) {
        val seats = friend.hostingOpenSeats ?: 1
        return if (seats == 1) "Hosting · 1 seat" else "Hosting · $seats seats"
    }
    if (friend.online) return "Online"
    val seen = friend.lastSeenAt?.let { runCatching { Instant.parse(it.replace(Regex("\\+00:00$"), "Z")) }.getOrNull() } ?: return "Offline"
    val minutes = Duration.between(seen, Instant.now()).toMinutes().coerceAtLeast(1)
    return when {
        minutes < 60 -> "Last seen $minutes min ago"
        minutes < 60 * 24 -> "Last seen ${minutes / 60} h ago"
        else -> "Last seen ${minutes / (60 * 24)} d ago"
    }
}

/** Friends or Messages as Arena's tab strip, with the unread count beside Messages. */
@Composable
private fun FriendsTabPicker(messages: Boolean, unread: Int, select: (Boolean) -> Unit) {
    Box(Modifier.fillMaxWidth()) {
        Box(Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(bottom = 2.dp).height(1.dp).alpha(0.35f).background(ArenaGlass.hairline))
        Row(Modifier.fillMaxWidth()) {
            for (option in listOf(false, true)) {
                val selected = option == messages
                BrandPressable({ if (!selected) { GameAudio.play(GameSound.UI_TAP); select(option) } }, Modifier.weight(1f).defaultMinSize(minHeight = 44.dp)
                    .semantics { this.selected = selected; role = Role.Tab }.testTag(if (option) "friends.tab.messages" else "friends.tab.friends")) {
                    Box(Modifier.fillMaxWidth().height(40.dp), contentAlignment = Alignment.Center) {
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(if (option) "Messages" else "Friends", color = if (selected) ArenaMenuStyle.text else ArenaMenuStyle.dim,
                                style = ArenaMenuStyle.font(14f, if (selected) SfWeight.bold else SfWeight.semibold))
                            if (option && unread > 0) Text("$unread", Modifier.defaultMinSize(18.dp, 18.dp).background(ArenaMenuStyle.ember, CircleShape)
                                .padding(horizontal = 5.dp, vertical = 1.dp), color = Color.White,
                                style = io.magicmobile.android.ui.sf(10f, SfWeight.black).copy(fontFeatureSettings = "tnum", textAlign = androidx.compose.ui.text.style.TextAlign.Center))
                        }
                        ArenaTabBar(selected, Modifier.align(Alignment.BottomCenter))
                    }
                }
            }
        }
    }
}
