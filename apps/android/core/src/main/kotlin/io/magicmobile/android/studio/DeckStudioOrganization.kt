package io.magicmobile.android.studio

import io.magicmobile.android.game.J
import io.magicmobile.android.game.array
import io.magicmobile.android.game.bool
import io.magicmobile.android.game.get
import io.magicmobile.android.game.integer
import io.magicmobile.android.game.isUuid
import io.magicmobile.android.game.obj
import io.magicmobile.android.game.string
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.io.File
import java.text.Normalizer

/** Optional local authoring data; never part of the deck sent to XMage or a web service. */
data class DeckStudioOrganization(
    val tags: List<String> = emptyList(),
    val notes: String = "",
    val importAnnotations: List<String> = emptyList(),
    val importedFrom: String? = null,
    val importReceiptFile: String? = null,
    val importAnnotationCount: Int? = null,
) {
    fun validated(): DeckStudioOrganization {
        if (tags.size > 24 || notes.utf8Size > 16_384 || importAnnotations.size > 2000 ||
            !importAnnotations.all { it.utf8Size <= 8192 && '\u0000' !in it } || (importedFrom?.utf8Size ?: 0) > 2048 ||
            importAnnotationCount?.let { it !in 0..2_000_000 || it < importAnnotations.size } == true ||
            importReceiptFile?.let { !validReceiptFile(it) } == true || '\u0000' in notes || importedFrom?.contains('\u0000') == true) throw Failure.Invalid
        val seen = HashSet<String>()
        val checked = tags.mapNotNull { raw ->
            val tag = raw.trim()
            if (tag.isEmpty() || tag.utf8Size > 80 || tag.any { Character.isISOControl(it) }) throw Failure.Invalid
            val key = Normalizer.normalize(tag, Normalizer.Form.NFD).replace(Regex("\\p{M}+"), "").lowercase()
            if (seen.add(key)) tag else null
        }
        return copy(tags = checked)
    }

    fun json(): JsonObject = JsonObject(sortedMapOf<String, JsonElement>().apply {
        put("tags", JsonArray(tags.map(::JsonPrimitive))); put("notes", JsonPrimitive(notes))
        put("importAnnotations", JsonArray(importAnnotations.map(::JsonPrimitive)))
        importedFrom?.let { put("importedFrom", JsonPrimitive(it)) }
        importReceiptFile?.let { put("importReceiptFile", JsonPrimitive(it)) }
        importAnnotationCount?.let { put("importAnnotationCount", JsonPrimitive(it)) }
    })

    sealed class Failure(message: String) : Exception(message) {
        object Invalid : Failure("Use up to 24 tags (80 bytes each), 16 KiB of notes, and a bounded import receipt. Existing data is unchanged.")
        object Corrupt : Failure("Saved deck details could not be read safely. The original file is preserved; card editing still works.")
        object Conflict : Failure("Deck details changed elsewhere. Close and reopen Details before saving; the newer version was preserved.")
        object Unavailable : Failure("Local deck-detail storage is unavailable. Your deck cards are unchanged.")
    }

    companion object {
        const val maximumBytes = 512 * 1024
        fun validReceiptFile(name: String): Boolean = name.endsWith(".json") && name.length == 41 && isUuid(name.dropLast(5))

        fun decode(value: J?): DeckStudioOrganization {
            fun strings(key: String) = (value[key].array ?: throw Failure.Corrupt).map { it.string ?: throw Failure.Corrupt }
            fun optional(key: String) = value[key]?.takeIf { it !is JsonNull }?.let { it.string ?: throw Failure.Corrupt }
            return DeckStudioOrganization(strings("tags"), value["notes"].string ?: throw Failure.Corrupt, strings("importAnnotations"),
                optional("importedFrom"), optional("importReceiptFile"),
                value["importAnnotationCount"]?.takeIf { it !is JsonNull }?.let { (it.integer ?: throw Failure.Corrupt).toInt() })
        }
    }
}

/**
 * Content revision is separate from the deck record's card-list revision, so two editors
 * cannot silently overwrite each other's notes or tags.
 */
class DeckStudioOrganizationStore(private val directory: File?, val receiptDirectory: File?) {
    data class Snapshot(val value: DeckStudioOrganization, val revision: Int)

