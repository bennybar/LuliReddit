package com.bennybar.luli_for_reddit.settings

import androidx.compose.runtime.Immutable

/**
 * An entry under the side bar's tabs (#109). Persisted by [id] (never change one) in
 * [PREFS_KEY]: their order, a hidden one as "-id". Settings can't be hidden: the
 * side bar may be the only way back in to it.
 */
enum class SideBarItem(val id: String, val label: String) {
    SAVED("saved", "Saved"),
    CUSTOM_FEEDS("customFeeds", "Custom feeds"),
    HISTORY("history", "History"),
    OFFLINE("offline", "Read later"),
    DRAFTS("drafts", "Drafts"),
    SETTINGS("settings", "Settings"),
    RECENTLY_VISITED("recentlyVisited", "Recently visited"),
    FAVORITES("favorites", "Favorites"),
    ;

    companion object {
        const val PREFS_KEY = "sideBarItems"

        /**
         * The stored order: ids it doesn't know are dropped, and items missing from it are
         * added, shown, in their default order (the enum's: the side bar before #109), so
         * entries added later still appear. Settings is always shown.
         */
        fun parse(stored: List<String>?): List<SideBarEntry> {
            val out = mutableListOf<SideBarEntry>()
            for (raw in stored.orEmpty()) {
                val item = SideBarItem.entries.firstOrNull { it.id == raw.removePrefix("-") } ?: continue
                if (out.none { it.item == item }) out += SideBarEntry(item, !raw.startsWith("-") || item == SETTINGS)
            }
            for (item in SideBarItem.entries) if (out.none { it.item == item }) out += SideBarEntry(item, true)
            return out
        }

        fun toPrefs(entries: List<SideBarEntry>): List<String> = entries.map { if (it.shown) it.item.id else "-${it.item.id}" }
    }
}

@Immutable
data class SideBarEntry(val item: SideBarItem, val shown: Boolean)
