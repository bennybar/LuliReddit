package com.bennybar.luli_for_reddit.data

import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.core.get
import com.bennybar.luli_for_reddit.core.str
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MediaUploadTest {
    @Test
    fun anImageLeasesWithoutAFilepath() {
        // #296: a filepath lease makes Reddit report the image failed (a title-only post).
        assertEquals(mapOf("mimetype" to "image/png"), MediaUpload.leaseParams("image.png", "image/png"))
        assertEquals(mapOf("filepath" to "clip.mp4", "mimetype" to "video/mp4"), MediaUpload.leaseParams("clip.mp4", "video/mp4"))
    }

    @Test
    fun theFormatComesFromTheBytes() {
        fun b(vararg x: Int) = ByteArray(x.size) { x[it].toByte() }
        assertEquals("image/jpeg", MediaUpload.imageMimeType(b(0xFF, 0xD8, 0xFF, 0xE0), "image/png"))
        assertEquals("image/png", MediaUpload.imageMimeType(b(0x89, 'P'.code, 'N'.code, 'G'.code), "image/jpeg"))
        assertEquals("image/gif", MediaUpload.imageMimeType("GIF89a".toByteArray(), "image/jpeg"))
        assertEquals("image/webp", MediaUpload.imageMimeType("RIFF\u0000\u0000\u0000\u0000WEBPVP8 ".toByteArray(), "image/jpeg"))
        assertEquals("image/heic", MediaUpload.imageMimeType("\u0000\u0000\u0000\u0018ftypheic".toByteArray(), "image/jpeg"))
        assertEquals("image/jpeg", MediaUpload.imageMimeType(b(1, 2), "image/jpeg"))
    }

    @Test
    fun theNameFollowsTheFormat() {
        assertEquals("image.png", MediaUpload.fileName("image.jpg", "image/png"))
        assertEquals("photo.webp", MediaUpload.fileName("photo", "image/webp"))
        assertEquals("clip.mp4", MediaUpload.fileName("clip.mp4", "video/mp4"))
    }

    @Test
    fun readsTheUploadFormWrappedOrBare() {
        val wrapped = AppJson.parseToJsonElement("""{"args":{"action":"//a.example","fields":[]},"asset":{"asset_id":"x"}}""")
        val bare = AppJson.parseToJsonElement("""{"action":"//b.example","fields":[]}""")
        assertEquals("//a.example", MediaUpload.uploadForm(wrapped)["action"].str())
        assertEquals("//b.example", MediaUpload.uploadForm(bare)["action"].str())
    }

    @Test
    fun readsS3sAnswer() {
        val xml = "<PostResponse><Location>https://reddit-uploaded-media.s3-accelerate.amazonaws.com/abc?x=1&amp;y=2</Location><Key>abc</Key></PostResponse>"
        assertEquals("https://reddit-uploaded-media.s3-accelerate.amazonaws.com/abc?x=1&y=2", MediaUpload.xmlTag(xml, "Location"))
        assertEquals("abc", MediaUpload.xmlTag(xml, "Key"))
        assertNull(MediaUpload.xmlTag("<Error/>", "Location"))
    }
}
