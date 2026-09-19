package io.magicmobile.android.core

import java.text.Normalizer
import java.util.Locale
import kotlin.math.exp
import kotlin.math.ln

data class RoleTarget(val lower: Int, val upper: Int) {
    init { require(lower in 0..2000 && upper in lower..2000) }
    fun comparison(count: Int) = when { count < lower -> "Below your target"; count > upper -> "Above your target"; else -> "Within your target" }
}

/** Auxiliary local preferences. These are never sent in the XMage deck payload. */
data class InsightPreferences(
    val overrides: Map<String, Set<DeckRole>> = emptyMap(),
    val targets: Map<DeckRole, RoleTarget> = emptyMap(),
) {
    init { require(overrides.size <= 2000 && overrides.keys.all { it.isNotBlank() && it.toByteArray().size <= 2000 }) }
    fun encode(): ByteArray = Wire.encode(mapOf("schema" to 1,
        "overrides" to overrides.mapValues { it.value.map(DeckRole::key) },
        "targets" to targets.mapKeys { it.key.key }.mapValues { mapOf("lower" to it.value.lower,"upper" to it.value.upper) }))
        .also { require(it.size <= 512 * 1024) }
    companion object {
        fun decode(bytes: ByteArray): InsightPreferences {
            require(bytes.size <= 512 * 1024)
            val root=Wire.decode(bytes);require(root.number("schema")==1L)
            val overrides=root.obj("overrides").orEmpty().mapValues { (_,value) ->
                Wire.list(value).map { requireNotNull(DeckRole.fromKey(Wire.string(it))) }.toSet()
            }
            val targets=root.obj("targets").orEmpty().map { (key,value) ->
                val row=Wire.objectValue(value);val lower=Wire.integer(row["lower"]);val upper=Wire.integer(row["upper"])
                require(lower in 0..2000 && upper in lower..2000)
                requireNotNull(DeckRole.fromKey(key)) to RoleTarget(lower.toInt(),upper.toInt())
            }.toMap()
            return InsightPreferences(overrides,targets)
        }
    }
}

data class RoleEvidence(val role: DeckRole, val source: String)
data class InsightCard(val name: String, val quantity: Int, val evidence: List<RoleEvidence>, val reviewed: Boolean)
data class DeckInsights(val cards: List<InsightCard>, val symbols: Map<String,Int>, val types: Map<String,Int>, val missingCostCount: Int) {
    fun count(role: DeckRole)=cards.filter { card -> card.evidence.any { it.role==role } }.sumOf { it.quantity }
    val unclassifiedCount get()=cards.filter { it.evidence.isEmpty() }.sumOf { it.quantity }
    companion object {
        fun analyze(deck: Deck, catalogue: Catalogue, preferences: InsightPreferences): DeckInsights {
            val rows=deck.entries.filter { it.section=="deck" };require(rows.sumOf { it.quantity.toLong() } <= 2000)
            val symbols=sortedMapOf<String,Int>();val types=sortedMapOf<String,Int>();var missing=0
            val cards=rows.groupBy { catalogue.find(it.name)?.name ?: it.name }.toSortedMap().map { (name,group) ->
                val card=catalogue.find(name);val quantity=group.sumOf { it.quantity }
                card?.types.orEmpty().forEach { types[it]=types.getOrDefault(it,0)+quantity }
                if(card?.cost==null)missing+=quantity else Regex("\\{([^{}]+)\\}").findAll(card.cost).forEach {
                    val symbol=it.groupValues[1];if(symbol!="*")symbols[symbol]=symbols.getOrDefault(symbol,0)+quantity
                }
                InsightCard(name,quantity,RoleHints.classify(card,preferences.overrides[name]),name in preferences.overrides)
            }
            return DeckInsights(cards,symbols,types,missing)
        }
    }
}

/** Same conservative clauses as iOS: a trigger, condition, modal or granted ability
 * is not flattened into a promise that the deck contains that effect. */
