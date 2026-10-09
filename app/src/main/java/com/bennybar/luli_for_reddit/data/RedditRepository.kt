package com.bennybar.luli_for_reddit.data

import com.bennybar.luli_for_reddit.core.arr
import com.bennybar.luli_for_reddit.core.get
import com.bennybar.luli_for_reddit.core.net.Http
import com.bennybar.luli_for_reddit.core.net.RedditClient
import com.bennybar.luli_for_reddit.core.net.await
import com.bennybar.luli_for_reddit.core.net.uploadToCatbox
import com.bennybar.luli_for_reddit.core.obj
import com.bennybar.luli_for_reddit.core.str
import com.bennybar.luli_for_reddit.model.Comment
import com.bennybar.luli_for_reddit.model.Flair
import com.bennybar.luli_for_reddit.model.InboxItem
import com.bennybar.luli_for_reddit.model.Listing
import com.bennybar.luli_for_reddit.model.Multireddit
import com.bennybar.luli_for_reddit.model.Post
import com.bennybar.luli_for_reddit.model.RedditUser
import com.bennybar.luli_for_reddit.model.Subreddit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import okhttp3.MultipartBody
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/** A thread: the post, its comment tree and the mods' suggested sort (e.g. "qa"). */
data class Thread(val post: Post, val comments: List<Comment>, val suggestedSort: String?)

/** An uploaded media asset: its public S3 url and Reddit asset id (= media_id). */
data class MediaAsset(val url: String, val assetId: String)

/**
 * Every Reddit endpoint the app uses. Parsing mirrors the Flutter build
 * one-to-one; JSON work happens off the main thread.
 */
class RedditRepository(val client: RedditClient) {

    // Short-lived cache of the subscription list — it's expensive (up to 5
    // sequential paged requests) and hit on every For You build. Config is
    // pushed in from settings.
    @Volatile private var subsCache: List<Subreddit>? = null
    @Volatile private var subsCacheAt: Long = 0
    @Volatile var subsCacheEnabled: Boolean = true
    @Volatile var subsCacheTtlMillis: Long = 10 * 60_000L

