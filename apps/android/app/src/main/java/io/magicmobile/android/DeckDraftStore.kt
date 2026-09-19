package io.magicmobile.android

import android.content.Context
import android.util.AtomicFile
import io.magicmobile.android.core.*
import java.io.File

data class DeckDraft(val id: String, val baseRevision: Long?, val deck: Deck, val savedID: String? = null)

/** Drafts never replace the saved deck. A changed base revision requires opening a copy. */
class DeckDraftStore(context: Context) {
    private val root = File(context.noBackupFilesDir, "deck-drafts-v1").apply { mkdirs() }
    private fun file(id: String): AtomicFile { require(Wire.uuid(id));return AtomicFile(File(root,"$id.json")) }
    fun read(id: String): DeckDraft? {
        val file=file(id);if(!file.baseFile.exists()&&!File(file.baseFile.path+".bak").exists())return null
        val data=file.openRead().use {Wire.decode(readBounded(it,Wire.LIMIT))}
        require(Wire.integer(data["schema"])==1L && data.text("id")==id)
        val revision=data["baseRevision"]?.let(Wire::integer)?.also {require(it in 1..1_000_000_000)}
        val savedID=data.text("savedID")?.also{require(Wire.uuid(it))}
        return DeckDraft(id,revision,Deck.decode(Wire.objectValue(data["deck"])),savedID)
    }
    fun all(): List<DeckDraft> = root.listFiles().orEmpty().filter {it.extension=="json"}.mapNotNull {read(it.nameWithoutExtension)}
    fun write(id: String, baseRevision: Long?, deck: Deck, savedID:String?=null) {
        read(id) // Preserve unreadable drafts instead of overwriting them.
        require(savedID==null||Wire.uuid(savedID))
        val data=Wire.encode(mapOf("schema" to 1,"id" to id,"baseRevision" to baseRevision,"deck" to deck.json(),"savedID" to savedID))
        val file=file(id);val output=file.startWrite()
        try {output.write(data);file.finishWrite(output)}catch(error:Exception){file.failWrite(output);throw error}
    }
    fun delete(id: String) {file(id).delete()}
}
