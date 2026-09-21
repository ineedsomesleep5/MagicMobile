package io.magicmobile.android.core

/** Displays only the supplied per-viewer projection, never fills redactions from a catalogue. */
object GameplayPresentation {
    fun cards(value: Any?): List<Obj> = when(value) {
        is Map<*, *> -> value.values.mapNotNull { it as? Map<*, *> }.map(Wire::objectValue)
        is List<*> -> value.mapNotNull { it as? Map<*, *> }.map(Wire::objectValue)
        else -> emptyList()
    }

    fun hidden(card: Obj) = card.flag("hideInfo") || card.flag("faceDown")

    fun printedCost(card: Obj): String? {
        if(hidden(card)) return null
        return listOf("manaCostLeftStr","manaCostRightStr").map { key ->
            card.array(key).filterIsInstance<String>().joinToString("") { symbol ->
                if(symbol.startsWith("{")) symbol else "{$symbol}"
            }
        }.filter(String::isNotBlank).joinToString(" // ").takeIf(String::isNotBlank)
    }

    fun details(card: Obj): String {
        if(hidden(card)) return "This card's identity is hidden."
        val type = listOf("superTypes", "cardTypes", "subTypes")
            .map { card.array(it).filterIsInstance<String>().joinToString(" ") }.filter(String::isNotBlank).joinToString(" · ")
        val rules = card.array("rules").filterIsInstance<String>().joinToString("\n")
        return listOf(type, rules).filter(String::isNotBlank).joinToString("\n\n").let(Decisions::plain)
    }

    fun status(card: Obj): String = buildList {
        if(card["phasedIn"]==false)add("Phased out")
        if(!hidden(card) && card.array("cardTypes").any { it is String && it.equals("CREATURE",ignoreCase=true) } && card["power"] != null)
            add("${card["power"]}/${card["toughness"] ?: "?"}")
        if(card.flag("tapped")) add("Tapped")
        if(card.flag("summoningSickness")) add("Summoning sickness")
        card.number("damage")?.takeIf { it > 0 }?.let { add("$it damage") }
        card.array("counters").map(Wire::objectValue).forEach { counter ->
            counter.number("count")?.takeIf { it != 0L }?.let { add("$it ${Decisions.plain(counter.text("name").orEmpty())}") }
        }
    }.joinToString(" · ")
}
