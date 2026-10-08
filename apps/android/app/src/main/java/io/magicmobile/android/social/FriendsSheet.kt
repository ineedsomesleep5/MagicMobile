package io.magicmobile.android.social

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import io.magicmobile.android.game.FriendChallengeRules
import io.magicmobile.android.game.PlayMode
import io.magicmobile.android.game.PlayerAccountRules
import io.magicmobile.android.game.PlayerFriend
import io.magicmobile.android.game.PlayerSearchResult
import io.magicmobile.android.game.PlayerSearchRules
import io.magicmobile.android.game.ProfileVisibility
import io.magicmobile.android.ranked.ProfileEmptyNote
import io.magicmobile.android.ranked.ProfilePalette
import io.magicmobile.android.ranked.ProfileSectionTitle
import io.magicmobile.android.ranked.PublicProfileScreen
import io.magicmobile.android.ranked.SocialNotice
import io.magicmobile.android.ranked.SocialPlayerHeading
import io.magicmobile.android.ranked.SocialRowCard
import io.magicmobile.android.ranked.SocialWaiting
import io.magicmobile.android.ranked.TavernFacePlaque
import io.magicmobile.android.ranked.leatherCard
import io.magicmobile.android.ranked.socialButton
import io.magicmobile.android.ranked.withRelation
import io.magicmobile.android.ui.BrandTheme
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.TavernButtonKind
import io.magicmobile.android.ui.TavernConfirmationDialog
import io.magicmobile.android.ui.TavernDialogAction
import io.magicmobile.android.ui.TavernMenu
import io.magicmobile.android.ui.TavernMenuEdge
import io.magicmobile.android.ui.TavernMenuItem
import io.magicmobile.android.ui.TavernPalette
import io.magicmobile.android.ui.TavernPanelTitle
import io.magicmobile.android.ui.TavernPlaqueButton
import io.magicmobile.android.ui.TavernSealButton
import io.magicmobile.android.ui.TavernTag
import io.magicmobile.android.ui.TavernTextField
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.sf
import io.magicmobile.android.ui.tavernTitleBar
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
 * Find players as you type, add friends, see who's online and join their tables in one tap, and open anyone's profile. All in the
 * tavern's leather and brass (FriendsView.swift).
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
    LaunchedEffect(Unit) {
        if (account.phase == PlayerAccount.Phase.READY) account.refresh() else account.start()
        io.magicmobile.android.ranked.SocialFixtures.openScreen?.let { screen ->
            val value = screen.substringAfter(":", "")
            if (screen.startsWith("public:") && value.isNotEmpty()) profileFor = value
            if (screen.startsWith("search:") && value.isNotEmpty()) query = value
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
    val parchment = TavernPalette.parchment

    Box(Modifier.fillMaxWidth()) {
        Column(Modifier.fillMaxWidth().imePadding()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = 6.dp).tavernTitleBar(), verticalAlignment = Alignment.CenterVertically) {
                TavernPanelTitle("Friends", Modifier.weight(1f).semantics { heading() })
                TavernSealButton(done, Modifier.testTag("friends.done"), contentDescription = "Done")
            }
            Column(Modifier.fillMaxWidth().heightIn(max = 640.dp).verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                when {
                    account.phase == PlayerAccount.Phase.UNAVAILABLE -> Column(Modifier.leatherCard(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(account.notice ?: PlayerAccountRules.message("offline"), color = parchment, style = sf(14f, SfWeight.regular, SfDesign.SERIF))
                        TavernPlaqueButton("Try again", { scope.launch { account.start() } }, Modifier.testTag("friends.retry"), kind = TavernButtonKind.SECONDARY)
                    }
                    account.phase != PlayerAccount.Phase.READY -> Box(Modifier.leatherCard()) { SocialWaiting("Loading your profile…") }
                    account.username == null || editingName -> Column(Modifier.leatherCard(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        ProfileSectionTitle("Your player name")
                        TavernTextField(nameDraft, { value -> nameDraft = value.filter { it in 'a'..'z' || it in 'A'..'Z' || it in '0'..'9' || it == '_' }.take(20) },
                            "Player name", Modifier.testTag("friends.nameField"))
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            TavernPlaqueButton(if (editingName) "Save name" else "Choose name", { scope.launch { if (account.claim(nameDraft)) editingName = false } },
                                Modifier.testTag("friends.saveName"), enabled = PlayerAccountRules.isValidUsername(nameDraft))
                            if (editingName) TavernPlaqueButton("Cancel", { editingName = false }, kind = TavernButtonKind.SECONDARY)
                        }
                        Text("Used at every table, and friends add you by it. 3–20 letters, numbers or underscores.", Modifier.alpha(0.7f), color = parchment,
                            style = sf(12f, SfWeight.regular, SfDesign.SERIF))
                    }
                    else -> {
                        Row(Modifier.leatherCard(), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            Row(Modifier.weight(1f).defaultMinSize(minHeight = 44.dp).socialButton("Your profile, ${account.username}", "friends.myProfile") { profileFor = account.username },
                                horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                                SfImage("person.crop.circle.fill", TavernPalette.brass, 30.dp)
                                Column {
                                    Text(account.username ?: "", color = parchment, style = sf(18f, SfWeight.black, SfDesign.SERIF))
                                    Text(if (account.visibilityKnown) "Profile: ${account.visibility.title}" else "Your name at every table", Modifier.alpha(0.7f), color = parchment,
                                        style = sf(12f, SfWeight.regular, SfDesign.SERIF))
                                }
                            }
                            TavernPlaqueButton("Change", { nameDraft = account.username ?: ""; editingName = true }, Modifier.testTag("friends.changeName"), kind = TavernButtonKind.SECONDARY)
                        }
                        // Search: live as you type, or, on a server without it, a plain "add by exact name".
                        Column(Modifier.leatherCard().testTag("friends.searchCard"), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            ProfileSectionTitle(if (account.searchAvailable) "Find players" else "Add a friend")
                            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterEnd) {
                                TavernTextField(query, { query = it.take(40) }, if (account.searchAvailable) "Start typing a player name" else "Their exact player name",
                                    Modifier.testTag(if (account.searchAvailable) "friends.search" else "friends.addField"))
                                if (query.isNotEmpty()) Box(Modifier.size(44.dp).socialButton("Clear search", "friends.search.clear") { query = "" }, contentAlignment = Alignment.Center) {
                                    SfImage("xmark.circle.fill", TavernPalette.ink.copy(alpha = 0.55f), 16.dp)
                                }
                            }
                            if (account.searchAvailable) {
                                val trimmed = query.trim()
                                if (trimmed.isEmpty() || PlayerSearchRules.normalized(trimmed) == null) Text(
                                    when {
                                        trimmed.isEmpty() -> "Type two or more letters of a player's name to see who's out there."
                                        trimmed.length < PlayerSearchRules.MINIMUM_LENGTH -> "Keep typing: two letters at least."
                                        else -> "Player names have letters, numbers and underscores only."
                                    }, Modifier.alpha(0.7f).testTag("friends.search.hint"), color = parchment, style = sf(12f, SfWeight.regular, SfDesign.SERIF))
                                else when (val state = search) {
                                    is SearchState.Failed -> Text(state.message, Modifier.testTag("friends.search.error"), color = ProfilePalette.win, style = sf(13f, SfWeight.semibold, SfDesign.SERIF))
                                    SearchState.Searching -> if (results.isEmpty()) SocialWaiting("Looking for players…")
                                    SearchState.Done -> if (results.isEmpty()) Box(Modifier.testTag("friends.search.empty")) { ProfileEmptyNote("No players found starting with “$trimmed”.", "magnifyingglass") }
                                    SearchState.Idle -> {}
                                }
                                if (results.isNotEmpty() && PlayerSearchRules.normalized(trimmed) != null) Column(Modifier.alpha(if (search == SearchState.Searching) 0.6f else 1f).testTag("friends.search.results"),
                                    verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                    for (result in results) ResultRow(result, { profileFor = result.username }, {
                                        results = results.map { if (it.username == result.username) it.withRelation("outgoing") else it }
                                        scope.launch {
                                            account.addFriend(result.username); account.refresh()
                                            // A request they had already sent you makes you friends at once.
                                            account.friends.firstOrNull { it.username == result.username }?.let { now -> results = results.map { if (it.username == result.username) it.withRelation(now.relation) else it } }
                                        }
                                    }, {
                                        account.friends.firstOrNull { it.username == result.username }?.let { friend ->
                                            results = results.map { if (it.username == result.username) it.withRelation("friend") else it }
                                            scope.launch { account.respond(friend, true) }
                                        }
                                    })
                                }
                            } else {
                                TavernPlaqueButton("Add friend", { val name = query; query = ""; scope.launch { account.addFriend(name) } }, Modifier.testTag("friends.add"), enabled = query.isNotBlank())
                                Text("Live search arrives with the next server update. Until then, add a friend by their exact player name.", Modifier.alpha(0.7f).testTag("friends.searchUnavailable"),
                                    color = parchment, style = sf(12f, SfWeight.regular, SfDesign.SERIF))
                            }
                        }
                        val incoming = account.friends.filter { it.isIncoming }
                        if (incoming.isNotEmpty()) Column(Modifier.leatherCard(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            ProfileSectionTitle("Requests", "${incoming.size}")
                            for (friend in incoming) SocialRowCard {
                                SocialPlayerHeading(friend.username, null, "Wants to be your friend", null, account.friendRanks[friend.username],
                                    Modifier.socialButton("${friend.username} wants to be your friend", "friends.request.${friend.username}") { profileFor = friend.username })
                                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                                    TavernPlaqueButton("Decline", { scope.launch { account.respond(friend, false) } }, Modifier.testTag("friends.decline.${friend.username}"), kind = TavernButtonKind.SECONDARY)
                                    TavernPlaqueButton("Accept", { scope.launch { account.respond(friend, true) } }, Modifier.testTag("friends.accept.${friend.username}"))
                                }
                            }
                        }
                        val friends = account.friends.filter { it.isFriend }
                        Column(Modifier.leatherCard().testTag("friends.list"), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            ProfileSectionTitle("Friends", if (friends.isEmpty()) null else "${account.onlineFriendCount} online")
                            if (friends.isEmpty()) ProfileEmptyNote("Search for a player above to add your first friend. You'll see when they're online and can join their tables.", "person.2.fill")
                            for (friend in friends) FriendRow(friend, account, myRankStep, challenge, { profileFor = friend.username }, join, done, { confirmBlock = friend }, scope)
                        }
                        val outgoing = account.friends.filter { it.isOutgoing }
                        if (outgoing.isNotEmpty()) Column(Modifier.leatherCard(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            ProfileSectionTitle("Sent", "${outgoing.size}")
                            for (friend in outgoing) SocialRowCard {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Text(friend.username, Modifier.weight(1f).defaultMinSize(minHeight = 44.dp).socialButton("${friend.username}, request sent", "friends.sent.${friend.username}") { profileFor = friend.username }
                                        .padding(vertical = 12.dp), color = parchment, style = sf(15f, SfWeight.heavy, SfDesign.SERIF))
                                    TavernPlaqueButton("Cancel", { scope.launch { account.remove(friend) } }, Modifier.testTag("friends.cancel.${friend.username}"), kind = TavernButtonKind.SECONDARY)
                                }
                            }
                        }
                        if (account.blocked.isNotEmpty()) Column(Modifier.leatherCard(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            ProfileSectionTitle("Blocked", "${account.blocked.size}")
                            for (name in account.blocked) SocialRowCard {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Text(name, Modifier.weight(1f), color = parchment, style = sf(15f, SfWeight.heavy, SfDesign.SERIF))
                                    TavernPlaqueButton("Unblock", { scope.launch { account.unblock(name) } }, Modifier.testTag("friends.unblock.$name"), kind = TavernButtonKind.SECONDARY)
                                }
                            }
                        }
                        Column(Modifier.padding(top = 6.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            TavernPlaqueButton("Delete my profile", { confirmDelete = true }, Modifier.testTag("friends.deleteAccount"), kind = TavernButtonKind.DANGER)
                            Text("Deletes your player name, friends, blocks and game history from MagicMobile's server. Your decks and games on this phone stay.",
                                Modifier.alpha(0.6f), color = parchment, style = sf(11f, SfWeight.regular, SfDesign.SERIF))
                        }
                    }
                }
            }
        }
        account.notice?.takeIf { account.phase == PlayerAccount.Phase.READY }?.let { SocialNotice(it, { account.notice = null }, Modifier.align(Alignment.BottomCenter)) }
    }

    profileFor?.let { name ->
        Dialog({ profileFor = null }, DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false, dismissOnBackPress = false)) {
            PublicProfileScreen(account, name, challenge?.let { handler -> { friendName, mode -> account.friends.firstOrNull { it.username == friendName }?.let { handler(it, mode) } } },
                myRankStep) { profileFor = null }
        }
    }
    confirmBlock?.let { friend ->
        TavernConfirmationDialog("Block ${friend.username}?", "They're removed from your friends and can't send you requests. You can unblock them here later.",
            listOf(TavernDialogAction("Block", destructive = true) { scope.launch { account.block(friend.username) } })) { confirmBlock = null }
    }
    if (confirmDelete) {
        TavernConfirmationDialog("Delete your profile?", "Your player name, friends and blocks are removed for good. A new profile starts the next time you open Friends.",
            listOf(TavernDialogAction("Delete profile", destructive = true) { scope.launch { if (account.deleteAccount()) done() } })) { confirmDelete = false }
    }
}

