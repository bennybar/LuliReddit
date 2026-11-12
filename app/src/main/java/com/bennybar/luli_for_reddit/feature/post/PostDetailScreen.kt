package com.bennybar.luli_for_reddit.feature.post

import androidx.compose.runtime.Immutable
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.platform.LocalDensity
import com.bennybar.luli_for_reddit.state.LocalAuthorIcons
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.ui.graphics.Brush
import com.bennybar.luli_for_reddit.ui.SearchIcon
import com.bennybar.luli_for_reddit.ui.subredditName
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.ui.input.nestedscroll.nestedScroll
import com.bennybar.luli_for_reddit.feature.feed.FabScroll
import com.bennybar.luli_for_reddit.feature.feed.CollapsingFab
import com.bennybar.luli_for_reddit.settings.ThreadFab
import com.bennybar.luli_for_reddit.settings.ThreadFabPosition
import androidx.compose.material3.FabPosition
import androidx.compose.material.icons.rounded.VerticalAlignTop
import com.bennybar.luli_for_reddit.settings.calmComments
import com.bennybar.luli_for_reddit.ui.ToggleIcon
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.material3.MenuDefaults
import androidx.compose.material3.DropdownMenuGroup
import androidx.compose.material3.DropdownMenuPopup
import com.bennybar.luli_for_reddit.ui.PickOneMenu
import com.bennybar.luli_for_reddit.ui.RefreshBox
import com.bennybar.luli_for_reddit.ui.Loading
import com.bennybar.luli_for_reddit.model.UserFlair
import com.bennybar.luli_for_reddit.feature.media.GalleryM3Carousel
import androidx.compose.foundation.layout.widthIn
import com.bennybar.luli_for_reddit.feature.feed.ReminderLine
import com.bennybar.luli_for_reddit.feature.reminders.PostReminders
import com.bennybar.luli_for_reddit.feature.feed.PollOptions
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.lazy.layout.LazyLayoutCacheWindow
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.Reply
import androidx.compose.material.icons.automirrored.rounded.Sort
import androidx.compose.material.icons.outlined.ModeComment
import androidx.compose.material.icons.rounded.AddCircleOutline
import androidx.compose.material.icons.rounded.AddComment
import androidx.compose.material.icons.rounded.Link
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Bookmark
import androidx.compose.material.icons.rounded.BookmarkBorder
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.FiberNew
import androidx.compose.material.icons.rounded.Forum
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.KeyboardArrowUp
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.Translate
import androidx.compose.material.icons.automirrored.rounded.OpenInNew
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.PlayCircleFilled
import androidx.compose.material.icons.rounded.RecordVoiceOver
import androidx.compose.material.icons.rounded.PushPin
import androidx.compose.material.icons.rounded.Repeat
import androidx.compose.material.icons.rounded.Share
import androidx.compose.material.icons.rounded.SearchOff
import androidx.compose.material.icons.rounded.SubdirectoryArrowRight
import androidx.compose.material.icons.rounded.UnfoldLess
import androidx.compose.material.icons.rounded.UnfoldMore
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import coil3.compose.AsyncImage
import com.bennybar.luli_for_reddit.feature.media.rememberPauseWhileScrolling
import com.bennybar.luli_for_reddit.feature.media.LocalListScrolling
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.feature.settings.PickOption
import com.bennybar.luli_for_reddit.feature.settings.pickOption
import androidx.compose.ui.unit.Dp
import com.bennybar.luli_for_reddit.core.Translate
import com.bennybar.luli_for_reddit.core.compactNumber
import com.bennybar.luli_for_reddit.core.redditPostRoute
import com.bennybar.luli_for_reddit.feature.feed.redditLinkLabel
import com.bennybar.luli_for_reddit.feature.feed.rememberCrosspost
import com.bennybar.luli_for_reddit.core.extractMediaLinks
import com.bennybar.luli_for_reddit.core.bodySegments
import com.bennybar.luli_for_reddit.core.BodySegment
import com.bennybar.luli_for_reddit.core.isGifUrl
import com.bennybar.luli_for_reddit.core.isVideoUrl
import com.bennybar.luli_for_reddit.core.timeAgo
import com.bennybar.luli_for_reddit.data.COMMENT_SORTS
import com.bennybar.luli_for_reddit.feature.markdown.IconTooltip
import com.bennybar.luli_for_reddit.feature.markdown.RedditMarkdown
import com.bennybar.luli_for_reddit.feature.media.GalleryCarousel
import com.bennybar.luli_for_reddit.feature.media.NsfwBlur
import com.bennybar.luli_for_reddit.model.Comment
import com.bennybar.luli_for_reddit.model.Post
import com.bennybar.luli_for_reddit.model.Flair
import com.bennybar.luli_for_reddit.feature.compose.pickLinkFlair
import androidx.compose.runtime.produceState
import androidx.compose.material.icons.rounded.LocalOffer
import com.bennybar.luli_for_reddit.model.PostType
import com.bennybar.luli_for_reddit.nav.AppNavigator
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.nav.NavCache
import com.bennybar.luli_for_reddit.nav.Route
import com.bennybar.luli_for_reddit.feature.feed.CalmFlair
import com.bennybar.luli_for_reddit.feature.feed.CalmGhost
import com.bennybar.luli_for_reddit.feature.feed.CalmPill
import com.bennybar.luli_for_reddit.feature.feed.CalmVoteGroup
import com.bennybar.luli_for_reddit.feature.feed.LetterAvatar
import com.bennybar.luli_for_reddit.feature.feed.avatarTones
import com.bennybar.luli_for_reddit.model.Subreddit
import com.bennybar.luli_for_reddit.settings.PostDisplay
import com.bennybar.luli_for_reddit.settings.Settings
import com.bennybar.luli_for_reddit.settings.SwipeAction
import com.bennybar.luli_for_reddit.state.PostOverrides
import com.bennybar.luli_for_reddit.ui.Overlays
import com.bennybar.luli_for_reddit.ui.friendlyError
import com.bennybar.luli_for_reddit.ui.theme.LocalVoteColors
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.flow.first
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.rememberUpdatedState
import kotlinx.coroutines.launch

/** Depth-edge colors (rotate by nesting level). */
private val railColors = listOf(
    Color(0xFF9F8BE8),
    Color(0xFF62B5AA),
    Color(0xFFE0A55C),
    Color(0xFFD88FB4),
    Color(0xFF7E9BE0),
)

