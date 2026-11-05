package com.bennybar.luli_for_reddit.feature.inbox

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** #113: which drags on the Inbox head for the side bar instead of the pager. */
class InboxSideBarDragTest {
    @Test
    fun towardTheEndEdgeOpensIt() {
        assertTrue(isSideBarDrag(8f, 0f, rtl = false))
        assertTrue(isSideBarDrag(6f, -5f, rtl = false)) // ~40°: still more sideways
        assertFalse(isSideBarDrag(-8f, 0f, rtl = false)) // the next section
    }

    @Test
    fun aScrollIsLeftToTheList() {
        assertFalse(isSideBarDrag(5f, 6f, rtl = false))
        assertFalse(isSideBarDrag(0f, 8f, rtl = false))
        assertFalse(isSideBarDrag(0f, 0f, rtl = false))
    }

    @Test
    fun rtlMirrorsIt() {
        assertTrue(isSideBarDrag(-8f, 1f, rtl = true))
        assertFalse(isSideBarDrag(8f, 1f, rtl = true))
    }
}