    @Synchronized fun load(recordID: String): Snapshot {
        val file = file(recordID)
        if (!file.exists()) return Snapshot(DeckStudioOrganization(), 0)
        try {
            if (file.length() > DeckStudioOrganization.maximumBytes) throw DeckStudioOrganization.Failure.Corrupt
            val bytes = file.readBytes()
            if (bytes.size > DeckStudioOrganization.maximumBytes) throw DeckStudioOrganization.Failure.Corrupt
            val envelope = Json.parseToJsonElement(String(bytes, Charsets.UTF_8))
            val revision = envelope["revision"].integer ?: throw DeckStudioOrganization.Failure.Corrupt
            val value = DeckStudioOrganization.decode(envelope["value"])
            if (envelope["schema"].integer != 1L || envelope["recordID"].string != recordID || revision !in 1..1_000_000_000 ||
                value.validated() != value) throw DeckStudioOrganization.Failure.Corrupt
            return Snapshot(value, revision.toInt())
        } catch (error: Exception) { throw DeckStudioOrganization.Failure.Corrupt }
    }

    @Synchronized fun save(value: DeckStudioOrganization, recordID: String, expectedRevision: Int): Snapshot {
        val existing = load(recordID)
        if (existing.revision != expectedRevision || expectedRevision >= 1_000_000_000) throw DeckStudioOrganization.Failure.Conflict
        val checked = value.validated()
        val snapshot = Snapshot(checked, existing.revision + 1)
        val data = JsonObject(sortedMapOf("recordID" to JsonPrimitive(recordID), "revision" to JsonPrimitive(snapshot.revision),
            "schema" to JsonPrimitive(1), "value" to checked.json())).toString().toByteArray(Charsets.UTF_8)
        if (data.size > DeckStudioOrganization.maximumBytes) throw DeckStudioOrganization.Failure.Invalid
        val file = file(recordID)
        file.parentFile?.mkdirs()
        val temporary = File(file.parentFile, file.name + ".tmp")
        temporary.writeBytes(data)
        if (!temporary.renameTo(file)) { temporary.delete(); throw DeckStudioOrganization.Failure.Unavailable }
        return snapshot
    }

    @Synchronized fun retainImport(recordID: String, annotations: List<String>, source: String?, receiptFile: String? = null) {
        val old = load(recordID)
        val value = old.value
        // A large import stays fully preserved in its receipt, not stuffed into this small record.
        val small = annotations.size <= 2000 && annotations.all { it.utf8Size <= 8192 } && annotations.sumOf { it.utf8Size } <= 128 * 1024
        if (!small && receiptFile == null) throw DeckStudioOrganization.Failure.Invalid
        val inline = if (small) annotations else emptyList()
        if (value.importReceiptFile != null || value.importAnnotationCount != null || value.importAnnotations.isNotEmpty() || value.importedFrom != null) {
            if (value.importReceiptFile != receiptFile || value.importAnnotations != inline ||
                (value.importAnnotationCount ?: value.importAnnotations.size) != annotations.size || value.importedFrom != source) throw DeckStudioOrganization.Failure.Conflict
            return
        }
        save(value.copy(importAnnotations = inline, importedFrom = source, importReceiptFile = receiptFile, importAnnotationCount = annotations.size),
            recordID, old.revision)
    }

    @Synchronized fun duplicate(from: String, to: String) {
        val original = load(from)
        if (original.revision <= 0) return
        save(original.value, to, 0)
    }

    @Synchronized fun delete(recordID: String) { file(recordID).takeIf { it.exists() }?.delete() }

    /** Nonessential index failures do not hide cards or touch unreadable files. */
    fun tagIndex(recordIDs: List<String>): Map<String, List<String>> =
        recordIDs.take(4000).mapNotNull { id -> runCatching { id to load(id).value.tags }.getOrNull() }.toMap()

    /** Only an app-created UUID file name can resolve inside the receipt directory. */
    fun receiptFile(value: DeckStudioOrganization): File? {
        val name = value.importReceiptFile?.takeIf(DeckStudioOrganization::validReceiptFile) ?: return null
        return receiptDirectory?.let { File(it, name) }
    }

    private fun file(id: String): File {
        val directory = directory
        if (directory == null || id.isEmpty() || id.utf8Size > 256 || id.any { Character.isISOControl(it) }) throw DeckStudioOrganization.Failure.Unavailable
        // The ID never becomes a path. Full stored-ID validation rejects hash collisions.
        var hash = -0x340d631b7bdddcdbL // 14695981039346656037
        for (byte in id.toByteArray(Charsets.UTF_8)) hash = (hash xor (byte.toLong() and 0xff)) * 1099511628211L
        return File(directory, "details-${java.lang.Long.toUnsignedString(hash, 16)}.json")
    }
}