/** A post + threaded comments. The already-loaded Post, if any, is in NavCache under postId. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PostDetailScreen(subreddit: String, postId: String, focusCommentId: String?) {
    val nav = LocalNavigator.current
    val vm: CommentsViewModel = viewModel(key = "post:$subreddit/$postId/${focusCommentId.orEmpty()}") {
        CommentsViewModel(subreddit, postId, focusCommentId)
    }
    val ui by vm.state.collectAsStateWithLifecycle()
    val dwell: ThreadDwell = viewModel(key = "dwell:$postId/${focusCommentId.orEmpty()}") { ThreadDwell(postId) }
    val initialPost = remember(postId) { NavCache.get<Post>(postId) }
    val session by app.session.state.collectAsStateWithLifecycle()
    val username = remember(session) { app.session.username }
    val aiKey by app.post.aiKey.collectAsStateWithLifecycle()
    val settings by app.settings.state.collectAsStateWithLifecycle()
    // Back from voting in this post's poll on Reddit: load the results.
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        if (app.post.pollVoteOpened == postId) {
            app.post.pollVoteOpened = null
            vm.refresh()
        }
    }
    // Translated (Translate in the top bar, or Settings → Auto-translate).
    val thread = remember(ui.thread, ui.translation, ui.commentTranslations) { ui.thread?.translated(ui.shownTexts) }
    val flat = thread?.flat ?: emptyList()
    val since = dwell.since
    dwell.post = thread?.post ?: initialPost

    LaunchedEffect(Unit) { app.post.refreshAiKey() }
    ThreadLifecycle(dwell, nav)

    // Build comments about a screen ahead, so scrolling shows ready-made rows
    // instead of composing them mid-frame.
    @OptIn(ExperimentalFoundationApi::class)
    val listState = rememberLazyListState(cacheWindow = LazyLayoutCacheWindow(ahead = 900.dp, behind = 300.dp))
    val scope = rememberCoroutineScope()
    val haptic = LocalHapticFeedback.current

    // In-post comment search. Matches by fullname, not list position:
    // collapsing or loading more replies shifts positions.
    var searchOpen by remember { mutableStateOf(false) }
    var query by remember { mutableStateOf("") }
    var matchIds by remember { mutableStateOf<List<String>>(emptyList()) }
    var matchPos by remember { mutableIntStateOf(0) }
    var currentMatchId by remember { mutableStateOf<String?>(null) }

    fun isNew(c: Comment) = since != null && !c.isMore && c.author != username && c.createdUtc > since

    fun scrollToMatch() {
        if (matchIds.isEmpty()) return
        currentMatchId = matchIds[matchPos]
        // Resolve against the list as it is now; a match hidden inside a
        // collapsed thread has no row to scroll to.
        val ci = flat.indexOfFirst { it.fullname == currentMatchId }
        if (ci < 0) return
        scope.launch {
            val h = listState.layoutInfo.viewportSize.height
            listState.animateScrollToItem(ci + 1, -(h * 0.12f).toInt())
        }
    }

    fun runSearch(raw: String) {
        val q = raw.trim().lowercase()
        val m = if (q.isEmpty()) emptyList() else flat.filter { !it.isMore && it.body.lowercase().contains(q) }.map { it.fullname }
        matchIds = m
        matchPos = 0
        currentMatchId = m.firstOrNull()
        if (m.isNotEmpty()) scrollToMatch()
    }

    fun stepMatch(delta: Int) {
        if (matchIds.isEmpty()) return
        matchPos = (matchPos + delta + matchIds.size) % matchIds.size
        scrollToMatch()
    }

    fun toggleSearch() {
        searchOpen = !searchOpen
        if (!searchOpen) {
            query = ""
            matchIds = emptyList()
            currentMatchId = null
        }
    }

    /**
     * Scrolls to the next comment below the current top that passes [match],
     * wrapping to the first when moving forward. False when none does. List
     * index 0 is the post header, so comment `ci` lives at list index `ci + 1`.
     */
    fun jumpNext(backwards: Boolean = false, match: (Comment) -> Boolean): Boolean {
        if (flat.isEmpty()) return false
        val topIndex = listState.firstVisibleItemIndex
        val hits = flat.indices.filter { !flat[it].isMore && match(flat[it]) }.map { it + 1 }
        if (hits.isEmpty()) return false
        val target = if (backwards) hits.lastOrNull { it < topIndex } ?: return false
        else hits.firstOrNull { it > topIndex } ?: hits.first()
        scope.launch { listState.animateScrollToItem(target) }
        return true
    }

    // Settings → Volume keys move between comments: while this thread is the
    // screen on top, the activity hands volume presses here.
    val latestJump = rememberUpdatedState<(Boolean) -> Boolean> { up -> jumpNext(backwards = up) { it.depth == 0 } }
    LifecycleResumeEffect(Unit) {
        val h: (Boolean) -> Boolean = { up -> latestJump.value(up) }
        VolumeKeys.handler = h
        onPauseOrDispose { if (VolumeKeys.handler === h) VolumeKeys.handler = null }
    }

    val actions = remember(vm, nav) { ThreadActions(vm, nav, scope) }
    actions.post = thread?.post
    actions.flat = flat
    actions.translatedComments = ui.commentTranslations.keys
    actions.translateButton = if (ui.translateTargets.isEmpty()) null else {
        { size -> TranslateButton(ui.translateTargets, ui.translatedTo, ui.translating, vm::translateTo, size) }
    }

    // A reply just posted: once it's in the list, scroll to it and highlight
    // it for a moment (the search highlight).
    var revealId by remember { mutableStateOf<String?>(null) }
    actions.reveal = { revealId = it }
    val latestFlat by rememberUpdatedState(flat)
    LaunchedEffect(revealId) {
        val id = revealId ?: return@LaunchedEffect
        // Keyed on the id only (clearing it at the start would cancel this
        // before it scrolls); wait for the row to appear in the list.
        val ci = withTimeoutOrNull(2_000) {
            snapshotFlow { latestFlat.indexOfFirst { it.fullname == id } }.first { it >= 0 }
        } ?: return@LaunchedEffect
        currentMatchId = id
        val h = listState.layoutInfo.viewportSize.height
        listState.animateScrollToItem(ci + 1, -(h * 0.25f).toInt())
        delay(1800)
        if (currentMatchId == id && !searchOpen) currentMatchId = null
        revealId = null
    }

    val fab = remember { FabScroll() }
    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        thread?.post?.subredditPrefixed?.let { subredditName(it) } ?: if (subreddit == "_") "Post" else subredditName(subreddit),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = { nav.pop() }) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") }
                },
                actions = {
                    if (thread != null) {
                        SortMenu(vm.currentSort, vm::changeSort)
                        IconTooltip("Search comments") {
                            IconButton(onClick = ::toggleSearch) {
                                Icon(if (searchOpen) Icons.Rounded.SearchOff else SearchIcon, "Search comments")
                            }
                        }
                        IconButton(onClick = { showPostActionsSheet(thread.post) }) { Icon(Icons.Rounded.MoreVert, "More") }
                        if (username.isNotEmpty() && thread.post.author == username) OwnPostMenu(thread.post, vm, nav)
                    }
                },
            )
        },
        floatingActionButtonPosition = when (settings.threadFabPosition) {
            ThreadFabPosition.LEFT -> FabPosition.Start
            ThreadFabPosition.MIDDLE -> FabPosition.Center
            ThreadFabPosition.RIGHT -> FabPosition.End
        },
        floatingActionButton = {
            if (thread != null) {
                val newCount = remember(flat, since, username) { flat.count(::isNew) }
                val opAuthor = thread.post.author
                val hasOp = remember(flat, opAuthor, settings.threadJumpOp) {
                    settings.threadJumpOp && opAuthor.isNotEmpty() && opAuthor != "[deleted]" && flat.any { !it.isMore && it.author == opAuthor }
                }
                val hasMine = remember(flat, username, settings.threadJumpMine) {
                    settings.threadJumpMine && username.isNotEmpty() && flat.any { !it.isMore && it.author == username }
                }
                ThreadToolbar(
                    newCount = newCount,
                    hasOp = hasOp,
                    hasMine = hasMine,
                    hasComments = settings.threadJumpNext && thread.comments.isNotEmpty(), // the ↓ button (#121)
                    onPrevNew = { jumpNext(backwards = true, match = ::isNew) },
                    onNextNew = { jumpNext(match = ::isNew) },
                    onOp = { jumpNext { it.author == opAuthor } },
                    onPrevOp = {
                        haptic.performHapticFeedback(HapticFeedbackType.SegmentTick)
                        jumpNext(backwards = true) { it.author == opAuthor }
                    },
                    onMine = { jumpNext { it.author == username } },
                    onPrevMine = {
                        haptic.performHapticFeedback(HapticFeedbackType.SegmentTick)
                        jumpNext(backwards = true) { it.author == username }
                    },
                    button = settings.threadFab,
                    position = settings.threadFabPosition,
                    onComment = { actions.replyToPost() },
                    onTop = { scope.launch { listState.animateScrollToItem(0) } },
                    onSummarize = if (!aiKey.isNullOrEmpty()) ({ showSummarySheet(thread.post, flat) }) else null,
                    onAsk = if (!aiKey.isNullOrEmpty()) ({ showAskSheet(thread.post, flat) { id -> revealId = id } }) else null,
                    onNext = { jumpNext { it.depth == 0 } },
                    onPrev = {
                        haptic.performHapticFeedback(HapticFeedbackType.SegmentTick)
                        jumpNext(backwards = true) { it.depth == 0 }
                    },
                    expanded = fab.expanded,
                )
            }
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(top = padding.calculateTopPadding()).nestedScroll(fab)) {
            when {
                thread != null -> Column(Modifier.fillMaxSize()) {
                    if (focusCommentId != null) FocusBanner { nav.pop(); nav.push(Route.Post(subreddit, postId)) }
                    RefreshBox(isRefreshing = ui.refreshing, onRefresh = vm::refresh, modifier = Modifier.weight(1f)) {
                        CommentList(
                            thread = thread,
                            listState = listState,
                            username = username,
                            isNew = ::isNew,
                            currentMatchId = currentMatchId,
                            settings = settings,
                            actions = actions,
                        )
                    }
                }
                ui.error != null && !ui.loading -> Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(
                            "Could not load this post.\n${friendlyError(ui.error)}",
                            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                        )
                        Spacer(Modifier.height(16.dp))
                        Button(onClick = vm::refresh) { Text("Retry") }
                    }
                }
                // Paint the post we already have (from the feed) while comments load.
                else -> LazyColumn(Modifier.fillMaxSize()) {
                    if (initialPost != null) item(key = "header") { PostHeader(initialPost, fresh = false) }
                    item(key = "loading") {
                        Box(Modifier.fillMaxWidth().padding(40.dp), contentAlignment = Alignment.Center) { Loading() }
                    }
                }
            }
            if (searchOpen && thread != null) {
                SearchBar(
                    query = query,
                    onQuery = { query = it; runSearch(it) },
                    total = matchIds.size,
                    pos = matchPos,
                    onStep = ::stepMatch,
                    onClose = ::toggleSearch,
                    modifier = Modifier.align(Alignment.TopCenter).padding(8.dp),
                )
            }
        }
    }
}

/** Pause/resume reading time with the screen; learn when another screen covers it. */
@Composable
private fun ThreadLifecycle(dwell: ThreadDwell, nav: AppNavigator) {
    val owner = LocalLifecycleOwner.current
    DisposableEffect(owner) {
        val obs = LifecycleEventObserver { _, e ->
            when (e) {
                Lifecycle.Event.ON_RESUME -> dwell.resume()
                Lifecycle.Event.ON_PAUSE -> dwell.pause()
                // A pushed profile or subreddit covers the thread: learn from
                // what was read so far (backgrounding the app doesn't count).
                Lifecycle.Event.ON_STOP -> if (nav.controller.currentBackStackEntry !== owner) dwell.learn()
                else -> {}
            }
        }
        owner.lifecycle.addObserver(obs)
        onDispose { owner.lifecycle.removeObserver(obs) }
    }
}

/**
 * Reading time in a thread, counted only while it's on screen and the app is
 * in the foreground — the strongest cheap signal there is: a post read for
 * two minutes is a far stronger "more like this" than one backed out of at
 * once. Each tier is awarded at most once per visit. Also remembers the
 * previous visit (for "new comments") and records this one.
 */
class ThreadDwell(postId: String) : androidx.lifecycle.ViewModel() {
    /** Previous visit to this thread (millis); null on the first. */
    val since: Long? = app.threadVisits.lastVisit(postId)
    var post: Post? = null
    private var startedAt: Long? = System.currentTimeMillis()
    private var accumulated = 0L
    private val awarded = HashSet<String>()

    init {
        // Remember the previous visit before recording this one: comments
        // posted since then are marked new.
        app.threadVisits.record(postId)
    }

    fun resume() {
        if (startedAt == null) startedAt = System.currentTimeMillis()
    }

    fun pause() {
        startedAt?.let { accumulated += System.currentTimeMillis() - it }
        startedAt = null
    }

    fun learn() {
        val p = post ?: return
        val running = startedAt?.let { System.currentTimeMillis() - it } ?: 0L
        val seconds = ((accumulated + running) / 1000).coerceIn(0, 600)
        val learner = app.forYou.learner
        if (seconds < 3) {
            if (awarded.isEmpty() && awarded.add("bounce")) learner.bounce(p)
            return
        }
        // 3s+ is real engagement (opening alone isn't: it may be a bounce).
        if (awarded.add("dwell")) learner.dwell(p)
        if (seconds >= 30 && awarded.add("read")) learner.read(p)
        if (seconds >= 120 && awarded.add("longRead")) learner.read(p, long = true)
    }

    override fun onCleared() {
        pause()
        learn()
    }
}

/** Row actions for the comment list, in one stable object (rows stay skippable). */
@Stable
private class ThreadActions(val vm: CommentsViewModel, val nav: AppNavigator, val scope: CoroutineScope) {
    var post: Post? = null
    var flat: List<Comment> = emptyList()

    fun toggle(c: Comment) = vm.toggleCollapse(c.id)
    fun unfold(c: Comment) = vm.unfold(c.id)

    fun loadMore(c: Comment) {
        val p = post ?: return
        // A "more" stub with no children ids is Reddit's "continue this
        // thread": the replies are too deep to fetch here, so open that
        // branch in single-comment focus mode.
        if (c.moreChildren.isEmpty() && c.parentId.startsWith("t1_")) {
            nav.openPost(p, focusCommentId = c.parentId.removePrefix("t1_"))
        } else {
            vm.loadMore(c)
        }
    }

    /** Set by the screen: scroll to and briefly highlight a comment (a reply just posted). */
    var reveal: (String) -> Unit = {}

    private fun onReplied(parent: String, reply: Comment) {
        val p = post ?: return
        vm.insertReply(parent, reply)
        // The new comment lands at the top of the thread or under its parent —
        // often off-screen, so it looked like nothing happened. Bring it in.
        reveal(reply.fullname)
        app.postOverrides.bumpComments(p, 1)
        // Commenting is the strongest engagement signal we have.
        app.forYou.learner.comment(p)
    }

    fun replyToPost() {
        val p = post ?: return
        scope.launch { showReplySheet(p.fullname, parentDepth = -1, post = p)?.let { onReplied(p.fullname, it) } }
    }

    fun reply(c: Comment) {
        scope.launch { showReplySheet(c.fullname, c.depth, replyingTo = c.author, post = post)?.let { onReplied(c.fullname, it) } }
    }

    fun edit(c: Comment) {
        scope.launch { showEditSheet(c.fullname, c.body)?.let { vm.applyEdit(c.fullname, it) } }
    }

