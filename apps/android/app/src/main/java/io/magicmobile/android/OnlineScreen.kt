package io.magicmobile.android

import android.content.Intent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.magicmobile.android.core.Deck

@Composable fun OnlineSignInRecovery(model:AppModel,state:OnlineState) {
    var email by remember {mutableStateOf("")};var password by remember {mutableStateOf("")}
    AlertDialog(onDismissRequest={},title={Text("Sign in to reconnect")},text={Column(verticalArrangement=Arrangement.spacedBy(12.dp)){
        Text("Your session expired. Use the same account to return to your seat.")
        OutlinedTextField(email,{email=it.take(254)},label={Text("Email")},singleLine=true,keyboardOptions=KeyboardOptions(keyboardType=KeyboardType.Email))
        OutlinedTextField(password,{password=it.take(256)},label={Text("Password")},singleLine=true,visualTransformation=PasswordVisualTransformation())
        state.message?.let {Text(it,color=MaterialTheme.colorScheme.error)}
    }},confirmButton={TextButton(onClick={model.signInOnline(email,password,false)},enabled=!state.busy&&email.isNotBlank()&&password.isNotBlank()){Text("Reconnect")}},dismissButton={TextButton(onClick=model::returnFromExpiredSession,enabled=!state.busy){Text("Return to menu")}})
}

