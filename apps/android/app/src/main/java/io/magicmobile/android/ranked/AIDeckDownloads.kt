package io.magicmobile.android.ranked

import android.content.Context
import io.magicmobile.android.game.AIDeckUpdates
import io.magicmobile.android.game.AppConfig
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** The phone's copy of a newer ai-decks.json ([AIDeckUpdates]; AIDeckUpdates in AIDeckPool.swift). */
object AIDeckDownloads {
    private fun file(context: Context) = File(context.filesDir, "ai-decks.json")

    fun installed(context: Context, bundled: String): String? =
        runCatching { file(context).takeIf { it.exists() }?.readText() }.getOrNull()?.takeIf { AIDeckUpdates.isUsable(it, bundled) }

    /** Best effort, and nothing changes until the next launch: a game in progress keeps the decks it started with. */
    suspend fun refresh(context: Context, config: AppConfig) = withContext(Dispatchers.IO) {
        runCatching {
            val bundled = context.assets.open("ai-decks.json").use { it.readBytes().decodeToString() }
            val current = installed(context, bundled)?.let(AIDeckUpdates::revision)
            val offered = config.deckFiles[AIDeckUpdates.catalogue(bundled)]
            when (val step = AIDeckUpdates.step(offered, current, AIDeckUpdates.revision(bundled))) {
                AIDeckUpdates.Step.Keep -> Unit
                AIDeckUpdates.Step.Remove -> { file(context).delete(); Unit }
                is AIDeckUpdates.Step.Download -> {
                    val bytes = download(step.file.url) ?: return@runCatching
                    val sha256 = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
                    val text = bytes.decodeToString()
                    if (sha256 == step.file.sha256 && AIDeckUpdates.isUsable(text, bundled)) {
                        val temporary = File(context.filesDir, "ai-decks.json.tmp")
                        temporary.writeBytes(bytes)
                        temporary.renameTo(file(context))
                    }
                }
            }
        }
        Unit
    }

    private fun download(url: String): ByteArray? {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.connectTimeout = 15_000
        connection.readTimeout = 30_000
        return try {
            if (connection.responseCode != 200 || connection.contentLengthLong > AIDeckUpdates.MAX_BYTES) return null
            connection.inputStream.use { it.readBytes() }
        } finally { connection.disconnect() }
    }
}
