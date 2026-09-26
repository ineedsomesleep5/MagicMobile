package io.magicmobile.android.studio

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.magicmobile.android.board.BoardSheet
import io.magicmobile.android.board.ManaSymbolView
import io.magicmobile.android.core.Deck
import io.magicmobile.android.game.CardCountText
import io.magicmobile.android.ondevice.OnDeviceSetupModel
import io.magicmobile.android.ui.BrandTheme
import io.magicmobile.android.ui.GameAudio
import io.magicmobile.android.ui.GameSound
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfText
import io.magicmobile.android.ui.SfWeight
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Where Deck Studio opens: a deck, optionally with the Cards list filtered to the cards that need fixing. */
data class DeckStudioOpen(val deckID: String, val cards: List<String> = emptyList())

/**
 * DeckStudioPlaySelection.swift: one "Play this deck" controller for the library tiles, the
 * workspace header and the validation panel. [DeckStudioPlayFlow] makes every decision; this keeps
 * the visible phase, runs the XMage check off the main thread and selects the source deck on a pass.
 */
class DeckStudioPlaySelection(
    private val scope: CoroutineScope,
    private val gameLive: () -> Boolean,
    private val select: (String) -> Unit,
    /** The current playing-deck ID. */
    val selectedID: () -> String,
    flow: DeckStudioPlayFlow? = null,
) {
    sealed class Phase {
        object Idle : Phase()
        data class Checking(val name: String) : Phase()
        data class Finished(val outcome: DeckStudioPlayFlow.Outcome) : Phase()
    }

    private val engine by lazy {
        flow ?: DeckStudioPlayFlow(DeckStudioServices.checkResults, DeckStudioServices.appBuild, DeckStudioValidationService::validate)
    }
    var phase by mutableStateOf<Phase>(Phase.Idle); private set
    val checking: Boolean get() = phase is Phase.Checking
    private var job: Job? = null

    fun play(source: DeckStudioPlayFlow.Source, resolver: OnDeviceDeckResolver?) {
        if (checking) return
        when (val step = engine.start(source, gameLive(), resolver)) {
            is DeckStudioPlayFlow.Step.Done -> finish(step.outcome)
            is DeckStudioPlayFlow.Step.Check -> {
                val current = resolver ?: return
                phase = Phase.Checking(step.name)
                job = scope.launch {
                    try { finish(engine.check(step, current)) }
                    catch (cancelled: CancellationException) { if (phase is Phase.Checking) phase = Phase.Idle }
                }
            }
        }
    }

    private fun finish(outcome: DeckStudioPlayFlow.Outcome) {
        if (outcome is DeckStudioPlayFlow.Outcome.Playing) select(outcome.deckID)
        phase = Phase.Finished(outcome)
    }

    /** Cancel stops a running check; the playing deck does not change. */
    fun cancel() { job?.cancel(); job = null; phase = Phase.Idle }

    fun dismiss() { if (!checking) phase = Phase.Idle }

    companion object {
        /** A library record plays as it is saved. */
        fun source(deckID: String, deck: DeckList) = DeckStudioPlayFlow.Source { Result.success(DeckStudioPlayFlow.Prepared(deckID, deck)) }
    }
}

/** The open draft as a Play source: a new or changed draft is saved first. */
fun DeckStudioEditorModel.playSource() = DeckStudioPlayFlow.Source {
    val id = preparePlayable() ?: return@Source Result.failure(IllegalStateException(error ?: "Save this deck before playing it."))
    runCatching { DeckStudioPlayFlow.Prepared(id, draft.deck()) }
}