/** DeckStudioRoleAnalysis.swift: explainable functional-role hints, not a deck score. */
enum class DeckStudioRole(val key: String, val title: String) {
    RAMP("ramp", "Ramp"),
    CARD_FLOW("cardFlow", "Draw / card flow"),
    INTERACTION("interaction", "Targeted interaction"),
    BOARD_WIPE("boardWipe", "Board wipes"),
    PROTECTION("protection", "Protection"),
    GRAVEYARD_HATE("graveyardHate", "Graveyard interaction"),
    RECURSION("recursion", "Recursion"),
    TUTOR("tutor", "Tutors");

    companion object { fun of(key: String): DeckStudioRole? = entries.firstOrNull { it.key == key } }
}

data class DeckStudioRoleEvidence(val role: DeckStudioRole, val source: Source, val explanation: String) {
    enum class Source { REVIEWED, CURATED, TEXT_PATTERN }
}

object DeckStudioRoleClassifier {
    private class Rule(val role: DeckStudioRole, pattern: String, val explanation: String) { val expression = Regex(pattern) }

    private val rules = listOf(
        Rule(DeckStudioRole.RAMP, """^\{t\}: add (?:\{[wubrgc]\})+\.""", "A nonland permanent has a direct tap-for-mana ability."),
        Rule(DeckStudioRole.RAMP, """^\{t\}: add one mana of any color(?: in your commander's color identity)?\.""", "A nonland permanent has a direct tap-for-mana ability."),
        Rule(DeckStudioRole.RAMP, """^search your library for (?:a|up to two) basic land cards?, (?:reveal (?:it|them), )?put (?:it|one of them) onto the battlefield""", "A library-search instruction puts a basic land onto the battlefield. Conditions still need review."),
        Rule(DeckStudioRole.CARD_FLOW, """^draw (?:a|two|three|four|five|six|seven|[1-9][0-9]?) cards?\.""", "A direct draw instruction is present. Cantrips and draw-then-discard effects are card flow, not necessarily net advantage."),
        Rule(DeckStudioRole.INTERACTION, """^(?:destroy|exile) target (?:creature|artifact|enchantment|permanent)(?: or (?:creature|artifact|enchantment))?\.""", "A direct targeted removal instruction is present; restrictions and other modes still matter."),
        Rule(DeckStudioRole.INTERACTION, """^counter target (?:noncreature )?spell\.""", "A direct counterspell instruction is present."),
        Rule(DeckStudioRole.BOARD_WIPE, """^(?:destroy|exile) all creatures\.""", "A direct instruction affects all creatures. Symmetry and deck context still matter."),
        Rule(DeckStudioRole.PROTECTION, """^permanents you control gain hexproof and indestructible until end of turn\.""", "A direct protective instruction grants hexproof and indestructible."),
        Rule(DeckStudioRole.GRAVEYARD_HATE, """^exile (?:all cards from all graveyards|target card from a graveyard|target player's graveyard)\.""", "A direct instruction exiles cards from a graveyard."),
        Rule(DeckStudioRole.RECURSION, """^return target (?:(?:creature|artifact|enchantment|permanent) )?card from your graveyard to (?:your hand|the battlefield)\.""", "A direct instruction returns a card from your graveyard."),
        Rule(DeckStudioRole.TUTOR, """^search your library for a card, put that card into your hand, then shuffle\.""", "A direct unrestricted library-search instruction is present."),
    )
    private val modal = Regex("""\bchoose (?:one|two|three|four|any)\b""")
    private val conditional = Regex("""\b(?:when|whenever|at the beginning|at the end|if|unless|activate only|activate (?:as|during)|only any time)\b""")
    private val newlines = Regex("[\n\r\u000B\u000C\u0085  ]")

    /**
     * Reminder text removed, then each sentence and each activated ability's effect offered as
     * its own candidate. Triggered and conditional effects are left to curated tags and review.
     */
    fun clauses(text: String): List<String> {
        var normalized = Normalizer.normalize(text, Normalizer.Form.NFC).lowercase(java.util.Locale.ROOT).replace("’", "'")
        var depth = 0
        val stripped = StringBuilder()
        for (character in normalized) {
            when {
                character == '(' -> { depth += 1; stripped.append(' ') }
                character == ')' -> { if (depth <= 0) return emptyList(); depth -= 1 }
                depth == 0 -> stripped.append(character)
            }
        }
        if (depth != 0) return emptyList()
        normalized = stripped.toString()
        if (normalized.any { it in "\"“”•" } || modal.containsMatchIn(normalized)) return emptyList()
        fun tidy(value: String): String? {
            val cleaned = value.split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
            return if (cleaned.isEmpty()) null else if (cleaned.endsWith(".")) cleaned else "$cleaned."
        }
        val pieces = ArrayList<String>()
        for (line in normalized.split(newlines)) {
            if (conditional.containsMatchIn(line)) continue
            val candidates = listOf(line) + line.split('.', ';').filter { it.isNotEmpty() }
            for (candidate in candidates) {
                val whole = tidy(candidate) ?: continue
                pieces += whole
                val colon = candidate.indexOf(':')
                if (colon >= 0) tidy(candidate.substring(colon + 1))?.let { pieces += it }
            }
        }
        val seen = HashSet<String>()
        return pieces.filter { seen.add(it) }
    }