object RoleHints {
    private val rules=listOf(
        DeckRole.RAMP to "^\\{t\\}: add (?:\\{[wubrgc]\\})+\\.",
        DeckRole.RAMP to "^\\{t\\}: add one mana of any color(?: in your commander's color identity)?\\.",
        DeckRole.RAMP to "^search your library for (?:a|up to two) basic land cards?, (?:reveal (?:it|them), )?put (?:it|one of them) onto the battlefield",
        DeckRole.CARD_FLOW to "^draw (?:a|two|three|four|five|six|seven|[1-9][0-9]?) cards?\\.",
        DeckRole.INTERACTION to "^(?:destroy|exile) target (?:creature|artifact|enchantment|permanent)(?: or (?:creature|artifact|enchantment))?\\.",
        DeckRole.INTERACTION to "^counter target (?:noncreature )?spell\\.",
        DeckRole.BOARD_WIPE to "^(?:destroy|exile) all creatures\\.",
        DeckRole.PROTECTION to "^permanents you control gain hexproof and indestructible until end of turn\\.",
        DeckRole.GRAVEYARD_HATE to "^exile (?:all cards from all graveyards|target card from a graveyard|target player's graveyard)\\.",
        DeckRole.RECURSION to "^return target (?:(?:creature|artifact|enchantment|permanent) )?card from your graveyard to (?:your hand|the battlefield)\\.",
        DeckRole.TUTOR to "^search your library for a card, put that card into your hand, then shuffle\\."
    ).map { it.first to Regex(it.second) }
    private val conditional=Regex("\\b(?:when|whenever|at the beginning|at the end|if|unless|activate only|activate (?:as|during)|only any time)\\b")
    fun clauses(text: String): List<String> {
        if(text.toByteArray().size>32768)return emptyList()
        val normalized=Normalizer.normalize(Decisions.plain(text),Normalizer.Form.NFC).lowercase(Locale.ROOT).replace('’','\'')
        var depth=0;val clean=StringBuilder()
        for(c in normalized) when(c) {
            '(' -> {depth++;clean.append(' ')}
            ')' -> {if(depth==0)return emptyList();depth--}
            else -> if(depth==0)clean.append(c)
        }
        if(depth!=0 || clean.any { it in "\"“”•" } || Regex("\\bchoose (?:one|two|three|four|any)\\b").containsMatchIn(clean))return emptyList()
        fun tidy(s:String)=s.trim().replace(Regex("\\s+")," ").let { if(it.isEmpty() || it.endsWith('.'))it else "$it." }
        return clean.lines().filterNot { conditional.containsMatchIn(it) }.flatMap { line ->
            (listOf(line)+line.split('.',';')).flatMap { candidate ->
                listOf(tidy(candidate))+if(':' in candidate)listOf(tidy(candidate.substringAfter(':')))else emptyList()
            }
        }.filter(String::isNotEmpty).distinct().takeIf { it.size<=512 }.orEmpty()
    }
    fun classify(card: CardInfo?, reviewed: Set<DeckRole>?=null): List<RoleEvidence> {
        if(reviewed!=null)return DeckRole.entries.filter { it in reviewed }.map { RoleEvidence(it,"Your tag") }
        val result=linkedMapOf<DeckRole,String>()
        card?.roles.orEmpty().mapNotNull(DeckRole::fromKey).forEach { result[it]="Curated tag" }
        val clauses=card?.rules?.let(::clauses).orEmpty()
        rules.forEach { (role,pattern) ->
            if(role !in result && (role!=DeckRole.RAMP || card?.types?.let { "LAND" !in it }==true) && clauses.any(pattern::containsMatchIn))result[role]="Text-pattern hint"
        }
        return DeckRole.entries.mapNotNull { role -> result[role]?.let { RoleEvidence(role,it) } }
    }
}

object LandDrawProbability {
    /** Hypergeometric sampling without replacement. No mulligans or play decisions. */
    fun atLeast(threshold:Int, successes:Int, population:Int, draws:Int):Double {
        require(population in 0..2000 && successes in 0..population && draws in 0..population)
        val low=maxOf(0,draws-(population-successes));val high=minOf(successes,draws)
        if(threshold<=low)return 1.0
        if(threshold>high)return 0.0
        fun logChoose(n:Int,k:Int):Double {val count=minOf(k,n-k);return (1..count).sumOf { ln((n-count+it).toDouble())-ln(it.toDouble()) }}
        val denominator=logChoose(population,draws)
        return (threshold..high).sumOf { hits -> exp(logChoose(successes,hits)+logChoose(population-successes,draws-hits)-denominator) }.coerceIn(0.0,1.0)
    }
}
