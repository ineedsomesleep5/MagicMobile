package io.magicmobile.android

import androidx.compose.foundation.layout.Column
import androidx.compose.material3.*
import androidx.compose.runtime.*
import io.magicmobile.android.core.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import javax.net.ssl.HttpsURLConnection
import java.net.URL

@Composable internal fun DeckLinkDialog(close: () -> Unit, imported: (Deck, String) -> Unit) {
    var link by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    AlertDialog(onDismissRequest = { if(!busy)close() }, title = { Text("Import public deck") }, text = {
        Column {
            Text("Import an Archidekt or Moxfield public link. This contacts that provider only after you tap Import. All boards are preserved for review; private decks and sign-in are unsupported.")
            OutlinedTextField(value = link, onValueChange = { link = it.take(2048) }, enabled = !busy, label = { Text("Public deck URL") })
            if(busy)LinearProgressIndicator()
            error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        }
    }, confirmButton = { TextButton(enabled = !busy && link.isNotBlank(), onClick = {
        busy = true;error = null
        scope.launch {
            runCatching { withContext(Dispatchers.IO) {
                val source = DeckLinkImport.source(link)
                val connection = URL(source.endpoint).openConnection() as HttpsURLConnection
                try {
                    connection.instanceFollowRedirects = false;connection.connectTimeout = 15000;connection.readTimeout = 15000
                    connection.useCaches = false
                    connection.setRequestProperty("Accept", "application/json")
                    connection.setRequestProperty("User-Agent", "MagicMobile-DeckImport/1.0")
                    require(connection.responseCode == 200) { "Provider unavailable (HTTP ${connection.responseCode}). Export as text and paste instead." }
                    require(connection.contentType?.substringBefore(';')?.trim()?.lowercase() == "application/json" && connection.contentLengthLong <= 2 * 1024 * 1024) { "Provider returned unsupported or oversized data." }
                    val data = connection.inputStream.use { readBounded(it, 2 * 1024 * 1024) }
                    DeckLinkImport.decode(source, Wire.objectValue(io.magicmobile.core.Json.parseObject(data.toString(Charsets.UTF_8))))
                } finally { connection.disconnect() }
            } }.onSuccess{imported(it,link.trim())}.onFailure { error = it.message ?: "Import failed. Export as text and paste instead." }
            busy = false
        }
    }) { Text("Import") } }, dismissButton = { TextButton(enabled = !busy, onClick = close) { Text("Cancel") } })
}
