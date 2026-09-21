package io.magicmobile.android

import android.app.Application
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.ViewModelStore
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

class OnlineAvailabilityTest {
    @Test fun unconfiguredOnlineEntryDoesNotStartAuthenticationOrGame() {
        assumeTrue("This fallback build intentionally has no online service",BuildConfig.ONLINE_SERVER_URL.isBlank())
        val instrumentation=InstrumentationRegistry.getInstrumentation()
        instrumentation.runOnMainSync {
            val store=ViewModelStore()
            val factory=ViewModelProvider.AndroidViewModelFactory(instrumentation.targetContext.applicationContext as Application)
            val model=ViewModelProvider(store,factory)[AppModel::class.java]
            try {
                model.openOnline()
                val online=model.online.value
                assertFalse(online.configured)
                assertFalse(online.connected)
                assertFalse(online.busy)
                assertNull(online.userId)
                assertNull(online.lobby)
                assertFalse(model.state.value.playing)
                assertFalse(model.state.value.onlineGame)
            } finally {store.clear()}
        }
    }
}