    fun classify(text: String?, types: List<String>?, curated: List<DeckStudioRole> = emptyList(), reviewed: Set<DeckStudioRole>? = null): List<DeckStudioRoleEvidence> {
        if (reviewed != null) return DeckStudioRole.entries.filter { it in reviewed }.map {
            DeckStudioRoleEvidence(it, DeckStudioRoleEvidence.Source.REVIEWED, "You assigned this role. It overrides automatic hints for this card.")
        }
        val matches = LinkedHashMap<DeckStudioRole, DeckStudioRoleEvidence>()
        for (role in curated) if (role !in matches) matches[role] = DeckStudioRoleEvidence(role, DeckStudioRoleEvidence.Source.CURATED,
            "Tagged by Scryfall's community-curated oracle tags, bundled with this build. Correct it if you disagree.")
        fun resolved() = DeckStudioRole.entries.mapNotNull { matches[it] }
        if (text == null || text.utf8Size > 32768) return resolved()
        val pieces = clauses(text)
        if (pieces.size > 512) return resolved()
        for (rule in rules) {
            if (rule.role in matches) continue
            if (rule.role == DeckStudioRole.RAMP && (types == null || "LAND" in types)) continue
            if (pieces.any { rule.expression.containsMatchIn(it) }) {
                matches[rule.role] = DeckStudioRoleEvidence(rule.role, DeckStudioRoleEvidence.Source.TEXT_PATTERN, rule.explanation)
            }
        }
        return resolved()
    }
}

class DeckStudioRoleAnalysis(entries: List<Entry>, overrides: Map<String, Set<DeckStudioRole>>) {
    data class Entry(val name: String, val quantity: Int, val text: String?, val types: List<String>?, val curated: List<DeckStudioRole> = emptyList())
    data class Card(val name: String, val quantity: Int, val evidence: List<DeckStudioRoleEvidence>, val userReviewed: Boolean)
    class AnalysisError : Exception("Invalid role analysis entries")

    val cards: List<Card>
    val mainCount: Int
    val unclassifiedCount: Int
    val missingMetadataCount: Int

    fun count(role: DeckStudioRole): Int = cards.filter { card -> card.evidence.any { it.role == role } }.sumOf { it.quantity }

    init {
        if (entries.size > 2000) throw AnalysisError()
        var total = 0; var missing = 0
        val grouped = HashMap<String, Pair<Entry, Int>>()
        for (entry in entries) {
            if (entry.name.isEmpty() || entry.name.utf8Size > 2000 || entry.quantity !in 1..2000 || entry.quantity > 2000 - total) throw AnalysisError()
            total += entry.quantity
            if (entry.text == null || entry.types == null) missing += entry.quantity
            val prior = grouped[entry.name]
            if (prior != null) {
                if (prior.first.text != entry.text || prior.first.types != entry.types || prior.first.curated != entry.curated) throw AnalysisError()
                grouped[entry.name] = entry to prior.second + entry.quantity
            } else grouped[entry.name] = entry to entry.quantity
        }
        cards = grouped.keys.sorted().map { name ->
            val (entry, count) = grouped.getValue(name)
            Card(name, count, DeckStudioRoleClassifier.classify(entry.text, entry.types, entry.curated, overrides[name]), overrides[name] != null)
        }
        mainCount = total; missingMetadataCount = missing
        unclassifiedCount = cards.filter { it.evidence.isEmpty() }.sumOf { it.quantity }
    }
}

