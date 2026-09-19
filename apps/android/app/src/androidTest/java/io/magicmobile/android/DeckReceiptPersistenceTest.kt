package io.magicmobile.android

import android.content.ContextWrapper
import androidx.test.platform.app.InstrumentationRegistry
import io.magicmobile.android.core.CardEntry
import io.magicmobile.android.core.Deck
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.UUID

class DeckReceiptPersistenceTest {
    private fun isolated(): ContextWrapper {
        val target=InstrumentationRegistry.getInstrumentation().targetContext
        val directory=File(target.cacheDir,"receipt-test-${UUID.randomUUID()}").apply{mkdirs()}
        return object:ContextWrapper(target) {
            override fun getFilesDir()=File(directory,"files").apply{mkdirs()}
            override fun getNoBackupFilesDir()=File(directory,"private").apply{mkdirs()}
        }
    }
    private val deck=Deck("Imported source",listOf(CardEntry("Island",99),CardEntry("Leader",1,"commanders")))

    @Test fun receiptMigrationPreservesSourceAfterOriginalIsRemoved() {
        val context=isolated();val original=UUID.randomUUID().toString();val saved=UUID.randomUUID().toString()
        val receipt=ImportReceipt("Text import","99 Island (SET) 1",listOf("Line 1: (SET) 1"),deck)
        val store=ReceiptStore(context)
        store.write(original,receipt);store.copy(original,saved);store.delete(original)
        assertNull(ReceiptStore(context).read(original))
        assertEquals(receipt,ReceiptStore(context).read(saved))
        // Updating the editable deck cannot rewrite the imported source snapshot.
        val changed=deck.change(0,-1)
        assertNotEquals(changed,ReceiptStore(context).read(saved)?.importedDeck)
        store.delete(saved)
        assertNull(store.read(saved))
    }

    @Test fun corruptedSourceCannotBeSilentlyOverwrittenOrCopied() {
        val context=isolated();val id=UUID.randomUUID().toString();val destination=UUID.randomUUID().toString()
        val store=ReceiptStore(context);val receipt=ImportReceipt("Text","",emptyList(),deck)
        store.write(id,receipt)
        val file=File(context.noBackupFilesDir,"deck-import-receipts-v1/$id.json")
        val corrupt="{broken".toByteArray();file.writeBytes(corrupt)
        assertTrue(runCatching{store.write(id,receipt)}.isFailure)
        assertTrue(runCatching{store.copy(id,destination)}.isFailure)
        assertArrayEquals(corrupt,file.readBytes())
        assertNull(store.read(destination))
        store.delete(id)
    }

    @Test fun interruptedReceiptSaveKeepsTheSameSavedIdentityAcrossReopen() {
        val context=isolated();val drafts=DeckDraftStore(context);val store=DeckStore(context)
        val draftID=UUID.randomUUID().toString();val saved=store.save(deck)
        drafts.write(draftID,saved.revision,deck,saved.id)
        val reopened=DeckDraftStore(context).read(draftID)!!
        assertEquals(saved.id,reopened.savedID)
        val target=DeckStore(context).all().single{it.id==reopened.savedID&&it.revision==reopened.baseRevision}
        val updated=store.save(deck.change(0,-1),target)
        assertEquals(saved.id,updated.id)
        assertEquals(1,store.all().size)
        assertEquals(saved.revision+1,updated.revision)
        // A stale base remains detectable instead of silently overwriting the new revision.
        assertNotEquals(reopened.baseRevision,updated.revision)
        assertTrue(runCatching{store.save(deck,target)}.isFailure)
        drafts.delete(draftID);store.delete(updated)
    }
}
