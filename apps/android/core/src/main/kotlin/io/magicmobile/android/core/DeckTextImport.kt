package io.magicmobile.android.core

data class DeckTextPreview(val deck: Deck, val annotations: List<String>, val originalText: String = "")
object DeckTextImport {
    fun strictUTF8(bytes:ByteArray):String {
        require(bytes.size<=2*1024*1024){"Deck file exceeds 2 MiB."}
        return try{Charsets.UTF_8.newDecoder().onMalformedInput(java.nio.charset.CodingErrorAction.REPORT).onUnmappableCharacter(java.nio.charset.CodingErrorAction.REPORT).decode(java.nio.ByteBuffer.wrap(bytes)).toString()}
        catch(error:java.nio.charset.CharacterCodingException){throw IllegalArgumentException("Deck file is not valid UTF-8. No cards were imported.",error)}
    }
    /** Current iOS DeckList JSON. Commander rows remain in entries so row order is retained. */
    fun exportJSON(deck:Deck):String=io.magicmobile.core.Json.write(mapOf("name" to deck.name,"commander" to null,"entries" to deck.entries.map{mapOf("cardName" to it.name,"quantity" to it.quantity,"section" to it.section)})).also{require(it.toByteArray().size<=2*1024*1024){"Deck JSON exceeds the 2 MiB interchange limit."}}
    fun exportText(deck:Deck):String {
        val text=deck.export()
        val decoded=runCatching{preview(deck.name,text).deck}.getOrElse{throw IllegalArgumentException("Use JSON export to preserve empty drafts, custom boards or unusual card names.")}
        fun counts(value:Deck)=value.entries.groupBy{it.section to it.name}.mapValues{(_,rows)->rows.sumOf{it.quantity}}
        require(counts(decoded)==counts(deck)){"Use JSON export to preserve every name, quantity and board."}
        return text
    }
    private fun section(value: String): String? = DeckSections.known(value)
    fun preview(name: String, text: String): DeckTextPreview {
        require(text.toByteArray().size <= 2 * 1024 * 1024)
        val jsonText=text.removePrefix("\uFEFF")
        if(jsonText.trimStart().startsWith('{')) {
            val value=Wire.objectValue(io.magicmobile.core.Json.parseObject(jsonText))
            val annotations=mutableListOf<String>()
            val envelope=value.text("format")=="magicmobile-deck-v1"
            if("format" in value)require(envelope){"Unsupported deck JSON format. No cards imported."}
            val data=if(envelope){require(value.keys==setOf("format","deck")){"Unexpected JSON envelope fields."};Wire.objectValue(value["deck"])}else value
            require(data.keys.all{it in setOf("name","entries","commander")}&&data.keys.containsAll(setOf("name","entries"))){"Expected iOS DeckList or Android deck JSON."}
            val rows=Wire.list(data["entries"]).map(Wire::objectValue)
            val ios="commander" in data||rows.firstOrNull()?.containsKey("cardName")==true
            require(!envelope||!ios){"Android envelope contains an incompatible deck schema."}
            fun entry(row:Obj,primary:Boolean=false):CardEntry {
                val nameKey=if(ios)"cardName" else "name"
                require(row.keys==setOf(nameKey,"quantity","section")){"Unexpected or missing card fields. No cards imported."}
                val count=Wire.integer(row["quantity"]);require(count in 1..2000){"Card quantity must be between 1 and 2,000."}
                val sourceSection=Wire.string(row["section"])
                val destination=if(primary)"commanders" else DeckSections.normalize(sourceSection)
                if(destination!=sourceSection)annotations+="${Wire.string(row[nameKey])}: source board '$sourceSection' interpreted as '$destination'. Original JSON retained."
                return CardEntry(Wire.string(row[nameKey]),count.toInt(),destination)
            }
            val entries=data["commander"]?.let{listOf(entry(Wire.objectValue(it),true))}.orEmpty()+rows.map{entry(it)}
            return DeckTextPreview(Deck(Wire.string(data["name"]),entries),annotations,text)
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
