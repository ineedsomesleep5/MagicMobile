package io.magicmobile.android.core

/** Only public, projected type information is used; unknown permanents stay in support. */
object BattlefieldLayout {
    private val manaEffect=Regex("(?i)^\\s*add\\s+(?:\\{[cwubrg]\\}|(?:one|two|three|\\d+) mana)")
    private fun producesMana(rules:List<String>)=rules.asSequence().flatMap(String::lineSequence).any{line->
        val parts=line.split(':',limit=2)
        if(parts.size!=2)return@any false
        val cost=parts[0].trim().lowercase()
        !cost.startsWith("when ") && !cost.startsWith("whenever ") && !cost.startsWith("at ") &&
            ("{t}" in cost || "sacrifice" in cost || cost.startsWith("tap ")) && manaEffect.containsMatchIn(parts[1])
    }
    data class Rows(val front:List<Obj>,val support:List<Obj>,val landsTop:List<Obj>,val landsBottom:List<Obj>,val rocks:List<Obj>)

    fun rows(cards:List<Obj>,landscape:Boolean):Rows {
        val front=mutableListOf<Obj>();val support=mutableListOf<Obj>()
        val lands=mutableListOf<Obj>();val rocks=mutableListOf<Obj>()
        cards.forEach {card->
            val types=card.array("cardTypes").filterIsInstance<String>().map(String::uppercase).toSet()
            when {
                GameplayPresentation.hidden(card) -> support+=card
                "CREATURE" in types || "PLANESWALKER" in types || "BATTLE" in types || "EQUIPMENT" in card.array("subTypes").filterIsInstance<String>().map(String::uppercase) -> front+=card
                "LAND" in types -> lands+=card
                "ARTIFACT" in types && producesMana(card.array("rules").filterIsInstance<String>()) -> rocks+=card
                else -> support+=card
            }
        }
        return if(landscape && rocks.isEmpty())Rows(front,support,lands.filterIndexed{index,_->index%2==0},lands.filterIndexed{index,_->index%2==1},rocks)
            else Rows(front,support,lands,emptyList(),rocks)
    }
}
