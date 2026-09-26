package io.magicmobile.android.studio

import io.magicmobile.android.core.CardEntry
import io.magicmobile.android.core.Deck
import io.magicmobile.android.core.DeckSections
import io.magicmobile.android.game.J
import io.magicmobile.android.game.array
import io.magicmobile.android.game.bool
import io.magicmobile.android.game.get
import io.magicmobile.android.game.integer
import io.magicmobile.android.game.isUuid
import io.magicmobile.android.game.string
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.util.UUID

/** Models.swift DeckEntry. */
data class DeckEntry(val cardName: String, val quantity: Int, val section: String) {
    fun json(): JsonObject = JsonObject(sortedMapOf("cardName" to JsonPrimitive(cardName),
        "quantity" to JsonPrimitive(quantity), "section" to JsonPrimitive(section)))

    companion object {
        fun decode(value: J?): DeckEntry {
            val name = value["cardName"].string; val quantity = value["quantity"].integer; val section = value["section"].string
            if (name == null || quantity == null || section == null || quantity !in Int.MIN_VALUE..Int.MAX_VALUE) throw DeckEditingError.InvalidEntry
            return DeckEntry(name, quantity.toInt(), section)
        }
    }
}

/** Models.swift DeckList: the primary commander apart, partners and other boards in entries. */
data class DeckList(val name: String, val commander: DeckEntry?, val entries: List<DeckEntry>) {
    val totalCards: Int get() = (commander?.quantity ?: 0) + entries.sumOf { it.quantity }

    /** Swift's JSONEncoder: keys sorted, a missing commander omitted. */
    fun json(): JsonObject {
        val fields = sortedMapOf<String, JsonElement>("entries" to JsonArray(entries.map { it.json() }), "name" to JsonPrimitive(name))
        commander?.let { fields["commander"] = it.json() }
        return JsonObject(fields)
    }

    /**
     * The Android library keeps one entry list with the primary commander first in the
     * commander section, the shape build 7 saved. Card names and quantities are unchanged.
     */
    fun storedDeck(): Deck = Deck(name, listOfNotNull(commander?.let { CardEntry(it.cardName, it.quantity, "commanders") }) +
        entries.map { CardEntry(it.cardName, it.quantity, DeckSections.normalize(it.section)) })

    companion object {
        fun decode(value: J?): DeckList {
            val name = value["name"].string ?: throw DeckEditingError.InvalidName
            val rows = value["entries"].array ?: throw DeckEditingError.InvalidEntry
            val commander = value["commander"]?.takeIf { it !is JsonNull }?.let(DeckEntry::decode)
            return DeckList(name, commander, rows.map(DeckEntry::decode))
        }

        /** The first commander-section entry is the primary commander, as the link importer decides. */
        fun fromStored(deck: Deck): DeckList {
            val index = deck.entries.indexOfFirst { it.section == "commanders" }
            val rows = deck.entries.map { DeckEntry(it.name, it.quantity, it.section) }
            return DeckList(deck.name, rows.getOrNull(index), rows.filterIndexed { i, _ -> i != index })
        }
    }
}

/** OnDeviceDeckEditing.Error. Messages match the iOS app. */
sealed class DeckEditingError(message: String) : Exception(message) {
    object InvalidName : DeckEditingError("Give this draft a nonempty name of at most 512 UTF-8 bytes.")
    object InvalidEntry : DeckEditingError("Card names and sections must be nonempty and at most 2,000 UTF-8 bytes. Quantities must be 1–2,000, with at most 2,000 cards total.")
    object MultiplePrimaryCommanders : DeckEditingError("Only one row may be marked as the primary commander. Keep partners in the commander section.")
    object OversizedJSON : DeckEditingError("Draft JSON must be at most 2 MiB.")
    object MissingEntry : DeckEditingError("That card row changed. Reopen the draft.")
    object MissingRecord : DeckEditingError("That saved deck no longer exists.")
    object StaleRevision : DeckEditingError("The saved library changed. Reopen it before saving again.")
    object CopyRequired : DeckEditingError("Make a local editing copy of this cloud deck first.")
    object UnreadableCache : DeckEditingError("The saved library is unreadable. Preserve it before recovery.")
}

val String.utf8Size: Int get() = toByteArray(Charsets.UTF_8).size
/** Swift `trimmingCharacters(in: .whitespaces)`: spaces and tabs, not line breaks. */
internal fun String.trimSpaces(): String = trim { it == ' ' || it == '\t' || it == ' ' || Character.getType(it) == Character.SPACE_SEPARATOR.toInt() }

