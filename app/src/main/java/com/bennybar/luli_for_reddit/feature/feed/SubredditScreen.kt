package com.bennybar.luli_for_reddit.feature.feed

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.togetherWith
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.material3.FilledTonalIconToggleButton
import androidx.compose.material3.Surface
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Check
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.em
import kotlinx.coroutines.delay
import androidx.compose.foundation.background
import android.app.Activity
import android.content.ContextWrapper
import android.graphics.Bitmap
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalView
import androidx.core.graphics.ColorUtils
import androidx.core.view.WindowCompat
import coil3.toBitmap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import com.bennybar.luli_for_reddit.settings.HeaderHeight
import com.bennybar.luli_for_reddit.settings.TopBarMode
import com.bennybar.luli_for_reddit.nav.searchMorphSource
import com.bennybar.luli_for_reddit.nav.searchMorphSourceText
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
import com.bennybar.luli_for_reddit.feature.media.opensPicture
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.BoxWithConstraints
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
    private val _about = MutableStateFlow<Async<Subreddit>>(seen[name.lowercase()]?.let { Async.Data(it) } ?: Async.Loading)
    val about: StateFlow<Async<Subreddit>> = _about

    /** Optimistic subscribe state. */
    val subOverride = MutableStateFlow<Boolean?>(null)

    init {
        viewModelScope.launch {
            try {
                val fresh = app.repository.getSubredditAbout(name).also {
                    if (app.settings.value.trackHistory) app.recentSubreddits.visit(it)
                }
                seen[name.lowercase()] = fresh
                if ((_about.value as? Async.Data)?.value != fresh) _about.value = Async.Data(fresh)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // Keep the header from earlier this session rather than drop it.
                if (_about.value !is Async.Data) _about.value = Async.Error(e)
            }
        }
    }

    companion object {
        /**
         * Abouts seen this session: a community opened again paints its header at once, then
         * refreshes it. On iPhone it slotted in above the cached posts a moment later and
         * pushed them down (measured on the simulator); the same order holds here.
         */
        private val seen = java.util.concurrent.ConcurrentHashMap<String, Subreddit>()
    }

    /** [done]: called once Reddit took it (the "Joined r/x" pill, #277), never on a failure. */
    fun toggleSub(s: Subreddit, currentlySubscribed: Boolean, done: ((Boolean) -> Unit)? = null) {
        val next = !currentlySubscribed
        subOverride.value = next
        app.scope.launch {
            try {
                app.repository.setSubscribed(s.name, next)
                done?.invoke(next)
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
    // "Joined r/x" / "Left r/x" after the banner header's + / ✓ (#277), for a few seconds.
    var joinPill by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(joinPill) { if (joinPill != null) { delay(3_000); joinPill = null } }
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
                        is Async.Data -> if (bannerHeader) SubredditAbout(a.value) else SubredditHeader(a.value, vm)
                    }
                },
                floatingChipsY = if (!settings.floatingChips) null else bar::chipsY,
            )
            // Above the floating button, in the theme's inverse colours (#277).
            AnimatedVisibility(
                joinPill != null,
                Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(bottom = 92.dp),
                enter = fadeIn() + slideInVertically { it / 2 },
                exit = fadeOut() + slideOutVertically { it / 2 },
            ) {
                var last by remember { mutableStateOf("") }
                joinPill?.let { last = it }
                Surface(shape = CircleShape, color = MaterialTheme.colorScheme.inverseSurface, contentColor = MaterialTheme.colorScheme.inverseOnSurface, shadowElevation = 6.dp) {
                    Text(last, Modifier.padding(horizontal = 18.dp, vertical = 10.dp), style = MaterialTheme.typography.labelLarge)
                }
            }
            HidingTopBar(bar) {
                if (bannerHeader) {
                    BannerTitleBar(
                        collapsing, name, (about as? Async.Data)?.value, vm,
                        onSearch = { nav.push(Route.Search(subreddit = name)) }, onMenu = openMenu,
                        onJoined = { joined -> joinPill = if (joined) "Joined ${subredditName("r/$name")}" else "Left ${subredditName("r/$name")}" },
                    )
                } else if (settings.topBarMode == TopBarMode.FULL) {
                    // The Full bar, as on the tabs (#285): a round search bar that grows into
                    // the search page's field, its words with it.
                    FullSearchBar(
                        "Search in r/$name",
                        onClick = { nav.push(Route.Search(subreddit = name)) },
                        pillModifier = Modifier.searchMorphSource(),
                        textModifier = Modifier.searchMorphSourceText(),
                        actions = { IconButton(onClick = openMenu) { Icon(Icons.Rounded.MoreHoriz, "More") } },
                    )
                } else BloomTopBar(
                    subredditName(name),
                    // Search, and the rest in the ⋯ menu: a row of five cropped the name (#112).
                    actions = {
                        IconButton(onClick = { nav.push(Route.Search(subreddit = name)) }, Modifier.searchMorphSource()) { Icon(SearchIcon, "Search") }
                        IconButton(onClick = openMenu) { Icon(Icons.Rounded.MoreHoriz, "More") }
                    },
                )
            }
        }
    }
}

