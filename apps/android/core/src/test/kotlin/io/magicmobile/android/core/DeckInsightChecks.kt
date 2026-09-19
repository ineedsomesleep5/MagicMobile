package io.magicmobile.android.core

import kotlin.math.abs

fun deckInsightChecks() {
    fun card(text:String,types:List<String> = listOf("INSTANT"),roles:List<String> = emptyList())=CardInfo("Example","T","1",null,text,null,null,types=types,roles=roles)
    check(RoleHints.classify(card("Draw two cards.")).single().role==DeckRole.CARD_FLOW)
    check(RoleHints.classify(card("Whenever a creature dies, draw two cards.")).isEmpty())
    check(RoleHints.classify(card("If you control a creature, draw two cards. Draw a card.")).isEmpty())
    check(RoleHints.classify(card("Choose one —\n• Draw two cards.")).isEmpty())
    check(RoleHints.classify(card("Target creature gains \"{T}: Draw a card.\"")).isEmpty())
    check(RoleHints.classify(card("Scry 1. Draw a card.")).single().role==DeckRole.CARD_FLOW)
    check(RoleHints.classify(card("{T}: Add {G}.",listOf("LAND"))).isEmpty())
    check(RoleHints.classify(card("{T}: Add {G}.",listOf("CREATURE"))).single().role==DeckRole.RAMP)
    check(RoleHints.classify(card("Draw a card.",roles=listOf("tutor")),emptySet()).isEmpty())
    check(RoleHints.classify(card("Draw a card."),setOf(DeckRole.PROTECTION)).single().source=="Your tag")
    val preferences=InsightPreferences(mapOf("Example" to emptySet()),mapOf(DeckRole.RAMP to RoleTarget(5,10)))
    check(InsightPreferences.decode(preferences.encode())==preferences)
    check(preferences.targets.getValue(DeckRole.RAMP).comparison(4)=="Below your target")
    check(runCatching{InsightPreferences.decode("{\"schema\":2}".toByteArray())}.isFailure)
    check(runCatching{RoleTarget(10,5)}.isFailure)
    check(abs(LandDrawProbability.atLeast(1,1,10,1)-0.1)<1e-10)
    check(abs(LandDrawProbability.atLeast(2,2,4,2)-1.0/6)<1e-10)
    check(LandDrawProbability.atLeast(0,0,0,0)==1.0)
    check(LandDrawProbability.atLeast(1,0,10,7)==0.0)
    check(LandDrawProbability.atLeast(7,10,10,7)==1.0)
    check(runCatching{LandDrawProbability.atLeast(3,35,99,100)}.isFailure)
    println("PASS: 20 Android role preference/classification/probability assertions")
}

fun main()=deckInsightChecks()