/** OnDeviceDeckEditing.swift NativeDeckRow. */
data class NativeDeckRow(
    val id: UUID = UUID.randomUUID(),
    val cardName: String = "",
    val quantity: Int = 1,
    val section: String = "deck",
    /** Clear when the user explicitly changes this row's section. */
    val isPrimaryCommander: Boolean = false,
) {
    fun json(): JsonObject = JsonObject(sortedMapOf("cardName" to JsonPrimitive(cardName), "id" to JsonPrimitive(id.toString().uppercase()),
        "isPrimaryCommander" to JsonPrimitive(isPrimaryCommander), "quantity" to JsonPrimitive(quantity), "section" to JsonPrimitive(section)))

    companion object {
        fun decode(value: J?): NativeDeckRow {
            val id = value["id"].string?.takeIf(::isUuid) ?: throw DeckEditingError.InvalidEntry
            val quantity = value["quantity"].integer?.takeIf { it in Int.MIN_VALUE..Int.MAX_VALUE } ?: throw DeckEditingError.InvalidEntry
            return NativeDeckRow(UUID.fromString(id), value["cardName"].string ?: throw DeckEditingError.InvalidEntry, quantity.toInt(),
                value["section"].string ?: throw DeckEditingError.InvalidEntry, value["isPrimaryCommander"].bool ?: throw DeckEditingError.InvalidEntry)
        }
    }
}

/** OnDeviceDeckEditing.swift NativeDeckDraft. */
data class NativeDeckDraft(val name: String = "New Commander Deck", val rows: List<NativeDeckRow> = emptyList()) {
    private fun isMainBasicLand(row: NativeDeckRow, name: String): Boolean =
        row.cardName == name && !row.isPrimaryCommander && row.section.trim().lowercase() in setOf("deck", "main")

    fun basicLandCount(name: String): Int = rows.filter { isMainBasicLand(it, name) }.sumOf { it.quantity }

    /** A deliberate main-deck edit, never an automatic mana-base recommendation. */
    fun settingBasicLandCount(name: String, quantity: Int): NativeDeckDraft {
        if (name !in basicLandNames || quantity !in 0..2000) throw DeckEditingError.InvalidEntry
        val existing = rows.firstOrNull { isMainBasicLand(it, name) }
        val kept = rows.filterNot { isMainBasicLand(it, name) }
        val updated = copy(rows = if (quantity > 0) kept + (existing ?: NativeDeckRow(cardName = name)).copy(quantity = quantity) else kept)
        // Check entries and count without making an unfinished name prevent editing.
        updated.copy(name = "Draft").deck()
        return updated
    }

    fun deck(): DeckList {
        val marked = rows.indices.filter { rows[it].isPrimaryCommander }
        if (marked.size > 1) throw DeckEditingError.MultiplePrimaryCommanders
        val primary = marked.firstOrNull() ?: rows.indexOfFirst { it.section.trim().lowercase() in setOf("commander", "commanders") }
        var commander: DeckEntry? = null
        val entries = ArrayList<DeckEntry>()
        rows.forEachIndexed { index, row ->
            val entry = DeckEntry(row.cardName, row.quantity, row.section)
            if (index == primary) commander = entry else entries += entry
        }
        val result = DeckList(name, commander, entries)
        OnDeviceDeckEditing.validateDraft(result)
        return result
    }

    fun exportJSON(): String = OnDeviceDeckEditing.exportJSON(deck())

    fun json(): JsonObject = JsonObject(sortedMapOf("name" to JsonPrimitive(name), "rows" to JsonArray(rows.map { it.json() })))

    companion object {
        val basicLandNames = listOf("Plains", "Island", "Swamp", "Mountain", "Forest", "Wastes")

        fun of(deck: DeckList): NativeDeckDraft = NativeDeckDraft(deck.name,
            listOfNotNull(deck.commander).map { NativeDeckRow(cardName = it.cardName, quantity = it.quantity, section = it.section, isPrimaryCommander = true) } +
                deck.entries.map { NativeDeckRow(cardName = it.cardName, quantity = it.quantity, section = it.section) })

        fun importJSON(text: String): NativeDeckDraft = of(OnDeviceDeckEditing.importJSON(text))

        fun decode(value: J?): NativeDeckDraft = NativeDeckDraft(value["name"].string ?: throw DeckEditingError.InvalidName,
            (value["rows"].array ?: throw DeckEditingError.InvalidEntry).map(NativeDeckRow::decode))
    }
}

/** A small key-value store: SharedPreferences on the phone, a map in tests. */
interface StudioDefaults {
    fun string(key: String): String?
    fun set(key: String, value: String)
    fun remove(key: String)
    fun keys(): Set<String>
}

