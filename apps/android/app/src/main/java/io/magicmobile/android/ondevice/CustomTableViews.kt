package io.magicmobile.android.ondevice

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.magicmobile.android.BuildConfig
import io.magicmobile.android.board.ConfirmationAction
import io.magicmobile.android.board.ConfirmationDialog
import io.magicmobile.android.core.Deck
import io.magicmobile.android.game.AIDeck
import io.magicmobile.android.game.ArenaBoxGeometry
import io.magicmobile.android.game.ArenaCustomTable
import io.magicmobile.android.game.CommanderBracket
import io.magicmobile.android.game.TableJoinLink
import io.magicmobile.android.menus.ArenaButton
import io.magicmobile.android.menus.ArenaButtonKind
import io.magicmobile.android.menus.ArenaButtonText
import io.magicmobile.android.menus.ArenaCaps
import io.magicmobile.android.menus.ArenaDeckBox
import io.magicmobile.android.menus.ArenaDeckBoxModel
import io.magicmobile.android.menus.ArenaEmblem
import io.magicmobile.android.menus.ArenaGlass
import io.magicmobile.android.menus.ArenaMenuStyle
import io.magicmobile.android.menus.ArenaNewDeckBox
import io.magicmobile.android.menus.ArenaPillButton
import io.magicmobile.android.menus.ArenaPlayButton
import io.magicmobile.android.menus.ArenaSlider
import io.magicmobile.android.menus.ArenaStepper
import io.magicmobile.android.menus.arenaCard
import io.magicmobile.android.menus.arenaScrollFade
import io.magicmobile.android.ranked.TavernScreenHeader
import io.magicmobile.android.social.LocalPlayerAccount
import io.magicmobile.android.ui.AppPreferences
import io.magicmobile.android.ui.BrandPressable
import io.magicmobile.android.ui.CommanderDeckPortrait
import io.magicmobile.android.ui.FitText
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.TavernMenu
import io.magicmobile.android.ui.TavernMenuEdge
import io.magicmobile.android.ui.TavernMenuItem
import io.magicmobile.android.ui.TavernPicker
import io.magicmobile.android.ui.TavernPickerSection
import io.magicmobile.android.ui.TavernTextField
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.sf

/*
 * The custom table as Arena's event page (OnDeviceRootView.swift `setupContent`, `setupSeat`, `setupTable`, `setupSeats`,
 * `setupStartBar`, `RelayTablePanel`, `RelayWaitingRoomView`, `MatchRoomView`; Caleb, 2026-10-22): your deck on one glass
 * plate, the table on the other, and Start on a solid strip below them. Nothing scrolls under the strip, and nothing sits bare
 * on the room. Android has no Game Center: the players are AI or Online (relay tables).
 */

/** Everything the custom table shows and does; the root view owns the state. */
class CustomTableModel(
    val setup: OnDeviceSetupModel,
    val deck: Deck?,
    val deckID: String,
    val deckBox: ArenaDeckBoxModel?,
    val bracket: CommanderBracket?,
    val playerName: String,
    val setPlayerName: (String) -> Unit,
    val validName: Boolean,
    val online: Boolean,
    val setOnline: (Boolean) -> Unit,
    val aiPool: List<AIDeck>,
    val aiIDs: List<String>,
    val aiSections: List<TavernPickerSection<String>>,
    val selectAIDeck: (Int, String) -> Unit,
    val opponentCount: Int,
    val addSeat: () -> Unit,
    val removeSeat: (Int) -> Unit,
    val aiSkill: Int,
    val setAISkill: (Int) -> Unit,
    val startingMode: String,
    val setStartingMode: (String) -> Unit,
    val mayStart: Boolean,
    val onlinePlayers: Int,
    val setOnlinePlayers: (Int) -> Unit,
    val back: () -> Unit,
    val changeDeck: () -> Unit,
    val explainBracket: () -> Unit,
    val openStudio: (io.magicmobile.android.studio.DeckStudioOpen) -> Unit,
    val start: () -> Unit,
    val leave: () -> Unit,
    val hostOnline: () -> Unit,
    val joinOnline: (String) -> Unit,
    val readyOnline: () -> Unit,
) {
    /** In a match room the deck and name stay editable until the player taps Ready. */
    val editableInRoom: Boolean get() = (setup.multiplayer as? RelayTable)?.room?.let { !it.localReady } ?: false
    val locked: Boolean get() = setup.isBusy || setup.needsLeave
    val seatLocked: Boolean get() = setup.isBusy || (setup.needsLeave && !editableInRoom)
}

