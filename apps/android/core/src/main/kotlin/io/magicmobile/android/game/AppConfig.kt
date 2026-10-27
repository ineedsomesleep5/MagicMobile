package io.magicmobile.android.game

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull

/**
 * What the server can change without a build (iOS AppConfig, mm_app_config; docs/SERVER_CONTROLS.md): a news banner for the
 * main menu, card-name fixes for deck imports, and switches for newer features. The phone keeps the last copy
 * ([AppConfigState], saved by the app), so it applies offline too.
 */
data class AppConfig(val notice: Notice? = null, val nameFixes: Map<String, String> = emptyMap(), val switches: Map<String, Boolean> = emptyMap()) {
    data class Notice(val id: String, val text: String)

    /** A switch the server hasn't named is on. */
    fun isOn(name: String): Boolean = switches[name] ?: true

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
            AppConfig(notice, fixes, switches)
        }.getOrNull()
    }
}

/** The app's current copy, readable from any thread; the app loads and saves it (AppConfigStore). */
object AppConfigState {
    @Volatile var current: AppConfig = AppConfig()
}