/** The brand's ember accent, as a capsule button (DeckStudioButtonStyle, primary). */
@Composable
fun DeckStudioEmberButton(title: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, icon: String? = null) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val shape = RoundedCornerShape(DeckStudioMetrics.controlRadius)
    Row(modifier.alpha(if (!enabled) 0.55f else if (pressed) 0.8f else 1f).defaultMinSize(minHeight = DeckStudioMetrics.controlHeight)
        .background(DeckStudioPalette.accent, shape).clip(shape)
        .clickable(interaction, null, enabled = enabled, role = Role.Button) { GameAudio.play(GameSound.UI_TICK); onClick() }
        .padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
        icon?.let { SfImage(it, Color.White, 15.dp) }
        Text(title, color = Color.White, style = StudioText.body.weight(SfWeight.semibold), maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/**
 * The workspace header's primary button: "Play this deck", "Save & play" for unsaved changes, or a
 * disabled "✓ Playing" when this deck is already selected and its stored check is still current.
 */
@Composable
fun DeckStudioPlayDeckButton(selection: DeckStudioPlaySelection, model: DeckStudioEditorModel, resolver: OnDeviceDeckResolver?, modifier: Modifier = Modifier) {
    val needsSave = !model.readOnly && (model.isDirty || model.record == null)
    val sourceID = model.sourceID
    val draft = model.draft
    val revision = DeckStudioServices.checkRevision
    val current = remember(draft, needsSave, sourceID, resolver, revision) {
        if (needsSave || sourceID == null || resolver == null) return@remember false
        val deck = runCatching { draft.deck() }.getOrNull() ?: return@remember false
        val key = DeckStudioPlayRules.key(sourceID, deck, resolver, DeckStudioServices.appBuild) ?: return@remember false
        runCatching { DeckStudioServices.checkResults.result(key)?.valid == true }.getOrDefault(false)
    }
    val playing = current && sourceID == selection.selectedID()
    val title = when { playing -> DeckStudioPlayText.playingButton; needsSave -> DeckStudioPlayText.saveAndPlay; else -> DeckStudioPlayText.play }
    DeckStudioEmberButton(title, { selection.play(model.playSource(), resolver) },
        modifier.fillMaxWidth().semantics { contentDescription = if (playing) DeckStudioPlayText.playingLabel else title },
        enabled = !playing && !selection.checking && resolver != null && (!needsSave || model.canSave), icon = if (playing) null else "play.fill")
}

/** The ember "Playing" badge on the playing deck's tile. */
@Composable
fun DeckStudioPlayingBadge(modifier: Modifier = Modifier) {
    Row(modifier.background(DeckStudioPalette.accent, CircleShape).padding(horizontal = 10.dp, vertical = 7.dp)
        .clearAndSetSemantics { contentDescription = DeckStudioPlayText.playingLabel },
        horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
        SfImage("flame.fill", Color.White, 12.dp)
        Text(DeckStudioPlayText.playing, color = Color.White, style = StudioText.caption2.weight(SfWeight.semibold))
    }
}

private fun DeckStudioPlayStatus.icon() = when (this) {
    DeckStudioPlayStatus.READY -> "checkmark.circle.fill" to DeckStudioPalette.success
    DeckStudioPlayStatus.NEEDS_FIXES -> "exclamationmark.triangle.fill" to DeckStudioPalette.warning
    DeckStudioPlayStatus.NOT_CHECKED -> "circle" to DeckStudioPalette.secondaryInk
}

/** A tile's status chip: Ready, Needs fixes or Not checked, from its stored check result. */
@Composable
fun DeckStudioPlayStatusChip(status: DeckStudioPlayStatus, modifier: Modifier = Modifier) {
    val (icon, tint) = status.icon()
    Row(modifier.background(DeckStudioPalette.surfaceElevated.copy(alpha = 0.94f), CircleShape).padding(horizontal = 9.dp, vertical = 6.dp)
        .semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        SfImage(icon, tint, 11.dp)
        Text(status.title, color = DeckStudioPalette.ink, style = StudioText.caption2.weight(SfWeight.semibold), maxLines = 1)
    }
}

/** The pinned "Now playing: <name> · <status>" row at the top of the library. */
@Composable
fun DeckStudioNowPlayingStrip(name: String, status: DeckStudioPlayStatus?, open: () -> Unit, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).background(DeckStudioPalette.surface, RoundedCornerShape(14.dp))
        .clip(RoundedCornerShape(14.dp)).clickable(role = Role.Button) { open() }.padding(horizontal = 14.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        SfImage("flame.fill", DeckStudioPalette.accent, 15.dp)
        Text(DeckStudioPlayText.nowPlayingStrip(name, status), Modifier.weight(1f), color = DeckStudioPalette.ink,
            style = StudioText.subheadline.weight(SfWeight.medium), maxLines = 1, overflow = TextOverflow.Ellipsis)
        SfImage("chevron.right", DeckStudioPalette.secondaryInk, 13.dp)
    }
}

/** "Now playing <name>" with Set up game, or the live-game notice. Stays until dismissed. */
@Composable
fun DeckStudioPlayBanner(selection: DeckStudioPlaySelection, setUpGame: () -> Unit, modifier: Modifier = Modifier) {
    val outcome = (selection.phase as? DeckStudioPlaySelection.Phase.Finished)?.outcome
    val (title, detail) = when (outcome) {
        is DeckStudioPlayFlow.Outcome.Playing -> DeckStudioPlayText.nowPlaying(outcome.name) to
            outcome.excludedCards.takeIf { it > 0 }?.let(DeckStudioPlayText::excluded)
        DeckStudioPlayFlow.Outcome.GameLive -> DeckStudioPlayText.gameLive to null
        else -> return
    }
    Row(modifier.navigationBarsPadding().padding(horizontal = 16.dp, vertical = 12.dp).widthIn(max = 640.dp).fillMaxWidth()
        .background(DeckStudioPalette.ink, RoundedCornerShape(18.dp)).padding(start = 16.dp, top = 10.dp, bottom = 10.dp, end = 4.dp)
        .semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        SfImage(if (outcome is DeckStudioPlayFlow.Outcome.Playing) "flame.fill" else "exclamationmark.triangle.fill", BrandTheme.ember, 17.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, color = Color.White, style = StudioText.subheadline.weight(SfWeight.semibold), maxLines = 2, overflow = TextOverflow.Ellipsis)
            detail?.let { Text(it, color = Color.White.copy(alpha = 0.78f), style = StudioText.caption) }
        }
        if (outcome is DeckStudioPlayFlow.Outcome.Playing) {
            Box(Modifier.defaultMinSize(minHeight = 44.dp).clip(CircleShape).clickable(role = Role.Button) { selection.dismiss(); setUpGame() }
                .padding(horizontal = 8.dp), contentAlignment = Alignment.Center) {
                Text(DeckStudioPlayText.setUpGame, color = BrandTheme.ember, style = StudioText.subheadline.weight(SfWeight.semibold))
            }
        }
        StudioIconButton("xmark", "Dismiss notification", { selection.dismiss() }, tint = Color.White, size = 13.dp)
    }
}

