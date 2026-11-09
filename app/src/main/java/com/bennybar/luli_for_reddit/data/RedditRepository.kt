package com.bennybar.luli_for_reddit.data

import com.bennybar.luli_for_reddit.model.UserFlairSelector
import com.bennybar.luli_for_reddit.model.UserFlairChoice
import android.net.Uri
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.arr
import com.bennybar.luli_for_reddit.core.get
import com.bennybar.luli_for_reddit.core.isTrue
import com.bennybar.luli_for_reddit.core.net.Http
import com.bennybar.luli_for_reddit.core.net.RedditApiException
import com.bennybar.luli_for_reddit.core.net.RedditClient
import com.bennybar.luli_for_reddit.core.net.await
import com.bennybar.luli_for_reddit.core.net.uploadToCatbox
import com.bennybar.luli_for_reddit.core.obj
import com.bennybar.luli_for_reddit.core.redditPostRoute
import com.bennybar.luli_for_reddit.core.resolveShareLink
import com.bennybar.luli_for_reddit.core.str
import com.bennybar.luli_for_reddit.feature.post.CommentTree
import com.bennybar.luli_for_reddit.model.Comment
import com.bennybar.luli_for_reddit.model.Flair
import com.bennybar.luli_for_reddit.model.InboxItem
import com.bennybar.luli_for_reddit.model.Listing
import com.bennybar.luli_for_reddit.model.Multireddit
import com.bennybar.luli_for_reddit.model.Post
import com.bennybar.luli_for_reddit.model.RedditUser
import com.bennybar.luli_for_reddit.model.Subreddit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObjectBuilder
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import okhttp3.MultipartBody
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/** A thread: the post, its comment tree and the mods' suggested sort (e.g. "qa"). */
data class Thread(val post: Post, val comments: List<Comment>, val suggestedSort: String?)

/** The most comments one "more replies" request asks for. */
private const val MORE_LIMIT = 500

