package io.magicmobile.android

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import android.util.AtomicFile
import androidx.compose.foundation.Image
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import io.magicmobile.android.core.*
import kotlin.coroutines.coroutineContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.security.MessageDigest

/**
 * Card artwork on the same terms as the iOS build: opt-in, Scryfall only, bounded, and
 * cached on the device. Declining leaves every other feature working; rules text and deck
 * building never need the network.
 */
object Artwork {
    private val downloaded=MutableSharedFlow<String>(extraBufferCapacity=64,onBufferOverflow=BufferOverflow.DROP_OLDEST)
    internal val downloadChanges=downloaded.asSharedFlow()
    internal var consentRevision by mutableIntStateOf(0)
        private set
    private const val PREFS = "magicmobile.artwork"
    private const val CONSENT_KEY = "magicmobile.deckArtworkNetworkEnabled"
    private const val MAX_BYTES = 2 * 1024 * 1024
    private const val MAX_DOWNLOAD_BYTES = 20L * 1024 * 1024 * 1024
    private const val FREE_SPACE_RESERVE = 1024L * 1024 * 1024
    private val ALLOWED_HOSTS = setOf("api.scryfall.com", "cards.scryfall.io")
    private const val MAX_REDIRECTS = 5
    private val ALLOWED_TYPES = setOf("image/jpeg", "image/png")

