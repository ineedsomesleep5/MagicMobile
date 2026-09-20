package io.magicmobile.android

import android.content.Intent
import android.os.Handler
import android.os.Looper
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.border
import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.alpha
import androidx.compose.foundation.background
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.onLongClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.zIndex
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import io.magicmobile.android.core.*
import java.util.Locale

@Composable internal fun GameScreen(model:AppModel,state:ScreenState,inspect:(String)->Unit) {
    val poll=state.game;val snapshot=poll?.snapshot;val game=snapshot?.obj("gameView")
    val decision=poll?.decision
    val choices=remember(decision,snapshot){runCatching{if(decision==null)emptyList() else Decisions.choices(decision,snapshot)}.getOrElse{emptyList()}}
    val viewerPlayerId=gameplayViewerId(poll)
    val responseCue=priorityResponseCue(decision,game,viewerPlayerId)
    val allBattlefield=game?.array("players").orEmpty().map(Wire::objectValue).flatMap{GameplayPresentation.cards(it["battlefield"])}
    val playerIds=game?.array("players").orEmpty().map(Wire::objectValue).mapNotNull{it.text("playerId")}.toSet()
    val commanderCasts=remember(decision,snapshot,viewerPlayerId){runCatching{castableCommanderIds(decision,snapshot,viewerPlayerId)}.getOrDefault(emptySet())}
    var expandedZones by remember {mutableStateOf<Set<String>>(emptySet())}
    var confirmClose by remember {mutableStateOf(false)}
    var confirmYield by remember {mutableStateOf<AutoYieldPolicy.Mode?>(null)}
    var selectedCard by remember {mutableStateOf<Obj?>(null)}
    var selectedRevision by remember {mutableStateOf<Long?>(null)}
    var notices by remember(poll?.matchId,poll?.viewerId) {mutableStateOf<List<Pair<Long,String>>>(emptyList())}
    BackHandler {confirmClose=true}
    LaunchedEffect(poll?.revision) {
        val incoming=poll?.events.orEmpty().filter{it.text("kind")=="message"}.mapNotNull{event->
            val revision=event.number("revision");val message=event.obj("body")?.text("message")
            if(revision!=null && revision <= (poll?.revision ?: -1) && !message.isNullOrBlank())revision to Decisions.plain(message).take(16384) else null
        }
        if(selectedRevision!=poll?.revision || poll?.phase!="running")selectedCard=null
        notices=(notices+incoming).distinct().sortedBy{it.first}.takeLast(64)
    }
    val board=rememberLazyListState()
    val scope=rememberCoroutineScope()
    val context=LocalContext.current
    Box(Modifier.fillMaxSize()) {
    BattlefieldBackground { Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(horizontal=12.dp)){Text(state.status,modifier=Modifier.weight(1f),style=MaterialTheme.typography.bodySmall);TextButton(onClick={model.refresh()},enabled=!state.closing){Text("Refresh")};TextButton(onClick={confirmClose=true}){Text(if(state.closing)"Retry cleanup" else "Leave")}}
        if(state.busy)LinearProgressIndicator(Modifier.fillMaxWidth())
        if(state.pendingAnswer)Row(Modifier.padding(12.dp)){Text("Uncertain response",modifier=Modifier.weight(1f));Button(onClick={model.retry()},enabled=!state.closing){Text("Retry same action")}}
        if(state.autoPassing) {
            Row(Modifier.fillMaxWidth().padding(horizontal=12.dp)) {
                Text(state.autoPassStatus,Modifier.weight(1f),style=MaterialTheme.typography.bodySmall)
                TextButton(onClick={model.stopAutoPass()}){Text("Stop auto-pass")}
            }
        } else {
            LazyRow(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(4.dp),contentPadding=PaddingValues(horizontal=12.dp)) {
                item {TextButton(enabled=model.canAutoPass(AutoYieldPolicy.Mode.SAFE_END_TURN),onClick={model.startAutoPass(AutoYieldPolicy.Mode.SAFE_END_TURN)}){Text("End turn safely")}}
                item {TextButton(enabled=model.canAutoPass(AutoYieldPolicy.Mode.END_TURN_SKIPPING_RESPONSES),onClick={confirmYield=AutoYieldPolicy.Mode.END_TURN_SKIPPING_RESPONSES}){Text("Skip responses this turn")}}
                item {TextButton(enabled=model.canAutoPass(AutoYieldPolicy.Mode.UNTIL_MY_TURN),onClick={confirmYield=AutoYieldPolicy.Mode.UNTIL_MY_TURN}){Text("Skip to my turn")}}
            }
            if(state.autoPassStatus.isNotBlank())Text(state.autoPassStatus,Modifier.padding(horizontal=12.dp),style=MaterialTheme.typography.bodySmall)
        }
        if(decision!=null && !decision.submitted) TextButton(onClick={scope.launch{board.animateScrollToItem(0)}},modifier=Modifier.fillMaxWidth()) {Text(responseCue ?: "Your action · ${Decisions.plain(decision.payload.text("message").orEmpty()).take(100)}")}
        // A new decision must not land below the fold: on a phone an unseen prompt reads as
        // a frozen game, which is exactly how the mulligan question presented on device.
        LaunchedEffect(decision?.id,decision?.revision) {
            if(decision!=null && !decision.submitted) runCatching { board.animateScrollToItem(0) }
        }
        LazyColumn(Modifier.weight(1f),state=board,contentPadding=PaddingValues(12.dp),verticalArrangement=Arrangement.spacedBy(10.dp)) {
            if(decision!=null)item {Card(Modifier.fillMaxWidth()){Column(Modifier.padding(14.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                Text(decision.kind.replace('_',' '),style=MaterialTheme.typography.titleMedium)
                Text(Decisions.plain(decision.payload.text("message").orEmpty()))
                if(decision.submitted)Text("Answer submitted · waiting for XMage")
                choices.forEach { choice ->
                    val passHelp=priorityPassHelp(decision,choice,game,viewerPlayerId)
                    Column(Modifier.fillMaxWidth(),horizontalAlignment=Alignment.CenterHorizontally){
                        OutlinedButton(onClick={if(choice.type=="uuid" && choice.value in commanderCasts)expandedZones=emptySet();model.answer(choice.type,choice.value)},enabled=!state.busy && !state.pendingAnswer && !state.closing && !decision.submitted,modifier=Modifier.fillMaxWidth().semantics{passHelp?.let{stateDescription=it.accessibility}}) {Text(choice.label)}
                        passHelp?.let{Text(it.text,style=MaterialTheme.typography.labelSmall,modifier=Modifier.clearAndSetSemantics{})}
                    }
                }
                if("integer" in decision.responseTypes) {
                    // The engine sends the Int sentinels to mean "no limit". Showing them
                    // literally prefilled the field with -2147483648 and labelled the range
                    // "-2147483648 … 2147483647", which reads as a broken prompt.
                    val range=PromptPresentation.integerRange(decision)
                    var amount by remember(decision.id,decision.revision){mutableStateOf(range.initialValue)}
                    val entered=amount.toLongOrNull()
                    val withinRange=range.contains(entered)
                    OutlinedTextField(value=amount,onValueChange={amount=it.filter{c->c.isDigit()||c=='-'}.take(12)},
                        isError=amount.isNotEmpty() && !withinRange,label={Text("Amount · ${range.label}")})
                    TextButton(onClick={entered?.let{model.answer("integer",it)}},enabled=!state.busy && !state.pendingAnswer && !state.closing && !decision.submitted && withinRange){Text("Submit amount")}
                }
                if("integers" in decision.responseTypes){
                    val rowsResult=remember(decision){runCatching{PromptPresentation.allocationRows(decision)}}
                    val rows=rowsResult.getOrDefault(emptyList())
                    if(rowsResult.isFailure)Text("Allocation details are unavailable. Refresh the game before answering.",color=MaterialTheme.colorScheme.error)
                    var values by remember(decision.id,decision.revision){mutableStateOf(rows.map{(it.number("defaultValue") ?: it.number("min"))?.toString().orEmpty()})}
                    rows.forEachIndexed{index,row->OutlinedTextField(value=values[index],onValueChange={value->values=values.toMutableList().also{it[index]=value.filter{c->c.isDigit()||c=='-'}.take(12)}},label={Text(Decisions.plain(row.text("message") ?: "Amount ${index+1}"))},supportingText={Text("${row.number("min")} … ${row.number("max")}")},modifier=Modifier.fillMaxWidth())}
                    val entered=values.map{it.toLongOrNull()};val valid=rowsResult.isSuccess && entered.all{it!=null} && runCatching{decision.answer("integers",entered)}.isSuccess
                    Text("Total ${entered.filterNotNull().sum()} · required ${decision.minimum ?: "any"} … ${decision.maximum ?: "any"}")
                    TextButton(onClick={model.answer("integers",entered)},enabled=!state.busy && !state.pendingAnswer && !state.closing && !decision.submitted && valid){Text("Submit allocation")}
                }
                if(decision.kind=="CHOOSE_PILE") {CardZone("Pile 1",decision.payload["pile1"]){selectedCard=it.takeIf(Obj::isNotEmpty);selectedRevision=poll?.revision};CardZone("Pile 2",decision.payload["pile2"]){selectedCard=it.takeIf(Obj::isNotEmpty);selectedRevision=poll?.revision}}
                if(decision.kind=="PICK_TARGET")CardZone("Visible candidates",decision.payload["cards"]){selectedCard=it.takeIf(Obj::isNotEmpty);selectedRevision=poll?.revision}
                if(decision.kind in setOf("CHOOSE_ABILITY","PICK_ABILITY")) {
                    val sources=decision.payload.array("abilities").map(Wire::objectValue).mapNotNull{it.obj("sourceCard")}.distinctBy{it["id"]}
                    if(sources.isNotEmpty())CardZone("Ability sources",sources){selectedCard=it.takeIf(Obj::isNotEmpty);selectedRevision=poll?.revision}
                }
                if(choices.isEmpty() && decision.responseTypes.none{it=="integer" || it=="integers"} && !decision.submitted)Text("This prompt variant needs additional Android presentation support. No choice will be guessed. Export diagnostics and report the prompt kind.",color=MaterialTheme.colorScheme.error)
            }}}
            item {Text("Turn ${game?.get("turn") ?: "—"} · ${game?.get("step")?.toString()?.replace('_',' ') ?: "Waiting for state"}",style=MaterialTheme.typography.titleLarge,fontFamily=FontFamily.Serif)
                Text(Decisions.plain(game?.text("activePlayerName").orEmpty()),style=MaterialTheme.typography.bodyMedium)}
            item {Card(Modifier.fillMaxWidth()){Column(Modifier.padding(12.dp)){CardZone("Your hand",game?.get("myHand")){selectedCard=it.takeIf(Obj::isNotEmpty);selectedRevision=poll?.revision}}}}
            item {Card(Modifier.fillMaxWidth()){Column(Modifier.padding(12.dp)){CardZone("Stack",game?.get("stack")){selectedCard=it.takeIf(Obj::isNotEmpty);selectedRevision=poll?.revision}}}}
            val players=runCatching{game?.array("players").orEmpty().map(Wire::objectValue)}.getOrDefault(emptyList())
            items(players,key={it["playerId"].toString()}) { player -> Card(Modifier.fillMaxWidth()){Column(Modifier.padding(12.dp)){Text("${player["name"]} · ${player["life"]} life",style=MaterialTheme.typography.titleMedium)
                Text("Hand ${player["handCount"] ?: "?"} · Library ${player["libraryCount"] ?: "?"}",style=MaterialTheme.typography.bodySmall)
                PlayerStateBadges(player)
                val attachedEffects=player.text("playerId")?.let{id->allBattlefield.filter{battlefieldAttachmentRoot(it,allBattlefield,playerIds)==id}}.orEmpty()
                if(attachedEffects.isNotEmpty())CardZone("Enchantments on ${Decisions.plain(player.text("name").orEmpty())}",attachedEffects,compact=true){selectedCard=it.takeIf(Obj::isNotEmpty);selectedRevision=poll?.revision}
                if(player.flag("hasPriority"))Text("Has priority",color=MaterialTheme.colorScheme.primary)
                player.obj("manaPool")?.let { pool ->
                    val mana=listOf("white" to "W","blue" to "U","black" to "B","red" to "R","green" to "G","colorless" to "C").filter{(pool.number(it.first) ?: 0)>0}
                    if(mana.isNotEmpty())LazyRow(horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                        items(mana) { (key,symbol) ->
                            val action=if(decision?.submitted==false && player.text("playerId")==viewerPlayerId)floatingManaChoice(choices,player.text("playerId"),key) else null
                            if(action!=null)OutlinedButton(onClick={model.answer(action.type,action.value)},enabled=!state.busy&&!state.pendingAnswer&&!state.closing,modifier=Modifier.border(2.dp,Color(0xFFFFD166),RoundedCornerShape(24.dp))) {ManaSymbol(symbol,22);Text(" × ${pool.number(key)} · Spend",Modifier.padding(start=6.dp))}
                            else Row { ManaSymbol(symbol);Text(" × ${pool.number(key)}") }
                        }
                    }
                }
                BattlefieldZone(player["battlefield"],allBattlefield,playerIds){selectedCard=it.takeIf(Obj::isNotEmpty);selectedRevision=poll?.revision}
                val playerId=player.text("playerId").orEmpty()
                val expanded=playerId in expandedZones
                val canCast=playerId==viewerPlayerId && commanderCasts.isNotEmpty() && !state.busy && !state.pendingAnswer && !state.closing
                TextButton(onClick={expandedZones=if(expanded)expandedZones-playerId else expandedZones+playerId},modifier=if(canCast)Modifier.border(2.dp,Color(0xFFFFD166),RoundedCornerShape(24.dp)) else Modifier){Text(if(canCast)"Commander ready to cast · Zones" else if(expanded)"Hide other zones" else "Graveyard / exile / commanders")}
                if(expanded){CardZone("Graveyard",player["graveyard"]){selectedCard=it.takeIf(Obj::isNotEmpty);selectedRevision=poll?.revision};CardZone("Exile",player["exile"]){selectedCard=it.takeIf(Obj::isNotEmpty);selectedRevision=poll?.revision};CardZone("Command zone",player["commandList"]){selectedCard=it.takeIf(Obj::isNotEmpty);selectedRevision=poll?.revision}}
            }}}
            game?.array("combat").orEmpty().map(Wire::objectValue).forEach {group->item {Card(Modifier.fillMaxWidth()){Column(Modifier.padding(12.dp)){
                Text("Combat → ${group.text("defenderId")?.let{Decisions.labelForID(snapshot,it)} ?: "Defender"}")
                CardZone("Attackers",group["attackers"]){selectedCard=it.takeIf(Obj::isNotEmpty);selectedRevision=poll?.revision};CardZone("Blockers",group["blockers"]){selectedCard=it.takeIf(Obj::isNotEmpty);selectedRevision=poll?.revision}
            }}}}
            listOf("authorizedLookedAt" to "Looked at", "authorizedOpponentHands" to "Revealed hand").forEach{(key,title)->snapshot?.obj(key)?.forEach{(name,cards)->item{CardZone("$title · ${Decisions.plain(name)}",cards){selectedCard=it.takeIf(Obj::isNotEmpty);selectedRevision=poll?.revision}}}}
            listOf("revealed" to "Revealed", "companion" to "Companion").forEach{(key,title)->game?.array(key)?.map(Wire::objectValue)?.forEach{zone->item{CardZone(zone.text("name") ?: title,zone["cards"]){selectedCard=it.takeIf(Obj::isNotEmpty);selectedRevision=poll?.revision}}}}
            snapshot?.array("namedExiles")?.map(Wire::objectValue)?.forEach{zone->item{CardZone(zone.text("name") ?: "Exile",zone["cards"]){selectedCard=it.takeIf(Obj::isNotEmpty);selectedRevision=poll?.revision}}}
            snapshot?.obj("commanders")?.takeIf{it.isNotEmpty()}?.let{commanders->item{Card(Modifier.fillMaxWidth()){Column(Modifier.padding(12.dp)){
                Text("Commanders",style=MaterialTheme.typography.titleMedium)
                commanders.values.map(Wire::objectValue).forEach{commander->Text("${Decisions.plain(commander.text("name").orEmpty())} · tax ${commander.number("commanderTax") ?: 0}");commander.obj("damageToPlayers")?.forEach{(id,damage)->Text("${Decisions.playerName(snapshot,id) ?: "Player"}: $damage commander damage",style=MaterialTheme.typography.bodySmall)}}
            }}}}
            if(poll?.phase in setOf("ended","failed"))item{Text(if(poll?.phase=="ended")"Game finished" else "Game stopped — not recorded as a loss",style=MaterialTheme.typography.titleLarge)}
            if(notices.isNotEmpty())item{var showLog by remember{mutableStateOf(false)};TextButton(onClick={showLog=!showLog}){Text(if(showLog)"Hide game messages" else "Game messages · ${notices.size}")};if(showLog)notices.forEach{Text(it.second,modifier=Modifier.padding(vertical=4.dp),style=MaterialTheme.typography.bodySmall)}}
            item {TextButton(onClick={model.diagnostics {text->Handler(Looper.getMainLooper()).post{context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply{type="text/plain";putExtra(Intent.EXTRA_TEXT,text)},"Share private diagnostics"))}}}){Text("Export diagnostics (may contain private card data)")}}
        }
    }}
    selectedCard?.takeIf{selectedRevision==poll?.revision && poll?.phase=="running"}?.let{card->TransientCardInspector(card)}
    confirmYield?.let { mode -> AlertDialog(onDismissRequest={confirmYield=null},title={Text("Skip priority responses?")},text={Text("${mode.status} You may miss opportunities to respond to spells and abilities. This does not answer targeting, payment, combat selection or other choices for you.")},confirmButton={TextButton(enabled=model.canAutoPass(mode),onClick={confirmYield=null;model.startAutoPass(mode)}){Text("Start skipping responses")}},dismissButton={TextButton(onClick={confirmYield=null}){Text("Cancel")}}) }
    if(confirmClose)AlertDialog(onDismissRequest={confirmClose=false},title={Text("Leave this game?")},text={Text("There is no saved-game resume in this Android alpha. Engine cleanup will finish before another game can start.")},confirmButton={TextButton(onClick={confirmClose=false;model.close()}){Text("Leave / retry cleanup")}},dismissButton={TextButton(onClick={confirmClose=false}){Text("Keep playing")}})
    }
}
@Composable private fun PlayerStateBadges(player:Obj) {
    val badges=publicPlayerBadges(player)
    var previous by remember(player.text("playerId")){mutableStateOf(badges)}
    var changed by remember{mutableStateOf(false)}
    LaunchedEffect(badges){
        if(previous!=badges&&android.animation.ValueAnimator.areAnimatorsEnabled()){
            previous=badges;changed=true;kotlinx.coroutines.delay(550);changed=false
        }else{previous=badges;changed=false}
    }
    val highlight by animateFloatAsState(if(changed)0.22f else 0f,tween(if(android.animation.ValueAnimator.areAnimatorsEnabled())180 else 0),label="Player counter change")
    if(badges.isNotEmpty())LazyRow(horizontalArrangement=Arrangement.spacedBy(8.dp),modifier=Modifier.background(Color(0xFFFFD166).copy(alpha=highlight),RoundedCornerShape(8.dp)).padding(vertical=4.dp)){
        items(badges){Text(it,style=MaterialTheme.typography.labelLarge)}
    }
}
@Composable private fun BattlefieldZone(value:Any?,all:List<Obj>,playerIds:Set<String>,inspect:(Obj)->Unit) {
    val local=GameplayPresentation.cards(value)
    val roots=remember(all,playerIds){all.associate{it.text("id") to battlefieldAttachmentRoot(it,all,playerIds)}}
    Text("Battlefield · ${local.size}",style=MaterialTheme.typography.labelLarge)
    LazyRow(horizontalArrangement=Arrangement.spacedBy(8.dp),contentPadding=PaddingValues(vertical=6.dp)) {
        itemsIndexed(local.filter{roots[it.text("id")]==null},key={index,card->card.text("id") ?: "unknown:$index"}){_,host->
            Column(Modifier.width(172.dp).border(1.dp,MaterialTheme.colorScheme.outlineVariant,RoundedCornerShape(12.dp)).padding(6.dp)){
                CardZone("Permanent",listOf(host),inspect=inspect)
                all.filter{roots[it.text("id")]==host.text("id")&&roots[it.text("id")]!=null}.forEach{attachment->
                    val immediateHost=all.firstOrNull{it.text("id")==attachment.text("attachedTo")}
                    Text("Attached to ${immediateHost?.let(Decisions::cardLabel) ?: "permanent"}",style=MaterialTheme.typography.labelSmall)
                    CardZone("Attachment",listOf(attachment),inspect=inspect)
                }
            }
        }
    }
}
@Composable private fun CardZone(title:String,value:Any?,compact:Boolean=false,inspect:(Obj)->Unit) {
    val cards=GameplayPresentation.cards(value)
    var accessibleCard by remember{mutableStateOf<Obj?>(null)}
    Text("$title · ${cards.size}",style=MaterialTheme.typography.labelLarge)
    if(cards.isEmpty())Text("—",style=MaterialTheme.typography.bodySmall)
    LazyRow(horizontalArrangement=Arrangement.spacedBy(8.dp),contentPadding=PaddingValues(vertical=6.dp)) {itemsIndexed(cards,key={index,card->card.text("id") ?: "unknown:$index"}){_,card->
        val opacity by animateFloatAsState(if(isPhasedOut(card))0.45f else 1f,tween(if(android.animation.ValueAnimator.areAnimatorsEnabled())220 else 0),label="Phasing")
        OutlinedCard(Modifier.width(if(compact)136.dp else 156.dp).alpha(opacity).pointerInput(card){awaitEachGesture{awaitFirstDown(requireUnconsumed=false);val ended=withTimeoutOrNull(350){waitForUpOrCancellation()!=null};if(ended==null){inspect(card);try{waitForUpOrCancellation()}finally{inspect(emptyMap())}}}}.semantics{onLongClick("Card details"){accessibleCard=card;true}}){
        if(!GameplayPresentation.hidden(card))GameCardArtwork(card,Modifier.fillMaxWidth().height(if(compact)56.dp else 96.dp))
        Column(Modifier.padding(if(compact)6.dp else 10.dp).heightIn(min=if(compact)0.dp else 92.dp),verticalArrangement=Arrangement.spacedBy(4.dp)){Text(Decisions.cardLabel(card),style=MaterialTheme.typography.titleSmall,maxLines=2,overflow=TextOverflow.Ellipsis);if(!compact)ManaCost(GameplayPresentation.printedCost(card));Text(GameplayPresentation.status(card),style=MaterialTheme.typography.bodySmall,maxLines=2,overflow=TextOverflow.Ellipsis)}
    }}}
    accessibleCard?.let{card->AlertDialog(onDismissRequest={accessibleCard=null},title={Text(Decisions.cardLabel(card))},text={Column(Modifier.verticalScroll(rememberScrollState()),verticalArrangement=Arrangement.spacedBy(12.dp)){
        if(!GameplayPresentation.hidden(card))GameCardArtwork(card,Modifier.fillMaxWidth().height(240.dp))
        ManaCost(GameplayPresentation.printedCost(card),24);Text(GameplayPresentation.status(card));Text(GameplayPresentation.details(card).ifBlank{"No additional rules text in this game view."})
    }},confirmButton={TextButton(onClick={accessibleCard=null}){Text("Close")}})}
}