/** The banner header's room under the bar's row: the banner, the icon over its foot, the name and members. */
private val BANNER_EXTRA = 150.dp
private const val BANNER = 136f // the banner's height under the status bar, dp
private val ICON = 76.dp // the icon over the banner's foot (#268: bigger), 30dp in the bar
private val NAME_GAP = 10.dp // the name under the banner's foot (#268: a little lower)
private val ICON_OVER = 26.dp // how much of the icon is over the banner's foot: about a third (#277)
private val JOIN = 40.dp // the + / ✓ button by the name (#277)
private val BAR_ROW_TOP = 10.dp // the bar's row, under the status bar (CollapsingTitle's)

/**
 * A subreddit's header with Settings › Header height on Medium or Tall (#257), as a
 * messaging app's profile: the banner (or a band in the community's colour) behind the
 * bar's buttons, which sit in blurred circles (#268) to stay readable; the icon on the
 * left over the banner's foot, the name and members beside it. As the list scrolls, the
 * banner slides up with the name, so the name never runs over it (#268), and fades into
 * the bar's colour; the icon and name slide into the bar together.
 */
@Composable
private fun BannerTitleBar(
    state: CollapsingTitle, name: String, about: Subreddit?, vm: SubredditAboutViewModel,
    onSearch: () -> Unit, onMenu: () -> Unit, onJoined: (Boolean) -> Unit,
) {
    val cs = MaterialTheme.colorScheme
    val nav = LocalNavigator.current
    val sideBar = LocalSideBar.current != null
    val p = state.progress
    val top = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    // Without a banner or a colour of its own: the theme's soft accent, not a grey block.
    val band = about?.keyColor?.let { runCatching { Color(android.graphics.Color.parseColor(it)) }.getOrNull() } ?: cs.primaryContainer
    // A light banner gets dark icons, on it and in the status bar (#268); a picture's
    // lightness is known once it's loaded, the band's until then.
    var imageLight by remember(about?.bannerUrl) { mutableStateOf<Boolean?>(null) }
    // Reddit's desktop banners are 4000 px wide and as little as 128 tall: filling this box
    // shows a sliver of one blown up several times (Reddit feedback, r/Howtomen). One that
    // would need more than 1.5× becomes a soft wash of its own colours, not a blurry zoom.
    var soft by remember(about?.bannerUrl) { mutableStateOf(false) }
    val light = imageLight ?: (band.luminance() > 0.5f)
    BannerStatusBar(light = light, shown = { state.progress < 0.5f })
    val onBanner = androidx.compose.ui.graphics.lerp(if (light) Color.Black.copy(alpha = 0.87f) else Color.White, cs.onSurface, p)
    // The name's way from under the banner's foot into the bar; the banner moves with it.
    val nameTop = lerp(top + BANNER.dp + NAME_GAP, top + BAR_ROW_TOP + 10.dp, p)
    val bannerShift = (BANNER.dp + NAME_GAP - BAR_ROW_TOP - 10.dp) * p
    // Gone, not covered, once folded: a covered banner left a line under the status bar (#268).
    val bannerAlpha = 1f - (p * 1.2f).coerceAtMost(1f)
    val scope = rememberCoroutineScope()
    val bannerPx = with(LocalDensity.current) { (top + BANNER.dp).roundToPx() }
    val request = rememberCoverRequest(about?.bannerUrl, feedDecodeWidth(), bannerPx)
    // The round buttons' places in the header, for the blurred banner behind them.
    var root by remember { mutableStateOf<LayoutCoordinates?>(null) }
    val holes = remember { mutableStateMapOf<Int, Rect>() }
    BoxWithConstraints(
        Modifier.fillMaxWidth().height(top + state.height).background(cs.surface).clipToBounds().onGloballyPositioned { root = it },
    ) {
        val width = maxWidth
        if (bannerAlpha > 0f) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(top + BANNER.dp)
                    .graphicsLayer { translationY = -bannerShift.toPx(); alpha = bannerAlpha }
                    .background(band),
            ) {
                if (request != null) {
                    AsyncImage(
                        model = request,
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize().then(if (soft) Modifier.blur(30.dp) else Modifier),
                        onSuccess = { s ->
                            soft = bannerPx > s.result.image.height * 1.5f
                            scope.launch { imageLight = isLight(s.result.image.toBitmap()) }
                        },
                    )
                }
            }
            // The banner again, blurred, only inside the buttons' circles (#268).
            if (request != null && holes.isNotEmpty()) {
                val shapes = holes.values.toList()
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(top + BANNER.dp)
                        .drawWithContent {
                            // Each a circle or a pill: rounded by half its height.
                            val path = Path().apply { shapes.forEach { addRoundRect(RoundRect(it, CornerRadius(it.height / 2))) } }
                            clipPath(path) { this@drawWithContent.drawContent() }
                        }
                        .graphicsLayer { translationY = -bannerShift.toPx(); alpha = bannerAlpha },
                ) {
                    AsyncImage(
                        model = request,
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize().blur(16.dp),
                    )
                }
            }
        }
        // The icon and name, from over the banner's foot into the bar after ←.
        val iconSize = lerp(ICON, 30.dp, p)
        val iconX = lerp(16.dp, 58.dp, p)
        // About a third of it over the banner's foot (#277), the rest beside the name.
        val iconY = lerp(top + BANNER.dp - ICON_OVER, top + BAR_ROW_TOP + 9.dp, p)
        // The ring is a disc behind the icon, not a border over it: a border let the
        // picture's edge show around it (#268).
        val ring = lerp(3.dp, 0.dp, p)
        Box(
            Modifier
                .offset(iconX - ring, iconY - ring)
                .size(iconSize + ring * 2)
                .background(cs.surface, CircleShape)
                .padding(ring),
        ) {
            // A tap opens the picture full screen (#279); a letter avatar has none.
            val icon = about?.iconUrl
            LetterAvatar(
                name, iconSize, cs.secondaryContainer, cs.onSecondaryContainer, imageUrl = icon,
                modifier = if (icon != null) Modifier.opensPicture(icon, "r/$name") else Modifier,
            )
        }
        val nameX = lerp(16.dp + ICON + 12.dp, iconX + iconSize + 10.dp, p)
        Text(
            subredditName("r/$name"),
            Modifier
                .offset(nameX, nameTop)
                // Clear of the + / ✓ button open, of the search and ⋯ buttons once in the bar.
                .widthIn(max = width - nameX - lerp(16.dp + JOIN + 8.dp, 104.dp, p)),
            fontSize = (26f - 8f * p).sp,
            fontWeight = FontWeight.ExtraBold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        if (about != null) {
            // Join as an icon by the name (#277): + to join, ✓ to leave; it never cuts the name.
            val override by vm.subOverride.collectAsStateWithLifecycle()
            val subscribed = override ?: about.userIsSubscriber ?: false
            val label = subredditName("r/$name")
            FilledTonalIconToggleButton(
                checked = subscribed,
                onCheckedChange = { vm.toggleSub(about, subscribed, onJoined) },
                modifier = Modifier
                    .offset(width - 16.dp - JOIN, nameTop)
                    .size(JOIN)
                    .graphicsLayer { alpha = (1f - p * 2.5f).coerceAtLeast(0f) }
                    .semantics { contentDescription = if (subscribed) "Leave $label" else "Join $label" },
                enabled = p < 0.4f,
            ) {
                AnimatedContent(
                    subscribed,
                    transitionSpec = { (scaleIn(initialScale = 0.5f) + fadeIn()) togetherWith (scaleOut(targetScale = 0.5f) + fadeOut()) },
                    label = "join",
                ) { joined -> Icon(if (joined) Icons.Rounded.Check else Icons.Rounded.Add, null) }
            }
            Text(
                "${compactNumber(about.subscribers)} members",
                Modifier.offset(16.dp + ICON + 12.dp, nameTop + 36.dp).graphicsLayer { alpha = (1f - p * 2.5f).coerceAtLeast(0f) },
                color = cs.onSurfaceVariant,
                style = MaterialTheme.typography.bodyMedium,
            )
        }
        // The bar's row, over the banner: blurred, lightly tinted circles keep the buttons readable on any picture.
        CompositionLocalProvider(LocalContentColor provides onBanner) {
            Row(Modifier.padding(start = 4.dp, top = top + BAR_ROW_TOP, end = 4.dp).height(48.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                val tint = (if (light) Color.White.copy(alpha = 0.3f) else Color.Black.copy(alpha = 0.25f)).let { it.copy(alpha = it.alpha * (1f - p)) }
                fun back(i: Int) = Modifier
                    .onGloballyPositioned { c -> root?.takeIf { it.isAttached }?.let { r -> holes[i] = r.localBoundingBoxOf(c) } }
                    .background(tint, CircleShape) // a circle, or a pill when wider
                Box(back(0)) {
                    if (sideBar) SideBarButton()
                    else IconButton(onClick = { nav.pop() }) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") }
                }
                Spacer(Modifier.weight(1f))
                // Search and ⋯ share one pill, spaced as on Posts (#282).
                Row(back(1)) {
                    // What the search page's field grows out of (#285).
                    IconButton(onClick = onSearch, Modifier.searchMorphSource()) { Icon(SearchIcon, "Search") }
                    IconButton(onClick = onMenu) { Icon(Icons.Rounded.MoreHoriz, "More") }
                }
            }
        }
    }
}