    private val memory = object : LruCache<String, Bitmap>(24 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Bitmap) = value.byteCount
    }
    /** ON_STOP: drop decoded images; they reload from the disk cache when the board is shown again. */
    fun releaseMemory() = memory.evictAll()

    private val downloadLock=Any()
    private var accountedDownloadBytes=-1L
    private var tokenMetadata: Map<String,ArtworkRecord>? = null
    private val tokenLookupLock=Mutex()
    private val checkedTokens=mutableMapOf<ArtworkTokenIdentity,Long>()
    private const val TOKEN_RETRY_MS=5*60*1000L

    /** Saved token metadata by Scryfall ID, from downloads and from live play. */
    internal fun storedTokens(context:Context):Map<String,ArtworkRecord> = tokens(context)
    private fun tokens(context:Context):Map<String,ArtworkRecord> = synchronized(downloadLock) {
        tokenMetadata ?: downloadDirectory(context).listFiles().orEmpty().filter{it.extension=="token"&&it.length() in 1..32768}.mapNotNull{file->
            runCatching{ArtworkCatalogue.decode(Wire.objectValue(io.magicmobile.core.Json.parseObject(file.readText())))}.getOrNull()
        }.filter{it.token!=null}.associateBy{it.id}.also{tokenMetadata=it}
    }
    internal fun saveToken(context:Context,record:ArtworkRecord) = synchronized(downloadLock) {
        require(record.token!=null)
        val bytes=Wire.encode(record.json());require(bytes.size<=32768)
        val file=AtomicFile(File(downloadDirectory(context),"${record.id.replace(':','_')}.token"));val output=file.startWrite()
        try{output.write(bytes);file.finishWrite(output)}catch(failure:Throwable){file.failWrite(output);throw failure}
        tokenMetadata=tokens(context)+(record.id to record)
    }

    private fun downloadDirectory(context: Context) =
        File(context.filesDir, "downloaded-card-art-v1").apply { mkdirs() }

    /** Live Scryfall art is on unless the player turned it off (iOS registers the same default). */
    fun enabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(CONSENT_KEY, true)

    fun setEnabled(context: Context, value: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean(CONSENT_KEY, value).apply()
        consentRevision++
        if(!value)ArtworkDownloadService.pause(context.applicationContext)
    }

    private fun cacheFile(context: Context, name: String) =
        File(File(context.cacheDir, "card-art").apply { mkdirs() }, artworkFileKey(name) + ".img")

    internal fun downloadFile(context: Context, name: String, quality: ArtworkQuality) =
        File(downloadDirectory(context), artworkDownloadFileName(name, quality))

    /** The stored image file names, read once (NativeAssetDownloads scans one directory listing too). */
    internal fun downloadedFileNames(context: Context): Set<String> =
        downloadDirectory(context).listFiles()?.filter { it.isFile && it.length() in 1..MAX_BYTES.toLong() }?.mapTo(HashSet()) { it.name } ?: emptySet()

    /** Whether a listing holds an image at this quality or better, without decoding it. */
    internal fun listedDownload(files: Set<String>, name: String, quality: ArtworkQuality): Boolean =
        listedArtworkDownload(files, name, quality)

    /** A downloaded token image of any quality, even Compact, can be shown. */
    private fun hasTokenDownload(context: Context, id: String) = hasDownload(context, "token:$id", TOKEN_DOWNLOAD_QUALITY)

    internal fun hasDownload(context: Context, name: String, quality: ArtworkQuality): Boolean =
        ArtworkQuality.entries.asReversed().any { candidate ->
            candidate.shortEdge >= quality.shortEdge &&
                downloadFile(context, name, candidate).let { file ->
                    file.isFile && file.length() in 1..MAX_BYTES.toLong() && BitmapFactory.Options().let { bounds ->
                        bounds.inJustDecodeBounds=true;BitmapFactory.decodeFile(file.path,bounds)
                        minOf(bounds.outWidth,bounds.outHeight)>=quality.shortEdge && maxOf(bounds.outWidth,bounds.outHeight)<=4096
                    }
                }
        }

    internal fun storedDownloadBytes(context: Context): Long = synchronized(downloadLock) {
        if(accountedDownloadBytes<0)accountedDownloadBytes=downloadDirectory(context).listFiles()?.filter(File::isFile)?.sumOf(File::length) ?: 0L
        accountedDownloadBytes
    }

    internal fun saveDownload(context: Context, name: String, quality: ArtworkQuality, bytes: ByteArray): Boolean {
        if (name.isBlank() || name.length > 512 || bytes.size !in 1..MAX_BYTES) return false
        val bitmap = decode(bytes) ?: return false
        if (minOf(bitmap.width, bitmap.height) < quality.shortEdge) return false
        synchronized(downloadLock) {
            val destination=downloadFile(context, name, quality)
            val previous=destination.takeIf(File::isFile)?.length() ?: 0L
            val stored=storedDownloadBytes(context)
            check(stored-previous+bytes.size<=MAX_DOWNLOAD_BYTES){"Artwork storage reached its 20 GB limit. Existing downloads were preserved."}
            check(destination.parentFile?.usableSpace?.let{it-bytes.size>=FREE_SPACE_RESERVE}==true){"Download paused to preserve 1 GB of free device space."}
            val atomic = AtomicFile(downloadFile(context, name, quality))
            val output = atomic.startWrite()
            try { output.write(bytes); atomic.finishWrite(output) }
            catch (failure: Throwable) { atomic.failWrite(output); throw failure }
            accountedDownloadBytes=stored-previous+bytes.size
            memory.put(name, bitmap)
        }
        downloaded.tryEmit(name)
        return true
    }

    internal fun matchesDownload(context:Context,key:String,name:String,token:Boolean,identity:ArtworkTokenIdentity?,printingKey:String?=null):Boolean =
        artworkDownloadMatches(key,name,token,identity,if(token&&key.startsWith("token:"))tokens(context)[key.removePrefix("token:")]?.token else null,printingKey)

    private fun decode(bytes: ByteArray): Bitmap? = runCatching {
        val bounds=BitmapFactory.Options().apply{inJustDecodeBounds=true}
        BitmapFactory.decodeByteArray(bytes,0,bytes.size,bounds)
        if(bounds.outWidth !in 1..4096 || bounds.outHeight !in 1..4096)null else BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
    }.getOrNull()

    /** Returns null when artwork is unavailable; it never substitutes a different card. */
    suspend fun load(context: Context, name: String, token:Boolean=false, tokenIdentity:ArtworkTokenIdentity?=null, art:CardArtChoices.Selection?=null,
                     cachedReady:suspend (Bitmap)->Unit = {}): Bitmap? = withContext(Dispatchers.IO) {
        if (name.isBlank() || name.length > 512) return@withContext null
        if(!token) {
            // The art the player chose, exactly that printing. The card's default art shows instead only when
            // Scryfall has no such printing, or it is neither saved nor reachable online.
            if(art!=null)loadImage(context,printingArtKey(art),cachedReady){fetchPrinting(context,art)}?.let{return@withContext it}
            return@withContext loadImage(context,name,cachedReady){fetch(context,name)}
        }
        val lookup=run {
            val identity=tokenIdentity?.normalized() ?: return@withContext null
            val online=enabled(context)
            val stored=tokens(context).values
            // As on iOS: a Standard image, else online a lookup for one, else any downloaded
            // quality (Compact downloads count), and offline a differently worded equivalent.
            val matched=selectEquivalentToken(stored,identity){hasDownload(context,"token:${it.id}",ArtworkQuality.STANDARD)}
                ?: (if(online)fetchToken(context,identity) else null)
                ?: selectEquivalentToken(stored,identity){hasTokenDownload(context,it.id)}
                ?: if(!online)looseEquivalentToken(stored,identity){hasTokenDownload(context,it.id)} else null
            "token:"+(matched?.id ?: return@withContext null)
        }
        var cached=memory.get(lookup)
        cached?.let{return@withContext it}
        ArtworkQuality.entries.asReversed().forEach { quality ->
            val downloaded = downloadFile(context, lookup, quality)
            if (downloaded.isFile && downloaded.length() in 1..MAX_BYTES.toLong()) {
                decode(downloaded.readBytes())?.let { if(cached==null || it.width>cached!!.width)cached=it }
            }
        }
        cached
    }

    /**
     * A card image by key (the card's name, or a chosen printing): the best saved download, the live cache,
     * and, with online art on, one fetch for a High image. A saved image keeps showing when the fetch fails.
     */
    private suspend fun loadImage(context:Context,key:String,cachedReady:suspend (Bitmap)->Unit,fetcher:suspend ()->ByteArray?):Bitmap? {
        var cached=memory.get(key)
        cached?.takeIf{minOf(it.width,it.height)>=ArtworkQuality.HIGH.shortEdge}?.let{return it}
        ArtworkQuality.entries.asReversed().forEach { quality ->
            val downloaded = downloadFile(context, key, quality)
            if (downloaded.isFile && downloaded.length() in 1..MAX_BYTES.toLong()) {
                decode(downloaded.readBytes())?.let { if(cached==null || it.width>cached!!.width)cached=it }
            }
        }
        val file = cacheFile(context, key)
        if (file.isFile && file.length() in 1..MAX_BYTES.toLong()) {
            decode(file.readBytes())?.let { if(cached==null || it.width>cached!!.width)cached=it }
        }
        cached?.let { memory.put(key,it);cachedReady(it) }
        if (!enabled(context) || (cached?.let{minOf(it.width,it.height)>=ArtworkQuality.HIGH.shortEdge}==true)) return cached
        val bytes = try {fetcher()}catch(cancelled:CancellationException){throw cancelled}catch(_:Exception){null} ?: return cached
        coroutineContext.ensureActive()
        if(!enabled(context))return cached
        runCatching { file.writeBytes(bytes) }
        return decode(bytes)?.takeIf{cached==null || it.width>=cached!!.width}?.also { memory.put(key, it) } ?: cached
    }

    /** Scryfall's image of exactly this printing (its reverse face for `back`); null when there is no such printing or face. */
    private suspend fun fetchPrinting(context:Context,art:CardArtChoices.Selection): ByteArray? {
        val metadata=try{ArtworkTransport.bytes(context,URL(art.printing.cardUrl()),4*1024*1024,setOf("application/json"))}
            catch(failure:IllegalStateException){if(failure.message=="Scryfall returned 404.")return null else throw failure}
        val record=ArtworkCatalogue.decode(Wire.objectValue(io.magicmobile.core.Json.parseObject(metadata.toString(Charsets.UTF_8)))) ?: return null
        val image=printingImage(record,art.back,"large") ?: return null
        return ArtworkTransport.bytes(context,URL(image),MAX_BYTES,ALLOWED_TYPES)
    }

    private suspend fun fetch(context:Context,name: String): ByteArray? {
        val encoded=URLEncoder.encode(name,"UTF-8")
        val metadata=ArtworkTransport.bytes(context,URL("https://api.scryfall.com/cards/named?exact=$encoded"),4*1024*1024,setOf("application/json"))
        val record=ArtworkCatalogue.decode(Wire.objectValue(io.magicmobile.core.Json.parseObject(metadata.toString(Charsets.UTF_8)))) ?: return null
        val selected=record.faces.firstOrNull{it.name.equals(name,true)&&it.images.isNotEmpty()} ?: record
        val image=selected.images["large"] ?: return null
        return ArtworkTransport.bytes(context,URL(image),MAX_BYTES,ALLOWED_TYPES)
    }

    /**
     * Opt-in, bounded exact token lookup for a Standard image; never falls back to a card-name
     * image. load() uses a stored image of any quality when this finds nothing.
     */
    private suspend fun fetchToken(context:Context,identity:ArtworkTokenIdentity):ArtworkRecord? = tokenLookupLock.withLock {
        selectEquivalentToken(tokens(context).values,identity){hasDownload(context,"token:${it.id}",ArtworkQuality.STANDARD)}?.let{return@withLock it}
        val name=identity.name.removeSuffix(" token")
        if(!safeTokenSearchName(name) || !enabled(context))return@withLock null
        val now=System.currentTimeMillis()
        if(!tokenLookupAllowed(checkedTokens[identity],now,TOKEN_RETRY_MS))return@withLock null
        if(checkedTokens.size>=1024)checkedTokens.clear()
        try {
            val query=URLEncoder.encode("!\"$name\" t:token","UTF-8")
            val candidates=ArrayList<ArtworkRecord>()
            var more=false
            for(page in 1..3){
                coroutineContext.ensureActive()
                val metadata=ArtworkTransport.bytes(context,URL("https://api.scryfall.com/cards/search?q=$query&unique=cards&page=$page"),4*1024*1024,setOf("application/json"))
                val result=tokenSearchPage(Wire.objectValue(io.magicmobile.core.Json.parseObject(metadata.toString(Charsets.UTF_8))))
                candidates+=result.first
                more=result.second
                if(!more)break
            }
            if(more){checkedTokens[identity]=now;return@withLock null} // Truncated search cannot prove a safe match.
            val record=selectEquivalentToken(candidates,identity){it.images["normal"]!=null}
                ?: run{checkedTokens[identity]=now;return@withLock null}
            coroutineContext.ensureActive();check(enabled(context)){"Online artwork is disabled."}
            val image=ArtworkTransport.bytes(context,URL(record.images.getValue("normal")),MAX_BYTES,ALLOWED_TYPES)
            coroutineContext.ensureActive();check(enabled(context)){"Online artwork is disabled."}
            if(!saveDownload(context,"token:${record.id}",ArtworkQuality.STANDARD,image)){checkedTokens[identity]=now;return@withLock null}
            saveToken(context,record)
            checkedTokens.remove(identity)
            record
        }catch(cancelled:CancellationException){throw cancelled}
        catch(_:Exception){if(enabled(context))checkedTokens[identity]=now;null}
    }

    /** HTTPS only, Scryfall hosts only, no embedded credentials, default port only. */
    internal fun allowed(url: URL): Boolean =
        url.protocol == "https" &&
            url.host.lowercase() in ALLOWED_HOSTS &&
            url.userInfo == null &&
            (url.port == -1 || url.port == 443)
}