/** The event page: the header, the two plates (one card when upright), and the pinned strip with Start. */
@Composable
fun CustomTablePage(model: CustomTableModel) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val wide = maxWidth > maxHeight && LocalDensity.current.fontScale < 1.5f
        Column(Modifier.fillMaxSize()) {
            Column(Modifier.weight(1f).fillMaxWidth().windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal)),
                horizontalAlignment = Alignment.CenterHorizontally) {
                Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = 6.dp).alpha(if (model.locked) 0.45f else 1f)) {
                    TavernScreenHeader("Custom Table", back = { if (!model.locked) model.back() }, backTitle = "Main menu")
                }
                Box(Modifier.weight(1f).widthIn(max = 940.dp).fillMaxWidth().padding(horizontal = 16.dp).padding(top = 4.dp, bottom = 10.dp)) {
                    if (wide) Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        // Each plate keeps its frame; what doesn't fit scrolls inside it and fades at its foot.
                        Plate(Modifier.width(300.dp), 12.dp) { CustomTableSeat(model, wide = true) }
                        Plate(Modifier.weight(1f).testTag("lobby.scroll"), 14.dp) { CustomTableTable(model, wide = true) }
                    } else Plate(Modifier.fillMaxWidth().testTag("lobby.scroll"), 14.dp) {
                        CustomTableSeat(model, wide = false)
                        SetupRule()
                        CustomTableTable(model, wide = false)
                    }
                }
            }
            CustomTableStartBar(model)
        }
    }
}

@Composable
private fun Plate(modifier: Modifier, padding: Dp, content: @Composable ColumnScope.() -> Unit) {
    Box(modifier.fillMaxHeight().arenaCard(0.dp)) {
        Column(Modifier.fillMaxSize().arenaScrollFade(28.dp).verticalScroll(rememberScrollState()).padding(padding).padding(bottom = 20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp), content = content)
    }
}

/** Your seat: your deck as an open box, its bracket and check, your name on a plate, and Change deck. */
@Composable
private fun CustomTableSeat(model: CustomTableModel, wide: Boolean) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
        model.deckBox?.let { box ->
            val width = if (wide) 124f else 118f
            ArenaDeckBox(box, Modifier.padding(top = (ArenaBoxGeometry(width).rise * 1.6f + 4f).dp), selected = true, width = width.dp)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            model.bracket?.let { bracket ->
                Row(Modifier.defaultMinSize(minHeight = 30.dp).clickable(enabled = !model.seatLocked, role = Role.Button) { model.explainBracket() }
                    .testTag("play.deck.bracket"), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(bracket.title, color = ArenaMenuStyle.gold, style = ArenaMenuStyle.font(11f, SfWeight.bold))
                    SfImage("info.circle", ArenaMenuStyle.gold, 10.dp)
                }
            }
            io.magicmobile.android.studio.DeckStudioSetupDeckStatus(model.setup, model.deckID, model.deck, model.openStudio)
            NamePlate(model)
            ArenaPillButton("Change deck", model.changeDeck, enabled = !model.locked, identifier = "setup.changeDeck")
        }
    }
}

