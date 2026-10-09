package com.bennybar.luli_for_reddit.model

import android.net.Uri
import com.bennybar.luli_for_reddit.core.textWithoutMedia
import androidx.compose.runtime.Immutable
import com.bennybar.luli_for_reddit.core.arr
import com.bennybar.luli_for_reddit.core.bool
import com.bennybar.luli_for_reddit.core.double
import com.bennybar.luli_for_reddit.core.get
import com.bennybar.luli_for_reddit.core.int
import com.bennybar.luli_for_reddit.core.isTrue
import com.bennybar.luli_for_reddit.core.long
import com.bennybar.luli_for_reddit.core.obj
import com.bennybar.luli_for_reddit.core.str
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

enum class PostType { SELF, IMAGE, VIDEO, GIF, GALLERY, LINK }

/** A gallery item (resolved image url + dimensions). */
@Immutable
data class GalleryImage(val url: String, val width: Int? = null, val height: Int? = null)

@Immutable
data class Post(
    val id: String,
    val fullname: String, // t3_xxx
    val title: String,
    val subreddit: String,
    val subredditPrefixed: String,
    val author: String,
    val score: Int,
    val numComments: Int,
    val upvoteRatio: Double,
    val createdUtc: Long, // millis since epoch
    val permalink: String,
    val url: String,
    val domain: String,
    val type: PostType,
    val isSelf: Boolean = false,
    val selftext: String = "",
    val over18: Boolean = false,
    val spoiler: Boolean = false,
    val stickied: Boolean = false,
    val locked: Boolean = false,
    val saved: Boolean = false,
    val canModPost: Boolean = false,
    val linkFlairText: String? = null,
    val distinguished: String? = null,
    /** The mods' suggested comment sort (e.g. "qa" on AMAs), when set. */
    val suggestedSort: String? = null,
    val feedReason: String? = null, // "why you're seeing this" in For You (transient)
    val crosspostFrom: String? = null, // subreddit a crosspost originates from
    /** Images / GIFs referenced inside the body (`media_metadata`), by id — shown inline, not as links. */
    val bodyMedia: Map<String, String> = emptyMap(),
    val pollOptions: List<String> = emptyList(),
    // media
    val thumbnailUrl: String? = null,
    val previewUrl: String? = null,
    val previewMedUrl: String? = null, // smaller resolution for feed cards
    val blurredPreviewUrl: String? = null, // reddit's pre-blurred NSFW/spoiler variant
    val previewWidth: Int? = null,
    val previewHeight: Int? = null,
    val hlsUrl: String? = null,
    val fallbackVideoUrl: String? = null,
    val gifMp4Url: String? = null, // reddit's mp4 variant for GIF posts (much smaller)
    val gallery: List<GalleryImage> = emptyList(),
    /** Vote state: true = up, false = down, null = none. */
    val likes: Boolean? = null,
) {
    val hasMedia: Boolean get() = previewUrl != null || gallery.isNotEmpty() || type == PostType.VIDEO

    /** The body as a feed card previews it: without image / video links that the post view shows as media. */
    val snippet: String by lazy { if (bodyMedia.isEmpty() && "http" !in selftext) selftext else textWithoutMedia(selftext) }

    companion object {
        /** Parses a single listing child's `data` object. */
        fun fromData(d: JsonElement): Post {
            // A crosspost carries no content of its own: its text, media and
            // link live on the original post (its own url just points there).
            val parent = d["crosspost_parent_list"].arr()?.firstOrNull()?.obj()
            val content: JsonElement = parent ?: d
            val preview = firstPreviewImage(d) ?: firstPreviewImage(content)
            fun videoOf(x: JsonElement?): JsonObject? =
                x["media"]["reddit_video"].obj() ?: x["secure_media"]["reddit_video"].obj()
            val redditVideo = videoOf(d) ?: videoOf(parent)
            val ownGallery = parseGallery(d)
            val gallery = if (ownGallery.isNotEmpty() || parent == null) ownGallery else parseGallery(parent)
            // A bare v.redd.it link with no video metadata: its HLS stream sits
            // at a fixed address under the video's id.
            val url = content["url"].str() ?: d["url"].str() ?: ""
            val vreddit = runCatching { Uri.parse(url) }.getOrNull()
            val bareVreddit = redditVideo == null && vreddit?.host == "v.redd.it" &&
                vreddit.pathSegments.isNotEmpty()
            val isVideo = d["is_video"].isTrue() || parent["is_video"].isTrue() || redditVideo != null || bareVreddit
            val flair = d["link_flair_text"].str()

            return Post(
                id = d["id"].str() ?: "",
                fullname = d["name"].str() ?: "t3_${d["id"].str()}",
                title = (d["title"].str() ?: "").trim(),
                subreddit = d["subreddit"].str() ?: "",
                subredditPrefixed = d["subreddit_name_prefixed"].str() ?: "",
                author = d["author"].str() ?: "[deleted]",
                score = d["score"].int() ?: 0,
                numComments = d["num_comments"].int() ?: 0,
                upvoteRatio = d["upvote_ratio"].double() ?: 0.0,
                createdUtc = (d["created_utc"].long() ?: 0L) * 1000,
                permalink = d["permalink"].str() ?: "",
                url = url,
                domain = content["domain"].str() ?: d["domain"].str() ?: "",
                type = detectType(content, isVideo, gallery.isNotEmpty()),
                isSelf = content["is_self"].isTrue(),
                selftext = d["selftext"].str()?.ifEmpty { null } ?: content["selftext"].str() ?: "",
                over18 = d["over_18"].isTrue(),
                spoiler = d["spoiler"].isTrue(),
                stickied = d["stickied"].isTrue(),
                suggestedSort = d["suggested_sort"].str()?.ifEmpty { null },
                locked = d["locked"].isTrue(),
                saved = d["saved"].isTrue(),
                canModPost = d["can_mod_post"].isTrue(),
                linkFlairText = if (flair.isNullOrBlank()) null else flair,
                distinguished = d["distinguished"].str(),
                crosspostFrom = parent?.get("subreddit").str(),
                bodyMedia = Comment.mediaUrls(content["media_metadata"]),
                pollOptions = content["poll_data"]["options"].arr()?.mapNotNull { it["text"].str()?.ifEmpty { null } }
                    ?: emptyList(),
                thumbnailUrl = validThumb(d["thumbnail"].str()) ?: validThumb(content["thumbnail"].str()),
                previewUrl = preview?.url,
                previewMedUrl = medPreviewUrl(d) ?: medPreviewUrl(content) ?: preview?.url,
                blurredPreviewUrl = blurredPreviewUrl(d) ?: blurredPreviewUrl(content),
                previewWidth = preview?.width,
                previewHeight = preview?.height,
                hlsUrl = redditVideo?.get("hls_url").str()
                    ?: if (bareVreddit) "https://v.redd.it/${vreddit!!.pathSegments.first()}/HLSPlaylist.m3u8" else null,
                fallbackVideoUrl = redditVideo?.get("fallback_url").str(),
                gifMp4Url = content["preview"]["reddit_video_preview"]["fallback_url"].str(),
                gallery = gallery,
                likes = d["likes"].bool(),
            )
        }

        private fun detectType(d: JsonElement, isVideo: Boolean, hasGallery: Boolean): PostType {
            if (d["is_self"].isTrue()) return PostType.SELF
            if (hasGallery) return PostType.GALLERY
            if (isVideo) return PostType.VIDEO
            when (d["post_hint"].str()) {
                "image" -> return PostType.IMAGE
                "rich:video", "hosted:video" -> return PostType.VIDEO
            }
            val rawUrl = d["url"].str() ?: ""
            val parsed = runCatching { Uri.parse(rawUrl) }.getOrNull()
            // Check the path without query params — preview.redd.it links end
            // with `.png?width=…&s=…`.
            val path = (parsed?.path ?: rawUrl).lowercase()
            if (path.endsWith(".gif")) return PostType.GIF
            if (path.endsWith(".jpg") || path.endsWith(".jpeg") || path.endsWith(".png") || path.endsWith(".webp")) {
                return PostType.IMAGE
            }
            if (path.endsWith(".gifv") || path.endsWith(".mp4")) return PostType.VIDEO
            val host = parsed?.host?.lowercase() ?: ""
            if (host == "i.redd.it" || host == "preview.redd.it" || host == "i.imgur.com") return PostType.IMAGE
            return PostType.LINK
        }

        private fun validThumb(thumb: String?): String? =
            if (thumb == null || thumb.isEmpty() || thumb in setOf("self", "default", "nsfw", "spoiler", "image")) null
            else thumb

        private data class Img(val url: String, val width: Int?, val height: Int?)

        private fun firstPreviewImage(d: JsonElement): Img? {
            val source = d["preview"]["images"][0]["source"]
            val src = source["url"].str() ?: return null
            return Img(src, source["width"].int(), source["height"].int())
        }

        /**
         * Reddit's own pre-blurred copy of an NSFW (`nsfw`) or spoiler
         * (`obfuscated`) preview — the smallest >= 320px wide.
         */
        private fun blurredPreviewUrl(d: JsonElement): String? {
            val variants = d["preview"]["images"][0]["variants"]
            val v = variants["nsfw"].obj() ?: variants["obfuscated"].obj() ?: return null
            for (r in v["resolutions"].arr() ?: emptyList()) {
                if ((r["width"].int() ?: 0) >= 320) return r["url"].str()
            }
            return v["source"]["url"].str()
        }

        /** ~The smallest preview >= 640px wide, else the largest. Resolutions are ascending. */
        private fun medPreviewUrl(d: JsonElement): String? {
            val res = d["preview"]["images"][0]["resolutions"].arr()
            if (res.isNullOrEmpty()) return null
            for (r in res) {
                val u = r["url"].str()
                if (u != null && (r["width"].int() ?: 0) >= 640) return u
            }
            return res.last()["url"].str()
        }

        private fun parseGallery(d: JsonElement): List<GalleryImage> {
            val galleryData = d["gallery_data"].obj() ?: return emptyList()
            val metadata = d["media_metadata"].obj() ?: return emptyList()
            return (galleryData["items"].arr() ?: emptyList()).mapNotNull { item ->
                val mediaId = item["media_id"].str() ?: return@mapNotNull null
                val s = metadata[mediaId]["s"]
                val url = s["u"].str() ?: s["gif"].str() ?: return@mapNotNull null
                GalleryImage(url, s["x"].int(), s["y"].int())
            }
        }
    }
}
