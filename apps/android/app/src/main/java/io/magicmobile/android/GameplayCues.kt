package io.magicmobile.android

import io.magicmobile.android.core.*
import java.util.Locale

/** The transport viewer is a seat ID; game actions use the validated engine player UUID. */
internal fun gameplayViewerId(poll:GamePoll?):String? {
    val snapshot=poll?.snapshot ?: return null
    val player=snapshot.text("enginePlayerId") ?: return null
    return player.takeIf{Wire.uuid(it) && snapshot.obj("gameView")?.text("myPlayerId")==it}
}

/** Only the engine's current, viewer-authorized priority choices can light command zones. */
internal fun castableCommanderIds(decision:Decision?,snapshot:Obj?,viewer:String?):Set<String> {
    if(decision==null || decision.submitted || decision.kind!="SELECT" || decision.payload.text("selectMode")!="priority" || viewer==null)return emptySet()
    if(decision.payload.text("manaPlayerId")!=viewer)return emptySet()
    val game=snapshot?.obj("gameView") ?: return emptySet()
    val player=game.array("players").map(Wire::objectValue).find{it.text("playerId")==viewer} ?: return emptySet()
    val allowed=Decisions.choices(decision,snapshot).filter{it.type=="uuid"}.map{it.value}.toSet()
    val playable=game.obj("canPlayObjects")?.obj("objects").orEmpty()
    return GameplayPresentation.cards(player["commandList"]).mapNotNull{it.text("id")}.filter{id->
        id in allowed && playable.obj(id)?.array("basicCastAbilities")?.isNotEmpty()==true
    }.toSet()
}

internal fun floatingManaChoice(choices:List<Choice>,playerId:String?,color:String):Choice? =
    choices.firstOrNull{it.type=="mana" && (it.value as? Map<*,*>)?.let{value->value["playerId"]==playerId && value["manaType"]==color.uppercase(Locale.ROOT)}==true}

/** Only relationships explicitly supplied by the viewer's engine projection are grouped. */
internal fun battlefieldAttachmentRoot(card:Obj,all:List<Obj>,playerIds:Set<String> = emptySet()):String? {
    val id=card.text("id") ?: return null
    val byId=all.mapNotNull{value->value.text("id")?.let{it to value}}.toMap()
    val seen=mutableSetOf(id)
    var current=card
    while(true){
        val host=current.text("attachedTo") ?: return current.text("id")?.takeIf{it!=id}
        if(!seen.add(host))return null
        if(host in playerIds)return host
        current=byId[host] ?: return null
    }
}

internal fun isPhasedOut(card:Obj)=card["phasedIn"]==false

internal fun publicPlayerBadges(player:Obj):List<String> = buildList {
    player.array("counters").map(Wire::objectValue).forEach{counter->
        val name=counter.text("name")?.let(Decisions::plain)?.takeIf(String::isNotBlank)
        val count=counter.number("count")
        if(name!=null&&count!=null&&count!=0L)add("$count $name")
    }
    if(player.flag("monarch"))add("Monarch")
    if(player.flag("initiative"))add("Initiative")
    player.array("designationNames").filterIsInstance<String>().map(Decisions::plain).filter(String::isNotBlank).forEach{if(it !in this)add(it)}
}

internal fun priorityResponseCue(decision:Decision?,game:Obj?,viewer:String?):String? {
    if(viewer==null || decision==null || decision.submitted || decision.kind!="SELECT" ||
        decision.payload.text("selectMode")!="priority" || decision.payload.text("manaPlayerId")!=viewer)return null
    val hasStack=GameplayPresentation.cards(game?.get("stack")).isNotEmpty()
    val mainPhase=listOfNotNull(game?.text("step"),game?.text("phase")).any{
        it.uppercase(Locale.ROOT).filter(Char::isLetterOrDigit) in setOf("PRECOMBATMAIN","POSTCOMBATMAIN","MAIN1","MAIN2")
    }
    if(game?.text("activePlayerId")==viewer && !hasStack && mainPhase)return null
    val step=(game?.text("step") ?: game?.text("phase"))?.replace('_',' ')?.lowercase(Locale.ROOT)?.replaceFirstChar{it.titlecase(Locale.ROOT)} ?: "Priority"
    return (if(hasStack)"Respond to the stack" else "Your response window")+" · $step"
}

internal data class PriorityPassHelp(val text:String,val accessibility:String)

internal fun priorityPassHelp(decision:Decision?,choice:Choice,game:Obj?,viewer:String?):PriorityPassHelp? {
    if(viewer==null || decision==null || decision.submitted || decision.kind!="SELECT" ||
        decision.payload.text("selectMode")!="priority" || decision.payload.text("manaPlayerId")!=viewer ||
        "boolean" !in decision.responseTypes || choice.type!="boolean" || choice.value!=true)return null
    val options=decision.payload.obj("options")
    if(options?.get("possibleAttackers")!=null || options?.get("possibleBlockers")!=null)return null
    val stack=game?.get("stack")
    if(stack !is List<*> && stack !is Map<*,*>)return null
    return if(GameplayPresentation.cards(stack).isNotEmpty())
        PriorityPassHelp("Let others respond","Other players may respond. The top spell or ability resolves only if everyone passes.")
    else PriorityPassHelp("Let this step continue","Other players may respond. The step advances only if everyone passes.")
}
