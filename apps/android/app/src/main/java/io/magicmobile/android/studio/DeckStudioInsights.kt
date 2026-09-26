package io.magicmobile.android.studio

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import io.magicmobile.android.board.BoardSheet
import io.magicmobile.android.board.ConfirmationAction
import io.magicmobile.android.board.ConfirmationDialog
import io.magicmobile.android.board.ManaSymbolView
import io.magicmobile.android.board.MenuEntry
import io.magicmobile.android.ui.IosSlider
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.rgb
import io.magicmobile.android.ui.sf
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID
import kotlin.math.abs
import kotlin.math.roundToInt

@Composable
private fun Metric(label: String, value: String) {
    Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.Top) {
        Text(label, Modifier.weight(1f), color = DeckStudioPalette.ink, style = StudioText.subheadline)
        Spacer(Modifier.width(16.dp))
        Text(value, color = DeckStudioPalette.secondaryInk, style = StudioText.subheadline)
    }
}

/** DeckStudioAnalysisView.swift: statistics, curve, printed symbols, types, colours and land odds. */
@Composable
fun DeckStudioAnalysisContent(draft: NativeDeckDraft, metadata: NativeDeckMetadataCatalogue?, curveOnly: Boolean, inspect: (String) -> Unit) {
    var selectedBin by remember { mutableStateOf<Int?>(null) }
    var requiredLands by remember { mutableStateOf(3) }
    var cardsSeen by remember { mutableStateOf(7) }
    val statistics = remember(draft, metadata) {
        val display = if (draft.name.isBlank()) draft.copy(name = "Draft") else draft
        runCatching { metadata?.statistics(display.deck()) }.getOrNull()
    }
    val mainRows = draft.rows.filter { DeckStudioDraftPresentation.section(it) == "deck" }
    fun curveBin(row: NativeDeckRow): Int? {
        val card = metadata?.card(row.cardName) ?: return null
        val types = card.types ?: return null
        if ("LAND" in types) return null
        val value = card.manaValue ?: return null
        return if (value >= 7) 7 else value.toInt()
    }
    fun binCount(bin: Int) = mainRows.filter { curveBin(it) == bin }.sumOf { it.quantity }
    fun typeCount(type: String) = mainRows.filter { metadata?.card(it.cardName)?.types?.contains(type) == true }.sumOf { it.quantity }
    fun colorCount(color: String) = mainRows.filter { row ->
        val colors = metadata?.card(row.cardName)?.colors ?: return@filter false
        if (color == "C") colors.isEmpty() else color in colors
    }.sumOf { it.quantity }
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        if (statistics == null) {
            DeckStudioNotice("Analysis unavailable", "Wait for the local metadata catalogue or fix malformed draft entries. Your saved deck is unchanged.")
            return@Column
        }
        if (!curveOnly) StudioPanel {
            Text("Your deck at a glance", color = DeckStudioPalette.ink, style = StudioText.title2.weight(SfWeight.semibold))
            Metric("Main deck", "${statistics.cardCount}")
            Metric("Commander(s)", "${draft.rows.filter { DeckStudioDraftPresentation.section(it) == "commanders" }.sumOf { it.quantity }}")
            Metric("Other sections", "${draft.rows.filter { DeckStudioDraftPresentation.section(it) !in setOf("deck", "commanders") }.sumOf { it.quantity }}")
            Metric("Lands in main", "${statistics.landCount}")
            Metric("Average nonland mana value", statistics.averageManaValue?.let { String.format(java.util.Locale.US, "%.2f", it) } ?: "Unavailable")
            Text("Deck statistics · check legality in Playtest.", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
        }
        StudioPanel {
            Text("Main-deck mana curve", color = DeckStudioPalette.ink, style = StudioText.headline)
            Text("Tap a bar to see its cards. Main-deck nonlands only.", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
            val maximum = (0..7).maxOf(::binCount).coerceAtLeast(1)
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.Bottom) {
                for (bin in 0..7) {
                    Column(Modifier.width(44.dp).height(144.dp).clickable { selectedBin = if (selectedBin == bin) null else bin }
                        .semantics { contentDescription = "Mana value ${if (bin == 7) "7 or more" else "$bin"}, ${binCount(bin)} cards. Show cards." },
                        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(7.dp, Alignment.Bottom)) {
                        Text("${binCount(bin)}", color = DeckStudioPalette.ink, style = StudioText.caption)
                        Box(Modifier.fillMaxWidth().height(maxOf(3f, 100f * binCount(bin) / maximum).dp)
                            .background(if (selectedBin == bin) DeckStudioPalette.accent else DeckStudioPalette.ink, RoundedCornerShape(5.dp)))
                        Text(if (bin == 7) "7+" else "$bin", color = DeckStudioPalette.ink, style = StudioText.caption)
                    }
                }
            }
            selectedBin?.let { bin ->
                for (row in mainRows.filter { curveBin(it) == bin }) {
                    Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).clickable { inspect(row.cardName) }, horizontalArrangement = Arrangement.spacedBy(10.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(36.dp, 50.dp).clip(RoundedCornerShape(5.dp))) { DeckStudioArtwork(row.cardName, Modifier.fillMaxSize()) }
                        Box(Modifier.weight(1f)) { Metric(row.cardName, "×${row.quantity}") }
                    }
                }
            }
            if (statistics.unknownTypeCount > 0 || statistics.unknownManaValueCount > 0) DeckStudioNotice("Incomplete metadata",
                "${statistics.unknownTypeCount} unknown types; ${statistics.unknownManaValueCount} unknown mana values. Missing data is excluded, not treated as zero.")
        }
        StudioPanel {
            Text("Printed mana symbols", color = DeckStudioPalette.ink, style = StudioText.headline)
            for (symbol in statistics.manaSymbolCounts.keys.sorted()) Row(Modifier.semantics(mergeDescendants = true) {
                contentDescription = "$symbol mana symbol: ${statistics.manaSymbolCounts[symbol] ?: 0}"
            }, verticalAlignment = Alignment.CenterVertically) {
                ManaSymbolView(symbol, 24.dp)
                Spacer(Modifier.weight(1f))
                Text("${statistics.manaSymbolCounts[symbol] ?: 0}", color = DeckStudioPalette.secondaryInk, style = StudioText.body)
            }
            StudioDisclosure("How to read these counts", titleStyle = StudioText.caption, color = DeckStudioPalette.secondaryInk) {
                Text("Printed costs, not available mana sources. Hybrid and Phyrexian symbols stay distinct. Conditional mana, land-face choices and cost reductions are not inferred.",
                    color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
            }
        }
        if (!curveOnly) {
            StudioPanel(spacing = 10.dp) {
                Text("Card types & colors", color = DeckStudioPalette.ink, style = StudioText.headline)
                for (type in listOf("CREATURE", "ARTIFACT", "ENCHANTMENT", "INSTANT", "SORCERY", "LAND", "PLANESWALKER", "BATTLE")) {
                    Metric(type.lowercase().replaceFirstChar { it.uppercase() }, "${typeCount(type)}")
                }
                HorizontalDivider(thickness = 0.5.dp, color = DeckStudioPalette.separator)
                val names = mapOf("W" to "White", "U" to "Blue", "B" to "Black", "R" to "Red", "G" to "Green", "C" to "Colorless")
                for (color in listOf("W", "U", "B", "R", "G", "C")) Row(Modifier.semantics(mergeDescendants = true) {
                    contentDescription = "${names[color]}: ${colorCount(color)} cards"
                }, verticalAlignment = Alignment.CenterVertically) {
                    ManaSymbolView(color, 24.dp); Spacer(Modifier.weight(1f))
                    Text("${colorCount(color)}", color = DeckStudioPalette.secondaryInk, style = StudioText.body)
                }
                StudioDisclosure("About types and colors", titleStyle = StudioText.caption, color = DeckStudioPalette.secondaryInk) {
                    Text("Main-deck quantities; categories overlap for multi-type and multicolor cards. Unknown colors are excluded. Card colors are not commander identity or mana sources.",
                        color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                }
            }
            StudioPanel {
                Text("Opening hands & land draws", color = DeckStudioPalette.ink, style = StudioText.headline)
                StudioStepper("At least $requiredLands lands", requiredLands, 1..7, { requiredLands = it })
                StudioStepper("Cards seen: $cardsSeen", cardsSeen, 7..30, { cardsSeen = it })
                val value = if (statistics.cardCount >= cardsSeen && statistics.unknownTypeCount == 0)
                    runCatching { DeckStudioProbability.atLeast(requiredLands, statistics.landCount, statistics.cardCount, cardsSeen) }.getOrNull() else null
                if (value != null) {
                    Text(String.format(java.util.Locale.US, "%.1f%%", value * 100), color = DeckStudioPalette.ink, style = sf(34f, SfWeight.semibold, SfDesign.ROUNDED))
                    Text("Chance of at least $requiredLands lands in $cardsSeen random cards.", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                    StudioDisclosure("What this estimate includes", titleStyle = StudioText.caption, color = DeckStudioPalette.secondaryInk) {
                        Text("Uses printed lands in the ${statistics.cardCount}-card main deck. Seven cards represents an opening hand; commanders stay outside the library. No mulligans, tutors, extra draws, land-face choices or play decisions are modeled. Enough lands does not guarantee each land drop or the colors you need.",
                            color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                    }
                } else Text("Requires at least $cardsSeen main-deck cards and known card types.", color = DeckStudioPalette.ink, style = StudioText.caption)
            }
        }
        if (statistics.unknownNames.isNotEmpty()) StudioPanel(spacing = 10.dp) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                SfImage("exclamationmark.triangle", DeckStudioPalette.ink, 17.dp)
                Text("Unresolved cards", color = DeckStudioPalette.ink, style = StudioText.headline)
            }
            statistics.unknownNames.forEach { Text(it, color = DeckStudioPalette.ink, style = StudioText.subheadline) }
        }
    }
}

