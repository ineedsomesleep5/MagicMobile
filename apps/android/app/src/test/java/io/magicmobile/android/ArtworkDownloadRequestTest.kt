package io.magicmobile.android

import io.magicmobile.android.core.*
import org.junit.Assert.*
import org.junit.Test
import java.io.IOException
import kotlinx.coroutines.CancellationException

class ArtworkDownloadRequestTest {
    @Test fun restoresExactCardsQualityTokensAndScope() {
        ArtworkQuality.entries.forEach{quality->listOf(true,false).forEach{tokens->
            val request=ArtworkDownloadRequest(listOf("Island","Karametra's Favor"),quality,tokens,false)
            assertEquals(request,ArtworkDownloadRequest.decode(request.encode()))
            assertEquals(request.copy(catalogue=true),ArtworkDownloadRequest.decode(request.copy(catalogue=true).encode()))
        }}
    }
    @Test fun malformedRequestsCannotSilentlyChangeScopeOrQuality() {
        val valid=Wire.decode(ArtworkDownloadRequest(listOf("Island"),ArtworkQuality.STANDARD,true,false).encode())
        listOf(valid-"tokens",valid+("quality" to "unknown"),valid+("catalogue" to "true"),
            valid+("schema" to 2),valid+("names" to emptyList<String>()),valid+("names" to listOf("Island",2)),
            valid+("names" to listOf("Island","Island"))).forEach{assertTrue(runCatching{ArtworkDownloadRequest.decode(Wire.encode(it))}.isFailure)}
        assertTrue(runCatching{ArtworkDownloadRequest.decode("<html>offline</html>".toByteArray())}.isFailure)
    }
    @Test fun retriesOnlyBoundedTransientTransfers() {
        assertTrue(shouldRetryArtworkTransfer(IOException("connection lost"),0))
        assertTrue(shouldRetryArtworkTransfer(IllegalStateException("Scryfall returned 503."),1))
        assertFalse(shouldRetryArtworkTransfer(IOException("connection lost"),2))
        assertFalse(shouldRetryArtworkTransfer(IllegalStateException("Scryfall returned 429."),0))
        assertFalse(shouldRetryArtworkTransfer(IllegalStateException("Unsupported artwork file."),0))
        assertFalse(shouldRetryArtworkTransfer(CancellationException("paused"),0))
    }
}
