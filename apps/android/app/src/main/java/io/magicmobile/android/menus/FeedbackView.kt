package io.magicmobile.android.menus

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import io.magicmobile.android.board.tavernSettingsPanel
import io.magicmobile.android.game.FeedbackDraft
import io.magicmobile.android.ui.SfWeight
import kotlinx.coroutines.launch

/**
 * Send feedback (Options and About): Bug or Feature idea, the note, an optional contact. The account attaches the
 * build and the phone. Success and failure stay on this page; a failure keeps the note so it can be sent again.
 */
@Composable
fun FeedbackForm(send: suspend (String, String, String) -> String) {
    var kind by rememberSaveable { mutableStateOf("bug") }
    var message by rememberSaveable { mutableStateOf("") }
    var contact by rememberSaveable { mutableStateOf("") }
    var sending by rememberSaveable { mutableStateOf(false) }
    var outcome by rememberSaveable { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val sent = outcome == "sent"
    val canSend = !sending && !sent && FeedbackDraft.message(message) != null && FeedbackDraft.contact(contact).ok
    Column(Modifier.tavernSettingsPanel(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        if (sent) {
            Text(FeedbackDraft.notice("sent"), color = ArenaMenuStyle.gold, style = ArenaMenuStyle.font(15f, SfWeight.semibold),
                modifier = Modifier.testTag("feedback.status"))
            ArenaPillButton("Send another", { outcome = null; message = ""; contact = "" }, identifier = "feedback.another")
        } else {
            ArenaSegmented(listOf("Bug" to "bug", "Feature idea" to "feature"), kind, { kind = it }, identifier = "feedback.kind", stretch = true)
            NoteField(message, { message = FeedbackDraft.cleanMessage(it); if (outcome != "sent") outcome = null })
            ContactField(contact, { contact = FeedbackDraft.cleanContact(it); if (outcome != "sent") outcome = null })
            outcome?.let { code ->
                Text(FeedbackDraft.notice(code), color = ArenaMenuStyle.ember, style = ArenaMenuStyle.font(13f, SfWeight.semibold),
                    modifier = Modifier.testTag("feedback.status"))
            }
            ArenaPillButton(if (sending) "Sending…" else "Send", {
                if (!canSend) return@ArenaPillButton
                sending = true
                val sentKind = kind
                val sentMessage = message
                val sentContact = contact
                scope.launch {
                    outcome = send(sentKind, sentMessage, sentContact)
                    sending = false
                }
            }, lit = true, enabled = canSend, identifier = "feedback.send")
        }
    }
}

@Composable
private fun NoteField(message: String, onChange: (String) -> Unit) {
    val shape = RoundedCornerShape(12.dp)
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        BasicTextField(message, onChange, Modifier.fillMaxWidth().heightIn(min = 140.dp)
            .background(androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.45f), shape)
            .border(1.dp, ArenaGlass.hairline, shape).padding(12.dp)
            .testTag("feedback.message").semantics { contentDescription = "Message" },
            textStyle = ArenaMenuStyle.font(14f, SfWeight.medium).copy(color = ArenaMenuStyle.text),
            cursorBrush = SolidColor(ArenaMenuStyle.gold),
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
            decorationBox = { inner ->
                Box {
                    if (message.isEmpty()) Text("What happened, or what should MagicMobile do?", color = ArenaMenuStyle.dim,
                        style = ArenaMenuStyle.font(14f, SfWeight.medium))
                    inner()
                }
            })
        Text("${FeedbackDraft.chars(message)}/${FeedbackDraft.MAX_MESSAGE}", Modifier.align(Alignment.End),
            color = ArenaMenuStyle.dim, style = ArenaMenuStyle.font(11f, SfWeight.semibold).copy(fontFeatureSettings = "tnum"))
    }
}

@Composable
private fun ContactField(contact: String, onChange: (String) -> Unit) {
    val shape = RoundedCornerShape(12.dp)
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        BasicTextField(contact, onChange, Modifier.fillMaxWidth().heightIn(min = 40.dp)
            .background(androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.45f), shape)
            .border(1.dp, ArenaGlass.hairline, shape).padding(horizontal = 12.dp, vertical = 10.dp)
            .testTag("feedback.contact").semantics { contentDescription = "Contact" },
            singleLine = true, textStyle = ArenaMenuStyle.font(14f, SfWeight.medium).copy(color = ArenaMenuStyle.text),
            cursorBrush = SolidColor(ArenaMenuStyle.gold),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email, capitalization = KeyboardCapitalization.None),
            decorationBox = { inner ->
                Box {
                    if (contact.isEmpty()) Text("Email or handle, if you want a reply", color = ArenaMenuStyle.dim,
                        style = ArenaMenuStyle.font(14f, SfWeight.medium))
                    inner()
                }
            })
        if (!FeedbackDraft.contact(contact).ok) {
            Text(FeedbackDraft.notice("invalid_contact"), color = ArenaMenuStyle.ember, style = ArenaMenuStyle.font(12f, SfWeight.semibold))
        }
    }
}
