package io.magicmobile.android.core

import java.io.File
import java.util.UUID

private var checks=0
private fun verify(value:Boolean,label:String){checks++;check(value){label}}
private fun rejects(label:String,block:()->Unit){checks++;try{block()}catch(_:Exception){return};error("Expected rejection: $label")}
fun main(args:Array<String>){
    val id=UUID.randomUUID().toString()
    val base=mapOf("promptId" to "p", "revision" to 9007199254740993L,"kind" to "ASK","payload" to mapOf("message" to "Keep hand?"),"responseTypes" to listOf("boolean"),"min" to 0,"max" to 1)
    val d=Decision.parse(Wire.decode(Wire.encode(base)))
    verify(d.revision==9007199254740993L,"64-bit revision preserved")
    verify(d.answer("boolean",true)["value"]==true,"typed boolean")
    val labelledAsk=d.copy(payload=mapOf("message" to "Keep hand?","options" to mapOf("UI.left.btn.text" to "Keep <b>these seven</b>","UI.right.btn.text" to "Ship &amp; redraw")))
    val askChoices=Decisions.choices(labelledAsk,null)
    verify(askChoices==listOf(Choice("Keep these seven","boolean",true),Choice("Ship & redraw","boolean",false)),"ASK uses authoritative engine labels")
    verify(Decisions.choices(d,null).map{it.label}==listOf("Yes","No"),"ASK fallback labels stay semantically neutral")
    verify(Decisions.plain("&amp;lt;b&amp;gt;Keep&amp;lt;/b&amp;gt;&lt;br&gt;&#55; &mdash; ok")=="Keep\n7 — ok","display text reaches a safe decoded fixed point")
    rejects("wrong response kind"){d.answer("integer",1)}
    rejects("submitted prompt"){d.copy(submitted=true).answer("boolean",true)}
    rejects("duplicate JSON fields"){Wire.decode("{\"a\":1,\"a\":2}".toByteArray())}
    rejects("bad UTF8"){Wire.decode(byteArrayOf(0xC0.toByte(),0x80.toByte()))}
    rejects("protocol mismatch"){Wire.result(Wire.encode(mapOf("protocol" to 2,"ok" to true,"result" to emptyMap<String,Any>()))) }
    rejects("reversed bounds"){Decision.parse(base+mapOf("min" to 4,"max" to 2))}
    val amount=d.copy(kind="AMOUNT",responseTypes=setOf("integer"),minimum=-3,maximum=4)
    verify(amount.answer("integer",-3)["value"]==-3,"signed lower bound")
    rejects("amount lower"){amount.answer("integer",-4)}
    rejects("amount upper"){amount.answer("integer",5)}
    rejects("fractional amount"){amount.answer("integer",1.5)}
    val sentinelAmount=amount.copy(minimum=Int.MIN_VALUE.toLong(),maximum=Int.MAX_VALUE.toLong())
    verify(sentinelAmount.answer("integer",Int.MIN_VALUE)["value"]==Int.MIN_VALUE,"integer lower sentinel remains a valid protocol value")
    verify(sentinelAmount.answer("integer",Int.MAX_VALUE)["value"]==Int.MAX_VALUE,"integer upper sentinel remains a valid protocol value")
    rejects("below integer sentinel"){sentinelAmount.answer("integer",Int.MIN_VALUE.toLong()-1)}
    rejects("above integer sentinel"){sentinelAmount.answer("integer",Int.MAX_VALUE.toLong()+1)}
    val sentinelPresentation=PromptPresentation.integerRange(sentinelAmount)
    verify(sentinelPresentation.minimum==null && sentinelPresentation.maximum==null,"integer sentinels are hidden as unbounded")
    verify(sentinelPresentation.initialValue.isEmpty() && sentinelPresentation.label=="any amount","unbounded amount is not prefilled with a sentinel")
    verify(sentinelPresentation.contains(Int.MIN_VALUE.toLong()) && sentinelPresentation.contains(Int.MAX_VALUE.toLong()),"sentinel endpoints remain selectable")
    verify(!sentinelPresentation.contains(Int.MAX_VALUE.toLong()+1),"presentation rejects values outside engine integer domain")
    val constrainedPresentation=PromptPresentation.integerRange(amount)
    verify(constrainedPresentation.initialValue=="-3" && constrainedPresentation.label=="-3 … 4","real amount bounds remain visible")
    verify(constrainedPresentation.contains(-3L) && !constrainedPresentation.contains(5L),"visible amount range validates input")
    val multi=amount.copy(kind="MULTI_AMOUNT",responseTypes=setOf("integers"),minimum=2,maximum=3,payload=mapOf("allocations" to listOf(mapOf("min" to 0,"max" to 1),mapOf("min" to 1,"max" to 3))))
    verify(multi.answer("integers",listOf(1,2))["value"]==listOf(1,2),"allocations exact")
    rejects("wrong allocation count"){multi.answer("integers",listOf(3))}
    rejects("row bounds"){multi.answer("integers",listOf(2,1))}
    rejects("total bounds"){multi.answer("integers",listOf(0,1))}
    val snap=mapOf("schema" to "xmage-gameview-v1","enginePlayerId" to id,"gameView" to mapOf("myPlayerId" to id))
    val raw=mapOf("matchId" to "m","viewerId" to "you","revision" to d.revision,"phase" to "running","snapshot" to snap,"prompt" to base,"events" to emptyList<Any>())
    val poll=GamePoll.parse(raw,"m","you")
    rejects("wrong viewer"){GamePoll.parse(raw,"m","someone")}
    rejects("snapshot schema"){GamePoll.parse(raw+mapOf("snapshot" to (snap-"schema")),"m","you")}
    rejects("inner viewer"){GamePoll.parse(raw+mapOf("snapshot" to (snap+mapOf("gameView" to mapOf("myPlayerId" to UUID.randomUUID().toString())))),"m","you")}
    val state=PollState("m","you");verify(state.publish(poll),"first publication")
    val command=state.prepare("boolean",true);verify(command["promptRevision"]==d.revision,"command revision exact")
    verify(state.pending===command,"retry retains identical command")
    rejects("duplicate while pending"){state.prepare("boolean",false)}
    state.acknowledged();state.publish(poll)
    verify(state.current?.decision?.submitted==true,"equal revision cannot reopen consumed answer")
    rejects("consumed answer"){state.prepare("boolean",true)}
    verify(!state.publish(poll.copy(revision=d.revision-1,decision=null)),"old poll ignored")
    state.publish(poll.copy(revision=d.revision+1,phase="closed",decision=null))
    verify(state.current?.snapshot==null && state.terminal,"closed wipes private board")
    verify(!state.publish(poll.copy(revision=d.revision+2)),"terminal immutable")
    verify(Decisions.cardLabel(mapOf("name" to "Secret", "faceDown" to true))=="Face-down card","hidden card stays hidden")
    val target=d.copy(kind="PICK_TARGET",responseTypes=setOf("uuid","boolean"),payload=mapOf("required" to false,"cards" to listOf(mapOf("id" to id,"name" to "Visible")),"candidates" to listOf(id),"options" to mapOf("possibleTargets" to emptyList<String>(),"chosenTargets" to emptyList<String>())))
    verify(Decisions.choices(target,null).none{it.type=="uuid"},"browsable card is not necessarily eligible")
    val opponent=UUID.randomUUID().toString()
    val playerSnapshot=mapOf("gameView" to mapOf("players" to listOf(mapOf("playerId" to id,"name" to "You"),mapOf("playerId" to opponent,"name" to "Opponent <b>Two</b>"))))
    val playerTarget=target.copy(payload=mapOf("required" to true,"candidates" to listOf(opponent)))
    verify(Decisions.choices(playerTarget,playerSnapshot)==listOf(Choice("Opponent Two","uuid",opponent)),"player target uses projected player name instead of UUID")
    val chosen=target.copy(payload=target.payload+mapOf("options" to mapOf("possibleTargets" to emptyList<String>(),"chosenTargets" to listOf(id))))
    verify(Decisions.choices(chosen,null).any{it.type=="uuid" && it.value==id},"chosen target can be deselected")
    val deck=Deck.parse("Example","Commander\n1 Commander Name\n\nDeck\n2 Island\n1 Opt\n\nMaybeboard\n1 Test Card")
    verify(deck.entries.sumOf {it.quantity}==5,"counts preserved")
    verify(Deck.parse(deck.name,deck.export())==deck,"export roundtrip")
    verify(Deck.decode(deck.json())==deck,"JSON roundtrip")
    rejects("malformed line retained as error"){Deck.parse("Example","nonsense")}
    rejects("quantity overflow"){deck.change(0,Int.MAX_VALUE)}
    rejects("zero quantity"){Deck.parse("Example","0 Card")}
    verify(deck.change(1,-1).entries[1].quantity==1,"quantity edit")
    val fixtures=args.firstOrNull()?.let{File(it,"apps/ios/MagicMobileTests/Fixtures/OnDevice")}
    if(fixtures?.isDirectory==true){
        fixtures.listFiles().orEmpty().filter{it.extension=="json" && it.name.startsWith("2p-") || it.extension=="json" && it.name.startsWith("4p-")}.forEach {file->
            val envelope=Wire.decode(file.readBytes());val result=envelope.obj("result") ?: envelope
            if(result["matchId"] is String && result["viewerId"] is String){
                val p=GamePoll.parse(result,Wire.string(result["matchId"]),Wire.string(result["viewerId"]))
                p.decision?.let{Decisions.choices(it,p.snapshot)};verify(true,"real captured projection ${file.name}")
            }
        }
    }
    println("PASS: $checks Android protocol/deck/privacy assertions; fixture JVM checks, not Android or gameplay acceptance")
}
