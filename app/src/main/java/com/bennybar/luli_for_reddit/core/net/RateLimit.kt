package com.bennybar.luli_for_reddit.core.net

/** Snapshot of Reddit's API rate-limit headers (per OAuth client), taken [at] (millis). */
data class RateLimit(val remaining: Int, val used: Int, val resetSeconds: Int, val at: Long = System.currentTimeMillis()) {
    val total: Int get() = remaining + used

    /** Seconds until this window resets, counted from when it was read. */
    fun secondsLeft(now: Long = System.currentTimeMillis()): Int = (resetSeconds - ((now - at) / 1000).toInt()).coerceAtLeast(0)
}