/** Your name written on the plate, as Arena shows it on an event page; until you sign in it can be written on, with a pencil and a gold line under it. */
@Composable
private fun NamePlate(model: CustomTableModel) {
    val profileName = LocalPlayerAccount.current?.username
    val editable = profileName == null
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 30.dp).drawBehind {
            if (editable) drawRect(ArenaMenuStyle.gold.copy(alpha = 0.45f), Offset(0f, size.height - 1.dp.toPx()), androidx.compose.ui.geometry.Size(size.width, 1.dp.toPx()))
        }, horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            val style = ArenaMenuStyle.font(17f, SfWeight.bold).copy(color = ArenaMenuStyle.text)
            BasicTextField(model.playerName, model.setPlayerName, Modifier.weight(1f).testTag("ondevice.playerName").semantics { contentDescription = "Player name" },
                enabled = editable && !model.seatLocked, singleLine = true, textStyle = style, cursorBrush = SolidColor(ArenaMenuStyle.gold),
                decorationBox = { inner ->
                    Box(contentAlignment = Alignment.CenterStart) {
                        if (model.playerName.isEmpty()) Text("Player name", color = ArenaMenuStyle.dim, style = style)
                        inner()
                    }
                })
            if (editable) SfImage("pencil", ArenaMenuStyle.gold, 12.dp)
        }
        // Only a name that can't be used says why (AGENTS.md: no helper lines the layout can carry).
        if (editable && !model.validName) SetupNote("Choose a name with 1–24 characters.")
    }
}

/** The table: who sits at it, then for the AI the seats, its skill and who goes first. */
@Composable
private fun CustomTableTable(model: CustomTableModel, wide: Boolean) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (wide && !model.online) {
            Row(horizontalArrangement = Arrangement.spacedBy(18.dp), verticalAlignment = Alignment.Top) {
                Column(Modifier.weight(1f).padding(bottom = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    SetupPlayers(model); SetupRule(); ArenaCaps("Seats"); SetupSeats(model)
                }
                Column(Modifier.widthIn(max = 240.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    SetupSkill(model); SetupRule(); SetupFirst(model)
                }
            }
        } else {
            SetupPlayers(model)
            if (model.online) OnlineTable(model)
            else {
                SetupRule(); ArenaCaps("Seats"); SetupSeats(model)
                SetupRule(); SetupSkill(model)
                SetupRule(); SetupFirst(model)
            }
        }
        SetupRecovery(model)
    }
}

@Composable
private fun SetupPlayers(model: CustomTableModel) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        ArenaCaps("Players")
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            SetupTile("AI", "cpu", !model.online, "setup.mode.ai", !model.locked) { model.setOnline(false) }
            SetupTile("Online", "globe", model.online, "setup.mode.online", !model.locked) { model.setOnline(true) }
        }
    }
}

@Composable
private fun SetupSkill(model: CustomTableModel) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            ArenaCaps("AI skill")
            Spacer(Modifier.weight(1f))
            Text("${model.aiSkill}", color = ArenaMenuStyle.gold, style = ArenaMenuStyle.font(15f, SfWeight.bold).copy(fontFeatureSettings = "tnum"))
        }
        Box(Modifier.alpha(if (model.locked) 0.5f else 1f)) {
            ArenaSlider(model.aiSkill.toFloat(), { if (!model.locked) model.setAISkill(Math.round(it).coerceIn(1, 10)) }, "AI skill", range = 1f..10f,
                identifier = "onDevice.aiSkill", valueText = "AI skill: ${model.aiSkill}")
        }
    }
}

@Composable
private fun SetupFirst(model: CustomTableModel) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        ArenaCaps("Who goes first")
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            SetupTile("Choose", "hand.point.up.left.fill", model.startingMode == "choose", "setup.first.choose", !model.locked) { model.setStartingMode("choose") }
            SetupTile("Roll D20", "dice.fill", model.startingMode == "roll", "setup.first.roll", !model.locked) { model.setStartingMode("roll") }
        }
    }
}

