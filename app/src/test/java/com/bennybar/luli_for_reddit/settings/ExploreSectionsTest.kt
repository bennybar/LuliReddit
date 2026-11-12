package com.bennybar.luli_for_reddit.settings

import org.junit.Assert.assertEquals
import org.junit.Test

/** Settings › Explore sections (#161): stored order, hidden sections, defaults. */
class ExploreSectionsTest {
    private fun ids(entries: List<ExploreEntry>) = entries.map { (if (it.shown) "" else "-") + it.section.id }

    @Test
    fun `never set it is Explore from before`() {
        assertEquals(
            listOf("popular", "customFeeds", "recentlyVisited", "recommended", "popularCommunities", "favorites", "following"),
            ids(ExploreSection.parse(null)),
        )
        assertEquals(ExploreSection.parse(null), Settings().exploreSections)
    }

    @Test
    fun `stored order and hidden sections are kept, missing ones appended in default order`() {
        assertEquals(
            listOf("recommended", "-customFeeds", "popular", "recentlyVisited", "popularCommunities", "favorites", "following"),
            ids(ExploreSection.parse(listOf("recommended", "-customFeeds", "popular"))),
        )
    }

    @Test
    fun `unknown and repeated ids are dropped`() {
        assertEquals(
            listOf("favorites", "popular", "customFeeds", "recentlyVisited", "recommended", "popularCommunities", "following"),
            ids(ExploreSection.parse(listOf("trending", "favorites", "-favorites"))),
        )
    }

    @Test
    fun `a section added later shows up for someone who already reordered`() {
        assertEquals(
            listOf("-popular", "following", "favorites", "customFeeds", "recentlyVisited", "recommended", "popularCommunities"),
            ids(ExploreSection.parse(listOf("-popular", "following", "favorites", "customFeeds", "recentlyVisited", "recommended"))),
        )
    }

    @Test
    fun `prefs round trip`() {
        val stored = listOf("-popular", "recommended", "recentlyVisited", "-customFeeds", "following", "-popularCommunities", "favorites")
        assertEquals(stored, ExploreSection.toPrefs(ExploreSection.parse(stored)))
    }
}
