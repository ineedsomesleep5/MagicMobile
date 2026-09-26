package io.magicmobile.android.studio

import io.magicmobile.android.game.J
import io.magicmobile.android.game.array
import io.magicmobile.android.game.bool
import io.magicmobile.android.game.get
import io.magicmobile.android.game.integer
import io.magicmobile.android.game.string
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.io.File
import java.security.MessageDigest

/**
 * What a stored XMage check is bound to (DeckStudioReceiptStore.swift): the source deck ID, the
 * SHA-256 of the exact resolved engine request, the engine commit, the catalogue hash and the app
 * build. A change to any of them is a different key, so an old result can never show as current.
 */
data class DeckStudioCheckKey(val deckID: String, val requestSHA256: String, val upstream: String, val catalogue: String, val appBuild: String) {
    companion object {
        fun of(deckID: String, request: String, upstream: String, catalogue: String, appBuild: String) =
            DeckStudioCheckKey(deckID, sha256(request), upstream, catalogue, appBuild)

        fun sha256(text: String): String =
            MessageDigest.getInstance("SHA-256").digest(text.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
    }
}

/** A deck's status chip, taken only from a stored result whose key matches exactly. */
enum class DeckStudioPlayStatus(val title: String) {
    READY("Ready"), NEEDS_FIXES("Needs fixes"), NOT_CHECKED("Not checked")
}

/** One stored check, passed or failed. Evidence for one exact key, never a flag on a mutable deck. */
data class DeckStudioCheckResult(
    val key: DeckStudioCheckKey,
    val checkedAt: Long,
    val valid: Boolean,
    val issues: List<DeckStudioValidationReceipt.Issue>,
    /** Every issue XMage reported; only the first [maximumIssues] are kept. */
    val issueCount: Int,
    val summary: String,
) {
    /** The validation panel's receipt for [request], when that request is the one this result was stored for. */
    fun receipt(request: String): DeckStudioValidationReceipt? {
        if (DeckStudioCheckKey.sha256(request) != key.requestSHA256) return null
        return DeckStudioValidationReceipt(request, key.upstream, key.catalogue, key.appBuild, checkedAt, valid, issues, summary)
    }

    fun json(): JsonObject = JsonObject(sortedMapOf<String, JsonElement>(
        "deckID" to JsonPrimitive(key.deckID), "requestSHA256" to JsonPrimitive(key.requestSHA256), "upstream" to JsonPrimitive(key.upstream),
        "catalogue" to JsonPrimitive(key.catalogue), "appBuild" to JsonPrimitive(key.appBuild), "checkedAt" to JsonPrimitive(checkedAt),
        "valid" to JsonPrimitive(valid), "issueCount" to JsonPrimitive(issueCount), "summary" to JsonPrimitive(summary),
        "issues" to JsonArray(issues.map { issue ->
            JsonObject(sortedMapOf<String, JsonElement>("index" to JsonPrimitive(issue.index), "type" to JsonPrimitive(issue.type),
                "group" to (issue.group?.let(::JsonPrimitive) ?: JsonNull), "message" to JsonPrimitive(issue.message),
                "cardName" to (issue.cardName?.let(::JsonPrimitive) ?: JsonNull)))
        })))

    companion object {
        const val maximumIssues = 100

        fun of(deckID: String, receipt: DeckStudioValidationReceipt): DeckStudioCheckResult =
            DeckStudioCheckResult(DeckStudioCheckKey.of(deckID, receipt.request, receipt.upstream, receipt.catalogue, receipt.appBuild),
                receipt.checkedAt, receipt.valid, receipt.issues.take(maximumIssues), receipt.issues.size, receipt.summary)

        fun decode(value: J?): DeckStudioCheckResult {
            fun text(key: String, limit: Int) = value[key].string?.takeIf { it.isNotEmpty() && it.utf8Size <= limit } ?: throw IllegalStateException("invalid")
            fun optional(row: J?, key: String) = row[key]?.takeIf { it !is JsonNull }?.let { it.string?.takeIf { text -> text.utf8Size <= 2048 } ?: throw IllegalStateException("invalid") }
            val rows = value["issues"].array ?: throw IllegalStateException("invalid")
            val issues = rows.map { row ->
                DeckStudioValidationReceipt.Issue((row["index"].integer ?: throw IllegalStateException("invalid")).toInt(),
                    row["type"].string?.takeIf { it.utf8Size <= 128 } ?: throw IllegalStateException("invalid"), optional(row, "group"),
                    row["message"].string?.takeIf { it.utf8Size <= 16_384 } ?: throw IllegalStateException("invalid"), optional(row, "cardName"))
            }
            val sha = text("requestSHA256", 64)
            val count = value["issueCount"].integer ?: throw IllegalStateException("invalid")
            val valid = value["valid"].bool ?: throw IllegalStateException("invalid")
            if (!Regex("^[0-9a-f]{64}$").matches(sha) || issues.size > maximumIssues || count !in issues.size.toLong()..2000L ||
                (valid && count != 0L) || (!valid && count == 0L)) throw IllegalStateException("invalid")
            return DeckStudioCheckResult(DeckStudioCheckKey(text("deckID", 512), sha, text("upstream", 256), text("catalogue", 256), text("appBuild", 64)),
                value["checkedAt"].integer ?: throw IllegalStateException("invalid"), valid, issues, count.toInt(),
                value["summary"].string?.takeIf { it.utf8Size <= 16_384 } ?: throw IllegalStateException("invalid"))
        }
    }
}

/**
 * Stored check results on this device (DeckStudioReceiptStore.swift). Lookups match the whole key,
 * so an edit, a new engine, catalogue or app build reads as "Not checked". At most 200 results are
 * kept, newest first, and five per deck. A missing or unreadable file is only a cache miss: it
 * never reads as Ready, and the next stored result replaces it.
 */
class DeckStudioReceiptStore(private val file: File?, private val changed: () -> Unit = {}) {
    private var loaded = false
    private var results: List<DeckStudioCheckResult> = emptyList()

