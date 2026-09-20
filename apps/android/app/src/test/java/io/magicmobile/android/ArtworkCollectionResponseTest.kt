package io.magicmobile.android

import io.magicmobile.android.core.*
import org.junit.Assert.*
import org.junit.Test

class ArtworkCollectionResponseTest {
    private val response=Wire.decode("""{"object":"list","not_found":[],"data":[{"object":"card","id":"00000000-0000-0000-0000-000000000001","name":"Island"}]}""".toByteArray())

    @Test fun acceptsActualCollectionShapeWithoutPaginationField() {
        assertEquals("Island",validatedArtworkCollection(response,1).single().text("name"))
        assertEquals(validatedArtworkCollection(response,1),validatedArtworkCollection(response+("has_more" to false),1))
        assertTrue(validatedArtworkCollection(response+("data" to emptyList<Obj>()),1).isEmpty())
    }

    @Test fun rejectsInvalidPaginationAndUnboundedOrMalformedData() {
        listOf<Any?>(true,"false",0,null).forEach{value->
            assertTrue(runCatching{validatedArtworkCollection(response+("has_more" to value),1)}.isFailure)
        }
        listOf(response-"data",response+("object" to "error"),response+("data" to emptyMap<String,Any>()),
            response+("data" to listOf("not a card")),response+("data" to response.array("data")+response.array("data")))
            .forEach{assertTrue(runCatching{validatedArtworkCollection(it,1)}.isFailure)}
        assertTrue(runCatching{validatedArtworkCollection(response,0)}.isFailure)
        assertTrue(runCatching{validatedArtworkCollection(response,76)}.isFailure)
    }
}
