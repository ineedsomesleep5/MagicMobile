package io.magicmobile.android

import android.content.Context
import android.util.AtomicFile
import io.magicmobile.android.core.*
import java.io.File

data class ImportReceipt(val source: String, val originalText: String, val annotations: List<String>, val importedDeck: Deck) {
    fun json(): Obj = mapOf("schema" to 1,"source" to source,"originalText" to originalText,"annotations" to annotations,"importedDeck" to importedDeck.json())
}
/** Local source evidence stays separate from the editable deck and never enters native requests. */
class ReceiptStore(context: Context) {
    private val root=File(context.noBackupFilesDir,"deck-import-receipts-v1").apply{mkdirs()}
    private fun file(id:String):AtomicFile{require(Wire.uuid(id));return AtomicFile(File(root,"$id.json"))}
    fun read(id:String):ImportReceipt? {
        val file=file(id);if(!file.baseFile.exists()&&!File(file.baseFile.path+".bak").exists())return null
        val value=file.openRead().use{Wire.objectValue(io.magicmobile.core.Json.parseObject(readBounded(it,8*1024*1024).toString(Charsets.UTF_8)))}
        require(Wire.integer(value["schema"])==1L)
        return ImportReceipt(Wire.string(value["source"]),Wire.string(value["originalText"]),value.array("annotations").map(Wire::string),Deck.decode(Wire.objectValue(value["importedDeck"])))
    }
    fun write(id:String,receipt:ImportReceipt) {
        read(id)
        require(receipt.originalText.toByteArray().size<=2*1024*1024&&receipt.source.length<=2048&&receipt.annotations.size<=10000)
        val bytes=io.magicmobile.core.Json.write(receipt.json()).toByteArray();require(bytes.size<=8*1024*1024)
        val file=file(id);val output=file.startWrite();try{output.write(bytes);file.finishWrite(output)}catch(error:Exception){file.failWrite(output);throw error}
    }
    fun copy(from:String,to:String){read(from)?.let{write(to,it)}}
    fun delete(id:String){file(id).delete()}
}