/** Local editor preferences, not part of the engine deck payload. */
data class DeckStudioRolePreferences(
    val overrides: Map<String, Set<DeckStudioRole>> = emptyMap(),
    val targets: Map<DeckStudioRole, Target> = emptyMap(),
) {
    data class Target(val enabled: Boolean = false, val lower: Int = 0, val upper: Int = 0) {
        val isValid: Boolean get() = lower in 0..2000 && upper in lower..2000
        fun comparison(count: Int): String? {
            if (!enabled || !isValid) return null
            return when { count < lower -> "Below your target"; count > upper -> "Above your target"; else -> "Within your target" }
        }
    }

    class Invalid : Exception("Saved analysis preferences could not be read safely. They have been preserved; no deck data was changed.")

    fun validated(): DeckStudioRolePreferences {
        if (overrides.size > 2000 || !overrides.keys.all { it.isNotEmpty() && it.utf8Size <= 2000 } || !targets.values.all { it.isValid }) throw Invalid()
        return this
    }

    fun save(key: String, defaults: StudioDefaults) {
        val checked = validated()
        val text = JsonObject(mapOf("schema" to JsonPrimitive(1),
            "overrides" to JsonObject(checked.overrides.mapValues { (_, roles) -> JsonArray(roles.sortedBy { it.ordinal }.map { JsonPrimitive(it.key) }) }),
            "targets" to JsonObject(checked.targets.entries.associate { (role, target) -> role.key to JsonObject(mapOf(
                "enabled" to JsonPrimitive(target.enabled), "lower" to JsonPrimitive(target.lower), "upper" to JsonPrimitive(target.upper))) }))).toString()
        if (text.utf8Size > 512 * 1024) throw Invalid()
        defaults.set(key, text)
    }

    companion object {
        fun load(key: String, defaults: StudioDefaults): DeckStudioRolePreferences {
            val text = defaults.string(key) ?: return DeckStudioRolePreferences()
            if (text.utf8Size > 512 * 1024) throw Invalid()
            try {
                val value = Json.parseToJsonElement(text)
                if (value["schema"].integer != 1L) throw Invalid()
                val overrides = (value["overrides"].obj ?: throw Invalid()).mapValues { (_, roles) ->
                    (roles.array ?: throw Invalid()).map { role -> role.string?.let(DeckStudioRole::of) ?: throw Invalid() }.toSet()
                }
                val targets = (value["targets"].obj ?: throw Invalid()).entries.associate { (key, target) ->
                    (DeckStudioRole.of(key) ?: throw Invalid()) to Target(target["enabled"].bool ?: throw Invalid(),
                        target["lower"].integer?.toInt() ?: throw Invalid(), target["upper"].integer?.toInt() ?: throw Invalid())
                }
                return DeckStudioRolePreferences(overrides, targets).validated()
            } catch (error: Invalid) { throw error } catch (error: Exception) { throw Invalid() }
        }
    }
}

/**
 * A receipt is evidence for one exact request and installed engine, not a flag attached
 * permanently to a mutable deck record.
 */
data class DeckStudioValidationReceipt(
    val request: String,
    val upstream: String,
    val catalogue: String,
    val appBuild: String,
    val checkedAt: Long,
    val valid: Boolean,
    val issues: List<Issue>,
    val summary: String,
) {
    data class Issue(val index: Int, val type: String, val group: String?, val message: String, val cardName: String?)
    class InvalidReceipt : Exception("XMage returned an unrecognized validation result. The draft is unchanged and has not been marked legal.")

    fun matches(request: String, upstream: String, catalogue: String, appBuild: String): Boolean =
        this.request == request && this.upstream == upstream && this.catalogue == catalogue && this.appBuild == appBuild

    companion object {
        fun success(result: J, request: String, upstream: String, catalogue: String, appBuild: String, now: Long = System.currentTimeMillis()): DeckStudioValidationReceipt {
            if (result !is JsonObject || result["valid"].bool != true || result["validator"].string != "Commander" || result["upstream"].string != upstream ||
                result["catalogueHash"].string != catalogue || result["issues"].array?.isEmpty() != true) throw InvalidReceipt()
            return DeckStudioValidationReceipt(request, upstream, catalogue, appBuild, now, true, emptyList(), "Passed the installed XMage Commander validator")
        }

        fun rejection(details: J, message: String, request: String, upstream: String, catalogue: String, appBuild: String, now: Long = System.currentTimeMillis()): DeckStudioValidationReceipt {
            val rows = details["issues"].array
            if (details !is JsonObject || details["validator"].string != "Commander" || rows == null || rows.isEmpty() || rows.size > 2000) throw InvalidReceipt()
            val issues = rows.mapIndexed { index, row ->
                val type = row["type"].string; val text = row["message"].string
                if (row !is JsonObject || type == null || text == null || type.utf8Size > 128 || text.utf8Size > 16_384) throw InvalidReceipt()
                val group = row["group"].string; val name = row["cardName"].string
                if ((group?.utf8Size ?: 0) > 2048 || (name?.utf8Size ?: 0) > 2048) throw InvalidReceipt()
                Issue(index, type, group, text, name)
            }
            return DeckStudioValidationReceipt(request, upstream, catalogue, appBuild, now, false, issues, message)
        }
    }
}