/** Draw-only overlay: the original pointer stream keeps ownership so lift/cancel always closes it. */
@Composable private fun TransientCardInspector(card:Obj) {
    Box(Modifier.fillMaxSize().zIndex(20f),contentAlignment=Alignment.Center) {
        Surface(Modifier.padding(24.dp).widthIn(max=420.dp),shape=RoundedCornerShape(16.dp),tonalElevation=8.dp,shadowElevation=12.dp) {
            Column(Modifier.padding(16.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                Text(Decisions.cardLabel(card),style=MaterialTheme.typography.titleLarge,maxLines=2,overflow=TextOverflow.Ellipsis)
                if(!GameplayPresentation.hidden(card))GameCardArtwork(card,Modifier.fillMaxWidth().heightIn(max=360.dp).aspectRatio(.716f).clip(RoundedCornerShape(10.dp)))
                ManaCost(GameplayPresentation.printedCost(card),24)
                Text(GameplayPresentation.status(card),maxLines=2,overflow=TextOverflow.Ellipsis)
                Text(GameplayPresentation.details(card).ifBlank{"No additional rules text in this game view."},maxLines=7,overflow=TextOverflow.Ellipsis)
            }
        }
    }
}

@Composable private fun GameCardArtwork(card:Obj,modifier:Modifier) {
    val token=card.flag("isToken")
    CardArtwork(card.text("displayName") ?: card.text("name") ?: Decisions.cardLabel(card),modifier,
        token=token,tokenIdentity=if(token)gameArtworkTokenIdentity(card) else null){}
}

/** Returns an identity only when the per-viewer game projection contains every token discriminator. */
internal fun gameArtworkTokenIdentity(card:Obj):ArtworkTokenIdentity? {
    if(GameplayPresentation.hidden(card)||!card.flag("isToken"))return null
    val colors=card.obj("color") ?: return null
    val colorNames=listOf("white" to "W","blue" to "U","black" to "B","red" to "R","green" to "G")
    if(colorNames.any{colors[it.first] !is Boolean})return null
    fun words(key:String)=card.array(key).filterIsInstance<String>().map { value ->
        value.lowercase(Locale.ROOT).replaceFirstChar { it.titlecase(Locale.ROOT) }
    }
    val mainTypes=words("superTypes")+words("cardTypes")
    val subTypes=words("subTypes")
    val typeLine=mainTypes.joinToString(" ")+(if(subTypes.isEmpty())"" else " — ${subTypes.joinToString(" ")}")
    val name=(card.text("displayName") ?: card.text("name"))?.takeIf(String::isNotBlank) ?: return null
    return ArtworkTokenIdentity(name,typeLine,card.array("rules").filterIsInstance<String>().joinToString("\n"),
        card.text("power"),card.text("toughness"),colorNames.filter{colors.flag(it.first)}.mapTo(linkedSetOf()){it.second})
}