/** The AI seats as deck boxes: tap one for its deck, its × empties it, and a "+" seat adds an opponent. */
@Composable
private fun SetupSeats(model: CustomTableModel) {
    // Room above and beside the boxes for each seat's ×, which the scroll would otherwise clip.
    Row(Modifier.horizontalScroll(rememberScrollState()).padding(top = 12.dp, end = 12.dp, bottom = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Bottom) {
        for (index in 0 until ArenaCustomTable.seatCount(model.opponentCount)) SetupSeat(model, index)
        if (ArenaCustomTable.canAddSeat(model.opponentCount)) {
            // The box is the seat; its name plate and the "+" say enough (no captions under them).
            BrandPressable({ GameAudio.play(GameSound.UI_TAP); model.addSeat() },
                Modifier.testTag("ondevice.aiSeat.add").semantics { contentDescription = "Add an AI opponent"; role = Role.Button }, enabled = !model.locked) {
                ArenaNewDeckBox(width = 70.dp)
            }
        }
    }
}

@Composable
private fun SetupSeat(model: CustomTableModel, index: Int) {
    val selection = model.aiIDs.getOrElse(index) { "" }
    val deck = model.aiPool.firstOrNull { it.id == selection }
    Box {
        TavernMenu(Modifier.testTag("ondevice.aiDeck.${index + 1}"), edge = TavernMenuEdge.BELOW, enabled = !model.locked, scrollHeight = 420.dp,
            contentDescription = "AI ${index + 1} deck, ${deck?.name ?: "Choose"}", label = {
                ArenaDeckBox(ArenaDeckBoxModel(deck?.id ?: "seat-$index", deck?.name ?: "Choose a deck", deck?.commander,
                    deck?.colors?.map { it.toString() } ?: emptyList(), deck?.bracket?.label ?: ""), width = 70.dp)
            }) {
            for (section in model.aiSections) {
                section.title?.let { ArenaCaps(it, 9.5f, Modifier.padding(top = 4.dp)) }
                for ((label, value) in section.options) {
                    TavernMenuItem(label, { model.selectAIDeck(index, value) }, systemImage = if (value == selection) "checkmark" else null)
                }
            }
        }
        if (ArenaCustomTable.canRemoveSeat(model.opponentCount)) {
            Box(Modifier.align(Alignment.TopEnd).offset(x = 10.dp, y = (-10).dp).size(34.dp)
                .clickable(enabled = !model.locked, role = Role.Button) { GameAudio.play(GameSound.UI_TAP); model.removeSeat(index) }
                .semantics { contentDescription = "Remove AI ${index + 1}" }.testTag("ondevice.aiSeat.remove.${index + 1}"),
                contentAlignment = Alignment.Center) {
                Box(Modifier.size(20.dp).background(Color.Black.copy(alpha = 0.85f), CircleShape).border(0.8.dp, ArenaGlass.hairline, CircleShape),
                    contentAlignment = Alignment.Center) { SfImage("xmark", ArenaMenuStyle.text, 9.dp) }
            }
        }
    }
}

/** A choice as a tile: an emblem in a glass circle over its name, lit when chosen. */
@Composable
private fun SetupTile(title: String, symbol: String, on: Boolean, identifier: String, enabled: Boolean, action: () -> Unit) {
    val shape = RoundedCornerShape(10.dp)
    Column(Modifier.widthIn(max = 110.dp).clickable(enabled = enabled, role = Role.Button) { GameAudio.play(GameSound.UI_TAP); action() }
        .semantics { contentDescription = title; selected = on }.testTag(identifier)
        .then(if (on) Modifier.background(Color.White.copy(alpha = 0.07f), shape).border(0.8.dp, ArenaGlass.hairline, shape) else Modifier)
        .padding(horizontal = 10.dp, vertical = 8.dp).alpha(if (enabled) 1f else 0.6f),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Box(Modifier.size(38.dp).background(Color.Black.copy(alpha = 0.5f), CircleShape)
            .border(if (on) 1.6.dp else 0.9.dp, if (on) ArenaMenuStyle.metal else ArenaGlass.hairline, CircleShape), contentAlignment = Alignment.Center) {
            ArenaEmblem(symbol, 17.dp, lit = on)
        }
        FitText(title, ArenaMenuStyle.font(12f, SfWeight.semibold), color = if (on) Color.White else ArenaMenuStyle.dim, minimumScale = 0.8f)
    }
}

@Composable
private fun SetupRule() {
    Box(Modifier.fillMaxWidth().padding(vertical = 2.dp).height(1.dp).alpha(0.3f).background(ArenaGlass.hairline))
}

@Composable
private fun SetupNote(text: String) = Text(text, color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(11.5f, SfWeight.medium))

@Composable
private fun SetupRecovery(model: CustomTableModel) {
    val setup = model.setup
    if (setup.needsLeave) ArenaPillButton("Leave / retry closing", model.leave, enabled = !setup.isBusy && !setup.session.isWorking)
    if (setup.identity == null) ArenaPillButton("Retry loading local catalogue", { setup.prepare() })
    OnDeviceDiagnosticsEntry(setup)
    if (!BuildConfig.NATIVE_ENGINE) SetupNote("This build has no native engine. Install the full APK to play.")
}

/** The pinned strip: what the table is doing, and Start in the corner, as Arena pins Play. A solid dark strip below the plates. */
@Composable
private fun CustomTableStartBar(model: CustomTableModel) {
    Box(Modifier.fillMaxWidth()
        .background(Brush.verticalGradient(listOf(rgb(0.06, 0.06, 0.075), Color.Black)))
        .drawBehind { drawRect(ArenaGlass.hairline, alpha = 0.6f, size = androidx.compose.ui.geometry.Size(size.width, 1.dp.toPx())) }) {
        Row(Modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal + WindowInsetsSides.Bottom))
            .padding(horizontal = 20.dp, vertical = 9.dp).defaultMinSize(minHeight = 46.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            // The idle line said only what the page shows; the strip speaks when the table is doing something.
            Text(ArenaCustomTable.stripStatus(model.setup.status), Modifier.weight(1f), color = ArenaMenuStyle.dim,
                style = ArenaMenuStyle.font(12f, SfWeight.medium), maxLines = 2)
            if (!model.online) Box(Modifier.semantics(mergeDescendants = true) { contentDescription = "Start game" }) {
                ArenaPlayButton("Start", model.start, Modifier.size(200.dp, 46.dp), fontSize = 21f, enabled = model.mayStart, identifier = "setup.start")
            }
        }
    }
}

