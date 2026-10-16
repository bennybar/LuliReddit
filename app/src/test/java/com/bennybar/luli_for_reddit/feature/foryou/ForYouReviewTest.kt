package com.bennybar.luli_for_reddit.feature.foryou

import android.content.SharedPreferences
import com.bennybar.luli_for_reddit.core.storage.Prefs
import com.bennybar.luli_for_reddit.model.Post
import com.bennybar.luli_for_reddit.model.PostType
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.test.*
import kotlinx.coroutines.ExperimentalCoroutinesApi
import org.junit.Assert.*
import org.junit.Test
import java.lang.reflect.Proxy
import sun.misc.Unsafe

class ForYouReviewTest {
    // In-memory Android interface double; the production Prefs and stores execute unchanged.
    private fun prefs(): Prefs {
        val data = mutableMapOf<String, Any?>()
        val editor = Proxy.newProxyInstance(javaClass.classLoader, arrayOf(SharedPreferences.Editor::class.java)) { proxy, method, args ->
            when {
                method.name.startsWith("put") -> { data[args!![0] as String] = args[1]; proxy }
                method.name == "remove" -> { data.remove(args!![0]); proxy }
                method.name == "clear" -> { data.clear(); proxy }
                method.name == "commit" -> true
                else -> null
            }
        }
        val sp = Proxy.newProxyInstance(javaClass.classLoader, arrayOf(SharedPreferences::class.java)) { _, method, args ->
            when (method.name) {
                "contains" -> data.containsKey(args!![0])
                "getAll" -> data.toMap()
                "edit" -> editor
                else -> if (method.name.startsWith("get")) data[args!![0]] ?: args[1] else null
            }
        }
        val field = Unsafe::class.java.getDeclaredField("theUnsafe").apply { isAccessible = true }
        val p = (field.get(null) as Unsafe).allocateInstance(Prefs::class.java) as Prefs
        Prefs::class.java.getDeclaredField("sp").apply { isAccessible = true }.set(p, sp)
        Prefs::class.java.getDeclaredField("_changes").apply { isAccessible = true }.set(p, MutableSharedFlow<String>(extraBufferCapacity = 64))
        return p
    }

    @Test fun commonWordMustBeCountedInEveryDocument() {
        val store = DocFreqStore(prefs())
        store.load("alice")
        store.observe(List(100) { "Commonword" })
        assertEquals(100.0, store.state.value["commonword"]!!, 0.001)
        assertEquals(0.2, store.idf("commonword"), 0.001)
    }

    @Test fun loadingThenLearningMustNotDecayAnOldWeightTwice() {
        val prefs = prefs()
        val old = System.currentTimeMillis() - 10 * 86400000L
        prefs.setString("interest_weights_alice", "{\"_ts\":$old,\"oldsub\":10.0}")
        val store = InterestStore(prefs) { true }
        store.load("alice")
        val justLoaded = store.weightFor("oldsub")
        store.bump("newsub", 1.0)
        assertEquals(justLoaded, store.weightFor("oldsub"), 0.001)
    }

    @OptIn(ExperimentalCoroutinesApi::class)
    @Test fun pendingImpressionsMustNotMoveToAnotherAccount() = runTest {
        val store = ImpressionStore(prefs(), { true }, this)
        store.load("alice")
        store.record("alice_post")
        store.load("bob")
        advanceUntilIdle()
        assertEquals(0.0, store.count("alice_post"), 0.001)
    }

    @Test fun thirdStoryMustStayExcludedAcrossPages() {
        val title = "Starship launch succeeds orbital flight test"
        val p = Post(id="third", fullname="t3_third", title=title, subreddit="space", subredditPrefixed="r/space", author="a", score=500, numComments=0, upvoteRatio=0.9, createdUtc=1000, permalink="/x", url="/x", domain="", type=PostType.SELF, isSelf=true)
        val result = rankForYou(listOf(Candidate(p,"best")), RankInputs(subscribed=setOf("space"), previousTitles=listOf(title,title), now=3600000))
        assertTrue("Two previous copies should exclude a third", result.ranked.isEmpty())
    }
}