/** DeckStudioRoleInsightsView.swift: reviewable card roles, not a deck score. */
@Composable
fun DeckStudioRoleInsightsView(draft: NativeDeckDraft, metadata: NativeDeckMetadataCatalogue?, contextID: String?, inspect: (String) -> Unit) {
    val key = "deckStudio.roles.v1." + (contextID ?: "new")
    val defaults = DeckStudioServices.defaults
    var preferences by remember { mutableStateOf(DeckStudioRolePreferences()) }
    var blocked by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var selectedRole by remember { mutableStateOf<DeckStudioRole?>(null) }
    var review by remember { mutableStateOf<Pair<String, Set<DeckStudioRole>>?>(null) }
    var showTargets by remember { mutableStateOf(false) }
    LaunchedEffect(key) {
        review = null; showTargets = false
        try { preferences = if (contextID == null) DeckStudioRolePreferences() else DeckStudioRolePreferences.load(key, defaults); blocked = false; error = null }
        catch (failure: Exception) {
            blocked = true; preferences = DeckStudioRolePreferences()
            error = "Analysis preferences need recovery. The stored data is preserved and editing these settings is paused; deck editing still works."
        }
    }
    fun change(edit: (DeckStudioRolePreferences) -> DeckStudioRolePreferences): Boolean {
        if (contextID == null || blocked) return false
        val changed = edit(preferences)
        return try { changed.save(key, defaults); preferences = changed; error = null; true } catch (failure: Exception) { error = failure.message; false }
    }
    val analysis = remember(draft, metadata, preferences) {
        runCatching {
            DeckStudioRoleAnalysis(draft.rows.filter { DeckStudioDraftPresentation.section(it) == "deck" }.map { row ->
                val card = metadata?.card(row.cardName)
                DeckStudioRoleAnalysis.Entry(row.cardName, row.quantity, card?.oracleText, card?.types, (card?.roles ?: emptyList()).mapNotNull(DeckStudioRole::of))
            }, preferences.overrides)
        }.getOrNull()
    }
    fun sourceLabel(source: DeckStudioRoleEvidence.Source) = when (source) {
        DeckStudioRoleEvidence.Source.REVIEWED -> "Your tag"; DeckStudioRoleEvidence.Source.CURATED -> "Curated tag"; DeckStudioRoleEvidence.Source.TEXT_PATTERN -> "Text-pattern hint"
    }
    StudioPanel(spacing = 14.dp) {
        Text("What your cards do", color = DeckStudioPalette.ink, style = StudioText.title2.weight(SfWeight.semibold))
        Text("Card roles · reviewable, not a deck score", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
        Text("Roles come from Scryfall's community-curated oracle tags, bundled with this build and used offline. Cards those tags miss fall back to conservative rules-text patterns, which leave triggered and conditional effects unclassified. Draw includes cantrips, not just net card advantage. Your own tags override everything here.",
            color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
        error?.let { Text(it, color = DeckStudioPalette.warning, style = StudioText.caption) }
        if (contextID == null) Text("Save this draft once to customize role tags and target ranges for this deck.", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
        if (analysis == null) { Text("Role analysis is unavailable for malformed or oversized draft data. Your deck is unchanged.", color = DeckStudioPalette.ink, style = StudioText.caption); return@StudioPanel }
        for (role in DeckStudioRole.entries) {
            Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).clickable { selectedRole = if (selectedRole == role) null else role }
                .semantics { contentDescription = "${role.title}, ${analysis.count(role)} cards. Review detected cards." }, verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(role.title, color = DeckStudioPalette.ink, style = StudioText.subheadline.weight(SfWeight.medium))
                    val target = preferences.targets[role]
                    target?.comparison(analysis.count(role))?.let { Text("$it · ${target.lower}–${target.upper}", color = DeckStudioPalette.secondaryInk, style = StudioText.caption2) }
                }
                Text("${analysis.count(role)}", color = DeckStudioPalette.ink, style = StudioText.subheadline)
                Spacer(Modifier.width(8.dp))
                SfImage(if (selectedRole == role) "chevron.up" else "chevron.down", DeckStudioPalette.ink, 11.dp)
            }
            if (selectedRole == role) {
                val matching = analysis.cards.filter { card -> card.evidence.any { it.role == role } }
                if (matching.isEmpty()) Text("No cards tagged for this role. Curated tags and text patterns are not exhaustive, so check the cards yourself before concluding your deck lacks the effect.",
                    color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                for (card in matching) Column(Modifier.padding(start = 12.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Row(Modifier.defaultMinSize(minHeight = 44.dp).clickable { inspect(card.name) }, horizontalArrangement = Arrangement.spacedBy(10.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(40.dp, 56.dp).clip(RoundedCornerShape(5.dp))) { DeckStudioArtwork(card.name, Modifier.fillMaxSize()) }
                        Text("${card.quantity} × ${card.name}", color = DeckStudioPalette.ink, style = StudioText.subheadline)
                    }
                    card.evidence.filter { it.role == role }.forEach { evidence ->
                        Text("${sourceLabel(evidence.source)}: ${evidence.explanation}", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                    }
                }
            }
        }
        HorizontalDivider(thickness = 0.5.dp, color = DeckStudioPalette.separator)
        Text("${analysis.unclassifiedCount} of ${analysis.mainCount} main-deck cards have no role tag. ${analysis.missingMetadataCount} have incomplete metadata. Counts include quantities; one card can have multiple roles. Lands can be tagged but do not count as automatic ramp.",
            color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
        StudioPlainButton("Set my target ranges", { showTargets = true }, icon = "slider.horizontal.3", enabled = !blocked && contextID != null)
        StudioDisclosure("Review or assign card roles") {
            for (card in analysis.cards) Column(Modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp)
                .clickable(enabled = !blocked && contextID != null) { review = card.name to card.evidence.map { it.role }.toSet() }, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(card.name, color = DeckStudioPalette.ink, style = StudioText.subheadline)
                Text(if (card.evidence.isEmpty()) "Unclassified" else card.evidence.joinToString(" · ") { it.role.title }, color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                if (card.userReviewed) Text("Your reviewed tags", color = DeckStudioPalette.ink, style = StudioText.caption2)
            }
        }
    }
    review?.let { (name, original) ->
        BoardSheet({ review = null }, background = rgbLight, skipPartiallyExpanded = true, sound = false) {
            var selected by remember(name) { mutableStateOf(original) }
            Column(Modifier.fillMaxWidth().height(largeSheetHeight())) {
                StudioSheetBar("Review roles", done = { if (change { it.copy(overrides = it.overrides + (name to selected)) }) review = null },
                    doneTitle = "Save", cancel = { review = null })
                Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                    FormSection(name, "These are your functional tags, not XMage legality or EDHREC statistics. An empty selection explicitly clears automatic hints for this card.") {
                        for (role in DeckStudioRole.entries) StudioToggle(role.title, role in selected, { enabled -> selected = if (enabled) selected + role else selected - role })
                    }
                    FormSection { StudioPlainButton("Use automatic hints again", { if (change { it.copy(overrides = it.overrides - name) }) review = null }) }
                }
            }
        }
    }
    if (showTargets) BoardSheet({ showTargets = false }, background = rgbLight, skipPartiallyExpanded = true, sound = false) {
        var targets by remember { mutableStateOf(preferences.targets) }
        Column(Modifier.fillMaxWidth().height(largeSheetHeight())) {
            StudioSheetBar("My target ranges", done = { if (change { it.copy(targets = targets) }) showTargets = false }, doneTitle = "Save", cancel = { showTargets = false })
            Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                FormSection { Text("Choose your own ranges. All targets start off; there is no universal ideal Commander deck. These targets compare tagged main-deck quantities, not unrecognized effects.",
                    color = DeckStudioPalette.ink, style = StudioText.caption) }
                for (role in DeckStudioRole.entries) {
                    val target = targets[role] ?: DeckStudioRolePreferences.Target()
                    FormSection(role.title) {
                        StudioToggle("Compare with my target", target.enabled, { targets = targets + (role to target.copy(enabled = it)) })
                        if (target.enabled) {
                            StudioStepper("Minimum: ${target.lower}", target.lower, 0..2000, { targets = targets + (role to target.copy(lower = it, upper = maxOf(it, target.upper))) })
                            StudioStepper("Maximum: ${target.upper}", target.upper, 0..2000, { targets = targets + (role to target.copy(upper = it, lower = minOf(it, target.lower))) })
                        }
                    }
                }
            }
        }
    }
}

/** DeckStudioValidationPanel.swift: check Commander rules with the installed engine, then play. */
@Composable
fun DeckStudioValidationPanel(state: DeckStudioValidationState, deck: DeckList?, resolver: OnDeviceDeckResolver?, play: ((DeckList) -> Unit)? = null) {
    val scope = rememberCoroutineScope()
    var acknowledgeExclusions by remember(deck) { mutableStateOf(false) }
    val prepared = deck?.let { runCatching { DeckStudioPlayProjection(it) }.getOrNull() }
    val request = if (prepared != null && resolver != null) runCatching { prepared.resolve(resolver) }.getOrNull() else null
    val currentReceipt = run {
        val receipt = state.receipt ?: return@run null
        if (request == null || resolver == null) return@run null
        val encoded = runCatching { String(io.magicmobile.android.game.EngineJson.encode(request), Charsets.UTF_8) }.getOrNull() ?: return@run null
        receipt.takeIf { it.matches(encoded, resolver.upstreamCommit, resolver.catalogueHash, DeckStudioServices.appBuild) }
    }
    val exclusionsAccepted = prepared?.excluded?.isEmpty() == true || acknowledgeExclusions
    LaunchedEffect(request) { state.prepare(request) }
    StudioPanel {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            SfImage("checkmark.shield", DeckStudioPalette.ink, 24.dp)
            Text("Ready to play?", color = DeckStudioPalette.ink, style = StudioText.title2.weight(SfWeight.semibold))
        }
        Text("Check Commander rules, then start a game against AI.", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
        if (prepared != null && prepared.excluded.isNotEmpty()) {
            StudioToggle("Validate the playing deck only", acknowledgeExclusions, { acknowledgeExclusions = it }, style = StudioText.subheadline)
            Text("${prepared.excluded.sumOf { it.quantity }} sideboard/maybeboard cards stay in this draft. Playing creates a separate playable copy; your original remains intact.",
                color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
        }
        if (currentReceipt != null) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                SfImage(if (currentReceipt.valid) "checkmark.circle" else "exclamationmark.triangle", DeckStudioPalette.ink, 16.dp)
                Text(if (currentReceipt.valid) "Commander validation passed" else "Commander validation found issues", color = DeckStudioPalette.ink,
                    style = StudioText.subheadline.weight(SfWeight.semibold))
            }
            StudioDisclosure("Validation details", titleStyle = StudioText.caption, color = DeckStudioPalette.secondaryInk) {
                Text("${formatDateTime(currentReceipt.checkedAt)} · installed XMage · app ${currentReceipt.appBuild}. Applies to these playing cards and this engine build.",
                    color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
            }
            for (issue in currentReceipt.issues) Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                issue.cardName?.takeIf { it.isNotEmpty() }?.let { Text(it, color = DeckStudioPalette.ink, style = StudioText.subheadline.weight(SfWeight.semibold)) }
                Text(issue.message, color = DeckStudioPalette.ink, style = StudioText.caption)
                Text(listOfNotNull(issue.type, issue.group).filter { it.isNotEmpty() }.joinToString(" · "), color = DeckStudioPalette.secondaryInk, style = StudioText.caption2)
            }
        } else Text("Not checked yet", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
        state.error?.let { Text(it, color = DeckStudioPalette.danger, style = StudioText.caption) }
        if (state.checking) {
            StudioProgress("Checking Commander rules…")
            StudioPlainButton("Cancel check", { state.cancelPending() })
            Text("Please wait for the engine to finish closing before playing.", color = DeckStudioPalette.ink, style = StudioText.caption2)
        }
        if (DeckStudioValidationService.cleanupRequired) {
            StudioButton("Finish closing", {
                scope.launch { try { DeckStudioValidationService.retryCleanup(); state.error = null } catch (failure: Exception) { state.error = failure.message } }
            }, primary = false, enabled = !DeckStudioValidationService.busy)
        } else {
            StudioButton(if (currentReceipt == null) "Validate deck" else "Validate again", {
                if (request != null && resolver != null && exclusionsAccepted) state.validate(request, resolver)
            }, Modifier.semantics { contentDescription = "deckStudio.validate" }, enabled = request != null && !DeckStudioValidationService.busy && exclusionsAccepted)
            if (play != null && prepared != null) StudioButton("Play against AI", { play(prepared.playing) }, Modifier.semantics { contentDescription = "deckStudio.playtestValidated" },
                primary = false, icon = "play.fill", enabled = currentReceipt?.valid == true && !DeckStudioValidationService.busy && exclusionsAccepted)
        }
        if (request == null && deck != null && resolver != null) {
            val message = runCatching { DeckStudioPlayProjection(deck).resolve(resolver); "" }.getOrElse { it.message ?: "" }
            if (message.isNotEmpty()) Text(message, color = DeckStudioPalette.warning, style = StudioText.caption)
        }
    }
}

private object MatchHistoryText {
    fun commanders(game: DeckStudioRecordedGame) = game.opponents?.flatMap { it.commanders } ?: emptyList()
    fun opponentName(game: DeckStudioRecordedGame) = game.opponents?.joinToString(" · ") { it.name }?.ifEmpty { null } ?: "AI opponent"
    fun result(game: DeckStudioRecordedGame) = when (game.end) {
        DeckStudioRecordedGame.End.COMPLETED -> game.won?.let { if (it) "Won" else "Not won" } ?: "Unknown"
        DeckStudioRecordedGame.End.IN_PROGRESS -> "In progress"
        DeckStudioRecordedGame.End.LEFT -> "Left game"
        DeckStudioRecordedGame.End.INTERRUPTED -> "Interrupted"
        DeckStudioRecordedGame.End.ENGINE_FAILED -> "Engine stopped"
    }
    fun duration(game: DeckStudioRecordedGame): String {
        val minutes = (game.elapsedSeconds / 60).toInt()
        return if (minutes >= 60) "${minutes / 60}h ${minutes % 60}m" else "${minutes}m"
    }
}

/** DeckStudioPlaytestInsightsView.swift: opt-in local history of AI games with this deck. */
@Composable
fun DeckStudioPlaytestInsightsView(signature: DeckStudioDeckSignature?, metadata: NativeDeckMetadataCatalogue?, openMatch: (DeckStudioRecordedGame, Boolean) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val store = DeckStudioServices.playtests
    var enabled by remember { mutableStateOf(store.admission().enabled) }
    var detailedEnabled by remember { mutableStateOf(store.admission().detailedEnabled) }
    var games by remember { mutableStateOf<List<DeckStudioRecordedGame>>(emptyList()) }
    var error by remember { mutableStateOf<String?>(null) }
    var clearConfirmation by remember { mutableStateOf(false) }
    var generation by remember { mutableStateOf(UUID.randomUUID()) }
    var allDecks by remember { mutableStateOf(false) }
    var result by remember { mutableStateOf("All results") }
    val results = listOf("All results", "Wins", "Not won", "Completed", "Unfinished")
    val selected = if (allDecks || signature == null) games else games.filter { it.deck == signature }
    val visible = selected.filter { game ->
        when (result) {
            "Wins" -> game.end == DeckStudioRecordedGame.End.COMPLETED && game.won == true
            "Not won" -> game.end == DeckStudioRecordedGame.End.COMPLETED && game.won == false
            "Completed" -> game.end == DeckStudioRecordedGame.End.COMPLETED
            "Unfinished" -> game.end != DeckStudioRecordedGame.End.COMPLETED
            else -> true
        }
    }
    fun refresh() {
        val token = generation
        scope.launch {
            try {
                val values = withContext(Dispatchers.IO) { store.summaries() }
                if (generation != token) return@launch
                games = values; error = store.failure
            } catch (failure: Exception) {
                if (generation == token) error = "Saved playtest history could not be read. It is preserved; use Clear all history only to deliberately discard it."
            }
        }
    }
    LaunchedEffect(signature) { if (signature == null) allDecks = true; refresh() }
    StudioPanel {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Game history", Modifier.weight(1f), color = DeckStudioPalette.ink, style = StudioText.title2.weight(SfWeight.semibold))
            Text(if (enabled) (if (detailedEnabled) "Detail on" else "Summaries on") else "Saving off", color = DeckStudioPalette.secondaryInk,
                style = StudioText.caption.weight(SfWeight.semibold))
        }
        StudioDisclosure("History settings & privacy", Modifier.semantics { contentDescription = "deckHistory.settings" }, label = {
            SfImage("info.circle", DeckStudioPalette.ink, 16.dp)
            Text("History settings & privacy", color = DeckStudioPalette.ink, style = StudioText.subheadline.weight(SfWeight.medium))
        }) {
            StudioToggle("Save AI game summaries", enabled, { value ->
                enabled = value; if (!value) detailedEnabled = false; store.setEnabled(value)
            })
            StudioToggle("Save detailed public game history", detailedEnabled, { value -> detailedEnabled = value; store.setDetailedEnabled(value) }, enabled = enabled)
            Text("Both choices are local and apply to future AI matches. Detail saves sampled public life totals, battlefield counts, visible cards and recognized public notices. It never saves hands, opponent decks or raw game messages. Turning detail off keeps saved history until you delete it.",
                color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
            Row {
                StudioPlainButton("Refresh history", ::refresh)
                Spacer(Modifier.weight(1f))
                StudioPlainButton("Clear all history", { clearConfirmation = true }, destructive = true)
            }
            Text("Up to 100 recent sessions within 8 MB; oldest sessions are removed first.", color = DeckStudioPalette.secondaryInk, style = StudioText.caption2)
        }
        error?.let { Text(it, color = DeckStudioPalette.warning, style = StudioText.caption) }
        if (signature == null) Text("Showing all decks · exact deck filter unavailable", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            StudioMenuPicker(if (allDecks) "All decks" else "This exact deck", {
                listOf(MenuEntry.Item("This exact deck", checked = !allDecks) { allDecks = false }, MenuEntry.Item("All decks", checked = allDecks) { allDecks = true })
            }, enabled = signature != null)
            StudioMenuPicker(result, { results.map { value -> MenuEntry.Item(value, checked = value == result) { result = value } } })
        }
        if (games.isEmpty()) {
            Text(if (enabled) "No saved matches yet." else "No saved matches. Enable summaries in History settings for future AI games.",
                color = DeckStudioPalette.ink, style = StudioText.subheadline)
        } else {
            val completed = selected.filter { it.end == DeckStudioRecordedGame.End.COMPLETED }
            Text("${selected.size} matches · ${completed.count { it.won == true }} confirmed wins", color = DeckStudioPalette.ink, style = StudioText.subheadline.weight(SfWeight.semibold))
            if (visible.isEmpty()) Text("No sessions match these filters.", color = DeckStudioPalette.ink, style = StudioText.subheadline)
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) { for (game in visible) MatchHistoryRow(game) { openMatch(it, false) } }
            StudioDisclosure("About these numbers", titleStyle = StudioText.caption) {
                Text("Exact deck means the same playing cards and quantities, not the title. Only confirmed outcomes count as wins or not-won. Life changes are not damage dealt; a visible card is not proof of a cast. Observations are not an engine replay. Older matches may lack detail or opponent names. Duration includes pauses.",
                    color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
            }
            StudioPlainButton("Export filtered history", {
                shareText(context, kotlinx.serialization.json.JsonArray(visible.map { it.json() }).toString())
            }, icon = "square.and.arrow.up")
        }
    }
    if (clearConfirmation) ConfirmationDialog("Delete all local game history?", "Decks are not deleted. Games already in progress will not restore the cleared history.",
        listOf(ConfirmationAction("Delete history", destructive = true) {
            generation = UUID.randomUUID()
            try { store.clear(); games = emptyList(); error = null } catch (failure: Exception) { error = "Could not remove the saved history. Existing data is preserved." }
        }), light = true) { clearConfirmation = false }
}

@Composable
private fun MatchHistoryRow(game: DeckStudioRecordedGame, open: (DeckStudioRecordedGame) -> Unit) {
    val commanders = MatchHistoryText.commanders(game)
    val opponentName = MatchHistoryText.opponentName(game)
    val commanderLabel = commanders.firstOrNull()?.let { if (commanders.size == 1) it else "$it +${commanders.size - 1}" } ?: opponentName
    Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 70.dp).background(DeckStudioPalette.surface, RoundedCornerShape(12.dp)).clip(RoundedCornerShape(12.dp))
        .clickable { open(game) }.padding(12.dp)
        .semantics { contentDescription = "$commanderLabel, $opponentName, versus your deck ${game.title}, ${MatchHistoryText.result(game)}, ${MatchHistoryText.duration(game)}" },
        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        if (commanders.isEmpty()) Box(Modifier.size(52.dp, 70.dp).background(DeckStudioPalette.background, RoundedCornerShape(5.dp)), contentAlignment = Alignment.Center) {
            SfImage("person.crop.rectangle.stack", DeckStudioPalette.ink, 22.dp)
        } else Box {
            commanders.take(3).forEachIndexed { index, name ->
                Box(Modifier.offset(x = (index * 34).dp).size(52.dp, 70.dp).clip(RoundedCornerShape(5.dp))
                    .border(2.dp, DeckStudioPalette.surface, RoundedCornerShape(5.dp))) { DeckStudioArtwork(name, Modifier.fillMaxSize()) }
            }
            Spacer(Modifier.width((52 + 34 * (minOf(3, commanders.size) - 1)).dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(commanderLabel, color = DeckStudioPalette.ink, style = StudioText.subheadline.weight(SfWeight.semibold), maxLines = 2)
            Text("$opponentName · vs your deck: ${game.title}", color = DeckStudioPalette.ink, style = StudioText.caption, maxLines = 2)
            Text(formatDateTime(game.startedAt), color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
            Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                for ((title, value) in listOf("Result" to MatchHistoryText.result(game), "Duration" to MatchHistoryText.duration(game),
                    "Turn" to (if (game.observedTurn > 0) "${game.observedTurn}" else "—"))) {
                    Column(Modifier.weight(1f).defaultMinSize(minHeight = 32.dp).background(DeckStudioPalette.surfaceElevated, RoundedCornerShape(7.dp)).padding(horizontal = 5.dp)) {
                        Text(title, color = DeckStudioPalette.secondaryInk, style = StudioText.caption2)
                        Text(value, color = DeckStudioPalette.ink, style = StudioText.caption.weight(SfWeight.semibold), maxLines = 1)
                    }
                }
            }
        }
        SfImage("chevron.right", DeckStudioPalette.secondaryInk, 12.dp, Modifier.align(Alignment.CenterVertically))
    }
}

/** MatchHistoryDashboard: one recorded match, full screen, with its sampled public timeline. */
@Composable
fun MatchHistoryDashboard(game: DeckStudioRecordedGame, exactDeck: Boolean, metadata: NativeDeckMetadataCatalogue?, dismiss: () -> Unit) {
    var sampleIndex by remember(game.id) { mutableStateOf(maxOf(0, (game.timeline?.samples?.size ?: 1) - 1)) }
    var inspected by remember { mutableStateOf<String?>(null) }
    val own = game.deck.rows.filter { it.section == "commanders" }.map { it.name }
    BackHandler { dismiss() }
    StudioScreen {
        Column(Modifier.fillMaxSize()) {
            StudioNavBar("Match history", leading = {
                StudioGlassGroup { StudioGlassIcon("chevron.left", "Back to history", dismiss) }
            })
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp).navigationBarsPadding()
                .semantics { contentDescription = "deckHistory.dashboard.scroll" }, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Column(Modifier.fillMaxWidth().background(DeckStudioPalette.surface, RoundedCornerShape(12.dp)).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    val opponents = game.opponents
                    if (!opponents.isNullOrEmpty()) opponents.forEachIndexed { index, opponent -> OpponentCard(opponent, index + 1) }
                    else Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        SfImage("person.crop.rectangle.stack", DeckStudioPalette.secondaryInk, 17.dp)
                        Text("Opponent identity and commander not recorded", color = DeckStudioPalette.secondaryInk, style = StudioText.subheadline.weight(SfWeight.medium))
                    }
                    Text("vs your deck · ${game.title.ifEmpty { "Untitled deck" }}", color = DeckStudioPalette.ink, style = StudioText.subheadline.weight(SfWeight.medium), maxLines = 2)
                    Text(formatDateTime(game.startedAt), color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for ((title, value) in listOf("Result" to MatchHistoryText.result(game), "Duration" to MatchHistoryText.duration(game),
                        "Turn" to (if (game.observedTurn > 0) "${game.observedTurn} observed" else "Not observed"))) {
                        Column(Modifier.weight(1f).defaultMinSize(minHeight = 64.dp).background(DeckStudioPalette.surfaceElevated, RoundedCornerShape(10.dp)).padding(12.dp),
                            verticalArrangement = Arrangement.spacedBy(5.dp)) {
                            Text(title, color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                            Text(value, color = DeckStudioPalette.ink, style = StudioText.headline)
                        }
                    }
                }
                val timeline = game.timeline
                if (timeline != null && timeline.samples.isNotEmpty()) ObservedTimeline(timeline, game.viewerPlayerID, sampleIndex, { sampleIndex = it }) { inspected = it }
                else Text(if (timeline == null) "Detailed history was not recorded for this match." else "No public game state was observed for detailed history.",
                    Modifier.fillMaxWidth().background(DeckStudioPalette.surface, RoundedCornerShape(12.dp)).padding(16.dp),
                    color = DeckStudioPalette.secondaryInk, style = StudioText.subheadline)
                Column(Modifier.fillMaxWidth().background(DeckStudioPalette.surface, RoundedCornerShape(12.dp)).padding(16.dp)) {
                    StudioDisclosure("Match info", titleStyle = StudioText.subheadline.weight(SfWeight.medium)) {
                        Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                            @Composable fun line(text: String) = Text(text, color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                            line(if (exactDeck) "Exact current playing deck" else "Historical playing deck · may differ from current draft")
                            line("Your commander: ${if (own.isEmpty()) "Not recorded" else own.joinToString(" · ")}")
                            line("${game.deck.rows.sumOf { it.count }} playing cards · ${game.deck.rows.size} distinct entries")
                            if (game.opponents == null) line("Opponent identity was not recorded.")
                            if (game.end != DeckStudioRecordedGame.End.COMPLETED) line("Unfinished session · no confirmed result")
                            game.commandZoneCasts.keys.sorted().forEach { line("$it: ${game.commandZoneCasts[it] ?: 0} observed command-zone casts") }
                            line("App ${game.appBuild} · XMage ${game.upstream} · catalogue ${game.catalogue}")
                        }
                    }
                }
            }
        }
    }
    inspected?.let { name ->
        BoardSheet({ inspected = null }, background = DeckStudioPalette.background, skipPartiallyExpanded = true, sound = false) {
            DeckStudioCardInspector(name, metadata?.card(name)) { inspected = null }
        }
    }
}

@Composable
private fun OpponentCard(opponent: DeckStudioRecordedGame.Opponent, number: Int) {
    Column(Modifier.fillMaxWidth().background(DeckStudioPalette.surfaceElevated, RoundedCornerShape(9.dp)).padding(10.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
        Text("Opponent $number · ${opponent.name}", color = DeckStudioPalette.ink, style = StudioText.subheadline.weight(SfWeight.semibold), maxLines = 2)
        Row(horizontalArrangement = Arrangement.spacedBy(9.dp)) {
            if (opponent.commanders.isEmpty()) Box(Modifier.size(50.dp, 70.dp).background(DeckStudioPalette.background, RoundedCornerShape(5.dp)), contentAlignment = Alignment.Center) {
                SfImage("person.crop.rectangle.stack", DeckStudioPalette.ink, 20.dp)
            } else Box {
                opponent.commanders.take(2).forEachIndexed { index, name ->
                    Box(Modifier.offset(x = (index * 30).dp).size(50.dp, 70.dp).clip(RoundedCornerShape(5.dp))
                        .border(2.dp, DeckStudioPalette.surface, RoundedCornerShape(5.dp))) { DeckStudioArtwork(name, Modifier.fillMaxSize()) }
                }
                Spacer(Modifier.width((50 + 30 * (minOf(2, opponent.commanders.size) - 1)).dp))
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                if (opponent.commanders.isEmpty()) Text("Commander not recorded", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
                else {
                    opponent.commanders.take(2).forEach { Text(it, color = DeckStudioPalette.ink, style = StudioText.caption, maxLines = 2) }
                    if (opponent.commanders.size > 2) StudioDisclosure("${opponent.commanders.size - 2} more commanders", titleStyle = StudioText.caption) {
                        opponent.commanders.drop(2).forEach { Text(it, color = DeckStudioPalette.ink, style = StudioText.caption) }
                    }
                }
            }
        }
    }
}

private val seriesColors = listOf(rgb(0.0, 0.48, 1.0), rgb(1.0, 0.58, 0.0), rgb(0.2, 0.78, 0.35), rgb(0.69, 0.32, 0.87))

/** Samples advance when a public metric or observation changes; scrubbing reviews the sampled evidence. */
@Composable
private fun ObservedTimeline(timeline: DeckStudioPublicTimeline, viewer: String?, sampleIndex: Int, select: (Int) -> Unit, inspect: (String) -> Unit) {
    var showAllEvents by remember { mutableStateOf(false) }
    val index = sampleIndex.coerceIn(0, timeline.samples.size - 1)
    val sample = timeline.samples[index]
    val last = timeline.samples.last().players
    val ordered = last.filter { it.id == viewer } + last.filter { it.id != viewer }
    val series = ordered.mapIndexed { position, player ->
        Triple(player.id, if (player.id == viewer) "You" else "Opponent ${position - (if (last.any { it.id == viewer }) 1 else 0) + 1} · ${player.name}",
            seriesColors[position % seriesColors.size])
    }
    val events = timeline.events.filter { event ->
        val isOutcome = index == timeline.samples.size - 1 && event.kind == DeckStudioPublicTimeline.Event.Kind.OUTCOME
        (event.revision <= sample.revision || isOutcome) && (showAllEvents || event.turn == sample.turn || isOutcome)
    }
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text("Turn review", Modifier.semantics { contentDescription = "deckHistory.timeline.dashboard" }, color = DeckStudioPalette.ink, style = StudioText.headline)
        Text("Public state observations · gaps between samples are unknown", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
        if (timeline.samplesTruncated || timeline.eventsTruncated) Text("History trimmed · earlier observations may be missing", color = DeckStudioPalette.warning, style = StudioText.caption)
        TimelineChart("Observed life", timeline, series, index) { it.life }
        TimelineChart("Battlefield count", timeline, series, index) { it.battlefieldCount }
        Column(Modifier.fillMaxWidth().background(DeckStudioPalette.surface, RoundedCornerShape(12.dp)).padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("${if (sample.turn > 0) "Turn ${sample.turn}" else "Turn not observed"} · observation ${index + 1}/${timeline.samples.size}", color = DeckStudioPalette.ink,
                style = StudioText.subheadline.weight(SfWeight.semibold))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                StudioIconButton("chevron.left", "Previous observation", { select(maxOf(0, index - 1)) }, enabled = index > 0)
                Box(Modifier.weight(1f)) {
                    if (timeline.samples.size >= 2) IosSlider(index.toFloat() / (timeline.samples.size - 1), { select((it * (timeline.samples.size - 1)).roundToInt()) },
                        tint = DeckStudioPalette.ink, label = "Game observation")
                }
                StudioIconButton("chevron.right", "Next observation", { select(minOf(timeline.samples.size - 1, index + 1)) }, enabled = index < timeline.samples.size - 1)
            }
            for (player in sample.players) Row {
                Text(if (player.id == viewer) "You" else player.name, Modifier.weight(1f), color = DeckStudioPalette.ink, style = StudioText.caption)
                Text("${player.life} life · ${player.battlefieldCount} permanents", color = DeckStudioPalette.ink, style = StudioText.caption)
            }
        }
        Column(Modifier.fillMaxWidth().background(DeckStudioPalette.surface, RoundedCornerShape(12.dp)).padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            StudioToggle("All events so far", showAllEvents, { showAllEvents = it }, style = StudioText.caption, tint = DeckStudioPalette.accent)
            Text(if (showAllEvents) "Public events so far" else "This turn’s public events", color = DeckStudioPalette.ink, style = StudioText.subheadline.weight(SfWeight.semibold))
            if (events.isEmpty()) Text("No recorded public events here.", color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
            for (event in events) Row(Modifier.defaultMinSize(minHeight = 49.dp), horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                val card = event.cardName
                if (card != null) Box(Modifier.size(36.dp, 49.dp).clip(RoundedCornerShape(4.dp))) { DeckStudioArtwork(card, Modifier.fillMaxSize()) }
                else Box(Modifier.size(36.dp, 44.dp), contentAlignment = Alignment.Center) { SfImage("flag.checkered", DeckStudioPalette.ink, 18.dp) }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(eventTitle(event, sample, viewer), color = DeckStudioPalette.ink, style = StudioText.caption.weight(SfWeight.semibold))
                    event.typeLine?.let { Text(it, color = DeckStudioPalette.ink, style = StudioText.caption2) }
                    Text("Turn ${event.turn}", color = DeckStudioPalette.ink, style = StudioText.caption2)
                }
                if (card != null) StudioIconButton("rectangle.portrait.and.arrow.right", "Inspect $card", { inspect(card) })
            }
        }
        Column(Modifier.fillMaxWidth().background(DeckStudioPalette.surface, RoundedCornerShape(12.dp)).padding(14.dp)) {
            StudioDisclosure("About this review", titleStyle = StudioText.caption.weight(SfWeight.medium)) {
                Text("These are sampled public states and recognized public events, not a full engine replay. The charts follow successful observations; gaps are unknown. Life changes are not damage dealt. A card appearing on the battlefield or stack is not proof of a cast. Observation numbers are not turns.",
                    color = DeckStudioPalette.secondaryInk, style = StudioText.caption)
            }
        }
    }
}

private fun eventTitle(event: DeckStudioPublicTimeline.Event, sample: DeckStudioPublicTimeline.Sample, viewer: String?): String {
    val player = sample.players.firstOrNull { it.id == event.playerID }
    return when (event.kind) {
        DeckStudioPublicTimeline.Event.Kind.BATTLEFIELD_APPEARANCE -> "${event.cardName ?: "Card"} seen on ${if (player?.id == viewer) "your" else "an opponent's"} battlefield"
        DeckStudioPublicTimeline.Event.Kind.SPELL_ON_STACK -> "${event.cardName ?: "Spell"} seen on stack"
        DeckStudioPublicTimeline.Event.Kind.CAST -> "${if (player?.id == viewer) "You" else player?.name ?: "Opponent"} cast ${event.cardName ?: "a card"}"
        DeckStudioPublicTimeline.Event.Kind.DAMAGE -> "${event.cardName ?: "A card"} dealt ${event.amount ?: 0} damage to ${if (player?.id == viewer) "you" else player?.name ?: "an opponent"}"
        DeckStudioPublicTimeline.Event.Kind.LIFE_CHANGE -> "${if (player?.id == viewer) "You" else player?.name ?: "Opponent"} ${if ((event.amount ?: 0) < 0) "lost" else "gained"} ${abs(event.amount ?: 0)} life"
        DeckStudioPublicTimeline.Event.Kind.TURN_STARTED -> "Turn ${event.turn} began"
        DeckStudioPublicTimeline.Event.Kind.PHASE -> "${event.phaseName?.replace("_", " ")?.lowercase()?.split(" ")?.joinToString(" ") { it.replaceFirstChar(Char::uppercase) } ?: "Phase"} phase"
        DeckStudioPublicTimeline.Event.Kind.OUTCOME -> when (event.outcome) {
            "won" -> "Confirmed win"; "notWon" -> "Game ended · you did not win"; else -> "Game ended · result unknown"
        }
    }
}

/** A line chart of one public metric per player, with the selected observation marked. */
@Composable
private fun TimelineChart(title: String, timeline: DeckStudioPublicTimeline, series: List<Triple<String, String, Color>>, index: Int,
                          value: (DeckStudioPublicTimeline.Player) -> Int) {
    val measurer = rememberTextMeasurer()
    val step = maxOf(1, timeline.samples.size / 240)
    val points = timeline.samples.withIndex().filter { (position, _) -> position % step == 0 || position == timeline.samples.size - 1 }
    val values = points.flatMap { (_, sample) -> sample.players.map(value) }
    val low = minOf(0, values.minOrNull() ?: 0); val high = maxOf(1, values.maxOrNull() ?: 1)
    val count = maxOf(2, timeline.samples.size)
    Column(Modifier.fillMaxWidth().background(DeckStudioPalette.surfaceElevated, RoundedCornerShape(12.dp)).padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, color = DeckStudioPalette.ink, style = StudioText.subheadline.weight(SfWeight.semibold))
        Canvas(Modifier.fillMaxWidth().height(170.dp).semantics { contentDescription = "$title trend over ${timeline.samples.size} observed states" }) {
            val left = 34.dp.toPx(); val bottom = size.height - 30.dp.toPx(); val top = 6.dp.toPx(); val right = size.width - 6.dp.toPx()
            fun x(observation: Int) = left + (right - left) * (observation - 1) / (count - 1).toFloat()
            fun y(v: Int) = bottom - (bottom - top) * (v - low) / (high - low).toFloat()
            val label = io.magicmobile.android.ui.sf(10f).copy(color = DeckStudioPalette.secondaryInk)
            for (tick in 0..3) {
                val v = low + (high - low) * tick / 3
                drawLine(DeckStudioPalette.separator, Offset(left, y(v)), Offset(right, y(v)), 1f)
                drawText(measurer, "$v", Offset(0f, y(v) - 7.dp.toPx()), label)
            }
            for (tick in 0..3) {
                val observation = 1 + (count - 1) * tick / 3
                drawText(measurer, "$observation", Offset(x(observation) - 4.dp.toPx(), bottom + 4.dp.toPx()), label)
            }
            drawText(measurer, "Observation", Offset((left + right) / 2 - 28.dp.toPx(), bottom + 16.dp.toPx()), label)
            drawLine(DeckStudioPalette.accent.copy(alpha = 0.55f), Offset(x(index + 1), top), Offset(x(index + 1), bottom), 1.dp.toPx(),
                pathEffect = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 3.dp.toPx())))
            for ((id, _, color) in series) {
                val path = Path()
                points.forEachIndexed { i, (position, sample) ->
                    val player = sample.players.firstOrNull { it.id == id } ?: return@forEachIndexed
                    val point = Offset(x(position + 1), y(value(player)))
                    if (i == 0) path.moveTo(point.x, point.y) else path.lineTo(point.x, point.y)
                    drawCircle(color, 2.2.dp.toPx(), point)
                }
                drawPath(path, color, style = Stroke(2.dp.toPx()))
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
            for ((_, label, color) in series) Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(9.dp).background(color, CircleShape))
                Text(label, color = DeckStudioPalette.ink, style = StudioText.caption2, maxLines = 2)
            }
        }
    }
}
