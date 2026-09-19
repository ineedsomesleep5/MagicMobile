package io.magicmobile.android.core

/** Local scheduling of ordinary priority passes. This policy never infers a game
 * action, answers choices, retries a response, or changes engine authority. */
class AutoYieldPolicy {
    enum class Mode(val durationMs:Long,val passLimit:Int,val status:String) {
        SAFE_END_TURN(60_000,64,"Auto-passing routine priority this turn. Stop at any time."),
        END_TURN_SKIPPING_RESPONSES(120_000,256,"Skipping responses this turn, including the stack. Stops for choices or after 120 seconds / 256 passes."),
        UNTIL_MY_TURN(180_000,256,"Skipping responses until your next turn, including the stack. Stops for choices or after 180 seconds / 256 passes.")
    }
    data class Context(
        val matchId:String,val seatId:String,val viewerId:String,val activePlayerId:String?,val turn:Long,
        val phase:String,val localHumanEnabled:Boolean,val foreground:Boolean,val emptyStack:Boolean,
        val selfAuthority:Boolean,val resyncRequired:Boolean,val prompt:Decision?,
    ) {
        companion object {
            /** Missing projection evidence disables scheduling; absence is never authority. */
            fun fromPoll(poll:GamePoll,foreground:Boolean,localHumanEnabled:Boolean=true):Context? = runCatching {
                if(poll.failure!=null)return null
                val root=poll.snapshot ?: return null
                val view=root.obj("gameView") ?: return null
                val viewer=root.text("enginePlayerId") ?: return null
                if(!Wire.uuid(viewer) || view.text("myPlayerId")!=viewer)return null
                val turn=view.number("turn") ?: return null
                val active=view.text("activePlayerId") ?: return null
                if(!Wire.uuid(active))return null
                val stack=view.obj("stack") ?: return null
                val controls=root.obj("controlledPlayerViews") ?: return null
                val owner=view.array("players").map(Wire::objectValue).firstOrNull {it["playerId"]==viewer} ?: return null
                if(owner["isHuman"]!=true)return null
                val priority=owner["hasPriority"] as? Boolean ?: return null
                val timer=owner["timerActive"] as? Boolean ?: return null
                val selfAuthority=controls.isEmpty() && (!priority || timer) && (poll.decision==null || priority)
                Context(poll.matchId,poll.viewerId,viewer,active,turn,poll.phase,localHumanEnabled,
                    foreground,stack.isEmpty(),selfAuthority,poll.resync,poll.decision)
            }.getOrNull()
        }
    }
    enum class StopReason(val message:String) {
        UNAVAILABLE("Auto-pass stopped. Pass priority manually."),
        TURN_CHANGED("Auto-pass stopped. The turn changed."),
        CONTROL_CHANGED("Auto-pass stopped. Player control changed."),
        STACK("Auto-pass stopped. Check the stack."),
        DECISION("Auto-pass stopped. A choice needs your attention."),
        INTERRUPTED("Auto-pass stopped. Review the current game state."),
        LIMIT("Auto-pass stopped after its safety limit.")
    }
    sealed class Step {
        data object Wait:Step()
        data class Pass(val prompt:Decision):Step()
        data class Stop(val reason:StopReason):Step()
    }
    private var anchor:Context?=null
    private var mode=Mode.SAFE_END_TURN
    private var expiresAt=0L
    private val attempted=mutableSetOf<String>()
    private var latestRevision=-1L
    val active:Boolean get()=anchor!=null

    fun start(context:Context,nowMs:Long,mode:Mode=Mode.SAFE_END_TURN):Boolean {
        if(!canStart(context,mode) || nowMs<0 || nowMs>Long.MAX_VALUE-mode.durationMs)return false
        this.mode=mode;anchor=context;expiresAt=nowMs+mode.durationMs;attempted.clear();latestRevision=-1
        return true
    }
    fun stop(){anchor=null;attempted.clear();latestRevision=-1}

    fun evaluate(context:Context,nowMs:Long):Step {
        val anchor=anchor ?: return Step.Wait
        val boundary=if(mode==Mode.UNTIL_MY_TURN)
            context.activePlayerId==context.viewerId && (context.turn!=anchor.turn || anchor.activePlayerId!=anchor.viewerId)
        else context.turn!=anchor.turn || context.activePlayerId!=anchor.activePlayerId
        val prompt=context.prompt
        val reason=when {
            !context.localHumanEnabled || context.phase!="running" -> StopReason.UNAVAILABLE
            !context.foreground || context.resyncRequired -> StopReason.INTERRUPTED
            context.matchId!=anchor.matchId || context.seatId!=anchor.seatId || context.viewerId!=anchor.viewerId || !context.selfAuthority -> StopReason.CONTROL_CHANGED
            context.turn<anchor.turn || context.activePlayerId.isNullOrEmpty() || nowMs<0 -> StopReason.INTERRUPTED
            boundary -> StopReason.TURN_CHANGED
            mode==Mode.SAFE_END_TURN && !context.emptyStack -> StopReason.STACK
            nowMs>=expiresAt || attempted.size>=mode.passLimit -> StopReason.LIMIT
            prompt!=null && prompt.kind=="SELECT" && prompt.payload.text("selectMode")=="priority" && prompt.payload.text("manaPlayerId")!=context.viewerId -> StopReason.CONTROL_CHANGED
            prompt!=null && !ordinaryPriority(prompt,context.viewerId) -> StopReason.DECISION
            else -> null
        }
        if(reason!=null){stop();return Step.Stop(reason)}
        if(prompt==null || prompt.submitted || prompt.id in attempted || prompt.revision<=latestRevision)return Step.Wait
        return Step.Pass(prompt)
    }

    /** Reserve before dispatch even if delivery subsequently fails. Never auto-retry. */
    fun recordPass(prompt:Decision) {
        if(!active || attempted.size>=mode.passLimit)return
        attempted+=prompt.id;latestRevision=maxOf(latestRevision,prompt.revision)
    }
    companion object {
        fun canStart(context:Context,mode:Mode=Mode.SAFE_END_TURN):Boolean {
            if(!context.localHumanEnabled || !context.foreground || context.phase!="running" || context.turn<=0 ||
                context.activePlayerId.isNullOrEmpty() || !context.selfAuthority || context.resyncRequired)return false
            if(mode!=Mode.UNTIL_MY_TURN && context.activePlayerId!=context.viewerId || mode==Mode.SAFE_END_TURN && !context.emptyStack)return false
            val prompt=context.prompt ?: return mode==Mode.UNTIL_MY_TURN
            return !prompt.submitted && ordinaryPriority(prompt,context.viewerId)
        }
        private fun ordinaryPriority(prompt:Decision,viewer:String)=prompt.id.isNotBlank() && prompt.revision>=0 &&
            prompt.kind=="SELECT" && prompt.payload.text("selectMode")=="priority" && "boolean" in prompt.responseTypes &&
            prompt.payload.text("manaPlayerId")==viewer
    }
}
