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
}
