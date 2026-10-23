package io.magicmobile.android.game

/**
 * The custom table's rules as Arena's event page applies them (iOS OnDeviceRootView.swift `setupSeats`, `addAISeat`,
 * `removeAISeat`, `setupStartBar`): up to three AI seats shown as deck boxes, a seat that comes back with the deck it last
 * had, and a strip that speaks only when the table is doing something.
 */
object ArenaCustomTable {
    const val MAX_AI_SEATS = 3

    /** The idle setup line; the strip shows nothing for it, since the page already shows what it says. */
    const val IDLE_STATUS = "Choose your deck and players."

    /** The AI seats on the plate: always at least one, never more than three. */
    fun seatCount(opponentCount: Int): Int = opponentCount.coerceIn(1, MAX_AI_SEATS)

    /** The "+" seat shows while a seat is free. */
    fun canAddSeat(opponentCount: Int): Boolean = opponentCount < MAX_AI_SEATS

    /** A seat's × shows while more than one seat is taken. */
    fun canRemoveSeat(opponentCount: Int): Boolean = opponentCount > 1

    /** What the strip along the foot says for the setup's status. */
    fun stripStatus(status: String): String = if (status == IDLE_STATUS) "" else status

    /**
     * Adds a seat. It comes back with the deck it last had; a seat whose deck is gone gets the first precon not already at
     * the table (else [fallback]). Returns the three seat deck ids and the new count, or null when the table is full.
     */
    fun addSeat(ids: List<String>, opponentCount: Int, available: Set<String>, precons: List<String>, fallback: String): Pair<List<String>, Int>? {
        if (!canAddSeat(opponentCount)) return null
        val seats = padded(ids)
        val index = opponentCount.coerceAtLeast(0)
        if (seats[index] !in available) {
            val taken = seats.take(index).toSet()
            seats[index] = precons.firstOrNull { it !in taken } ?: fallback
        }
        return seats to index + 1
    }

    /**
     * Empties a seat: its deck waits just past the remaining seats, so adding a seat brings it back. Returns the three seat
     * deck ids and the new count, or null when the seat can't be emptied.
     */
    fun removeSeat(ids: List<String>, opponentCount: Int, index: Int): Pair<List<String>, Int>? {
        if (!canRemoveSeat(opponentCount) || index !in 0 until opponentCount) return null
        val seats = padded(ids)
        val removed = seats.removeAt(index)
        seats.add(opponentCount - 1, removed)
        return seats to opponentCount - 1
    }

    private fun padded(ids: List<String>): MutableList<String> =
        (ids.take(MAX_AI_SEATS) + List(maxOf(0, MAX_AI_SEATS - ids.size)) { "" }).toMutableList()
}
