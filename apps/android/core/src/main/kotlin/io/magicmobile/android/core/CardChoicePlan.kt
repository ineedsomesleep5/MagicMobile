package io.magicmobile.android.core

/** Local presentation draft. It never creates a batch command or retries a response. */
class CardChoicePlan private constructor(
    private val matchId:String, private val viewerId:String, private val kind:Kind,
    private val context:String, private val universe:Set<String>, private val selected:List<String>,
    private val top:List<String>,
    private val turn:Long?, private val activePlayer:String?, private val enginePlayer:String?,
    private val selectionBounds:Pair<Int,Int>?,
) {
    enum class Kind { SELECTION, SCRY, TOP_ORDER, BOTTOM_ORDER }
    var stopped=false; private set
    var finished=false; private set
    private var lastPrompt:Pair<String,Long>?=null
    private var expectedChosen:Set<String>?=null
    private var orderKind:Kind?=null
    private var remaining:List<String>?=null
    private var doneSent=false
    private var selectionAcknowledged=false
    private var awaitingFinal=false
    private var orderingContext:String?=null

    fun stop(){stopped=true}

    /** A null answer means wait or hand control back; only a new verified prompt can advance. */
    fun next(poll:GamePoll,pending:Boolean,failed:Boolean):Choice? {
        if(stopped || finished)return null
        if(awaitingFinal && !failed && !pending && poll.matchId==matchId && poll.viewerId==viewerId &&
            poll.phase=="ended" && !poll.resync && poll.revision>(lastPrompt?.second ?: Long.MAX_VALUE)){
            finished=true;return null
        }
        val view=poll.snapshot?.obj("gameView")
        if(failed || poll.matchId!=matchId || poll.viewerId!=viewerId || poll.phase in setOf("failed","closed") || poll.resync ||
            view?.number("turn")!=turn || view?.text("activePlayerId")!=activePlayer || poll.snapshot?.text("enginePlayerId")!=enginePlayer){stop();return null}
        if(pending)return null
        if(awaitingFinal){
            poll.decision?.takeIf{!it.submitted && poll.revision>(lastPrompt?.second ?: Long.MAX_VALUE)}?.let{next->
                if(next.id==lastPrompt?.first)stop() else finished=true
            }
            return null
        }
        if(poll.phase!="running"){stop();return null}
        val prompt=poll.decision ?: return null
        if(prompt.submitted)return null
        val key=prompt.id to prompt.revision
        if(key==lastPrompt)return null
        if(prompt.kind!="PICK_TARGET" || "uuid" !in prompt.responseTypes){stop();return null}
        val current=kind(prompt)
        val candidates=candidates(prompt) ?: run{stop();return null}
        if(candidates.isEmpty() || !universe.containsAll(candidates)){stop();return null}
        if(current==Kind.TOP_ORDER || current==Kind.BOTTOM_ORDER){
            if(kind==Kind.SCRY && (!doneSent || !selectionAcknowledged ||
                current==Kind.TOP_ORDER && selected.size>1 && orderKind!=Kind.BOTTOM_ORDER)){stop();return null}
            val messageContext=context(prompt)
            if(orderKind==current && orderingContext!=messageContext){stop();return null}
            val desired=when {kind==Kind.SCRY -> if(current==Kind.TOP_ORDER)top else selected
                kind==current -> selected
                else -> {stop();return null}}
            if(orderKind!=current){
                if(orderKind==Kind.TOP_ORDER || remaining?.size?.let{it>1}==true || candidates!=desired.toSet()){stop();return null}
                orderKind=current
                orderingContext=messageContext
                remaining=if(current==Kind.TOP_ORDER)desired.reversed() else desired
            }
            val queue=remaining.orEmpty()
            if(queue.isEmpty() || candidates!=queue.toSet()){stop();return null}
            if(queue.size==1){
                // HumanPlayer automatically places its last remaining card.
                remaining=queue
                if(current==Kind.TOP_ORDER || kind!=Kind.SCRY || top.isEmpty())finished=true
                return null
            }
            val id=queue.first()
            if(!authorized(prompt,id)){stop();return null}
            remaining=queue.drop(1);lastPrompt=key
            if(remaining!!.size==1 && (current==Kind.TOP_ORDER || kind!=Kind.SCRY || top.isEmpty()))awaitingFinal=true
            return Choice("Place card","uuid",id)
        }
        if(kind !in setOf(Kind.SELECTION,Kind.SCRY) || current!=kind || orderKind!=null || doneSent || context(prompt)!=context){stop();return null}
        if(selectionBounds(prompt)!=selectionBounds){stop();return null}
        if(candidates!=universe){stop();return null}
        val chosen=prompt.payload.obj("options")?.get("chosenTargets")?.let(Wire::list)?.map(Wire::string)?.toSet()
            ?: run{stop();return null}
        if(expectedChosen!=null && chosen!=expectedChosen || !universe.containsAll(chosen)){stop();return null}
        val remove=chosen.subtract(selected.toSet()).firstOrNull()
        val add=selected.firstOrNull{it !in chosen}
        val id=remove ?: add
        if(id!=null){
            if(id !in candidates || !authorized(prompt,id)){stop();return null}
            expectedChosen=if(id in chosen)chosen-id else chosen+id
            lastPrompt=key
            return Choice("Select card","uuid",id)
        }
        selectionAcknowledged=true
        if(selectionBounds?.let{selected.size !in it.first..it.second}==true){stop();return null}
        val doneLabel=prompt.payload.obj("options")?.text("UI.right.btn.text")
        if(doneLabel?.trim()?.equals("Done",true)!=true || "boolean" !in prompt.responseTypes){stop();return null}
        doneSent=true;lastPrompt=key
        if(kind==Kind.SELECTION)awaitingFinal=true
        return Choice("Done","boolean",false)
    }

    companion object {
        /** A visible UUID list alone may be a single required target, not a multi-card draft. */
        fun supportsDraft(prompt:Decision):Boolean {
            if(prompt.kind!="PICK_TARGET" || prompt.submitted || "uuid" !in prompt.responseTypes || candidateIds(prompt).size<2)return false
            val kind=kind(prompt)
            if(kind==Kind.TOP_ORDER || kind==Kind.BOTTOM_ORDER)return true
            val options=prompt.payload.obj("options") ?: return false
            if(options["chosenTargets"]?.let{runCatching{Wire.list(it)}.getOrNull()}==null)return false
            if(kind==Kind.SCRY)return true
            return (selectionBounds(prompt)?.second ?: 0)>1
        }
        /** TargetImpl's aggregate selection limit is in the message, not the one-UUID transport bounds. */
        fun selectionBounds(prompt:Decision):Pair<Int,Int>? {
            val match=Regex("selected\\s+\\d+\\s+of\\s+(\\d+)(?:,\\s*min\\s+(\\d+))?",RegexOption.IGNORE_CASE)
                .find(prompt.payload.text("message").orEmpty()) ?: return null
            val maximum=match.groupValues[1].toIntOrNull() ?: return null
            val minimum=match.groupValues[2].takeIf(String::isNotEmpty)?.toIntOrNull() ?: 0
            return if(maximum>=minimum)minimum to maximum else null
        }
        fun candidateIds(prompt:Decision):List<String> {
            val options=prompt.payload.obj("options")
            val ids=(options?.get("possibleTargets")?.let(Wire::list)?.map(Wire::string).orEmpty()+
                options?.get("chosenTargets")?.let(Wire::list)?.map(Wire::string).orEmpty())
                .ifEmpty{prompt.payload.array("candidates").map(Wire::string)}
            return if(ids.all(Wire::uuid))ids.distinct() else emptyList()
        }
        fun kind(prompt:Decision):Kind {
            val message=prompt.payload.text("message").orEmpty().lowercase()
            return when {
                "card order to put" in message && "last one chosen will be topmost" in message -> Kind.TOP_ORDER
                "card order to put" in message && "last one chosen will be bottommost" in message -> Kind.BOTTOM_ORDER
                "(scry)" in message && "bottom of your library" in message -> Kind.SCRY
                else -> Kind.SELECTION
            }
        }
        private fun context(prompt:Decision)=prompt.payload.text("message").orEmpty()
            .replace(Regex("\\s*\\(selected \\d+ of \\d+(?:, min \\d+)?\\)"),"")
        private fun candidates(prompt:Decision):Set<String>? {
            val ids=candidateIds(prompt)
            return ids.takeIf{it.isNotEmpty()}?.toSet()
        }
        private fun authorized(prompt:Decision,id:String)=Decisions.choices(prompt,null).any{it.type=="uuid" && it.value==id}
        fun create(poll:GamePoll,selected:List<String>,top:List<String> = emptyList()):CardChoicePlan? {
            val prompt=poll.decision ?: return null
            if(!supportsDraft(prompt) || poll.phase!="running" || poll.resync)return null
            val universe=candidates(prompt) ?: return null
            if(selected.size!=selected.toSet().size || top.size!=top.toSet().size || !universe.containsAll(selected+top))return null
            val kind=kind(prompt)
            val bounds=selectionBounds(prompt)
            if(kind in setOf(Kind.SELECTION,Kind.SCRY) && bounds?.let{selected.size !in it.first..it.second}==true)return null
            if(kind==Kind.SCRY && (selected.toSet() intersect top.toSet()).isNotEmpty())return null
            if(kind in setOf(Kind.TOP_ORDER,Kind.BOTTOM_ORDER) && selected.toSet()!=universe)return null
            if(kind==Kind.SCRY && (selected+top).toSet()!=universe)return null
            val view=poll.snapshot?.obj("gameView")
            return CardChoicePlan(poll.matchId,poll.viewerId,kind,context(prompt),universe,selected,top,
                view?.number("turn"),view?.text("activePlayerId"),poll.snapshot?.text("enginePlayerId"),bounds)
        }
    }
}