class MemoryDefaults : StudioDefaults {
    val values = LinkedHashMap<String, String>()
    override fun string(key: String) = values[key]
    override fun set(key: String, value: String) { values[key] = value }
    override fun remove(key: String) { values.remove(key) }
    override fun keys() = values.keys.toSet()
}

/** Recovery is separate from saved/playable decks and retains incomplete names and row IDs. */
object NativeDeckDraftRecovery {
    private const val prefix = "deckStudio.draft."

    fun load(key: String, defaults: StudioDefaults): NativeDeckDraft? {
        val text = defaults.string(prefix + key) ?: return null
        if (text.utf8Size > OnDeviceDeckEditing.maximumJSONBytes) throw DeckEditingError.OversizedJSON
        val draft = NativeDeckDraft.decode(Json.parseToJsonElement(text))
        draft.copy(name = "Recovery").deck()
        return draft
    }

    fun save(draft: NativeDeckDraft, key: String, defaults: StudioDefaults) {
        val text = draft.json().toString()
        if (text.utf8Size > OnDeviceDeckEditing.maximumJSONBytes) throw DeckEditingError.OversizedJSON
        defaults.set(prefix + key, text)
    }

    fun clear(key: String, defaults: StudioDefaults) = defaults.remove(prefix + key)

    /** Remove every revision only after the library deletion succeeds; keep the new-deck slot. */
    fun clearRecord(recordID: String, defaults: StudioDefaults) {
        val start = "$prefix$recordID."
        defaults.keys().filter { it.startsWith(start) && it.removePrefix(start).toLongOrNull() != null }.forEach(defaults::remove)
    }
}

/**
 * Lossless local draft editing, not rules validation (OnDeviceDeckEditing.swift). Resolve exact
 * supported names before play. Unknown sections stay intact until explicitly edited.
 */
object OnDeviceDeckEditing {
    const val maximumJSONBytes = 2 * 1024 * 1024

    data class TextAnnotation(val line: Int, val text: String)
    data class TextImport(val deck: DeckList, val annotations: List<TextAnnotation>)
    class TextImportError(val line: Int, val reason: String) : Exception("Line $line: $reason No cards were imported.")

    private fun sectionName(heading: String): String? = when (heading.lowercase()) {
        "deck", "main", "mainboard" -> "deck"
        "commander", "commanders" -> "commanders"
        "companion", "companions" -> "companions"
        "sideboard" -> "sideboard"
        "maybeboard", "considering" -> "maybeboard"
        else -> null
    }

    private val bulkTags = Regex("""\s+#!.+$""")
    private val label = Regex("""\s+\^[^^\r\n]+,#[0-9A-Fa-f]{6}\^$""")
    private val bracket = Regex("""\s+\[[^\[\]\r\n]+\]$""")
    private val foil = Regex("""\s+\*(?:F|E)\*$""")
    private val printing = Regex("""\s+\([A-Za-z0-9]+\)(?:\s+[A-Za-z0-9★†-]+)?$""")
    private val strayDecoration = Regex("""\s+\*[^*]*\*$""")

