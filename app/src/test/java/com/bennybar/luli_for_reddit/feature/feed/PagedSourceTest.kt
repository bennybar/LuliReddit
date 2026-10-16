package com.bennybar.luli_for_reddit.feature.feed

import com.bennybar.luli_for_reddit.model.Listing
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class PagedSourceTest {
    private val main = UnconfinedTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(main)
    @After fun tearDown() = Dispatchers.resetMain()

    @Test
    fun `a page fetched before a refresh doesn't land on the refreshed list`() = runTest(main) {
        var firstPages = 0
        val oldSecond = CompletableDeferred<Listing<String>>()
        val source = PagedSource { after ->
            if (after == null) {
                firstPages++
                if (firstPages == 1) Listing(listOf("old-first"), after = "p2") else Listing(listOf("fresh-first"), after = "p2-fresh")
            } else {
                oldSecond.await()
            }
        }
        source.start()
        source.loadMore() // page two of the old list, still in flight…
        source.load() // …when the list is refreshed
        oldSecond.complete(Listing(listOf("old-second"), after = "p3"))

        val s = source.state.value
        assertEquals(listOf("fresh-first"), s.items)
        assertEquals("p2-fresh", s.after)
        assertFalse(s.loadingMore)
    }
}
