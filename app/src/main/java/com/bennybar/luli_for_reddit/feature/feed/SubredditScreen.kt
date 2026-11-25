package com.bennybar.luli_for_reddit.feature.feed

import androidx.compose.foundation.background
import com.bennybar.luli_for_reddit.settings.HeaderHeight
import com.bennybar.luli_for_reddit.settings.TopBarMode
import com.bennybar.luli_for_reddit.feature.home.SideBarButton
import com.bennybar.luli_for_reddit.feature.home.LocalSideBar
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.lerp
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.Color
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.material3.LocalContentColor
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.border
import com.bennybar.luli_for_reddit.feature.markdown.RedditMarkdown
import com.bennybar.luli_for_reddit.ui.SearchIcon
import com.bennybar.luli_for_reddit.ui.subredditName
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.material3.FilledTonalToggleButton
import com.bennybar.luli_for_reddit.ui.Loading
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.material3.TextButton
import androidx.compose.material.icons.rounded.CheckCircle
import com.bennybar.luli_for_reddit.feature.settings.TextResult
import com.bennybar.luli_for_reddit.feature.settings.textDialog
import com.bennybar.luli_for_reddit.model.UserFlairChoice
import com.bennybar.luli_for_reddit.model.UserFlairSelector
import com.bennybar.luli_for_reddit.auth.SessionState
import androidx.compose.material.icons.automirrored.rounded.PlaylistAdd
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.VideoLibrary
import androidx.compose.material.icons.rounded.ExpandLess
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import coil3.compose.AsyncImage
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.compactNumber
import com.bennybar.luli_for_reddit.data.PostSort
import com.bennybar.luli_for_reddit.data.TopTime
import com.bennybar.luli_for_reddit.feature.settings.PickOption
import com.bennybar.luli_for_reddit.feature.settings.pickOption
import com.bennybar.luli_for_reddit.settings.SubredditSort
import com.bennybar.luli_for_reddit.model.Subreddit
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.nav.Route
import com.bennybar.luli_for_reddit.ui.Overlays
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/** A subreddit's about info (header + about sheet). */
class SubredditAboutViewModel(private val name: String) : ViewModel() {
    private val _about = MutableStateFlow<Async<Subreddit>>(Async.Loading)
    val about: StateFlow<Async<Subreddit>> = _about

    /** Optimistic subscribe state. */
    val subOverride = MutableStateFlow<Boolean?>(null)

    init {
        viewModelScope.launch {
            _about.value = try {
                Async.Data(
                    app.repository.getSubredditAbout(name).also {
                        if (app.settings.value.trackHistory) app.recentSubreddits.visit(it)
                    },
                )
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Async.Error(e)
            }
        }
    }

    fun toggleSub(s: Subreddit, currentlySubscribed: Boolean) {
        val next = !currentlySubscribed
        subOverride.value = next
        app.scope.launch {
            try {
                app.repository.setSubscribed(s.name, next)
            } catch (e: Exception) {
                subOverride.value = currentlySubscribed
                app.navigatorOrNull?.showActionError(if (next) "join" else "leave", e)
            }
        }
    }
}

