package io.magicmobile.android

import android.content.Context
import kotlinx.coroutines.*
import java.io.ByteArrayOutputStream
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URL
import kotlin.coroutines.coroutineContext

/** No redirects, credentials, cookies, or non-Scryfall hosts. Cancellation closes the socket. */
internal object ArtworkTransport {
    suspend fun bytes(context:Context,url:URL,maximum:Int,types:Set<String>):ByteArray {
        val output=ByteArrayOutputStream()
        transfer(context,url,maximum.toLong(),types,output)
        return output.toByteArray()
    }
    suspend fun transfer(context:Context,url:URL,maximum:Long,types:Set<String>,output:OutputStream)=coroutineScope {
        require(url.protocol=="https" && url.host in setOf("api.scryfall.com","cards.scryfall.io","data.scryfall.io") && url.userInfo==null && (url.port==-1||url.port==443)&&url.ref==null){"Unsupported artwork address."}
        coroutineContext.ensureActive();check(Artwork.enabled(context)){"Online artwork is disabled."}
        ScryfallRequestBudget.awaitTurn()
        coroutineContext.ensureActive();check(Artwork.enabled(context)){"Online artwork is disabled."}
        val connection=(url.openConnection() as HttpURLConnection).apply {
            instanceFollowRedirects=false;connectTimeout=15000;readTimeout=30000;useCaches=false
            setRequestProperty("User-Agent","MagicMobile-Android/0.1.1 (artwork)")
            setRequestProperty("Accept",types.joinToString(","))
        }
        val cancellation=launch(Dispatchers.IO,start=CoroutineStart.UNDISPATCHED){try{awaitCancellation()}finally{connection.disconnect()}}
        try {
            if(connection.responseCode==429){ScryfallRequestBudget.backOff(connection.getHeaderField("Retry-After")?.toIntOrNull()?:60);error("Scryfall requests are paused. Retry later.")}
            check(connection.responseCode==200){"Scryfall returned ${connection.responseCode}."}
            check(connection.contentType?.substringBefore(';')?.trim()?.lowercase() in types){"Unsupported artwork file."}
            check(connection.contentLengthLong<=maximum){"Artwork file is too large."}
            val buffer=ByteArray(65536);var size=0L
            connection.inputStream.use{input->while(true){coroutineContext.ensureActive();check(Artwork.enabled(context)){"Online artwork is disabled."};val read=input.read(buffer);if(read<0)break;size+=read;check(size<=maximum){"Artwork file is too large."};output.write(buffer,0,read)}}
            coroutineContext.ensureActive();check(Artwork.enabled(context)){"Online artwork is disabled."};check(size>0){"Empty artwork file."}
        } finally {cancellation.cancel();connection.disconnect()}
    }
}
