package com.bennybar.luli_for_reddit.feature.feed

import androidx.compose.material3.ToggleButton
import com.bennybar.luli_for_reddit.ui.Loading
import android.net.Uri
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Block
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.rounded.MailOutline
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.PrimaryScrollableTabRow
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.layout.layout
import androidx.compose.ui.unit.Constraints
import com.bennybar.luli_for_reddit.data.PostSort
import com.bennybar.luli_for_reddit.data.TopTime
import kotlin.math.roundToInt
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bennybar.luli_for_reddit.ui.theme.LocalVoteColors
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.compactNumber
import com.bennybar.luli_for_reddit.core.routeForRedditUrl
import com.bennybar.luli_for_reddit.core.timeAgo
import com.bennybar.luli_for_reddit.feature.post.confirmBlockUser
import com.bennybar.luli_for_reddit.model.Comment
import com.bennybar.luli_for_reddit.model.Post
import com.bennybar.luli_for_reddit.model.RedditUser
import com.bennybar.luli_for_reddit.nav.AppNavigator
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.nav.Route
import com.bennybar.luli_for_reddit.ui.friendlyError
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class UserAboutViewModel(private val username: String) : ViewModel() {
    private val _about = MutableStateFlow<Async<RedditUser>>(Async.Loading)
    val about: StateFlow<Async<RedditUser>> = _about

    init {
        viewModelScope.launch {
            _about.value = try {
                Async.Data(app.repository.getUserAbout(username))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Async.Error(e)
            }
        }
    }
}

/** A user's profile: header + Posts / Comments (and your own Saved / Upvoted) tabs. */
@Composable
fun UserScreen(username: String) {
    val nav = LocalNavigator.current
    val scope = rememberCoroutineScope()
    val me = currentSessionUsername()
    val isSelf = me.isNotEmpty() && me.equals(username, ignoreCase = true)

    Scaffold(
        topBar = {
            BloomTopBar(
                "u/$username",
                actions = {
                    if (!isSelf) {
                        IconButton(onClick = { nav.push(Route.ComposeMessage(to = username)) }) {
                            Icon(Icons.Rounded.MailOutline, "Send message")
                        }
                    }
                    IconButton(onClick = { nav.share("https://reddit.com/user/$username") }) { Icon(Icons.Outlined.Share, "Share") }
                    if (!isSelf) {
                        IconButton(onClick = { scope.launch { confirmBlockUser(username) } }) {
                            Icon(Icons.Rounded.Block, "Block user")
                        }
                    }
                },
            )
        },
        containerColor = MaterialTheme.colorScheme.surface,
    ) { padding ->
        UserProfileBody(username, Modifier.fillMaxSize().padding(top = padding.calculateTopPadding()))
    }
}

/**
 * A profile's header and its Posts / Comments (and your own Saved / Upvoted)
 * lists: the user screen, and the Profile tab ([belowHeader]: its "Your stuff" row).
 */