@Composable
private fun ResultRow(result: PlayerSearchResult, openProfile: () -> Unit, add: () -> Unit, accept: () -> Unit) {
    val parchment = TavernPalette.parchment
    val rank = result.position
    val relation = when (result.relation) {
        "friend" -> ", friend" + if (result.online == true) ", online" else ""
        "outgoing" -> ", request sent"; "incoming" -> ", wants to be your friend"; else -> ""
    }
    SocialRowCard {
        SocialPlayerHeading(result.username, result.favoriteCommander, result.favoriteCommander ?: if (result.visibility == ProfileVisibility.PUBLIC) "No games to show yet" else "Profile hidden",
            if (result.relation == "friend") result.online else null, rank,
            Modifier.socialButton("${result.username}${rank?.let { ", ${it.title}" } ?: ", unranked"}$relation", "friends.result.${result.username}") { openProfile() })
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            if (result.visibility != ProfileVisibility.PUBLIC) TavernTag(if (result.visibility == ProfileVisibility.FRIENDS) "FRIENDS ONLY" else "PRIVATE", leather = true)
            Spacer(Modifier.weight(1f))
            TavernPlaqueButton("Profile", openProfile, Modifier.testTag("friends.result.profile.${result.username}"), kind = TavernButtonKind.SECONDARY)
            when (result.relation) {
                "friend" -> TavernTag("FRIENDS", leather = true, accent = if (result.online == true) rgb(0.4, 0.85, 0.4) else null)
                "outgoing" -> TavernTag("REQUESTED", leather = true)
                "incoming" -> TavernPlaqueButton("Accept", accept, Modifier.testTag("friends.result.accept.${result.username}"))
                else -> TavernPlaqueButton("Add friend", add, Modifier.testTag("friends.result.add.${result.username}"))
            }
        }
    }
}