/** How many hidden comments one tap fetches one by one, when a page doesn't reach them. */
private const val MORE_BATCH = 10

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

    // Crossposts whose listing left out the original (Post.missingCrosspostParent),
    // rebuilt around it once it's fetched, by post id. Cards and the thread
    // header read this, so the post fills in where it's shown and the list
    // itself never moves.
    private val crosspostsFlow = MutableStateFlow<Map<String, Post>>(emptyMap())
    val crossposts: StateFlow<Map<String, Post>> = crosspostsFlow

    // The originals' raw JSON by fullname, so a reloaded page rebuilds its
    // crossposts at once. Null: asked for (in flight, or Reddit didn't return it).
    private val crosspostParents = HashMap<String, JsonElement?>()
    // Share links (Post.shareLink) by URL, resolved to the fullname of the post
    // they redirect to, so a reloaded page needn't resolve them again. Null: in
    // flight; "": not a post, or it couldn't be resolved (not tried again).
    private val shareLinkTargets = HashMap<String, String?>()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /**
     * Rebuilds [children] (crossposts missing their original, with their raw
     * JSON) as if `crosspost_parent_list` had been there: at once from the
     * originals already known, the rest after one request for all of them.
     * A share-link post becomes a crosspost of the post its link resolves to.
     * Failures are silent: the card keeps its in-app link to the original.
     */
    private fun fillCrossposts(children: List<Pair<Post, JsonElement>>) {
        if (children.isEmpty()) return
        fun parentOf(post: Post): String? =
            post.crosspostParent ?: synchronized(shareLinkTargets) { shareLinkTargets[post.url] }?.ifEmpty { null }
        fun rebuild() {
            val merged = children.mapNotNull { (post, raw) ->
                val fullname = parentOf(post) ?: return@mapNotNull null
                val parent = synchronized(crosspostParents) { crosspostParents[fullname] } ?: return@mapNotNull null
                post.id to Post.withCrosspostParent(raw, parent, fullname)
            }
            if (merged.isEmpty()) return
            // Kept for a For You page or an offline thread saved from here.
            synchronized(rawPosts) { for ((id, raw) in merged) if (id in rawPosts) rawPosts[id] = raw }
            val posts = merged.map { (id, raw) -> id to Post.fromData(raw) }
            crosspostsFlow.update { it + posts }
        }
        rebuild()
        val unresolved = synchronized(shareLinkTargets) {
            children.filter { it.first.shareLink }.map { it.first.url }.distinct().filter { it !in shareLinkTargets }
                .onEach { shareLinkTargets[it] = null }
        }
        fun wanted() = synchronized(crosspostParents) {
            children.mapNotNull { parentOf(it.first) }.distinct().filter { it !in crosspostParents }.take(100)
                .onEach { crosspostParents[it] = null }
        }
        val known = wanted()
        if (unresolved.isEmpty() && known.isEmpty()) return
        scope.launch {
            if (unresolved.isNotEmpty()) {
                // Each is a redirect on www.reddit.com (no sign-in); a few at a time.
                val gate = Semaphore(4)
                val targets = unresolved.map { url ->
                    async { url to gate.withPermit { resolveShareLink(Uri.parse(url))?.let { redditPostRoute(it.toString()) } } }
                }.awaitAll()
                synchronized(shareLinkTargets) { for ((url, route) in targets) shareLinkTargets[url] = route?.let { "t3_${it.postId}" } ?: "" }
            }
            // The originals the share links resolved to join the same request.
            val ids = known + wanted()
            if (ids.isEmpty()) return@launch
            try {
                // Reddit's /by_id (or PostsByIds) takes them all in one go.
                val parents = getPostsByIds(ids)
                synchronized(crosspostParents) {
                    for (p in parents) rawPost(p.id)?.let { crosspostParents[p.fullname] = it }
                }
                rebuild()
            } catch (_: Exception) {
                // Asked again with the next page that has them.
                synchronized(crosspostParents) { ids.forEach { crosspostParents.remove(it) } }
            }
        }
    }

    fun parsePostListing(json: JsonElement, fromCache: Boolean = false): Listing<Post> {
        val data = json["data"]
        val posts = mutableListOf<Post>()
        val crossposts = mutableListOf<Pair<Post, JsonElement>>()
        for (c in data["children"].arr() ?: emptyList()) {
            if (c["kind"].str() != "t3") continue
            val raw = c["data"] ?: continue
            val post = Post.fromData(raw)
            posts.add(post)
            if (post.missingCrosspostParent) crossposts.add(post to raw)
            synchronized(rawPosts) {
                rawPosts.remove(post.id)
                rawPosts[post.id] = raw
            }
        }
        fillCrossposts(crossposts)
        return Listing(posts, data["after"].str(), fromCache)
    }

    private suspend fun <T> parse(block: () -> T): T = withContext(Dispatchers.Default) { block() }

    /** Posts by fullname (t3_…), in the order given (Reddit reorders and drops removed ones). */
    suspend fun getPostsByIds(fullnames: List<String>): List<Post> {
        if (fullnames.isEmpty()) return emptyList()
        if (client.isWebMode()) {
            // /by_id.json is refused for the website sign-in (Reddit Home, Blend).
            val data = client.gql("PostsByIds", GQL_POSTS_BY_IDS, postsByIdsVariables(fullnames))
            val byId = parse {
                (data["postsInfoByIds"].arr() ?: emptyList()).filter(::gqlIsPost).associate { n ->
                    val raw = gqlPostData(n.obj()!!)
                    val post = Post.fromData(raw)
                    // Kept like a listing's, e.g. for a Home page saved for offline.
                    synchronized(rawPosts) {
                        rawPosts.remove(post.id)
                        rawPosts[post.id] = raw
                    }
                    "t3_${post.id}" to post
                }
            }
            return fullnames.mapNotNull { byId[it] }
        }
        val json = client.get("/by_id/${fullnames.joinToString(",")}", mapOf("limit" to fullnames.size, "sr_detail" to true))
        val byId = parse { parsePostListing(json).items.associateBy { "t3_${it.id}" } }
        return fullnames.mapNotNull { byId[it] }
    }

    private fun postsQuery(sort: PostSort, time: TopTime, after: String?, limit: Int): Map<String, Any?> =
        // sr_detail: each post carries its subreddit's icon for the card.
        linkedMapOf<String, Any?>("limit" to limit, "sr_detail" to true).apply {
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
        return orGql({
            val res = client.getResult("$base/${sort.path}", postsQuery(sort, time, after, limit))
            parse { parsePostListing(res.json, res.fromCache) }
        }) {
            // Reddit's app loads a feed page as post ids, then the posts by id
            // (its page sizes: 6 first, then 24).
            var cursor = after
            // PostsByIds drops removed posts, so a page can come back empty
            // while the feed goes on: skip ahead a few pages, not end it there.
            for (i in 0 until 5) {
                val (operation, hash, vars) = gqlFeedQuery(subreddit, sort, time, cursor) ?: throw RedditApiException(403)
                val ids = gqlFeedPostIds(client.gql(operation, hash, vars))
                val posts = getPostsByIds(ids)
                cursor = ids.lastOrNull()
                if (posts.isNotEmpty() || cursor == null) return@orGql Listing(posts, cursor)
            }
            Listing(emptyList(), null)
        }
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
        return orGql({ client.get(path, query) }) {
            // Reddit's app loads the post by id and its comments side by side.
            coroutineScope {
                val post = async { client.gql("PostsByIds", GQL_POSTS_BY_IDS, postsByIdsVariables(listOf("t3_$postId"))) }
                val forest = async {
                    client.gql("PostComments", GQL_POST_COMMENTS, postCommentsVariables("t3_$postId", sort, focusCommentId, null))
                }
                val p = post.await()["postsInfoByIds"][0].obj()?.takeIf(::gqlIsPost) ?: throw Exception("This post isn't available")
                val trees = forest.await()["postInfoById"]["commentForest"]["trees"].arr() ?: emptyList()
                parse { gqlThreadData(gqlPostData(p), trees) }
            }
        }
    }

    /** Parses a comments response (live or saved offline). */
    fun parseThread(body: JsonElement): Thread {
        val postData = body[0]["data"]["children"][0]["data"]
        val post = Post.fromData(postData!!)
        if (post.missingCrosspostParent) fillCrossposts(listOf(post to postData))
        val suggested = postData["suggested_sort"].str()
        val comments = (body[1]["data"]["children"].arr() ?: emptyList())
            .filter { it.obj() != null }
            .map { Comment.fromChild(it, 0) }
        return Thread(post, comments, suggested?.ifEmpty { null })
    }

    /** Expands a "load more comments" node (flat list, rendered at [depth]). */
    suspend fun getMoreComments(
        linkFullname: String,
        moreNode: Comment,
        sort: String = "confidence",
    ): List<Comment> {
        val childrenIds = moreNode.moreChildren
        val depth = moreNode.depth
        // A "more" row from the GraphQL fallback: continue it by its cursor.
        childrenIds.singleOrNull()?.takeIf { it.startsWith(GQL_MORE) }?.let { more ->
            val (parent, cursor) = more.removePrefix(GQL_MORE).split(' ', limit = 2).let { it[0] to it.getOrElse(1) { "" } }
            val data = client.gql("PostComments", GQL_POST_COMMENTS, postCommentsVariables(linkFullname, sort, null, cursor))
            val trees = data["postInfoById"]["commentForest"]["trees"].arr() ?: emptyList()
            return parse { gqlCommentThings(trees, linkFullname, moreParent = parent).map { Comment.fromChild(it, depth) } }
        }
        // Reddit answers /api/morechildren with a 403 since late October 2026
        // (#59), so the hidden replies come from the thread itself.
        val postId = linkFullname.removePrefix("t3_")
        suspend fun fetch(focus: String?): List<Comment> {
            val raw = getCommentsRaw("", postId, sort, focus, MORE_LIMIT)
            return parse { CommentTree.flatten(parseThread(raw).comments, emptySet()) }
        }
        val parent = moreNode.parentId
        val page = if (parent.startsWith("t1_")) {
            val all = fetch(parent.removePrefix("t1_"))
            CommentTree.flatten(all.find { it.fullname == parent }?.replies ?: emptyList(), emptySet())
        } else {
            fetch(null)
        }
        // Not the row itself coming back: a "more" row takes its first child's id.
        if (page.any { !it.isMore && it.id in childrenIds }) return page
        // Past what one page holds (a huge thread): fetch some of the hidden
        // comments one by one, and leave the rest on the row.
        val batch = childrenIds.take(MORE_BATCH).flatMap { id ->
            val all = fetch(id)
            CommentTree.flatten(listOfNotNull(all.find { it.id == id }), emptySet())
        }
        val rest = childrenIds.drop(MORE_BATCH)
        if (rest.isEmpty()) return batch
        return batch + moreNode.copy(moreChildren = rest, moreCount = (moreNode.moreCount - MORE_BATCH).coerceAtLeast(rest.size))
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

    /** [where] ∈ submitted | upvoted | downvoted | hidden (post listings); [sort] (and [time] for Top) only for submitted. */
    suspend fun getUserPosts(
        username: String,
        where: String = "submitted",
        after: String? = null,
        limit: Int = 25,
        sort: PostSort? = null,
        time: TopTime? = null,
    ): Listing<Post> {
        val json = client.get(
            "/user/$username/$where",
            linkedMapOf<String, Any?>("limit" to limit, "after" to after, "sr_detail" to true, "sort" to sort?.path, "t" to time?.param),
        )
        return parse { parsePostListing(json) }
    }

    suspend fun getUserComments(username: String, after: String? = null, sort: PostSort? = null, time: TopTime? = null): Listing<Comment> {
        val json = client.get(
            "/user/$username/comments",
            linkedMapOf<String, Any?>("limit" to 25, "after" to after, "sort" to sort?.path, "t" to time?.param),
        )
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
        val json = client.get("/user/$username/saved", linkedMapOf<String, Any?>("limit" to limit, "after" to after, "sr_detail" to true))
        return parse {
            val data = json["data"]
            val crossposts = mutableListOf<Pair<Post, JsonElement>>()
            Listing(
                (data["children"].arr() ?: emptyList()).mapNotNull { c ->
                    when (c["kind"].str()) {
                        "t3" -> c["data"]?.let { raw -> Post.fromData(raw).also { if (it.missingCrosspostParent) crossposts.add(it to raw) } }
                        "t1" -> Comment.fromChild(c, 0)
                        else -> null
                    }
                },
                data["after"].str(),
            ).also { fillCrossposts(crossposts) }
        }
    }

    suspend fun searchPosts(
        query: String,
        subreddit: String? = null,
        after: String? = null,
        sort: String = "relevance",
        time: String = "all",
    ): Listing<Post> {
        if (client.isWebMode()) {
            // The posts come from the results themselves: /by_id.json is refused too.
            val (nodes, next) = gqlSearch(
                client.gql("SearchPosts", GQL_SEARCH_POSTS, searchPostsVariables(query, subreddit, after, sort, time)),
                "posts",
            )
            return parse { Listing(nodes.map { Post.fromData(gqlPostData(it)) }, next) }
        }
        val base = if (subreddit == null) "/search" else "/r/$subreddit/search"
        val q = linkedMapOf<String, Any?>("q" to query, "type" to "link", "sort" to sort, "t" to time, "limit" to 25, "sr_detail" to true)
        if (subreddit != null) q["restrict_sr"] = true
        if (after != null) q["after"] = after
        val json = client.get(base, q)
        return parse { parsePostListing(json) }
    }

    suspend fun searchSubreddits(query: String): List<Subreddit> {
        if (client.isWebMode()) {
            val vars = buildJsonObject {
                put("query", query.trim().replace(Regex("^/?r/", RegexOption.IGNORE_CASE), ""))
                put("productSurface", "android")
                put("first", 25)
            }
            val (nodes, _) = gqlSearch(client.gql("CommunityPickerSearchPaginated", GQL_SEARCH_COMMUNITIES, vars), "communities")
            return nodes.filter { it["__typename"].str() == "Subreddit" && it["name"].str() != null }
                .map { Subreddit.fromData(gqlSubredditData(it)) }
        }
        val json = client.get("/subreddits/search", linkedMapOf("q" to query, "limit" to 25))
        return (json["data"]["children"].arr() ?: emptyList()).mapNotNull { it["data"]?.let(Subreddit::fromData) }
    }

    suspend fun searchUsers(query: String): List<RedditUser> {
        if (client.isWebMode()) {
            val vars = buildJsonObject {
                put("query", query)
                put("productSurface", "android")
                put("pageSize", 25)
            }
            val (nodes, _) = gqlSearch(client.gql("SearchPeople", GQL_SEARCH_PEOPLE, vars), "authors")
            return nodes.filter { it["__typename"].str() == "Redditor" && it["name"].str() != null }
                .map { RedditUser.fromData(gqlUserData(it)) }
        }
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
        orGql({ client.post("/api/vote", mapOf("id" to fullname, "dir" to "$dir", "rank" to "10")) }) {
            val post = fullname.startsWith("t3_")
            val state = when (dir) { 1 -> "UP"; -1 -> "DOWN"; else -> "NONE" }
            gqlMutation(
                if (post) "UpdatePostVoteState" else "UpdateCommentVoteState",
                if (post) GQL_POST_VOTE else GQL_COMMENT_VOTE,
                if (post) "updatePostVoteState" else "updateCommentVoteState",
            ) { put(if (post) "postId" else "commentId", fullname); put("voteState", state) }
        }
    }

    /**
     * Website sign-in: [rest], or when Reddit's edge refuses it (403, as it
     * did for search and /by_id) the same thing through GraphQL ([gql]). A
     * 403 with a reason (a private, quarantined or gated subreddit) is
     * Reddit's own answer, not the edge's page.
     */
    /**
     * Commenters' profile pictures (#133), lowercased name → url, from the first page of
     * the thread's GraphQL comment forest (the .json comments carry none). Website
     * sign-in only.
     */
    suspend fun getCommentAvatars(postId: String, sort: String): Map<String, String> {
        val data = client.gql("PostComments", GQL_POST_COMMENTS, postCommentsVariables("t3_$postId", sort, null, null))
        return gqlAuthorIcons(data["postInfoById"]["commentForest"]["trees"].arr() ?: emptyList())
    }

    private suspend fun <T> orGql(rest: suspend () -> T, gql: suspend () -> T): T {
        try {
            return rest()
        } catch (e: RedditApiException) {
            if (e.statusCode != 403 || e.reason != null || !client.isWebMode()) throw e
            return gql()
        }
    }

    /** A GraphQL mutation taking `input` (built by [input]), whose result is [field]. */
    private suspend fun gqlMutation(operation: String, hash: String, field: String, input: JsonObjectBuilder.() -> Unit) {
        gqlCheckOk(client.gql(operation, hash, buildJsonObject { putJsonObject("input", input) })[field])
    }

    /**
     * Opts in to a quarantined or gated ([reason]) subreddit so its posts load.
     * Only quarantine has an OAuth API; the website sign-in uses GraphQL,
     * like Reddit's app.
     */
    suspend fun optInSubreddit(name: String, reason: String) {
        if (!client.isWebMode()) {
            client.post("/api/quarantine_option", mapOf("sr_name" to name, "accept" to "true"))
            return
        }
        if (reason == "gated") {
            gqlMutation("UpdateOptInToGatedSubreddit", GQL_OPT_IN_GATED, "optInToGatedSubreddit") { put("subredditName", name) }
        } else {
            val id = client.gql("SubredditInfoByName", GQL_SUBREDDIT_INFO, subredditInfoVariables(name))["subredditInfoByName"]["id"].str()
                ?: throw Exception("r/$name wasn't found")
            gqlMutation("UpdateOptInToQuarantinedSubreddit", GQL_OPT_IN_QUARANTINED, "updateSubredditQuarantineOptInState") {
                put("subredditId", id); put("optInState", "OPTED_IN")
            }
        }
    }

    /** Whether [reason] (a refused subreddit's) is one the user can opt in to here. */
    suspend fun canOptIn(reason: String?): Boolean =
        reason == "quarantined" || (reason == "gated" && client.isWebMode())

    suspend fun setSubscribed(subredditName: String, subscribe: Boolean) {
        client.post("/api/subscribe", mapOf("action" to if (subscribe) "sub" else "unsub", "sr_name" to subredditName))
        subsCache = null // subscription set changed
    }

    suspend fun setSaved(fullname: String, saved: Boolean) {
        orGql({ client.post(if (saved) "/api/save" else "/api/unsave", mapOf("id" to fullname)) }) {
            val post = fullname.startsWith("t3_")
            gqlMutation(
                if (post) "UpdatePostSaveState" else "UpdateCommentSaveState",
                if (post) GQL_POST_SAVE else GQL_COMMENT_SAVE,
                if (post) "updatePostSaveState" else "updateCommentSaveState",
            ) { put(if (post) "postId" else "commentId", fullname); put("saveState", if (saved) "SAVED" else "NONE") }
        }
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
        val c = Comment.fromChild(thing, depth)
        // A website session gets the legacy reply format: id + rendered HTML,
        // no author, body or timestamp. Fill those in from what was sent, or
        // the new comment shows up blank (it looked like the reply vanished).
        if (c.body.isNotEmpty() && c.author != "[deleted]") return c
        return c.copy(
            author = app.session.username,
            body = text,
            parentId = c.parentId.ifEmpty { parentFullname },
            createdUtc = System.currentTimeMillis(),
            score = 1,
            likes = true,
        )
    }

    /** Reddit's answer when a subreddit doesn't allow images in comments. */
    private fun isImageRefusal(message: String?): Boolean {
        val m = message?.lowercase() ?: return false
        return "image" in m || "media" in m || "richtext" in m || "not allowed" in m
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
        suspend fun viaCatbox(): Comment {
            val url = uploadToCatbox(bytes, filename)
            return reply(parentFullname, if (text.isEmpty()) url else "$text\n\n$url", depth = depth)
        }
        // Reddit wouldn't take the image (upload failed): host it on Catbox.
        val asset = try {
            uploadMediaAsset(bytes, filename, mimeType)
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (_: Exception) {
            return viaCatbox()
        }
        return try {
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
        } catch (e: RedditApiException) {
            // Only when the subreddit refuses images in comments. Anything else
            // (rate limit, locked thread, a network error after Reddit may have
            // accepted it) is reported as-is: falling back then published the
            // image on Catbox and could post the comment twice.
            if (!isImageRefusal(e.message)) throw e
            viaCatbox()
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            if (e is java.io.IOException || !isImageRefusal(e.message)) throw e
            viaCatbox()
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
        val id = res["json"]["data"]["id"].str()
        // Image posts are created asynchronously: Reddit answers with a
        // websocket URL, not the id. No errors means it was posted (treating it
        // as a failure invited a duplicate post).
        if (id == null && kind == "image") return ""
        return id ?: throw Exception("Reddit did not return the new post.")
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

    /**
     * Your user flair in [subreddit] (from its About, which carries it for the
     * signed-in user) and the choices it offers (user_flair_v2; empty when it
     * has none for you, or won't let you pick).
     */
    suspend fun getUserFlairSelector(subreddit: String): UserFlairSelector {
        val about = client.get("/r/$subreddit/about")["data"]
        val choices = try {
            // ".json": the website session's www host 404s this path without it.
            client.get("/r/$subreddit/api/user_flair_v2.json").arr().orEmpty().mapNotNull { c ->
                UserFlairChoice(
                    id = c["id"].str() ?: return@mapNotNull null,
                    text = c["text"].str()?.trim().orEmpty(),
                    editable = c["text_editable"].isTrue(),
                )
            }
        } catch (_: Exception) {
            emptyList() // 403: no user flair here for you
        }
        return UserFlairSelector(
            currentText = about["user_flair_text"].str()?.replace(Regex(":[\\w-]+:"), "")?.trim()?.ifEmpty { null },
            currentId = about["user_flair_template_id"].str()?.ifEmpty { null },
            choices = choices,
        )
    }

    /** Sets your user flair in [subreddit] ([choice] null: no flair). [text]: your words, for an editable choice. */
    suspend fun setUserFlair(subreddit: String, username: String, choice: UserFlairChoice?, text: String?) {
        val data = linkedMapOf<String, Any?>("api_type" to "json", "name" to username)
        if (choice != null) {
            data["flair_template_id"] = choice.id
            if (choice.editable && text != null) data["text"] = text
        }
        throwIfErrors(client.post("/r/$subreddit/api/selectflair", data))
    }

    /** The post flairs you can pick in [subreddit] (v2: with colours, emoji and editable text; ".json" as for user flair). */
    suspend fun getLinkFlairs(subreddit: String): List<Flair> = try {
        (client.get("/r/$subreddit/api/link_flair_v2.json").arr() ?: emptyList()).map(Flair::fromJson).filter { it.text.isNotEmpty() }
    } catch (_: Exception) {
        emptyList() // subreddit may have no flairs / no permission
    }

    /** Sets the flair of your post [postFullname] in [subreddit] ([flair] null: no flair; its text is yours for an editable one). */
    suspend fun setPostFlair(subreddit: String, postFullname: String, flair: Flair?) {
        throwIfErrors(client.post("/r/$subreddit/api/selectflair", postFlairForm(postFullname, flair)))
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

    /** Renames / re-describes a custom feed, or makes it public or private (its communities stay). */
    suspend fun updateMultireddit(multi: Multireddit, displayName: String, description: String, visibility: String) {
        val multipath = multi.path.trimEnd('/')
        val model = buildJsonObject {
            put("display_name", displayName)
            put("description_md", description)
            put("visibility", visibility)
            put("subreddits", JsonArray(multi.subreddits.map { buildJsonObject { put("name", it) } }))
        }
        throwIfErrors(client.putForm("/api/multi$multipath", mapOf("model" to model.toString(), "multipath" to multipath, "api_type" to "json")))
    }

    /** Copies someone's (public) custom feed into yours as [displayName]. */
    suspend fun copyMultireddit(fromPath: String, username: String, displayName: String) {
        val name = displayName.lowercase().replace(Regex("[^a-z0-9_]+"), "_").trim('_').take(50).ifEmpty { "feed" }
        throwIfErrors(
            client.post(
                "/api/multi/copy",
                mapOf("from" to fromPath.trimEnd('/'), "to" to "/user/$username/m/$name", "display_name" to displayName, "api_type" to "json"),
            ),
        )
    }

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

    companion object {
        /** /api/selectflair's form for a post's flair; the text only for an editable template, as for user flair. */
        fun postFlairForm(postFullname: String, flair: Flair?): Map<String, Any?> {
            val data = linkedMapOf<String, Any?>("api_type" to "json", "link" to postFullname)
            if (flair != null) {
                data["flair_template_id"] = flair.id
                if (flair.editable) data["text"] = flair.text
            }
            return data
        }
    }
}