@Composable
fun UserProfileBody(username: String, modifier: Modifier = Modifier, belowHeader: @Composable () -> Unit = {}) {
    val scope = rememberCoroutineScope()
    val vm = viewModel(key = "user_$username") { UserAboutViewModel(username) }
    val about by vm.about.collectAsStateWithLifecycle()
    val me = currentSessionUsername()
    val isSelf = me.isNotEmpty() && me.equals(username, ignoreCase = true)
    val repo = app.repository

    val tabs = buildList {
        add("Posts")
        add("Comments")
        if (isSelf) {
            add("Saved")
            add("Upvoted")
        }
    }
    val pager = rememberPagerState { tabs.size }
    // Your own lists reload on every return from a post (scores and votes
    // you just changed); others' after the usual five minutes.
    val staleAfter = if (isSelf) 30_000L else 5 * 60_000L
    // Posts and comments, newest first like reddit.com; Hot and Top too.
    var sort by rememberSaveable { mutableStateOf(PostSort.NEWEST) }
    var time by rememberSaveable { mutableStateOf(TopTime.ALL) }
    val sortKey = if (sort.needsTime) "${sort.path}_${time.param}" else sort.path
    val sortTime = time.takeIf { sort.needsTime }

    // The header (and the Profile tab's row under it) slides away as a list
    // scrolls down and comes back once it's back at the top; the tabs stay.
    // On each list, inside its pull-to-refresh: the header comes back before
    // a pull refreshes.
    var headerHeight by remember { mutableIntStateOf(0) }
    var headerOffset by remember { mutableFloatStateOf(0f) }
    val collapse = remember {
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                if (available.y >= 0) return Offset.Zero
                val next = (headerOffset + available.y).coerceAtLeast(-headerHeight.toFloat())
                val used = next - headerOffset
                headerOffset = next
                return Offset(0f, used)
            }

            override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
                if (available.y <= 0) return Offset.Zero
                val next = (headerOffset + available.y).coerceAtMost(0f)
                val used = next - headerOffset
                headerOffset = next
                return Offset(0f, used)
            }
        }
    }
    val listModifier = Modifier.nestedScroll(collapse)

    Column(modifier) {
        Column(
            Modifier.clipToBounds().layout { measurable, constraints ->
                val p = measurable.measure(constraints.copy(minHeight = 0, maxHeight = Constraints.Infinity))
                headerHeight = p.height
                val offset = headerOffset.roundToInt().coerceAtLeast(-p.height)
                layout(p.width, p.height + offset) { p.place(0, offset) }
            },
        ) {
            when (val a = about) {
                Async.Loading -> Box(Modifier.fillMaxWidth().height(96.dp), contentAlignment = Alignment.Center) {
                    Loading()
                }
                is Async.Error -> Text("Could not load profile: ${friendlyError(a.error)}", Modifier.padding(16.dp))
                is Async.Data -> ProfileHeader(a.value, canFollow = !isSelf && me.isNotEmpty())
            }
            belowHeader()
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            PrimaryScrollableTabRow(
                selectedTabIndex = pager.currentPage,
                modifier = Modifier.weight(1f),
                edgePadding = 0.dp,
                containerColor = MaterialTheme.colorScheme.surface,
            ) {
                tabs.forEachIndexed { i, t ->
                    Tab(
                        selected = pager.currentPage == i,
                        onClick = { scope.launch { pager.animateScrollToPage(i) } },
                        text = { Text(t) },
                    )
                }
            }
            if (tabs[pager.currentPage] == "Posts" || tabs[pager.currentPage] == "Comments") {
                SortBar(
                    sort,
                    time,
                    onPick = { s, t ->
                        sort = s
                        if (t != null) time = t
                    },
                    sorts = listOf(PostSort.NEWEST, PostSort.HOT, PostSort.TOP),
                )
            }
        }
        HorizontalPager(pager, Modifier.weight(1f), beyondViewportPageCount = 0, key = { tabs[it] }) { page ->
            when (tabs[page]) {
                "Posts" -> PagedList(
                    rememberPagedSource("u_${username}_posts_$sortKey") { a ->
                        repo.getUserPosts(username, after = a, sort = sort, time = sortTime)
                    },
                    itemKey = Post::id,
                    listModifier = listModifier,
                    emptyLabel = "No posts yet",
                    staleAfterMillis = staleAfter,
                ) { PostCard(it) }
                "Comments" -> PagedList(
                    rememberPagedSource("u_${username}_comments_$sortKey") { a ->
                        repo.getUserComments(username, after = a, sort = sort, time = sortTime)
                    },
                    itemKey = Comment::fullname,
                    listModifier = listModifier,
                    emptyLabel = "No comments yet",
                    staleAfterMillis = staleAfter,
                ) { ProfileCommentCard(it) }
                "Saved" -> PagedList(
                    rememberPagedSource("u_${username}_saved") { a -> repo.getUserSaved(username, after = a) },
                    itemKey = { if (it is Post) it.fullname else (it as Comment).fullname },
                    listModifier = listModifier,
                    emptyLabel = "Nothing saved",
                    staleAfterMillis = staleAfter,
                    contentType = { if (it is Post) "post" else "comment" },
                ) { item -> if (item is Post) PostCard(item) else ProfileCommentCard(item as Comment) }
                else -> PagedList(
                    rememberPagedSource("u_${username}_upvoted") { a -> repo.getUserPosts(username, where = "upvoted", after = a) },
                    itemKey = Post::id,
                    listModifier = listModifier,
                    emptyLabel = "Nothing upvoted",
                    staleAfterMillis = staleAfter,
                ) { PostCard(it) }
            }
        }
    }
}