/** The Play sheets: Checking your deck, Can't play this deck yet, and the rule issues that block play. */
@Composable
fun DeckStudioPlaySheets(selection: DeckStudioPlaySelection, fix: (DeckStudioOpen) -> Unit) {
    when (val phase = selection.phase) {
        is DeckStudioPlaySelection.Phase.Checking -> PlaySheet({ selection.cancel() }) {
            Text(DeckStudioPlayText.checkingTitle, color = DeckStudioPalette.ink, style = StudioText.title3.weight(SfWeight.semibold))
            Text(DeckStudioPlayText.checking(phase.name), color = DeckStudioPalette.secondaryInk, style = StudioText.subheadline)
            StudioProgress("Checking Commander rules…")
            StudioButton("Cancel", { selection.cancel() }, Modifier.fillMaxWidth(), primary = false)
        }
        is DeckStudioPlaySelection.Phase.Finished -> when (val outcome = phase.outcome) {
            is DeckStudioPlayFlow.Outcome.CannotPlay -> DeckStudioIssuesSheet(DeckStudioPlayText.cannotPlayTitle, outcome.message, emptyList(), 0,
                fix = outcome.deckID?.let { id -> { selection.dismiss(); fix(DeckStudioOpen(id, outcome.cards)) } }, dismiss = { selection.dismiss() })
            is DeckStudioPlayFlow.Outcome.Blocked -> DeckStudioIssuesSheet(outcome.result, { selection.dismiss(); fix(DeckStudioOpen(outcome.deckID, it)) }) { selection.dismiss() }
            is DeckStudioPlayFlow.Outcome.CheckFailed -> PlaySheet({ selection.dismiss() }) {
                Text(DeckStudioPlayText.checkingTitle, color = DeckStudioPalette.ink, style = StudioText.title3.weight(SfWeight.semibold))
                Text(outcome.message, color = DeckStudioPalette.danger, style = StudioText.subheadline)
                StudioButton(DeckStudioPlayText.notNow, { selection.dismiss() }, Modifier.fillMaxWidth(), primary = false)
            }
            else -> {}
        }
        DeckStudioPlaySelection.Phase.Idle -> {}
    }
}

/** "N rule issues block play": a stored failed check's issues, grouped as XMage reported them. */
@Composable
fun DeckStudioIssuesSheet(result: DeckStudioCheckResult, fix: (List<String>) -> Unit, dismiss: () -> Unit) {
    DeckStudioIssuesSheet(DeckStudioPlayText.issuesBlockPlay(result.issueCount), null, DeckStudioPlayRules.groupedIssues(result.issues),
        result.issueCount - result.issues.size, { fix(DeckStudioPlayRules.issueCards(result)) }, dismiss)
}

