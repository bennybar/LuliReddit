package com.bennybar.luli_for_reddit.core

import org.junit.Assert.assertEquals
import org.junit.Test

class AnalyticsBucketTest {
    @Test
    fun postsOpenedBuckets() {
        assertEquals("1", Analytics.bucket(1, 1, 5, 20))
        assertEquals("2-5", Analytics.bucket(2, 1, 5, 20))
        assertEquals("2-5", Analytics.bucket(5, 1, 5, 20))
        assertEquals("6-20", Analytics.bucket(6, 1, 5, 20))
        assertEquals("21+", Analytics.bucket(300, 1, 5, 20))
    }

    @Test
    fun homePostBuckets() {
        assertEquals("0", Analytics.bucket(0, 0, 9))
        assertEquals("1-9", Analytics.bucket(7, 0, 9))
        assertEquals("10+", Analytics.bucket(10, 0, 9))
    }
}