@Composable
internal fun currentSessionUsername(): String {
    val session by app.session.state.collectAsStateWithLifecycle()
    return (session as? com.bennybar.luli_for_reddit.auth.SessionState.LoggedIn)?.session?.username ?: ""
}

@Composable
private fun ProfileHeader(user: RedditUser, canFollow: Boolean) {
    val cs = MaterialTheme.colorScheme
    val nav = LocalNavigator.current
    val scope = rememberCoroutineScope()
    // Following a user is subscribing to their profile (u_<name>): their posts
    // then show in your Best / Hot / New and For You, like a subreddit's.
    var following by remember(user.name) { mutableStateOf(user.following) }
    var busy by remember { mutableStateOf(false) }
    Row(Modifier.padding(start = 16.dp, top = 8.dp, end = 16.dp, bottom = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        LetterAvatar(user.name, 60.dp, cs.primaryContainer, cs.onPrimaryContainer, imageUrl = user.iconUrl)
        Spacer(Modifier.width(16.dp))
        Column(Modifier.weight(1f)) {
            Text("u/${user.name}", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.ExtraBold)
            Spacer(Modifier.height(4.dp))
            Text(
                "${compactNumber(user.linkKarma)} post · ${compactNumber(user.commentKarma)} comment karma",
                color = cs.onSurfaceVariant,
            )
            Text(
                "Joined ${SimpleDateFormat("MMM yyyy", LocalConfiguration.current.locales[0]).format(Date(user.createdUtc))}",
                fontSize = 12.sp,
                color = cs.onSurfaceVariant,
            )
        }
        if (canFollow) {
            val toggle: () -> Unit = {
                val next = !following
                following = next
                busy = true
                scope.launch {
                    try {
                        app.repository.setSubscribed("u_${user.name}", next)
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        following = !next
                        nav.showActionError(if (next) "follow" else "unfollow", e)
                    } finally {
                        busy = false
                    }
                }
            }
            // One toggle: its shape and fill change with the state, and it reads as on/off.
            ToggleButton(checked = following, onCheckedChange = { toggle() }, enabled = !busy) {
                Text(if (following) "Following" else "Follow")
            }
        }
    }
}

/** Opens a comment's permalink (its thread, focused on it). */
internal fun openPermalink(nav: AppNavigator, permalink: String) {
    if (permalink.isEmpty()) return
    routeForRedditUrl(Uri.parse("https://reddit.com$permalink"))?.let(nav::push)
}

@Composable
private fun ProfileCommentCard(comment: Comment) {
    val cs = MaterialTheme.colorScheme
    val nav = LocalNavigator.current
    // Your votes from threads (this list is Reddit's copy from when it loaded).
    val votes by app.commentVotes.state.collectAsStateWithLifecycle()
    val vote = votes[comment.id]
    val likes = if (vote != null) vote.likes else comment.likes
    val voteColors = LocalVoteColors.current
    BloomCard(Modifier.fillMaxWidth(), onClick = { openPermalink(nav, comment.permalink) }) {
        Column(Modifier.padding(14.dp)) {
            if (comment.linkTitle.isNotEmpty()) {
                Text(comment.linkTitle, maxLines = 2, overflow = TextOverflow.Ellipsis, fontWeight = FontWeight.Bold)
            }
            Text(
                "r/${comment.subreddit} · ${compactNumber(vote?.score ?: comment.score)} pts · ${timeAgo(comment.createdUtc)}",
                fontSize = 12.sp,
                color = when (likes) { true -> voteColors.up; false -> voteColors.down; null -> cs.onSurfaceVariant },
            )
            Spacer(Modifier.height(6.dp))
            Text(comment.body.replace('\n', ' '), maxLines = 4, overflow = TextOverflow.Ellipsis, color = cs.onSurface)
        }
    }
}
