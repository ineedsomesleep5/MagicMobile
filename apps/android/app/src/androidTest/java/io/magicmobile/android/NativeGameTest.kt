package io.magicmobile.android

import androidx.test.platform.app.InstrumentationRegistry
import io.magicmobile.android.core.*
import org.junit.Assert.*
import org.junit.Test

/** Exercises the packaged JNI/AOT engine, not a fixture or network substitute. */
class NativeGameTest {
    @Test fun nativeRuntimeClosesAndReopens() {
        assertTrue(BuildConfig.NATIVE_ENGINE)
        android.util.Log.i("MagicMobileAcceptance","Opening native runtime")
        val token=NativeBridge.open()
        assertTrue(token!=0L)
        android.util.Log.i("MagicMobileAcceptance","Native runtime opened")
        assertEquals(0,NativeBridge.close(token))
        android.util.Log.i("MagicMobileAcceptance","Native runtime closed")
        val reopened=NativeBridge.open()
        assertTrue(reopened!=0L && reopened!=token)
        android.util.Log.i("MagicMobileAcceptance","Native runtime reopened without requests")
        assertEquals(0,NativeBridge.close(reopened))
    }
    @Test fun packagedEngineCompletesCommanderGame() {
        assertTrue("This test requires -PwithNative=true", BuildConfig.NATIVE_ENGINE)
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        val catalogue=Catalogue(context.assets.open("catalogue.jsonl"))
        val decks=Wire.decode(context.assets.open("precons.json").use {it.readBytes()})
            .array("decks").map {Deck.decode(Wire.objectValue(it))}
        val human=decks.first {it.name.contains("Token Triumph",true)}
        val opponent=decks.first {it.name.contains("Grave Danger",true)}
        var token=NativeBridge.open()
        assertTrue("Native isolate opens",token!=0L)
        android.util.Log.i("MagicMobileAcceptance","Game test: runtime opened; validating bundled deck")
        fun request(op:String,vararg fields:Pair<String,Any?>)=Wire.result(NativeBridge.request(token,Wire.request(op,*fields)))
        try {
            val valid=request("validateDeck","deck" to catalogue.resolve(human,false))
            android.util.Log.i("MagicMobileAcceptance","Game test: validation returned")
            assertTrue(valid.flag("valid"))
            assertEquals(catalogue.upstreamCommit,valid.text("upstream"))
            assertEquals(catalogue.registryHash,valid.text("catalogueHash"))
            // Validate teardown/reopen, the same transition used by the Play dialog.
            assertEquals(0,NativeBridge.close(token));token=0
            android.util.Log.i("MagicMobileAcceptance","Game test: validation runtime closed; reopening")
            token=NativeBridge.open();assertTrue(token!=0L)
            android.util.Log.i("MagicMobileAcceptance","Game test: runtime reopened; creating match")
            val created=request("create","configuration" to mapOf("seats" to listOf(
                mapOf("seatId" to "player-1","name" to "You","controller" to "human","deck" to catalogue.resolve(human,false)),
                mapOf("seatId" to "player-2","name" to "AI","controller" to "ai","aiSkill" to 1,"deck" to catalogue.resolve(opponent,false)))))
            assertEquals("native-aot",created.obj("engine")?.text("execution"))
            val match=Wire.string(created["matchId"])
            val state=PollState(match,"player-1")
            val deadline=System.nanoTime()+java.util.concurrent.TimeUnit.MINUTES.toNanos(25)
            var highestTurn=0L;var responses=0;var lastProgress=0L
            val kinds=mutableSetOf<String>()
            while(System.nanoTime()<deadline) {
                val poll=GamePoll.parse(request("poll","matchId" to match,"viewerId" to "player-1","after" to (state.current?.revision ?: 0L)),match,"player-1")
                state.publish(poll)
                highestTurn=maxOf(highestTurn,poll.snapshot?.obj("gameView")?.number("turn") ?: 0L)
                if(highestTurn>lastProgress){lastProgress=highestTurn;android.util.Log.i("MagicMobileAcceptance","Turn $highestTurn; responses $responses")}
                if(poll.phase=="failed")fail("Native game failed: ${poll.failure}; diagnostics: ${request("diagnostics")}")
                if(poll.phase=="ended") {
                    assertTrue("A real multi-turn game completed",highestTurn>=2 && responses>0)
                    val evidence="Native Commander game completed; turn=$highestTurn; responses=$responses; promptKinds=${kinds.sorted()}; upstream=${catalogue.upstreamCommit}; catalogue=${catalogue.registryHash}"
                    android.util.Log.i("MagicMobileAcceptance",evidence)
                    java.io.File(context.getExternalFilesDir(null),"native-game-acceptance.txt").writeText(evidence)
                    return
                }
                val prompt=state.current?.decision
                if(prompt!=null && !prompt.submitted) {
                    kinds+=prompt.kind
                    val choices=Decisions.choices(prompt,poll.snapshot)
                    // The test human keeps the opening hand, passes priority, and chooses
                    // a legal discard when required. The real AI plays to a natural win.
                    val choice=when(prompt.kind) {
                        "ASK"->choices.firstOrNull {it.type=="boolean" && it.value==false}
                        "SELECT"->choices.firstOrNull {it.type=="boolean" && it.value==true}
                        else->choices.firstOrNull {it.type=="uuid"} ?: choices.firstOrNull()
                    }
                    val command=when {
                        choice!=null->state.prepare(choice.type,choice.value)
                        "integer" in prompt.responseTypes->state.prepare("integer",maxOf(0L,prompt.minimum ?: 0L).coerceAtMost(prompt.maximum ?: Int.MAX_VALUE.toLong()))
                        else->error("Unhandled real prompt ${prompt.kind}; accepted types=${prompt.responseTypes}")
                    }
                    request("respond","matchId" to match,"viewerId" to "player-1","command" to command)
                    state.acknowledged();responses++
                }
                Thread.sleep(30)
            }
            fail("Game did not complete within 25 minutes; turn=$highestTurn; responses=$responses; prompt=${state.current?.decision?.kind}")
        } finally {
            if(token!=0L) {
                var status=NativeBridge.close(token)
                repeat(30){if(status!=0){Thread.sleep(100);status=NativeBridge.close(token)}}
                assertEquals("Native runtime releases after game",0,status)
            }
        }
    }
}