    fun delete(c: Comment) {
        scope.launch {
            if (!confirmDelete("comment")) return@launch
            try {
                app.repository.deleteThing(c.fullname)
                vm.removeComment(c.fullname)
            } catch (e: Exception) {
                nav.showActionError("delete", e)
            }
        }
    }

    fun vote(c: Comment, dir: Int) {
        val current = PostOverrides.dirOf(c.likes)
        val target = if (current == dir) 0 else dir
        // Upvoting comments says you're into this thread's subreddit.
        if (target == 1) post?.let { app.forYou.learner.commentUpvote(it) }
        vm.updateComment(c.fullname) {
            it.copy(score = it.score + target - current, likes = when (target) { 1 -> true; -1 -> false; else -> null })
        }
        app.commentVotes.setVote(c, target)
        scope.launch {
            try {
                app.repository.vote(c.fullname, target)
            } catch (e: Exception) {
                vm.updateComment(c.fullname) { it.copy(score = c.score, likes = c.likes) }
                app.commentVotes.setVote(c, current)
                nav.showActionError("vote", e)
            }
        }
    }

    fun toggleSave(c: Comment) {
        val next = !c.saved
        vm.updateComment(c.fullname) { it.copy(saved = next) }
        scope.launch {
            try {
                app.repository.setSaved(c.fullname, next)
            } catch (e: Exception) {
                vm.updateComment(c.fullname) { it.copy(saved = !next) }
                nav.showActionError(if (next) "save" else "unsave", e)
            }
        }
    }

    fun shareImage(c: Comment) {
        val p = post ?: return
        showShareCommentImage(p, CommentTree.chainTo(flat, c))
    }

    fun share(c: Comment) = nav.share("https://reddit.com${c.permalink}")

    /** The post's Translate button, when it has languages to offer (set by the screen). */
    var translateButton: (@Composable (Dp) -> Unit)? = null

    /** Comments translated one by one (set by the screen). */
    var translatedComments: Set<String> = emptySet()

    /** ⋯ → Translate / Show original on one comment. */
    fun translate(c: Comment) = vm.translateComment(c.fullname) { targets ->
        pickOption(targets.map { PickOption(it, "Translate to ${Translate.languageName(it)}") }, null, radio = false)
    }

    fun block(c: Comment) {
        scope.launch { confirmBlockUser(c.author) }
    }

    fun mod(c: Comment, doneMsg: String, action: suspend (com.bennybar.luli_for_reddit.data.RedditRepository) -> Unit) {
        scope.launch {
            if (!modAction(doneMsg, action)) return@launch
            if (doneMsg.startsWith("Distinguished")) vm.updateComment(c.fullname) { it.copy(distinguished = "moderator") }
            else if (doneMsg.startsWith("Undistinguished")) vm.updateComment(c.fullname) { it.copy(distinguished = null) }
        }
    }
}

@Composable
private fun CommentList(
    thread: PostThread,
    listState: LazyListState,
    username: String,
    isNew: (Comment) -> Boolean,
    currentMatchId: String?,
    settings: Settings,
    actions: ThreadActions,
) {
    val flat = thread.flat
    // Animated images in the thread pause while it scrolls (see rememberPauseWhileScrolling).
    val scrolling = remember(listState) { { listState.isScrollInProgress } }
    val icons by app.authorAvatars.icons.collectAsState()
    CompositionLocalProvider(LocalListScrolling provides scrolling, LocalAuthorIcons provides if (settings.commentAvatars) icons else emptyMap()) {
        LazyColumn(
            Modifier.fillMaxSize(),
            state = listState,
            // Room for the floating buttons, so the last comment clears them.
            contentPadding = PaddingValues(top = 6.dp, bottom = 160.dp),
        ) {
            item(key = "header", contentType = "header") {
                // Translate sits on the post, with its share / save.
                PostHeader(thread.post, fresh = true, translate = actions.translateButton)
            }
            if (flat.isEmpty()) {
                item(key = "empty", contentType = "empty") {
                    Box(Modifier.fillMaxWidth().padding(40.dp), contentAlignment = Alignment.Center) { Text("No comments yet") }
                }
            } else if (settings.calmComments) {
                // Calm: one container per top-level thread, drawn as contiguous
                // rows (still one lazy item per comment) whose first / last
                // rows round the container's top / bottom.
                itemsIndexed(flat, key = { _, c -> c.fullname }, contentType = { _, c -> if (c.isMore) "more" else "comment" }) { i, c ->
                    val first = i == 0 || c.depth == 0
                    val last = i == flat.lastIndex || flat[i + 1].depth == 0
                    val rails = CalmRails(c.depth, prev = if (i == 0) 0 else flat[i - 1].depth, next = if (i == flat.lastIndex) 0 else flat[i + 1].depth)
                    CalmThreadRow(first, last, highlighted = currentMatchId == c.fullname, rails) {
                        if (c.isMore) {
                            MoreRow(c, loading = c.fullname in thread.loadingMore, onClick = { actions.loadMore(c) }, start = calmIndent(c.depth) - 6.dp)
                        } else {
                            Column {
                                CalmCommentRow(
                                    comment = c,
                                    isNew = isNew(c),
                                    isOwn = username.isNotEmpty() && c.author == username,
                                    opAuthor = thread.post.author,
                                    collapsed = c.id in thread.collapsed,
                                    settings = settings,
                                    actions = actions,
                                )
                                if (CommentTree.folded(c.id) in thread.collapsed && c.id !in thread.collapsed) FoldedReplies(c, actions)
                            }
                        }
                    }
                }
            } else {
                items(flat, key = { it.fullname }, contentType = { if (it.isMore) "more" else "comment" }) { c ->
                    if (c.isMore) {
                        MoreRow(c, loading = c.fullname in thread.loadingMore, onClick = { actions.loadMore(c) })
                    } else {
                        Column {
                            CommentTile(
                                comment = c,
                                highlighted = currentMatchId == c.fullname,
                                isNew = isNew(c),
                                isOwn = username.isNotEmpty() && c.author == username,
                                opAuthor = thread.post.author,
                                collapsed = c.id in thread.collapsed,
                                settings = settings,
                                actions = actions,
                            )
                            if (CommentTree.folded(c.id) in thread.collapsed && c.id !in thread.collapsed) FoldedReplies(c, actions)
                        }
                    }
                }
            }
        }
    }
}

/** Where volume presses go while a thread is on screen (Settings → Volume keys move between comments). */
object VolumeKeys {
    /** up = volume up; true if it moved. Null when no thread is showing. */
    @Volatile var handler: ((up: Boolean) -> Boolean)? = null
}

/** "Show 12 replies" under a top-level comment opened folded (Settings → Open threads collapsed). */
@Composable
private fun FoldedReplies(c: Comment, actions: ThreadActions) {
    val n = remember(c) { CommentTree.replyCount(c) }
    TextButton(onClick = { actions.unfold(c) }, modifier = Modifier.padding(start = 8.dp)) {
        Icon(Icons.Rounded.UnfoldMore, null, Modifier.size(16.dp))
        Spacer(Modifier.width(6.dp))
        Text(if (n == 1) "Show 1 reply" else "Show $n replies")
    }
}

