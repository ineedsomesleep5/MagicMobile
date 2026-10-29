package io.magicmobile.android.laws

import kotlin.random.Random

/**
 * Laws: properties that must hold for every input, checked against many seeded random ones (docs/LAWS.md). A failure names
 * its seed and case, so `forAll(seed = <that seed>)` replays it exactly. No library: a plain seeded loop over JUnit.
 */
object Laws {
    /** A deeper local run: `gradlew :core:test -Plaws.runs=20000 --tests "io.magicmobile.android.laws.*"`. CI keeps the default. */
    val defaultRuns: Int = System.getProperty("laws.runs")?.toIntOrNull() ?: 500

    fun forAll(name: String, runs: Int = defaultRuns, seed: Long = 0x4D61676963L, check: (Random) -> Unit) {
        for (case in 0 until runs) {
            val caseSeed = seed + case
            try {
                check(Random(caseSeed))
            } catch (failure: Throwable) {
                throw AssertionError("Law '$name' broke on case $case (seed $caseSeed): ${failure.message}", failure)
            }
        }
    }

    fun <T> Random.pick(values: List<T>): T = values[nextInt(values.size)]
}
