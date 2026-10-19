package io.magicmobile.android

import androidx.test.platform.app.InstrumentationRegistry
import io.magicmobile.android.core.*
import org.junit.Assert.*
import org.junit.Test
import java.util.UUID

class DeviceFeatureTest {
    @Test fun savedDeckSurvivesReopeningAndRejectsAStaleSave() {
        // Isolated cache folder under the instrumentation process's own UID.
        val target=InstrumentationRegistry.getInstrumentation().targetContext
        val directory=java.io.File(target.cacheDir,"acceptance-${UUID.randomUUID()}").apply {mkdirs()}
        val context=object:android.content.ContextWrapper(target) {
            override fun getFilesDir()=java.io.File(directory,"files").apply {mkdirs()}
            override fun getNoBackupFilesDir()=java.io.File(directory,"no-backup").apply {mkdirs()}
        }
        val store=DeckStore(context)
        val deck=Deck("Acceptance ${UUID.randomUUID()}",listOf(CardEntry("Emmara, Soul of the Accord",1,"commanders"),CardEntry("Forest",99)))
        var saved=store.save(deck)
        try {
            saved=store.organize(saved,true,listOf("Acceptance"),"Private note")
            val reopened=DeckStore(context).all().single {it.id==saved.id}
            assertEquals(saved,reopened)
            val changed=deck.change(1,-1)
            // Saving over the reopened copy keeps its identity; that stale copy cannot overwrite the update.
            saved=store.save(changed,reopened)
            assertEquals(reopened.id,saved.id)
            assertEquals(reopened.revision+1,saved.revision)
            assertEquals(changed,DeckStore(context).all().single().deck)
            assertTrue(runCatching{store.save(deck,reopened)}.isFailure)
            assertEquals(changed,Deck.parse(changed.name,changed.export()))
        } finally {store.delete(saved)}
    }
}
