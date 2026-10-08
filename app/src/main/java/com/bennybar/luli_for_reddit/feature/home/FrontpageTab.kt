package com.bennybar.luli_for_reddit.feature.home

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.PlayCircleOutline
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Speed
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.auth.SessionState
import com.bennybar.luli_for_reddit.feature.feed.EditSquareIcon
import com.bennybar.luli_for_reddit.feature.feed.GlassSurface
import com.bennybar.luli_for_reddit.feature.feed.LetterAvatar
import com.bennybar.luli_for_reddit.feature.feed.PostListView
import com.bennybar.luli_for_reddit.feature.feed.SearchPill
import com.bennybar.luli_for_reddit.nav.AppNavigator
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.nav.Route
import com.bennybar.luli_for_reddit.settings.PostDisplay
import com.bennybar.luli_for_reddit.settings.TopBarMode
import com.bennybar.luli_for_reddit.ui.Overlays

@Composable
internal fun currentUsername(): String {
    val session by app.session.state.collectAsStateWithLifecycle()
    return (session as? SessionState.LoggedIn)?.session?.username ?: ""
}

/** The Posts tab: the frontpage feed under its top bar (Full or Expandable mode). */
@Composable
internal fun FrontpageTab(chromeVisible: Boolean) {
    val cs = MaterialTheme.colorScheme
    val nav = LocalNavigator.current
    val username = currentUsername()
    val settings by app.settings.state.collectAsStateWithLifecycle()
    val forYou = settings.forYouFeed
    val homeOn = settings.redditHomeAllowed && settings.redditHomeFeed
    val expandable = settings.topBarMode == TopBarMode.EXPANDABLE
    // Full mode pins the action row; Expandable floats it in on demand.
    val showActionRow = settings.topBarMode == TopBarMode.FULL

    Column(Modifier.fillMaxSize()) {
        // Full mode: Google-app style search bar with avatar — collapses on scroll.
        if (showActionRow) {
            AnimatedVisibility(
                visible = chromeVisible,
                enter = expandVertically(tween(220), expandFrom = Alignment.Top),
                exit = shrinkVertically(tween(220), shrinkTowards = Alignment.Top),
            ) {
                Row(
                    Modifier.fillMaxWidth().padding(start = 16.dp, top = 12.dp, end = 16.dp, bottom = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    if (settings.showApiUsage) {
                        ApiUsagePill(Modifier.weight(1f))
                    } else {
                        SearchPill("Search Reddit", onClick = { nav.push(Route.Search()) }, modifier = Modifier.weight(1f))
                    }
                    Spacer(Modifier.width(4.dp))
                    NewPostButton { nav.push(Route.Submit()) }
                    DisplayMenu()
                    Spacer(Modifier.width(4.dp))
                    ProfileAvatar(username, 44.dp) { nav.push(Route.User(username)) }
                }
            }
        }
        PostListView(
            feedKey = "",
            modifier = Modifier.weight(1f),
            header = {
                Row(
                    Modifier.fillMaxWidth().padding(start = 16.dp, top = if (expandable) 10.dp else 8.dp, end = if (expandable) 4.dp else 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        if (homeOn) "Home" else if (forYou) "For You" else "Frontpage",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.ExtraBold,
                    )
                    if (!homeOn && forYou) {
                        Spacer(Modifier.width(8.dp))
                        Text(
                            "Personalized on-device · Beta",
                            Modifier.weight(1f),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            fontSize = 12.sp,
                            color = cs.onSurfaceVariant,
                        )
                    } else {
                        Spacer(Modifier.weight(1f))
                    }
                    // Expandable mode: one button that floats the toolbar in.
                    if (expandable) {
                        IconButton(onClick = { showFloatingToolbar(nav, username) }) {
                            Icon(Icons.Rounded.MoreHoriz, "Toolbar")
                        }
                    }
                }
            },
        )
    }
}

@Composable
private fun NewPostButton(onClick: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    FilledIconButton(
        onClick = onClick,
        colors = IconButtonDefaults.filledIconButtonColors(containerColor = cs.primary, contentColor = cs.onPrimary),
    ) { Icon(EditSquareIcon, "New post", Modifier.size(22.dp)) }
}

@Composable
private fun ProfileAvatar(username: String, size: Dp, onClick: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    LetterAvatar(
        username,
        size = size,
        container = cs.primaryContainer,
        content = cs.onPrimaryContainer,
        fontSize = 16.sp,
        modifier = Modifier
            .semantics { contentDescription = "Your profile" }
            .clickable(role = Role.Button, onClick = onClick),
    )
}

/** Three-dot menu to switch the feed's post display type (and media autoplay). */
@Composable
private fun DisplayMenu(onPicked: () -> Unit = {}) {
    val settings by app.settings.state.collectAsStateWithLifecycle()
    var open by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { open = true }) { Icon(Icons.Rounded.MoreVert, "Display") }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }, shape = RoundedCornerShape(16.dp)) {
            for (d in PostDisplay.entries) {
                DropdownMenuItem(
                    text = { Text(d.label) },
                    leadingIcon = { Icon(d.icon, null, Modifier.size(20.dp)) },
                    trailingIcon = if (d == settings.postDisplay) ({ Icon(Icons.Rounded.Check, null, Modifier.size(18.dp)) }) else null,
                    onClick = {
                        open = false
                        app.settings.setPostDisplay(d)
                        onPicked()
                    },
                )
            }
            HorizontalDivider()
            DropdownMenuItem(
                text = { Text("Autoplay media") },
                leadingIcon = { Icon(Icons.Outlined.PlayCircleOutline, null, Modifier.size(20.dp)) },
                trailingIcon = if (settings.autoplayMedia) ({ Icon(Icons.Rounded.Check, null, Modifier.size(18.dp)) }) else null,
                onClick = {
                    open = false
                    app.settings.setAutoplayMedia(!settings.autoplayMedia)
                    onPicked()
                },
            )
        }
    }
}

