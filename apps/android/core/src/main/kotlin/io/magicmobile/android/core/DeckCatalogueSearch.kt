package io.magicmobile.android.core

object DeckCatalogueSearch {
    fun search(cards:List<CardInfo>,query:String="",type:String="",setCode:String="",minimum:Double?=null,maximum:Double?=null,allowedIdentity:Set<String>?=null,limit:Int=80):List<CardInfo> {
        require(minimum==null||minimum.isFinite()&&minimum>=0){"Use a nonnegative minimum mana value."}
        require(maximum==null||maximum.isFinite()&&maximum>=0){"Use a nonnegative maximum mana value."}
        require(minimum==null||maximum==null||minimum<=maximum){"Minimum mana value must not exceed maximum."}
        require(allowedIdentity==null||setOf("W","U","B","R","G").containsAll(allowedIdentity))
        val term=query.trim();val edition=setCode.trim()
        return cards.asSequence().filter {card->
            (term.isEmpty()||card.name.contains(term,true)||card.rules?.contains(term,true)==true)&&
            (type.isEmpty()||card.types?.any{it.equals(type,true)}==true)&&
            (edition.isEmpty()||card.set.equals(edition,true)||card.setCodes.any{it.equals(edition,true)})&&
            (minimum==null||card.manaValue?.let{it>=minimum}==true)&&
            (maximum==null||card.manaValue?.let{it<=maximum}==true)&&
            (allowedIdentity==null||card.identity?.all{it in allowedIdentity}==true)
        }.sortedWith(compareBy<CardInfo>{when{it.name.equals(term,true)->0;it.name.startsWith(term,true)->1;it.name.contains(term,true)->2;else->3}}.thenBy{it.name})
            .take(limit.coerceIn(0,2000)).toList()
    }
}
