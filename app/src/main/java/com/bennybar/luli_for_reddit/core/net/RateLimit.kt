package com.bennybar.luli_for_reddit.core.net

/** Snapshot of Reddit's API rate-limit headers (per OAuth client). */
data class RateLimit(val remaining: Int, val used: Int, val resetSeconds: Int) {
    val total: Int get() = remaining + used
}
