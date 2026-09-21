package io.magicmobile.android.core

import java.io.File
import java.util.UUID

private var checks=0
private fun verify(value:Boolean,label:String){checks++;check(value){label}}
private fun rejects(label:String,block:()->Unit){checks++;try{block()}catch(_:Exception){return};error("Expected rejection: $label")}
fun main(args:Array<String>){
    autoYieldChecks()
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
    val a=UUID.randomUUID().toString();val b=UUID.randomUUID().toString();val c=UUID.randomUUID().toString()
    fun pick(message:String,revision:Long,available:List<String>,chosen:List<String>?=null):Decision=Decision("prompt-$revision",revision,"PICK_TARGET",
        mapOf("message" to message,"required" to false,"candidates" to available,
            "options" to (mapOf("UI.right.btn.text" to "Done")+(if(chosen==null)emptyMap() else mapOf("chosenTargets" to chosen,"possibleTargets" to available)))),
        setOf("uuid","boolean"),false,null,null)
    fun at(prompt:Decision)=GamePoll("match","viewer",prompt.revision,"running",null,prompt,false,emptyList(),null)
    val selectMessage="Choose cards (selected 0 of 3)"
    verify(!CardChoicePlan.supportsDraft(pick("Choose target",1,listOf(a,b),emptyList()).copy(minimum=0,maximum=1)),"single required target cannot open multi-card draft")
    verify(!CardChoicePlan.supportsDraft(pick("Choose a target",1,listOf(a,b),emptyList())),"unbounded UUID list alone cannot open draft")
    verify(CardChoicePlan.supportsDraft(pick(selectMessage,1,listOf(a,b,c),emptyList())),"counted multi-card selection supports draft")
    verify(CardChoicePlan.supportsDraft(pick(selectMessage,1,listOf(a,b,c),emptyList()).copy(minimum=0,maximum=1)),"one-UUID transport maximum does not hide aggregate multi-card draft")
    verify(CardChoicePlan.selectionBounds(pick("Sacrifice (selected 2 of 6, min 3)",1,listOf(a,b),emptyList()))==3 to 6,"aggregate selection bounds parse from prompt text")
    verify(!CardChoicePlan.supportsDraft(pick(selectMessage,1,listOf(a,b,c))),"selection without chosenTargets cannot open draft")
    verify(CardChoicePlan.create(at(pick("Choose target",1,listOf(a,b),emptyList()).copy(minimum=0,maximum=1)),listOf(a,b))==null,"core also rejects unsupported single-target draft")
    val draft=CardChoicePlan.create(at(pick(selectMessage,1,listOf(a,b,c),emptyList())),listOf(b,c))!!
    verify(draft.next(at(pick(selectMessage,1,listOf(a,b,c),emptyList())),false,false)?.value==b,"draft sends first UUID")
    verify(draft.next(at(pick(selectMessage,1,listOf(a,b,c),emptyList())),false,false)==null,"same prompt cannot send twice")
    verify(draft.next(at(pick("Choose cards (selected 1 of 3)",2,listOf(a,c),listOf(b))),false,false)?.value==c,"draft verifies chosen state before next UUID")
    verify(draft.next(at(pick("Choose cards (selected 2 of 3)",3,listOf(a),listOf(b,c))),false,false)?.type=="boolean" && !draft.finished,"explicit Done waits for delivery outcome")
    verify(draft.next(at(pick(selectMessage,4,listOf(a,b,c),emptyList())).copy(decision=null),false,false)==null && !draft.finished,"no-prompt poll does not prematurely finish draft")
    verify(draft.next(at(pick(selectMessage,5,listOf(a,b,c),emptyList()).copy(kind="SELECT")),false,false)==null && draft.finished,"new prompt acknowledges final Done")
    val stale=CardChoicePlan.create(at(pick(selectMessage,1,listOf(a,b),emptyList())),listOf(b))!!
    stale.next(at(pick(selectMessage,1,listOf(a,b),emptyList())),false,false)
    verify(stale.next(at(pick("Different choice",2,listOf(a),listOf(b))),false,false)==null && stale.stopped,"changed prompt context pauses draft")
    val mismatch=CardChoicePlan.create(at(pick(selectMessage,1,listOf(a,b),emptyList())),listOf(b))!!
    mismatch.next(at(pick(selectMessage,1,listOf(a,b),emptyList())),false,false)
    verify(mismatch.next(at(pick(selectMessage,2,listOf(a,b),emptyList())),false,false)==null && mismatch.stopped,"unchanged chosenTargets pauses draft")
    val lostCandidate=CardChoicePlan.create(at(pick(selectMessage,1,listOf(a,b,c),emptyList())),listOf(b,c))!!
    lostCandidate.next(at(pick(selectMessage,1,listOf(a,b,c),emptyList())),false,false)
    verify(lostCandidate.next(at(pick("Choose cards (selected 1 of 3)",2,listOf(c),listOf(b))),false,false)==null && lostCandidate.stopped,"changed candidate universe pauses draft")
    val bounded=CardChoicePlan.create(at(pick("Choose cards (selected 0 of 2, min 1)",1,listOf(a,b),emptyList()).copy(minimum=0,maximum=1)),listOf(a,b))!!
    bounded.next(at(pick("Choose cards (selected 0 of 2, min 1)",1,listOf(a,b),emptyList()).copy(minimum=0,maximum=1)),false,false)
    verify(bounded.next(at(pick("Choose cards (selected 1 of 2, min 2)",2,listOf(b),listOf(a)).copy(minimum=0,maximum=1)),false,false)==null && bounded.stopped,"changed aggregate count bounds pause selection despite stable transport bounds")
    verify(CardChoicePlan.create(at(pick("Sacrifice (selected 0 of 6, min 6)",1,listOf(a,b,c),emptyList()).copy(minimum=0,maximum=1)),listOf(a,b))==null,"draft cannot start below aggregate minimum")
    val six=(1..6).map{java.util.UUID.randomUUID().toString()}
    fun sacrifice(count:Int)=pick("Sacrifice (selected $count of 6, min 6)",count.toLong()+1,six.drop(count),six.take(count)).copy(minimum=0,maximum=1)
    val sixPlan=CardChoicePlan.create(at(sacrifice(0)),six)!!
    for(count in 0 until 6)verify(sixPlan.next(at(sacrifice(count)),false,false)?.value==six[count],"six-sacrifice stage ${count+1} sends one UUID with transport maximum one")
    verify(sixPlan.next(at(sacrifice(6)),false,false)?.type=="boolean" && !sixPlan.finished,"six-sacrifice Done follows acknowledged sixth UUID")
    val scryMessage="Choose cards (scry) to put on the bottom of your library (selected 0 of 3)"
    verify(CardChoicePlan.supportsDraft(pick(scryMessage,1,listOf(a,b,c),emptyList())),"scry supports draft")
    val scry=CardChoicePlan.create(at(pick(scryMessage,1,listOf(a,b,c),emptyList()).copy(minimum=0,maximum=1)),listOf(b,c),listOf(a))!!
    verify(CardChoicePlan.supportsDraft(pick(scryMessage,1,listOf(a,b,c),emptyList()).copy(minimum=0,maximum=1)),"scry remains draftable with one-UUID transport maximum")
    verify(scry.next(at(pick(scryMessage,1,listOf(a,b,c),emptyList()).copy(minimum=0,maximum=1)),false,false)?.value==b,"scry chooses bottom subset first with one-UUID transport bounds")
    verify(scry.next(at(pick(scryMessage.replace("0 of 3","1 of 3"),2,listOf(a,c),listOf(b)).copy(minimum=0,maximum=1)),false,false)?.value==c,"scry chooses second bottom card with one-UUID transport bounds")
    val premature=CardChoicePlan.create(at(pick(scryMessage,1,listOf(a,b,c),emptyList())),listOf(b,c),listOf(a))!!
    premature.next(at(pick(scryMessage,1,listOf(a,b,c),emptyList())),false,false)
    val bottomMessage="Choose card order to put on bottom; last one chosen will be bottommost"
    verify(premature.next(at(pick(bottomMessage,2,listOf(b,c))),false,false)==null && premature.stopped,"same-candidate ordering cannot precede acknowledged selection and Done")
    verify(scry.next(at(pick(scryMessage.replace("0 of 3","2 of 3"),3,listOf(a),listOf(b,c)).copy(minimum=0,maximum=1)),false,false)?.type=="boolean","scry confirms bottom subset with one-UUID transport bounds")
    verify(scry.next(at(pick(bottomMessage,4,listOf(b,c))),false,false)?.value==b,"bottom order sends first card and leaves last to XMage")
    val topMessage="Choose card order to put on top; last one chosen will be topmost"
    verify(CardChoicePlan.supportsDraft(pick(topMessage,10,listOf(a,b,c))),"ordering supports draft")
    verify(scry.next(at(pick(topMessage,5,listOf(a))),false,false)==null && scry.finished,"one top card is auto-placed without a response")
    val skippedBottom=CardChoicePlan.create(at(pick(scryMessage,1,listOf(a,b,c),emptyList())),listOf(b,c),listOf(a))!!
    skippedBottom.next(at(pick(scryMessage,1,listOf(a,b,c),emptyList())),false,false)
    skippedBottom.next(at(pick(scryMessage.replace("0 of 3","1 of 3"),2,listOf(a,c),listOf(b))),false,false)
    skippedBottom.next(at(pick(scryMessage.replace("0 of 3","2 of 3"),3,listOf(a),listOf(b,c))),false,false)
    verify(skippedBottom.next(at(pick(topMessage,4,listOf(a))),false,false)==null && skippedBottom.stopped,"top order cannot skip multi-card bottom order")
    val topOnly=CardChoicePlan.create(at(pick(topMessage,10,listOf(a,b,c))),listOf(a,b,c))!!
    verify(topOnly.next(at(pick(topMessage,10,listOf(a,b,c))),false,false)?.value==c,"top order reverses desired top-first")
    verify(topOnly.next(at(pick(topMessage,11,listOf(a,b))),false,false)?.value==b && !topOnly.finished,"top order sends N minus one but waits for final outcome")
    verify(topOnly.next(at(pick(topMessage,12,listOf(a))),false,true)==null && topOnly.stopped && !topOnly.finished,"rejected final ordering answer stops draft")
    val replayed=CardChoicePlan.create(at(pick(topMessage,10,listOf(a,b,c))),listOf(a,b,c))!!
    replayed.next(at(pick(topMessage,10,listOf(a,b,c))),false,false)
    replayed.next(at(pick(topMessage,11,listOf(a,b))),false,false)
    verify(replayed.next(at(pick(topMessage,12,listOf(a)).copy(id="prompt-11")),false,false)==null && replayed.stopped && !replayed.finished,"reopened final prompt is not mistaken for acceptance")
    val orderContext=CardChoicePlan.create(at(pick(topMessage,10,listOf(a,b,c))),listOf(a,b,c))!!
    orderContext.next(at(pick(topMessage,10,listOf(a,b,c))),false,false)
    verify(orderContext.next(at(pick("Choose card order to put on top for another effect; last one chosen will be topmost",11,listOf(a,b))),false,false)==null && orderContext.stopped,"changed ordering context pauses draft")
    val uncertain=CardChoicePlan.create(at(pick(selectMessage,1,listOf(a,b),emptyList())),listOf(a))!!
    verify(uncertain.next(at(pick(selectMessage,1,listOf(a,b),emptyList())),true,false)==null && !uncertain.stopped,"own pending command waits")
    verify(uncertain.next(at(pick(selectMessage,1,listOf(a,b),emptyList())),false,true)==null && uncertain.stopped,"failed delivery stops without retry")
    fun atTurn(prompt:Decision,turn:Long)=at(prompt).copy(snapshot=mapOf("enginePlayerId" to a,"gameView" to mapOf("turn" to turn,"activePlayerId" to b)))
    val turnBound=CardChoicePlan.create(atTurn(pick(selectMessage,1,listOf(a,b),emptyList()),4),listOf(a))!!
    verify(turnBound.next(atTurn(pick(selectMessage,2,listOf(a,b),emptyList()),5),false,false)==null && turnBound.stopped,"next-turn matching prompt cannot continue old draft")
    val attacker=UUID.randomUUID().toString()
    val attackerCard=mapOf("id" to attacker,"name" to "Declared attacker")
    val attackView=mapOf("activePlayerId" to id,"players" to listOf(mapOf("playerId" to id,"battlefield" to mapOf(attacker to attackerCard))),"combat" to listOf(mapOf("attackers" to mapOf(attacker to attackerCard))))
    val attackPrompt=d.copy(kind="SELECT",responseTypes=setOf("uuid","boolean"),payload=mapOf("selectMode" to "attackers","options" to mapOf("possibleAttackers" to emptyList<String>())))
    verify(Decisions.choices(attackPrompt,mapOf("enginePlayerId" to id,"gameView" to attackView)).any{it.value==attacker},"declared attacker remains available to deselect")
    verify(Decisions.choices(attackPrompt,mapOf("enginePlayerId" to opponent,"gameView" to attackView)).none{it.value==attacker},"opponent attacker cannot be deselected without control")
    verify(Decisions.choices(attackPrompt,mapOf("enginePlayerId" to opponent,"gameView" to attackView,"controlledPlayerViews" to mapOf(id to mapOf("myPlayerId" to id,"activePlayerId" to id)))).any{it.value==attacker},"explicitly authorized controlled-turn attacker can be deselected")
    val manaPrompt=d.copy(kind="PLAY_MANA",responseTypes=setOf("uuid"),payload=emptyMap())
    val manaSnapshot=mapOf("gameView" to mapOf("canPlayObjects" to mapOf("objects" to mapOf(attacker to mapOf("basicManaAbilities" to listOf(mapOf("value" to "Add white mana")))))))
    verify(Decisions.choices(manaPrompt,manaSnapshot)==listOf(Choice("Add white mana","uuid",attacker)),"legacy basic mana family remains playable during payment")
    val secret=mapOf("name" to "Secret name","faceDown" to true,"rules" to listOf("Secret rules"),"power" to "8","toughness" to "8")
    verify(!GameplayPresentation.details(secret).contains("Secret") && !GameplayPresentation.status(secret).contains("8"),"face-down card details do not reconstruct secret text or stats")
    val plain:Obj=mapOf("name" to "Plains","cardTypes" to listOf("LAND"),"power" to "0","toughness" to "0")
    verify(GameplayPresentation.status(plain).isEmpty(),"noncreature Plains must not display projected 0/0")
    verify(GameplayPresentation.status(plain+mapOf("cardTypes" to listOf("CREATURE","LAND")))=="0/0","real creature land keeps live 0/0")
    val walkerWithLoyalty:Obj=plain+mapOf("cardTypes" to listOf("PLANESWALKER"),"counters" to listOf(mapOf("name" to "loyalty","count" to 3)))
    verify(GameplayPresentation.status(walkerWithLoyalty)=="3 loyalty","planeswalker loyalty remains visible without fake 0/0")
    verify(GameplayPresentation.status(plain+mapOf("faceDown" to true)).isEmpty(),"hidden land stats remain redacted")
    verify(GameplayPresentation.cards(mapOf(attacker to attackerCard))==GameplayPresentation.cards(listOf(attackerCard)),"card collections accept engine map and array shapes")
    fun permanent(name:String,vararg types:String,rules:List<String> = emptyList()):Obj=mapOf("id" to name,"cardTypes" to types.toList(),"rules" to rules)
    val landA=permanent("land-a","LAND");val landB=permanent("land-b","LAND");val landC=permanent("land-c","LAND")
    val fighter=permanent("mana-creature","CREATURE",rules=listOf("{T}: Add {G}."))
    val artifactFighter=permanent("artifact-creature","ARTIFACT","CREATURE",rules=listOf("Add {C}."))
    val rock=permanent("rock","ARTIFACT",rules=listOf("{T}: Add {C}."))
    val enchantment=permanent("support","ENCHANTMENT")
    val battlefield=listOf(landA,fighter,rock,landB,artifactFighter,enchantment,landC)
    val rows=BattlefieldLayout.rows(battlefield,true)
    verify(rows.front==listOf(fighter,artifactFighter) && rows.rocks==listOf(rock),"mana and artifact creatures remain in combat; only noncreature mana rocks separate")
    verify(rows.landsTop==listOf(landA,landB,landC)&&rows.landsBottom.isEmpty()&&rows.support==listOf(enchantment),"rocks keep a single stable land row")
    val signet=permanent("signet","ARTIFACT",rules=listOf("{1}, {T}: Add {U}{B}."))
    val treasure=permanent("treasure","ARTIFACT",rules=listOf("{T}, Sacrifice this artifact: Add one mana of any color."))
    val altar=permanent("altar","ARTIFACT",rules=listOf("Sacrifice a creature: Add {C}{C}."))
    val triggered=permanent("triggered","ARTIFACT",rules=listOf("Whenever a creature dies: Add {C}."))
    val equipment:Obj=mapOf("id" to "equipment","cardTypes" to listOf("ARTIFACT"),"subTypes" to listOf("EQUIPMENT"))
    val resources=BattlefieldLayout.rows(listOf(signet,treasure,altar,triggered,fighter,equipment),true)
    verify(resources.rocks==listOf(signet,treasure,altar)&&resources.support==listOf(triggered),"activated tap and sacrifice mana rocks group without triggered add text")
    verify(resources.front==listOf(fighter,equipment),"mana creatures and equipment retain foreground priority")
    val noRocks=BattlefieldLayout.rows(battlefield-rock,true)
    verify(noRocks.landsTop==listOf(landA,landC)&&noRocks.landsBottom==listOf(landB),"landscape land rows retain relative order without rocks")
    val portrait=BattlefieldLayout.rows(battlefield,false)
    verify(portrait.landsTop==listOf(landA,landB,landC)&&portrait.landsBottom.isEmpty(),"portrait keeps lands together")
    val walker=permanent("walker","PLANESWALKER");val battle=permanent("battle","BATTLE")
    val foreground=BattlefieldLayout.rows(listOf(enchantment,walker,battle,equipment),false)
    verify(foreground.front==listOf(walker,battle,equipment)&&foreground.support==listOf(enchantment),"combat types, planeswalkers, battles and equipment stay foreground")
    val tapped=BattlefieldLayout.rows(listOf(landA,landB+("tapped" to true),landC),true)
    verify(tapped.landsTop.map{it["id"]}==noRocks.landsTop.map{it["id"]}&&tapped.landsBottom.map{it["id"]}==noRocks.landsBottom.map{it["id"]},"tapping does not reshuffle alternating land rows")
    verify(GameplayPresentation.printedCost(secret+mapOf("manaCostLeftStr" to listOf("W")))==null,"face-down printed costs stay hidden")
    verify(GameplayPresentation.status(secret+("phasedIn" to false))=="Phased out","phasing status does not reveal face-down identity or stats")
    val phasedTarget=target.copy(payload=mapOf("cards" to listOf(mapOf("id" to id,"phasedIn" to false)),"candidates" to listOf(id)))
    verify(Decisions.choices(phasedTarget,null).any{it.value==id},"explicit engine-authorized object choices are not filtered by visual phasing state")
    verify(GameplayPresentation.printedCost(mapOf("manaCostLeftStr" to listOf("2","W"),"manaCostRightStr" to listOf("U/R")))=="{2}{W} // {U/R}","split costs preserve faces and symbols")
    val mode=d.copy(kind="CHOOSE_MODE",responseTypes=setOf("uuid"),payload=mapOf("choices" to mapOf("invalid-mode" to "Bad",id to "Valid")))
    verify(Decisions.choices(mode,null)==listOf(Choice("Valid","uuid",id)),"mode controls only present valid engine UUID responses")
    val alias=UUID.randomUUID().toString()
    val faceCard=mapOf("id" to id,"name" to "Front face","secondCardFace" to mapOf("id" to alias,"name" to "Back face"))
    val facePrompt=target.copy(payload=mapOf("cards" to listOf(faceCard),"candidates" to listOf(id),"responseAliases" to mapOf(alias to id)))
    verify(Decisions.choices(facePrompt,null).first{it.value==alias}.label=="Choose alternate face: Back face","alternate face response uses the matching authorized face label")
    val hiddenFacePrompt=facePrompt.copy(payload=facePrompt.payload+("cards" to listOf(faceCard+("hideInfo" to true))))
    verify(Decisions.choices(hiddenFacePrompt,null).none{it.label.contains("Back face") || it.label.contains("Front face")},"redacted base does not expose nested face names")
    val allocation=d.copy(kind="MULTI_AMOUNT",responseTypes=setOf("integers"),payload=mapOf("allocations" to listOf(mapOf("message" to "Target", "min" to 0,"max" to 3,"defaultValue" to 1))))
    verify(PromptPresentation.allocationRows(allocation).size==1,"allocation rows validate before presentation")
    rejects("malformed allocation row does not reach UI"){PromptPresentation.allocationRows(allocation.copy(payload=mapOf("allocations" to listOf("invalid"))))}
    rejects("reversed allocation bounds do not reach UI"){PromptPresentation.allocationRows(allocation.copy(payload=mapOf("allocations" to listOf(mapOf("message" to "Target","min" to 3,"max" to 0)))))}
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
