package io.magicmobile.android.game

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Mirrors the GameStats cases in Build19LogicTests.swift. */
class GameStatsTest {
    private fun text(vararg values: String) = JsonArray(values.map { JsonPrimitive(it) })

    private fun creature(id: String, name: String, power: Int, identity: JsonObject? = null) = jsonObject(
        "instanceId" to JsonPrimitive(id),
        "card" to (identity ?: jsonObject("name" to JsonPrimitive(name), "typeLine" to JsonPrimitive("Creature — Bear"), "oracleText" to JsonPrimitive(""))),
        "power" to JsonPrimitive(power), "toughness" to JsonPrimitive(power), "isCreaturePermanent" to JsonPrimitive(true), "tapped" to JsonPrimitive(false))

    private fun snapshot(game: String = "g", turn: Int = 3, lives: Map<String, Int>, battlefield: Map<String, List<J>>,
                         graveyard: Map<String, List<J>> = emptyMap(), combat: List<J> = emptyList()): GameSnapshot {
        val players = listOf("me", "them").map { id ->
            jsonObject("playerId" to JsonPrimitive(id), "displayName" to JsonPrimitive(if (id == "me") "Me" else "Them"),
                "life" to JsonPrimitive(lives[id] ?: 40), "poison" to JsonPrimitive(0), "commanderTax" to JsonPrimitive(0),
                "zones" to jsonObject("hand" to JsonArray(emptyList()), "battlefield" to JsonArray(battlefield[id] ?: emptyList()),
                    "graveyard" to JsonArray(graveyard[id] ?: emptyList()), "exile" to JsonArray(emptyList()), "library" to JsonArray(emptyList()),
                    "command" to JsonArray(emptyList()), "stack" to JsonArray(emptyList())))
        }
        val panels = jsonObject("stack" to JsonPrimitive(false), "command" to JsonPrimitive(true), "graveyard" to JsonPrimitive(true),
            "exile" to JsonPrimitive(true), "revealed" to JsonPrimitive(false), "lookedAt" to JsonPrimitive(false), "search" to JsonPrimitive(false))
        val empty = JsonArray(emptyList())
        val xmage = jsonObject("schemaVersion" to JsonPrimitive(1), "gameId" to JsonPrimitive(game), "bridgeRevision" to JsonPrimitive(1),
            "callbackCoverage" to empty, "stack" to empty, "combat" to JsonArray(combat), "players" to empty, "exileZones" to empty,
            "revealed" to empty, "lookedAt" to empty, "companion" to empty, "playableObjects" to empty, "panels" to panels)
        val root = jsonObject("id" to JsonPrimitive(game), "phase" to JsonPrimitive("COMBAT"), "turn" to JsonPrimitive(turn), "log" to empty,
            "legalActions" to empty, "viewerPlayerId" to JsonPrimitive("me"), "players" to JsonArray(players), "xmage" to xmage)
        return EngineJson.format.decodeFromJsonElement(GameSnapshot.serializer(), root)
    }

    private fun attack(blocked: Boolean, vararg attackers: J) = jsonObject("defenderId" to JsonPrimitive("them"), "defenderName" to JsonPrimitive("Them"),
        "blocked" to JsonPrimitive(blocked), "attackers" to JsonArray(attackers.toList()), "blockers" to JsonArray(emptyList()))