    @Synchronized fun result(key: DeckStudioCheckKey): DeckStudioCheckResult? { load(); return results.firstOrNull { it.key == key } }

    @Synchronized fun status(key: DeckStudioCheckKey?): DeckStudioPlayStatus {
        val result = key?.let(::result) ?: return DeckStudioPlayStatus.NOT_CHECKED
        return if (result.valid) DeckStudioPlayStatus.READY else DeckStudioPlayStatus.NEEDS_FIXES
    }

    @Synchronized fun all(): List<DeckStudioCheckResult> { load(); return results }

    /** Keeps [value] as the newest result for its key. Returns false when the file could not be written. */
    @Synchronized fun record(value: DeckStudioCheckResult): Boolean {
        load()
        val sameDeck = results.filter { it.key.deckID == value.key.deckID && it.key != value.key }.take(maximumPerDeck - 1)
        var next = (results.filter { it.key.deckID != value.key.deckID } + sameDeck + value).sortedByDescending { it.checkedAt }.take(maximumResults)
        while (encoded(next).size > maximumBytes && next.size > 1) next = next.dropLast(1)
        results = next
        changed()
        return write(next)
    }

    /** Forgets a deleted deck's results. */
    @Synchronized fun remove(deckID: String) {
        load()
        if (results.none { it.key.deckID == deckID }) return
        results = results.filter { it.key.deckID != deckID }
        changed()
        write(results)
    }

    private fun load() {
        if (loaded) return
        loaded = true
        val file = file ?: return
        results = runCatching {
            if (!file.exists()) return@runCatching emptyList()
            if (file.length() > maximumBytes) throw IllegalStateException("invalid")
            val payload = Json.parseToJsonElement(file.readText())
            val rows = payload["results"].array ?: throw IllegalStateException("invalid")
            if (payload["schema"].integer != 1L || rows.size > maximumResults) throw IllegalStateException("invalid")
            val decoded = rows.map(DeckStudioCheckResult::decode)
            if (decoded.map { it.key }.toSet().size != decoded.size) throw IllegalStateException("invalid")
            decoded
        }.getOrDefault(emptyList())
    }

    private fun encoded(values: List<DeckStudioCheckResult>): ByteArray =
        JsonObject(mapOf("schema" to JsonPrimitive(1), "results" to JsonArray(values.map { it.json() }))).toString().toByteArray(Charsets.UTF_8)

    private fun write(values: List<DeckStudioCheckResult>): Boolean = runCatching {
        val file = file ?: return false
        file.parentFile?.mkdirs()
        val temporary = File(file.parentFile, file.name + ".tmp")
        temporary.writeBytes(encoded(values))
        if (!temporary.renameTo(file)) { temporary.delete(); return false }
        true
    }.getOrDefault(false)

    companion object {
        const val maximumResults = 200
        const val maximumPerDeck = 5
        const val maximumBytes = 2 * 1024 * 1024
    }
}
