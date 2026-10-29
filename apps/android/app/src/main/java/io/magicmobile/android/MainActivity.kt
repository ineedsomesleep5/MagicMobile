package io.magicmobile.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.enableEdgeToEdge
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.core.view.WindowCompat

class MainActivity: ComponentActivity() {
    private val onDevice: io.magicmobile.android.ondevice.OnDeviceViewModel by viewModels()
    override fun onCreate(savedInstanceState:Bundle?) {
        super.onCreate(savedInstanceState);enableEdgeToEdge()
        val extras=DesignPreview.extras(intent)
        io.magicmobile.android.ui.LaunchEnvironment.load(this,extras)
        // UI previews and tests use their own preferences, like iOS's MAGICMOBILE_UI_TEST_PREFERENCES suite.
        io.magicmobile.android.ui.AppPreferences.init(this,extras["MAGICMOBILE_UI_TEST_PREFERENCES"]?.let{"magicmobile.preferences.$it"} ?: "magicmobile.preferences")
        // Walnut Tavern is the only table (Caleb, 2026-10-11): a board saved from the retired picker goes back to it.
        io.magicmobile.android.ui.AppPreferences.remove(io.magicmobile.android.board.BoardAppearancePreference.key)
        // The server's settings from the last launch (AppConfig) until this launch fetches them.
        io.magicmobile.android.ui.AppConfigStore.load()
        io.magicmobile.android.ui.GameAudio.init(this)
        io.magicmobile.android.ui.DeviceHeat.init(this)
        io.magicmobile.android.ui.GamePerformanceRecorder.init(this)
        // Local crash and ANR summaries for the report sheet (background thread); nothing is uploaded.
        if (savedInstanceState==null) io.magicmobile.android.ondevice.OnDeviceSystemReports.recordAtStartup(this)
        // The freeze log's watchdog and the earlier run's unsent freeze (docs/FREEZE_LOG.md); nothing is sent without Send.
        io.magicmobile.android.ondevice.FreezeLog.start(this)
        // Menus and the board are always dark, like the iOS app.
        WindowCompat.getInsetsController(window,window.decorView).apply{isAppearanceLightStatusBars=false;isAppearanceLightNavigationBars=false}
        io.magicmobile.android.studio.DeckStudioServices.install(this)
        if(DesignPreview.active) setContent { DesignPreviewHost() }
        else setContent {
            androidx.compose.foundation.layout.Box {
                io.magicmobile.android.ondevice.OnDeviceRoot(onDevice)
                io.magicmobile.android.menus.NameGate(onDevice.account)
            }
        }
        if (savedInstanceState==null) openJoinLink(intent)
    }

    /** Every touch keeps the board's breathing glows awake (BoardActivity); the touch itself goes on unchanged. */
    override fun dispatchTouchEvent(event: android.view.MotionEvent): Boolean {
        if (event.actionMasked == android.view.MotionEvent.ACTION_DOWN) io.magicmobile.android.board.BoardActivity.note()
        return super.dispatchTouchEvent(event)
    }

    override fun onStart() { super.onStart(); io.magicmobile.android.ondevice.FreezeLog.setForeground(true) }
    override fun onStop() { super.onStop(); io.magicmobile.android.ondevice.FreezeLog.setForeground(false) }

    override fun onLowMemory() { super.onLowMemory(); io.magicmobile.android.ondevice.FreezeLog.crumb("Low memory") }

    /** Memory pressure while running: free the decoded artwork (it reloads from disk), not the sounds or music. */
    @Suppress("DEPRECATION")
    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        io.magicmobile.android.ondevice.FreezeLog.crumb("Memory trim (level $level)")
        if (level >= android.content.ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW && level < android.content.ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN) {
            io.magicmobile.android.ui.GamePerformanceRecorder.noteMemoryWarning()
            io.magicmobile.android.Artwork.releaseMemory()
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        openJoinLink(intent)
    }

    /** A table invite link (TableJoinLink) opens that table's join flow. */
    private fun openJoinLink(intent: android.content.Intent?) {
        val link = intent?.takeIf { it.action == android.content.Intent.ACTION_VIEW }?.dataString ?: return
        io.magicmobile.android.game.TableJoinLink.code(link)?.let { onDevice.joinLinkCode = it }
    }
}
