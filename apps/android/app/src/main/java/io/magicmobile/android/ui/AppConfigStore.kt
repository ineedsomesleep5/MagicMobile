package io.magicmobile.android.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import io.magicmobile.android.game.AppConfig
import io.magicmobile.android.game.AppConfigState

/**
 * The phone's copy of the server's settings (iOS AppConfigStore; mm_app_config): kept in the app's preferences so it applies
 * offline, published to [AppConfigState] for the rules that read it, and the menu's notice as Compose state.
 */
object AppConfigStore {
    private const val KEY = "magicmobile.appConfig"
    /** The notice the player closed, by id: it doesn't come back. */
    private const val DISMISSED_KEY = "magicmobile.appConfig.dismissedNotice"

    /** The notice to show on the main menu, unless the player closed it. */
    var shownNotice by mutableStateOf<AppConfig.Notice?>(null); private set

    /** Once AppPreferences is ready: the last copy. */
    fun load() {
        AppConfigState.current = AppConfig.parse(AppPreferences.raw()?.getString(KEY, null) ?: "") ?: AppConfig()
        refreshNotice()
    }

    /** Keeps a reply from the server; anything else is ignored and the last copy stays. */
    fun store(text: String) {
        val parsed = AppConfig.parse(text) ?: return
        AppConfigState.current = parsed
        AppPreferences.raw()?.edit()?.putString(KEY, text)?.apply()
        refreshNotice()
    }

    fun dismissNotice(notice: AppConfig.Notice) {
        AppPreferences.raw()?.edit()?.putString(DISMISSED_KEY, notice.id)?.apply()
        refreshNotice()
    }

    private fun refreshNotice() {
        val notice = AppConfigState.current.notice
        shownNotice = notice?.takeIf { AppPreferences.raw()?.getString(DISMISSED_KEY, null) != it.id }
    }
}
