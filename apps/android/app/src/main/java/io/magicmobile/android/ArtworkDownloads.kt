package io.magicmobile.android

import android.content.Context
import io.magicmobile.android.core.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.URL
import kotlin.coroutines.coroutineContext

internal data class DownloadProgress(val completed: Int, val total: Int, val status: String)
internal data class DownloadScan(val cards:Int,val bytes:Long,val extraStored:Int,val extraTotal:Int,val coverageKnown:Boolean,
    val faceStored:Int=0,val faceTotal:Int=0,val tokenStored:Int=0,val tokenTotal:Int=0,val tokensKnown:Boolean=false,
    val missingCards:List<String> = emptyList(),val missingTokens:List<String> = emptyList())

/** Collection responses are a bounded list; Scryfall normally omits pagination metadata. */
internal fun validatedArtworkCollection(response:Obj,requested:Int):List<Obj> {
    val data=response["data"] as? List<*>
    check(requested in 1..75 && response.text("object")=="list" &&
        ("has_more" !in response || response["has_more"]==false) &&
        data!=null && data.size<=requested){"Unexpected artwork collection response."}
    return data.map(Wire::objectValue)
}

/** Bounded transfers; completed images and safe token identities survive retries. */
internal class ArtworkDownloadClient(private val context: Context) {
    private fun coverageFile(names:List<String>):java.io.File {
        val key=java.security.MessageDigest.getInstance("SHA-256").digest(names.joinToString("\n").toByteArray()).joinToString(""){"%02x".format(it)}
        return java.io.File(java.io.File(context.filesDir,"artwork-coverage").apply{mkdirs()},"$key.json")
    }
    suspend fun scan(names: List<String>, quality: ArtworkQuality,includeTokens:Boolean): DownloadScan = withContext(Dispatchers.IO) {
        val manifest=runCatching{val file=coverageFile(names);check(file.length() in 1..4*1024*1024);Wire.decode(file.readBytes())}.getOrNull()
        val faces=manifest?.array("faces").orEmpty().filterIsInstance<String>()
        val tokens=if(includeTokens)manifest?.array("tokens").orEmpty().filterIsInstance<String>()else emptyList()
        val unavailable=if(includeTokens)manifest?.number("unavailable")?.toInt() ?: 0 else 0
        // One directory listing answers every name, so a full-catalogue check stays quick.
        val files=Artwork.downloadedFileNames(context)
        fun stored(name:String)=Artwork.listedDownload(files,name,quality)
        val missingCards=names.filterNot(::stored)
        val missingFaces=faces.filterNot(::stored)
        val missingTokens=tokens.filterNot(::stored)
        DownloadScan(names.size-missingCards.size,Artwork.storedDownloadBytes(context),
            faces.size-missingFaces.size+tokens.size-missingTokens.size,faces.size+tokens.size+unavailable,
            manifest?.number("known")==names.size.toLong()&&(!includeTokens||manifest?.flag("includesTokens")==true),
            faces.size-missingFaces.size,faces.size,tokens.size-missingTokens.size,tokens.size+unavailable,
            manifest?.flag("includesTokens")==true,missingCards+missingFaces,missingTokens.map{it.removePrefix("token:")})
    }
    private fun saveCoverage(names:List<String>,faces:Set<String>,tokens:Set<String>,known:Int,includeTokens:Boolean,unavailable:Int) {
        val file=android.util.AtomicFile(coverageFile(names));val bytes=Wire.encode(mapOf("faces" to faces.toList(),"tokens" to tokens.toList(),"known" to known,"includesTokens" to includeTokens,"unavailable" to unavailable))
        val output=file.startWrite();try{output.write(bytes);file.finishWrite(output)}catch(failure:Throwable){file.failWrite(output);throw failure}
    }
    suspend fun download(names: List<String>, quality: ArtworkQuality, includeTokens: Boolean,
        fullCatalogue:Boolean, progress: suspend (DownloadProgress) -> Unit): List<String> = withContext(Dispatchers.IO) {
        val failures=mutableListOf<String>()
        var omittedFailures=0
        fun fail(name:String,failure:Throwable) = synchronized(failures) {
            if(failure is CancellationException)throw failure
            if(failure.message.orEmpty().let{it.contains("requests are paused")||it.contains("free device space")||it.contains("storage reached")})throw failure
            if(failures.size<100)failures+="$name: ${failure.message ?: "unavailable"}" else omittedFailures++
        }
        suspend fun checkActive(){coroutineContext.ensureActive();check(Artwork.enabled(context)){"Online artwork is disabled."}}
        suspend fun image(record:ArtworkRecord,key:String) {
            checkActive()
            if(Artwork.hasDownload(context,key,quality))return
            val url=record.images[quality.imageVersion]?.let(::URL) ?: error("No artwork at this quality.")
            val data=ArtworkTransport.bytes(context,url,2*1024*1024,setOf("image/jpeg","image/png"))
            checkActive()
            check(Artwork.saveDownload(context,key,quality,data)){"Artwork did not meet ${quality.label.lowercase()} quality."}
        }
        val catalogue=if(fullCatalogue){progress(DownloadProgress(0,names.size,"Preparing bulk artwork catalogue…"));bulk()}else {
            progress(DownloadProgress(0,names.size,"Checking deck artwork…"))
            collection(names.map{mapOf("name" to it)},includeTokens)
        }
        val wantedTokens=linkedMapOf<String,ArtworkRecord?>()
        val nameSet=names.toSet()
        val faces=linkedSetOf<String>()
        var known=0
        val unavailableTokens=catalogue.unavailableTokens.size
        if(includeTokens) {
            catalogue.tokens.forEach{(id,record)->wantedTokens[id]=record}
            catalogue.unavailableTokens.forEach{fail("Token $it",IllegalStateException("Safe artwork metadata is unavailable."))}
        }
        names.forEach{name->catalogue.card(name)?.let{card->known++;card.faces.filter{it.images.isNotEmpty()&&it.name !in nameSet}.forEach{faces+=it.name}}}
        fun persistCoverage()=saveCoverage(names,faces,wantedTokens.keys.map{"token:$it"}.toSet(),known,includeTokens,unavailableTokens)
        persistCoverage()
        val images=kotlinx.coroutines.channels.Channel<Pair<ArtworkRecord,String>>(8)
        val queued=java.util.concurrent.atomic.AtomicInteger()
        val completed=java.util.concurrent.atomic.AtomicInteger()
        val imageKeys=hashSetOf<String>()
        suspend fun enqueue(record:ArtworkRecord,key:String) {
            if(imageKeys.add(key)&&!Artwork.hasDownload(context,key,quality)){queued.incrementAndGet();images.send(record to key)}
        }
        val workers=List(4){launch {
            for((record,key) in images){
                try{image(record,key)}catch(failure:Exception){fail(key,failure)}
                progress(DownloadProgress(completed.incrementAndGet(),queued.get(),"Saving card artwork…"))
            }
        }}
        try {
        names.forEachIndexed{index,name->
            checkActive();progress(DownloadProgress(index,names.size,"Checking $name"))
            try {
                // Metadata is still needed on deck retries to discover faces and tokens.
                val card=catalogue.card(name) ?: error("No unambiguous catalogue artwork.")
                card.faces.filter{it.images.isNotEmpty()&&it.name !in nameSet}.forEach{faces+=it.name}
                if(includeTokens)card.related.forEach{wantedTokens.putIfAbsent(it,catalogue.tokens[it])}
                enqueue(card.faces.firstOrNull{it.name.equals(name,true)&&it.images.isNotEmpty()} ?: card,name)
                card.faces.filter{it.images.isNotEmpty()}.forEach{face->enqueue(face,face.name)}
            } catch(failure:Exception){fail(name,failure)}
        }
        if(includeTokens)wantedTokens.entries.forEachIndexed{index,(id,known)->
            checkActive();progress(DownloadProgress(names.size+index,names.size+wantedTokens.size,"Checking token artwork"))
            try {
                val record=known ?: metadata(URL("https://api.scryfall.com/cards/$id"))
                check(record.id==id&&record.token!=null){"Token metadata is unavailable."}
                checkActive();Artwork.saveToken(context,record)
                enqueue(record,"token:$id")
            } catch(failure:Exception){fail("Token $id",failure)}
        }
        images.close();workers.forEach{it.join()}
        checkActive()
        progress(DownloadProgress(names.size+wantedTokens.size,names.size+wantedTokens.size,"Download check complete"))
        if(omittedFailures>0)failures+="$omittedFailures additional items are unavailable. Completed files were retained."
        failures
        } finally {images.close();persistCoverage()}
    }
    private suspend fun collection(identifiers:List<Map<String,String>>,includeTokens:Boolean):ArtworkCatalogue {
        val result=ArtworkCatalogue()
        suspend fun fetch(values:List<Map<String,String>>) {
            values.chunked(75).forEach{batch->
                val bytes=ArtworkTransport.bytes(context,URL("https://api.scryfall.com/cards/collection"),8*1024*1024,setOf("application/json"),Wire.encode(mapOf("identifiers" to batch)))
                val response=Wire.objectValue(io.magicmobile.core.Json.parseObject(bytes.toString(Charsets.UTF_8)))
                validatedArtworkCollection(response,batch.size).forEach(result::add)
            }
        }
        fetch(identifiers)
        if(includeTokens){
            val ids=identifiers.mapNotNull{it["name"]}.flatMap{result.card(it)?.related.orEmpty()}.distinct()
            fetch(ids.map{mapOf("id" to it)})
        }
        return result
    }
    private suspend fun metadata(url:URL):ArtworkRecord {
        val data=ArtworkTransport.bytes(context,url,4*1024*1024,setOf("application/json"))
        return ArtworkCatalogue.decode(Wire.objectValue(io.magicmobile.core.Json.parseObject(data.toString(Charsets.UTF_8)))) ?: error("Invalid artwork metadata.")
    }
    private suspend fun bulk():ArtworkCatalogue {
        val directory=java.io.File(context.filesDir,"artwork-catalogue").apply{mkdirs()}
        val cache=java.io.File(directory,"oracle.gz")
        val job=coroutineContext
        fun parse(file:java.io.File):ArtworkCatalogue=file.inputStream().buffered(65536).use{raw->
            raw.mark(2);val gzip=raw.read()==0x1f&&raw.read()==0x8b;raw.reset()
            val input=if(gzip)java.util.zip.GZIPInputStream(raw,65536)else raw
            ArtworkCatalogue.parse(input){job.ensureActive();check(Artwork.enabled(context)){"Online artwork is disabled."}}
        }
        if(cache.isFile&&System.currentTimeMillis()-cache.lastModified() in 0..86_400_000) {
            try{return parse(cache)}catch(cancelled:CancellationException){throw cancelled}catch(_:Exception){/* Replace invalid cache only after a valid download. */}
        }
        val metadata=ArtworkTransport.bytes(context,URL("https://api.scryfall.com/bulk-data"),2*1024*1024,setOf("application/json"))
        val root=Wire.objectValue(io.magicmobile.core.Json.parseObject(metadata.toString(Charsets.UTF_8)))
        val item=root.array("data").map(Wire::objectValue).firstOrNull{it.text("type")=="oracle_cards"} ?: error("Oracle catalogue is unavailable.")
        val url=URL(item.text("jsonl_download_uri") ?: item.text("download_uri") ?: error("Catalogue download is unavailable."))
        check(url.host=="data.scryfall.io"){"Unsupported catalogue address."}
        val temporary=java.io.File.createTempFile("oracle-",".partial",directory)
        try{
            temporary.outputStream().use{ArtworkTransport.transfer(context,url,250L*1024*1024,setOf("application/gzip","application/x-gzip","application/json","application/octet-stream"),it)}
            val parsed=parse(temporary);coroutineContext.ensureActive()
            java.nio.file.Files.move(temporary.toPath(),cache.toPath(),java.nio.file.StandardCopyOption.REPLACE_EXISTING,java.nio.file.StandardCopyOption.ATOMIC_MOVE)
            return parsed
        }finally{temporary.delete()}
    }
}
