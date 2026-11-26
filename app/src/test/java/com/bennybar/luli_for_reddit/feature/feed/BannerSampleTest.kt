package com.bennybar.luli_for_reddit.feature.feed

import org.junit.Assert.assertEquals
import org.junit.Test

class BannerSampleTest {
    @Test
    fun aWideBannerIsSampledOnlyWhereTheCroppedBoxShowsIt() {
        // 4000×400 filling 1000×400: scale 1, the middle 1000 px across, the top quarter.
        val r = bannerSampleRect(4000, 400, 1000, 400, 0.25f)
        assertEquals(1500f, r.left, 0.01f)
        assertEquals(2500f, r.right, 0.01f)
        assertEquals(0f, r.top, 0.01f)
        assertEquals(100f, r.bottom, 0.01f)
    }

    @Test
    fun aTallPictureIsSampledFromTheMiddleBandsTop() {
        // 1000×2000 filling 1000×500: the middle 500 px tall, from y 750.
        val r = bannerSampleRect(1000, 2000, 1000, 500, 0.5f)
        assertEquals(0f, r.left, 0.01f)
        assertEquals(1000f, r.right, 0.01f)
        assertEquals(750f, r.top, 0.01f)
        assertEquals(1000f, r.bottom, 0.01f)
    }

    @Test
    fun unknownSizesSampleTheWholePicture() {
        val r = bannerSampleRect(800, 200, 0, 0, 0.3f)
        assertEquals(0f, r.left, 0.01f)
        assertEquals(800f, r.right, 0.01f)
        assertEquals(200f, r.bottom, 0.01f)
    }
}