/** Online: host or join a cross-play table, then the people at it and the match room (RelayTablePanel). */
@Composable
private fun OnlineTable(model: CustomTableModel) {
    val setup = model.setup
    val context = LocalContext.current
    val table = setup.multiplayer as? RelayTable
    var storedAICount by AppPreferences.int("magicmobile.relay.aiOpponentCount", 0)
    val players = model.onlinePlayers
    val aiCount = storedAICount.coerceIn(0, maxOf(0, 4 - players))
    val code = setup.relayJoinCode
    val locked = model.locked
    val mayEnter = model.deck != null && model.validName && setup.identity != null && !locked
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (table == null) {
            TavernPicker("Human players", players, listOf(TavernPickerSection(null, (2..4).map { "$it players" to it })), model.setOnlinePlayers, enabled = !locked)
            ArenaStepper("AI opponents: $aiCount", aiCount, 0..maxOf(0, 4 - players), { storedAICount = it }, identifier = "ondevice.relay.aiCount", enabled = !locked)
            for (index in 0 until aiCount) {
                TavernPicker("AI ${index + 1} deck", model.aiIDs.getOrElse(index) { "" }, model.aiSections, { model.selectAIDeck(index, it) }, enabled = !locked)
            }
            if (aiCount > 0) {
                ArenaStepper("AI skill: ${model.aiSkill}", model.aiSkill, 1..10, model.setAISkill, enabled = !locked)
                SetupNote("The host’s AI choices apply to everyone. Higher skill may slow turns.")
            }
            SetupNote("Share the invite link, or friends type the table code. Every player needs this app version and keeps it open during the match.")
            ArenaPlayButton("Host a table", model.hostOnline, Modifier.fillMaxWidth().height(46.dp), fontSize = 18f, enabled = mayEnter, identifier = "ondevice.relay.host")
            OrJoinDivider()
            TavernTextField(code, { value -> setup.relayJoinCode = value.uppercase().filter { it in TableJoinLink.ALPHABET }.take(6) }, "Table code",
                Modifier.testTag("ondevice.relay.code").semantics { contentDescription = "Table code" }, enabled = !locked)
            ArenaButton({ model.joinOnline(code) }, kind = ArenaButtonKind.SECONDARY, fullWidth = true, enabled = mayEnter && code.length == 6,
                identifier = "ondevice.relay.join") { ArenaButtonText("Join table") }
        } else {
            table.tableCode?.let { tableCode ->
                Column(Modifier.fillMaxWidth().roomPanel().padding(12.dp), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    ArenaCaps("Table code", 10.5f)
                    Text(tableCode.chunked(3).joinToString(" "), Modifier.testTag("ondevice.relay.tableCode").semantics { contentDescription = "Table code $tableCode" },
                        color = ArenaMenuStyle.text, style = sf(34f, SfWeight.black, SfDesign.SERIF, tracking = 3f))
                    if (table.room == null && table.endpoint == null && !table.isFailed) {
                        Text("Players ${table.seatsTaken}/${table.seatsWanted.coerceAtLeast(2)}", color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(12f, SfWeight.medium))
                        Row(Modifier.defaultMinSize(minHeight = 44.dp).clickable(role = Role.Button) {
                            val link = TableJoinLink.url(tableCode) ?: return@clickable
                            val send = Intent(Intent.ACTION_SEND).apply {
                                type = "text/plain"
                                putExtra(Intent.EXTRA_SUBJECT, "Join my MagicMobile table")
                                putExtra(Intent.EXTRA_TEXT, "Tap to join my MagicMobile table (code $tableCode): $link")
                            }
                            runCatching { context.startActivity(Intent.createChooser(send, "Share invite link")) }
                        }.testTag("ondevice.relay.share"), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                            SfImage("square.and.arrow.up", ArenaMenuStyle.gold, 14.dp)
                            Text("Share invite link", color = ArenaMenuStyle.gold, style = ArenaMenuStyle.font(15f, SfWeight.semibold))
                        }
                    }
                }
            }
            Text(table.status, color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(13f, SfWeight.medium))
            if (table.room == null && table.endpoint == null && !table.isFailed && table.waitingSeats.isNotEmpty()) {
                RelayWaitingRoomView(table.waitingSeats) { table.removeFromTable(it) }
            }
            table.room?.let { room -> MatchRoomView(room, model.deck?.name, model.deck?.commanderName, model.readyOnline) }
        }
    }
}

