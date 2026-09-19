package io.magicmobile.android.core

data class DeckTextPreview(val deck: Deck, val annotations: List<String>, val originalText: String = "")
object DeckTextImport {
    private fun section(value: String): String? = when(value.lowercase()) {
        "main", "mainboard", "deck" -> "deck"
        "commander", "commanders" -> "commanders"
        "companion", "companions" -> "companions"
        "sideboard" -> "sideboard"
        "maybeboard", "considering" -> "maybeboard"
        else -> null
    }
    fun preview(name: String, text: String): DeckTextPreview {
        require(text.toByteArray().size <= 2 * 1024 * 1024)
        if(text.trimStart().startsWith('{')) {
            val value=Wire.objectValue(io.magicmobile.core.Json.parseObject(text))
            val deck=if(value.text("format")=="magicmobile-deck-v1") {
                require(value.keys==setOf("format","deck"));Deck.decode(Wire.objectValue(value["deck"]))
            } else {require(value.keys==setOf("name","entries"));Deck.decode(value)}
            return DeckTextPreview(deck,emptyList(),text)
        }
        var board="deck";val rows=mutableListOf<CardEntry>();val annotations=mutableListOf<String>()
        text.removePrefix("\uFEFF").lines().forEachIndexed { index, raw ->
            val line=raw.trim();if(line.isBlank())return@forEachIndexed
            fun note(value:String){annotations+="Line ${index+1}: $value"}
            val heading=line.removePrefix("//").removePrefix("#").trim().removeSuffix(":").trim()
            section(heading)?.let {board=it;return@forEachIndexed}
            if(line.startsWith("//")||line.startsWith("#")||(!line.first().isDigit()&&line.endsWith(':'))){require(heading.isNotBlank()&&heading.length<=2000);note("Grouping in $board: $heading");return@forEachIndexed}
            val match=Regex("^(\\d{1,4})[xX]?\\s+(.+)$").matchEntire(line) ?: error("Line ${index+1}: expected '1 Card Name' or an explicit section heading. Nothing was discarded.")
            val count=match.groupValues[1].toInt();var card=match.groupValues[2].trim();var target=board
            fun suffix(pattern:String):String? {val found=Regex(pattern).find(card) ?: return null;card=card.removeRange(found.range).trim();return found.value.trim()}
            suffix("\\s+#!.+$")?.let(::note)
            suffix("\\s+\\^[^^\\r\\n]+,#[0-9A-Fa-f]{6}\\^$")?.let(::note)
            suffix("\\s+\\[[^\\[\\]\\r\\n]+\\]$")?.let {category->
                var value=category.drop(1).dropLast(1).trim()
                if(value.endsWith("{top}")){value=value.removeSuffix("{top}").trim();require(section(value)=="commanders"){"Line ${index+1}: unsupported top category"}}
                require(value.isNotEmpty()&&!value.contains('{')&&!value.contains('}'))
                section(value)?.let {mapped->require(board=="deck"||board==mapped){"Line ${index+1}: category conflicts with board"};target=mapped}
                note("Category: $category")
            }
            suffix("\\s+\\*(?:F|E)\\*$")?.let(::note)
            suffix("\\s+\\([A-Za-z0-9]+\\)(?:\\s+[A-Za-z0-9★†-]+)?$")?.let(::note)
            require(card.none{it in "[]^"}&&!card.contains("#!")&&!Regex("\\s+\\*[^*]*\\*$").containsMatchIn(card)){"Line ${index+1}: unsupported export suffix"}
            rows+=CardEntry(card,count,target)
        }
        require(rows.isNotEmpty()){ "No card rows found." }
        return DeckTextPreview(Deck(name,rows),annotations,text)
    }
}
