package com.bennybar.luli_for_reddit.feature.foryou

import androidx.compose.runtime.Composable
import com.bennybar.luli_for_reddit.AppContainer
import com.bennybar.luli_for_reddit.model.Listing
import com.bennybar.luli_for_reddit.model.Post
import com.bennybar.luli_for_reddit.state.UserScoped
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * [Agent C] The on-device For You engine + its stores (interest, keywords,
 * doc-freq, impressions, sub stats, explicit prefs, muted subs, metrics,
 * meta), the learner and the experimental Reddit Home loader.
 */
class ForYouModule(private val c: AppContainer) : UserScoped {
    val learner = ForYouLearner()
    val engine = ForYouEngine()
    val redditHome = RedditHomeEngine()
    override fun onUserChanged(username: String) {}
}

/** [Agent C] The one place For You learns from what the user does (respects trackHistory). */
class ForYouLearner {
    /** A For You card that stayed >=60% on screen for 1s. */
    fun impression(p: Post) {}
    /** A vote changed from [from] to [to] (-1, 0, +1); learns only the change. */
    fun vote(p: Post, from: Int, to: Int) {}
    fun save(p: Post, saved: Boolean) {}
    fun open(p: Post) {}
    fun viewMedia(p: Post) {}
    fun comment(p: Post) {}
    fun share(p: Post) {}
    /** Time in the thread: 30s+ ([long] = 2min+, on top of it). */
    fun read(p: Post, long: Boolean = false) {}
    /** Backed out within 3 seconds. */
    fun bounce(p: Post) {}
    /** Explicit "More/Less from r/x" (+1 / -1 / 0 to clear). */
    fun subPreference(p: Post, value: Int) {}
    fun topicPreference(topic: String, value: Int) {}
}

/** [Agent C] For You pages (seed, candidates, rank, diversity, cursors, saved first page). */
class ForYouEngine {
    /**
     * First page when [after] is null, else the page after that cursor.
     * [loaded] = posts currently shown (excluded from later pages; a refresh
     * demotes the old top 10). Posts carry feedReason.
     */
    suspend fun page(after: String?, loaded: List<Post>): Listing<Post> = Listing(emptyList())

    /** The last saved first page minus posts opened since, to paint instantly. */
    suspend fun cachedFirstPage(): Listing<Post>? = null
}

/** [Agent C] Experimental Reddit Home (headless WebView), falling back to For You. */
class RedditHomeEngine {
    /** Posts found so far while the first page loads (for the loading deck). */
    val progress: StateFlow<Int> = MutableStateFlow(0)
    /** A one-off notice for the feed ("Couldn't load Reddit Home, showing For You instead."). */
    val notice = MutableStateFlow<String?>(null)
    suspend fun page(after: String?, loaded: List<Post>): Listing<Post> = Listing(emptyList())
    suspend fun cachedFirstPage(): Listing<Post>? = null
    fun dispose() {}
}

/** [Agent C] The loading deck shown while Reddit Home reads its first page. */
@Composable
fun HomeLoadingDeck() {}
