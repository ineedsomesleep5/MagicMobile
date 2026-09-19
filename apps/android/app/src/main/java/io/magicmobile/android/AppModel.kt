package io.magicmobile.android

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import io.magicmobile.android.core.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

data class ValidationIssue(val type:String,val message:String,val group:String?=null,val cardName:String?=null)
data class DeckValidation(val valid:Boolean,val summary:String,val issues:List<ValidationIssue>,val request:String,val upstream:String,val catalogueHash:String,val appBuild:String,val checkedAt:Long=System.currentTimeMillis())
data class ScreenState(val loaded: Boolean=false,val decks: List<SavedDeck> = emptyList(),val precons: List<Deck> = emptyList(),
    val recovered: Deck?=null,val error: String?=null,val busy: Boolean=false,val game: GamePoll?=null,val playing: Boolean=false,
    val pendingAnswer: Boolean=false,val closing: Boolean=false,val paused: Boolean=false,val validation:DeckValidation?=null,
    val playtests:List<RecordedPlaytest> = emptyList(),val recordingEnabled:Boolean=false,
    val autoPassing:Boolean=false,val autoPassStatus:String="",val status: String="Loading local catalogue…")
class AppModel(application: Application): AndroidViewModel(application) {
    private val executor=Executors.newSingleThreadScheduledExecutor { runnable -> Thread(runnable,"MagicMobileEngine").apply { isDaemon=true } }
    private val mutable=MutableStateFlow(ScreenState()); val state=mutable.asStateFlow()
    val store=DeckStore(application)
    private val playtestStore=PlaytestStore(application)
    @Volatile var catalogue: Catalogue? = null; private set
    private var token=0L
    @Volatile private var session: PollState?=null
    private val visibility=AtomicLong(0)
    private val validationEpoch=AtomicLong(0)
    private val autoPassEpoch=AtomicLong(0)
    private val autoPassPolicy=AutoYieldPolicy()
    @Volatile private var foreground=true
    private var shuttingDown=false
    private var recordingId:String?=null
    init {
        executor.execute { attempt {
            catalogue=Catalogue(application.assets.open("catalogue.jsonl"))
            val precons=Wire.decode(application.assets.open("precons.json").use { it.readBytes() }).array("decks").map { Deck.decode(Wire.objectValue(it)) }
            val history=runCatching {
                playtestStore.all().filter { it.end=="in_progress" }.forEach { playtestStore.finish(it.id,"interrupted") }
                playtestStore.all()
            }
            if(history.isFailure)playtestStore.enabled=false
            val saved=store.all(); val recovery=store.recover()
            mutable.update { it.copy(loaded=true,decks=saved,precons=precons,recovered=recovery,playtests=history.getOrDefault(emptyList()),recordingEnabled=playtestStore.enabled,error=history.exceptionOrNull()?.let {"Private playtest history could not be opened. Recording is off; your decks are available. ${it.message}"},status=if(BuildConfig.NATIVE_ENGINE) "Local XMage ready to start" else "Diagnostic build — engine NOT packaged") }
        } }
        // ScheduledExecutorService cancels a periodic task for good if it ever throws, and
        // the guard below runs outside poll()'s own error handling. A single escaped
        // throwable would silently stop every future refresh and the game would look
        // frozen while the engine kept running, so nothing may escape this Runnable.
        executor.scheduleWithFixedDelay({
            try {
                val active = session
                if(foreground && !shuttingDown && active != null && !active.terminal) {
                    poll()
                    autoPassTick()
                }
            } catch(e: Throwable) {
                if(e is VirtualMachineError) throw e
                android.util.Log.w("MagicMobilePoll", "Poll tick failed; polling continues", e)
            }
        },350,350,TimeUnit.MILLISECONDS)
    }
    private fun native(op: String,vararg fields: Pair<String,Any?>): Obj = Wire.result(NativeBridge.request(token,Wire.request(op,*fields)))
    private fun attempt(block:()->Unit) { try { block() } catch(e:Throwable) {
        if(e is VirtualMachineError) throw e
        mutable.update { it.copy(busy=false,error=(e.message ?: e.javaClass.simpleName).take(2000)) }
    } }
    fun error(text:String?) { mutable.update { it.copy(error=text) } }
    fun canAutoPass(mode:AutoYieldPolicy.Mode):Boolean {
        val current=state.value
        if(current.busy || current.pendingAnswer || current.closing || current.error!=null || current.autoPassing)return false
        val context=current.game?.let {AutoYieldPolicy.Context.fromPoll(it,foreground)} ?: return false
        return AutoYieldPolicy.canStart(context,mode)
    }
    fun startAutoPass(mode:AutoYieldPolicy.Mode) {
        if(!canAutoPass(mode))return
        val epoch=autoPassEpoch.incrementAndGet()
        executor.execute {
            if(epoch!=autoPassEpoch.get() || !canAutoPass(mode))return@execute
            val context=state.value.game?.let {AutoYieldPolicy.Context.fromPoll(it,foreground)} ?: return@execute
            if(autoPassPolicy.start(context,android.os.SystemClock.elapsedRealtime(),mode))
                mutable.update {it.copy(autoPassing=true,autoPassStatus=mode.status)}
        }
    }
    fun stopAutoPass(reason:String="Auto-pass stopped. A pass already sent may still finish.") {
        autoPassEpoch.incrementAndGet()
        mutable.update {it.copy(autoPassing=false,autoPassStatus=reason)}
        executor.execute {autoPassPolicy.stop()}
    }
    private fun autoPassTick() {
        val epoch=autoPassEpoch.get()
        val current=state.value
        if(!current.autoPassing)return
        if(!foreground || current.error!=null || current.pendingAnswer || current.closing){stopAutoPass("Auto-pass stopped. Review the current game state.");return}
        if(current.busy)return
        val context=current.game?.let {AutoYieldPolicy.Context.fromPoll(it,foreground)}
        if(context==null){stopAutoPass("Auto-pass stopped. Pass priority manually.");return}
        when(val step=autoPassPolicy.evaluate(context,android.os.SystemClock.elapsedRealtime())) {
            AutoYieldPolicy.Step.Wait->Unit
            is AutoYieldPolicy.Step.Stop->stopAutoPass(step.reason.message)
            is AutoYieldPolicy.Step.Pass->{
                val active=session ?: return
                if(epoch!=autoPassEpoch.get() || !state.value.autoPassing || !foreground ||
                    active.current?.decision?.let {it.id==step.prompt.id && it.revision==step.prompt.revision}!=true)return
                autoPassPolicy.recordPass(step.prompt)
                try {
                    val command=active.prepare("boolean",true)
                    mutable.update {it.copy(busy=true)}
                    // send() refreshes the state but never recursively runs this policy.
                    send(active,command)
                }catch(e:Exception){stopAutoPass("Auto-pass stopped. Review the current game state.");error(e.message);mutable.update {it.copy(busy=false)}}
            }
        }
    }
    fun save(deck:Deck,record:SavedDeck?,onFailure:()->Unit={},done:(SavedDeck)->Unit) {
        if(state.value.busy){onFailure();return}
        mutable.update {it.copy(busy=true,error=null)}
        validationEpoch.incrementAndGet()
        executor.execute { try {
            val result=store.save(deck,record)
            val recovery=runCatching {store.clearDraft()}
            val decks=runCatching {store.all()}.getOrElse {(state.value.decks.filterNot {it.id==result.id}+result)}
            mutable.update {it.copy(busy=false,decks=decks,recovered=if(recovery.isSuccess)null else it.recovered,validation=null,error=recovery.exceptionOrNull()?.let {"Deck saved, but its recovery copy could not be cleared."})}
            done(result)
        } catch(e:Exception) {
            mutable.update {it.copy(busy=false,error=(e.message ?: "Unable to save deck").take(2000))}
            onFailure()
        } }
    }
    fun organize(record:SavedDeck,favorite:Boolean,tags:List<String>,notes:String){executor.execute {attempt {store.organize(record,favorite,tags,notes);mutable.update {it.copy(decks=store.all())}}}}
    fun duplicate(record:SavedDeck){executor.execute {attempt {
        // Read optional provenance before creating a copy, so unreadable evidence
        // cannot silently disappear or leave the player retrying duplicate copies.
        val receipts=ReceiptStore(getApplication());val receipt=receipts.read(record.id)
        val result=store.duplicate(record)
        val copied=runCatching {if(receipt!=null)receipts.write(result.id,receipt)}
        mutable.update {it.copy(decks=store.all(),error=copied.exceptionOrNull()?.let {"Deck copied, but its source receipt could not be copied. The original receipt is preserved."})}
    }}}
    fun recover(deck:Deck) { executor.execute { attempt { store.keepDraft(deck);mutable.update { it.copy(recovered=deck) } } } }
    fun discardRecovery() { executor.execute { attempt { store.clearDraft();mutable.update { it.copy(recovered=null) } } } }
    fun delete(record:SavedDeck) { executor.execute { attempt {
        store.delete(record)
        val cleanup=runCatching {ReceiptStore(getApplication()).delete(record.id);DeckDraftStore(getApplication()).delete(record.id)}
        mutable.update { it.copy(decks=store.all(),error=cleanup.exceptionOrNull()?.let {"Deck deleted, but its local draft or receipt could not be removed."}) }
    } } }
    fun setRecording(enabled:Boolean){executor.execute {attempt {if(!enabled){playtestStore.finish(recordingId,"interrupted");recordingId=null};playtestStore.enabled=enabled;mutable.update {it.copy(recordingEnabled=enabled,playtests=playtestStore.all())}}}}
    fun clearPlaytests(){executor.execute {attempt {playtestStore.clear();mutable.update {it.copy(playtests=emptyList())}}}}
    fun invalidateValidation(){validationEpoch.incrementAndGet();mutable.update {it.copy(validation=null)}}
    fun validationApplies(deck:Deck,excludeOtherBoards:Boolean):Boolean {
        val catalogue=catalogue ?: return false
        val request=runCatching {String(Wire.encode(catalogue.resolve(deck,excludeOtherBoards)),Charsets.UTF_8)}.getOrNull() ?: return false
        val receipt=state.value.validation ?: return false
        return receipt.request==request && receipt.upstream==catalogue.upstreamCommit && receipt.catalogueHash==catalogue.registryHash && receipt.appBuild==BuildConfig.VERSION_NAME
    }
    fun validationMatches(deck:Deck,excludeOtherBoards:Boolean)=validationApplies(deck,excludeOtherBoards)&&state.value.validation?.valid==true
    fun validate(deck:Deck,excludeOtherBoards:Boolean){
        if(state.value.busy || state.value.playing)return
        val epoch=validationEpoch.incrementAndGet()
        mutable.update {it.copy(busy=true,error=null,validation=null,status="Checking with the installed XMage Commander validator…")}
        executor.execute {attempt {
            require(BuildConfig.NATIVE_ENGINE){"Install the native APK to validate with XMage."}
            check(token==0L && session==null);val catalogue=checkNotNull(catalogue);val resolved=catalogue.resolve(deck,excludeOtherBoards)
            val request=String(Wire.encode(resolved),Charsets.UTF_8)
            token=NativeBridge.open();check(token!=0L)
            var result:DeckValidation?=null
            var failure:Throwable?=null
            try {
                result=try {
                    val report=native("validateDeck","deck" to resolved)
                    require(report.flag("valid") && report.text("validator")=="Commander" && report.array("issues").isEmpty() && report.text("upstream")==catalogue.upstreamCommit && report.text("catalogueHash")==catalogue.registryHash) {"XMage returned an unrecognized validation result. The draft is unchanged and has not been marked legal."}
                    DeckValidation(true,"Passed the installed XMage Commander validator",emptyList(),request,catalogue.upstreamCommit,catalogue.registryHash,BuildConfig.VERSION_NAME)
                } catch(e:EngineFault) {
                    if(e.code!="invalid_deck")throw e
                    val details=e.details.orEmpty();require(details.text("validator")=="Commander") {"XMage returned an unrecognized validation result. The draft is unchanged and has not been marked legal."}
                    val rawIssues=details.array("issues");require(rawIssues.isNotEmpty() && rawIssues.size<=2000)
                    val issues=rawIssues.map {raw->val row=Wire.objectValue(raw);val type=Wire.string(row["type"]);val message=Wire.string(row["message"]);require(type.toByteArray().size<=128 && message.toByteArray().size<=16_384);ValidationIssue(type,message,row.text("group")?.also {require(it.toByteArray().size<=2048)},row.text("cardName")?.also {require(it.toByteArray().size<=2048)})}
                    DeckValidation(false,e.message ?: "Deck failed validation",issues,request,catalogue.upstreamCommit,catalogue.registryHash,BuildConfig.VERSION_NAME)
                }
            } catch(e:Throwable) {
                failure=e
            } finally {
                val closed=NativeBridge.close(token)
                if(closed==0)token=0L else {
                    shuttingDown=true
                    mutable.update {it.copy(closing=true,status="Validation finished; engine cleanup must be retried")}
                    val cleanup=IllegalStateException("Validation completed, but engine cleanup returned status $closed. Retry cleanup before validating or playing.")
                    if(failure==null)failure=cleanup else failure?.addSuppressed(cleanup)
                }
            }
            failure?.let {throw it}
            val validation=checkNotNull(result)
            mutable.update {if(validationEpoch.get()==epoch)it.copy(busy=false,validation=validation,status=if(validation.valid)"Deck is valid for Commander" else "Deck needs changes") else it.copy(busy=false)}
        }}
    }
    fun start(deck:Deck,opponent:Deck,ais:Int,excludeOtherBoards:Boolean,aiSkill:Int,playerName:String) {
        if(state.value.busy || state.value.playing) return
        val humanName=playerName.trim()
        if(humanName.length !in 1..24 || humanName.any(Char::isISOControl)){error("Player name must be 1–24 characters.");return}
        mutable.update { it.copy(busy=true,error=null,status="Validating decks and starting real XMage…") }
        executor.execute { attempt {
            require(BuildConfig.NATIVE_ENGINE) { "This diagnostic APK has no rules engine. Install the native APK; no server fallback is used." }
            check(token==0L && session==null); require(ais in 1..3);require(aiSkill in 1..10)
            val catalogue=checkNotNull(catalogue)
            val human=catalogue.resolve(deck,excludeOtherBoards); val ai=catalogue.resolve(opponent,false)
            require(validationMatches(deck,excludeOtherBoards)) {"Validate this exact playing deck with the installed XMage build before starting."}
            token=NativeBridge.open(); check(token!=0L)
            try {
                val seats=(0..ais).map { index -> if(index==0) mapOf("seatId" to "player-1","name" to humanName, "controller" to "human","deck" to human) else mapOf("seatId" to "player-${index+1}","name" to "AI $index", "controller" to "ai","deck" to ai,"aiSkill" to aiSkill) }
                val created=native("create","configuration" to mapOf("seats" to seats))
                session=PollState(Wire.string(created["matchId"]),"player-1")
                val recording=runCatching {playtestStore.start(deck,Wire.string(created["matchId"]),ais,aiSkill,created.obj("engine").orEmpty(),catalogue,BuildConfig.VERSION_NAME)}
                recordingId=recording.getOrNull()?.id
                if(recording.isFailure)playtestStore.enabled=false
                mutable.update { it.copy(busy=false,playing=true,game=null,recordingEnabled=playtestStore.enabled,error=recording.exceptionOrNull()?.let {failure->"Game started, but private summary recording was turned off: ${failure.message ?: failure.javaClass.simpleName}"},status="Waiting for XMage…",closing=false) }; poll()
            } catch(e:Throwable) {
                val result=NativeBridge.close(token)
                if(result==0)token=0L else { shuttingDown=true;mutable.update { it.copy(playing=true,closing=true,status="Startup failed; cleanup must be retried") } }
                throw e
            }
        } }
    }
    private fun poll() { attempt {
        val s=session ?: return@attempt; if(token==0L || shuttingDown) return@attempt
        val epoch=visibility.get()
        val raw=native("poll","matchId" to s.match,"viewerId" to s.viewer,"after" to (s.current?.revision ?: 0L))
        val parsed=GamePoll.parse(raw,s.match,s.viewer)
        if(epoch!=visibility.get() || !foreground) return@attempt
        if(s.publish(parsed)) {
            if(parsed.phase in setOf("ended","failed","closed") && state.value.autoPassing)stopAutoPass("Auto-pass stopped. The game has ended.")
            val recording=runCatching {playtestStore.observe(recordingId,parsed)}
            if(recording.isFailure){recordingId=null;playtestStore.enabled=false}
            val history=runCatching {playtestStore.all()}.getOrDefault(state.value.playtests)
            mutable.update { it.copy(game=s.current,pendingAnswer=s.pending!=null,playtests=history,recordingEnabled=playtestStore.enabled,error=recording.exceptionOrNull()?.let {failure->"Playtest summary recording was turned off: ${failure.message ?: failure.javaClass.simpleName}"} ?: it.error,status=when(parsed.phase) {
            "failed"->"Engine reported a failed game";"ended"->"Game ended";"closed"->"Game closed";else->"Live · ${parsed.phase}" }) }
        }
    } }
    fun answer(type:String,value:Any?) {
        if(state.value.busy || state.value.pendingAnswer || state.value.closing || !foreground) return
        if(state.value.autoPassing)stopAutoPass()
        mutable.update { it.copy(busy=true,error=null) }
        executor.execute { attempt { val s=checkNotNull(session);check(!shuttingDown && foreground);val command=s.prepare(type,value);send(s,command) } }
    }
    private fun send(s:PollState,command:Obj) {
        try { native("respond","matchId" to s.match,"viewerId" to s.viewer,"command" to command);s.acknowledged();mutable.update { it.copy(busy=false,pendingAnswer=false) };poll() }
        catch(e:EngineFault) {
            if(e.code in setOf("invalid_response","stale_prompt","invalid_request","wrong_actor","match_closed"))s.rejected()
            mutable.update { it.copy(busy=false,pendingAnswer=s.pending!=null,error=e.message) }
        } catch(e:Exception) { mutable.update { it.copy(busy=false,pendingAnswer=true,error="Response delivery is uncertain. Retry uses the exact same request, not a new action.") } }
    }
    fun retry() { executor.execute { attempt { val s=session ?: return@attempt;val command=s.pending ?: return@attempt;check(!shuttingDown && foreground);send(s,command) } } }
    fun refresh() { executor.execute { poll() } }
    fun close() {
        stopAutoPass()
        visibility.incrementAndGet();mutable.update { it.copy(closing=true,busy=true,status="Closing engine…") }
        executor.execute { shuttingDown=true;attempt {
            val result=if(token!=0L) NativeBridge.close(token) else 0
            if(result!=0) { mutable.update { it.copy(busy=false,error="Engine cleanup is still busy (status $result). Tap Retry cleanup; the runtime remains owned.") };return@attempt }
            token=0;session=null;shuttingDown=false
            val recording=runCatching { playtestStore.finish(recordingId,"left") };recordingId=null
            val history=runCatching { playtestStore.all() }.getOrDefault(state.value.playtests)
            mutable.update { it.copy(busy=false,playing=false,closing=false,game=null,pendingAnswer=false,playtests=history,error=recording.exceptionOrNull()?.let {"Game closed, but its private summary could not be saved: ${it.message}"},status="Local engine closed") }
        } }
    }
    fun foreground(active:Boolean) { foreground=active;visibility.incrementAndGet();if(!active&&state.value.autoPassing)stopAutoPass("Auto-pass stopped while the app was in the background.");mutable.update { it.copy(paused=!active) };if(active)refresh() }
    fun diagnostics(done:(String)->Unit) { executor.execute { attempt { check(token!=0L); done(io.magicmobile.core.Json.write(native("diagnostics"))) } } }
    override fun onCleared() { foreground=false;executor.execute {
        // Optional history must never prevent releasing the native runtime.
        try { playtestStore.finish(recordingId,"interrupted") }
        finally { if(token!=0L) runCatching { NativeBridge.close(token) } }
    };executor.shutdown();super.onCleared() }
}
