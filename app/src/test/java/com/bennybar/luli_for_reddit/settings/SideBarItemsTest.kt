package com.bennybar.luli_for_reddit.settings

import org.junit.Assert.assertEquals
import org.junit.Test

/** Settings › Side bar entries (#109): stored order, hidden entries, defaults. */
class SideBarItemsTest {
    private fun ids(entries: List<SideBarEntry>) = entries.map { (if (it.shown) "" else "-") + it.item.id }

    @Test
    fun `never set it is the side bar from before`() {
        assertEquals(
            listOf("saved", "customFeeds", "history", "offline", "drafts", "settings", "recentlyVisited", "favorites"),
            ids(SideBarItem.parse(null)),
        )
        assertEquals(SideBarItem.parse(null), Settings().sideBarItems)
    }

    @Test
    fun `stored order and hidden entries are kept, missing ones appended in default order`() {
        val parsed = SideBarItem.parse(listOf("favorites", "-history", "settings"))
        assertEquals(
            listOf("favorites", "-history", "settings", "saved", "customFeeds", "offline", "drafts", "recentlyVisited"),
            ids(parsed),
        )
    }

    @Test
    fun `unknown and repeated ids are dropped`() {
        assertEquals(
            listOf("drafts", "saved", "customFeeds", "history", "offline", "settings", "recentlyVisited", "favorites"),
            ids(SideBarItem.parse(listOf("someday", "drafts", "-drafts", "-gone"))),
        )
    }

    @Test
    fun `settings can't be hidden`() {
        assertEquals(true, SideBarItem.parse(listOf("-settings")).first { it.item == SideBarItem.SETTINGS }.shown)
    }

    @Test
    fun `prefs round trip`() {
        val stored = listOf("history", "-saved", "settings", "-favorites", "customFeeds", "offline", "drafts", "recentlyVisited")
        assertEquals(stored, SideBarItem.toPrefs(SideBarItem.parse(stored)))
    }
}
