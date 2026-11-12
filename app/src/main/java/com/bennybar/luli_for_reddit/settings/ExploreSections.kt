package com.bennybar.luli_for_reddit.settings

import androidx.compose.runtime.Immutable

/**
 * A section of the Explore tab (#161). Persisted by [id] (never change one) in
 * [PREFS_KEY]: their order, a hidden one as "-id". Your communities aren't one:
 * they stay last, with the filter and sort.
 */
enum class ExploreSection(val id: String, val label: String) {
    POPULAR("popular", "Popular & All"),
    CUSTOM_FEEDS("customFeeds", "Custom feeds"),
    RECENTLY_VISITED("recentlyVisited", "Recently visited"),
    RECOMMENDED("recommended", "Recommended for you"),
    POPULAR_COMMUNITIES("popularCommunities", "Popular communities"),
    FAVORITES("favorites", "Favorites"),
    FOLLOWING("following", "Following"),
    ;

    /** A list of your communities: these sit under the filter, and give way to its results. */
    val isCommunityList get() = this == RECENTLY_VISITED || this == RECOMMENDED || this == FAVORITES || this == FOLLOWING

    companion object {
        const val PREFS_KEY = "exploreSections"

        /**
         * The stored order: ids it doesn't know are dropped, and sections missing from it
         * are added, shown, in their default order (the enum's: Explore before #161), so
         * sections added later still appear.
         */
        fun parse(stored: List<String>?): List<ExploreEntry> {
            val out = mutableListOf<ExploreEntry>()
            for (raw in stored.orEmpty()) {
                val section = ExploreSection.entries.firstOrNull { it.id == raw.removePrefix("-") } ?: continue
                if (out.none { it.section == section }) out += ExploreEntry(section, !raw.startsWith("-"))
            }
            for (section in ExploreSection.entries) if (out.none { it.section == section }) out += ExploreEntry(section, true)
            return out
        }

        fun toPrefs(entries: List<ExploreEntry>): List<String> = entries.map { if (it.shown) it.section.id else "-${it.section.id}" }
    }
}

@Immutable
data class ExploreEntry(val section: ExploreSection, val shown: Boolean)