@Composable fun OnlineScreen(model:AppModel,state:ScreenState) {
    val online by model.online.collectAsStateWithLifecycle()
    val context=LocalContext.current
    var email by rememberSaveable {mutableStateOf("")}
    // Passwords deliberately do not enter saved instance state.
    var password by remember {mutableStateOf("")}
    var signup by rememberSaveable {mutableStateOf(false)}
    var name by rememberSaveable {mutableStateOf("")}
    var code by rememberSaveable {mutableStateOf("")}
    var count by rememberSaveable {mutableIntStateOf(2)}
    var joining by rememberSaveable {mutableStateOf(false)}
    val decks=state.decks.map {it.deck}+state.precons
    var selected by remember {mutableStateOf<Deck?>(null)}
    var deckMenu by remember {mutableStateOf(false)}
    var leave by remember {mutableStateOf(false)}
    LaunchedEffect(Unit){model.openOnline()}
    LaunchedEffect(online.userId){if(online.userId!=null)password=""}
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
        Text(if(online.configured)"Play together" else "Online play is coming soon",style=MaterialTheme.typography.headlineLarge)
        if(!online.configured){Text("Cross-platform play is being prepared. You can still play Commander against AI offline.");return@Column}
        Text("One table. iPhone and Android.",style=MaterialTheme.typography.bodyLarge)
        if(online.busy)LinearProgressIndicator(Modifier.fillMaxWidth())
        if(online.locatingLobby){Text("Checking your current lobby…",style=MaterialTheme.typography.bodyMedium);TextButton(onClick=model::reconnectOnline,enabled=!online.busy){Text("Retry connection")}}
        online.message?.let {Text(it,style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.error)}
        if(!online.connected){Button(onClick=model::reconnectOnline,enabled=!online.busy){Text("Connect")};return@Column}
        if(online.userId==null) {
            Text(if(signup)"Create your account" else "Welcome back",style=MaterialTheme.typography.titleLarge)
            OutlinedTextField(email,{email=it.take(254)},label={Text("Email")},singleLine=true,keyboardOptions=KeyboardOptions(keyboardType=KeyboardType.Email),modifier=Modifier.fillMaxWidth())
            OutlinedTextField(password,{password=it.take(256)},label={Text("Password")},singleLine=true,visualTransformation=PasswordVisualTransformation(),keyboardOptions=KeyboardOptions(keyboardType=KeyboardType.Password),modifier=Modifier.fillMaxWidth())
            Button(onClick={model.signInOnline(email,password,signup)},enabled=!online.busy&&email.isNotBlank()&&password.isNotBlank(),modifier=Modifier.fillMaxWidth()){Text(if(signup)"Create account" else "Sign in")}
            TextButton(onClick={signup=!signup},enabled=!online.busy){Text(if(signup)"Already have an account? Sign in" else "New here? Create an account")}
            Text("Your sign-in works on both platforms. Online play sends your selected deck and game actions to the match server.",style=MaterialTheme.typography.bodySmall)
            return@Column
        }
        val lobby=online.lobby
        if(lobby!=null) {
            Text("Lobby ${lobby.code}",style=MaterialTheme.typography.headlineMedium)
            Text("${lobby.players.size} of ${lobby.playerCount} players · ${lobby.status.replace('_',' ')}")
            if(lobby.status=="interrupted")Text("This match could not be restored after the server restarted. Leave the lobby, then create a new table.",style=MaterialTheme.typography.bodyMedium)
            OutlinedButton(onClick={context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {type="text/plain";putExtra(Intent.EXTRA_TEXT,"Join my MagicMobile lobby: ${lobby.code}. Open Online play on iPhone or Android and enter this code.")},"Invite players"))}){Text("Share lobby code")}
            lobby.players.forEach {player->OutlinedCard(Modifier.fillMaxWidth()){Row(Modifier.padding(16.dp),horizontalArrangement=Arrangement.spacedBy(12.dp)){Column(Modifier.weight(1f)){Text(player.name,style=MaterialTheme.typography.titleMedium);Text(if(player.userId==lobby.hostUserId)"Host" else "Player",style=MaterialTheme.typography.bodySmall)};Text(if(player.ready)"Ready" else if(player.deckSubmitted)"Choosing ready" else "Choosing deck")}}}
            if(online.reconnecting){Text("Reconnecting… Your seat is reserved.");TextButton(onClick=model::reconnectOnline,enabled=!online.busy){Text("Try now")}}
            if(lobby.status in setOf("waiting","ready")) {
                val me=lobby.players.firstOrNull {it.userId==online.userId}
                Button(onClick={model.readyOnline(me?.ready!=true)},enabled=!online.busy&&!online.reconnecting&&me?.deckSubmitted==true,modifier=Modifier.fillMaxWidth()){Text(if(me?.ready==true)"Not ready" else "Ready to play")}
                if(lobby.hostUserId==online.userId)Button(onClick=model::startOnline,enabled=!online.busy&&!online.reconnecting&&lobby.players.size==lobby.playerCount&&lobby.players.all {it.ready&&it.deckSubmitted},modifier=Modifier.fillMaxWidth()){Text("Start game")}
                Text("Everyone must be ready before the host starts.",style=MaterialTheme.typography.bodySmall)
            }
            TextButton(onClick={leave=true},enabled=!online.busy){Text("Leave lobby")}
        } else {
            Row(horizontalArrangement=Arrangement.spacedBy(10.dp)){FilterChip(!joining,{joining=false},label={Text("Create lobby")});FilterChip(joining,{joining=true},label={Text("Join with code")})}
            OutlinedTextField(name,{name=it.take(24)},label={Text("Player name")},singleLine=true,modifier=Modifier.fillMaxWidth())
            Box {OutlinedButton(onClick={deckMenu=true},enabled=!online.busy,modifier=Modifier.fillMaxWidth()){Text(selected?.name ?: "Choose your deck")};DropdownMenu(deckMenu,{deckMenu=false}){decks.forEach {deck->DropdownMenuItem(text={Text(deck.name)},onClick={selected=deck;deckMenu=false})}}}
            if(joining)OutlinedTextField(code,{code=it.filter(Char::isLetterOrDigit).take(6).uppercase()},label={Text("Lobby code")},singleLine=true,modifier=Modifier.fillMaxWidth())
            else Row(horizontalArrangement=Arrangement.spacedBy(8.dp)){(2..4).forEach {n->FilterChip(count==n,{count=n},label={Text("$n players")})}}
            Button(onClick={selected?.let {model.createOnline(it,name,count,if(joining)code else null)}},enabled=!online.busy&&!online.locatingLobby&&selected!=null&&name.isNotBlank()&&(!joining||code.length==6),modifier=Modifier.fillMaxWidth()){Text(if(joining)"Join lobby" else "Create lobby")}
            Text("Your deck is checked by the server before joining. All players need the same MagicMobile build.",style=MaterialTheme.typography.bodySmall)
            TextButton(onClick=model::signOutOnline,enabled=!online.busy&&!online.locatingLobby){Text("Sign out")}
        }
    }
    if(leave)AlertDialog(onDismissRequest={leave=false},title={Text("Leave this lobby?")},text={Text("If the game has started, leaving ends the match for everyone.")},confirmButton={TextButton(onClick={leave=false;model.leaveOnline()}){Text("Leave")}},dismissButton={TextButton(onClick={leave=false}){Text("Stay")}})
}
