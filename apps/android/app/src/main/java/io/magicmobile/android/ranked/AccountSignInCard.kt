package io.magicmobile.android.ranked

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import io.magicmobile.android.game.PlayerAccountRules
import io.magicmobile.android.social.GoogleSignIn
import io.magicmobile.android.social.PlayerAccount
import io.magicmobile.android.social.SupabaseLite
import io.magicmobile.android.ui.SfDesign
import io.magicmobile.android.ui.SfImage
import io.magicmobile.android.ui.SfWeight
import io.magicmobile.android.ui.TavernButtonKind
import io.magicmobile.android.ui.TavernConfirmationDialog
import io.magicmobile.android.ui.TavernDialogAction
import io.magicmobile.android.ui.TavernPalette
import io.magicmobile.android.ui.TavernPlaqueButton
import io.magicmobile.android.ui.sf
import kotlinx.coroutines.launch

/**
 * The profile's "Keep your profile" card (AccountSignInCard.swift): sign in with Google so the name, friends and rank
 * follow the player to any phone; signed in, it shows the account and a sign-out.
 */
@Composable
fun AccountSignInCard(account: PlayerAccount) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var confirmSignOut by remember { mutableStateOf(false) }
    val busy = account.isSigningIn || account.phase == PlayerAccount.Phase.LOADING
    Column(Modifier.leatherCard().testTag("profile.accountCard"), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        ProfileSectionTitle(if (account.linkedIdentities.isEmpty()) "Keep your profile" else "Your account")
        if (account.linkedIdentities.isEmpty()) {
            Text("Sign in to keep your name, friends and rank on every phone. Your profile on this phone comes with you.",
                Modifier.alpha(0.85f), color = TavernPalette.parchment, style = sf(13f, SfWeight.regular, SfDesign.SERIF))
            TavernPlaqueButton("Continue with Google", {
                scope.launch {
                    try {
                        val (token, nonce) = GoogleSignIn.signIn(context)
                        account.signIn("google", token, nonce)
                    } catch (error: Exception) { account.notice = PlayerAccountRules.message(SupabaseLite.code(error)) }
                }
            }, Modifier.testTag("profile.account.google"), compact = false, enabled = !busy, systemImage = "person.crop.circle.fill", fullWidth = true)
        } else {
            for (identity in account.linkedIdentities) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                SfImage("person.crop.circle.badge.checkmark", TavernPalette.parchment, 16.dp)
                Text(identity.email?.let { "${identity.title} · $it" } ?: identity.title, color = TavernPalette.parchment,
                    style = sf(14f, SfWeight.semibold, SfDesign.SERIF))
            }
            TavernPlaqueButton("Sign Out", { confirmSignOut = true }, Modifier.testTag("profile.account.signOut"),
                kind = TavernButtonKind.SECONDARY, enabled = !busy, systemImage = "rectangle.portrait.and.arrow.right")
        }
        if (account.isSigningIn) CircularProgressIndicator(Modifier.size(20.dp), color = TavernPalette.parchment, strokeWidth = 2.dp)
    }
    if (confirmSignOut) TavernConfirmationDialog("Sign out on this phone?",
        "Your profile stays on your account. This phone starts a new one until you sign in again.",
        listOf(TavernDialogAction("Sign Out", destructive = true) { scope.launch { account.signOut() } })) { confirmSignOut = false }
}
