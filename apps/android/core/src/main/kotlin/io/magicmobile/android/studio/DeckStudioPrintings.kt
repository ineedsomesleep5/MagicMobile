package io.magicmobile.android.studio

import io.magicmobile.android.core.CardPrinting
import io.magicmobile.android.game.J
import io.magicmobile.android.game.array
import io.magicmobile.android.game.bool
import io.magicmobile.android.game.get
import io.magicmobile.android.game.obj
import io.magicmobile.android.game.string
import kotlinx.serialization.json.Json
import java.net.URI
import java.net.URLEncoder

/** One printing of a card in Scryfall's search results, for choosing its artwork (DeckStudioScryfallPrinting.swift). */
data class ScryfallPrinting(val id: String, val name: String, val set: String, val setName: String, val collectorNumber: String,
                            val releasedAt: String?, val thumbnail: String?) {
    /** Null when the set code or collector number is not one the app can ask Scryfall for exactly. */
    val printing: CardPrinting? get() = CardPrinting.of(set, collectorNumber)
    /** "Commander Masters · 2023". */
    val caption: String get() = listOfNotNull(setName.takeIf { it.isNotEmpty() }, releasedAt?.take(4)?.takeIf { it.isNotEmpty() }).joinToString(" · ")
}

data class ScryfallPrintingsPage(val printings: List<ScryfallPrinting>, val hasMore: Boolean, val page: Int)

/** Every printing of exactly one card: the request and the bounded reading of its answer. */
object DeckStudioPrintings {
    /** A name with a quote or backslash cannot be searched exactly, so it has no other printings. */
    fun isSearchable(name: String): Boolean = name.isNotBlank() && name.toByteArray().size <= 120 && '"' !in name && '\\' !in name && name.none { it.isISOControl() }

    /** Newest first, one page (up to 175) at a time; only the card name goes to Scryfall. Null for an unsearchable name or page. */
    fun requestUrl(name: String, page: Int): String? {
        val card = name.trim()
        if (!isSearchable(card) || page !in 1..10) return null
        fun encode(value: String) = URLEncoder.encode(value, "UTF-8")
        return "https://api.scryfall.com/cards/search?q=${encode("!\"$card\"")}&unique=prints&order=released&dir=desc&page=$page"
    }

    /** The small picture is only ever one on Scryfall's image host. */
    fun thumbnailAllowed(url: String): Boolean = runCatching {
        val uri = URI(url)
        uri.scheme == "https" && uri.host?.lowercase() == "cards.scryfall.io" && uri.rawUserInfo == null && uri.port == -1
    }.getOrDefault(false)

    fun parse(json: String, page: Int): ScryfallPrintingsPage {
        val root = Json.parseToJsonElement(json)
        val rows = root["data"].array
        if (root["object"].string != "list" || rows == null || rows.size > 200) throw IllegalArgumentException("Scryfall returned an unsupported response.")
        val printings = rows.map { row ->
            val id = row["id"].string ?: throw IllegalArgumentException("Scryfall returned an unsupported response.")
            val faceImages = row["card_faces"].array?.firstOrNull()["image_uris"].obj
            val images = row["image_uris"].obj ?: faceImages
            ScryfallPrinting(id, row["name"].string.orEmpty(), row["set"].string.orEmpty(), row["set_name"].string.orEmpty(),
                row["collector_number"].string.orEmpty(), row["released_at"].string,
                images?.get("small").string?.takeIf(::thumbnailAllowed))
        }
        return ScryfallPrintingsPage(printings, root["has_more"].bool == true, page)
    }
}
