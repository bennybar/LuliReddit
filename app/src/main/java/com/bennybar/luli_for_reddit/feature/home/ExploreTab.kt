package com.bennybar.luli_for_reddit.feature.home

import com.bennybar.luli_for_reddit.ui.SearchIcon
import com.bennybar.luli_for_reddit.settings.TopBarMode
import com.bennybar.luli_for_reddit.feature.feed.HidingTopBar
import com.bennybar.luli_for_reddit.feature.feed.rememberHidingBar
import com.bennybar.luli_for_reddit.feature.feed.rememberSizedRequest
import coil3.compose.AsyncImage
import androidx.compose.ui.layout.ContentScale
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.foundation.lazy.itemsIndexed
import com.bennybar.luli_for_reddit.settings.ExploreSection
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.foundation.clickable
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.shape.RoundedCornerShape
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.async
import androidx.compose.material3.FilledTonalButton
import androidx.compose.runtime.produceState
import com.bennybar.luli_for_reddit.feature.settings.confirmDialog
import androidx.compose.foundation.background
import com.bennybar.luli_for_reddit.ui.subredditName
import com.bennybar.luli_for_reddit.state.RecentSubreddit
import com.bennybar.luli_for_reddit.ui.ToggleIcon
import com.bennybar.luli_for_reddit.ui.PickOneMenu
import com.bennybar.luli_for_reddit.ui.connectedShapes
import com.bennybar.luli_for_reddit.ui.ConnectedGap
import com.bennybar.luli_for_reddit.ui.RefreshBox
import com.bennybar.luli_for_reddit.ui.Loading
import androidx.compose.material3.TextButton
import androidx.compose.material.icons.rounded.Add
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Sort
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.DynamicFeed
import androidx.compose.material.icons.rounded.FilterList
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.Public
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material.icons.rounded.StarBorder
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.auth.SessionState
import com.bennybar.luli_for_reddit.core.compactNumber
import com.bennybar.luli_for_reddit.feature.feed.Async
import com.bennybar.luli_for_reddit.feature.feed.LetterAvatar
import com.bennybar.luli_for_reddit.feature.feed.Tile
import com.bennybar.luli_for_reddit.feature.feed.PillTextField
import com.bennybar.luli_for_reddit.feature.feed.SearchPill
import com.bennybar.luli_for_reddit.feature.feed.SectionHeader
import com.bennybar.luli_for_reddit.model.Subreddit
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.nav.Route
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch

/** The user's subscriptions (favourites first, then A–Z, from the repository). */
class SubscriptionsViewModel : ViewModel() {
    private val _subs = MutableStateFlow<Async<List<Subreddit>>>(Async.Loading)
    val subs: StateFlow<Async<List<Subreddit>>> = _subs
    private var job: Job? = null

    /** The account generation the list was loaded for (reload after a switch). */
    var loadedFor = app.feed.version.value

    init {
        load()
    }