    @Test fun summaryCreditsUnblockedAttackersAndCountsDeaths() {
        val bear = creature("bear", "Grizzly Bears", 3); val cub = creature("cub", "Bear Cub", 2)
        val wall = creature("wall", "Wall of Wood", 0)
        val board = mapOf("me" to listOf<J>(bear, cub), "them" to listOf<J>(wall))
        val swing = listOf<J>(attack(false, bear, cub))
        val stats = GameStats()
        stats.record(snapshot(lives = mapOf("me" to 40, "them" to 40), battlefield = board))
        stats.record(snapshot(lives = mapOf("me" to 40, "them" to 40), battlefield = board, combat = swing))
        stats.record(snapshot(lives = mapOf("me" to 40, "them" to 35), battlefield = board, combat = swing))
        assertEquals(5, stats.combatDamage)
        assertEquals(5, stats.biggestHit)
        assertEquals("Grizzly Bears", stats.topCard?.name)
        assertEquals(3, stats.topCard?.damage)
        // The same combat staying on screen is not credited twice.
        stats.record(snapshot(lives = mapOf("me" to 40, "them" to 35), battlefield = board, combat = swing))
        assertEquals(5, stats.combatDamage)
        stats.record(snapshot(turn = 4, lives = mapOf("me" to 38, "them" to 35), battlefield = mapOf("me" to listOf<J>(bear), "them" to emptyList()),
            graveyard = mapOf("me" to listOf<J>(cub), "them" to listOf<J>(wall))))
        assertEquals(1, stats.creaturesDestroyed)
        assertEquals(1, stats.creaturesLost)
        assertEquals(4, stats.turns)
        assertEquals(38, stats.finalLife)
        stats.record(snapshot(game = "next", turn = 1, lives = mapOf("me" to 40, "them" to 40), battlefield = emptyMap()))
        assertEquals("a new game starts a new summary", 0, stats.combatDamage)
        assertNull(stats.topCard)
        assertEquals(emptyMap<String, ZoneCard>(), stats.cardByName)
    }

    @Test fun blockedAttacksAndOtherLifeLossAreNotCombatCredit() {
        val bear = creature("bear", "Grizzly Bears", 3)
        val blocked = listOf<J>(attack(true, bear))
        val stats = GameStats()
        stats.record(snapshot(lives = mapOf("me" to 40, "them" to 40), battlefield = mapOf("me" to listOf<J>(bear)), combat = blocked))
        stats.record(snapshot(lives = mapOf("me" to 40, "them" to 37), battlefield = mapOf("me" to listOf<J>(bear)), combat = blocked))
        stats.record(snapshot(lives = mapOf("me" to 40, "them" to 30), battlefield = mapOf("me" to listOf<J>(bear))))
        assertEquals(0, stats.combatDamage)
        assertNull(stats.topCard)
    }

    @Test fun tokenTopAttackerKeepsItsBattlefieldCardForArt() {
        val template = jsonObject("name" to JsonPrimitive("Squirrel"), "typeLine" to JsonPrimitive("Token Creature — Squirrel"),
            "oracleText" to JsonPrimitive(""), "power" to JsonPrimitive("1"), "toughness" to JsonPrimitive("1"), "colors" to text("G"))
        val face = mapOf("name" to JsonPrimitive("Squirrel Token"), "typeLine" to JsonPrimitive("Token Creature — Squirrel"),
            "oracleText" to JsonPrimitive(""), "isToken" to JsonPrimitive(true))
        val squirrel = creature("squirrel", "Squirrel Token", 4, jsonObject(face + mapOf("tokenColors" to text("G"), "tokenArtwork" to template)))
        // XMage's combat group carries the same card without the token template.
        val swinging = creature("squirrel", "Squirrel Token", 4, jsonObject(face))
        val bear = creature("bear", "Grizzly Bears", 1)
        val swing = listOf<J>(attack(false, swinging, bear))
        val stats = GameStats()
        stats.record(snapshot(lives = mapOf("me" to 40, "them" to 40), battlefield = mapOf("me" to listOf<J>(squirrel, bear)), combat = swing))
        stats.record(snapshot(lives = mapOf("me" to 40, "them" to 35), battlefield = mapOf("me" to listOf<J>(squirrel, bear))))
        val top = stats.topCard!!
        assertEquals("the result screen drops the Token suffix", "Squirrel", top.name)
        assertEquals(4, top.damage)
        assertEquals("matched by instance ID", "squirrel", top.card?.instanceId)
        assertEquals("the battlefield card carries the art template", "Squirrel", top.card?.card?.tokenArtwork?.name)
        assertEquals("credit stays keyed by the engine name", 4, stats.damageByCard["Squirrel Token"])
    }

    @Test fun tokenDisplayNameDropsOnlyATrailingTokenWord() {
        assertEquals("Squirrel", GameStats.tokenDisplayName("Squirrel Token"))
        assertEquals("Food", GameStats.tokenDisplayName(" Food token "))
        assertEquals("Token", GameStats.tokenDisplayName("Token"))
        assertEquals("Grizzly Bears", GameStats.tokenDisplayName("Grizzly Bears"))
    }
}