    /**
     * Explicit text-export grammar only, not CSV/JSON or arbitrary provider text. Unknown card
     * names and custom sections survive as draft data; the caller shows annotations and
     * resolves names before play.
     */
    fun importText(text: String, name: String): TextImport {
        if (text.utf8Size > maximumJSONBytes) throw TextImportError(1, "Deck text exceeds 2 MiB.")
        validateDraft(DeckList(name, null, emptyList()))
        val rows = ArrayList<NativeDeckRow>()
        val annotations = ArrayList<TextAnnotation>()
        var section = "deck"
        var total = 0
        val lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
        for ((offset, raw) in lines.withIndex()) {
            val number = offset + 1
            fun invalid(reason: String) = TextImportError(number, reason)
            var line = raw.trimSpaces()
            if (offset == 0 && line.startsWith("﻿")) line = line.substring(1)
            line = line.trimSpaces()
            if (line.isEmpty()) continue
            var heading = line
            val explicitHeading = heading.startsWith("//") || heading.startsWith("#") || heading.endsWith(":")
            if (heading.startsWith("//")) heading = heading.substring(2) else if (heading.startsWith("#")) heading = heading.substring(1)
            heading = heading.trimSpaces()
            if (heading.endsWith(":")) heading = heading.dropLast(1)
            heading = heading.trimSpaces()
            val known = sectionName(heading)
            if (known != null) { section = known; continue }
            if (explicitHeading && line.firstOrNull()?.isDigit() != true) {
                if (heading.isEmpty() || heading.utf8Size > 2000) throw invalid("Invalid section heading.")
                annotations += TextAnnotation(number, "Grouping retained in $section: $heading")
                continue
            }
            val split = line.indexOfFirst { it.isWhitespace() }
            val token = if (split < 0) line else line.substring(0, split)
            val digits = if (token.lowercase().endsWith("x")) token.dropLast(1) else token
            val count = digits.takeIf { d -> d.isNotEmpty() && d.all { it in '0'..'9' } }?.toIntOrNull()
            if (split < 0 || count == null || count !in 1..2000 || count > 2000 - total) {
                throw invalid("Use '1 Card Name' or '1x Card Name', with at most 2,000 cards total. Mark custom headings with // or a trailing colon.")
            }
            var cardName = line.substring(split + 1).trimSpaces()
            var rowSection = section
            fun takeSuffix(pattern: Regex): String? {
                val match = pattern.find(cardName) ?: return null
                cardName = cardName.removeRange(match.range)
                return match.value.trimSpaces()
            }
            // Moxfield bulk tags have their own delimiter; punctuation inside names is untouched.
            takeSuffix(bulkTags)?.let { annotations += TextAnnotation(number, it) }
            takeSuffix(label)?.let { annotations += TextAnnotation(number, it) }
            takeSuffix(bracket)?.let { category ->
                var value = category.drop(1).dropLast(1).trimSpaces()
                if (value.endsWith("{top}")) {
                    value = value.dropLast(5).trimSpaces()
                    if (sectionName(value) != "commanders") throw invalid("Only [Commander{top}] is supported as a premier category.")
                }
                if (value.isEmpty()) throw invalid("Empty bracket category.")
                if ("{" in value || "}" in value) throw invalid("Unsupported category flags; specify the intended deck section explicitly.")
                val mapped = sectionName(value)
                // A category under an explicit non-main section must not silently move it.
                if (section != "deck" && mapped != null && mapped != section) throw invalid("Bracket category conflicts with the current section.")
                if (mapped != null) rowSection = mapped
                annotations += TextAnnotation(number, "Category retained: $category")
            }
            takeSuffix(foil)?.let { annotations += TextAnnotation(number, it) }
            takeSuffix(printing)?.let { annotations += TextAnnotation(number, it) }
            // Fail on malformed or unrecognized export decorations rather than import an altered name.
            if ("[" in cardName || "]" in cardName || "^" in cardName || "#!" in cardName || strayDecoration.containsMatchIn(cardName)) {
                throw invalid("Unsupported or malformed export suffix; use one bracket category and the documented printing/foil/label syntax.")
            }
            cardName = cardName.trimSpaces()
            try { validate(DeckEntry(cardName, count, rowSection)) } catch (error: DeckEditingError) { throw invalid("Card name or section is empty or too long.") }
            rows += NativeDeckRow(cardName = cardName, quantity = count, section = rowSection)
            total += count
        }
        if (rows.isEmpty()) throw TextImportError(1, "The list has no card rows.")
        return TextImport(NativeDeckDraft(name, rows).deck(), annotations)
    }

    fun validateDraft(deck: DeckList) {
        if (deck.name.utf8Size > 512 || deck.name.isBlank()) throw DeckEditingError.InvalidName
        deck.commander?.let(::validate)
        var count = deck.commander?.quantity ?: 0
        for (entry in deck.entries) {
            validate(entry)
            if (entry.quantity > 2000 - count) throw DeckEditingError.InvalidEntry
            count += entry.quantity
        }
    }

    private fun validate(entry: DeckEntry) {
        if (entry.quantity !in 1..2000 || entry.cardName.utf8Size > 2000 || entry.section.utf8Size > 2000 ||
            entry.cardName.isBlank() || entry.section.isBlank()) throw DeckEditingError.InvalidEntry
    }

    private val pretty = Json { prettyPrint = true }

    /** JSON draft exchange preserves every section and name verbatim, unlike lossy text. */
    fun exportJSON(deck: DeckList): String {
        validateDraft(deck)
        val text = pretty.encodeToString(JsonElement.serializer(), deck.json())
        if (text.utf8Size > maximumJSONBytes) throw DeckEditingError.OversizedJSON
        return text
    }

    fun importJSON(text: String): DeckList {
        if (text.utf8Size > maximumJSONBytes) throw DeckEditingError.OversizedJSON
        val value = try { Json.parseToJsonElement(text) } catch (error: Exception) { throw DeckEditingError.InvalidEntry }
        if (value !is JsonObject) throw DeckEditingError.InvalidEntry
        val deck = DeckList.decode(value)
        validateDraft(deck)
        return deck
    }
}