/**
 * Shows live Reddit API rate-limit usage in place of the search bar
 * (power-user setting). Reddit allows ~100 requests/minute per OAuth client.
 */
@Composable
private fun ApiUsagePill(modifier: Modifier = Modifier) {
    val cs = MaterialTheme.colorScheme
    val rl by app.rateLimit.collectAsStateWithLifecycle()
    val r = rl
    val label = if (r == null) "API usage · no calls yet" else "API ${r.used}/${r.total} · resets ${r.resetSeconds}s"
    GlassSurface(modifier) {
        Row(Modifier.padding(horizontal = 18.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.Speed, null, tint = cs.onSurfaceVariant)
            Spacer(Modifier.width(12.dp))
            Text(label, Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis, color = cs.onSurfaceVariant)
        }
    }
}

/**
 * Expandable top-bar mode: floats the full toolbar (search, new post,
 * display, profile) in from the top as a dismissible overlay — it never
 * displaces the feed.
 */
private fun showFloatingToolbar(nav: AppNavigator, username: String) {
    Overlays.launch { done ->
        val cs = MaterialTheme.colorScheme
        val visible = remember { MutableTransitionState(false).apply { targetState = true } }
        var after by remember { mutableStateOf<(() -> Unit)?>(null) }
        fun close(then: (() -> Unit)? = null) {
            after = then
            visible.targetState = false
        }
        // Finish closing once the exit animation has run.
        LaunchedEffect(visible.currentState, visible.targetState) {
            if (!visible.targetState && !visible.currentState && visible.isIdle) {
                done()
                after?.invoke()
            }
        }
        BackHandler { close() }
        Box(Modifier.fillMaxSize()) {
            AnimatedVisibility(visible, enter = fadeIn(tween(200)), exit = fadeOut(tween(200))) {
                Box(
                    Modifier
                        .fillMaxSize()
                        .background(Color.Black.copy(alpha = 0.30f))
                        .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { close() },
                )
            }
            AnimatedVisibility(
                visible,
                Modifier.statusBarsPadding().padding(start = 12.dp, top = 8.dp, end = 12.dp),
                enter = fadeIn(tween(200)) + slideInVertically(tween(200)) { -it / 6 },
                exit = fadeOut(tween(200)) + slideOutVertically(tween(200)) { -it / 6 },
            ) {
                GlassSurface(color = cs.surfaceContainerHigh) {
                    Row(Modifier.padding(horizontal = 8.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Row(
                            Modifier
                                .weight(1f)
                                .clip(RoundedCornerShape(24.dp))
                                .clickable { close { nav.push(Route.Search()) } }
                                .padding(horizontal = 14.dp, vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(Icons.Rounded.Search, null, tint = cs.onSurfaceVariant)
                            Spacer(Modifier.width(12.dp))
                            Text("Search Reddit", color = cs.onSurfaceVariant, maxLines = 1)
                        }
                        Spacer(Modifier.width(4.dp))
                        NewPostButton { close { nav.push(Route.Submit()) } }
                        DisplayMenu()
                        Spacer(Modifier.width(4.dp))
                        ProfileAvatar(username, 40.dp) { close { nav.push(Route.User(username)) } }
                    }
                }
            }
        }
    }
}
