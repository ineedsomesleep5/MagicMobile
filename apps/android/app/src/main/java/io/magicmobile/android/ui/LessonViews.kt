package io.magicmobile.android.ui

import android.content.Context
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import io.magicmobile.android.game.BoardRect
import io.magicmobile.android.board.centerAt
import io.magicmobile.android.game.LessonCatalog
import io.magicmobile.android.game.LessonCoach
import io.magicmobile.android.game.LessonFrame
import io.magicmobile.android.game.LessonInfo
import io.magicmobile.android.game.LessonListener
import io.magicmobile.android.game.LessonScript
import io.magicmobile.android.game.LessonSpot
import io.magicmobile.android.game.LessonText
import io.magicmobile.android.game.EngineJson
import io.magicmobile.android.game.array
import io.magicmobile.android.game.get
import io.magicmobile.android.game.string
import io.magicmobile.android.menus.ArenaGlass
import io.magicmobile.android.menus.ArenaMenuStyle
import io.magicmobile.android.menus.ArenaPanelHeader
import kotlin.math.roundToInt

/** The lessons and their recordings, from the app's assets (iOS Lessons.swift reads the same files from its bundle). */
object LessonAssets {
    private var cached: List<LessonInfo>? = null
    fun all(context: Context): List<LessonInfo> = cached ?: runCatching {
        LessonCatalog.parse(context.assets.open("lessons/lessons.json").use { it.readBytes() })
    }.getOrDefault(emptyList()).also { cached = it }

    fun script(context: Context, id: String): LessonScript =
        LessonScript(EngineJson.decode(context.assets.open("lessons/lesson-$id.json").use { it.readBytes() }))

    /** Lessons finished on this device, kept like iOS's string array (comma-joined here). */
    fun completed(): Set<String> = AppPreferences.string(LessonCatalog.KEY, "").value.split(',').filter { it.isNotEmpty() }.toSet()
    fun complete(id: String) { AppPreferences.string(LessonCatalog.KEY, "").value = (completed() + id).sorted().joinToString(",") }
}

/** The coach's state for the board (iOS LessonRun): the frame's note, a nudge after a wrong move, the finish. */
class LessonRun(val lesson: LessonInfo) : LessonListener {
    var coach by mutableStateOf<LessonCoach?>(null); private set
    var waitsForGotIt by mutableStateOf(false); private set
    /** The player the board must switch to before the lesson goes on (a swap step), by engine ID. */
    var waitsForFocus by mutableStateOf<String?>(null); private set
    var complete by mutableStateOf(false); private set
    var nudges by mutableIntStateOf(0); private set
    var focus by mutableStateOf(LessonSpot.Focus()); private set
    /** The coach points at the opponents' side of the table. */
    var spotIsAcross by mutableStateOf(false); private set
    /** What the board has open (LessonBoardCover), reported by the board. */
    var boardCover by mutableStateOf(io.magicmobile.android.game.LessonBoardCover.NONE); private set
    val placement: io.magicmobile.android.game.LessonCoachPlacement
        get() = io.magicmobile.android.game.LessonPlacement.of(boardCover, spotIsAcross, complete || waitsForGotIt)

    fun boardCovered(cover: io.magicmobile.android.game.LessonBoardCover) { if (boardCover != cover) boardCover = cover }
    /** Lets the lesson go on after a note; set by the root once the transport exists. */
    var release: (() -> Unit)? = null

    fun gotIt() { if (waitsForGotIt) { waitsForGotIt = false; release?.invoke() } }

    /** The board now shows this opponent at the top: a swap step it was waiting for goes on. */
    fun boardFocused(playerID: String) {
        if (waitsForFocus == null || waitsForFocus != playerID) return
        waitsForFocus = null; waitsForGotIt = true; gotIt()
    }

    override fun show(frame: LessonFrame) {
        if (frame.complete || frame.ended) {
            if (!complete) LessonAssets.complete(lesson.id)
            complete = true
        }
        // A frame without a note of its own keeps the last one up while its move is still to make.
        if (frame.coach != null) coach = frame.coach else if (frame.expect == null && !frame.note) coach = null
        val focusID = frame.focus?.let { name ->
            frame.poll["snapshot"]["gameView"]["players"].array?.firstOrNull { it["name"].string == name }?.get("playerId").string
        }
        waitsForFocus = focusID
        waitsForGotIt = frame.note && focusID == null
        // A swap step also rings the opponent to switch to, in the player card's swap row.
        focus = LessonSpot.resolve(frame.coach?.spot, frame.poll, frame.expect).let { if (focusID == null) it else it.copy(ids = it.ids + focusID) }
        spotIsAcross = io.magicmobile.android.game.LessonPlacement.across(focus.ids, frame.poll)
    }

