package com.bennybar.luli_for_reddit.feature.feed

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
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.PrimaryScrollableTabRow
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
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
        Column(Modifier.fillMaxSize().padding(top = padding.calculateTopPadding())) {
            when (val a = about) {
                Async.Loading -> Box(Modifier.fillMaxWidth().height(96.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
                is Async.Error -> Text("Could not load profile: ${friendlyError(a.error)}", Modifier.padding(16.dp))
                is Async.Data -> ProfileHeader(a.value)
            }
            PrimaryScrollableTabRow(
                selectedTabIndex = pager.currentPage,
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
            HorizontalPager(pager, Modifier.weight(1f), beyondViewportPageCount = 0, key = { tabs[it] }) { page ->
                when (tabs[page]) {
                    "Posts" -> PagedList(
                        rememberPagedSource("u_${username}_posts") { a -> repo.getUserPosts(username, after = a) },
                        itemKey = Post::id,
                        emptyLabel = "No posts yet",
                    ) { PostCard(it) }
                    "Comments" -> PagedList(
                        rememberPagedSource("u_${username}_comments") { a -> repo.getUserComments(username, after = a) },
                        itemKey = Comment::fullname,
                        emptyLabel = "No comments yet",
                    ) { ProfileCommentCard(it) }
                    "Saved" -> PagedList(
                        rememberPagedSource("u_${username}_saved") { a -> repo.getUserSaved(username, after = a) },
                        itemKey = { if (it is Post) it.fullname else (it as Comment).fullname },
                        emptyLabel = "Nothing saved",
                        contentType = { if (it is Post) "post" else "comment" },
                    ) { item -> if (item is Post) PostCard(item) else ProfileCommentCard(item as Comment) }
                    else -> PagedList(
                        rememberPagedSource("u_${username}_upvoted") { a -> repo.getUserPosts(username, where = "upvoted", after = a) },
                        itemKey = Post::id,
                        emptyLabel = "Nothing upvoted",
                    ) { PostCard(it) }
                }
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
private fun ProfileHeader(user: RedditUser) {
    val cs = MaterialTheme.colorScheme
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
                "Joined ${SimpleDateFormat("MMM yyyy", Locale.getDefault()).format(Date(user.createdUtc))}",
                fontSize = 12.sp,
                color = cs.onSurfaceVariant,
            )
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
    BloomCard(Modifier.fillMaxWidth(), onClick = { openPermalink(nav, comment.permalink) }) {
        Column(Modifier.padding(14.dp)) {
            if (comment.linkTitle.isNotEmpty()) {
                Text(comment.linkTitle, maxLines = 2, overflow = TextOverflow.Ellipsis, fontWeight = FontWeight.Bold)
            }
            Text(
                "r/${comment.subreddit} · ${compactNumber(comment.score)} pts · ${timeAgo(comment.createdUtc)}",
                fontSize = 12.sp,
                color = cs.onSurfaceVariant,
            )
            Spacer(Modifier.height(6.dp))
            Text(comment.body.replace('\n', ' '), maxLines = 4, overflow = TextOverflow.Ellipsis, color = cs.onSurface)
        }
    }
}
