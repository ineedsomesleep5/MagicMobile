package io.magicmobile.android

import android.content.Context
import android.util.AtomicFile
import io.magicmobile.android.core.*
import java.io.File
import java.util.UUID

data class RecordedPlaytest(
    val id: String,
    val matchId: String,
    val deckName: String,
    val deck: DeckSignature?,
    val commanderNames: List<String>,
    val aiOpponents: Int,
    val aiSkill: Int,
    val upstream: String,
    val catalogueHash: String,
    val appBuild: String,
    val startedAt: Long,
    val observedAt: Long,
    val finishedAt: Long?,
    val highestTurn: Int,
    val commanderCasts: Map<String, Int>,
    val end: String,
    val won: Boolean?,
    val lastRevision: Long,
    val viewerPlayerId: String?,
)

/** Bounded, device-only summaries. No hands, opponent decks, actions or snapshots are stored. */
class PlaytestStore(context: Context) {
    private val prefs=context.getSharedPreferences("magicmobile.playtests",Context.MODE_PRIVATE)
    private val file=AtomicFile(File(context.noBackupFilesDir,"playtests-v1.json"))
    var enabled: Boolean
        @Synchronized get()=prefs.getBoolean("enabled",false)
        @Synchronized set(value){prefs.edit().putBoolean("enabled",value).apply()}

    @Synchronized fun all(): List<RecordedPlaytest> = read().sortedByDescending { it.startedAt }

    @Synchronized fun start(deck: Deck,matchId:String,aiOpponents:Int,aiSkill:Int,engine:Obj,catalogue:Catalogue,appBuild:String): RecordedPlaytest? {
        if(!enabled)return null
        require(Wire.uuid(matchId) && aiOpponents in 1..3 && aiSkill in 1..10)
        require(engine.text("engine")=="xmage" && engine.text("execution")=="native-aot" && engine.text("upstream")==catalogue.upstreamCommit && engine.text("catalogueHash")==catalogue.registryHash)
        require(appBuild.isNotBlank() && appBuild.toByteArray().size<=128)
        val now=System.currentTimeMillis();val signature=DeckSignature.from(deck,catalogue)
        val row=RecordedPlaytest(UUID.randomUUID().toString(),matchId,boundedTitle(deck.name),signature,
            signature.cards.filter {it.section==PlayingSection.COMMANDERS}.map {it.name}.distinct().take(4),
            aiOpponents,aiSkill,catalogue.upstreamCommit,catalogue.registryHash,appBuild,
            now,now,null,0,emptyMap(),"in_progress",null,-1,null).validated()
        replace(row);return row
    }

    @Synchronized fun observe(id:String?,poll:GamePoll) {
        if(id==null)return
        val current=read().firstOrNull { it.id==id } ?: return
        if(current.end!="in_progress" || poll.matchId!=current.matchId || poll.revision<=current.lastRevision)return
        val now=System.currentTimeMillis();val root=poll.snapshot
        val view=root?.obj("gameView");val turn=view?.number("turn")?.takeIf { it in 0..1_000_000 }?.toInt() ?: current.highestTurn
        val viewer=root?.text("enginePlayerId")
        if(viewer!=null && (!Wire.uuid(viewer) || current.viewerPlayerId!=null && current.viewerPlayerId!=viewer))return
        val casts=current.commanderCasts.toMutableMap()
        val commanders=runCatching {root?.obj("commanders")}.getOrNull()
        if(viewer!=null)commanders?.values?.mapNotNull { it as? Map<*,*> }?.forEach { raw ->
            val owner=raw["ownerPlayerId"] as? String;val name=raw["name"] as? String
            val count=runCatching { Wire.integer(raw["castsFromCommandZone"]) }.getOrNull()
            if(owner==viewer && name != null && name in current.commanderNames && count!=null && count in 0..1_000_000) casts[name]=maxOf(casts[name] ?: 0,count.toInt())
        }
        var end=current.end;var won=current.won;var finished:Long?=null
        val outcome=runCatching {root?.obj("outcome")}.getOrNull()
        if(outcome?.flag("ended")==true) {
            end="completed";finished=now
            val winners=runCatching { outcome.array("winnerPlayerIds").map(Wire::string) }.getOrDefault(emptyList())
            won=viewer?.let { if(winners.isEmpty()||winners.any {!Wire.uuid(it)})null else it in winners }
        } else when(poll.phase) {
            "ended"->{end="completed";finished=now}
            "failed"->{end="engine_failed";finished=now}
            "closed"->{end="interrupted";finished=now}
        }
        val observed=maxOf(now,current.observedAt);if(finished!=null)finished=observed
        replace(current.copy(observedAt=observed,finishedAt=finished,highestTurn=maxOf(current.highestTurn,turn),commanderCasts=casts,end=end,won=won,lastRevision=poll.revision,viewerPlayerId=viewer ?: current.viewerPlayerId).validated())
    }

    @Synchronized fun finish(id:String?,end:String) {
        if(id==null)return
        require(end in setOf("left","interrupted"))
        val current=read().firstOrNull { it.id==id } ?: return
        if(current.end=="in_progress") {
            val now=System.currentTimeMillis()
            replace(current.copy(observedAt=maxOf(now,current.observedAt),finishedAt=maxOf(now,current.observedAt),end=end).validated())
        }
    }

