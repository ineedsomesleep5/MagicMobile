package io.magicmobile.android.menus

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import io.magicmobile.android.game.PlayerAccountRules
import io.magicmobile.android.social.GoogleSignIn
import io.magicmobile.android.social.PlayerAccount
import io.magicmobile.android.social.SupabaseLite
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import kotlinx.coroutines.launch

/**
 * The first thing a player without a name sees (NameGateView.swift; Caleb, 2026-10-29: "make them have to login"): a
 * name for every table, or sign in to the account that already has one. Covers the app until the profile has a name;
 * offline, or with the profile server down, the app plays as before ([PlayerAccount.needsName] is false).
 */
@Composable
fun NameGate(account: PlayerAccount) {
    if (!account.needsName) return
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var name by remember { mutableStateOf("") }
    var saving by remember { mutableStateOf(false) }
    val focus = remember { FocusRequester() }
    val busy = saving || account.isSigningIn
    fun save() {
        if (!PlayerAccountRules.isValidUsername(name) || busy) return
        saving = true
        scope.launch { try { account.claim(name) } finally { saving = false } }
    }
    LaunchedEffect(Unit) { account.notice = null; runCatching { focus.requestFocus() } }
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.88f))
        .clickable(remember { MutableInteractionSource() }, null) {}.testTag("nameGate"), contentAlignment = Alignment.Center) {
        Column(Modifier.safeDrawingPadding().imePadding().verticalScroll(rememberScrollState()).widthIn(max = 380.dp)
            .padding(horizontal = 24.dp, vertical = 40.dp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(18.dp)) {
            Text("Choose your name", color = ArenaMenuStyle.gold, style = ArenaMenuStyle.title(26f))
            Column(Modifier.fillMaxWidth().arenaCard(padding = 18.dp), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(Modifier.fillMaxWidth().height(48.dp).background(Color.Black.copy(alpha = 0.55f), CircleShape)
                    .border(1.dp, ArenaGlass.hairline, CircleShape).padding(horizontal = 16.dp), contentAlignment = Alignment.Center) {
                    if (name.isEmpty()) Text("Player name", color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(17f, SfWeight.semibold))
                    BasicTextField(name, { value -> name = value.filter { it in 'a'..'z' || it in 'A'..'Z' || it in '0'..'9' || it == '_' }.take(20) },
                        Modifier.fillMaxWidth().focusRequester(focus).testTag("nameGate.field").semantics { contentDescription = "Player name" },
                        singleLine = true,
                        textStyle = ArenaMenuStyle.font(17f, SfWeight.semibold).copy(color = ArenaMenuStyle.text, textAlign = TextAlign.Center),
                        cursorBrush = SolidColor(ArenaMenuStyle.gold),
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, imeAction = ImeAction.Go),
                        keyboardActions = KeyboardActions(onGo = { save() }))
                }
                Text(account.notice ?: "3–20 letters, numbers or underscores", color = if (account.notice == null) ArenaMenuStyle.dim else ArenaMenuStyle.loss,
                    style = ArenaMenuStyle.font(12f, SfWeight.medium), textAlign = TextAlign.Center)
                ArenaButton({ save() }, kind = ArenaButtonKind.PRIMARY, fullWidth = true, enabled = PlayerAccountRules.isValidUsername(name) && !busy,
                    label = "Continue", identifier = "nameGate.continue") { ArenaButtonText("Continue") }
            }
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                ArenaCaps("Already have a profile?")
                ArenaButton({
                    scope.launch {
                        try {
                            val (token, nonce) = GoogleSignIn.signIn(context)
                            account.signIn("google", token, nonce)
                        } catch (error: Exception) { account.notice = PlayerAccountRules.message(SupabaseLite.code(error)) }
                    }
                }, kind = ArenaButtonKind.SECONDARY, fullWidth = true, enabled = !busy, label = "Continue with Google", identifier = "nameGate.google") {
                    SfImage("person.crop.circle.fill", androidx.compose.material3.LocalContentColor.current, 14.dp)
                    ArenaButtonText("Continue with Google")
                }
                if (account.isSigningIn) CircularProgressIndicator(Modifier.size(20.dp), color = ArenaMenuStyle.gold, strokeWidth = 2.dp)
            }
        }
    }
}