enum class ArtworkQuality(val id: String, val label: String, val imageVersion: String, val shortEdge: Int, val estimatedBytes: Int) {
    COMPACT("compact", "Compact", "small", 146, 20_000),
    STANDARD("standard", "Standard", "normal", 488, 100_000),
    HIGH("high", "High", "large", 672, 200_000),
}

internal data class ArtworkCrop(val x:Int,val y:Int,val width:Int,val height:Int)
internal fun artworkIllustrationCrop(imageWidth:Int,imageHeight:Int,targetWidth:Int,targetHeight:Int):ArtworkCrop {
    require(imageWidth>0&&imageHeight>0&&targetWidth>0&&targetHeight>0)
    var x=(imageWidth*.08).toInt();var y=(imageHeight*.145).toInt()
    var width=(imageWidth*.84).toInt().coerceAtLeast(1);var height=(imageHeight*.385).toInt().coerceAtLeast(1)
    width=width.coerceAtMost(imageWidth-x);height=height.coerceAtMost(imageHeight-y)
    val targetAspect=targetWidth.toDouble()/targetHeight
    if(width.toDouble()/height>targetAspect){val next=(height*targetAspect).toInt().coerceAtLeast(1);x+=(width-next)/2;width=next}
    else {val next=(width/targetAspect).toInt().coerceAtLeast(1);y+=(height-next)/2;height=next}
    return ArtworkCrop(x,y,width,height)
}

