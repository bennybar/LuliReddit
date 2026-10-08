package com.bennybar.luli_for_reddit.core

import com.bennybar.luli_for_reddit.BuildConfig
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Port of the Flutter build's test/app_version_test.dart: the update checker
 * compares GitHub's latest release with the app version; if they disagree,
 * an up-to-date install keeps being offered its own version.
 */
class AppVersionTest {
    @Test
    fun `app version is the build's versionName`() {
        assertEquals(BuildConfig.VERSION_NAME, RedditConstants.APP_VERSION)
        assertTrue(Regex("^\\d+\\.\\d+\\.\\d+(-[A-Za-z0-9]+)?$").matches(RedditConstants.APP_VERSION))
    }

    @Test
    fun `the installed version is never offered as an update`() {
        val v = RedditConstants.APP_VERSION
        assertEquals(0, UpdateChecker.compareVersions(v, v))
    }

    @Test
    fun `versions order semver-ish, prereleases before their release`() {
        val ordered = listOf("1.0.9", "1.0.50", "1.0.51", "2.0.0-beta1", "2.0.0-beta2", "2.0.0-rc1", "2.0.0", "2.0.1", "10.0.0")
        for (i in ordered.indices) {
            for (j in ordered.indices) {
                val got = Integer.signum(UpdateChecker.compareVersions(ordered[i], ordered[j]))
                assertEquals("${ordered[i]} vs ${ordered[j]}", Integer.signum(i.compareTo(j)), got)
            }
        }
    }

    @Test
    fun `missing parts count as zero`() {
        assertEquals(0, UpdateChecker.compareVersions("2.0", "2.0.0"))
        assertTrue(UpdateChecker.compareVersions("1.0.51", "2") < 0)
    }
}