/** Single-comment view (from an inbox reply / permalink): "Show all" opens the whole thread. */
@Composable
private fun FocusBanner(onShowAll: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    Surface(color = cs.secondaryContainer, modifier = Modifier.fillMaxWidth().clickable(onClick = onShowAll)) {
        Row(Modifier.padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.SubdirectoryArrowRight, null, Modifier.size(18.dp), tint = cs.onSecondaryContainer)
            Spacer(Modifier.width(8.dp))
            Text(
                "Viewing a single comment thread",
                Modifier.weight(1f),
                color = cs.onSecondaryContainer,
                fontWeight = FontWeight.SemiBold,
            )
            Text("Show all", color = cs.primary, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun SortMenu(current: String, onPick: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        IconTooltip("Sort comments") {
            IconButton(onClick = { open = true }) { Icon(Icons.AutoMirrored.Rounded.Sort, "Sort comments") }
        }
        PickOneMenu(open, { open = false }, COMMENT_SORTS, current, onPick)
    }
}

/** Edit (self posts), edit flair (where the sub has post flair) / delete for your own post. */
@Composable
private fun OwnPostMenu(post: Post, vm: CommentsViewModel, nav: AppNavigator) {
    var open by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    // Loaded up front so "Edit flair" only shows where the sub has post flair (#88).
    val flairs by produceState(emptyList<Flair>(), post.subreddit) { value = app.repository.getLinkFlairs(post.subreddit) }
    Box {
        IconButton(onClick = { open = true }) { Icon(Icons.Rounded.Edit, "Edit or delete") }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            // Image and gallery posts can carry body text too, and Reddit lets you edit it (#88).
            if (post.isSelf || post.selftext.isNotBlank()) {
                DropdownMenuItem(text = { Text("Edit") }, leadingIcon = { Icon(Icons.Rounded.Edit, null) }, onClick = {
                    open = false
                    scope.launch { showEditSheet(post.fullname, post.selftext)?.let { vm.applyEdit(post.fullname, it) } }
                })
            }
            if (flairs.isNotEmpty()) {
                DropdownMenuItem(text = { Text("Edit flair") }, leadingIcon = { Icon(Icons.Rounded.LocalOffer, null) }, onClick = {
                    open = false
                    scope.launch {
                        // Its template by text; one with your own words, or set by a mod, matches none (no check, not "No flair").
                        val current = post.linkFlairText?.let { t -> flairs.find { it.text == t } ?: Flair("", t) }
                        val pick = pickLinkFlair(post.subreddit, flairs, current) ?: return@launch
                        try {
                            app.repository.setPostFlair(post.subreddit, post.fullname, pick.flair)
                            vm.applyFlair(pick.flair)
                            nav.showSnackbar(if (pick.flair == null) "Flair removed" else "Flair set")
                        } catch (e: Exception) {
                            nav.showActionError("change the flair", e)
                        }
                    }
                })
            }
            DropdownMenuItem(text = { Text("Delete") }, leadingIcon = { Icon(Icons.Rounded.Delete, null) }, onClick = {
                open = false
                scope.launch {
                    if (!confirmDelete("post")) return@launch
                    try {
                        app.repository.deleteThing(post.fullname)
                        nav.pop()
                    } catch (e: Exception) {
                        nav.showActionError("delete", e)
                    }
                }
            })
        }
    }
}

@Composable
private fun SearchBar(
    query: String,
    onQuery: (String) -> Unit,
    total: Int,
    pos: Int,
    onStep: (Int) -> Unit,
    onClose: () -> Unit,
    modifier: Modifier,
) {
    val cs = MaterialTheme.colorScheme
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    Surface(
        modifier.fillMaxWidth(),
        shape = RoundedCornerShape(28.dp),
        color = cs.surfaceContainerHigh,
        shadowElevation = 4.dp,
    ) {
        Row(Modifier.padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Spacer(Modifier.width(6.dp))
            Icon(SearchIcon, null, Modifier.size(20.dp), tint = cs.onSurfaceVariant)
            TextField(
                value = query,
                onValueChange = onQuery,
                modifier = Modifier.weight(1f).focusRequester(focus),
                placeholder = { Text("Search comments") },
                singleLine = true,
                colors = androidx.compose.material3.TextFieldDefaults.colors(
                    focusedContainerColor = Color.Transparent,
                    unfocusedContainerColor = Color.Transparent,
                    focusedIndicatorColor = Color.Transparent,
                    unfocusedIndicatorColor = Color.Transparent,
                ),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                keyboardActions = KeyboardActions(onSearch = { onStep(1) }),
            )
            if (query.isNotBlank()) {
                Text(if (total == 0) "0/0" else "${pos + 1}/$total", fontSize = 12.sp, color = cs.onSurfaceVariant)
            }
            IconTooltip("Previous") {
                IconButton(onClick = { onStep(-1) }, enabled = total > 0, modifier = Modifier.size(40.dp)) {
                    Icon(Icons.Rounded.KeyboardArrowUp, "Previous")
                }
            }
            IconTooltip("Next") {
                IconButton(onClick = { onStep(1) }, enabled = total > 0, modifier = Modifier.size(40.dp)) {
                    Icon(Icons.Rounded.KeyboardArrowDown, "Next")
                }
            }
            IconTooltip("Close") {
                IconButton(onClick = onClose, modifier = Modifier.size(40.dp)) { Icon(Icons.Rounded.Close, "Close") }
            }
        }
    }
}

/**
 * Two levels, like WhatsApp's (#72): a row for moving through the thread,
 * [↑ N new ↓] [OP] [your comment] [summarize] [ask] [● next/prev top-level], over a big
 * New comment button that folds as you scroll.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ThreadToolbar(
    newCount: Int,
    hasOp: Boolean,
    hasMine: Boolean,
    hasComments: Boolean,
    onPrevNew: () -> Unit,
    onNextNew: () -> Unit,
    onOp: () -> Unit,
    onPrevOp: () -> Unit,
    onMine: () -> Unit,
    onPrevMine: () -> Unit,
    button: ThreadFab, // the big button under the row (#90)
    position: ThreadFabPosition,
    onComment: () -> Unit,
    onTop: () -> Unit,
    onSummarize: (() -> Unit)?,
    onAsk: (() -> Unit)?,
    onNext: () -> Unit,
    onPrev: () -> Unit,
    expanded: Boolean,
) {
    val cs = MaterialTheme.colorScheme
    val on = cs.onSurface

    @Composable
    fun btn(icon: ImageVector, tip: String, onLongClick: (() -> Unit)? = null, onClick: () -> Unit) {
        IconTooltip(tip) {
            if (onLongClick != null) {
                Box(
                    Modifier
                        .size(48.dp)
                        .clip(CircleShape)
                        .combinedClickable(onClick = onClick, onLongClick = onLongClick, onClickLabel = tip),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(icon, tip, Modifier.size(24.dp), tint = on)
                }
            } else {
                IconButton(onClick = onClick, modifier = Modifier.size(48.dp)) { Icon(icon, tip, Modifier.size(24.dp), tint = on) }
            }
        }
    }

    val align = when (position) {
        ThreadFabPosition.LEFT -> Alignment.Start
        ThreadFabPosition.MIDDLE -> Alignment.CenterHorizontally
        ThreadFabPosition.RIGHT -> Alignment.End
    }
    Column(horizontalAlignment = align, verticalArrangement = Arrangement.spacedBy(12.dp)) {
    if (newCount > 0 || hasOp || hasMine || onSummarize != null || onAsk != null || hasComments) Surface(color = cs.surfaceContainerHigh, shape = CircleShape, shadowElevation = 3.dp) {
        Row(Modifier.padding(4.dp), verticalAlignment = Alignment.CenterVertically) {
            if (newCount > 0) {
                // The new-comments stepper, on its own tonal segment.
                Row(
                    Modifier.height(48.dp).clip(CircleShape).background(on.copy(alpha = 0.08f)),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    btn(Icons.Rounded.KeyboardArrowUp, "Previous new comment", onClick = onPrevNew)
                    Text("$newCount new", fontSize = 12.sp, fontWeight = FontWeight.ExtraBold, color = on)
                    btn(Icons.Rounded.KeyboardArrowDown, "Next new comment", onClick = onNextNew)
                }
            }
            if (hasOp) btn(Icons.Rounded.RecordVoiceOver, "OP's comments (long-press for previous)", onLongClick = onPrevOp, onClick = onOp)
            if (hasMine) btn(Icons.Rounded.Person, "Your comments (long-press for previous)", onLongClick = onPrevMine, onClick = onMine)
            onSummarize?.let { btn(Icons.Rounded.AutoAwesome, "Summarize thread", onClick = it) }
            onAsk?.let { btn(Icons.Rounded.Forum, "Ask about this thread", onClick = it) }
            if (hasComments) {
                // The main action: a filled accent circle. Tap for next
                // top-level comment, long-press for previous.
                Box(
                    Modifier
                        .size(48.dp)
                        .clip(CircleShape)
                        .background(cs.primary)
                        .combinedClickable(onClick = onNext, onLongClick = onPrev, onClickLabel = "Next top-level comment"),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Rounded.KeyboardArrowDown, "Next top-level comment (long-press for previous)", tint = cs.onPrimary)
                }
            }
        }
    }
    when (button) {
        ThreadFab.NEW_COMMENT -> CollapsingFab(Icons.Rounded.AddComment, button.label, expanded, onClick = onComment)
        ThreadFab.SCROLL_TOP -> CollapsingFab(Icons.Rounded.VerticalAlignTop, button.label, expanded, onClick = onTop)
        ThreadFab.OFF -> {}
    }
    }
}

// ---------------------------------------------------------------------------
// Post header
// ---------------------------------------------------------------------------

/**
 * The post itself. [fresh]: the post as just fetched with its comments
 * (seeds the shared overrides so the feed card reflects it when you go back);
 * false for the feed's copy shown while loading, which can be stale.
 */
@Composable
private fun PostHeader(post: Post, fresh: Boolean, translate: (@Composable (Dp) -> Unit)? = null) {
    // A crosspost whose original the thread left out fills in once it's fetched.
    val p = rememberCrosspost(post)
    val cs = MaterialTheme.colorScheme
    val nav = LocalNavigator.current
    val scope = rememberCoroutineScope()
    LaunchedEffect(p) { if (fresh) app.postOverrides.syncFromServer(p) }
    val overrides by app.postOverrides.state.collectAsState()
    val ov = overrides[p.id]
    val likes = if (ov != null) ov.likes else p.likes
    val score = ov?.score ?: p.score
    val saved = ov?.saved ?: p.saved
    val numComments = ov?.numComments ?: p.numComments

    fun vote(dir: Int) {
        val o = app.postOverrides
        val current = PostOverrides.dirOf(o.effective(p).likes)
        val target = if (current == dir) 0 else dir
        o.setVote(p, target)
        // Same learning as a vote on the card.
        val learner = app.forYou.learner
        learner.vote(p, current, target)
        scope.launch {
            try {
                app.repository.vote(p.fullname, target)
            } catch (e: Exception) {
                learner.vote(p, target, current)
                o.setVote(p, current)
                nav.showActionError("vote", e)
            }
        }
    }

    fun toggleSave() {
        val o = app.postOverrides
        val next = !o.effective(p).saved
        o.setSaved(p, next)
        val learner = app.forYou.learner
        learner.save(p, next)
        if (next) PostReminders.offer(p) else PostReminders.cancel(p.id)
        scope.launch {
            try {
                app.repository.setSaved(p.fullname, next)
            } catch (e: Exception) {
                o.setSaved(p, !next)
                learner.save(p, !next)
                nav.showActionError(if (next) "save" else "unsave", e)
            }
        }
    }

    val settings by app.settings.state.collectAsState()
    // Settings → Mark what you voted on: the comments' glow on the post too (#141).
    val votes = LocalVoteColors.current
    val glow = if (!settings.voteEdge || !settings.voteGlow) null else when (likes) {
        true -> votes.up
        false -> votes.down
        null -> null
    }
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    if (settings.postDisplay.isCalm) {
        CalmPostHeader(p, fresh, score, likes, saved, numComments, ::vote, ::toggleSave, translate, Modifier.voteGlow(glow, rtl, fadeTop = true))
        return
    }

    Column(Modifier.fillMaxWidth().voteGlow(glow, rtl, fadeTop = true).padding(start = 16.dp, top = 12.dp, end = 16.dp, bottom = 8.dp)) {
        Text(
            subredditName(p.subredditPrefixed),
            Modifier.clickable { nav.openSubreddit(p.subreddit) },
            fontWeight = FontWeight.Bold,
            color = cs.primary,
        )
        Spacer(Modifier.height(2.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                "u/${p.author} · ${timeAgo(p.createdUtc)}",
                Modifier.clickable { nav.openUser(p.author) },
                fontSize = 12.sp,
                color = cs.onSurfaceVariant,
            )
            p.authorFlair?.let {
                Spacer(Modifier.width(6.dp))
                FlairChip(it)
            }
        }
        Spacer(Modifier.height(12.dp))
        Text(p.title, style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold, lineHeight = 1.3.em))
        p.linkFlair?.let {
            Spacer(Modifier.height(8.dp))
            com.bennybar.luli_for_reddit.feature.feed.Flair(it)
        }
        p.crosspostFrom?.let { from ->
            Spacer(Modifier.height(8.dp))
            // A tap opens the original post and its comments (#100).
            Row(
                Modifier
                    .clip(CircleShape)
                    .clickable(enabled = p.crosspostId != null, onClickLabel = "Open the original post") {
                        nav.push(Route.Post(from, p.crosspostId!!))
                    }
                    .padding(vertical = 2.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Rounded.Repeat, null, Modifier.size(14.dp), tint = cs.onSurfaceVariant)
                Spacer(Modifier.width(6.dp))
                Text("Crossposted from ${subredditName(from)}", fontSize = 12.sp, color = cs.onSurfaceVariant)
            }
        }
        ReminderLine(p)
        Spacer(Modifier.height(12.dp))
        PostMedia(p, nav)
        PollOptions(p)
        // Gallery/image/link posts can carry a body too — show it whenever
        // there's selftext, not only for pure self-posts.
        PostBody(p)
        Spacer(Modifier.height(12.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            VotePill(score, likes, onUp = { vote(1) }, onDown = { vote(-1) })
            Spacer(Modifier.width(8.dp))
            Row(
                Modifier
                    .height(36.dp)
                    .clip(RoundedCornerShape(50))
                    .border(1.dp, cs.outlineVariant, RoundedCornerShape(50))
                    .padding(horizontal = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Outlined.ModeComment, null, Modifier.size(18.dp), tint = cs.onSurfaceVariant)
                Spacer(Modifier.width(8.dp))
                Text(compactNumber(numComments), style = MaterialTheme.typography.labelLarge)
            }
            Spacer(Modifier.weight(1f))
            translate?.invoke(24.dp)
            ToggleIcon(saved, { toggleSave() }, Icons.Rounded.Bookmark, Icons.Rounded.BookmarkBorder, "Save")
        }
        HorizontalDivider(Modifier.padding(vertical = 12.dp))
    }
}

/**
 * The Calm post header: subreddit avatar + [r/sub / u/author · age] + a
 * Join pill, a 24sp regular title, the flair pill, media (radius 22) and
 * the connected vote group, then the comment count.
 */
@Composable
private fun CalmPostHeader(
    p: Post,
    fresh: Boolean,
    score: Int,
    likes: Boolean?,
    saved: Boolean,
    numComments: Int,
    vote: (Int) -> Unit,
    toggleSave: () -> Unit,
    translate: (@Composable (Dp) -> Unit)?,
    glow: Modifier,
) {
    val cs = MaterialTheme.colorScheme
    val nav = LocalNavigator.current
    val signedIn = app.session.username.isNotEmpty()
    // Icon + membership come from the subreddit's about (fetched once the
    // thread is in; the feed's copy shown while loading skips it).
    val about by androidx.compose.runtime.produceState<Subreddit?>(null, p.subreddit, fresh) {
        if (fresh) value = runCatching { app.repository.getSubredditAbout(p.subreddit) }.getOrNull()
    }
    var joinedOverride by remember(p.subreddit) { mutableStateOf<Boolean?>(null) }
    val joined = joinedOverride ?: about?.userIsSubscriber

    Column(Modifier.fillMaxWidth().then(glow).padding(start = 20.dp, top = 4.dp, end = 20.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            LetterAvatar(
                p.subreddit,
                size = 40.dp,
                container = cs.secondaryContainer,
                content = cs.onSecondaryContainer,
                imageUrl = about?.iconUrl,
                modifier = Modifier.clickable { nav.openSubreddit(p.subreddit) },
            )
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    subredditName(p.subredditPrefixed.ifEmpty { p.subreddit }),
                    Modifier.clickable { nav.openSubreddit(p.subreddit) },
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Medium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        "u/${p.author} · ${timeAgo(p.createdUtc)}",
                        Modifier.clickable { nav.openUser(p.author) },
                        fontSize = 12.5.sp,
                        color = cs.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    p.authorFlair?.let {
                        Spacer(Modifier.width(6.dp))
                        FlairChip(it)
                    }
                }
            }
            if (signedIn && joined != null) {
                Spacer(Modifier.width(8.dp))
                Box(
                    Modifier
                        .height(32.dp)
                        .clip(RoundedCornerShape(16.dp))
                        .background(cs.secondaryContainer)
                        .clickable {
                            val next = !joined
                            joinedOverride = next
                            app.scope.launch {
                                try {
                                    app.repository.setSubscribed(p.subreddit, next)
                                } catch (e: Exception) {
                                    joinedOverride = !next
                                    nav.showActionError(if (next) "join" else "leave", e)
                                }
                            }
                        }
                        .padding(horizontal = 14.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(if (joined) "Joined" else "Join", fontSize = 13.sp, fontWeight = FontWeight.Medium, color = cs.onSecondaryContainer)
                }
            }
        }
        Text(
            p.title,
            Modifier.padding(top = 14.dp),
            fontSize = 24.sp,
            fontWeight = FontWeight.Normal,
            lineHeight = 1.2.em,
            letterSpacing = (-0.01).em,
        )
        p.linkFlair?.let { CalmFlair(it, Modifier.padding(top = 8.dp)) }
        p.crosspostFrom?.let { from ->
            Spacer(Modifier.height(8.dp))
            // A tap opens the original post and its comments (#100).
            Row(
                Modifier
                    .clip(CircleShape)
                    .clickable(enabled = p.crosspostId != null, onClickLabel = "Open the original post") {
                        nav.push(Route.Post(from, p.crosspostId!!))
                    }
                    .padding(vertical = 2.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Rounded.Repeat, null, Modifier.size(14.dp), tint = cs.onSurfaceVariant)
                Spacer(Modifier.width(6.dp))
                Text("Crossposted from ${subredditName(from)}", fontSize = 12.sp, color = cs.onSurfaceVariant)
            }
        }
        ReminderLine(p)
        Spacer(Modifier.height(12.dp))
        PostMedia(p, nav, radius = 22.dp)
        PollOptions(p)
        PostBody(p)
        Row(Modifier.padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            CalmVoteGroup(score, likes, onUp = { vote(1) }, onDown = { vote(-1) }, height = 40.dp, iconSize = 19.dp, hPad = 14.dp)
            Spacer(Modifier.width(8.dp))
            CalmPill(Icons.Outlined.ModeComment, compactNumber(numComments), onClick = null, height = 40.dp, iconSize = 18.dp, hPad = 14.dp)
            Spacer(Modifier.weight(1f))
            translate?.invoke(20.dp)
            CalmGhost(Icons.Rounded.Share, "Share", cs.onSurfaceVariant, {
                app.forYou.learner.share(p)
                nav.share("https://reddit.com${p.permalink}", subject = p.title)
            }, size = 40.dp, iconSize = 20.dp)
            CalmGhost(
                if (saved) Icons.Rounded.Bookmark else Icons.Rounded.BookmarkBorder,
                if (saved) "Unsave" else "Save",
                if (saved) cs.primary else cs.onSurfaceVariant,
                toggleSave,
                size = 40.dp,
                iconSize = 20.dp,
                pop = saved,
            )
        }
        Text(
            "${compactNumber(numComments)} comments",
            Modifier.padding(top = 16.dp, bottom = 10.dp),
            fontSize = 16.sp,
            fontWeight = FontWeight.Medium,
        )
    }
}

