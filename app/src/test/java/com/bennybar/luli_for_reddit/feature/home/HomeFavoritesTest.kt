package com.bennybar.luli_for_reddit.feature.home

import com.bennybar.luli_for_reddit.core.parseJsonOrNull
import com.bennybar.luli_for_reddit.model.Multireddit
import com.bennybar.luli_for_reddit.model.Subreddit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Home's row of favorites (#311). */
class HomeFavoritesTest {
    private fun sub(name: String, fav: Boolean) = Subreddit(name, "r/$name", name, "", 0, userHasFavorited = fav)
    private fun multi(name: String, fav: Boolean) = Multireddit(name, name.uppercase(), "/user/me/m/$name/", emptyList(), isFavorited = fav)

    @Test
    fun favoriteFeedsComeFirstThenFavoriteCommunities() {
        val got = homeFavorites(
            listOf(multi("tech", true), multi("news", false)),
            listOf(sub("Ninjago", true), sub("AskReddit", false), sub("u_someone", true), sub("CozyPlaces", true)),
        ) { "me" }
        assertEquals(
            listOf(
                HomeFavorite("m::me::tech", "TECH", multi = true),
                HomeFavorite("Ninjago", "Ninjago", multi = false),
                HomeFavorite("CozyPlaces", "CozyPlaces", multi = false),
            ),
            got,
        )
    }

    @Test
    fun noFavoritesNoRow() {
        assertTrue(homeFavorites(listOf(multi("a", false)), listOf(sub("b", false))) { "me" }.isEmpty())
    }

    @Test
    fun aCustomFeedReadsRedditsFavoriteFlag() {
        val starred = Multireddit.fromData(parseJsonOrNull("""{"name":"gpt","display_name":"GPT","path":"/user/me/m/gpt/","is_favorited":true}""")!!)
        val plain = Multireddit.fromData(parseJsonOrNull("""{"name":"x","path":"/user/me/m/x/"}""")!!)
        assertTrue(starred.isFavorited)
        assertFalse(plain.isFavorited)
    }
}