    override fun nudge() { nudges += 1 }
}

/** The ring the coach draws around what to touch next (board coordinates, dp): a brass glow that breathes. */
@Composable
fun LessonFocusRing(rect: BoardRect, circle: Boolean = false) {
    val breathe = if (LaunchEnvironment.reduceMotion) 0f else rememberInfiniteTransition(label = "lesson-ring")
        .animateFloat(0f, 1f, infiniteRepeatable(tween(800), RepeatMode.Reverse), label = "lesson-ring-breathe").value
    Canvas(Modifier.centerAt(rect.midX, rect.midY).requiredSize((rect.width + 12).dp, (rect.height + 12).dp)
        .graphicsLayer { val s = 1f + 0.05f * breathe; scaleX = s; scaleY = s }) {
        val glow = ArenaMenuStyle.gold.copy(alpha = 0.35f + 0.3f * breathe)
        if (circle) {
            drawCircle(glow, size.minDimension / 2, style = Stroke(9.dp.toPx()))
            drawCircle(ArenaMenuStyle.gold, size.minDimension / 2, style = Stroke(3.dp.toPx()))
        } else {
            val radius = CornerRadius(10.dp.toPx())
            drawRoundRect(glow, cornerRadius = radius, style = Stroke(9.dp.toPx()))
            drawRoundRect(ArenaMenuStyle.gold, cornerRadius = radius, style = Stroke(3.dp.toPx()))
        }
    }
}

/**
 * Maren's note at the top of the table (iOS LessonCoachCard): the moment's title and a sentence or two; Got it on a note, and
 * Next Lesson and Done once the lesson is over. A wrong move shakes the card and says so.
 */
@Composable
fun LessonCoachCard(run: LessonRun, nextTitle: String, next: (() -> Unit)?, done: () -> Unit, modifier: Modifier = Modifier) {
    if (!run.complete && run.coach == null) return
    // The player opened the tucked chip: the card shows until the next note or the panel closes.
    var untucked by remember(run.coach, run.boardCover) { mutableStateOf(false) }
    val placement = run.placement.let { if (it == io.magicmobile.android.game.LessonCoachPlacement.TUCKED && untucked) io.magicmobile.android.game.LessonCoachPlacement.LOW else it }
    androidx.compose.foundation.layout.BoxWithConstraints(modifier.fillMaxWidth()) {
        // Low: under a player's card at the top and above your hand and the corner buttons.
        val top by androidx.compose.animation.core.animateDpAsState(
            if (placement == io.magicmobile.android.game.LessonCoachPlacement.LOW) maxHeight * 0.5f else 0.dp,
            if (LaunchEnvironment.reduceMotion) tween(150) else spring(0.8f, 380f), label = "lesson-coach-place")
        androidx.compose.animation.AnimatedContent(placement == io.magicmobile.android.game.LessonCoachPlacement.TUCKED, Modifier.fillMaxWidth().padding(top = top.coerceAtLeast(0.dp)),
            transitionSpec = {
                (androidx.compose.animation.fadeIn(tween(220)) + androidx.compose.animation.scaleIn(initialScale = 0.85f))
                    .togetherWith(androidx.compose.animation.fadeOut(tween(150)) + androidx.compose.animation.scaleOut(targetScale = 0.85f))
            }, contentAlignment = Alignment.TopCenter, label = "lesson-coach-tuck") { tucked ->
            if (tucked) LessonCoachChip(run) { untucked = true } else LessonCoachNote(run, nextTitle, next, done)
        }
    }
}