    @Synchronized fun clear(){file.delete()}

    private fun replace(value:RecordedPlaytest){
        val rows=(read().filterNot { it.id==value.id }+value.validated()).sortedByDescending { it.startedAt }.take(100)
        val bytes=Wire.encode(mapOf("schema" to 3,"games" to rows.map { it.json() }))
        val output=file.startWrite();try{output.write(bytes);file.finishWrite(output)}catch(e:Exception){file.failWrite(output);throw e}
    }
    private fun read():List<RecordedPlaytest>{
        if(!file.baseFile.exists())return emptyList()
        val root=file.openRead().use { Wire.decode(readBounded(it,Wire.LIMIT)) };val schema=Wire.integer(root["schema"]);require(schema in 1..3)
        return root.array("games").take(100).map { decode(Wire.objectValue(it),schema) }
    }
    private fun RecordedPlaytest.json():Obj=mapOf("id" to id,"matchId" to matchId,"deckName" to deckName,"deck" to deck?.cards?.map {mapOf("name" to it.name,"quantity" to it.quantity,"section" to it.section.name)},"commanderNames" to commanderNames,"aiOpponents" to aiOpponents,"aiSkill" to aiSkill,"upstream" to upstream,"catalogueHash" to catalogueHash,"appBuild" to appBuild,"startedAt" to startedAt,"observedAt" to observedAt,"finishedAt" to finishedAt,"highestTurn" to highestTurn,"commanderCasts" to commanderCasts,"end" to end,"won" to won,"lastRevision" to lastRevision,"viewerPlayerId" to viewerPlayerId)
    private fun decode(o:Obj,schema:Long):RecordedPlaytest {
        val end=Wire.string(o["end"]);require(end in setOf("in_progress","completed","left","interrupted","engine_failed"))
        val casts=o.obj("commanderCasts").orEmpty().mapValues {
            Wire.integer(it.value).also { count->require(count in 0..1_000_000) }.toInt()
        }
        val id=Wire.string(o["id"]);val matchId=Wire.string(o["matchId"]);require(Wire.uuid(id) && Wire.uuid(matchId))
        val opponents=Wire.integer(o["aiOpponents"]);val skill=Wire.integer(o["aiSkill"]);val turn=Wire.integer(o["highestTurn"])
        require(opponents in 1..3 && skill in 1..10 && turn in 0..1_000_000)
        val revision=if(schema>=2L)Wire.integer(o["lastRevision"]) else -1L;require(revision>=-1)
        val viewer=if(schema>=2L)o.text("viewerPlayerId") else null;require(viewer==null||Wire.uuid(viewer))
        val title=Wire.string(o["deckName"])
        val signature=if(schema==3L && o["deck"]!=null) {
            val expected=o.array("deck").map {raw->val card=Wire.objectValue(raw);val quantity=Wire.integer(card["quantity"]);require(quantity in 1..2000);PlayingCard(Wire.string(card["name"]),quantity.toInt(),PlayingSection.valueOf(Wire.string(card["section"]))) }
            DeckSignature.canonical(expected)
        } else null
        return RecordedPlaytest(id,matchId,title,signature,o.array("commanderNames").map(Wire::string),opponents.toInt(),skill.toInt(),o.text("upstream").orEmpty(),o.text("catalogueHash").orEmpty(),if(schema>=2L)Wire.string(o["appBuild"]) else "development",Wire.integer(o["startedAt"]),Wire.integer(o["observedAt"]),o["finishedAt"]?.let(Wire::integer),turn.toInt(),casts,end,o["won"] as? Boolean,revision,viewer).validated()
    }

    private fun RecordedPlaytest.validated():RecordedPlaytest {
        require(Wire.uuid(id)&&Wire.uuid(matchId)&&deckName.toByteArray().size<=512&&commanderNames.size<=12&&commanderNames.distinct().size==commanderNames.size)
        require(aiOpponents in 1..3&&aiSkill in 1..10&&upstream.isNotBlank()&&upstream.toByteArray().size<=128&&catalogueHash.isNotBlank()&&catalogueHash.toByteArray().size<=256&&appBuild.isNotBlank()&&appBuild.toByteArray().size<=128)
        require(startedAt>=0&&observedAt>=startedAt&&observedAt-startedAt<=365L*24*60*60*1000&&finishedAt?.let {it in startedAt..observedAt}!=false)
        require(highestTurn in 0..1_000_000&&lastRevision>=-1&&viewerPlayerId?.let(Wire::uuid)!=false&&commanderCasts.size<=12&&commanderCasts.all {(name,count)->name in commanderNames&&count in 0..1_000_000})
        require((end=="in_progress")== (finishedAt==null) && (end=="completed"||won==null))
        deck?.let {signature->
            PlaytestSummary(id,matchId,"player-1",signature,deckName,upstream,catalogueHash,appBuild,aiOpponents,startedAt,observedAt,finishedAt,
                PlaytestEnd.valueOf(end.uppercase()),highestTurn,commanderCasts,won,lastRevision,viewerPlayerId)
        }
        return this
    }

    private fun boundedTitle(value:String):String {
        var end=0;var count=0
        while(end<value.length&&count<128){end+=Character.charCount(value.codePointAt(end));count++}
        return value.substring(0,end)
    }
}
