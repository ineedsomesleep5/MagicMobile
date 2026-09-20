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
