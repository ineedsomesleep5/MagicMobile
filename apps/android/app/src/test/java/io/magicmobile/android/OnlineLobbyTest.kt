package io.magicmobile.android

import io.magicmobile.android.core.*
import org.junit.Assert.*
import org.junit.Test

class OnlineLobbyTest {
    private val user="98765432-1234-4234-8234-123456789012"
    private fun lobby():Obj=mapOf("id" to "12345678-1234-4234-8234-123456789012","code" to "ABC123","status" to "ready","hostUserId" to user,"playerCount" to 2L,"players" to listOf(mapOf("userId" to user,"name" to "Caleb","seatId" to user,"ready" to true,"deckSubmitted" to true)))
    @Test fun `lobby keeps authenticated seat and readiness`() {
        val result=OnlineLobby.parse(Wire.decode(Wire.encode(lobby())))
        assertEquals(2,result.playerCount);assertEquals(user,result.players.single().seatId)
        assertTrue(result.players.single().ready);assertNull(result.matchId)
    }
    @Test fun `duplicate seats and oversized lobbies fail closed`() {
        val row=lobby().array("players").single()
        assertThrows(IllegalArgumentException::class.java){OnlineLobby.parse(lobby()+mapOf("players" to listOf(row,row)))}
        assertThrows(IllegalArgumentException::class.java){OnlineLobby.parse(lobby()+mapOf("playerCount" to 5L))}
    }
    @Test fun `non uuid lobby ids cannot become request paths`() {
        assertThrows(IllegalArgumentException::class.java){OnlineLobby.parse(lobby()+mapOf("id" to "../other"))}
    }
    @Test fun `authentication string errors retain refresh code`() {
        val error=onlineServiceError(400,mapOf("error" to "invalid_grant","code" to "refresh_token_not_found","error_description" to "Refresh token expired"))
        assertEquals("refresh_token_not_found",error.code);assertEquals("Refresh token expired",error.message)
    }
    @Test fun `server errors retain structured rejection code`() {
        val error=onlineServiceError(409,mapOf("error" to mapOf("code" to "stale_prompt","message" to "Refresh this decision")))
        assertEquals("stale_prompt",error.code);assertEquals("Refresh this decision",error.message)
    }
    @Test fun `current lobby response distinguishes no membership from malformed reply`() {
        assertNull(decodeOnlineResponse(" null\n".toByteArray()))
        assertEquals("ABC123",OnlineLobby.parse(checkNotNull(decodeOnlineResponse(Wire.encode(lobby())))).code)
        assertThrows(Exception::class.java){decodeOnlineResponse("[]".toByteArray())}
        assertThrows(Exception::class.java){decodeOnlineResponse("".toByteArray())}
    }
    @Test fun `polling allows quota headroom and bounded recovery`() {
        assertEquals(1000L,onlinePollDelayMillis(0))
        assertEquals(2000L,onlinePollDelayMillis(1))
        assertEquals(10_000L,onlinePollDelayMillis(5))
        assertEquals(30_000L,onlinePollDelayMillis(Int.MAX_VALUE))
        assertTrue(60_000L/onlinePollDelayMillis(0)<180L)
    }
    @Test fun `interrupted membership retains leave target without creating gameplay`() {
        val result=OnlineLobby.parse(lobby()+mapOf("status" to "interrupted","matchId" to null,"seatId" to null))
        assertEquals("interrupted",result.status);assertNull(result.matchId);assertNull(result.seatId)
        assertEquals(lobby()["id"],result.id)
    }
}
