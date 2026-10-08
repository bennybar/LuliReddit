package com.bennybar.luli_for_reddit.core

import java.util.Locale

/** Compact formatting helpers for scores, counts and relative time. */
fun compactNumber(n: Int): String = when {
    n >= 1_000_000 -> String.format(Locale.US, "%.1fM", n / 1_000_000.0)
    n >= 1_000 -> String.format(Locale.US, "%.1fk", n / 1_000.0)
    else -> n.toString()
}

/** "5m", "3h", "2d", "4mo", "1y" or "now" since [epochMillis] (UTC). */
fun timeAgo(epochMillis: Long): String {
    val diff = System.currentTimeMillis() - epochMillis
    val minutes = diff / 60_000
    val hours = minutes / 60
    val days = hours / 24
    return when {
        days >= 365 -> "${days / 365}y"
        days >= 30 -> "${days / 30}mo"
        days >= 1 -> "${days}d"
        hours >= 1 -> "${hours}h"
        minutes >= 1 -> "${minutes}m"
        else -> "now"
    }
}