private fun openMedia(p: Post, nav: AppNavigator) {
    when (p.type) {
        PostType.IMAGE -> nav.openImage(p.previewUrl ?: p.url, p.title)
        PostType.GIF -> if (p.gifMp4Url != null) {
            nav.openVideo(p.gifMp4Url, p.title, downloadUrl = p.gifMp4Url, externalUrl = p.url, gif = true)
        } else {
            nav.openImage(p.url, p.title)
        }
        PostType.GALLERY -> nav.openGallery(p.gallery, p.title)
        PostType.VIDEO -> nav.openPostVideo(p)
        // A link to a Reddit post (e.g. a crosspost whose original didn't load) opens in Ilay.
        // A share link (Post.shareLink) whose original didn't load is resolved on tap.
        PostType.LINK -> if (p.shareLink) nav.openLink(p.url) else redditPostRoute(p.url)?.let(nav::push) ?: nav.openInBrowser(p.url)
        PostType.SELF -> {}
    }
}

@Composable
private fun PostMedia(p: Post, nav: AppNavigator, radius: androidx.compose.ui.unit.Dp = 16.dp) {
    if (p.type == PostType.SELF) return
    val cs = MaterialTheme.colorScheme
    val blurNsfw by app.settings.state.collectAsState()
    val blur = (p.over18 && blurNsfw.blurNsfw) || p.spoiler
    val label = if (p.over18) "NSFW" else "Spoiler"
    if (p.type == PostType.GALLERY && p.gallery.isNotEmpty()) {
        NsfwBlur(blur, Modifier.padding(bottom = 12.dp), label = label) {
            if (p.gallery.size > 1) GalleryM3Carousel(p.gallery, title = p.title)
            else GalleryCarousel(p.gallery, if (radius != 16.dp) Modifier.clip(RoundedCornerShape(radius)) else Modifier, title = p.title)
        }
        return
    }
    if (p.type == PostType.LINK) {
        // The link's own picture (a news article's), as its card in the list has it (#130).
        val preview = p.previewUrl
        if (preview != null) {
            val w = p.previewWidth
            val h = p.previewHeight
            val aspect = if (w != null && h != null && h > 0) (w.toFloat() / h).coerceIn(0.5f, 2f) else 16f / 9f
            NsfwBlur(blur, Modifier.padding(bottom = 8.dp), blurredImageUrl = p.blurredPreviewUrl, label = label) {
                AsyncImage(
                    model = preview,
                    contentDescription = p.title,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .fillMaxWidth()
                        .aspectRatio(aspect)
                        .clip(RoundedCornerShape(radius))
                        .background(cs.surfaceContainerHighest)
                        .clickable { openMedia(p, nav) },
                )
            }
        }
        val inApp = remember(p.url) { redditLinkLabel(p) }
        OutlinedButton(onClick = { openMedia(p, nav) }, modifier = Modifier.padding(bottom = 12.dp)) {
            Icon(if (inApp != null) Icons.Rounded.Link else Icons.AutoMirrored.Rounded.OpenInNew, null, Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text(inApp ?: p.domain, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        return
    }
    val url = p.previewUrl
        ?: (if (p.type == PostType.IMAGE || p.type == PostType.GIF) p.url else null)
        ?: p.gallery.firstOrNull()?.url
    val w = p.previewWidth
    val h = p.previewHeight
    val aspect = if (w != null && h != null && h > 0) (w.toFloat() / h).coerceIn(0.5f, 2f) else 16f / 9f
    NsfwBlur(blur, Modifier.padding(bottom = 12.dp), blurredImageUrl = p.blurredPreviewUrl, label = label) {
        Box(
            Modifier
                .fillMaxWidth()
                .aspectRatio(aspect)
                .clip(RoundedCornerShape(radius))
                .background(cs.surfaceContainerHighest)
                .clickable { openMedia(p, nav) },
            contentAlignment = Alignment.Center,
        ) {
            if (url != null) {
                AsyncImage(
                    model = url,
                    contentDescription = p.title,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                    onSuccess = rememberPauseWhileScrolling(),
                )
            }
            if (p.type == PostType.VIDEO) {
                Box(Modifier.clip(CircleShape).background(Color.Black.copy(alpha = 0.54f)).padding(14.dp)) {
                    Icon(Icons.Rounded.PlayArrow, "Play", Modifier.size(36.dp), tint = Color.White)
                }
            }
        }
    }
}

@Composable
private fun VotePill(score: Int, likes: Boolean?, onUp: () -> Unit, onDown: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    val votes = LocalVoteColors.current
    val up = likes == true
    val down = likes == false
    Row(
        Modifier.clip(RoundedCornerShape(50)).background(cs.surfaceContainerHigh),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = onUp, modifier = Modifier.size(40.dp)) {
            Icon(Icons.Rounded.ArrowUpward, "Upvote", Modifier.size(20.dp), tint = if (up) votes.up else cs.onSurfaceVariant)
        }
        Text(
            compactNumber(score),
            fontWeight = FontWeight.Bold,
            color = if (up) votes.up else if (down) votes.down else cs.onSurfaceVariant,
        )
        IconButton(onClick = onDown, modifier = Modifier.size(40.dp)) {
            Icon(Icons.Rounded.ArrowDownward, "Downvote", Modifier.size(20.dp), tint = if (down) votes.down else cs.onSurfaceVariant)
        }
    }
}

// ---------------------------------------------------------------------------
// Comments
// ---------------------------------------------------------------------------

/** "Load more replies" node — a light indented row, not a card. */
@Composable
private fun MoreRow(c: Comment, loading: Boolean, onClick: () -> Unit, start: Dp? = null) {
    val cs = MaterialTheme.colorScheme
    val indent = (c.depth.coerceIn(0, 6) * 8).dp
    Box(Modifier.fillMaxWidth().padding(start = start ?: (10.dp + indent), end = 10.dp, bottom = 8.dp)) {
        TextButton(onClick = onClick, enabled = !loading) {
            if (loading) {
                Loading(Modifier.size(24.dp), color = LocalContentColor.current)
            } else {
                Icon(Icons.Rounded.AddCircleOutline, null, Modifier.size(18.dp), tint = cs.primary)
            }
            Spacer(Modifier.width(8.dp))
            Text(if (c.moreChildren.isEmpty()) "Continue thread →" else "${c.moreCount} more replies")
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun CommentTile(
    comment: Comment,
    highlighted: Boolean,
    isNew: Boolean, // posted since the user's last visit to this thread
    isOwn: Boolean,
    opAuthor: String,
    collapsed: Boolean,
    settings: Settings,
    actions: ThreadActions,
) {
    val cs = MaterialTheme.colorScheme
    val votes = LocalVoteColors.current
    val haptic = LocalHapticFeedback.current
    val nav = LocalNavigator.current
    val tapToCollapse = settings.tapToCollapse
    val depth = comment.depth
    val indent = (depth.coerceIn(0, 6) * 8).dp
    val isMod = comment.distinguished == "moderator"
    val nameColor = when {
        isMod -> Color(0xFF4CAF50)
        isOwn -> cs.primary
        else -> cs.onSurface
    }
    val edge = railColors[(depth - 1).coerceIn(0, railColors.size - 1)].copy(alpha = 0.9f)
    // Settings → Mark what you voted on: a glow, or an edge on the other side.
    val voteEdge = if (!settings.voteEdge) null else when (comment.likes) {
        true -> votes.up
        false -> votes.down
        null -> null
    }
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    val shape = RoundedCornerShape(14.dp)
    val toggle = { actions.toggle(comment) }

    /** What a swipe on this comment does, per Settings → Swipe actions. */
    fun swipe(a: SwipeAction): SwipeSpec? = when (a) {
        SwipeAction.UPVOTE -> SwipeSpec(a.icon, votes.up) { actions.vote(comment, 1) }
        SwipeAction.DOWNVOTE -> SwipeSpec(a.icon, votes.down) { actions.vote(comment, -1) }
        SwipeAction.SAVE -> SwipeSpec(a.icon, cs.primary) { actions.toggleSave(comment) }
        SwipeAction.REPLY -> SwipeSpec(a.icon, cs.tertiary) { actions.reply(comment) }
        SwipeAction.COLLAPSE -> SwipeSpec(a.icon, cs.secondary) { toggle() }
        SwipeAction.HIDE, SwipeAction.DISMISS, SwipeAction.HIDE_SUB, SwipeAction.NONE -> null
    }

    SwipeActions(
        enabled = settings.swipeActions,
        start = swipe(settings.swipeCommentStart),
        end = swipe(settings.swipeCommentEnd),
        actionInset = PaddingValues(start = 10.dp + indent, end = 10.dp, bottom = 8.dp),
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(start = 10.dp + indent, end = 10.dp, bottom = 8.dp)
                .shadow(1.dp, shape, ambientColor = Color.Black.copy(alpha = 0.05f), spotColor = Color.Black.copy(alpha = 0.08f))
                .clip(shape)
                .background(if (highlighted) cs.primaryContainer else cs.surfaceContainerLow)
                .then(if (highlighted) Modifier.border(1.5.dp, cs.primary, shape) else Modifier)
                .voteGlow(voteEdge.takeIf { settings.voteGlow }, rtl)
                // Colored depth edge (only on replies), full height — drawn,
                // not laid out, so it costs no extra layout pass.
                .drawBehind {
                    val w = 4.dp.toPx()
                    if (depth > 0) drawRect(edge, Offset(if (rtl) size.width - w else 0f, 0f), Size(w, size.height))
                    if (voteEdge != null && !settings.voteGlow) drawRect(voteEdge, Offset(if (rtl) 0f else size.width - w, 0f), Size(w, size.height))
                }
                .padding(start = if (depth > 0) 4.dp else 0.dp),
        ) {
            // Long-press collapses the whole subtree; tap re-expands a collapsed
            // comment (so a tap can't accidentally collapse) unless tap-to-collapse is on.
            Row(
                Modifier
                    .fillMaxWidth()
                    .combinedClickable(
                        onClick = { if (collapsed || tapToCollapse) toggle() },
                        onLongClick = {
                            haptic.performHapticFeedback(HapticFeedbackType.SegmentTick)
                            toggle()
                        },
                    )
                    .padding(start = 12.dp, top = 8.dp, end = 12.dp, bottom = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                // Tapping the avatar/name opens the commenter's profile.
                // The name is measured first and never gives way: the flair (weighted,
                // so it gets what's left) is what truncates (#96).
                Row(
                    Modifier.clickable(enabled = comment.author != "[deleted]") { nav.openUser(comment.author) },
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    AuthorDot(comment.author, 20)
                    Spacer(Modifier.width(8.dp))
                    Text(
                        "u/${comment.author}",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                        color = nameColor,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                if (comment.author == opAuthor && comment.author != "[deleted]") {
                    Spacer(Modifier.width(6.dp))
                    Badge("OP", cs.primaryContainer, cs.onPrimaryContainer, 10.sp)
                }
                if (comment.stickied) {
                    Spacer(Modifier.width(6.dp))
                    Icon(Icons.Rounded.PushPin, "Pinned", Modifier.size(14.dp), tint = cs.primary)
                }
                comment.authorFlair?.let {
                    Spacer(Modifier.width(6.dp))
                    FlairChip(it, Modifier.weight(1f, fill = false))
                }
                Spacer(Modifier.width(8.dp))
                Text("· ${timeAgo(comment.createdUtc)}", fontSize = 12.5.sp, color = cs.onSurfaceVariant, maxLines = 1)
                if (isNew) {
                    Spacer(Modifier.width(6.dp))
                    Badge("NEW", cs.tertiaryContainer, cs.onTertiaryContainer, 10.5.sp)
                }
                if (collapsed) {
                    Spacer(Modifier.weight(1f))
                    Icon(Icons.Rounded.UnfoldMore, "Expand", Modifier.size(16.dp), tint = cs.onSurfaceVariant)
                }
            }
            if (!collapsed) {
                Column(
                    Modifier
                        .fillMaxWidth()
                        .then(if (tapToCollapse) Modifier.clickable(indication = null, interactionSource = null, onClick = toggle) else Modifier)
                        .padding(horizontal = 12.dp),
                ) {
                    // Plain text, not selectable: a selectable paragraph is far
                    // heavier to build while scrolling through hundreds of
                    // comments (and swallows taps for tap-to-collapse).
                    // "Copy text" is in the ⋯ menu.
                    BodyWithMedia(comment.body, comment.media, nav, maxMedia = 3)
                }
                CommentActionsRow(comment, isOwn, actions)
            } else {
                Text(
                    comment.body.replace('\n', ' '),
                    Modifier.padding(start = 40.dp, end = 12.dp, bottom = 8.dp),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    fontSize = 13.sp,
                    color = cs.onSurfaceVariant,
                    fontStyle = FontStyle.Italic,
                )
            }
        }
    }
}

@Composable
private fun Badge(text: String, bg: Color, fg: Color, size: androidx.compose.ui.unit.TextUnit) {
    Text(
        text,
        Modifier.clip(RoundedCornerShape(6.dp)).background(bg).padding(horizontal = 6.dp, vertical = 1.dp),
        fontSize = size,
        fontWeight = FontWeight.ExtraBold,
        color = fg,
        maxLines = 1,
    )
}

/**
 * Settings → Mark comments you voted on (#122): the vote's colour glows softly from
 * the comment's top corner (the end side), fading in and out with the vote. A still
 * gradient, drawn: nothing to lay out or animate while scrolling.
 */
@Composable
private fun Modifier.voteGlow(color: Color?, rtl: Boolean, fadeTop: Boolean = false): Modifier {
    var last by remember { mutableStateOf(color ?: Color.Transparent) }
    if (color != null) last = color
    val shown by animateFloatAsState(if (color != null) 1f else 0f, tween(350), label = "voteGlow")
    if (shown == 0f) return this
    return drawBehind {
        // Gone by the comment's bottom edge, so it never stops in a line against the next one.
        val radius = minOf(size.height, size.width * 0.9f).coerceAtLeast(1f)
        val glow = Brush.radialGradient(
            listOf(last.copy(alpha = 0.34f * shown), last.copy(alpha = 0.10f * shown), Color.Transparent),
            center = Offset(if (rtl) 0f else size.width, 0f),
            radius = radius,
        )
        if (!fadeTop) {
            drawRect(glow)
            return@drawBehind
        }
        // Calm's rows have no card: fade in from the row's top too, so it doesn't stop
        // in a line against the comment above (#141). Only voted rows pay for the layer.
        val fade = minOf(32.dp.toPx(), size.height * 0.45f)
        drawContext.canvas.saveLayer(Rect(Offset.Zero, size), Paint())
        drawRect(glow)
        drawRect(Brush.verticalGradient(listOf(Color.Transparent, Color.Black), startY = 0f, endY = fade), blendMode = BlendMode.DstIn)
        drawContext.canvas.restore()
    }
}

/** A user's flair in this community, next to their name (#31): its text, with its emoji drawn inline. */
@Composable
private fun FlairChip(flair: UserFlair, modifier: Modifier = Modifier) {
    val cs = MaterialTheme.colorScheme
    val (text, emoji) = com.bennybar.luli_for_reddit.feature.feed.rememberFlairText(flair)
    Text(
        text,
        // Lightly tinted, as post flairs are (#131).
        modifier.widthIn(max = 160.dp).clip(RoundedCornerShape(6.dp)).background(cs.secondaryContainer).padding(horizontal = 6.dp, vertical = 1.dp),
        fontSize = 11.sp,
        color = cs.onSecondaryContainer,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
        inlineContent = emoji,
    )
}

@Composable
private fun CommentActionsRow(c: Comment, isOwn: Boolean, actions: ThreadActions) {
    val cs = MaterialTheme.colorScheme
    val votes = LocalVoteColors.current
    val up = c.likes == true
    val down = c.likes == false
    var menu by remember { mutableStateOf(false) }

    @Composable
    fun small(icon: ImageVector, desc: String, tint: Color, on: Boolean = false, onClick: () -> Unit) {
        IconButton(onClick = onClick, modifier = Modifier.size(36.dp)) { Icon(icon, desc, Modifier.size(18.dp), tint = tint) }
    }

    Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        small(Icons.Rounded.ArrowUpward, "Upvote", if (up) votes.up else cs.onSurfaceVariant, up) { actions.vote(c, 1) }
        Text(
            if (c.scoreHidden) "–" else compactNumber(c.score),
            fontSize = 12.sp,
            fontWeight = FontWeight.Bold,
            color = if (up) votes.up else if (down) votes.down else cs.onSurfaceVariant,
        )
        small(Icons.Rounded.ArrowDownward, "Downvote", if (down) votes.down else cs.onSurfaceVariant, down) { actions.vote(c, -1) }
        TextButton(
            onClick = { actions.reply(c) },
            contentPadding = PaddingValues(horizontal = 8.dp),
            modifier = Modifier.heightIn(min = 36.dp),
            colors = androidx.compose.material3.ButtonDefaults.textButtonColors(contentColor = cs.onSurfaceVariant),
        ) {
            Icon(Icons.AutoMirrored.Rounded.Reply, null, Modifier.size(16.dp))
            Spacer(Modifier.width(6.dp))
            Text("Reply", fontSize = 12.5.sp)
        }
        Spacer(Modifier.weight(1f))
        small(Icons.Rounded.UnfoldLess, "Collapse thread", cs.onSurfaceVariant) { actions.toggle(c) }
        small(
            if (c.saved) Icons.Rounded.Bookmark else Icons.Rounded.BookmarkBorder,
            if (c.saved) "Unsave" else "Save",
            if (c.saved) cs.primary else cs.onSurfaceVariant,
            c.saved,
        ) { actions.toggleSave(c) }
        Box {
            small(Icons.Rounded.MoreHoriz, "More", cs.onSurfaceVariant) { menu = true }
            DropdownMenuPopup(expanded = menu, onDismissRequest = { menu = false }) {
                CommentMenuItems(c, isOwn, actions) { f ->
                    menu = false
                    f()
                }
            }
        }
    }
}

/** The comment ⋯ menu's entries; [pick] closes the menu then runs the action. */
@Composable
private fun ColumnScope.CommentMenuItems(
    c: Comment,
    isOwn: Boolean,
    actions: ThreadActions,
    withSave: Boolean = false,
    pick: (() -> Unit) -> Unit,
) {
    // Material 3 Expressive menu groups: share-ish actions, then yours (or
    // block), then moderator actions.
    val groups = buildList<@Composable ColumnScope.() -> Unit> {
        add {
            if (withSave) DropdownMenuItem(text = { Text(if (c.saved) "Unsave" else "Save") }, onClick = { pick { actions.toggleSave(c) } })
            DropdownMenuItem(
                text = { Text(if (c.fullname in actions.translatedComments) "Show original" else "Translate") },
                onClick = { pick { actions.translate(c) } },
            )
            DropdownMenuItem(text = { Text("Copy text") }, onClick = { pick { copyToClipboard(c.body) } })
            if (c.permalink.isNotEmpty()) DropdownMenuItem(text = { Text("Share") }, onClick = { pick { actions.share(c) } })
            DropdownMenuItem(text = { Text("Share as image") }, onClick = { pick { actions.shareImage(c) } })
        }
        if (isOwn) {
            add {
                DropdownMenuItem(text = { Text("Edit") }, onClick = { pick { actions.edit(c) } })
                DropdownMenuItem(text = { Text("Delete") }, onClick = { pick { actions.delete(c) } })
            }
        } else if (c.author != "[deleted]") {
            add { DropdownMenuItem(text = { Text("Block u/${c.author}") }, onClick = { pick { actions.block(c) } }) }
        }
        // Moderators of this community (the post says so) can act on comments too.
        if (actions.post?.canModPost == true) {
            add {
                DropdownMenuItem(text = { Text("Approve") }, onClick = { pick { actions.mod(c, "Approved") { it.modApprove(c.fullname) } } })
                DropdownMenuItem(text = { Text("Remove") }, onClick = { pick { actions.mod(c, "Removed") { it.modRemove(c.fullname) } } })
                DropdownMenuItem(
                    text = { Text("Remove as spam") },
                    onClick = { pick { actions.mod(c, "Removed as spam") { it.modRemove(c.fullname, spam = true) } } },
                )
                if (isOwn) {
                    val distinguished = c.distinguished == "moderator"
                    DropdownMenuItem(
                        text = { Text(if (distinguished) "Undistinguish" else "Distinguish as mod") },
                        onClick = {
                            pick {
                                actions.mod(c, if (distinguished) "Undistinguished" else "Distinguished") {
                                    it.modDistinguish(c.fullname, if (distinguished) "no" else "yes")
                                }
                            }
                        },
                    )
                }
            }
        }
    }
    groups.forEachIndexed { i, group ->
        if (i > 0) Spacer(Modifier.height(MenuDefaults.GroupSpacing))
        DropdownMenuGroup(shapes = MenuDefaults.groupShape(i, groups.size)) { group() }
    }
}

// ---------------------------------------------------------------------------
// Calm comments
// ---------------------------------------------------------------------------

private val CalmRadius = 24.dp

/** The rails' spacing (#166): each one this far from the last, the first this far from the container's edge. */
private val CalmRailStep = 12.dp

/** Where a Calm comment's text starts at [depth]: past its rails. */
private fun calmIndent(depth: Int) = 16.dp + CalmRailStep * depth.coerceIn(0, 8)

/** A row's rails: its [depth] and its neighbours', so each line runs on unbroken and has round ends where it starts and stops. */
@Immutable
private class CalmRails(val depth: Int, val prev: Int, val next: Int)

/**
 * One row of a Calm thread container (surfaceContainerLow, radius 24, 12dp
 * side margin): [first] rounds the top and adds the container's top inset,
 * [last] rounds the bottom and leaves the 10dp gap to the next thread. It
 * draws the row's [rails]: one line per ancestor, joined row to row (#166).
 */
@Composable
private fun CalmThreadRow(first: Boolean, last: Boolean, highlighted: Boolean, rails: CalmRails, content: @Composable () -> Unit) {
    val cs = MaterialTheme.colorScheme
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    val shape = RoundedCornerShape(
        topStart = if (first) CalmRadius else 0.dp,
        topEnd = if (first) CalmRadius else 0.dp,
        bottomStart = if (last) CalmRadius else 0.dp,
        bottomEnd = if (last) CalmRadius else 0.dp,
    )
    Box(
        Modifier
            .fillMaxWidth()
            .padding(start = 12.dp, end = 12.dp, bottom = if (last) 10.dp else 0.dp)
            .clip(shape)
            .background(com.bennybar.luli_for_reddit.feature.feed.calmCardColor())
            .padding(top = if (first) 6.dp else 0.dp, bottom = if (last) 6.dp else 0.dp)
            .then(if (highlighted) Modifier.background(cs.primaryContainer) else Modifier)
            // Drawn, not laid out (no extra layout pass per depth).
            .drawBehind {
                val w = 2.5.dp.toPx()
                val inset = 6.dp.toPx() // where a line starts or stops, so its round end shows
                for (l in 0 until rails.depth.coerceAtMost(8)) {
                    val x = (CalmRailStep * (l + 1)).toPx()
                    val cx = if (rtl) size.width - x else x
                    // A line starts on its first reply and stops on the last one under it.
                    val top = if (rails.prev <= l) inset else -w
                    val bottom = if (rails.next <= l) size.height - inset else size.height + w
                    // A soft colour per depth, as the cards style's edges (#166).
                    drawLine(railColors[l % railColors.size], Offset(cx, top), Offset(cx, bottom), w, StrokeCap.Round)
                }
            },
    ) { content() }
}

/**
 * A Calm comment row inside its thread container: 2dp neutral rails per
 * depth (OP's own rail tinted primary), avatar 24 + name + OP + age, the
 * body, and a small ↑ score ↓ · Reply · Collapse · ⋯ row (save in ⋯).
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun CalmCommentRow(
    comment: Comment,
    isNew: Boolean,
    isOwn: Boolean,
    opAuthor: String,
    collapsed: Boolean,
    settings: Settings,
    actions: ThreadActions,
) {
    val cs = MaterialTheme.colorScheme
    val votes = LocalVoteColors.current
    val haptic = LocalHapticFeedback.current
    val nav = LocalNavigator.current
    val tapToCollapse = settings.tapToCollapse
    val depth = comment.depth.coerceIn(0, 8)
    val isOp = comment.author == opAuthor && comment.author != "[deleted]"
    val nameColor = when {
        comment.distinguished == "moderator" -> Color(0xFF4CAF50)
        isOwn -> cs.primary
        else -> cs.onSurface
    }
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    val toggle = { actions.toggle(comment) }
    val up = comment.likes == true
    val down = comment.likes == false
    val voteEdge = if (!settings.voteEdge) null else if (up) votes.up else if (down) votes.down else null
    var menu by remember { mutableStateOf(false) }

    fun swipe(a: SwipeAction): SwipeSpec? = when (a) {
        SwipeAction.UPVOTE -> SwipeSpec(a.icon, votes.up) { actions.vote(comment, 1) }
        SwipeAction.DOWNVOTE -> SwipeSpec(a.icon, votes.down) { actions.vote(comment, -1) }
        SwipeAction.SAVE -> SwipeSpec(a.icon, cs.primary) { actions.toggleSave(comment) }
        SwipeAction.REPLY -> SwipeSpec(a.icon, cs.tertiary) { actions.reply(comment) }
        SwipeAction.COLLAPSE -> SwipeSpec(a.icon, cs.secondary) { toggle() }
        SwipeAction.HIDE, SwipeAction.DISMISS, SwipeAction.HIDE_SUB, SwipeAction.NONE -> null
    }

    SwipeActions(
        enabled = settings.swipeActions,
        start = swipe(settings.swipeCommentStart),
        end = swipe(settings.swipeCommentEnd),
        slideColor = com.bennybar.luli_for_reddit.feature.feed.calmCardColor(),
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                // The rails are the thread row's (CalmThreadRow); this marks your vote.
                .drawBehind {
                    val w = 2.dp.toPx()
                    val top = 10.dp.toPx()
                    val bottom = size.height - 2.dp.toPx()
                    if (voteEdge != null && !settings.voteGlow) {
                        val x = 6.dp.toPx() + w
                        drawRect(voteEdge, Offset(if (rtl) x - w else size.width - x, top), Size(w, (bottom - top).coerceAtLeast(0f)))
                    }
                }
                .voteGlow(voteEdge.takeIf { settings.voteGlow }, rtl, fadeTop = true)
                .padding(start = calmIndent(depth), top = 10.dp, end = 16.dp, bottom = 8.dp),
        ) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .combinedClickable(
                        onClick = { if (collapsed || tapToCollapse) toggle() },
                        onLongClick = {
                            haptic.performHapticFeedback(HapticFeedbackType.SegmentTick)
                            toggle()
                        },
                    ),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                // The name is measured first and never gives way: the flair (weighted,
                // so it gets what's left) is what truncates (#96).
                Row(
                    Modifier.clickable(enabled = comment.author != "[deleted]") { nav.openUser(comment.author) },
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    AuthorDot(comment.author, 24)
                    Spacer(Modifier.width(8.dp))
                    Text(
                        comment.author,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Medium,
                        color = nameColor,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                if (isOp) {
                    Spacer(Modifier.width(6.dp))
                    Badge("OP", cs.primaryContainer, cs.onPrimaryContainer, 10.sp)
                }
                if (comment.stickied) {
                    Spacer(Modifier.width(6.dp))
                    Icon(Icons.Rounded.PushPin, "Pinned", Modifier.size(14.dp), tint = cs.primary)
                }
                comment.authorFlair?.let {
                    Spacer(Modifier.width(6.dp))
                    FlairChip(it, Modifier.weight(1f, fill = false))
                }
                Spacer(Modifier.width(6.dp))
                Text("· ${timeAgo(comment.createdUtc)}", fontSize = 13.sp, color = cs.onSurfaceVariant, maxLines = 1)
                if (isNew) {
                    Spacer(Modifier.width(6.dp))
                    Badge("NEW", cs.tertiaryContainer, cs.onTertiaryContainer, 10.5.sp)
                }
                if (collapsed) {
                    Spacer(Modifier.weight(1f))
                    CollapsePill(Icons.Rounded.UnfoldMore, "Expand", toggle)
                }
            }
            if (collapsed) {
                Text(
                    comment.body.replace('\n', ' '),
                    Modifier.padding(top = 4.dp),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    fontSize = 13.sp,
                    color = cs.onSurfaceVariant,
                    fontStyle = FontStyle.Italic,
                )
                return@Column
            }
            Column(
                Modifier
                    .fillMaxWidth()
                    .padding(top = 4.dp)
                    .then(if (tapToCollapse) Modifier.clickable(indication = null, interactionSource = null, onClick = toggle) else Modifier),
            ) {
                BodyWithMedia(comment.body, comment.media, nav, maxMedia = 3)
            }
            // ↑ score ↓ · Reply · Collapse · ⋯ — small, 32dp targets.
            Row(Modifier.fillMaxWidth().padding(top = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                val muted = cs.onSurfaceVariant
                // A vote colours its arrow and the score, with no circle behind it (#141).
                Box(Modifier.size(32.dp).clip(CircleShape).clickable { actions.vote(comment, 1) }, contentAlignment = Alignment.Center) {
                    Icon(Icons.Rounded.ArrowUpward, "Upvote", Modifier.size(16.dp), tint = if (up) votes.up else muted)
                }
                Text(
                    if (comment.scoreHidden) "–" else compactNumber(comment.score),
                    fontSize = 12.5.sp,
                    fontWeight = FontWeight.Medium,
                    color = if (up) votes.up else if (down) votes.down else muted,
                )
                Box(Modifier.size(32.dp).clip(CircleShape).clickable { actions.vote(comment, -1) }, contentAlignment = Alignment.Center) {
                    Icon(Icons.Rounded.ArrowDownward, "Downvote", Modifier.size(16.dp), tint = if (down) votes.down else muted)
                }
                Spacer(Modifier.width(6.dp))
                Row(
                    Modifier
                        .height(32.dp)
                        .clip(RoundedCornerShape(16.dp))
                        .clickable { actions.reply(comment) }
                        .padding(horizontal = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.AutoMirrored.Rounded.Reply, null, Modifier.size(16.dp), tint = muted)
                    Spacer(Modifier.width(4.dp))
                    Text("Reply", fontSize = 12.5.sp, fontWeight = FontWeight.Medium, color = muted)
                }
                Spacer(Modifier.weight(1f))
                if (comment.saved) Icon(Icons.Rounded.Bookmark, "Saved", Modifier.size(16.dp), tint = cs.primary)
                CollapsePill(Icons.Rounded.UnfoldLess, "Collapse", toggle)
                Box {
                    Box(Modifier.size(32.dp).clip(CircleShape).clickable { menu = true }, contentAlignment = Alignment.Center) {
                        Icon(Icons.Rounded.MoreHoriz, "More", Modifier.size(16.dp), tint = muted)
                    }
                    DropdownMenuPopup(expanded = menu, onDismissRequest = { menu = false }) {
                        CommentMenuItems(comment, isOwn, actions, withSave = true) { f ->
                            menu = false
                            f()
                        }
                    }
                }
            }
        }
    }
}

/** Calm thread's collapse / expand control: a labelled tonal pill, easy to spot and hit. */
@Composable
private fun CollapsePill(icon: ImageVector, label: String, onClick: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    Row(
        Modifier
            .padding(start = 4.dp)
            .height(28.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(cs.secondaryContainer)
            .clickable(onClickLabel = label, onClick = onClick)
            .padding(start = 8.dp, end = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, Modifier.size(16.dp), tint = cs.onSecondaryContainer)
        Spacer(Modifier.width(4.dp))
        Text(label, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = cs.onSecondaryContainer)
    }
}

/**
 * A post's text with the images / GIFs / videos in it shown inline (uploaded
 * ones via `media_metadata`, and linked i.redd.it / preview.redd.it /
 * v.redd.it / imgur …), as comments do — they used to show as bare links.
 */
@Composable
private fun PostBody(p: Post) {
    if (p.selftext.isEmpty()) return
    BodyWithMedia(p.selftext, p.bodyMedia, LocalNavigator.current, maxMedia = 10, selectable = true)
}

/**
 * A post / comment body in reading order: markdown text, with each image,
 * GIF or video drawn where it appears (a paragraph that's only a media link
 * shows as that media, not as the link).
 */
@Composable
private fun BodyWithMedia(body: String, media: Map<String, String>, nav: AppNavigator, maxMedia: Int, selectable: Boolean = false) {
    val segments = remember(body, media) { bodySegments(body, media, maxMedia) }
    for (seg in segments) {
        when (seg) {
            is BodySegment.Text -> RedditMarkdown(seg.markdown, selectable = selectable)
            is BodySegment.Media -> CommentMedia("", listOf(seg.uri), nav, max = 1)
        }
    }
}

/**
 * Inline previews for any media linked in a comment body (images, gifs,
 * videos), so comments don't just show a bare URL that opens a browser.
 * [extra]: media resolved from media_metadata, shown first.
 */
@Composable
private fun CommentMedia(body: String, extra: List<android.net.Uri>, nav: AppNavigator, max: Int = 3) {
    val links = remember(body, extra) { (extra + extractMediaLinks(body)).distinct().take(max) } // capped: link-heavy comments can't blow up the list
    if (links.isEmpty()) return
    val cs = MaterialTheme.colorScheme
    Column(Modifier.padding(top = 8.dp)) {
        for (uri in links) {
            val video = isVideoUrl(uri)
            Box(
                Modifier
                    .padding(bottom = 8.dp)
                    .fillMaxWidth()
                    .heightIn(max = 260.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .clickable { nav.openLink(uri.toString()) },
                contentAlignment = Alignment.Center,
            ) {
                if (video) {
                    Box(Modifier.fillMaxWidth().height(120.dp).background(cs.surfaceContainerHighest))
                    Icon(Icons.Rounded.PlayCircleFilled, "Play", Modifier.size(48.dp), tint = cs.onSurface.copy(alpha = 0.8f))
                } else {
                    var failed by remember(uri) { mutableStateOf(false) }
                    var loaded by remember(uri) { mutableStateOf(false) }
                    val pauseWhileScrolling = rememberPauseWhileScrolling()
                    if (failed) {
                        Box(Modifier.fillMaxWidth().height(60.dp).background(cs.surfaceContainerHighest), contentAlignment = Alignment.Center) {
                            Text("Could not load media", fontSize = 12.sp, color = cs.onSurfaceVariant)
                        }
                    } else {
                        AsyncImage(
                            model = uri.toString(),
                            contentDescription = null,
                            contentScale = ContentScale.Crop,
                            onSuccess = { loaded = true; pauseWhileScrolling(it) },
                            onError = { failed = true },
                            // A 120dp placeholder only while loading; then the image's own height (max 260).
                            modifier = Modifier
                                .fillMaxWidth()
                                .heightIn(min = if (loaded) 0.dp else 120.dp, max = 260.dp)
                                .then(if (loaded) Modifier else Modifier.background(cs.surfaceContainerHighest)),
                        )
                    }
                    if (isGifUrl(uri)) {
                        Text(
                            "GIF",
                            Modifier
                                .align(Alignment.TopEnd)
                                .padding(6.dp)
                                .clip(RoundedCornerShape(6.dp))
                                .background(Color.Black.copy(alpha = 0.54f))
                                .padding(horizontal = 6.dp, vertical = 2.dp),
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White,
                        )
                    }
                }
            }
        }
    }
}

/**
 * Small colored avatar with the author's initial (color derived from name), or their
 * profile picture once it's known (#133), drawn over it.
 */
@Composable
private fun AuthorDot(name: String, size: Int) {
    val clean = name.removePrefix("u/")
    val deleted = clean.isEmpty() || clean.startsWith("[")
    // Soft tones like the other placeholders (#168).
    val (tone, onTone) = avatarTones(clean)
    val icon = if (deleted) null else LocalAuthorIcons.current[clean.lowercase()]
    Box(Modifier.size(size.dp).clip(CircleShape).background(if (deleted) MaterialTheme.colorScheme.outline else tone), contentAlignment = Alignment.Center) {
        Text(
            if (deleted) "?" else clean.first().uppercase(),
            color = if (deleted) Color.White else onTone,
            fontWeight = FontWeight.Bold,
            fontSize = (size * 0.5f).sp,
            lineHeight = (size * 0.5f).sp,
        )
        if (icon != null) {
            val px = with(LocalDensity.current) { size.dp.roundToPx() }
            AsyncImage(
                model = com.bennybar.luli_for_reddit.feature.feed.rememberSizedRequest(icon, px),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}

/**
 * Translate: with one language to offer, a toggle (it / the original);
 * with two (the phone's and Settings → Second language), a menu.
 */
@Composable
internal fun TranslateButton(targets: List<String>, shownIn: String?, busy: Boolean, onPick: (String?) -> Unit, size: Dp = 24.dp) {
    var menu by remember { mutableStateOf(false) }
    val label = if (shownIn != null) "Show original" else "Translate"
    Box {
        IconTooltip(label) {
            IconButton(
                onClick = {
                    when {
                        targets.size > 1 -> menu = true
                        shownIn != null -> onPick(null)
                        else -> onPick(targets.single())
                    }
                },
                enabled = !busy,
            ) {
                if (busy) Loading(Modifier.size(size - 4.dp))
                else Icon(Icons.Rounded.Translate, label, Modifier.size(size), tint = if (shownIn != null) MaterialTheme.colorScheme.primary else LocalContentColor.current)
            }
        }
        DropdownMenu(menu, onDismissRequest = { menu = false }) {
            for (t in targets) {
                DropdownMenuItem(
                    text = { Text("Translate to ${Translate.languageName(t)}") },
                    trailingIcon = { if (t == shownIn) Icon(Icons.Rounded.Check, null) },
                    onClick = { menu = false; onPick(t) },
                )
            }
            if (shownIn != null) DropdownMenuItem(text = { Text("Show original") }, onClick = { menu = false; onPick(null) })
        }
    }
}