/** Tucked while a panel is open: Maren's name and the step's title in a small glass chip; a tap opens the card. */
@Composable
private fun LessonCoachChip(run: LessonRun, open: () -> Unit) {
    Row(Modifier.wrapContentWidth().clickable(onClickLabel = "Shows the note", onClick = open).tavernPanelChrome(tavern = true, cornerRadius = 18.dp)
        .testTag("lesson.chip").padding(horizontal = 10.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        TavernTag(LessonText.COACH.uppercase(), accent = TavernPalette.ember)
        Text(run.coach?.title ?: run.lesson.title, color = TavernPalette.parchment, style = sf(13f, SfWeight.semibold, SfDesign.SERIF), maxLines = 1)
    }
}

@Composable
private fun LessonCoachNote(run: LessonRun, nextTitle: String, next: (() -> Unit)?, done: () -> Unit, modifier: Modifier = Modifier) {
    val coach = run.coach
    if (!run.complete && coach == null) return
    val shake = remember { Animatable(0f) }
    var nudged by remember(coach) { mutableStateOf(false) }
    // Only a new wrong move: the card leaves the table between notes and must not replay an old one when it comes back.
    var seenNudges by remember { mutableIntStateOf(run.nudges) }
    LaunchedEffect(run.nudges) {
        if (run.nudges == seenNudges) return@LaunchedEffect
        seenNudges = run.nudges
        nudged = true
        shake.snapTo(10f); shake.animateTo(0f, spring(0.25f, 900f))
    }
    Column(modifier.offset { IntOffset((shake.value * density).roundToInt(), 0) }.padding(horizontal = 16.dp).widthIn(max = 420.dp).fillMaxWidth()
        .glow(Color.Black.copy(alpha = 0.55f), 10.dp, 12.dp)
        .tavernPanelChrome(tavern = true, cornerRadius = 12.dp)
        .testTag("lesson.coach")
        .padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            TavernTag(LessonText.COACH.uppercase(), accent = TavernPalette.ember)
            TavernPanelTitle(if (run.complete) LessonText.COMPLETE else coach?.title ?: run.lesson.title, Modifier.semantics { heading() })
        }
        Text(if (nudged) LessonText.NUDGE else if (run.complete && coach == null) LessonText.ALL_COMPLETE else coach?.text ?: "",
            Modifier.testTag("lesson.coach.text"), color = TavernPalette.parchment, style = sf(14f, SfWeight.medium, SfDesign.SERIF))
        if (run.complete) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                TavernPlaqueButton(LessonText.DONE, done, Modifier.testTag("lesson.done"), TavernButtonKind.SECONDARY)
                Spacer(Modifier.weight(1f))
                if (next != null) TavernPlaqueButton(nextTitle, next, Modifier.testTag("lesson.next"))
            }
        } else if (run.waitsForGotIt) {
            Row(Modifier.fillMaxWidth()) {
                Spacer(Modifier.weight(1f))
                TavernPlaqueButton(LessonText.GOT_IT, { run.gotIt() }, Modifier.testTag("lesson.gotIt"))
            }
        }
    }
}

/** The lessons in order, a check on each one finished, then the guided game (iOS LessonListView). */
@Composable
fun LessonListView(lessons: List<LessonInfo>, play: (String) -> Unit, playGuided: (() -> Unit)?, back: () -> Unit) {
    val completed = remember { LessonAssets.completed() }
    val firstUnfinished = lessons.firstOrNull { it.id !in completed }?.id
    Column(Modifier.fillMaxWidth()) {
        ArenaPanelHeader(LessonText.TITLE, back = back, closeIdentifier = "lessons.close")
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally) {
            Column(Modifier.widthIn(max = 560.dp).fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                lessons.forEachIndexed { index, lesson ->
                    LessonRow("${index + 1}", lesson.title, lesson.id in completed, lesson.id == firstUnfinished, "lessons.${lesson.id}") { play(lesson.id) }
                }
                if (playGuided != null) LessonRow("${lessons.size + 1}", LessonText.GUIDED, false, firstUnfinished == null, "lessons.guided", playGuided)
            }
        }
    }
}

@Composable
private fun LessonRow(number: String, title: String, done: Boolean, next: Boolean, tag: String, action: () -> Unit) {
    val shape = RoundedCornerShape(12.dp)
    Row(Modifier.fillMaxWidth().background(Color.Black.copy(alpha = 0.45f), shape).border(1.dp, ArenaGlass.hairline, shape)
        .clickable(role = Role.Button, onClick = action)
        .semantics(mergeDescendants = true) { contentDescription = if (done) "$title, finished" else title }
        .testTag(tag).padding(12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Box(Modifier.size(38.dp).background(Color.Black.copy(alpha = 0.7f), CircleShape)
            .then(if (next) Modifier.border(1.5.dp, ArenaMenuStyle.gold, CircleShape) else Modifier.border(0.9.dp, ArenaGlass.hairline, CircleShape)),
            contentAlignment = Alignment.Center) {
            if (done) SfImage("checkmark", ArenaMenuStyle.gold, 15.dp)
            else Text(number, color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(17f, SfWeight.bold))
        }
        Text(title, Modifier.weight(1f), color = ArenaMenuStyle.text, style = ArenaMenuStyle.font(18f, SfWeight.bold))
        Plaque(if (done) "Replay" else "Play", icon = "chevron.right", primary = next)
    }
}
