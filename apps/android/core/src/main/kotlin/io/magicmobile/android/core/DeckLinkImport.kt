package io.magicmobile.android.core

import java.net.URI

object DeckLinkImport {
    data class Source(val provider: String, val id: String, val endpoint: String)
    fun source(text: String): Source {
        require(text.length <= 2048)
        val uri = URI(text.trim())
        require(uri.scheme == "https" && uri.rawUserInfo == null && uri.port == -1 && uri.rawQuery == null && uri.rawFragment == null && !uri.rawPath.contains('%')) { "Use a public HTTPS deck link without credentials, query parameters, or fragments." }
        val parts = uri.path.split('/')
        require(parts.size in 3..4 && parts[0].isEmpty() && parts[1] == "decks")
        val id = parts[2]
        return when(uri.host?.lowercase()) {
            "moxfield.com", "www.moxfield.com" -> {
                require(Regex("[A-Za-z0-9_-]{22}").matches(id) && (parts.size == 3 || parts[3].isEmpty()))
                Source("moxfield", id, "https://api2.moxfield.com/v3/decks/all/$id")
            }
            "archidekt.com", "www.archidekt.com" -> {
                require(Regex("[1-9][0-9]{0,14}").matches(id) && (parts.size == 3 || Regex("[A-Za-z0-9_-]*").matches(parts[3])))
                Source("archidekt", id, "https://archidekt.com/api/decks/$id/")
            }
            else -> error("Only public Archidekt and Moxfield deck links are supported.")
        }
    }
    fun decode(source: Source, value: Obj): Deck {
        fun row(name: String, count: Any?, section: String): CardEntry {
            val quantity = Wire.integer(count); require(quantity in 1..2000)
            return CardEntry(name, quantity.toInt(), section)
        }
        val entries = mutableListOf<CardEntry>()
        if(source.provider == "moxfield") {
            require(value.text("publicId") == source.id && value.text("visibility")?.lowercase() == "public") { "Deck must be public and match the requested link." }
            val sections = mapOf("mainboard" to "deck", "commanders" to "commanders", "companions" to "companions", "sideboard" to "sideboard", "maybeboard" to "maybeboard")
            Wire.objectValue(value["boards"]).forEach { (key, board) ->
                val cards = Wire.objectValue(Wire.objectValue(board)["cards"])
                require(key in sections || cards.isEmpty()) { "Unsupported provider board: $key. No cards imported." }
                cards.values.forEach { raw -> val card = Wire.objectValue(raw)
                    entries += row(Wire.string(Wire.objectValue(card["card"])["name"]), card["quantity"], sections.getValue(key))
                }
            }
        } else {
            require(Wire.integer(value["id"]).toString() == source.id && value["private"] == false && value["unlisted"] == false) { "Deck must be public and match the requested link." }
            val categories = mutableMapOf<String, Boolean>()
            value.array("categories").forEach { raw -> val category = Wire.objectValue(raw);val name = Wire.string(category["name"])
                require(name !in categories && category["includedInDeck"] is Boolean)
                categories[name] = category["includedInDeck"] as Boolean
            }
            value.array("cards").forEach { raw -> val card = Wire.objectValue(raw)
                val labels = card["categories"]?.let { Wire.list(it).map(Wire::string) }.orEmpty()
                require(labels.all { it in categories }) { "Unknown provider category. No cards imported." }
                val roles = labels.map(String::lowercase).filter { it in setOf("commander", "companion", "sideboard", "maybeboard") }.toSet()
                require(roles.size <= 1 && (card["companion"] == null || card["companion"] is Boolean))
                val companion = card["companion"] == true || "companion" in roles
                val excluded = labels.isNotEmpty() && labels.all { categories[it] == false }
                require(!(companion && "commander" in roles))
                val side = roles.any { it in setOf("sideboard", "maybeboard") }
                require(!side || (!companion && labels.none { categories[it] == true })) { "Conflicting included/excluded provider categories." }
                require(!excluded || "commander" !in roles)
                val section = when { "commander" in roles -> "commanders"; companion -> "companions"; "sideboard" in roles -> "sideboard"; side || excluded -> "maybeboard"; else -> "deck" }
                entries += row(Wire.string(Wire.objectValue(Wire.objectValue(card["card"])["oracleCard"])["name"]), card["quantity"], section)
            }
        }
        require(entries.isNotEmpty()) { "Provider returned an empty deck." }
        return Deck(Wire.string(value["name"]), entries)
    }
}