/**
 * The status bar's icons dark over a light banner and light over a dark one while the
 * header is open (#268); the theme's again once it folds, and when the page goes.
 */
@Composable
private fun BannerStatusBar(light: Boolean, shown: () -> Boolean) {
    val view = LocalView.current
    val controller = remember(view) {
        generateSequence(view.context) { (it as? ContextWrapper)?.baseContext }.firstNotNullOfOrNull { it as? Activity }
            ?.window?.let { WindowCompat.getInsetsController(it, view) }
    }
    val theme = remember(controller) { controller?.isAppearanceLightStatusBars }
    val open by remember { derivedStateOf(shown) }
    LaunchedEffect(open, light) {
        if (controller != null && theme != null) controller.isAppearanceLightStatusBars = if (open) light else theme
    }
    DisposableEffect(controller) {
        onDispose { if (controller != null && theme != null) controller.isAppearanceLightStatusBars = theme }
    }
}

/** Whether a picture is light, from a sample of its pixels (off the main thread: a hardware bitmap is copied to read them). */
private suspend fun isLight(bitmap: Bitmap): Boolean = withContext(Dispatchers.Default) {
    val b = if (bitmap.config == Bitmap.Config.HARDWARE) bitmap.copy(Bitmap.Config.ARGB_8888, false) else bitmap
    var sum = 0.0
    var n = 0
    for (yi in 0 until 6) for (xi in 0 until 12) {
        // The top part: what the status bar and the buttons sit on.
        val x = ((xi + 0.5f) / 12f * b.width).toInt().coerceIn(0, b.width - 1)
        val y = ((yi + 0.5f) / 6f * b.height * 0.6f).toInt().coerceIn(0, b.height - 1)
        sum += ColorUtils.calculateLuminance(b.getPixel(x, y))
        n++
    }
    sum / n > 0.5
}

