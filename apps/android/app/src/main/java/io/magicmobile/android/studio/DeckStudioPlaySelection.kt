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

    fun play(source: DeckStudioPlayFlow.Source, resolver: OnDeviceDeckResolver?, name: String = "") {
        if (checking) return
        when (val step = engine.start(source, gameLive(), resolver, name)) {
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
        // A game that started during the check keeps its deck.
        val final = if (outcome is DeckStudioPlayFlow.Outcome.Playing && gameLive()) DeckStudioPlayFlow.Outcome.GameLive else outcome
        if (final is DeckStudioPlayFlow.Outcome.Playing) select(final.deckID)
        phase = Phase.Finished(final)
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

/** What Play offers for the open draft (DeckStudioPlayAction): "Play this deck", "Save & play" or "Playing". */
data class DeckStudioPlayAction(val title: String, val playing: Boolean, val enabled: Boolean)

@Composable
fun rememberDeckStudioPlayAction(selection: DeckStudioPlaySelection, model: DeckStudioEditorModel, resolver: OnDeviceDeckResolver?): DeckStudioPlayAction {
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
    val title = when { playing -> DeckStudioPlayText.playing; needsSave -> DeckStudioPlayText.saveAndPlay; else -> DeckStudioPlayText.play }
    return DeckStudioPlayAction(title, playing, !playing && !selection.checking && resolver != null && (!needsSave || model.canSave))
}

/**
 * The workspace header's primary button: "Play this deck", "Save & play" for unsaved changes, or a
 * disabled "Playing" with a checkmark when this deck is already selected and its stored check is still current.
 */
@Composable
fun DeckStudioPlayDeckButton(selection: DeckStudioPlaySelection, model: DeckStudioEditorModel, resolver: OnDeviceDeckResolver?, modifier: Modifier = Modifier) {
    val action = rememberDeckStudioPlayAction(selection, model, resolver)
    DeckStudioEmberButton(action.title, { selection.play(model.playSource(), resolver, model.draft.name) },
        modifier.fillMaxWidth().semantics { contentDescription = if (action.playing) DeckStudioPlayText.playingAccessibility else action.title },
        enabled = action.enabled, icon = if (action.playing) "checkmark" else "play.fill")
}

/** The ember "Playing" badge on the playing deck's tile. */
@Composable
fun DeckStudioPlayingBadge(modifier: Modifier = Modifier) {
    Row(modifier.background(DeckStudioPalette.accent, CircleShape).padding(horizontal = 10.dp, vertical = 7.dp)
        .clearAndSetSemantics { contentDescription = DeckStudioPlayText.playingAccessibility },
        horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
        SfImage("flame.fill", Color.White, 12.dp)
        Text(DeckStudioPlayText.playing, color = Color.White, style = StudioText.caption2.weight(SfWeight.semibold))
    }
}

private fun DeckStudioPlayStatus.icon() = when (this) {
    DeckStudioPlayStatus.READY -> "checkmark.seal.fill" to DeckStudioPalette.success
    DeckStudioPlayStatus.NEEDS_FIXES -> "exclamationmark.triangle.fill" to DeckStudioPalette.warning
    DeckStudioPlayStatus.NOT_CHECKED -> "questionmark.circle" to DeckStudioPalette.secondaryInk
}

/** A tile's status chip: Ready, Needs fixes or Not checked, from its stored check result. */
@Composable
fun DeckStudioPlayStatusChip(status: DeckStudioPlayStatus, modifier: Modifier = Modifier) {
    val (icon, tint) = status.icon()
    Row(modifier.background(DeckStudioPalette.surfaceElevated.copy(alpha = 0.94f), CircleShape).padding(horizontal = 9.dp, vertical = 6.dp)
        .clearAndSetSemantics { contentDescription = "Deck check: ${status.title}" }, horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
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
            StudioProgress(DeckStudioPlayText.checkingProgress)
            StudioButton("Cancel", { selection.cancel() }, Modifier.fillMaxWidth(), primary = false)
        }
        is DeckStudioPlaySelection.Phase.Finished -> when (val outcome = phase.outcome) {
            // Without a saved deck there is nothing to open, so Fix deck is not offered.
            is DeckStudioPlayFlow.Outcome.CannotPlay -> DeckStudioIssuesSheet(DeckStudioPlayText.cannotPlayTitle, outcome.name, outcome.message, emptyList(),
                outcome.cards, 0, fix = outcome.deckID?.let { id -> { cards: List<String> -> selection.dismiss(); fix(DeckStudioOpen(id, cards)) } },
                dismiss = { selection.dismiss() })
            is DeckStudioPlayFlow.Outcome.Blocked -> DeckStudioIssuesSheet(outcome.result, outcome.name,
                { cards -> selection.dismiss(); fix(DeckStudioOpen(outcome.deckID, cards)) }) { selection.dismiss() }
            // An engine failure is not a deck result: the same sheet as iOS, with the engine's message.
            is DeckStudioPlayFlow.Outcome.CheckFailed -> DeckStudioIssuesSheet(DeckStudioPlayText.cannotPlayTitle, outcome.name, outcome.message, emptyList(),
                emptyList(), 0, fix = { cards -> selection.dismiss(); fix(DeckStudioOpen(outcome.deckID, cards)) }, dismiss = { selection.dismiss() })
            else -> {}
        }
        DeckStudioPlaySelection.Phase.Idle -> {}
    }
}

/** "N rule issues block play": a stored failed check's issues, grouped as XMage reported them. */
@Composable
fun DeckStudioIssuesSheet(result: DeckStudioCheckResult, deckName: String, fix: (List<String>) -> Unit, dismiss: () -> Unit) {
    DeckStudioIssuesSheet(DeckStudioPlayText.issuesBlockPlay(result.issueCount), deckName, null, DeckStudioPlayRules.groupedIssues(result.issues),
        DeckStudioPlayRules.issueCards(result), result.issueCount - result.issues.size, fix, dismiss)
}

/**
 * Why a deck cannot be the playing deck, with the way back to its rows (DeckStudioPlayIssues). Fix
 * deck shows every named card; each named card also has its own button that shows just its row.
 */
@Composable
private fun DeckStudioIssuesSheet(title: String, deckName: String, message: String?, groups: List<Pair<String, List<DeckStudioValidationReceipt.Issue>>>,
                                  cards: List<String>, hidden: Int, fix: ((List<String>) -> Unit)?, dismiss: () -> Unit) {
    @Composable
    fun card(name: String) {
        if (fix == null) Text(name, color = DeckStudioPalette.ink, style = StudioText.subheadline.weight(SfWeight.semibold))
        else Row(Modifier.defaultMinSize(minHeight = 32.dp).clip(RoundedCornerShape(8.dp)).clickable(role = Role.Button) { fix(listOf(name)) }
            .semantics(mergeDescendants = true) { contentDescription = "$name. Shows this card in the deck" },
            horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            SfImage("magnifyingglass", DeckStudioPalette.accent, 13.dp)
            Text(name, color = DeckStudioPalette.accent, style = StudioText.subheadline.weight(SfWeight.semibold))
        }
    }
    PlaySheet(dismiss) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            SfImage("exclamationmark.triangle.fill", DeckStudioPalette.ink, 18.dp)
            Text(title, color = DeckStudioPalette.ink, style = StudioText.title3.weight(SfWeight.semibold))
        }
        if (deckName.isNotEmpty()) Text(deckName, color = DeckStudioPalette.secondaryInk, style = StudioText.subheadline)
        message?.let { Text(it, color = DeckStudioPalette.ink, style = StudioText.subheadline) }
        for ((group, issues) in groups) Column(Modifier.fillMaxWidth().background(DeckStudioPalette.surface, RoundedCornerShape(12.dp)).padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(group, Modifier.weight(1f), color = DeckStudioPalette.ink, style = StudioText.subheadline.weight(SfWeight.semibold))
                Text(DeckStudioPlayText.issues(issues.size), color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
            }
            for (issue in issues) Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                issue.cardName?.trim()?.takeIf { it.isNotEmpty() }?.let { card(it) }
                Text(issue.message, color = DeckStudioPalette.ink, style = StudioText.caption)
            }
        }
        if (groups.isEmpty() && cards.isNotEmpty()) Column(verticalArrangement = Arrangement.spacedBy(4.dp)) { cards.forEach { card(it) } }
        if (hidden > 0) Text(DeckStudioPlayText.notShown(hidden), color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            StudioButton(DeckStudioPlayText.notNow, dismiss, Modifier.weight(1f), primary = false)
            fix?.let { DeckStudioEmberButton(DeckStudioPlayText.fixDeck, { it(cards) }, Modifier.weight(1f), icon = "wrench.and.screwdriver") }
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
        // Colours only once the catalogue has loaded (Deck Studio loads it); the setup screen never loads it itself.
        val identity = setup.catalogue?.let { catalogue ->
            val commanders = deck.entries.filter { it.section == "commanders" }.map { it.name }
            val colors = commanders.map { catalogue.find(it)?.identity ?: return@let null }.flatten().toSet()
            listOf("W", "U", "B", "R", "G").filter { it in colors }.takeIf { commanders.isNotEmpty() }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(CardCountText.label(DeckStudioDraftPresentation.gameCount(NativeDeckDraft.of(list))), color = BrandTheme.inkSecondary, style = SfText.caption())
            // A colorless commander shows the colorless symbol, as on iOS.
            identity?.let { colors -> (colors.ifEmpty { listOf("C") }).forEach { ManaSymbolView(it, 14.dp) } }
        }
        // Ready and not-checked decks show no line (Caleb, 2026-10-03): Start checks the deck anyway.
        status?.takeIf { it == DeckStudioPlayStatus.NEEDS_FIXES }?.let { value ->
            val (icon, _) = value.icon()
            val tint = when (value) { DeckStudioPlayStatus.READY -> BrandTheme.inkSecondary; DeckStudioPlayStatus.NEEDS_FIXES -> BrandTheme.ember; else -> BrandTheme.inkSecondary }
            Row(Modifier.defaultMinSize(minHeight = if (value == DeckStudioPlayStatus.NEEDS_FIXES) 44.dp else 0.dp)
                .then(if (value == DeckStudioPlayStatus.NEEDS_FIXES) Modifier.clip(CircleShape).clickable(enabled = !setup.isBusy, role = Role.Button) {
                    openStudio(DeckStudioOpen(deckID, fixCards(deckID, list, resolver)))
                } else Modifier)
                .semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                SfImage(icon, tint, 12.dp)
                Text(DeckStudioPlayText.setupStatus(value), color = tint, style = SfText.caption(SfWeight.semibold), textAlign = TextAlign.Center)
            }
        }
    }
    setup.deckIssues?.let { (id, result) ->
        DeckStudioIssuesSheet(result, deck?.name ?: "", { cards -> setup.deckIssues = null; openStudio(DeckStudioOpen(id, cards)) }) { setup.deckIssues = null }
    }
}

/** Fix in Deck Studio shows the cards XMage named, or the rows the resolver cannot play. */
private fun fixCards(deckID: String, deck: DeckList, resolver: OnDeviceDeckResolver?): List<String> {
    resolver ?: return emptyList()
    DeckStudioPlayRules.key(deckID, deck, resolver, DeckStudioServices.appBuild)?.let { key ->
        runCatching { DeckStudioServices.checkResults.result(key) }.getOrNull()?.let { return DeckStudioPlayRules.issueCards(it) }
    }
    return runCatching { DeckStudioPlayRules.unplayableCards(deck, resolver) }.getOrDefault(emptyList())
}