    fun load(force: Boolean = false): Job {
        job?.cancel()
        return viewModelScope.launch {
            if (_subs.value !is Async.Data) _subs.value = Async.Loading
            try {
                _subs.value = Async.Data(app.repository.getSubscribedSubreddits(force))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _subs.value = Async.Error(e)
            }
        }.also { job = it }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ExploreTab() {
    val cs = MaterialTheme.colorScheme
    val nav = LocalNavigator.current
    val vm = viewModel { SubscriptionsViewModel() }
    val subs by vm.subs.collectAsStateWithLifecycle()
    val visited by app.recentSubreddits.state.collectAsStateWithLifecycle()
    val settings by app.settings.state.collectAsStateWithLifecycle()
    val session by app.session.state.collectAsStateWithLifecycle()
    val anonymous = (session as? SessionState.LoggedIn)?.session?.anonymous == true
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()
    // "Recommended for you" (#157): picked on the phone from what For You learned, then
    // each one's icon and members (/api/info is refused, 403); again whenever the
    // subscriptions reload (a Join takes one off).
    var joined by remember { mutableStateOf(emptySet<String>()) }
    val hideNsfw = app.contentFilters.state.collectAsStateWithLifecycle().value.hideNsfw
    val recommended by produceState(emptyList<Subreddit>(), subs, anonymous, hideNsfw) {
        val list = (subs as? Async.Data)?.value
        if (list == null || anonymous) {
            value = emptyList()
            return@produceState
        }
        // Up to 10, as a carousel (#161); each looked up once a session, so coming back to
        // Explore costs no requests.
        val names = app.forYou.recommendedCommunities(list.mapTo(HashSet()) { it.name.lowercase() }, limit = 10)
        val info = coroutineScope {
            names.map { n ->
                async { recommendedInfo[n] ?: runCatching { app.repository.getSubredditAbout(n) }.getOrNull()?.also { recommendedInfo[n] = it } }
            }.awaitAll()
        }
        value = info.filterNotNull().filter { it.userIsSubscriber != true && !(hideNsfw && it.over18) }
    }
    // "Popular communities": Reddit's list, loaded at most once a day; only while the
    // section is shown. Signed out too (without Join).
    val showPopularSubs = settings.exploreSections.any { it.section == ExploreSection.POPULAR_COMMUNITIES && it.shown }
    val popularSubs by produceState(emptyList<Subreddit>(), showPopularSubs) {
        value = if (showPopularSubs) app.repository.getPopularSubreddits() else emptyList()
    }
    val join: (Subreddit) -> Unit = { sub ->
        joined = joined + sub.name.lowercase()
        scope.launch {
            try {
                app.repository.setSubscribed(sub.name, true)
                vm.load(force = true)
            } catch (e: Exception) {
                joined = joined - sub.name.lowercase()
                nav.showActionError("join", e)
            }
        }
    }
    // The top bar floats over the list and follows the finger, and follows Settings ›
    // Appearance › Top bar like Home's (#162): Expandable, a title with search; Full, the
    // round search bar, with the title scrolling under it.
    val expandable = settings.topBarMode == TopBarMode.EXPANDABLE
    val bar = rememberHidingBar(listState)
    val sideBar = LocalSideBar.current != null
    var query by rememberSaveable { mutableStateOf("") }
    var recentAll by rememberSaveable { mutableStateOf(false) } // Recently visited: all of it, not the first few (#162)
    var favOnly by rememberSaveable { mutableStateOf(false) }
    var sort by rememberSaveable { mutableStateOf("default") } // default | name | subscribers
    var refreshing by remember { mutableStateOf(false) }

    // Re-tapping the Explore tab scrolls back to top.
    LaunchedEffect(listState) {
        app.feed.tabReselect(1).drop(1).collect {
            listState.animateScrollToItem(0)
            bar.slide(0f)
        }
    }
    // After an account switch: that account's subscriptions and custom feeds.
    val version by app.feed.version.collectAsStateWithLifecycle()
    LaunchedEffect(version) {
        if (vm.loadedFor != version) {
            vm.loadedFor = version
            vm.load(force = true)
        }
        // Custom feeds row (shared with the You tab).
        app.feed.loadMultireddits()
    }
    val multis by app.feed.multireddits.collectAsStateWithLifecycle()

    // The star toggle: favouriting reorders the list, so reload it after.
    fun toggleFavorite(s: Subreddit) {
        scope.launch {
            try {
                app.repository.setSubredditFavorite(s.name, !s.userHasFavorited)
                vm.load()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                nav.showActionError(if (s.userHasFavorited) "unfavorite" else "favorite", e)
            }
        }
    }

    Box(Modifier.fillMaxSize().clipToBounds().nestedScroll(bar)) {
    val barHeight = with(LocalDensity.current) { bar.height.toDp() }
    RefreshBox(
        isRefreshing = refreshing,
        onRefresh = {
            scope.launch {
                refreshing = true
                try {
                    vm.load(force = true).join()
                } finally {
                    refreshing = false
                }
            }
        },
        modifier = Modifier.fillMaxSize(),
        indicatorPadding = barHeight,
    ) {
        // Under the bar; with it away, under a softly faded status bar (#127).
        LazyColumn(Modifier.fillMaxSize(), state = listState, contentPadding = PaddingValues(top = barHeight, bottom = 130.dp)) {
            // The sections in Settings' order (#161). Popular & All and Custom feeds can go
            // anywhere; the filter sits above the first list of your communities.
            fun LazyListScope.popular() {
                item(key = "popular") {
                    // A connected pair (#35): round outer corners, tight inner ones.
                    Row(Modifier.padding(start = 12.dp, top = 12.dp, end = 12.dp)) {
                        OutlinedButton(
                            onClick = { nav.openSubreddit("popular") },
                            modifier = Modifier.weight(1f).defaultMinSize(minHeight = 52.dp),
                            shape = connectedShapes(0, 2).shape,
                        ) {
                            Icon(Icons.Rounded.LocalFireDepartment, null, Modifier.size(18.dp))
                            Spacer(Modifier.width(8.dp))
                            Text("Popular")
                        }
                        Spacer(Modifier.width(ConnectedGap))
                        // With the Posts tab on r/all (Settings), this one opens the frontpage instead.
                        val postsAll = settings.postsTabAll
                        OutlinedButton(
                            onClick = { if (postsAll) nav.push(Route.Frontpage) else nav.openSubreddit("all") },
                            modifier = Modifier.weight(1f).defaultMinSize(minHeight = 52.dp),
                            shape = connectedShapes(1, 2).shape,
                        ) {
                            Icon(if (postsAll) Icons.Rounded.Home else Icons.Rounded.Public, null, Modifier.size(18.dp))
                            Spacer(Modifier.width(8.dp))
                            Text(if (postsAll) "Frontpage" else "All")
                        }
                    }
                }
            }
            fun LazyListScope.customFeeds() {
                // Custom feeds (multireddits), with "New feed" at the end (signed in).
                val multiList = (multis as? Async.Data)?.value.orEmpty()
                if (multiList.isNotEmpty() || !anonymous) {
                    item(key = "multis") {
                        Column(Modifier.inSection(first = true, last = true)) {
                            Row(Modifier.padding(start = 16.dp, top = 6.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                                SectionHeader("Custom feeds", Modifier.weight(1f))
                                if (!anonymous) TextButton(onClick = { nav.push(Route.CustomFeeds) }) { Text("See all") }
                            }
                            LazyRow(
                                Modifier.height(48.dp),
                                contentPadding = PaddingValues(horizontal = 12.dp),
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                items(multiList, key = { it.path.ifEmpty { it.name } }) { m ->
                                    AssistChip(
                                        onClick = {
                                            val parts = m.path.split('/').filter { it.isNotEmpty() }
                                            val user = if (parts.size >= 4) parts[1] else currentUser()
                                            nav.push(Route.Multireddit(user, m.name))
                                        },
                                        label = { Text(m.displayName.ifEmpty { m.name }) },
                                        leadingIcon = {
                                            Icon(Icons.Rounded.DynamicFeed, null, Modifier.size(18.dp), tint = cs.onSecondaryContainer)
                                        },
                                        shape = CircleShape,
                                        border = null,
                                        colors = AssistChipDefaults.assistChipColors(containerColor = cs.surfaceContainerHigh),
                                    )
                                }
                                if (!anonymous) {
                                    item(key = "new_multi") {
                                        AssistChip(
                                            onClick = { scope.launch { createMulti(currentUser()) } },
                                            label = { Text("New feed") },
                                            leadingIcon = { Icon(Icons.Rounded.Add, null, Modifier.size(18.dp), tint = cs.onSecondaryContainer) },
                                            shape = CircleShape,
                                            border = null,
                                            colors = AssistChipDefaults.assistChipColors(containerColor = cs.surfaceContainerHigh),
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
            fun LazyListScope.place(section: ExploreSection) {
                when (section) {
                    ExploreSection.POPULAR -> popular()
                    ExploreSection.CUSTOM_FEEDS -> customFeeds()
                    // The ones you haven't joined, up to 10.
                    ExploreSection.POPULAR_COMMUNITIES -> {
                        val mine = (subs as? Async.Data)?.value?.mapTo(HashSet()) { it.name.lowercase() }.orEmpty() + joined
                        communityCarousel(
                            "popularSubs", "Popular communities",
                            popularSubs.filter { it.name.lowercase() !in mine && !(hideNsfw && it.over18) }.take(10),
                            { nav.openSubreddit(it.name) },
                            if (anonymous) null else join,
                        )
                    }
                    else -> {}
                }
            }
            val order = settings.exploreSections.filter { it.shown }.map { it.section }
            val filterAt = order.indexOfFirst { it.isCommunityList }.let { if (it < 0) order.size else it }
            order.take(filterAt).forEach { place(it) }
            // Full top bar: the title scrolls with the list, as Home's does.
            if (!expandable) item(key = "title") {
                Row(Modifier.padding(start = 16.dp, top = 8.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        "Explore",
                        Modifier.weight(1f),
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.ExtraBold,
                    )
                    // The side bar always has Settings (#145).
                    if (LocalSideBar.current == null) SettingsButton()
                }
            }
            item(key = "filter") {
                Row(Modifier.padding(start = 16.dp, top = 12.dp, end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    PillTextField(
                        value = query,
                        onValueChange = { query = it },
                        placeholder = "Filter your communities",
                        leading = Icons.Rounded.FilterList,
                        modifier = Modifier.weight(1f),
                    )
                    ToggleIcon(favOnly, { favOnly = it }, Icons.Rounded.Star, Icons.Rounded.StarBorder, "Favorites only", tonal = true)
                    SortMenu(sort) { sort = it }
                }
            }
            when (val s = subs) {
                Async.Loading -> item(key = "loading") {
                    Box(Modifier.fillMaxWidth().padding(40.dp), contentAlignment = Alignment.Center) { Loading() }
                }
                is Async.Error -> item(key = "error") {
                    if (anonymous) {
                        SignInPrompt(
                            "Sign in to see the communities you've joined. You can still search and open any subreddit.",
                        )
                    } else {
                        Column(Modifier.fillMaxWidth().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("Couldn't load your communities.", textAlign = TextAlign.Center)
                            Spacer(Modifier.height(12.dp))
                            Button(onClick = { vm.load() }) { Text("Retry") }
                        }
                    }
                }
                is Async.Data -> subscriptionSections(
                    list = s.value,
                    sections = order.drop(filterAt),
                    place = { place(it) },
                    recommended = recommended.filter { it.name.lowercase() !in joined },
                    onJoin = join,
                    query = query,
                    favOnly = favOnly,
                    sort = sort,
                    // Settings can hide the section (and the side bar's).
                    visited = if (settings.showRecentlyVisited) visited else emptyList(),
                    // A followed user is a subscription to their profile, u_<name>.
                    onOpen = { if (it.name.startsWith("u_")) nav.openUser(it.name.removePrefix("u_")) else nav.openSubreddit(it.name) },
                    onStar = ::toggleFavorite,
                    // A favorite's picture: a long press offers to take it off Favorites.
                    onUnfavorite = { sub ->
                        scope.launch {
                            if (confirmDialog("Remove ${subredditName(sub.namePrefixed)} from Favorites?", "It stays in your communities.", "Remove")) toggleFavorite(sub)
                        }
                    },
                    recentAll = recentAll,
                    onRecentAll = { recentAll = !recentAll },
                    onClearRecent = { app.recentSubreddits.clear() },
                    onRemoveRecent = { sub ->
                        scope.launch {
                            val name = subredditName(sub.namePrefixed)
                            if (confirmDialog("Remove $name?", "It leaves Recently visited. Opening it again adds it back.", "Remove")) {
                                app.recentSubreddits.remove(sub.name)
                            }
                        }
                    },
                )
            }
            // Still loading (or failed): the sections placed after the lists show anyway.
            if (subs !is Async.Data) order.drop(filterAt).filter { !it.isCommunityList }.forEach { place(it) }
        }
    }
    HidingTopBar(bar, Modifier.statusBarsPadding().padding(horizontal = if (expandable) 7.dp else 0.dp)) {
        if (expandable) {
            Row(
                Modifier.fillMaxWidth().padding(start = if (sideBar) 0.dp else 16.dp, top = if (sideBar) 8.dp else 10.dp, end = 4.dp, bottom = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                SideBarButton(Modifier.offset(x = (-3).dp))
                Text("Explore", Modifier.weight(1f), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.ExtraBold)
                IconButton(onClick = { nav.push(Route.Search()) }) { Icon(SearchIcon, "Search communities & posts") }
                // The side bar always has Settings (#145).
                if (!sideBar) SettingsButton()
            }
        } else {
            // Exactly where the search screen's field is (#115): as tall, as far down,
            // as far from either edge (after the ☰, where its ← is).
            Row(
                Modifier.fillMaxWidth().padding(start = if (sideBar) 4.dp else 16.dp, top = 4.dp, end = 24.dp, bottom = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                SideBarButton()
                if (sideBar) Spacer(Modifier.width(4.dp))
                SearchPill("Search communities & posts", onClick = { nav.push(Route.Search()) }, modifier = Modifier.weight(1f))
            }
        }
    }
    }
}

/**
 * One rounded container per section (#162), drawn by its items: the first rounds the
 * top (with the gap above it), the last the bottom.
 */
@Composable
private fun Modifier.inSection(first: Boolean, last: Boolean): Modifier {
    val r = 24.dp
    return padding(start = 12.dp, top = if (first) 12.dp else 0.dp, end = 12.dp)
        .fillMaxWidth()
        .clip(RoundedCornerShape(if (first) r else 0.dp, if (first) r else 0.dp, if (last) r else 0.dp, if (last) r else 0.dp))
        .background(MaterialTheme.colorScheme.surfaceContainerLow)
        .padding(bottom = if (last) 8.dp else 0.dp)
}

private fun currentUser(): String = app.session.username

/** Recommended communities' details, looked up once a session (#161). */
private val recommendedInfo = java.util.concurrent.ConcurrentHashMap<String, Subreddit>()

private fun LazyListScope.subscriptionSections(
    list: List<Subreddit>,
    sections: List<ExploreSection>,
    place: LazyListScope.(ExploreSection) -> Unit,
    recommended: List<Subreddit>,
    onJoin: (Subreddit) -> Unit,
    query: String,
    favOnly: Boolean,
    sort: String,
    visited: List<RecentSubreddit>,
    onOpen: (Subreddit) -> Unit,
    onStar: (Subreddit) -> Unit,
    onUnfavorite: (Subreddit) -> Unit,
    recentAll: Boolean,
    onRecentAll: () -> Unit,
    onClearRecent: () -> Unit,
    onRemoveRecent: (Subreddit) -> Unit,
) {
    val q = query.trim().lowercase()
    val active = q.isNotEmpty() || favOnly || sort != "default"
    // Each list is a container of its own (#162): its header, then its rows.
    fun header(key: String, title: String) = item(key = "h_$key") {
        SectionHeader(title, Modifier.inSection(first = true, last = false).padding(start = 16.dp, top = 16.dp, end = 16.dp, bottom = 6.dp))
    }
    fun rows(section: String, subs: List<Subreddit>) =
        itemsIndexed(subs, key = { _, it -> "${section}_${it.name}" }, contentType = { _, _ -> "sub" }) { i, sub ->
            Box(Modifier.inSection(first = false, last = i == subs.lastIndex)) { SubredditRow(sub, onOpen, onStar) }
        }
    fun note(key: String, text: String) = item(key = key) {
        Box(Modifier.inSection(first = false, last = true).padding(24.dp), contentAlignment = Alignment.Center) { Text(text) }
    }

    if (active) {
        // Filtered/sorted flat view.
        var working = list.filter { (q.isEmpty() || it.name.lowercase().contains(q)) && (!favOnly || it.userHasFavorited) }
        if (sort == "name") working = working.sortedBy { it.name.lowercase() }
        else if (sort == "subscribers") working = working.sortedByDescending { it.subscribers }
        header("count", "${working.size} communities")
        if (working.isEmpty()) note("nomatch", "No matches") else rows("all", working)
        return
    }

    // Default view: the sections in Settings' order (#161), then the rest.
    val byName = list.associateBy { it.name.lowercase() }
    val recent = visited.map { byName[it.name.lowercase()] ?: it.asSubreddit() }
    val visits = visited.associate { it.name.lowercase() to it.visits }
    // A hidden Favorites or Following leaves its communities in the rest, so none goes missing.
    val showFavs = ExploreSection.FAVORITES in sections
    val showFollowing = ExploreSection.FOLLOWING in sections
    val favs = if (showFavs) list.filter { it.userHasFavorited } else emptyList()
    // The users you follow (their profiles, u_<name>) get their own section.
    val (following, rest) = list.filter { !(showFavs && it.userHasFavorited) }.partition { showFollowing && it.name.startsWith("u_") }
    for (section in sections) when (section) {
        ExploreSection.RECENTLY_VISITED -> if (recent.isNotEmpty()) {
            // The first few, and Show all (#162); short lists show whole.
            val folds = recent.size > 4
            val shown = if (folds && !recentAll) recent.take(3) else recent
            // "Clear" empties just this list; post history stays (History has its own clear).
            item(key = "h_recent") {
                Row(Modifier.inSection(first = true, last = false).padding(start = 16.dp, top = 6.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    SectionHeader("Recently visited", Modifier.weight(1f))
                    TextButton(onClick = onClearRecent) { Text("Clear") }
                }
            }
            // No star on ones you aren't subscribed to. Long-press: remove just this one (#123).
            itemsIndexed(shown, key = { _, it -> "recent_${it.name}" }, contentType = { _, _ -> "sub" }) { i, sub ->
                Box(Modifier.inSection(first = false, last = !folds && i == shown.lastIndex)) {
                    SubredditRow(sub, onOpen, if (sub.name.lowercase() in byName) onStar else null, visits = visits[sub.name.lowercase()]) { onRemoveRecent(sub) }
                }
            }
            if (folds) item(key = "recent_more") {
                Box(Modifier.inSection(first = false, last = true).padding(horizontal = 8.dp)) {
                    TextButton(onClick = onRecentAll, Modifier.fillMaxWidth()) { Text(if (recentAll) "Show less" else "Show all ${recent.size}") }
                }
            }
        }
        // Communities you engage with in For You but haven't joined (#157), as a carousel (#161)
        // of cards with their banners (#162).
        ExploreSection.RECOMMENDED -> communityCarousel("recommended", "Recommended for you", recommended, onOpen, onJoin)
        // Your favorites as a row of their pictures (#162); a long press offers to unfavorite.
        ExploreSection.FAVORITES -> if (favs.isNotEmpty()) {
            item(key = "favs", contentType = "favorites") {
                Column(Modifier.inSection(first = true, last = true)) {
                    SectionHeader("Favorites", Modifier.padding(start = 16.dp, top = 16.dp, end = 16.dp, bottom = 6.dp))
                    LazyRow(
                        contentPadding = PaddingValues(horizontal = 8.dp),
                        horizontalArrangement = Arrangement.spacedBy(2.dp),
                    ) {
                        items(favs, key = { it.name }) { sub -> FavoriteBubble(sub, onOpen, onUnfavorite) }
                    }
                }
            }
        }
        ExploreSection.FOLLOWING -> if (following.isNotEmpty()) {
            header("following", "Following")
            rows("following", following)
        }
        else -> place(section)
    }
    if (rest.isEmpty() && favs.isEmpty() && following.isEmpty()) {
        header("subs", "Subscriptions")
        note("none", "You have no subscriptions yet")
    } else if (rest.isNotEmpty()) {
        header("subs", if (favs.isEmpty() && following.isEmpty()) "Subscriptions" else "Communities")
        rows("rest", rest)
    }
}

/** A section of community cards in a sideways row (Recommended for you, Popular communities); none when empty. */
private fun LazyListScope.communityCarousel(key: String, title: String, subs: List<Subreddit>, onOpen: (Subreddit) -> Unit, onJoin: ((Subreddit) -> Unit)?) {
    if (subs.isEmpty()) return
    item(key = key, contentType = "carousel") {
        Column(Modifier.inSection(first = true, last = true)) {
            SectionHeader(title, Modifier.padding(start = 16.dp, top = 16.dp, end = 16.dp, bottom = 10.dp))
            LazyRow(
                contentPadding = PaddingValues(horizontal = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(subs, key = { it.name }) { sub -> CommunityCard(sub, onOpen, onJoin) }
            }
            Spacer(Modifier.height(4.dp))
        }
    }
}

/**
 * A community card (#161): the community's banner (#162; a tint when it has none) with
 * its picture over it, its name and members, and Join (not when signed out).
 */
@Composable
private fun CommunityCard(sub: Subreddit, onOpen: (Subreddit) -> Unit, onJoin: ((Subreddit) -> Unit)?) {
    val cs = MaterialTheme.colorScheme
    val card = cs.surfaceContainerHigh
    Box(
        Modifier
            .width(156.dp)
            .clip(RoundedCornerShape(20.dp))
            .background(card)
            .clickable { onOpen(sub) },
    ) {
        Box(Modifier.fillMaxWidth().height(56.dp).background(cs.secondaryContainer)) {
            val px = with(LocalDensity.current) { 156.dp.roundToPx() }
            sub.bannerUrl?.let { AsyncImage(rememberSizedRequest(it, px), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop) }
        }
        Column(Modifier.fillMaxWidth().padding(start = 12.dp, top = 26.dp, end = 12.dp, bottom = 12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            LetterAvatar(
                sub.name, 60.dp, cs.secondaryContainer, cs.onSecondaryContainer,
                // A ring of the card's colour lifts it off the banner.
                Modifier.border(3.dp, card, CircleShape),
                imageUrl = sub.iconUrl,
            )
            Spacer(Modifier.height(8.dp))
            Text(subredditName(sub.namePrefixed), style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text("${compactNumber(sub.subscribers)} members", style = MaterialTheme.typography.bodySmall, color = cs.onSurfaceVariant, maxLines = 1)
            if (onJoin != null) {
                Spacer(Modifier.height(10.dp))
                FilledTonalButton(onClick = { onJoin(sub) }) { Text("Join") }
            }
        }
    }
}

/** A favorite in the Favorites row (#162): its picture and name; tap opens, long press offers to unfavorite. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun FavoriteBubble(sub: Subreddit, onOpen: (Subreddit) -> Unit, onUnfavorite: (Subreddit) -> Unit) {
    val cs = MaterialTheme.colorScheme
    Column(
        Modifier
            .width(76.dp)
            .clip(RoundedCornerShape(16.dp))
            .combinedClickable(onClick = { onOpen(sub) }, onLongClick = { onUnfavorite(sub) })
            .padding(vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        LetterAvatar(sub.name.removePrefix("u_"), 56.dp, cs.secondaryContainer, cs.onSecondaryContainer, imageUrl = sub.iconUrl)
        Spacer(Modifier.height(6.dp))
        Text(sub.name.removePrefix("u_"), style = MaterialTheme.typography.labelMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun SortMenu(sort: String, onPick: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { open = true }) { Icon(Icons.AutoMirrored.Rounded.Sort, "Sort") }
        PickOneMenu(open, { open = false }, listOf("default" to "Default", "name" to "Name A–Z", "subscribers" to "Most subscribers"), sort, onPick)
    }
}

@Composable
internal fun SubredditRow(s: Subreddit, onOpen: (Subreddit) -> Unit, onStar: ((Subreddit) -> Unit)? = null, visits: Int? = null, onLongClick: (() -> Unit)? = null) {
    val cs = MaterialTheme.colorScheme
    Tile(
        title = { Text(subredditName(s.namePrefixed)) },
        subtitle = {
            val members = "${compactNumber(s.subscribers)} ${if (s.name.startsWith("u_")) "followers" else "members"}"
            // Recently visited: how often you opened it (#92).
            Text(if (visits == null) members else "$members · $visits ${if (visits == 1) "visit" else "visits"}")
        },
        leading = {
            LetterAvatar(s.name, 40.dp, cs.secondaryContainer, cs.onSecondaryContainer, imageUrl = s.iconUrl)
        },
        trailing = onStar?.let {
            {
                ToggleIcon(s.userHasFavorited, { _ -> it(s) }, Icons.Rounded.Star, Icons.Rounded.StarBorder, "Favorite")
            }
        },
        onClick = { onOpen(s) },
        onLongClick = onLongClick,
    )
}