/**
 * With the banner header (#257): the description in a card, 3 lines then Show all. Join is
 * by the name in the header (#277), so without a description there's no card (#278).
 */
@Composable
private fun SubredditAbout(s: Subreddit) {
    val cs = MaterialTheme.colorScheme
    var open by rememberSaveable { mutableStateOf(false) }
    var long by remember { mutableStateOf(false) }
    if (s.description.isEmpty()) {
        Spacer(Modifier.height(4.dp))
        return
    }
    // The same text size and spacing collapsed and open (#277): RedditMarkdown's.
    val style = MaterialTheme.typography.bodyMedium.copy(fontSize = 15.sp, lineHeight = 1.45.em)
    BloomCard(Modifier.padding(start = 10.dp, top = 4.dp, end = 10.dp, bottom = 4.dp).fillMaxWidth()) {
        // Show all / Show less grows and shrinks the card rather than jumping (#286).
        Column(Modifier.animateContentSize(tween(260, easing = FastOutSlowInEasing)).padding(start = 14.dp, top = 12.dp, end = 10.dp, bottom = 8.dp)) {
            // Reddit text, its links working, once it's all shown.
            if (open) RedditMarkdown(s.description, color = cs.onSurfaceVariant, fontSize = 15.sp)
            else Text(
                remember(s.description) { snippetMarkdown(s.description, cs.onSurfaceVariant) },
                color = cs.onSurfaceVariant,
                style = style,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis,
                onTextLayout = { if (it.hasVisualOverflow) long = true },
            )
            if (long) TextButton(onClick = { open = !open }, contentPadding = PaddingValues(horizontal = 0.dp)) {
                Text(if (open) "Show less" else "Show all")
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
            val stripPx = with(LocalDensity.current) { 110.dp.roundToPx() }
            var soft by remember(s.bannerUrl) { mutableStateOf(false) } // as the banner header's
            Box(Modifier.fillMaxWidth().height(110.dp).clip(RoundedCornerShape(20.dp))) {
                AsyncImage(
                    model = rememberCoverRequest(s.bannerUrl, feedDecodeWidth(), stripPx),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize().then(if (soft) Modifier.blur(30.dp) else Modifier),
                    onSuccess = { r -> soft = stripPx > r.result.image.height * 1.5f },
                )
            }
        }
        BloomCard(Modifier.padding(start = 4.dp, top = 10.dp, end = 4.dp, bottom = 4.dp).fillMaxWidth()) {
            Column(Modifier.padding(14.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    val nav = LocalNavigator.current
                    LetterAvatar(
                        s.name, 52.dp, cs.secondaryContainer, cs.onSecondaryContainer, imageUrl = s.iconUrl,
                        // A tap opens the picture full screen (#279).
                        modifier = s.iconUrl?.let { icon -> Modifier.opensPicture(icon, s.namePrefixed) } ?: Modifier,
                    )
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
