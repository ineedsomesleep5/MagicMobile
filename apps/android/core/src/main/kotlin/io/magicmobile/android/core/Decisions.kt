package io.magicmobile.android.core

data class Choice(val label: String, val type: String, val value: Any?)
object Decisions {
    fun plain(text: String): String = text.replace(Regex("(?is)<(script|style)[^>]*>.*?</\\1>"),"")
        .replace(Regex("(?i)<br\\s*/?>"),"\n").replace(Regex("<[^>]*>"),"")
        .replace("&amp;","&").replace("&lt;","<").replace("&gt;",">").replace("&quot;","\"").replace("&#39;","'")
    fun choices(prompt: Decision, snapshot: Obj?): List<Choice> {
        if(prompt.submitted) return emptyList()
        val p = prompt.payload; val result = mutableListOf<Choice>(); val options = p.obj("options") ?: emptyMap()
        fun bool(label:String,value:Boolean) { if("boolean" in prompt.responseTypes) result += Choice(label,"boolean",value) }
        when(prompt.kind) {
            "ASK" -> { bool(plain(options.text("buttonYes") ?: "Yes / keep"),true); bool(plain(options.text("buttonNo") ?: "No / mulligan"),false) }
            "CHOOSE_PILE" -> { bool("Pile 1",true); bool("Pile 2",false) }
            "CHOOSE_CHOICE","CHOOSE_MODE" -> {
                val choices = p.obj("choices") ?: emptyMap()
                val order = p.array("choiceOrder").mapNotNull { it as? String }.ifEmpty { choices.keys.toList() }
                order.forEach { key -> if(key in choices) result += Choice(plain(choices[key].toString()),if(prompt.kind == "CHOOSE_MODE") "uuid" else "string",key) }
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
                val candidates = p.array("cards").map(Wire::objectValue).associateBy { Wire.string(it["id"]) }
                val possible = options["possibleTargets"]?.let(Wire::list)?.map(Wire::string)
                val chosen = options["chosenTargets"]?.let(Wire::list)?.map(Wire::string) ?: emptyList()
                val allowed = if(possible != null || candidates.isNotEmpty() && "chosenTargets" in options) (possible.orEmpty()+chosen).toSet() else p.array("candidates").map(Wire::string).toSet()
                allowed.forEach { id -> if(Wire.uuid(id)) result += Choice(
                    playerName(snapshot, id) ?: cardLabel(candidates[id], id), "uuid", id) }
                if(options.flag("canCancel") || p["required"] == false) bool("Done / cancel",false)
                val aliases = p.obj("responseAliases") ?: emptyMap()
                aliases.forEach { (alias, base) -> if(base in allowed && Wire.uuid(alias)) result += Choice("Choose alternate face: ${cardLabel(candidates[base], alias)}","uuid",alias) }
            }
            "SELECT","PLAY_MANA","PLAY_X_MANA" -> {
                val specialTargets = (options["possibleAttackers"] ?: options["possibleBlockers"])?.let(Wire::list)?.map(Wire::string)
                if(specialTargets != null) specialTargets.filter(Wire::uuid).forEach { result += Choice(labelForID(snapshot,it),"uuid",it) }
                else {
                    val view = snapshot?.obj("gameView")
                    val playable = view?.obj("canPlayObjects")?.obj("objects") ?: emptyMap()
                    playable.forEach { (id, families) ->
                        val values = Wire.objectValue(families).values.flatMap { it as? List<*> ?: emptyList<Any?>() }.mapNotNull { it as? Map<*, *> }
                        val manaOnly = prompt.kind != "SELECT"
                        if(Wire.uuid(id) && values.any { !manaOnly || it["manaAbility"] == true }) result += Choice(labelForID(snapshot,id),"uuid",id)
                    }
                }
                if(prompt.kind == "SELECT") {
                    bool(if(specialTargets != null) "Done" else "Pass priority",true)
                    if("string" in prompt.responseTypes && options["specialButton"] != null) result += Choice(plain(options["specialButton"].toString()),"string","special")
                }
                else {
                    bool("Cancel payment",false)
                    if("string" in prompt.responseTypes) result += Choice("Special payment","string","special")
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
        return zones.firstNotNullOfOrNull { it[id] }?.let { cardLabel(it,id) } ?: id
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
