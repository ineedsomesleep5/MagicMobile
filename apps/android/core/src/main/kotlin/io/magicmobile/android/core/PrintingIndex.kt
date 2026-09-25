package io.magicmobile.android.core

import java.io.InputStream

/**
 * The compact name → printing table from printings.tsv. It resolves a deck exactly as
 * Catalogue.resolve does, without loading the full catalogue's rules text and metadata.
 */
class PrintingIndex(input: InputStream) {
    class Printing(val name: String, val setCode: String, val collectorNumber: String)

    val catalogueHash: String
    val upstreamCommit: String
    private val printings = HashMap<String, Printing>(40_000)
    private val aliases = HashMap<String, String>()

    init {
        val lines = input.bufferedReader(Charsets.UTF_8).use { it.readLines() }
        val header = lines.firstOrNull()?.split('\t')
        require(header != null && header.size == 3 && header[0] == "#") { "The card index is incomplete. Update the app." }
        catalogueHash = header[1]; upstreamCommit = header[2]
        require(Regex("^[0-9a-f]{64}$").matches(catalogueHash) && Regex("^[0-9a-f]{40}$").matches(upstreamCommit)) { "The card index is incomplete. Update the app." }
        for (index in 1 until lines.size) {
            val line = lines[index]
            if (line.isEmpty()) continue
            val fields = line.split('\t')
            if (fields.size == 3 && fields[0] == "=") { aliases[fields[1]] = fields[2]; continue }
            require(fields.size == 3 && fields.all { it.isNotEmpty() }) { "The card index is damaged at line ${index + 1}. Update the app." }
            require(printings.put(fields[0], Printing(fields[0], fields[1], fields[2])) == null) { "The card index repeats ${fields[0]}." }
        }
        require(printings.isNotEmpty() && aliases.values.all(printings::containsKey)) { "The card index is incomplete. Update the app." }
    }

    val size: Int get() = printings.size
    fun find(name: String): Printing? = printings[name] ?: aliases[name]?.let(printings::get)

    /** Catalogue.resolve: the engine's deck configuration, rejecting unknown sections and cards. */
    fun resolve(deck: Deck, excludeOtherBoards: Boolean): Obj {
        val extra = deck.entries.filter { it.section !in setOf("deck", "commanders", "companions") }
        val unknown = deck.entries.map { it.section }.filter { it !in DeckEditing.boards }.distinct()
        require(unknown.isEmpty()) { "Map or remove unsupported deck section(s) before playing: ${unknown.joinToString()}. Nothing was silently excluded." }
        require(extra.isEmpty() || excludeOtherBoards) { "Review and acknowledge excluded sideboard/maybeboard sections before playing." }
        fun section(name: String): List<Obj> = deck.entries.filter { it.section == name }.map { row ->
            val c = find(row.name) ?: throw IllegalArgumentException("Unknown compiled card: ${row.name}. Correct the exact name or export without printing annotations.")
            mapOf("count" to row.quantity, "setCode" to c.setCode, "collectorNumber" to c.collectorNumber, "name" to c.name)
        }
        require(deck.entries.any { it.section == "commanders" }) { "Add a commander section first." }
        return mapOf("name" to deck.name, "main" to section("deck"), "commanders" to section("commanders"), "companions" to section("companions"))
    }
}