@Composable
fun SubredditScreen(name: String) {
    val nav = LocalNavigator.current
    val scope = rememberCoroutineScope()
    val vm = viewModel(key = "sr_$name") { SubredditAboutViewModel(name) }
    val about by vm.about.collectAsStateWithLifecycle()
    val session by app.session.state.collectAsStateWithLifecycle()
    val anonymous = (session as? SessionState.LoggedIn)?.session?.anonymous != false
    val fab = rememberFabScroll()
    val settings by app.settings.state.collectAsStateWithLifecycle()
    val listState = rememberFeedListState()
    var refreshRequests by remember { mutableIntStateOf(0) } // the Refresh floating button
    var hideReadRequests by remember { mutableIntStateOf(0) } // the Hide read posts floating button
    // The top bar hides and comes back as on Home (#112).
    val bar = rememberHidingBar(listState)
    // Reloading (a sort change, too) starts a new list from the top: the bar comes back with it.
    val loaded = rememberFeedController(name).ui.collectAsStateWithLifecycle().value is FeedUi.Data
    LaunchedEffect(loaded) { if (!loaded) bar.slide(0f) }
    // Expandable, Medium or Tall: the community's banner as the header, its icon and name
    // sliding into the bar as it folds (#257). Folded and the Full bar keep the plain bar.
    val bannerHeader = settings.topBarMode == TopBarMode.EXPANDABLE && settings.headerHeight != HeaderHeight.FOLDED
    val collapsing = rememberCollapsingTitle(extra = BANNER_EXTRA) { listState.firstVisibleItemIndex == 0 && listState.firstVisibleItemScrollOffset == 0 }
    val openMenu = {
        showBarMenu(
            listOfNotNull(
                MenuAction(Icons.Outlined.Info, "About & rules") { scope.launch { showAbout(name, (about as? Async.Data)?.value) } },
                MenuAction(Icons.Outlined.VideoLibrary, "Browse media") { openMediaBrowser(nav, name, listState) },
                if (anonymous || name.lowercase() in setOf("all", "popular")) null
                else MenuAction(Icons.AutoMirrored.Rounded.PlaylistAdd, "Add to a custom feed") { scope.launch { showAddToCustomFeed(name) } },
                MenuAction(Icons.Outlined.Share, "Share") { nav.share("https://reddit.com/r/$name") },
            ),
        )
    }
    Scaffold(
        floatingActionButton = {
            FeedFab(
                settings.homeFab,
                fab.expanded,
                onNewPost = { nav.push(Route.Submit(name)) },
                onSearch = { nav.push(Route.Search(subreddit = name)) },
                onTop = { scope.launch { listState.animateScrollToItem(0) } },
                onRefresh = { refreshRequests++ },
                onHideRead = { hideReadRequests++ },
            )
        },
        containerColor = MaterialTheme.colorScheme.surface,
    ) { padding ->
        Box(Modifier.fillMaxSize().clipToBounds().then(if (bannerHeader) Modifier.nestedScroll(collapsing) else Modifier).nestedScroll(bar).nestedScroll(fab)) {
            // "Hide NSFW posts" would leave an NSFW subreddit's page empty: say why instead (#94).
            val hideNsfw = app.contentFilters.state.collectAsStateWithLifecycle().value.hideNsfw
            if (hideNsfw && (about as? Async.Data)?.value?.over18 == true) {
                Column(
                    Modifier.padding(padding).fillMaxSize().padding(32.dp),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text("This community is NSFW", style = MaterialTheme.typography.titleMedium)
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "Its posts are hidden because Hide NSFW posts is on.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                    )
                    Spacer(Modifier.height(16.dp))
                    FilledTonalButton(onClick = { nav.push(Route.ContentFilters) }) { Text("Content filters") }
                }
            } else PostListView(
                feedKey = name,
                topPadding = with(LocalDensity.current) { bar.height.toDp() },
                listState = listState,
                refreshRequests = refreshRequests,
                hideReadRequests = hideReadRequests,
                header = {
                    when (val a = about) {
                        Async.Loading -> LinearProgressIndicator(Modifier.fillMaxWidth().height(4.dp))
                        is Async.Error -> {}
                        is Async.Data -> if (bannerHeader) SubredditAbout(a.value, vm) else SubredditHeader(a.value, vm)
                    }
                },
                floatingChipsY = if (!settings.floatingChips) null else bar::chipsY,
            )
            HidingTopBar(bar) {
                if (bannerHeader) {
                    BannerTitleBar(collapsing, name, (about as? Async.Data)?.value, onSearch = { nav.push(Route.Search(subreddit = name)) }, onMenu = openMenu)
                } else BloomTopBar(
                    subredditName(name),
                    // Search, and the rest in the ⋯ menu: a row of five cropped the name (#112).
                    actions = {
                        IconButton(onClick = { nav.push(Route.Search(subreddit = name)) }) { Icon(SearchIcon, "Search") }
                        IconButton(onClick = openMenu) { Icon(Icons.Rounded.MoreHoriz, "More") }
                    },
                )
            }
        }
    }
}

/** The banner header's room under the bar's row: the banner, the icon over its foot, the name and members. */
private val BANNER_EXTRA = 136.dp
private const val BANNER = 136f // the banner's height under the status bar, dp

/**
 * A subreddit's header with Settings › Header height on Medium or Tall (#257), as a
 * messaging app's profile: the banner (or a band in the community's colour) behind the
 * bar's buttons, which sit in dark circles to stay readable; the icon on the left over
 * the banner's foot, the name and members beside it. As the list scrolls, the banner
 * slides up under the bar's colour, and the icon and name slide into the bar together.
 */
