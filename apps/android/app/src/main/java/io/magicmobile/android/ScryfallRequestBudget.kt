package io.magicmobile.android

import java.util.concurrent.atomic.AtomicLong

private class ProviderFailure(message: String) : IllegalStateException(message)

/** One app-process budget for artwork's api.scryfall.com requests. Deck Studio's search keeps its own (studio/DeckStudioServices.kt). */
internal object ScryfallRequestBudget {
    private const val SPACING_MILLIS = 120L
    private val nextRequestAt = AtomicLong(0)
    private val blockedUntil = AtomicLong(0)
    fun awaitTurn() {
        while (true) {
            val now = System.currentTimeMillis()
            val observed = nextRequestAt.get()
            val due = maxOf(now, observed, blockedUntil.get())
            if (due - now > 2_000) throw ProviderFailure("Scryfall requests are paused after a rate limit. Retry later; no request was sent.")
            if (!nextRequestAt.compareAndSet(observed, due + SPACING_MILLIS)) continue
            if (due > now) Thread.sleep(due - now)
            if (blockedUntil.get() > System.currentTimeMillis()) throw ProviderFailure("Scryfall requests are paused after a rate limit. Retry later; no request was sent.")
            return
        }
    }
    fun backOff(seconds: Int) {
        val until = System.currentTimeMillis() + seconds.coerceIn(1, 3_600) * 1_000L
        blockedUntil.updateAndGet { maxOf(it, until) }
        nextRequestAt.updateAndGet { maxOf(it, until) }
    }
}