@Composable
private fun OrJoinDivider() {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.weight(1f)) { SetupRule() }
        Text("or join", color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(12f, SfWeight.semibold))
        Box(Modifier.weight(1f)) { SetupRule() }
    }
}

/** The rooms' recessed panel: black glass in the gold hairline. */
private fun Modifier.roomPanel(): Modifier = this
    .background(Color.Black.copy(alpha = 0.45f), RoundedCornerShape(12.dp))
    .border(0.8.dp, Brush.verticalGradient(listOf(ArenaGlass.hairlineTop.copy(alpha = 0.5f), ArenaGlass.hairlineBottom.copy(alpha = 0.4f))), RoundedCornerShape(12.dp))

/** HOST on a seat: gold capitals on a dark capsule. */
@Composable
private fun HostTag() {
    Text("HOST", Modifier.background(Color.Black.copy(alpha = 0.6f), CircleShape).border(0.8.dp, ArenaGlass.hairline, CircleShape)
        .padding(horizontal = 7.dp, vertical = 2.dp), color = ArenaMenuStyle.gold, style = ArenaMenuStyle.font(10f, SfWeight.heavy))
}

/** A relay table that is still filling: who has joined and, for the host, a Remove control per joiner (RelayWaitingRoomView). */
@Composable
private fun RelayWaitingRoomView(seats: List<RelayWaitingSeat>, remove: (String) -> Unit) {
    var removal by remember { mutableStateOf<RelayWaitingSeat?>(null) }
    Column(Modifier.fillMaxWidth().roomPanel().padding(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        ArenaCaps("At the table")
        seats.forEachIndexed { index, seat ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                SfImage(if (seat.connected) "person.crop.circle" else "wifi.exclamationmark", ArenaMenuStyle.gold, 18.dp)
                Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(seat.name, color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(15f, SfWeight.bold))
                        if (seat.isHost) HostTag()
                    }
                    Text(if (seat.isLocal) "You" else if (seat.connected) "Joined" else "Reconnecting…", color = ArenaMenuStyle.dim,
                        style = ArenaMenuStyle.font(12f, SfWeight.medium))
                }
                if (seat.removable) {
                    Box(Modifier.defaultMinSize(minWidth = 44.dp, minHeight = 44.dp).clickable(role = Role.Button) { removal = seat }
                        .semantics { contentDescription = "Remove ${seat.name}" }.testTag("ondevice.relay.remove.${index + 1}"), contentAlignment = Alignment.Center) {
                        Text("Remove", color = ArenaMenuStyle.loss, style = ArenaMenuStyle.font(14f, SfWeight.semibold))
                    }
                }
            }
        }
        if (seats.any { it.removable }) SetupNote("Remove anyone you did not invite. The match room opens when every seat is taken.")
    }
    removal?.let { seat ->
        ConfirmationDialog("Remove ${seat.name} from the table?", "Their seat opens for someone else. Anyone with the code can still join.",
            listOf(ConfirmationAction("Remove", destructive = true) { remove(seat.id) })) { removal = null }
    }
}

