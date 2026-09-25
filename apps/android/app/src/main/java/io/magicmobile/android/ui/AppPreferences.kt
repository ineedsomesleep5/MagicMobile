package io.magicmobile.android.ui

import android.content.Context
import android.content.SharedPreferences
import android.provider.Settings
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf

/**
 * iOS keeps these in UserDefaults through @AppStorage; Android keeps the same keys in
 * SharedPreferences. Each value is Compose state, so views update when a setting changes.
 */
object AppPreferences {
    private var prefs: SharedPreferences? = null
    private val strings = HashMap<String, MutableState<String>>()
    private val booleans = HashMap<String, MutableState<Boolean>>()
    private val ints = HashMap<String, MutableState<Int>>()
    private val doubles = HashMap<String, MutableState<Double>>()

    /** `name` isolates UI-test preferences the way MAGICMOBILE_UI_TEST_PREFERENCES does on iOS. */
    fun init(context: Context, name: String = "magicmobile.preferences") {
        prefs = context.applicationContext.getSharedPreferences(name, Context.MODE_PRIVATE)
        strings.clear(); booleans.clear(); ints.clear(); doubles.clear()
    }

    fun string(key: String, default: String): MutableState<String> = strings.getOrPut(key) {
        persisted(mutableStateOf(prefs?.getString(key, default) ?: default)) { prefs?.edit()?.putString(key, it)?.apply() }
    }
    fun boolean(key: String, default: Boolean): MutableState<Boolean> = booleans.getOrPut(key) {
        persisted(mutableStateOf(prefs?.getBoolean(key, default) ?: default)) { prefs?.edit()?.putBoolean(key, it)?.apply() }
    }
    fun int(key: String, default: Int): MutableState<Int> = ints.getOrPut(key) {
        persisted(mutableStateOf(prefs?.getInt(key, default) ?: default)) { prefs?.edit()?.putInt(key, it)?.apply() }
    }
    fun double(key: String, default: Double): MutableState<Double> = doubles.getOrPut(key) {
        persisted(mutableStateOf(prefs?.getString(key, null)?.toDoubleOrNull() ?: default)) { prefs?.edit()?.putString(key, it.toString())?.apply() }
    }
    fun contains(key: String): Boolean = prefs?.contains(key) == true
    fun remove(key: String) { prefs?.edit()?.remove(key)?.apply(); strings.remove(key); booleans.remove(key); ints.remove(key); doubles.remove(key) }

    private fun <T> persisted(state: MutableState<T>, save: (T) -> Unit): MutableState<T> = object : MutableState<T> by state {
        override var value: T
            get() = state.value
            set(newValue) { state.value = newValue; save(newValue) }
    }
}

/** Launch-time switches: DEBUG previews and the system's reduced-motion setting. */
object LaunchEnvironment {
    /** Mirrors the iOS launch environment (MAGICMOBILE_DESIGN_PREVIEW and friends); set from debug intent extras only. */
    var values: Map<String, String> = emptyMap()
    var reduceMotion = false
    var systemFontScale = 1f

    fun load(context: Context, extras: Map<String, String>) {
        values = extras
        reduceMotion = runCatching { Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f }.getOrDefault(false)
        systemFontScale = context.resources.configuration.fontScale
    }

    operator fun get(key: String): String? = values[key]
}
