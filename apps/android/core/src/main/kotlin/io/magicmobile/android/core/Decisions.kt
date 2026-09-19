package io.magicmobile.android.core

data class Choice(val label: String, val type: String, val value: Any?)
object Decisions {
    private val entities=mapOf("amp" to "&","lt" to "<","gt" to ">","quot" to "\"","apos" to "'","nbsp" to " ","ndash" to "–","mdash" to "—","hellip" to "…","lsquo" to "‘","rsquo" to "’","times" to "×")
    private val entityPattern=Regex("&(#(?:[xX][0-9a-fA-F]+|[0-9]+)|[A-Za-z]+);")
    private val scriptPattern=Regex("(?is)<(script|style)[^>]*>.*?</\\1>")
    private val breakPattern=Regex("(?i)<br\\s*/?>")
    private val tagPattern=Regex("<[^>]*>")
    private val whitespacePattern=Regex("\\s+")
    fun plain(text: String): String {
        var current=text
        while(true) {
            val decoded=entityPattern.replace(current) {match->
                val token=match.groupValues[1]
                entities[token] ?: if(token.startsWith("#"))runCatching {
                    val hex=token.startsWith("#x",true);val value=token.drop(if(hex)2 else 1).toInt(if(hex)16 else 10)
                    if(value<32 && value !in setOf(9,10,13) || value in 127..159 || value in 0x202A..0x202E || value in 0x2066..0x2069)"" else String(Character.toChars(value))
                }.getOrDefault("") else match.value
            }
            val next=decoded.replace(scriptPattern,"")
                .replace(breakPattern,"\n").replace(tagPattern,"")
                .lines().map {it.trim().replace(whitespacePattern," ")}.filter(String::isNotEmpty).joinToString("\n")
            if(next==current)return next
            current=next
        }
    }
    fun choices(prompt: Decision, snapshot: Obj?): List<Choice> {
        if(prompt.submitted) return emptyList()
        val p = prompt.payload; val result = mutableListOf<Choice>(); val options = p.obj("options") ?: emptyMap()
        fun bool(label:String,value:Boolean) { if("boolean" in prompt.responseTypes) result += Choice(label,"boolean",value) }
        when(prompt.kind) {
            // Never invent semantics for a yes/no question. The engine's own button text is
            // used when it supplies one; otherwise the answer is labelled plainly. The old
            // fallbacks read "Yes / keep" and "No / mulligan", which assumed the question was
            // "keep this hand?" — for XMage's actual "Mulligan for free, draw another 7
            // cards?" they told the player the exact opposite of what the button did.
            "ASK" -> {
                bool(plain(options.text("UI.left.btn.text") ?: options.text("buttonYes") ?: "Yes"),true)
                bool(plain(options.text("UI.right.btn.text") ?: options.text("buttonNo") ?: "No"),false)
            }
            "CHOOSE_PILE" -> { bool("Pile 1",true); bool("Pile 2",false) }
            "CHOOSE_CHOICE","CHOOSE_MODE" -> {
                val choices = p.obj("choices") ?: emptyMap()
                val order = p.array("choiceOrder").mapNotNull { it as? String }.ifEmpty { choices.keys.toList() }
                order.forEach { key -> if(key in choices && (prompt.kind!="CHOOSE_MODE" || Wire.uuid(key))) result += Choice(plain(choices[key].toString()),if(prompt.kind == "CHOOSE_MODE") "uuid" else "string",key) }
                p.obj("specialChoices")?.forEach { (key,label) -> if(p.flag("specialEnabled")) result += Choice("Special: ${plain(label.toString())}","string",key) }
                if(p.flag("specialEnabled") && p.flag("specialCanBeEmpty")) result += Choice("Special: none","string",null)
                if(p["required"] == false && prompt.kind == "CHOOSE_CHOICE") result += Choice("Cancel","string", "")
            }
            "CHOOSE_ABILITY","PICK_ABILITY" -> {
                p.array("abilities").forEach { raw -> val a = Wire.objectValue(raw); val id = a.text("id")
                    if(id != null && Wire.uuid(id)) result += Choice(plain(a.text("label") ?: a.text("value") ?: "Ability"),"uuid",id) }
                if(p["required"] == false || options.flag("canCancel")) bool("Cancel",false)
            }
            "PICK_TARGET" -> {
                val candidates = (options.array("orderedViews")+p.array("cards")).map(Wire::objectValue).associateBy { Wire.string(it["id"]) }
                val possible = options["possibleTargets"]?.let(Wire::list)?.map(Wire::string)
                val chosen = options["chosenTargets"]?.let(Wire::list)?.map(Wire::string) ?: emptyList()
                val allowed = if(possible != null || candidates.isNotEmpty() && "chosenTargets" in options) (possible.orEmpty()+chosen).toSet() else p.array("candidates").map(Wire::string).toSet()
                allowed.forEach { id -> if(Wire.uuid(id)) result += Choice(
                    playerName(snapshot, id) ?: cardLabel(candidates[id], labelForID(snapshot,id)), "uuid", id) }
                if(options.flag("canCancel") || p["required"] == false) bool("Done / cancel",false)
                val aliases = p.obj("responseAliases") ?: emptyMap()
                aliases.forEach { (alias, base) -> if(base in allowed && Wire.uuid(alias)) {
                    val card=candidates[base]
                    // Face aliases are authorized responses, but a redacted base must
                    // never reveal its nested face identity.
                    val face=card?.takeUnless(GameplayPresentation::hidden)?.obj("secondCardFace")?.takeIf { it["id"]==alias }
                    val label=if(face!=null)cardLabel(face) else "Alternate face"
                    result += Choice("Choose alternate face: $label","uuid",alias)
                } }
            }
            "SELECT","PLAY_MANA","PLAY_X_MANA" -> {
                val specialTargets = (options["possibleAttackers"] ?: options["possibleBlockers"])?.let(Wire::list)?.map(Wire::string)
                if(specialTargets != null) {
                    val selectable = specialTargets.toMutableSet()
                    // XMage removes declared attackers from possibleAttackers. Keep the
                    // current acting player's declared attackers available for deselection.
                    if(p.text("selectMode") == "attackers") {
                        val view = snapshot?.obj("gameView")
                        val active = view?.text("activePlayerId")
                        val controlled = active?.let { snapshot?.obj("controlledPlayerViews")?.obj(it) }
                        if(active != null && (active == snapshot?.text("enginePlayerId") ||
                            controlled?.text("myPlayerId") == active && controlled?.text("activePlayerId") == active)) {
                            val battlefield = view?.array("players").orEmpty().map(Wire::objectValue)
                                .find { it["playerId"] == active }?.obj("battlefield").orEmpty()
                            view?.array("combat").orEmpty().map(Wire::objectValue).forEach { group ->
                                GameplayPresentation.cards(group["attackers"]).forEach { card ->
                                    card.text("id")?.takeIf { it in battlefield }?.let(selectable::add)
                                }
                            }
                        }
                    }
                    selectable.filter(Wire::uuid).forEach { result += Choice(labelForID(snapshot,it),"uuid",it) }
                }
                else {
                    val view = snapshot?.obj("gameView")
                    val playable = view?.obj("canPlayObjects")?.obj("objects") ?: emptyMap()
                    playable.forEach { (id, families) ->
                        val manaOnly = prompt.kind != "SELECT"
                        val values = Wire.objectValue(families).flatMap { (family,rows) ->
                            (rows as? List<*>).orEmpty().mapNotNull { it as? Map<*, *> }
                                .filter { !manaOnly || (it["manaAbility"] as? Boolean ?: (family == "basicManaAbilities")) }
                        }
                        if(Wire.uuid(id) && values.isNotEmpty()) {
                            val action = values.first()["value"]?.toString()?.let(::plain)
                            result += Choice(action?.takeIf { it.isNotBlank() } ?: labelForID(snapshot,id),"uuid",id)
                        }
                    }
                }
                if(prompt.kind == "SELECT") {
                    bool(if(specialTargets != null) "Done" else "Pass priority",true)
                    if("string" in prompt.responseTypes && options["specialButton"] != null) result += Choice(plain(options["specialButton"].toString()),"string","special")
                }
                else {
                    bool("Cancel payment",false)
                    if(prompt.kind == "PLAY_MANA" && "string" in prompt.responseTypes) result += Choice("Special payment","string","special")
                    val manaPlayer = p.text("manaPlayerId")
                    val players = snapshot?.obj("gameView")?.array("players").orEmpty().map(Wire::objectValue)
                    val pool = players.find { it["playerId"] == manaPlayer }?.obj("manaPool")
                    if(manaPlayer != null && pool != null && "mana" in prompt.responseTypes) {
                        listOf("WHITE","BLUE","BLACK","RED","GREEN","COLORLESS","GENERIC").forEach { color ->
                            if((pool.number(color.lowercase()) ?: 0) > 0) result += Choice("Use floating $color","mana",mapOf("playerId" to manaPlayer,"manaType" to color))
                        }
                    }
                }
            }
            "MULTI_AMOUNT" -> if(options.flag("canCancel")) bool("Cancel",false)
        }
        return result.filter { it.type in prompt.responseTypes }.distinctBy { it.type to it.value }
    }
    fun cardLabel(value: Any?, fallback: String = "Card"): String {
        val c = value as? Map<*,*> ?: return fallback
        if(c["hideInfo"] == true || c["faceDown"] == true) return "Face-down card"
        return plain((c["displayName"] ?: c["name"] ?: fallback).toString())
    }
    fun labelForID(snapshot: Obj?, id: String): String {
        val g = snapshot?.obj("gameView") ?: return id
        playerName(snapshot, id)?.let { return it }
        val zones = mutableListOf<Obj>(); g.obj("myHand")?.let(zones::add); g.obj("stack")?.let(zones::add)
        g.array("players").map(Wire::objectValue).forEach { p -> listOf("battlefield","graveyard","exile").forEach { p.obj(it)?.let(zones::add) } }
        zones.firstNotNullOfOrNull { it[id] }?.let { return cardLabel(it,id) }
        val extras = g.array("players").map(Wire::objectValue).flatMap { GameplayPresentation.cards(it["commandList"]) } +
            listOf("revealed","companion").flatMap { key -> g.array(key).map(Wire::objectValue).flatMap { GameplayPresentation.cards(it["cards"]) } } +
            snapshot.array("namedExiles").map(Wire::objectValue).flatMap { GameplayPresentation.cards(it["cards"]) } +
            listOf("authorizedLookedAt","authorizedOpponentHands").flatMap { key -> snapshot.obj(key).orEmpty().values.flatMap(GameplayPresentation::cards) }
        return extras.firstOrNull { it["id"] == id }?.let { cardLabel(it,id) } ?: id
    }

    /** Some prompts target players rather than cards; "Select a starting player" is one.
     *  Without this the choice buttons read as raw UUIDs. */
    fun playerName(snapshot: Obj?, id: String): String? {
        val players = snapshot?.obj("gameView")?.array("players").orEmpty().map(Wire::objectValue)
        val match = players.find { it["playerId"] == id } ?: return null
        val name = (match["name"] ?: match["displayName"])?.toString()?.let(::plain)
        return name?.takeIf { it.isNotBlank() }
    }
}
