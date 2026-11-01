package io.magicmobile.android.game

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull

/**
 * What the server can change without a build (iOS AppConfig, mm_app_config; docs/SERVER_CONTROLS.md): a news banner for the
 * main menu, card-name fixes for deck imports, switches for newer features, and a newer AI deck file. The phone keeps the
 * last copy ([AppConfigState], saved by the app), so it applies offline too.
 */
data class AppConfig(val notice: Notice? = null, val nameFixes: Map<String, String> = emptyMap(), val switches: Map<String, Boolean> = emptyMap(),
                     /** By card catalogue hash: a file only suits the catalogue it was built for. */
                     val deckFiles: Map<String, DeckFile> = emptyMap()) {
    data class Notice(val id: String, val text: String)
    /** An ai-decks.json the server offers ([AIDeckUpdates]). */
    data class DeckFile(val revision: Int, val url: String, val sha256: String)

    /** A switch the server hasn't named is on, unless the feature says otherwise (voiceChat). */
    fun isOn(name: String, default: Boolean = true): Boolean = switches[name] ?: default

    companion object {
        const val MAX_NAME_FIXES = 500

        /** mm_app_config's reply; null when it isn't one. */
        fun parse(text: String): AppConfig? = runCatching {
            val root = Json.parseToJsonElement(text) as? JsonObject ?: return null
            val notice = (root["notice"] as? JsonObject)?.let { n ->
                val id = (n["id"] as? JsonPrimitive)?.takeIf { it.isString }?.content
                val body = (n["text"] as? JsonPrimitive)?.takeIf { it.isString }?.content
                if (id.isNullOrEmpty() || body.isNullOrEmpty()) null else Notice(id.take(80), body.take(280))
            }
            val fixes = (root["nameFixes"] as? JsonObject).orEmpty().entries.take(MAX_NAME_FIXES).mapNotNull { (from, to) ->
                val target = (to as? JsonPrimitive)?.takeIf { it.isString }?.content
                if (from.isEmpty() || target.isNullOrEmpty() || from.length > 200 || target.length > 200) null else from to target
            }.toMap()
            val switches = (root["switches"] as? JsonObject).orEmpty().mapNotNull { (name, value) ->
                (value as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull?.let { name to it }
            }.toMap()
            val files = (root["aiDecks"] as? JsonObject).orEmpty().mapNotNull { (catalogue, value) ->
                val file = value as? JsonObject ?: return@mapNotNull null
                val revision = (file["revision"] as? JsonPrimitive)?.takeIf { !it.isString }?.intOrNull
                val url = (file["url"] as? JsonPrimitive)?.takeIf { it.isString }?.content
                val sha256 = (file["sha256"] as? JsonPrimitive)?.takeIf { it.isString }?.content
                if (revision == null || revision <= 0 || url?.startsWith("https://") != true || sha256?.length != 64) null
                else catalogue to DeckFile(revision, url, sha256)
            }.toMap()
            AppConfig(notice, fixes, switches, files)
        }.getOrNull()
    }
}

/** The app's current copy, readable from any thread; the app loads and saves it (AppConfigStore). */
object AppConfigState {
    @Volatile var current: AppConfig = AppConfig()
}