@Composable
private fun FriendRow(friend: PlayerFriend, account: PlayerAccount, myRankStep: Int?, challenge: ((PlayerFriend, PlayMode) -> Unit)?, openProfile: () -> Unit,
                      join: (String) -> Unit, done: () -> Unit, block: () -> Unit, scope: kotlinx.coroutines.CoroutineScope) {
    val rank = account.friendRanks[friend.username]
    SocialRowCard {
        SocialPlayerHeading(friend.username, null, friendStatus(friend), friend.online, rank,
            Modifier.socialButton("${friend.username}${rank?.let { ", ${it.title}" } ?: ""}, ${friendStatus(friend)}", "friends.card.${friend.username}") { openProfile() })
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End), verticalAlignment = Alignment.CenterVertically) {
            val code = friend.joinableCode
            if (code != null) TavernPlaqueButton("Join", { join(code); done() }, Modifier.testTag("friends.join.${friend.username}"))
            else if (challenge != null && friend.online) {
                val mayRank = myRankStep?.let { FriendChallengeRules.mayRank(it, rank?.step) } ?: false
                TavernMenu(Modifier.testTag("friends.challenge.${friend.username}"), TavernMenuEdge.BELOW, contentDescription = "Challenge ${friend.username}", label = { TavernFacePlaque("Challenge") }) {
                    TavernMenuItem("Quick Match", { challenge(friend, PlayMode.QUICK); done() }, systemImage = "bolt.fill")
                    TavernMenuItem(if (mayRank) "Ranked" else "Ranked · same tier only", { if (mayRank) { challenge(friend, PlayMode.RANKED); done() } }, systemImage = "shield.lefthalf.filled")
                }
            }
            TavernMenu(Modifier.testTag("friends.more.${friend.username}"), TavernMenuEdge.BELOW, contentDescription = "More about ${friend.username}", label = {
                Box(Modifier.size(44.dp), contentAlignment = Alignment.Center) { SfImage("ellipsis", TavernPalette.brass, 17.dp) }
            }) {
                TavernMenuItem("View profile", openProfile, systemImage = "person.crop.circle")
                TavernMenuItem("Remove friend", { scope.launch { account.remove(friend) } }, systemImage = "xmark.circle", destructive = true)
                TavernMenuItem("Block", block, systemImage = "hand.raised", destructive = true)
            }
        }
    }
}

private fun friendStatus(friend: PlayerFriend): String {
    if (friend.joinableCode != null) {
        val seats = friend.hostingOpenSeats ?: 1
        return if (seats == 1) "Hosting a table · 1 seat open" else "Hosting a table · $seats seats open"
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
