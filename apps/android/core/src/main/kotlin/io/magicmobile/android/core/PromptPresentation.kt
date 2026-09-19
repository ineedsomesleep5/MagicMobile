package io.magicmobile.android.core

data class IntegerRangePresentation(val minimum: Long?, val maximum: Long?) {
    val initialValue: String get() = minimum?.toString().orEmpty()
    val label: String get() = when {
        minimum != null && maximum != null -> "$minimum … $maximum"
        minimum != null -> "at least $minimum"
        maximum != null -> "at most $maximum"
        else -> "any amount"
    }

    fun contains(value: Long?): Boolean = value != null &&
        value in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong() &&
        (minimum == null || value >= minimum) &&
        (maximum == null || value <= maximum)
}

object PromptPresentation {
    /** XMage uses the 32-bit endpoints as no-limit sentinels. They remain legal
     * protocol answers, but are not useful as visible bounds or prefilled input. */
    fun integerRange(decision: Decision): IntegerRangePresentation {
        require("integer" in decision.responseTypes)
        val minimum = decision.minimum?.takeIf { it > Int.MIN_VALUE.toLong() }
        val maximum = decision.maximum?.takeIf { it < Int.MAX_VALUE.toLong() }
        return IntegerRangePresentation(minimum, maximum)
    }
}
