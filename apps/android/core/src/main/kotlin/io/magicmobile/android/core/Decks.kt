package io.magicmobile.android.core

import java.io.InputStream

data class CardEntry(val name: String, val quantity: Int, val section: String = "deck")
data class Deck(val name: String, val entries: List<CardEntry>) {
    init { require(name.isNotBlank() && name.length <= 300 && entries.size <= 2000)
        var total = 0L
        entries.forEach { require(it.name.isNotBlank() && it.name.length <= 500 && it.quantity in 1..2000 && it.section.isNotBlank()); total += it.quantity }
        require(total <= 2000) }
    fun export(): String = buildString {
        entries.groupBy { it.section }.forEach { (section, rows) ->
            appendLine(section.replaceFirstChar { it.uppercase() }); rows.forEach { appendLine("${it.quantity} ${it.name}") }; appendLine()
        }
    }
    fun json(): Obj = mapOf("name" to name, "entries" to entries.map { mapOf("name" to it.name, "quantity" to it.quantity, "section" to it.section) })
    fun change(index: Int, delta: Int): Deck { val row = entries[index]; val n = row.quantity.toLong() + delta
        require(n in 0..2000); return copy(entries = entries.toMutableList().apply { if(n == 0L) removeAt(index) else set(index,row.copy(quantity = n.toInt())) }) }
    companion object {
        fun decode(value: Obj): Deck = Deck(Wire.string(value["name"]), value.array("entries").map {
            val row = Wire.objectValue(it); val count = Wire.integer(row["quantity"]); require(count in 1..2000)
            CardEntry(Wire.string(row["name"]),count.toInt(),Wire.string(row["section"])) })
        fun parse(name: String, text: String): Deck {
            require(text.toByteArray().size <= 2 * 1024 * 1024)
            var section = "deck"; val entries = mutableListOf<CardEntry>()
            text.removePrefix("\uFEFF").lines().forEachIndexed { index, raw ->
                val line = raw.trim(); if(line.isBlank()) return@forEachIndexed
                val heading = line.removePrefix("//").trim().lowercase()
                if(heading in setOf("commander","commanders","deck","main","mainboard","sideboard","maybeboard","companion","companions")) {
                    section = when(heading) { "commander","commanders" -> "commanders"; "main","mainboard" -> "deck"; "companion" -> "companions"; else -> heading }; return@forEachIndexed }
                val match = Regex("^(\\d{1,4})[xX]?\\s+(.+)$").matchEntire(line)
                    ?: throw IllegalArgumentException("Line ${index+1}: expected ‘1 Card Name’ or a section heading. Nothing was discarded.")
                val q = match.groupValues[1].toInt(); val card = match.groupValues[2].trim()
                entries += CardEntry(card,q,section)
            }
            return Deck(name,entries)
        }
    }
}