/** The relay pregame room: who is here, who is ready, and their commanders (MatchRoomView). */
@Composable
private fun MatchRoomView(room: RelayTable.MatchRoom, deckName: String?, localCommander: String?, ready: () -> Unit) {
    Column(Modifier.fillMaxWidth().roomPanel().padding(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        ArenaCaps("Match room")
        for (player in room.players) {
            val commanders = if (player.isLocal && !room.localReady) listOfNotNull(localCommander) else player.commanders
            Row(Modifier.semantics(mergeDescendants = true) { contentDescription = "${player.name}, ${if (player.isReady) "ready" else "not ready"}" },
                horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                CommanderDeckPortrait(commanders.firstOrNull(), Modifier.size(40.dp, 56.dp).alpha(if (player.isReady) 1f else 0.4f))
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(player.name, color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(15f, SfWeight.bold))
                        if (player.isHost) HostTag()
                    }
                    Text(if (commanders.isEmpty()) (if (player.isReady) "Ready" else "Choosing a deck…") else commanders.joinToString(" & "),
                        color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(12f, SfWeight.medium), maxLines = 2)
                }
                SfImage(if (player.isReady) "checkmark.circle.fill" else "hourglass", if (player.isReady) ArenaMenuStyle.gold else ArenaMenuStyle.dim, 20.dp)
            }
        }
        room.aiSummary?.let { Text(it, color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(12f, SfWeight.medium)) }
        if (room.localReady) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                SfImage("checkmark.seal.fill", ArenaMenuStyle.gold, 16.dp)
                Text("You're ready. The game starts when everyone is.", color = ArenaMenuStyle.gold, style = ArenaMenuStyle.font(13f, SfWeight.semibold))
            }
        } else {
            Text("Pick your deck above, then ready up${deckName?.let { " with $it" } ?: ""}.", color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(12f, SfWeight.medium))
            ArenaPlayButton("Ready", ready, Modifier.fillMaxWidth().height(46.dp), fontSize = 18f, enabled = deckName != null, identifier = "ondevice.matchRoom.ready")
        }
    }
}
