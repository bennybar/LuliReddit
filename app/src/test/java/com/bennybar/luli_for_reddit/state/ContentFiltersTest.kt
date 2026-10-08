package com.bennybar.luli_for_reddit.state

import com.bennybar.luli_for_reddit.model.Post
import com.bennybar.luli_for_reddit.model.PostType
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of test/content_filters_test.dart. */
class ContentFiltersTest {
    // Built directly (Post.fromData needs android.net.Uri, unavailable in JVM tests).
    private fun post(title: String, sub: String = "pics", nsfw: Boolean = false) = Post(
        id = title.hashCode().toString(),
        fullname = "t3_${title.hashCode()}",
        title = title,
        subreddit = sub,
        subredditPrefixed = "r/$sub",
        author = "someone",
        score = 1,
        numComments = 0,
        upvoteRatio = 1.0,
        createdUtc = 0,
        permalink = "",
        url = "https://example.com",
        domain = "example.com",
        type = PostType.LINK,
        over18 = nsfw,
    )

    @Test
    fun keywordsMatchWholeWordsOnlyInAnyScript() {
        val f = ContentFilters(keywords = listOf("cat", "מלחמה"))
        assertTrue(f.hides(post("My cat sleeps")))
        assertTrue(f.hides(post("Cat!")))
        assertFalse(f.hides(post("Vacation photos")))
        assertFalse(f.hides(post("Category theory")))
        assertTrue(f.hides(post("עדכון מלחמה היום")))
    }

    @Test
    fun subredditFilterSparesTheSubredditsOwnPage() {
        val f = ContentFilters(subreddits = listOf("politics"))
        val p = post("Hi", sub = "Politics")
        assertTrue(f.hides(p))
        assertFalse(f.hides(p, viewingSubreddit = "politics"))
    }

    @Test
    fun hideNsfw() {
        assertTrue(ContentFilters(hideNsfw = true).hides(post("x", nsfw = true)))
        assertFalse(ContentFilters().hides(post("x", nsfw = true)))
    }
}