/**
 * Which art a card view draws: the player's choice for that card name (the default everywhere cards are drawn by
 * name), or an exact one. A deck row passes its own choice, `Exact(null)` meaning the card's default art, so
 * another deck's choice never shows on it. CardArtSelection.swift.
 */
sealed interface CardArtSelection {
    object Active : CardArtSelection
    data class Exact(val printing: CardPrinting?) : CardArtSelection
}

/** The player's art choices, with a Compose revision that changes whenever what a card name shows does. */
object ArtChoices {
    var revision by mutableIntStateOf(0)
        private set
    val shared = CardArtChoices()
    init { shared.addListener { revision++ } }

    /** The printing a view draws: an exact one, else the player's choice for this card name. */
    fun resolve(name: String, art: CardArtSelection, token: Boolean): CardArtChoices.Selection? = when {
        token -> null
        art is CardArtSelection.Exact -> art.printing?.let { CardArtChoices.Selection(it, false) }
        else -> shared.selection(name)
    }
}

@Composable
fun CardArtwork(name: String, modifier: Modifier = Modifier, token:Boolean=false, tokenIdentity:ArtworkTokenIdentity?=null, artOnly:Boolean=false,
                art: CardArtSelection = CardArtSelection.Active, placeholder: @Composable () -> Unit = {}) {
    val context = LocalContext.current
    val consent = remember(Artwork.consentRevision){Artwork.enabled(context)}
    val choice = remember(name, token, art, ArtChoices.revision) { ArtChoices.resolve(name, art, token) }
    var bitmap by remember(name, token, tokenIdentity, choice) { mutableStateOf<Bitmap?>(null) }
    LaunchedEffect(name, consent, token, tokenIdentity, choice) {
        val chosenKey = choice?.let(::printingArtKey)
        Artwork.downloadChanges.onStart{emit("")}.filter{it.isEmpty()||Artwork.matchesDownload(context,it,name,token,tokenIdentity,chosenKey)}.collectLatest{
            bitmap = try { Artwork.load(context, name, token, tokenIdentity, choice){cached->withContext(Dispatchers.Main){bitmap=cached}} } catch(cancelled:CancellationException){throw cancelled}catch(_:Exception){bitmap}
        }
    }
    Box(modifier.background(Color(0xFFEDE7DC)), contentAlignment = Alignment.Center) {
        val image = bitmap
        if (image != null) {
            if(artOnly)Canvas(Modifier.fillMaxSize()) {
                val width=size.width.toInt().coerceAtLeast(1);val height=size.height.toInt().coerceAtLeast(1)
                val crop=artworkIllustrationCrop(image.width,image.height,width,height)
                drawImage(image.asImageBitmap(),srcOffset=IntOffset(crop.x,crop.y),srcSize=IntSize(crop.width,crop.height),dstSize=IntSize(width,height))
            } else Image(image.asImageBitmap(), contentDescription = null,
                modifier = Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
        } else {
            placeholder()
        }
    }
}

/** A saved download refreshes a view that draws its token, its card name, or the printing it chose (the name's default art is the fallback). */
internal fun artworkDownloadMatches(key:String,name:String,token:Boolean,expected:ArtworkTokenIdentity?,actual:ArtworkTokenIdentity?,printingKey:String?=null):Boolean =
    if(token)key.startsWith("token:")&&expected!=null&&actual!=null&&expected.normalized()==actual.normalized() else key==name||(printingKey!=null&&key==printingKey)

/** A chosen printing's art is saved apart from the card's default art: "print:cmm/400", and ":back" for its reverse face. */
internal fun printingArtKey(printing:CardPrinting,back:Boolean=false)="print:${printing.key}"+if(back)":back" else ""
internal fun printingArtKey(art:CardArtChoices.Selection)=printingArtKey(art.printing,art.back)

/** The picture of a printing's record: its front, or the reverse face of a double-faced card; null when it has none. */
internal fun printingImage(record:ArtworkRecord,back:Boolean,version:String):String? =
    if(back)record.faces.getOrNull(1)?.images?.get(version) else record.images[version]

/** Duplicate printings are equivalent only when their complete public token metadata matches. */
internal fun selectEquivalentToken(records:Collection<ArtworkRecord>,identity:ArtworkTokenIdentity,usable:(ArtworkRecord)->Boolean):ArtworkRecord? =
    records.asSequence().filter{it.token?.normalized()==identity.normalized() && usable(it)}.minByOrNull{it.id}

/**
 * Offline only (NativeAssetStore.looseTokenArtwork): a download whose rules are worded
 * differently still shows when name, type and colors agree, printed P/T agrees where both are
 * known, and every such download is one token. Otherwise unresolved.
 */
internal fun looseEquivalentToken(records:Collection<ArtworkRecord>,identity:ArtworkTokenIdentity,usable:(ArtworkRecord)->Boolean):ArtworkRecord? {
    val wanted=identity.normalized()
    if(wanted.typeLine.isEmpty())return null
    fun sameStat(stored:String?,runtime:String?):Boolean {
        val printed=stored?.takeIf{it.isNotEmpty()};val shown=runtime?.takeIf{it.isNotEmpty()&&it!="0"}
        return printed==null||shown==null||printed==shown
    }
    val matches=records.mapNotNull{record->record.token?.normalized()?.let{record to it}}.filter{(_,token)->
        token.name==wanted.name&&token.typeLine==wanted.typeLine&&token.colors==wanted.colors&&
            sameStat(token.power,identity.power)&&sameStat(token.toughness,identity.toughness)
    }
    val first=matches.minByOrNull{it.first.id} ?: return null
    if(!matches.all{it.second==first.second})return null
    return matches.filter{usable(it.first)}.minByOrNull{it.first.id}?.first
}

/** Downloaded file name: a hash of the quality and card or token key. */
internal fun artworkDownloadFileName(name:String,quality:ArtworkQuality)=artworkFileKey("${quality.id}:$name")+".img"
internal fun artworkFileKey(name:String):String =
    MessageDigest.getInstance("SHA-256").digest(name.toByteArray()).joinToString(""){"%02x".format(it)}.take(40)
/** Whether a listing holds an image at this quality or better, without decoding it. */
internal fun listedArtworkDownload(files:Set<String>,name:String,quality:ArtworkQuality):Boolean =
    ArtworkQuality.entries.any{it.shortEdge>=quality.shortEdge&&artworkDownloadFileName(name,it) in files}
/** Tokens show from a download of any quality: a Compact download is enough offline. */
internal val TOKEN_DOWNLOAD_QUALITY=ArtworkQuality.COMPACT

internal fun safeTokenSearchName(name:String):Boolean = name.isNotBlank() && name.length<=120 &&
    '"' !in name && '\\' !in name && name.none{it.isISOControl()}

internal fun tokenLookupAllowed(lastFailure:Long?,now:Long,retryAfter:Long):Boolean =
    lastFailure==null || now<lastFailure || now-lastFailure>=retryAfter

/** One Scryfall search page; caller may request no more than three numbered pages. */
internal fun tokenSearchPage(root:Obj):Pair<List<ArtworkRecord>,Boolean> {
    val rows=root["data"] as? List<*> ?: error("Invalid token search data.")
    val more=root["has_more"] as? Boolean ?: error("Invalid token search pagination.")
    require(root.text("object")=="list" && rows.size<=200){"Invalid token search response."}
    // Double-faced tokens too (an Incubator is one), when they name both faces: each result brings its reverse face
    // as a record of its own. A "double_faced_token" row with no faces is malformed and skipped, as before.
    return rows.map(Wire::objectValue).filter{
        it.text("layout")=="token" || it.text("layout")=="double_faced_token" && (it["card_faces"] as? List<*>)?.size==2
    }.mapNotNull(ArtworkCatalogue::decode)
        .flatMap{listOfNotNull(it,it.back)} to more
}