@Composable
private fun BannerTitleBar(state: CollapsingTitle, name: String, about: Subreddit?, onSearch: () -> Unit, onMenu: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    val nav = LocalNavigator.current
    val sideBar = LocalSideBar.current != null
    val p = state.progress
    val top = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    // Without a banner or a colour of its own: the theme's soft accent, not a grey block.
    val band = about?.keyColor?.let { runCatching { Color(android.graphics.Color.parseColor(it)) }.getOrNull() } ?: cs.primaryContainer
    val onBanner = androidx.compose.ui.graphics.lerp(Color.White, cs.onSurface, p)
    BoxWithConstraints(Modifier.fillMaxWidth().height(top + state.height).background(cs.surface).clipToBounds()) {
        val width = maxWidth
        Box(
            Modifier
                .fillMaxWidth()
                .height(top + BANNER.dp)
                .graphicsLayer { translationY = -70.dp.toPx() * p }
                .background(band),
        ) {
            if (about?.bannerUrl != null) {
                AsyncImage(
                    model = rememberSizedRequest(about.bannerUrl, feedDecodeWidth()),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
            }
            // Under the bar's colour as it folds.
            Box(Modifier.fillMaxSize().graphicsLayer { alpha = (p * 1.2f).coerceAtMost(1f) }.background(cs.surface))
        }
        // The icon and name, from over the banner's foot into the bar after ←.
        val iconSize = lerp(64.dp, 30.dp, p)
        val iconX = lerp(16.dp, 58.dp, p)
        val iconY = lerp(top + BANNER.dp - 26.dp, top + 10.dp + 9.dp, p)
        LetterAvatar(
            name,
            iconSize,
            cs.secondaryContainer,
            cs.onSecondaryContainer,
            Modifier
                .offset(iconX, iconY)
                .border(lerp(3.dp, 0.dp, p), cs.surface, CircleShape),
            imageUrl = about?.iconUrl,
        )
        val nameX = lerp(92.dp, iconX + iconSize + 10.dp, p)
        Text(
            subredditName("r/$name"),
            Modifier
                .offset(nameX, lerp(top + BANNER.dp + 4.dp, top + 10.dp + 10.dp, p))
                // Clear of the search and ⋯ buttons once in the bar.
                .widthIn(max = width - nameX - lerp(16.dp, 104.dp, p)),
            fontSize = (22f - 4f * p).sp,
            fontWeight = FontWeight.ExtraBold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        if (about != null) {
            Text(
                "${compactNumber(about.subscribers)} members",
                Modifier.offset(92.dp, top + BANNER.dp + 34.dp).graphicsLayer { alpha = (1f - p * 2.5f).coerceAtLeast(0f) },
                color = cs.onSurfaceVariant,
                style = MaterialTheme.typography.bodyMedium,
            )
        }
        // The bar's row, over the banner: round dark backs keep the buttons readable on any picture.
        CompositionLocalProvider(LocalContentColor provides onBanner) {
            Row(Modifier.padding(start = 4.dp, top = top + 10.dp, end = 4.dp).height(48.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                val back = Modifier.background(Color.Black.copy(alpha = 0.42f * (1f - p)), CircleShape)
                Box(back) {
                    if (sideBar) SideBarButton()
                    else IconButton(onClick = { nav.pop() }) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") }
                }
                Spacer(Modifier.weight(1f))
                IconButton(onClick = onSearch, modifier = back) { Icon(SearchIcon, "Search") }
                Spacer(Modifier.width(6.dp))
                IconButton(onClick = onMenu, modifier = back) { Icon(Icons.Rounded.MoreHoriz, "More") }
            }
        }
    }
}

/** With the banner header (#257): what's left of the header, the description in a card (3 lines, then Show all) and Join. */
@Composable
private fun SubredditAbout(s: Subreddit, vm: SubredditAboutViewModel) {
    val cs = MaterialTheme.colorScheme
    val override by vm.subOverride.collectAsStateWithLifecycle()
    val subscribed = override ?: s.userIsSubscriber ?: false
    var open by rememberSaveable { mutableStateOf(false) }
    var long by remember { mutableStateOf(false) }
    BloomCard(Modifier.padding(start = 10.dp, top = 4.dp, end = 10.dp, bottom = 4.dp).fillMaxWidth()) {
        Column(Modifier.padding(start = 14.dp, top = 12.dp, end = 10.dp, bottom = 8.dp)) {
            if (s.description.isNotEmpty()) {
                // Reddit text, its links working, once it's all shown.
                if (open) RedditMarkdown(s.description, color = cs.onSurfaceVariant)
                else Text(
                    remember(s.description) { snippetMarkdown(s.description, cs.onSurfaceVariant) },
                    color = cs.onSurfaceVariant,
                    maxLines = 3,
                    overflow = TextOverflow.Ellipsis,
                    onTextLayout = { if (it.hasVisualOverflow) long = true },
                )
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (long) TextButton(onClick = { open = !open }, contentPadding = PaddingValues(horizontal = 0.dp)) {
                    Text(if (open) "Show less" else "Show all")
                }
                Spacer(Modifier.weight(1f))
                FilledTonalToggleButton(checked = subscribed, onCheckedChange = { vm.toggleSub(s, subscribed) }) {
                    Text(if (subscribed) "Joined" else "Join")
                }
            }
        }
    }
}

@Composable
private fun SubredditHeader(s: Subreddit, vm: SubredditAboutViewModel) {
    val cs = MaterialTheme.colorScheme
    val override by vm.subOverride.collectAsStateWithLifecycle()
    val subscribed = override ?: s.userIsSubscriber ?: false
    Column(Modifier.padding(start = 6.dp, top = 8.dp, end = 6.dp)) {
        if (s.bannerUrl != null) {
            AsyncImage(
                model = rememberSizedRequest(s.bannerUrl, feedDecodeWidth()),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxWidth().height(110.dp).clip(RoundedCornerShape(20.dp)),
            )
        }
        BloomCard(Modifier.padding(start = 4.dp, top = 10.dp, end = 4.dp, bottom = 4.dp).fillMaxWidth()) {
            Column(Modifier.padding(14.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    LetterAvatar(s.name, 52.dp, cs.secondaryContainer, cs.onSecondaryContainer, imageUrl = s.iconUrl)
                    Spacer(Modifier.width(14.dp))
                    Column(Modifier.weight(1f)) {
                        Text(subredditName(s.namePrefixed), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.ExtraBold)
                        Text("${compactNumber(s.subscribers)} members", color = cs.onSurfaceVariant)
                    }
                    // One toggle: its shape and fill change with the state, and it reads as on/off.
                    FilledTonalToggleButton(checked = subscribed, onCheckedChange = { vm.toggleSub(s, subscribed) }) {
                        Text(if (subscribed) "Joined" else "Join")
                    }
                }
                if (s.description.isNotEmpty()) {
                    Spacer(Modifier.height(12.dp))
                    // Reddit text: its links open (#194).
                    RedditMarkdown(s.description, color = cs.onSurfaceVariant)
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
private suspend fun showAbout(name: String, about: Subreddit?) {
    Overlays.show<Unit> { done ->
        val cs = MaterialTheme.colorScheme
        ModalBottomSheet(onDismissRequest = { done(null) }) {
            val session by app.session.state.collectAsStateWithLifecycle()
            val signedIn = (session as? SessionState.LoggedIn)?.session?.anonymous == false
            val rules by produceState<List<Pair<String, String>>?>(null) {
                value = runCatching { app.repository.getSubredditRules(name) }.getOrDefault(emptyList())
            }
            LazyColumn(Modifier.navigationBarsPadding().padding(start = 20.dp, top = 4.dp, end = 20.dp, bottom = 24.dp)) {
                item {
                    Text(subredditName(name), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.ExtraBold)
                    if (about != null && about.title.isNotEmpty()) {
                        Text(about.title, Modifier.padding(top = 2.dp), style = MaterialTheme.typography.bodyMedium)
                    }
                    if (about != null) {
                        Text("${compactNumber(about.subscribers)} members", Modifier.padding(top = 4.dp), color = cs.onSurfaceVariant)
                    }
                    if (signedIn) YourFlair(name)
                    OwnSort(name)
                    if (about != null && about.description.isNotEmpty()) {
                        Spacer(Modifier.height(12.dp))
                        RedditMarkdown(about.description)
                    }
                    Spacer(Modifier.height(18.dp))
                    SectionHeader("Rules")
                    Spacer(Modifier.height(4.dp))
                }
                val r = rules
                when {
                    r == null -> item {
                        Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) { Loading() }
                    }
                    r.isEmpty() -> item { Text("No rules listed.") }
                    else -> items(r.size) { i -> RuleTile(i, r[i].first, r[i].second) }
                }
            }
        }
    }
}

/** An expandable rule (Flutter's ExpansionTile without dividers). */
@Composable
private fun RuleTile(index: Int, title: String, description: String) {
    var open by rememberSaveable { mutableStateOf(false) }
    Column {
        Row(
            Modifier.fillMaxWidth().clickable { open = !open }.padding(vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("${index + 1}. $title", Modifier.weight(1f), fontWeight = FontWeight.SemiBold)
            Icon(if (open) Icons.Rounded.ExpandLess else Icons.Rounded.ExpandMore, null)
        }
        AnimatedVisibility(open) {
            if (description.isNotEmpty()) RedditMarkdown(description, Modifier.padding(bottom = 12.dp))
        }
    }
}

/** The sort r/[sub] opens with (#60), in place of Settings' default sort. Applies right away. */
@Composable
private fun OwnSort(sub: String) {
    val cs = MaterialTheme.colorScheme
    val scope = rememberCoroutineScope()
    val settings by app.settings.state.collectAsStateWithLifecycle()
    val own = settings.subredditSorts[sub.lowercase()]
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(
            "Default sort: " + when {
                own == null -> "${settings.defaultSort.label} (from Settings)"
                own.sort.needsTime -> "${own.sort.label} · ${own.time.label}"
                else -> own.sort.label
            },
            Modifier.weight(1f),
            color = cs.onSurfaceVariant,
        )
        TextButton(onClick = {
            scope.launch {
                val pick = pickOption(
                    listOf(PickOption("", "Same as Settings (${settings.defaultSort.label})")) +
                        PostSort.entries.map { PickOption(it.path, it.label) },
                    own?.sort?.path ?: "",
                ) ?: return@launch
                val sort = PostSort.entries.find { it.path == pick }
                val time = if (sort?.needsTime == true) pickTopTime(own?.time ?: TopTime.DAY) ?: return@launch else TopTime.DAY
                app.settings.setSubredditSort(sub, sort?.let { SubredditSort(it, time) })
                app.feed.controller(sub).changeSort(sort ?: settings.defaultSort, time)
            }
        }) { Text("Change") }
    }
}

/**
 * Your user flair in r/[sub] (#31): what it is, and Change when the
 * community offers flair you can pick (No flair, a choice, or your own words
 * where a choice allows it).
 */
@Composable
private fun YourFlair(sub: String) {
    val cs = MaterialTheme.colorScheme
    val scope = rememberCoroutineScope()
    var version by remember { mutableStateOf(0) }
    val selector by produceState<Result<UserFlairSelector>?>(null, version) {
        value = runCatching { app.repository.getUserFlairSelector(sub) }
    }
    val s = selector?.getOrNull()
    Row(Modifier.fillMaxWidth().padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(
            when {
                selector == null -> "Your flair: …"
                s == null -> "Your flair: couldn't load"
                s.currentText != null -> "Your flair: ${s.currentText}"
                s.choices.isEmpty() -> "No user flair in this community"
                else -> "Your flair: none"
            },
            Modifier.weight(1f),
            color = cs.onSurfaceVariant,
        )
        if (s != null && s.choices.isNotEmpty()) {
            TextButton(onClick = {
                scope.launch {
                    if (pickUserFlair(sub, s)) version++
                }
            }) { Text("Change") }
        }
    }
}

private object NoFlair

/** Picks and sets your flair in [sub]; true if it changed. */
@OptIn(ExperimentalMaterial3Api::class)
private suspend fun pickUserFlair(sub: String, s: UserFlairSelector): Boolean {
    val picked = Overlays.show<Any> { done ->
        val cs = MaterialTheme.colorScheme
        ModalBottomSheet(onDismissRequest = { done(null) }) {
            LazyColumn(Modifier.navigationBarsPadding().padding(bottom = 8.dp)) {
                item {
                    Text(
                        "Your flair in r/$sub",
                        Modifier.padding(start = 20.dp, top = 4.dp, end = 20.dp, bottom = 8.dp),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                    )
                }
                item {
                    Tile(title = { Text("No flair") }, onClick = { done(NoFlair) },
                        trailing = { if (s.currentId == null && s.currentText == null) Icon(Icons.Rounded.CheckCircle, null, tint = cs.primary) })
                }
                items(s.choices.size) { i ->
                    val c = s.choices[i]
                    Tile(
                        title = { Text(c.text.ifEmpty { "(write your own)" }) },
                        subtitle = if (c.editable) ({ Text("You can change the text") }) else null,
                        trailing = { if (c.id == s.currentId) Icon(Icons.Rounded.CheckCircle, null, tint = cs.primary) },
                        onClick = { done(c) },
                    )
                }
            }
        }
    } ?: return false
    val choice = picked as? UserFlairChoice
    var text: String? = null
    if (choice != null && choice.editable) {
        val r = textDialog("Flair text", initial = if (choice.id == s.currentId) s.currentText ?: choice.text else choice.text) as? TextResult.Save
            ?: return false
        text = r.text.trim()
    }
    return try {
        app.repository.setUserFlair(sub, app.session.username, choice, text)
        app.navigatorOrNull?.showSnackbar(if (choice == null) "Flair removed" else "Flair set")
        true
    } catch (e: Exception) {
        app.navigatorOrNull?.showActionError("set your flair", e)
        false
    }
}
