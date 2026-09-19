package io.magicmobile.android

import android.content.Context
import android.util.AtomicFile
import io.magicmobile.android.core.*
import java.io.File
import java.util.UUID

data class SavedDeck(
    val id: String,
    val revision: Long,
    val deck: Deck,
    val favorite: Boolean = false,
    val tags: List<String> = emptyList(),
    val notes: String = "",
    val modifiedAtMillis: Long = 0,
)
/** Atomic local-only storage. Corrupt data stops writes rather than being overwritten. */
class DeckStore(context: Context) {
    private val root = File(context.filesDir,"decks-v1").apply { mkdirs() }
    private val recovery = AtomicFile(File(root,"draft.json"))
    @Synchronized fun all(): List<SavedDeck> = root.listFiles().orEmpty().filter { it.name.endsWith(".json") && it.name != "draft.json" }.map {
        decodeSaved(read(AtomicFile(it)),it.name.removeSuffix(".json")).copy(modifiedAtMillis=it.lastModified())
    }.sortedWith(compareByDescending<SavedDeck> { it.favorite }.thenBy { it.deck.name.lowercase() })
    @Synchronized fun save(deck: Deck, original: SavedDeck? = null): SavedDeck {
        val id=original?.id ?: UUID.randomUUID().toString(); require(Wire.uuid(id))
        val file=AtomicFile(File(root,"$id.json"))
        if(original != null) {
            val current=decodeSaved(read(file),id)
            require(current.revision == original.revision) { "Deck changed on disk. Reopen it before saving." }
            require(current.revision<1_000_000_000) { "Deck revision limit reached; copy the deck before editing again." }
        }
        val revision=Math.addExact(original?.revision ?: 0L,1L)
        val result=SavedDeck(id,revision,deck,original?.favorite ?: false,original?.tags.orEmpty(),original?.notes.orEmpty())
        write(file,result.json())
        return result.copy(modifiedAtMillis=file.baseFile.lastModified())
    }
    @Synchronized fun organize(record: SavedDeck, favorite: Boolean, tags: List<String>, notes: String): SavedDeck {
        require(Wire.uuid(record.id))
        val organization=DeckOrganization.create(tags,notes)
        val file=AtomicFile(File(root,"${record.id}.json"));val current=decodeSaved(read(file),record.id)
        require(current.revision==record.revision) { "Deck changed on disk. Reopen it before saving details." }
        require(current.revision<1_000_000_000) { "Deck revision limit reached; copy the deck before editing details again." }
        val result=current.copy(revision=Math.addExact(current.revision,1L),favorite=favorite,tags=organization.tags,notes=organization.notes)
        write(file,result.json());return result.copy(modifiedAtMillis=file.baseFile.lastModified())
    }
    @Synchronized fun duplicate(record: SavedDeck): SavedDeck {
        require(Wire.uuid(record.id));val current=decodeSaved(read(AtomicFile(File(root,"${record.id}.json"))),record.id)
        require(current.revision==record.revision) { "Deck changed on disk. Reopen it before copying." }
        val result=SavedDeck(UUID.randomUUID().toString(),1,current.deck.copy(name="${current.deck.name} copy"),false,current.tags,current.notes)
        val file=AtomicFile(File(root,"${result.id}.json"));write(file,result.json());return result.copy(modifiedAtMillis=file.baseFile.lastModified())
    }
    @Synchronized fun delete(record: SavedDeck) {
        require(Wire.uuid(record.id)); val file=AtomicFile(File(root,"${record.id}.json"))
        require(decodeSaved(read(file),record.id).revision==record.revision); file.delete()
    }
    @Synchronized fun recover(): Deck? = if(recovery.baseFile.exists()) read(recovery).let { require(Wire.integer(it["schema"])==1L);Deck.decode(Wire.objectValue(it["deck"])) } else null
    @Synchronized fun keepDraft(deck: Deck) { if(recovery.baseFile.exists()) read(recovery); write(recovery,mapOf("schema" to 1,"deck" to deck.json())) }
    @Synchronized fun clearDraft() { recovery.delete() }
    private fun decodeSaved(value: Obj,expectedID:String): SavedDeck {
        val schema=Wire.integer(value["schema"]);require(schema in 1..2)
        val id=Wire.string(value["id"]);require(Wire.uuid(id)&&id==expectedID)
        val revision=Wire.integer(value["revision"]);require(revision in 1..1_000_000_000)
        if(schema==2L)require(value["tags"] is List<*> && value["notes"] is String && value["favorite"] is Boolean)
        val tags=if(schema==2L)value.array("tags").map(Wire::string) else emptyList()
        val notes=if(schema==2L)Wire.string(value["notes"]) else "";val organization=DeckOrganization.create(tags,notes)
        require(organization.tags==tags && organization.notes==notes)
        val favorite=if(schema==2L)value["favorite"] as Boolean else false
        return SavedDeck(id,revision,Deck.decode(Wire.objectValue(value["deck"])),favorite,organization.tags,organization.notes)
    }
    private fun SavedDeck.json(): Obj = mapOf("schema" to 2,"id" to id,"revision" to revision,"deck" to deck.json(),"favorite" to favorite,"tags" to tags,"notes" to notes)
    private fun read(file: AtomicFile): Obj = file.openRead().use { stream -> Wire.decode(readBounded(stream,Wire.LIMIT)) }
    private fun write(file: AtomicFile, data: Obj) { val bytes=Wire.encode(data); val output=file.startWrite()
        try { output.write(bytes); file.finishWrite(output) } catch(e:Exception) { file.failWrite(output); throw e } }
}