    // The raw JSON of recently parsed posts (bounded), so a ranked For You
    // page or an offline thread can be saved and painted instantly next time.
    private val rawPosts = object : LinkedHashMap<String, JsonElement>(256, 0.75f, false) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, JsonElement>?) = size > 800
    }

    fun rawPost(id: String): JsonElement? = synchronized(rawPosts) { rawPosts[id] }

    fun parsePostListing(json: JsonElement, fromCache: Boolean = false): Listing<Post> {
        val data = json["data"]
        val posts = mutableListOf<Post>()
        for (c in data["children"].arr() ?: emptyList()) {
            if (c["kind"].str() != "t3") continue
            val raw = c["data"] ?: continue
            val post = Post.fromData(raw)
            posts.add(post)
            synchronized(rawPosts) {
                rawPosts.remove(post.id)
                rawPosts[post.id] = raw
            }
        }
        return Listing(posts, data["after"].str(), fromCache)
    }

    private suspend fun <T> parse(block: () -> T): T = withContext(Dispatchers.Default) { block() }

    /** Posts by fullname (t3_…), in the order given (Reddit reorders and drops removed ones). */
    suspend fun getPostsByIds(fullnames: List<String>): List<Post> {
        if (fullnames.isEmpty()) return emptyList()
        val json = client.get("/by_id/${fullnames.joinToString(",")}", mapOf("limit" to fullnames.size))
        val byId = parse { parsePostListing(json).items.associateBy { "t3_${it.id}" } }
        return fullnames.mapNotNull { byId[it] }
    }

    private fun postsQuery(sort: PostSort, time: TopTime, after: String?, limit: Int): Map<String, Any?> =
        linkedMapOf<String, Any?>("limit" to limit).apply {
            if (after != null) put("after", after)
            if (sort.needsTime) put("t", time.param)
        }

    /** Frontpage (subreddit == null) or a specific subreddit's posts. */
    suspend fun getPosts(
        subreddit: String? = null,
        sort: PostSort = PostSort.BEST,
        time: TopTime = TopTime.DAY,
        after: String? = null,
        limit: Int = 25,
    ): Listing<Post> {
        val base = if (subreddit == null) "" else "/r/$subreddit"
        val res = client.getResult("$base/${sort.path}", postsQuery(sort, time, after, limit))
        return parse { parsePostListing(res.json, res.fromCache) }
    }

    /** The last cached first page for exactly this feed, or null (to paint instantly). */
    suspend fun cachedPosts(
        subreddit: String? = null,
        sort: PostSort = PostSort.BEST,
        time: TopTime = TopTime.DAY,
        limit: Int = 25,
    ): Listing<Post>? {
        val base = if (subreddit == null) "" else "/r/$subreddit"
        val json = client.cached("$base/${sort.path}", postsQuery(sort, time, null, limit)) ?: return null
        val listing = parse { parsePostListing(json, fromCache = true) }
        return listing.takeIf { it.items.isNotEmpty() }
    }

    suspend fun getComments(
        subreddit: String,
        postId: String,
        sort: String = "confidence",
        focusCommentId: String? = null,
        limit: Int = 100,
    ): Thread {
        val raw = getCommentsRaw(subreddit, postId, sort, focusCommentId, limit)
        return parse { parseThread(raw) }
    }

    /** The raw comments response — kept as-is for offline reading. */
    suspend fun getCommentsRaw(
        subreddit: String,
        postId: String,
        sort: String = "confidence",
        focusCommentId: String? = null,
        limit: Int = 100,
    ): JsonElement {
        // `_` (or empty) means the subreddit is unknown (e.g. a redd.it link).
        val unknown = subreddit.isEmpty() || subreddit == "_"
        val path = if (unknown) "/comments/$postId" else "/r/$subreddit/comments/$postId"
        val query = linkedMapOf<String, Any?>("sort" to sort, "limit" to limit)
        // Focus on a single comment (permalink / inbox reply): Reddit returns
        // that comment's thread with a few parents for context.
        if (focusCommentId != null) {
            query["comment"] = focusCommentId
            query["context"] = 3
        }
        return client.get(path, query)
    }

    /** Parses a comments response (live or saved offline). */
    fun parseThread(body: JsonElement): Thread {
        val postData = body[0]["data"]["children"][0]["data"]
        val post = Post.fromData(postData!!)
        val suggested = postData["suggested_sort"].str()
        val comments = (body[1]["data"]["children"].arr() ?: emptyList())
            .filter { it.obj() != null }
            .map { Comment.fromChild(it, 0) }
        return Thread(post, comments, suggested?.ifEmpty { null })
    }

    /** Expands a "load more comments" node (flat list, rendered at [depth]). */
    suspend fun getMoreComments(
        linkFullname: String,
        childrenIds: List<String>,
        sort: String = "confidence",
        depth: Int = 0,
    ): List<Comment> {
        val json = client.get(
            "/api/morechildren",
            linkedMapOf(
                "api_type" to "json",
                "link_id" to linkFullname,
                "children" to childrenIds.joinToString(","),
                "sort" to sort,
                "limit_children" to false,
            ),
        )
        return parse { (json["json"]["data"]["things"].arr() ?: emptyList()).map { Comment.fromChild(it, depth) } }
    }

    suspend fun getSubredditAbout(name: String): Subreddit =
        Subreddit.fromData(client.get("/r/$name/about")["data"]!!)

    /** Subreddit rules as (title, description) pairs. */
    suspend fun getSubredditRules(name: String): List<Pair<String, String>> =
        (client.get("/r/$name/about/rules")["rules"].arr() ?: emptyList()).mapNotNull { r ->
            r.obj() ?: return@mapNotNull null
            (r["short_name"].str() ?: "").trim() to (r["description"].str() ?: "").trim()
        }

    suspend fun getUserAbout(username: String): RedditUser =
        RedditUser.fromData(client.get("/user/$username/about")["data"]!!)

    /** [where] ∈ submitted | upvoted | downvoted | hidden (post listings). */
    suspend fun getUserPosts(username: String, where: String = "submitted", after: String? = null, limit: Int = 25): Listing<Post> {
        val json = client.get("/user/$username/$where", linkedMapOf<String, Any?>("limit" to limit, "after" to after))
        return parse { parsePostListing(json) }
    }

    suspend fun getUserComments(username: String, after: String? = null): Listing<Comment> {
        val json = client.get("/user/$username/comments", linkedMapOf<String, Any?>("limit" to 25, "after" to after))
        return parse {
            val data = json["data"]
            Listing(
                (data["children"].arr() ?: emptyList()).filter { it["kind"].str() == "t1" }.map { Comment.fromChild(it, 0) },
                data["after"].str(),
            )
        }
    }

    /** Saved items are mixed posts (t3) and comments (t1), in original order. */
    suspend fun getUserSaved(username: String, after: String? = null, limit: Int = 25): Listing<Any> {
        val json = client.get("/user/$username/saved", linkedMapOf<String, Any?>("limit" to limit, "after" to after))
        return parse {
            val data = json["data"]
            Listing(
                (data["children"].arr() ?: emptyList()).mapNotNull { c ->
                    when (c["kind"].str()) {
                        "t3" -> c["data"]?.let { Post.fromData(it) }
                        "t1" -> Comment.fromChild(c, 0)
                        else -> null
                    }
                },
                data["after"].str(),
            )
        }
    }

    suspend fun searchPosts(
        query: String,
        subreddit: String? = null,
        after: String? = null,
        sort: String = "relevance",
        time: String = "all",
    ): Listing<Post> {
        val base = if (subreddit == null) "/search" else "/r/$subreddit/search"
        val q = linkedMapOf<String, Any?>("q" to query, "type" to "link", "sort" to sort, "t" to time, "limit" to 25)
        if (subreddit != null) q["restrict_sr"] = true
        if (after != null) q["after"] = after
        val json = client.get(base, q)
        return parse { parsePostListing(json) }
    }

    suspend fun searchSubreddits(query: String): List<Subreddit> {
        val json = client.get("/subreddits/search", linkedMapOf("q" to query, "limit" to 25))
        return (json["data"]["children"].arr() ?: emptyList()).mapNotNull { it["data"]?.let(Subreddit::fromData) }
    }

    suspend fun searchUsers(query: String): List<RedditUser> {
        val json = client.get("/search", linkedMapOf("q" to query, "type" to "user", "limit" to 25))
        return (json["data"]["children"].arr() ?: emptyList()).mapNotNull { it["data"]?.let(RedditUser::fromData) }
    }

    /** Drops the in-memory subscription cache (e.g. on account switch). */
    fun clearSubsCache() {
        subsCache = null
        subsCacheAt = 0
    }

    /** Subscriptions: favourites first, then alphabetical. */
    suspend fun getSubscribedSubreddits(force: Boolean = false): List<Subreddit> {
        val cached = subsCache
        if (!force && subsCacheEnabled && cached != null &&
            System.currentTimeMillis() - subsCacheAt < subsCacheTtlMillis
        ) return cached
        val result = mutableListOf<Subreddit>()
        var after: String? = null
        // Reddit caps at 100/page; loop a few pages for heavy subscribers.
        for (i in 0 until 5) {
            val json = client.get("/subreddits/mine/subscriber", linkedMapOf<String, Any?>("limit" to 100, "after" to after))
            val data = json["data"]
            for (c in data["children"].arr() ?: emptyList()) c["data"]?.let { result.add(Subreddit.fromData(it)) }
            after = data["after"].str() ?: break
        }
        result.sortWith(compareBy<Subreddit> { !it.userHasFavorited }.thenBy { it.name.lowercase() })
        subsCache = result
        subsCacheAt = System.currentTimeMillis()
        return result
    }

    suspend fun setSubredditFavorite(subredditName: String, favorite: Boolean) {
        client.post("/api/favorite", mapOf("sr_name" to subredditName, "make_favorite" to "$favorite"))
        subsCache = null // favourite flag changed
    }

    // --- Moderation (requires mod permission on the thing's subreddit) ---

    suspend fun modApprove(fullname: String) { client.post("/api/approve", mapOf("id" to fullname)) }

    suspend fun modRemove(fullname: String, spam: Boolean = false) {
        client.post("/api/remove", mapOf("id" to fullname, "spam" to "$spam"))
    }

    suspend fun modLock(fullname: String, lock: Boolean) {
        client.post(if (lock) "/api/lock" else "/api/unlock", mapOf("id" to fullname))
    }

    /** how: 'yes' (mod), 'no', or 'admin'. [sticky] pins a top comment. */
    suspend fun modDistinguish(fullname: String, how: String = "yes", sticky: Boolean = false) {
        client.post("/api/distinguish", mapOf("id" to fullname, "how" to how, "sticky" to "$sticky", "api_type" to "json"))
    }

    /** dir: 1 upvote, -1 downvote, 0 clear. */
    suspend fun vote(fullname: String, dir: Int) {
        client.post("/api/vote", mapOf("id" to fullname, "dir" to "$dir", "rank" to "10"))
    }

    suspend fun setSubscribed(subredditName: String, subscribe: Boolean) {
        client.post("/api/subscribe", mapOf("action" to if (subscribe) "sub" else "unsub", "sr_name" to subredditName))
        subsCache = null // subscription set changed
    }

    suspend fun setSaved(fullname: String, saved: Boolean) {
        client.post(if (saved) "/api/save" else "/api/unsave", mapOf("id" to fullname))
    }

    // --- Participate: reply / submit / edit / delete ---

    private fun apiErrors(body: JsonElement?): List<String> =
        (body["json"]["errors"].arr() ?: emptyList()).map { e ->
            val list = e.arr()
            if (list != null && list.size > 1) (list[1] as? JsonPrimitive)?.content ?: list[1].toString() else e.toString()
        }

    private fun throwIfErrors(body: JsonElement?) {
        apiErrors(body).firstOrNull()?.let { throw Exception(it) }
    }

    /** Replies to [parentFullname] (t3_ post or t1_ comment); returns the new comment at [depth]. */
    suspend fun reply(parentFullname: String, text: String, richtextJson: String? = null, depth: Int = 0): Comment {
        val data = linkedMapOf<String, Any?>("api_type" to "json", "thing_id" to parentFullname)
        if (richtextJson != null) data["richtext_json"] = richtextJson else data["text"] = text
        val res = client.post("/api/comment", data)
        throwIfErrors(res)
        val thing = res["json"]["data"]["things"][0] ?: throw Exception("Reddit did not return the new comment.")
        return Comment.fromChild(thing, depth)
    }

    /**
     * A comment reply with an inline image hosted by Reddit via the richtext
     * API (as the official app does). Subreddits that disallow comment images
     * reject it, so fall back to Catbox and drop a link into the comment.
     */
    suspend fun replyWithImage(
        parentFullname: String,
        text: String,
        bytes: ByteArray,
        filename: String,
        mimeType: String,
        depth: Int = 0,
    ): Comment {
        return try {
            val asset = uploadMediaAsset(bytes, filename, mimeType)
            val doc = buildJsonObject {
                putJsonArray("document") {
                    if (text.isNotEmpty()) {
                        addJsonObject {
                            put("e", "par")
                            putJsonArray("c") { addJsonObject { put("e", "text"); put("t", text) } }
                        }
                    }
                    addJsonObject { put("e", "img"); put("id", asset.assetId) }
                }
            }
            reply(parentFullname, text, richtextJson = doc.toString(), depth = depth)
        } catch (_: Exception) {
            val url = uploadToCatbox(bytes, filename)
            reply(parentFullname, if (text.isEmpty()) url else "$text\n\n$url", depth = depth)
        }
    }

    /** Edits the body of your own post (selftext) or comment. Returns the new body. */
    suspend fun editText(thingFullname: String, text: String): String {
        throwIfErrors(client.post("/api/editusertext", mapOf("api_type" to "json", "thing_id" to thingFullname, "text" to text)))
        return text
    }

    suspend fun deleteThing(fullname: String) { client.post("/api/del", mapOf("id" to fullname)) }

    /**
     * Submits a text, link or image post (upload images first with
     * [uploadImage]). Returns the new post id.
     */
    suspend fun submitPost(
        subreddit: String,
        title: String,
        kind: String, // 'self' | 'link' | 'image'
        text: String? = null,
        url: String? = null,
        nsfw: Boolean = false,
        spoiler: Boolean = false,
        sendReplies: Boolean = true,
        flair: Flair? = null,
    ): String {
        val data = linkedMapOf<String, Any?>("api_type" to "json", "sr" to subreddit, "title" to title, "kind" to kind)
        if (kind == "self") data["text"] = text ?: ""
        if (kind == "link" || kind == "image") {
            data["url"] = url ?: ""
            if (!text.isNullOrEmpty()) data["text"] = text
        }
        if (flair != null) {
            data["flair_id"] = flair.id
            data["flair_text"] = flair.text
        }
        data["nsfw"] = "$nsfw"
        data["spoiler"] = "$spoiler"
        data["sendreplies"] = "$sendReplies"
        val res = client.post("/api/submit", data)
        throwIfErrors(res)
        return res["json"]["data"]["id"].str() ?: throw Exception("Reddit did not return the new post.")
    }

    // --- Inbox / messages ---

    /** [where] ∈ inbox | unread | messages | sent | comments | mentions. */
    suspend fun getInbox(where: String = "inbox", after: String? = null, limit: Int = 25): Listing<InboxItem> {
        val json = client.get("/message/$where", linkedMapOf<String, Any?>("limit" to limit, "after" to after))
        return parse {
            val data = json["data"]
            Listing((data["children"].arr() ?: emptyList()).map { InboxItem.fromChild(it) }, data["after"].str())
        }
    }

    /** One page of 100 (Reddit's max): the badge shows "99+" beyond that. */
    suspend fun getUnreadCount(): Int = getInbox(where = "unread", limit = 100).items.size

    suspend fun markRead(fullname: String) { client.post("/api/read_message", mapOf("id" to fullname)) }
    suspend fun markAllRead() { client.post("/api/read_all_messages") }
    suspend fun markUnread(fullname: String) { client.post("/api/unread_message", mapOf("id" to fullname)) }

    /** Deletes a private message (t4_ only; comment replies can't be deleted). */
    suspend fun deleteMessage(fullname: String) { client.post("/api/del_msg", mapOf("id" to fullname)) }

    /** Replies to a message or inbox comment (thing_id = t4_/t1_ fullname). */
    suspend fun sendReply(parentFullname: String, text: String) {
        throwIfErrors(client.post("/api/comment", mapOf("api_type" to "json", "thing_id" to parentFullname, "text" to text)))
    }

    suspend fun composeMessage(to: String, subject: String, text: String) {
        throwIfErrors(client.post("/api/compose", mapOf("api_type" to "json", "to" to to, "subject" to subject, "text" to text)))
    }

    /**
     * Uploads media to Reddit's media store: lease from Reddit, then S3 POST.
     * Returns the public S3 url (link/image/video posts) and the asset id
     * (= media_id, needed for galleries and richtext images).
     */
    suspend fun uploadMediaAsset(bytes: ByteArray, filename: String, mimeType: String): MediaAsset {
        val lease = client.post("/api/media/asset.json", mapOf("filepath" to filename, "mimetype" to mimeType))
        val args = lease["args"]
        val action = args["action"].str() ?: throw Exception("Could not get an upload lease.")
        val assetId = lease["asset"]["asset_id"].str() ?: ""
        val form = MultipartBody.Builder().setType(MultipartBody.FORM)
        for (f in args["fields"].arr() ?: emptyList()) {
            val name = f["name"].str() ?: continue
            form.addFormDataPart(name, (f["value"] as? JsonPrimitive)?.content ?: "")
        }
        form.addFormDataPart("file", filename, bytes.toRequestBody())
        val uploadUrl = if (action.startsWith("http")) action else "https:$action"
        val xml = Http.client.await(Request.Builder().url(uploadUrl).post(form.build()).build())
            .use { withContext(Dispatchers.IO) { it.body.string() } }
        val location = Regex("<Location>(.*?)</Location>").find(xml)?.groupValues?.get(1)?.replace("&amp;", "&")
            ?: throw Exception("Upload failed (no location).")
        return MediaAsset(location, assetId)
    }

    suspend fun uploadImage(bytes: ByteArray, filename: String, mimeType: String): String =
        uploadMediaAsset(bytes, filename, mimeType).url

    // --- Post actions: hide / report / block / crosspost ---

    suspend fun setHidden(fullname: String, hidden: Boolean) {
        client.post(if (hidden) "/api/hide" else "/api/unhide", mapOf("id" to fullname))
    }

    suspend fun report(fullname: String, reason: String) {
        client.post("/api/report", mapOf("thing_id" to fullname, "reason" to reason))
    }

    /** Blocks a user (you stop seeing their posts/comments/messages). */
    suspend fun blockUser(username: String) { client.post("/api/block_user", mapOf("name" to username)) }

    suspend fun submitCrosspost(
        subreddit: String,
        title: String,
        crosspostFullname: String,
        nsfw: Boolean = false,
        spoiler: Boolean = false,
    ): String {
        val res = client.post(
            "/api/submit",
            linkedMapOf(
                "api_type" to "json", "sr" to subreddit, "title" to title, "kind" to "crosspost",
                "crosspost_fullname" to crosspostFullname, "nsfw" to "$nsfw", "spoiler" to "$spoiler",
                "sendreplies" to "true",
            ),
        )
        throwIfErrors(res)
        return res["json"]["data"]["id"].str() ?: throw Exception("Crosspost failed.")
    }

    // --- Flair ---

    suspend fun getLinkFlairs(subreddit: String): List<Flair> = try {
        (client.get("/r/$subreddit/api/link_flair").arr() ?: emptyList()).map(Flair::fromJson).filter { it.text.isNotEmpty() }
    } catch (_: Exception) {
        emptyList() // subreddit may have no flairs / no permission
    }

    // --- Gallery & video submission ---

    /** Submits a gallery post from already-uploaded media ids (asset_ids). */
    suspend fun submitGalleryPost(
        subreddit: String,
        title: String,
        mediaIds: List<String>,
        text: String = "",
        nsfw: Boolean = false,
        spoiler: Boolean = false,
        sendReplies: Boolean = true,
        flair: Flair? = null,
    ) {
        val body = buildJsonObject {
            put("sr", subreddit)
            put("submit_type", "subreddit")
            put("api_type", "json")
            put("show_error_list", true)
            put("title", title)
            put("text", text)
            put("spoiler", spoiler)
            put("nsfw", nsfw)
            put("kind", "self")
            put("original_content", false)
            put("post_to_twitter", false)
            put("sendreplies", sendReplies)
            put("validate_on_submit", true)
            if (flair != null) {
                put("flair_id", flair.id)
                put("flair_text", flair.text)
            }
            put("items", buildJsonArray {
                for (id in mediaIds) addJsonObject { put("caption", ""); put("outbound_url", ""); put("media_id", id) }
            })
        }
        throwIfErrors(client.postJson("/api/submit_gallery_post.json", body.toString()))
    }

    /** Submits a video (or video-gif) post from S3 urls returned by [uploadMediaAsset]. */
    suspend fun submitVideoPost(
        subreddit: String,
        title: String,
        videoUrl: String,
        posterUrl: String,
        isGif: Boolean = false,
        text: String = "",
        nsfw: Boolean = false,
        spoiler: Boolean = false,
        sendReplies: Boolean = true,
        flair: Flair? = null,
    ): String {
        val data = linkedMapOf<String, Any?>(
            "api_type" to "json", "sr" to subreddit, "title" to title,
            "kind" to if (isGif) "videogif" else "video", "url" to videoUrl, "video_poster_url" to posterUrl,
        )
        if (text.isNotEmpty()) data["text"] = text
        if (flair != null) {
            data["flair_id"] = flair.id
            data["flair_text"] = flair.text
        }
        data["nsfw"] = "$nsfw"
        data["spoiler"] = "$spoiler"
        data["sendreplies"] = "$sendReplies"
        val res = client.post("/api/submit", data)
        throwIfErrors(res)
        return res["json"]["data"]["id"].str() ?: ""
    }

    // --- Multireddits ---

    suspend fun getMyMultireddits(): List<Multireddit> =
        (client.get("/api/multi/mine", mapOf("expand_srs" to true)).arr() ?: emptyList())
            .mapNotNull { it["data"]?.let(Multireddit::fromData) }
            .sortedBy { it.displayName.lowercase() }

    suspend fun getMultiPosts(
        username: String,
        multiname: String,
        sort: PostSort = PostSort.HOT,
        time: TopTime = TopTime.DAY,
        after: String? = null,
        limit: Int = 25,
    ): Listing<Post> {
        val res = client.getResult("/user/$username/m/$multiname/${sort.path}", postsQuery(sort, time, after, limit))
        return parse { parsePostListing(res.json, res.fromCache) }
    }

    suspend fun createMultireddit(
        username: String,
        name: String,
        subreddits: List<String> = emptyList(),
        visibility: String = "private",
        description: String = "",
    ) {
        val multipath = "/user/$username/m/$name"
        val model = buildJsonObject {
            put("display_name", name)
            put("subreddits", JsonArray(subreddits.map { buildJsonObject { put("name", it) } }))
            put("visibility", visibility)
            put("description_md", description)
        }
        throwIfErrors(
            client.post("/api/multi$multipath", mapOf("model" to model.toString(), "multipath" to multipath, "api_type" to "json")),
        )
    }

    suspend fun deleteMultireddit(multipath: String) { client.delete("/api/multi$multipath") }

    suspend fun addSubredditToMulti(multipath: String, subreddit: String) {
        client.put("/api/multi$multipath/r/$subreddit", buildJsonObject { put("name", subreddit) }.toString())
    }

    suspend fun removeSubredditFromMulti(multipath: String, subreddit: String) {
        client.delete("/api/multi$multipath/r/$subreddit")
    }

    /**
     * [Agent D] One private-message conversation (root + replies) by any
     * message id in it, for opening a thread from a notification.
     */
    suspend fun getMessageThread(id: String): InboxItem? {
        val json = client.get("/message/messages/${id.removePrefix("t4_")}")
        return parse { json["data"]["children"].arr()?.firstOrNull()?.let { InboxItem.fromChild(it) } }
    }
}
