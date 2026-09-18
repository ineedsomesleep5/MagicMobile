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

data class ScreenState(val loaded: Boolean=false,val decks: List<SavedDeck> = emptyList(),val precons: List<Deck> = emptyList(),
    val recovered: Deck?=null,val error: String?=null,val busy: Boolean=false,val game: GamePoll?=null,val playing: Boolean=false,
    val pendingAnswer: Boolean=false,val closing: Boolean=false,val paused: Boolean=false,val status: String="Loading local catalogue…")
class AppModel(application: Application): AndroidViewModel(application) {
    private val executor=Executors.newSingleThreadScheduledExecutor { runnable -> Thread(runnable,"MagicMobileEngine").apply { isDaemon=true } }
    private val mutable=MutableStateFlow(ScreenState()); val state=mutable.asStateFlow()
    val store=DeckStore(application)
    @Volatile var catalogue: Catalogue? = null; private set
    private var token=0L
    @Volatile private var session: PollState?=null
    private val visibility=AtomicLong(0)
    @Volatile private var foreground=true
    private var shuttingDown=false
    init {
        executor.execute { attempt {
            catalogue=Catalogue(application.assets.open("catalogue.jsonl"))
            val precons=Wire.decode(application.assets.open("precons.json").use { it.readBytes() }).array("decks").map { Deck.decode(Wire.objectValue(it)) }
            val saved=store.all(); val recovery=store.recover()
            mutable.update { it.copy(loaded=true,decks=saved,precons=precons,recovered=recovery,status=if(BuildConfig.NATIVE_ENGINE) "Local XMage ready to start" else "Diagnostic build — engine NOT packaged") }
        } }
        // ScheduledExecutorService cancels a periodic task for good if it ever throws, and
        // the guard below runs outside poll()'s own error handling. A single escaped
        // throwable would silently stop every future refresh and the game would look
        // frozen while the engine kept running, so nothing may escape this Runnable.
        executor.scheduleWithFixedDelay({
            try {
                val active = session
                if(foreground && !shuttingDown && active != null && !active.terminal) poll()
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
    fun save(deck:Deck,record:SavedDeck?,done:(SavedDeck)->Unit) { executor.execute { attempt { val result=store.save(deck,record);store.clearDraft();mutable.update { it.copy(decks=store.all(),recovered=null) };done(result) } } }
    fun recover(deck:Deck) { executor.execute { attempt { store.keepDraft(deck);mutable.update { it.copy(recovered=deck) } } } }
    fun discardRecovery() { executor.execute { attempt { store.clearDraft();mutable.update { it.copy(recovered=null) } } } }
    fun delete(record:SavedDeck) { executor.execute { attempt { store.delete(record);mutable.update { it.copy(decks=store.all()) } } } }
    fun start(deck:Deck,opponent:Deck,ais:Int,excludeOtherBoards:Boolean) {
        if(state.value.busy || state.value.playing) return
        mutable.update { it.copy(busy=true,error=null,status="Validating decks and starting real XMage…") }
        executor.execute { attempt {
            require(BuildConfig.NATIVE_ENGINE) { "This diagnostic APK has no rules engine. Install the native APK; no server fallback is used." }
            check(token==0L && session==null); require(ais in 1..3)
            val catalogue=checkNotNull(catalogue)
            val human=catalogue.resolve(deck,excludeOtherBoards); val ai=catalogue.resolve(opponent,false)
            token=NativeBridge.open(); check(token!=0L)
            try {
                val seats=(0..ais).map { index -> mapOf("seatId" to "player-${index+1}","name" to if(index==0)"You" else "AI $index", "controller" to if(index==0)"human" else "ai","deck" to if(index==0) human else ai) }
                val created=native("create","configuration" to mapOf("seats" to seats))
                session=PollState(Wire.string(created["matchId"]),"player-1")
                mutable.update { it.copy(busy=false,playing=true,game=null,status="Waiting for XMage…",closing=false) }; poll()
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
        if(s.publish(parsed)) mutable.update { it.copy(game=s.current,pendingAnswer=s.pending!=null,status=when(parsed.phase) {
            "failed"->"Engine reported a failed game";"ended"->"Game ended";"closed"->"Game closed";else->"Live · ${parsed.phase}" }) }
    } }
    fun answer(type:String,value:Any?) {
        if(state.value.busy || state.value.pendingAnswer || state.value.closing || !foreground) return
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
        visibility.incrementAndGet();mutable.update { it.copy(closing=true,busy=true,status="Closing engine…") }
        executor.execute { shuttingDown=true;attempt {
            val result=if(token!=0L) NativeBridge.close(token) else 0
            if(result!=0) { mutable.update { it.copy(busy=false,error="Engine cleanup is still busy (status $result). Tap Retry cleanup; the runtime remains owned.") };return@attempt }
            token=0;session=null;shuttingDown=false
            mutable.update { it.copy(busy=false,playing=false,closing=false,game=null,pendingAnswer=false,status="Local engine closed") }
        } }
    }
    fun foreground(active:Boolean) { foreground=active;visibility.incrementAndGet();mutable.update { it.copy(paused=!active) };if(active)refresh() }
    fun diagnostics(done:(String)->Unit) { executor.execute { attempt { check(token!=0L); done(io.magicmobile.core.Json.write(native("diagnostics"))) } } }
    override fun onCleared() { foreground=false;executor.execute { if(token!=0L) runCatching { NativeBridge.close(token) } };executor.shutdown();super.onCleared() }
}
