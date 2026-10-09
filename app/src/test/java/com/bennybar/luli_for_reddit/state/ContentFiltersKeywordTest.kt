package com.bennybar.luli_for_reddit.state

import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.model.Post
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ContentFiltersKeywordTest {
    private fun post(title: String) = Post.fromData(AppJson.parseToJsonElement("""{"id":"a","title":"$title","subreddit":"x"}"""))

    @Test
    fun `keywords match whole words in any case and script`() {
        val f = ContentFilters(keywords = listOf("cat", "c++", "שלום"))
        assertTrue(f.hides(post("My CAT is cute")))
        assertFalse(f.hides(post("Summer vacation")))
        assertTrue(f.hides(post("Learning C++ today")))
        assertTrue(f.hides(post("אמרתי שלום לכולם")))
        assertFalse(f.hides(post("nothing here")))
    }
}