data class CardInfo(
    val name: String,
    val set: String,
    val collector: String,
    val type: String?,
    val rules: String?,
    val cost: String?,
    val identity: List<String>?,
    val colors: List<String>? = null,
    val manaValue: Double? = null,
    val roles: List<String>? = null,
    val types: List<String>? = null,
    val setCodes: List<String> = emptyList(),
)
class Catalogue(input: InputStream) {
    val cards: List<CardInfo>
    private val byName: Map<String, CardInfo>
    private val aliases: Map<String, String>
    val registryHash: String
    val upstreamCommit: String
    init {
        val bytes = input.use { readBounded(it, 48 * 1024 * 1024) }; require(bytes.size <= 48 * 1024 * 1024)
        val lines = bytes.toString(Charsets.UTF_8).lineSequence().filter { it.isNotBlank() }.iterator()
        require(lines.hasNext()); val header = Wire.objectValue(io.magicmobile.core.Json.parseObject(lines.next()))
        registryHash = Wire.string(header["catalogueHash"])
        upstreamCommit = Wire.string(header["upstreamCommit"])
        require(Regex("^[0-9a-f]{64}$").matches(registryHash) && Regex("^[0-9a-f]{40}$").matches(upstreamCommit))
        require(header.text("sourceMetadataSHA256")?.let {Regex("^[0-9a-f]{64}$").matches(it)}==true)
        val validName:(String)->Boolean={name->name.isNotEmpty() && name.toByteArray().size<=1024 && name==name.trim() && name.none(Char::isISOControl)}
        val knownColors=setOf("W","U","B","R","G")
        val knownTypes=setOf("ARTIFACT","BATTLE","CONSPIRACY","CREATURE","DUNGEON","ENCHANTMENT","INSTANT","LAND","PHENOMENON","PLANE","PLANESWALKER","SCHEME","SORCERY","KINDRED","VANGUARD")
        val knownRoles=DeckRole.entries.mapTo(mutableSetOf(),DeckRole::key)
        aliases = header.obj("nameAliases")?.mapValues { Wire.string(it.value) } ?: emptyMap()
        cards = lines.asSequence().map { line ->
            val c = Wire.objectValue(io.magicmobile.core.Json.parseObject(line))
            val name=Wire.string(c["name"]);require(validName(name))
            val manaValue = (c["manaValue"] as? Number)?.toDouble()?.also {
                require(it.isFinite() && it >= 0.0 && it < 1_000_000.0)
            }
            fun colors(key:String)=c[key]?.let {Wire.list(it).map(Wire::string).also {values->require(values.size<=5 && values.distinct().size==values.size && values.all(knownColors::contains))}}
            val suppliedTypes=c["types"]?.let {Wire.list(it).map(Wire::string).also {values->require(values.isNotEmpty() && values.size<=32 && values.distinct().size==values.size && values.all {type->Regex("^[A-Z][A-Z_]{0,63}$").matches(type)})}}
            val types=suppliedTypes?.takeIf {it.all(knownTypes::contains)}
            val roles=c["roles"]?.let {Wire.list(it).map(Wire::string).also {values->require(values.size<=knownRoles.size && values.distinct().size==values.size && values.all(knownRoles::contains))}} ?: emptyList()
            val sets=c["setCodes"]?.let {Wire.list(it).map(Wire::string)} ?: emptyList();require(sets.distinct().size==sets.size)
            val typeLine=c.text("typeLine")?.also {require(validName(it))}
            CardInfo(name,Wire.string(c["setCode"]),Wire.string(c["collectorNumber"]),
                if(types==null)null else typeLine,c.text("oracleText")?.let(Decisions::plain),c.text("manaCost"),
                colors("colorIdentity"),colors("colors"),manaValue,roles,types,sets)
        }.sortedBy {it.name}.toList()
        byName = cards.associateBy { it.name }; require(byName.size == cards.size && cards.isNotEmpty())
        require(aliases.size<=100_000 && aliases.all { (alias,target)->validName(alias) && target in byName && alias.startsWith("$target // ") && validName(alias.removePrefix("$target // ")) })
    }
    fun find(name: String): CardInfo? = byName[name] ?: aliases[name]?.let(byName::get)
    fun search(query: String,limit:Int=80): List<CardInfo> {
        val term=query.trim();if(term.isEmpty()||limit<=0)return emptyList()
        return cards.asSequence().filter {it.name.contains(term,true)||it.rules?.contains(term,true)==true}
            .sortedWith(compareBy<CardInfo> {card->
                when {card.name.equals(term,true)->0;card.name.startsWith(term,true)->1;card.name.contains(term,true)->2;else->3}
            }.thenBy {it.name}).take(limit.coerceAtMost(2000)).toList()
    }
    fun resolve(deck: Deck, excludeOtherBoards: Boolean): Obj {
        val extra = deck.entries.filter { it.section !in setOf("deck","commanders","companions") }
        require(extra.isEmpty() || excludeOtherBoards) { "Review and acknowledge excluded sideboard/maybeboard sections before playing." }
        fun section(name: String): List<Obj> = deck.entries.filter { it.section == name }.map { row ->
            val c = find(row.name) ?: throw IllegalArgumentException("Unknown compiled card: ${row.name}. Correct the exact name or export without printing annotations.")
            mapOf("count" to row.quantity, "setCode" to c.set, "collectorNumber" to c.collector, "name" to c.name)
        }
        require(deck.entries.any { it.section == "commanders" }) { "Add a commander section first." }
        val main = section("deck"); val command = section("commanders"); val companions = section("companions")
        return mapOf("name" to deck.name, "main" to main, "commanders" to command, "companions" to companions)
    }
}

fun readBounded(input: InputStream, maximum: Int): ByteArray {
    val out=java.io.ByteArrayOutputStream();val buffer=ByteArray(16384)
    while(true){val n=input.read(buffer);if(n<0)break;if(n==0)continue;require(n<=maximum-out.size()){ "Input exceeds safe size" };out.write(buffer,0,n)}
    return out.toByteArray()
}