@Composable
private fun DeckStudioIssuesSheet(title: String, message: String?, groups: List<Pair<String, List<DeckStudioValidationReceipt.Issue>>>, hidden: Int,
                                  fix: (() -> Unit)?, dismiss: () -> Unit) {
    PlaySheet(dismiss) {
        Text(title, color = DeckStudioPalette.ink, style = StudioText.title3.weight(SfWeight.semibold))
        message?.let { Text(it, color = DeckStudioPalette.secondaryInk, style = StudioText.subheadline) }
        for ((group, issues) in groups) Column(Modifier.fillMaxWidth().background(DeckStudioPalette.surface, RoundedCornerShape(14.dp)).padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(group, color = DeckStudioPalette.ink, style = StudioText.subheadline.weight(SfWeight.semibold))
            for (issue in issues) Column(Modifier.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                issue.cardName?.takeIf { it.isNotBlank() }?.let { Text(it, color = DeckStudioPalette.ink, style = StudioText.caption.weight(SfWeight.semibold)) }
                Text(issue.message, color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
            }
        }
        if (hidden > 0) Text("${DeckStudioPlayText.issues(hidden)} not shown", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            StudioButton(DeckStudioPlayText.notNow, dismiss, Modifier.weight(1f), primary = false)
            fix?.let { DeckStudioEmberButton(DeckStudioPlayText.fixDeck, it, Modifier.weight(1f), icon = "pencil") }
        }
    }
}

@Composable
private fun PlaySheet(dismiss: () -> Unit, content: @Composable () -> Unit) {
    BoardSheet(dismiss, background = DeckStudioPalette.background, skipPartiallyExpanded = true, sound = false) {
        Column(Modifier.fillMaxWidth().heightIn(max = 640.dp).verticalScroll(rememberScrollState()).padding(start = 20.dp, end = 20.dp, top = 12.dp, bottom = 20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) { content() }
    }
}

/**
 * The setup screen's deck card details: "N cards", the colour identity (once the card catalogue is
 * loaded) and the stored check status. "Needs fixes" opens Deck Studio on that deck, and a Start
 * that XMage rejected shows the same issues sheet as Play.
 */
@Composable
fun DeckStudioSetupDeckStatus(setup: OnDeviceSetupModel, deckID: String, deck: Deck?, openStudio: (DeckStudioOpen) -> Unit) {
    val resolver = setup.deckResolver
    val revision = DeckStudioServices.checkRevision
    val status by produceState<DeckStudioPlayStatus?>(null, deckID, deck, resolver, revision) {
        value = if (deck == null || resolver == null) null else withContext(Dispatchers.Default) {
            runCatching { DeckStudioPlayRules.status(deckID, DeckList.fromStored(deck), resolver, DeckStudioServices.appBuild, DeckStudioServices.checkResults) }.getOrNull()
        }
    }
    if (deck != null) Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        val list = remember(deck) { DeckList.fromStored(deck) }
        val identity = setup.catalogue?.let { catalogue ->
            val commanders = deck.entries.filter { it.section == "commanders" }.map { it.name }
            val colors = commanders.map { catalogue.find(it)?.identity ?: return@let null }.flatten().toSet()
            listOf("W", "U", "B", "R", "G").filter { it in colors }.takeIf { commanders.isNotEmpty() }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(CardCountText.label(DeckStudioDraftPresentation.gameCount(NativeDeckDraft.of(list))), color = BrandTheme.inkSecondary, style = SfText.caption())
            identity?.forEach { ManaSymbolView(it, 14.dp) }
        }
        status?.let { value ->
            val (icon, _) = value.icon()
            val tint = when (value) { DeckStudioPlayStatus.READY -> BrandTheme.inkSecondary; DeckStudioPlayStatus.NEEDS_FIXES -> BrandTheme.ember; else -> BrandTheme.inkSecondary }
            Row(Modifier.defaultMinSize(minHeight = if (value == DeckStudioPlayStatus.NEEDS_FIXES) 44.dp else 0.dp)
                .then(if (value == DeckStudioPlayStatus.NEEDS_FIXES) Modifier.clip(CircleShape).clickable(enabled = !setup.isBusy, role = Role.Button) {
                    openStudio(DeckStudioOpen(deckID))
                } else Modifier)
                .semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                SfImage(icon, tint, 12.dp)
                Text(DeckStudioPlayText.setupStatus(value), color = tint, style = SfText.caption(SfWeight.semibold), textAlign = TextAlign.Center)
            }
        }
    }
    setup.deckIssues?.let { (id, result) ->
        DeckStudioIssuesSheet(result, { cards -> setup.deckIssues = null; openStudio(DeckStudioOpen(id, cards)) }) { setup.deckIssues = null }
    }
}
