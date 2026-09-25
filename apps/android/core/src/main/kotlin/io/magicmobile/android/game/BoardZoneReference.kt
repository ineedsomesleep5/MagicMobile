package io.magicmobile.android.game

/** Port of BoardZoneReference.swift. Resolves membership from the current snapshot, never a cached card list. */
sealed class BoardZoneReference {
    enum class PlayerZone(val rawValue: String) { LIBRARY("library"), HAND("hand"), BATTLEFIELD("battlefield"), GRAVEYARD("graveyard"),
        EXILE("exile"), COMMAND("command"), STACK("stack") }

    enum class NamedKind(val rawValue: String) {
        EXILE("exile"), COMPANION("companion"), REVEALED("revealed"), LOOKED_AT("lookedAt");
        val title: String get() = if (this == LOOKED_AT) "Looked at" else capitalizedWords(rawValue)
        fun groups(snapshot: GameSnapshot): List<XmageNamedZone> {
            val x = snapshot.xmage ?: return emptyList()
            return when (this) { EXILE -> x.exileZones; COMPANION -> x.companion; REVEALED -> x.revealed; LOOKED_AT -> x.lookedAt }
        }
    }

    data class Player(val playerID: String, val zone: PlayerZone) : BoardZoneReference()
    data class Named(val kind: NamedKind, val id: String) : BoardZoneReference()
    data class Collection(val kind: NamedKind) : BoardZoneReference()
    data class PlayerEnchantments(val playerID: String) : BoardZoneReference()

    fun cards(snapshot: GameSnapshot): List<ZoneCard> = when (this) {
        is PlayerEnchantments -> ZoneCard.enchanting(playerID, snapshot.players.flatMap { it.zones.battlefield })
        is Player -> snapshot.players.firstOrNull { it.playerId == playerID }?.zones?.let { z ->
            when (zone) {
                PlayerZone.LIBRARY -> z.library; PlayerZone.HAND -> z.hand; PlayerZone.BATTLEFIELD -> z.battlefield
                PlayerZone.GRAVEYARD -> z.graveyard; PlayerZone.EXILE -> z.exile; PlayerZone.COMMAND -> z.command; PlayerZone.STACK -> z.stack
            }
        } ?: emptyList()
        is Named -> kind.groups(snapshot).firstOrNull { it.id == id }?.cards ?: emptyList()
        is Collection -> kind.groups(snapshot).flatMap { it.cards }
    }

    fun title(snapshot: GameSnapshot): String = when (this) {
        is PlayerEnchantments -> "Enchanting ${snapshot.playerLabel(playerID)}"
        is Player -> {
            val label = snapshot.players.firstOrNull { it.playerId == playerID }?.displayName?.let { EngineDisplayText.label(it) } ?: ""
            val zoneTitle = capitalizedWords(zone.rawValue) + if (zone == PlayerZone.HAND || zone == PlayerZone.LIBRARY) " — visible cards" else ""
            if (label.isEmpty()) zoneTitle else "$label · $zoneTitle"
        }
        is Named -> kind.groups(snapshot).firstOrNull { it.id == id }?.name?.let { EngineDisplayText.label(it, kind.title) } ?: kind.title
        is Collection -> kind.title
    }

    companion object {
        fun namedReferences(snapshot: GameSnapshot): List<BoardZoneReference> =
            NamedKind.entries.flatMap { kind -> kind.groups(snapshot).map { Named(kind, it.id) } }
    }
}
