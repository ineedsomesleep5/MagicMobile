package io.magicmobile.android.social

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import io.magicmobile.android.board.ConfirmationAction
import io.magicmobile.android.board.ConfirmationDialog
import io.magicmobile.android.game.PlayerAccountRules
import io.magicmobile.android.game.PlayerFriend
import io.magicmobile.android.ui.BrandTheme
import io.magicmobile.android.ui.IosListSection
import io.magicmobile.android.ui.IosSheetHeader
import io.magicmobile.android.ui.IosTextButton
import io.magicmobile.android.ui.IosTextField
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.sf
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant

/** FriendsView.swift: your profile name, friends with who's online, requests, and joining a friend's table in one tap. */
@Composable
fun FriendsSheet(account: PlayerAccount, join: (String) -> Unit, myRankStep: Int? = null,
                 challenge: ((PlayerFriend, io.magicmobile.android.game.PlayMode) -> Unit)? = null, done: () -> Unit) {
    val scope = rememberCoroutineScope()
    var nameDraft by remember { mutableStateOf("") }
    var editingName by remember { mutableStateOf(false) }
    var friendDraft by remember { mutableStateOf("") }
    var confirmDelete by remember { mutableStateOf(false) }
    var actionsFor by remember { mutableStateOf<PlayerFriend?>(null) }
    var confirmBlock by remember { mutableStateOf<PlayerFriend?>(null) }
    var challengeFor by remember { mutableStateOf<PlayerFriend?>(null) }
    // A friend's ranked card: whose, and the card once it loads.
    var cardFor by remember { mutableStateOf<String?>(null) }
    var card by remember { mutableStateOf<PlayerProfileCard?>(null) }
    var cardLoading by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { if (account.phase == PlayerAccount.Phase.READY) account.refresh() else account.start() }
    val secondary = Color.White.copy(alpha = 0.55f)

    Column(Modifier.fillMaxWidth().imePadding()) {
        IosSheetHeader("Friends", done)
        Column(Modifier.fillMaxWidth().heightIn(max = 620.dp).verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp)) {
            when {
                account.phase == PlayerAccount.Phase.UNAVAILABLE -> IosListSection {
                    Text(account.notice ?: PlayerAccountRules.message("offline"), Modifier.padding(16.dp), color = Color.White, style = sf(15f))
                    IosTextButton("Try again", { scope.launch { account.start() } }, Modifier.padding(start = 8.dp), color = BrandTheme.ember)
                }
                account.phase != PlayerAccount.Phase.READY ->
                    Text("Loading your profile…", color = secondary, style = sf(15f))
                account.username == null || editingName -> IosListSection("Your player name",
                    "Used at every table, and friends add you by it. 3–20 letters, numbers or underscores.") {
                    IosTextField(nameDraft, { value -> nameDraft = value.filter { it in 'a'..'z' || it in 'A'..'Z' || it in '0'..'9' || it == '_' }.take(20) },
                        "Player name", Modifier.padding(horizontal = 16.dp).semantics { contentDescription = "friends.nameField" })
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        IosTextButton(if (editingName) "Save name" else "Choose name", {
                            scope.launch { if (account.claim(nameDraft)) editingName = false }
                        }, color = BrandTheme.ember, bold = true, enabled = PlayerAccountRules.isValidUsername(nameDraft))
                        if (editingName) IosTextButton("Cancel", { editingName = false }, color = secondary)
                    }
                }
                else -> {
                    IosListSection {
                        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(12.dp),
                            verticalAlignment = Alignment.CenterVertically) {
                            SfImage("person.crop.circle", BrandTheme.ember, 24.dp)
                            Column(Modifier.weight(1f)) {
                                Text(account.username ?: "", color = Color.White, style = sf(17f, SfWeight.semibold))
                                Text("Your name at every table", color = secondary, style = sf(12f))
                            }
                            IosTextButton("Change", { nameDraft = account.username ?: ""; editingName = true }, color = BrandTheme.ember)
                        }
                    }
                    IosListSection("Add a friend") {
                        Row(Modifier.padding(start = 16.dp, end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                            IosTextField(friendDraft, { friendDraft = it.take(20) }, "Their player name",
                                Modifier.weight(1f).semantics { contentDescription = "friends.addField" })
                            IosTextButton("Add", { val name = friendDraft; friendDraft = ""; scope.launch { account.addFriend(name) } },
                                color = BrandTheme.ember, bold = true, enabled = friendDraft.isNotBlank())
                        }
                    }
                    val incoming = account.friends.filter { it.isIncoming }
                    if (incoming.isNotEmpty()) IosListSection("Requests") {
                        incoming.forEach { friend ->
                            Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                                Text(friend.username, Modifier.weight(1f), color = Color.White, style = sf(17f))
                                IosTextButton("Accept", { scope.launch { account.respond(friend, true) } }, color = BrandTheme.ember, bold = true)
                                IosTextButton("Decline", { scope.launch { account.respond(friend, false) } }, color = secondary)
                            }
                        }
                    }
                    val friends = account.friends.filter { it.isFriend }
                    IosListSection(if (friends.isEmpty()) "Friends" else "Friends · ${account.onlineFriendCount} online",
                        "Long-press a friend to remove or block them.") {
                        if (friends.isEmpty()) Text("Add friends by their player name to see when they're online and join their tables.",
                            Modifier.padding(16.dp), color = secondary, style = sf(15f))
                        friends.forEach { friend ->
                            Row(Modifier.fillMaxWidth().clickable { actionsFor = friend }.padding(start = 16.dp, end = 8.dp, top = 8.dp, bottom = 8.dp),
                                horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                                Box(Modifier.size(10.dp).background(if (friend.online) Color(0xFF34C759) else Color.Gray.copy(alpha = 0.5f), CircleShape))
                                Column(Modifier.weight(1f)) {
                                    Text(friend.username, color = Color.White, style = sf(17f, SfWeight.semibold))
                                    Text(friendStatus(friend), color = secondary, style = sf(12f))
                                }
                                // Their ranked badge this season; tapping it opens their card.
                                val rank = account.friendRanks[friend.username]
                                Row(Modifier.defaultMinSize(minWidth = 44.dp, minHeight = 44.dp).clickable {
                                    cardFor = friend.username; card = null; cardLoading = true
                                    scope.launch { card = account.profileCard(friend.username); cardLoading = false }
                                }.semantics { contentDescription = rank?.let { "${friend.username}'s card, ${it.title}" } ?: "${friend.username}'s card" },
                                    horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                                    if (rank != null) {
                                        io.magicmobile.android.ranked.RankEmblem(rank.tier, 30.dp)
                                        Text(rank.title, color = Color.White, style = sf(12f, SfWeight.heavy))
                                    } else io.magicmobile.android.ui.SfImage("shield.lefthalf.filled", secondary, 18.dp)
                                }
                                friend.joinableCode?.let { code ->
                                    Box(Modifier.defaultMinSize(minHeight = 36.dp).background(BrandTheme.ember, RoundedCornerShape(18.dp))
                                        .clickable { join(code); done() }.padding(horizontal = 16.dp, vertical = 8.dp)
                                        .semantics { contentDescription = "Join ${friend.username}" }, contentAlignment = Alignment.Center) {
                                        Text("Join", color = Color.White, style = sf(15f, SfWeight.semibold))
                                    }
                                } ?: run {
                                    if (challenge != null && friend.online) Box(Modifier.size(44.dp).clickable { challengeFor = friend }
                                        .semantics { contentDescription = "Challenge ${friend.username}" }, contentAlignment = Alignment.Center) {
                                        SfImage("figure.fencing", BrandTheme.ember, 20.dp)
                                    }
                                }
                            }
                        }
                    }
                    val outgoing = account.friends.filter { it.relation == "outgoing" }
                    if (outgoing.isNotEmpty()) IosListSection("Sent") {
                        outgoing.forEach { friend ->
                            Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                                Text(friend.username, Modifier.weight(1f), color = Color.White, style = sf(17f))
                                IosTextButton("Cancel", { scope.launch { account.remove(friend) } }, color = BrandTheme.ember)
                            }
                        }
                    }
                    if (account.blocked.isNotEmpty()) IosListSection("Blocked") {
                        account.blocked.forEach { name ->
                            Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                                Text(name, Modifier.weight(1f), color = Color.White, style = sf(17f))
                                IosTextButton("Unblock", { scope.launch { account.unblock(name) } }, color = BrandTheme.ember)
                            }
                        }
                    }
                    IosListSection(footer = "Deletes your player name, friends and blocks from MagicMobile's server. Your decks and games on this phone stay.") {
                        IosTextButton("Delete my profile", { confirmDelete = true }, Modifier.padding(start = 8.dp), color = rgb(1.0, 0.27, 0.23))
                    }
                }
            }
            account.notice?.takeIf { account.phase == PlayerAccount.Phase.READY }?.let { notice ->
                Text(notice, Modifier.fillMaxWidth().background(rgb(0.2, 0.2, 0.22), RoundedCornerShape(20.dp)).clickable { account.notice = null }
                    .padding(horizontal = 14.dp, vertical = 10.dp), color = Color.White, style = sf(13f, SfWeight.semibold))
            }
        }
    }

    cardFor?.let { name ->
        io.magicmobile.android.board.BoardSheet({ cardFor = null }, background = io.magicmobile.android.ui.TavernPalette.leather) {
            io.magicmobile.android.ranked.PlayerCardSheet(name, card, cardLoading) { cardFor = null }
        }
    }
    // Quick Match for any online friend; Ranked only in the same tier (Gold with Gold).
    challengeFor?.let { friend ->
        val mayRank = myRankStep?.let { io.magicmobile.android.game.FriendChallengeRules.mayRank(it, account.friendRanks[friend.username]?.step) } ?: false
        ConfirmationDialog("Challenge ${friend.username}", if (mayRank) "Ranked counts for both of you." else "Ranked challenges need the same tier.",
            listOfNotNull(ConfirmationAction("Quick Match") { challenge?.invoke(friend, io.magicmobile.android.game.PlayMode.QUICK); done() },
                if (mayRank) ConfirmationAction("Ranked") { challenge?.invoke(friend, io.magicmobile.android.game.PlayMode.RANKED); done() } else null)) {
            challengeFor = null
        }
    }
    actionsFor?.let { friend ->
        ConfirmationDialog(friend.username, null, listOf(
            ConfirmationAction("Remove friend", destructive = true) { scope.launch { account.remove(friend) } },
            ConfirmationAction("Block") { confirmBlock = friend })) { actionsFor = null }
    }
    confirmBlock?.let { friend ->
        ConfirmationDialog("Block ${friend.username}?", "They're removed from your friends and can't send you requests. You can unblock them here later.",
            listOf(ConfirmationAction("Block", destructive = true) { scope.launch { account.block(friend.username) } })) { confirmBlock = null }
    }
    if (confirmDelete) {
        ConfirmationDialog("Delete your profile?", "Your player name, friends and blocks are removed for good. A new profile starts the next time you open Friends.",
            listOf(ConfirmationAction("Delete profile", destructive = true) { scope.launch { if (account.deleteAccount()) done() } })) { confirmDelete = false }
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
