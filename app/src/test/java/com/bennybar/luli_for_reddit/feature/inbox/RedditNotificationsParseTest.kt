package com.bennybar.luli_for_reddit.feature.inbox

import com.bennybar.luli_for_reddit.core.AppJson
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RedditNotificationsParseTest {
    @Test
    fun `reads what the page lists, drops empties and repeats`() {
        val json = AppJson.parseToJsonElement(
            """{"login":false,"ready":true,"items":[
              {"id":"a1","type":"POST_REPLY","link":"https://www.reddit.com/r/x/comments/p1/t/c1/","title":"u/bob replied to your post in r/x","body":"Nice!","ts":"2026-10-17T15:03:29.378Z","avatar":"https://www.redditstatic.com/a.png"},
              {"id":"a1","type":"POST_REPLY","link":null,"title":"dup","body":"","ts":null,"avatar":null},
              {"id":"a2","type":"UPVOTE_POST","link":"javascript:void(0)","title":"10 upvotes!","body":"","ts":"bad","avatar":"/rel.png"},
              {"id":"a3","type":"X","link":null,"title":"","body":"","ts":null,"avatar":null}
            ]}""",
        )
        val items = RedditNotifications.parse(json)
        assertEquals(listOf("a1", "a2"), items.map { it.id })
        assertEquals("Nice!", items[0].body)
        assertEquals(1792249409378L, items[0].at)
        assertNull(items[1].link)
        assertEquals(0L, items[1].at)
        assertNull(items[1].avatar)
    }

    @Test
    fun `finds the comment a notification points at`() {
        assertEquals("phbdvfd", RedditNotifications.commentIdOf("https://www.reddit.com/r/GalaxyWatch/comments/1x79dhp/new_button_remapping_app/phbdvfd/"))
        assertEquals("ph6woy7", RedditNotifications.commentIdOf("https://www.reddit.com/r/WearOS/comments/1x79h6q/slug/ph6woy7/?screen_view_count=1"))
        assertEquals("abc12", RedditNotifications.commentIdOf("https://www.reddit.com/r/x/comments/1x/comment/abc12/"))
        assertNull("a post, not a comment", RedditNotifications.commentIdOf("https://www.reddit.com/r/WearOS/comments/1x79h6q/new_galaxy_watch/"))
    }
}
