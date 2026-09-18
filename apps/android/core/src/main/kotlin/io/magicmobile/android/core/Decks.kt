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

data class CardInfo(val name: String, val set: String, val collector: String, val type: String?, val rules: String?, val cost: String?, val identity: List<String>?)
class Catalogue(input: InputStream) {
    val cards: List<CardInfo>
    private val byName: Map<String, CardInfo>
    private val aliases: Map<String, String>
    val registryHash: String
    init {
        val bytes = input.use { readBounded(it, 48 * 1024 * 1024) }; require(bytes.size <= 48 * 1024 * 1024)
        val lines = bytes.toString(Charsets.UTF_8).lineSequence().filter { it.isNotBlank() }.iterator()
        require(lines.hasNext()); val header = Wire.objectValue(io.magicmobile.core.Json.parseObject(lines.next()))
        registryHash = Wire.string(header["catalogueHash"])
        aliases = header.obj("nameAliases")?.mapValues { Wire.string(it.value) } ?: emptyMap()
        cards = lines.asSequence().map { line ->
            val c = Wire.objectValue(io.magicmobile.core.Json.parseObject(line))
            CardInfo(Wire.string(c["name"]),Wire.string(c["setCode"]),Wire.string(c["collectorNumber"]),c.text("typeLine"),c.text("oracleText"),c.text("manaCost"),c["colorIdentity"]?.let { Wire.list(it).map(Wire::string) })
        }.toList()
        byName = cards.associateBy { it.name }; require(byName.size == cards.size && cards.isNotEmpty())
        require(aliases.values.all { it in byName })
    }
    fun find(name: String): CardInfo? = byName[name] ?: aliases[name]?.let(byName::get)
    fun search(query: String): List<CardInfo> = if(query.isBlank()) emptyList() else cards.asSequence().filter {
        it.name.contains(query,true) || it.rules?.contains(query,true) == true }.take(80).toList()
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
