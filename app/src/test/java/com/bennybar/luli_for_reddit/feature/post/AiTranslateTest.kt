package com.bennybar.luli_for_reddit.feature.post

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Translation through an AI service: replies that small models send (#308). */
class AiTranslateTest {
    @Test
    fun readsTheArrayWhereverItIs() {
        assertEquals(listOf("a", "b"), AiService.parseTranslations("""["a", "b"]""", 2))
        assertEquals(listOf("a", "b"), AiService.parseTranslations("```json\n[\"a\", \"b\"]\n```", 2))
        // A model's own words around it, brackets and all.
        assertEquals(
            listOf("x [1]", "y"),
            AiService.parseTranslations("Here [as asked] are they:\n[\"x [1]\", \"y\"]\nDone [ok].", 2),
        )
    }

    @Test
    fun aWrongCountIsNotAnAnswer() {
        assertNull(AiService.parseTranslations("""["a"]""", 2))
        assertNull(AiService.parseTranslations("""["a", 3]""", 2))
        assertNull(AiService.parseTranslations("sorry", 2))
        // One translation may come back as plain text.
        assertEquals(listOf("hola"), AiService.parseTranslations("hola", 1))
    }

    @Test
    fun aBatchThatLosesCountGoesAgainInHalves() = runTest {
        val asked = mutableListOf<Int>()
        val out = AiService.translateBatches(listOf("1", "2", "3", "4")) { batch ->
            asked += batch.size
            // Loses count on more than two at a time; "3" never comes back.
            when {
                batch.size > 2 -> """["only one"]"""
                "3" in batch -> "[]"
                else -> batch.joinToString(prefix = "[", postfix = "]") { "\"t$it\"" }
            }
        }
        assertEquals(listOf("t1", "t2", "3", "t4"), out)
        assertEquals(listOf(4, 2, 2, 1, 1), asked)
    }

    @Test
    fun waitsAsARateLimitAsks() {
        assertEquals(7_000L, AiService.retryWait("7"))
        assertEquals(1_500L, AiService.retryWait("1.5s"))
        assertEquals(5_000L, AiService.retryWait(null))
        assertNull(AiService.retryWait("60"))
    }
}
