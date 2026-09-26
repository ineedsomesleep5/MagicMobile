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
        io.magicmobile.android.ui.GameAudio.init(this)
        // Menus and the board are always dark, like the iOS app.
        WindowCompat.getInsetsController(window,window.decorView).apply{isAppearanceLightStatusBars=false;isAppearanceLightNavigationBars=false}
        io.magicmobile.android.studio.DeckStudioServices.install(this)
        if(DesignPreview.active) setContent { DesignPreviewHost() }
        else setContent { io.magicmobile.android.ondevice.OnDeviceRoot(onDevice) }
    }
}
