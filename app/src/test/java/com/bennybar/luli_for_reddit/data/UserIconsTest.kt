package com.bennybar.luli_for_reddit.data

import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.model.Post
import org.junit.Assert.assertEquals
import org.junit.Test

/** Pictures by account id (#185, and posters on cards #270). */
class UserIconsTest {
    @Test
    fun `names map to pictures, users without one are left out`() {
        val json = AppJson.parseToJsonElement(
            """
            {
              "t2_a": { "name": "Alice", "profile_img": "https://styles.redditmedia.com/a.png?width=256&amp;s=x" },
              "t2_b": { "name": "bob", "profile_img": "" },
              "t2_c": { "profile_img": "https://example.com/c.png" }
            }
            """,
        )
        assertEquals(mapOf("alice" to "https://styles.redditmedia.com/a.png?width=256&s=x"), parseUserIcons(json))
        assertEquals(emptyMap<String, String>(), parseUserIcons(null))
    }

    @Test
    fun `a post carries its author's account id`() {
        val p = Post.fromData(AppJson.parseToJsonElement("""{ "id": "p1", "title": "t", "author": "Alice", "author_fullname": "t2_a" }"""))
        assertEquals("t2_a", p.authorFullname)
        assertEquals("", Post.fromData(AppJson.parseToJsonElement("""{ "id": "p2", "title": "t" }""")).authorFullname)
    }
}
