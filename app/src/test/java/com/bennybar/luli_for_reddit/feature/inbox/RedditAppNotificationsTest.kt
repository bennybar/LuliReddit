package com.bennybar.luli_for_reddit.feature.inbox

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Which Reddit app notifications are inbox items (Ilay's own inbox notification takes over those). */
class RedditAppNotificationsTest {
    @Test
    fun `replies and messages are inbox notifications`() {
        assertTrue(RedditAppNotifications.isInbox("u/Ckabal and 1 other replied to your comment in r/WWE"))
        assertTrue(RedditAppNotifications.isInbox("u/someone replied to your post in r/Android"))
        assertTrue(RedditAppNotifications.isInbox("u/someone mentioned you in r/test"))
        assertTrue(RedditAppNotifications.isInbox("u/someone sent you a message"))
    }

    @Test
    fun `post recommendations are not`() {
        assertFalse(RedditAppNotifications.isInbox("Trending in r/WWE"))
        assertFalse(RedditAppNotifications.isInbox("r/Android: Pixel 11 announced"))
    }

    @Test
    fun `same text matches Reddit's shortened body`() {
        val body = "Totally agree, the **battery** on the Watch 8 is way better than the 7. Mine lasts two days."
        assertTrue(RedditAppNotifications.sameText(body, "Totally agree, the battery on the Watch 8 is way better than the…"))
    }

    @Test
    fun `same text rejects another item`() {
        assertFalse(RedditAppNotifications.sameText("Thanks for the tip!", "Totally agree, the battery on the Watch 8"))
    }

    @Test
    fun `same text needs enough text to tell items apart`() {
        assertFalse(RedditAppNotifications.sameText("ok", "ok"))
    }

    @Test
    fun `same item needs the same author when Reddit names one`() {
        val reddit = "u/Ckabal and 1 other replied to your comment in r/WWE"
        assertTrue(RedditAppNotifications.sameItem("u/Ckabal replied · Crown Jewel", "Thank you so much for this!", reddit, "Thank you so much for this!"))
        assertFalse(RedditAppNotifications.sameItem("u/someoneElse replied · Other post", "Thank you so much for this!", reddit, "Thank you so much for this!"))
    }
}
