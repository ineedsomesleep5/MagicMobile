package io.magicmobile.android

import android.content.Context
import android.util.AtomicFile
import io.magicmobile.android.core.*
import java.io.File
import java.util.UUID

data class SavedDeck(val id: String, val revision: Long, val deck: Deck)
/** Atomic local-only storage. Corrupt data stops writes rather than being overwritten. */
class DeckStore(context: Context) {
    private val root = File(context.filesDir,"decks-v1").apply { mkdirs() }
    private val recovery = AtomicFile(File(root,"draft.json"))
    @Synchronized fun all(): List<SavedDeck> = root.listFiles().orEmpty().filter { it.name.endsWith(".json") && it.name != "draft.json" }.map {
        val o=read(AtomicFile(it)); SavedDeck(Wire.string(o["id"]),Wire.integer(o["revision"]),Deck.decode(Wire.objectValue(o["deck"])))
    }.sortedBy { it.deck.name }
    @Synchronized fun save(deck: Deck, original: SavedDeck? = null): SavedDeck {
        val id=original?.id ?: UUID.randomUUID().toString(); require(Wire.uuid(id))
        val file=AtomicFile(File(root,"$id.json"))
        if(original != null) require(Wire.integer(read(file)["revision"]) == original.revision) { "Deck changed on disk. Reopen it before saving." }
        val revision=Math.addExact(original?.revision ?: 0L,1L)
        write(file,mapOf("schema" to 1,"id" to id,"revision" to revision,"deck" to deck.json()))
        return SavedDeck(id,revision,deck)
    }
    @Synchronized fun delete(record: SavedDeck) {
        require(Wire.uuid(record.id)); val file=AtomicFile(File(root,"${record.id}.json"))
        require(Wire.integer(read(file)["revision"])==record.revision); file.delete()
    }
    @Synchronized fun recover(): Deck? = if(recovery.baseFile.exists()) Deck.decode(Wire.objectValue(read(recovery)["deck"])) else null
    @Synchronized fun keepDraft(deck: Deck) { if(recovery.baseFile.exists()) read(recovery); write(recovery,mapOf("schema" to 1,"deck" to deck.json())) }
    @Synchronized fun clearDraft() { recovery.delete() }
    private fun read(file: AtomicFile): Obj = file.openRead().use { stream -> Wire.decode(readBounded(stream,Wire.LIMIT)) }.also { require(Wire.integer(it["schema"])==1L) }
    private fun write(file: AtomicFile, data: Obj) { val bytes=Wire.encode(data); val output=file.startWrite()
        try { output.write(bytes); file.finishWrite(output) } catch(e:Exception) { file.failWrite(output); throw e } }
}
