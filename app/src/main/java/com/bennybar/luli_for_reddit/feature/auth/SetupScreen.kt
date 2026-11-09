package com.bennybar.luli_for_reddit.feature.auth

import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Merge
import androidx.compose.material.icons.rounded.Restore
import androidx.compose.material.icons.rounded.WarningAmber
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.AppIcon
import com.bennybar.luli_for_reddit.feature.settings.NAV_STYLES
import com.bennybar.luli_for_reddit.feature.settings.SwitchTile
import com.bennybar.luli_for_reddit.feature.settings.ThemeColorsContent
import com.bennybar.luli_for_reddit.feature.settings.confirmRedditHome
import com.bennybar.luli_for_reddit.feature.settings.homeAmber
import com.bennybar.luli_for_reddit.feature.settings.restoreData
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.nav.Route
import com.bennybar.luli_for_reddit.settings.PostDisplay
import com.bennybar.luli_for_reddit.ui.AppIconPreview
import kotlinx.coroutines.launch

/** Set once the setup has run (or been skipped), and for anyone who already had an account. */
const val SETUP_DONE = "setupDone"

/** Whether a fresh install still gets the setup before signing in (#114). */
fun needsSetup(): Boolean = app.prefs.getBool(SETUP_DONE) != true

/**
 * The first-run setup (#114): welcome, restore a backup, the look, navigation and
 * the feed, then sign-in. Every page can be skipped; it all stays in Settings.
 */
@Composable
fun SetupScreen() {
    val nav = LocalNavigator.current
    var step by rememberSaveable { mutableIntStateOf(0) }
    val last = 4

    fun finish() {
        app.prefs.setBool(SETUP_DONE, true)
        nav.resetTo(Route.Login)
    }

    BackHandler(enabled = step > 0) { step-- }

    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface).statusBarsPadding().navigationBarsPadding()) {
        if (step > 0) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = { step-- }) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") }
                LinearProgressIndicator(progress = { step / last.toFloat() }, Modifier.weight(1f).padding(horizontal = 8.dp))
                TextButton(onClick = ::finish) { Text("Skip") }
            }
        }
        AnimatedContent(
            targetState = step,
            transitionSpec = {
                val dir = if (targetState > initialState) 1 else -1
                (slideInHorizontally { it / 5 * dir } + fadeIn()) togetherWith (slideOutHorizontally { -it / 5 * dir } + fadeOut())
            },
            modifier = Modifier.weight(1f),
            label = "setup",
        ) { page ->
            when (page) {
                0 -> Welcome { step = 1 }
                1 -> Restore(onRestored = ::finish) { step = 2 }
                2 -> Page("Make it yours", "Light or dark, your colour, and how it spreads. All of it is in Settings later too.", { step = 3 }) {
                    ThemeColorsContent()
                }
                3 -> Page("Getting around", "How you move between Posts, Explore, Inbox and Profile, and how posts look.", { step = 4 }) {
                    Layout()
                }
                else -> Page("Your front page", "What Posts shows first. You can switch between them any time.", ::finish, next = "Sign in") {
                    Feed()
                }
            }
        }
    }
}

@Composable
private fun Welcome(onNext: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    Column(
        Modifier.fillMaxSize().padding(horizontal = 28.dp, vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Spacer(Modifier.weight(1f))
        AppIconPreview(AppIcon.parse(app.settings.value.appIcon), 96.dp)
        Spacer(Modifier.height(24.dp))
        Text("Welcome to Ilay", style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
        Spacer(Modifier.height(12.dp))
        Text(
            "A calm, fast way to read Reddit. A few quick choices and you're in.",
            style = MaterialTheme.typography.bodyLarge,
            color = cs.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.weight(1f))
        Button(onClick = onNext, modifier = Modifier.fillMaxWidth().height(56.dp)) { Text("Get started") }
    }
}

@Composable
private fun Restore(onRestored: () -> Unit, onSkip: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) scope.launch {
            restoreData(context, uri)
            onRestored()
        }
    }
    Page("Coming from another phone?", "Restore an Ilay backup to bring your settings, For You and history. Sign-in and keys aren't in backups.", onSkip, next = "I don't have a backup") {
        Spacer(Modifier.height(24.dp))
        OutlinedButton(
            onClick = { runCatching { pick.launch(arrayOf("application/json", "application/octet-stream", "text/*")) } },
            modifier = Modifier.fillMaxWidth().height(56.dp),
        ) {
            Icon(Icons.Rounded.Restore, null)
            Spacer(Modifier.width(10.dp))
            Text("Restore a backup")
        }
    }
}

/** Navigation (bottom bar / side bar / both) and the post layout. */
@Composable
private fun Layout() {
    val s by app.settings.state.collectAsStateWithLifecycle()
    Label("Navigation")
    NAV_STYLES.forEachIndexed { i, (title, description) ->
        Choice(title, description, s.navStyle == i) { app.settings.setNavStyle(i) }
    }
    Label("Posts")
    for (d in PostDisplay.entries) {
        Choice(d.label, null, s.postDisplay == d, d.icon) { app.settings.setPostDisplay(d) }
    }
}

/** For You, and Reddit Home (with its warning) and Blend. */
@Composable
private fun Feed() {
    val s by app.settings.state.collectAsStateWithLifecycle()
    val ctrl = app.settings
    val scope = rememberCoroutineScope()
    SwitchTile(
        "For You",
        "Ilay picks posts from your subscriptions and what you read, instead of Reddit's Best",
        Icons.Rounded.AutoAwesome, s.forYouFeed, onChange = ctrl::setForYouFeed,
    )
    SwitchTile(
        "Reddit Home (experimental)",
        "Your real reddit.com Home feed, with the website sign-in",
        Icons.Rounded.WarningAmber, s.redditHomeAllowed,
        accent = homeAmber(),
        onChange = { v ->
            if (!v) ctrl.setRedditHomeAllowed(false)
            else scope.launch { if (confirmRedditHome()) ctrl.setRedditHomeAllowed(true) }
        },
    )
    if (s.redditHomeAllowed) {
        SwitchTile(
            "Blend (Beta)",
            "For You also ranks your Reddit Home: Reddit's recommendations, under your For You choices",
            Icons.Rounded.Merge, s.forYouFeed && s.blendHome,
        ) { v ->
            ctrl.setBlendHome(v)
            if (v) ctrl.setForYouFeed(true)
        }
    }
}

/** A step: its title and why, its content (scrolling), and the button on to the next. */
@Composable
private fun Page(title: String, subtitle: String, onNext: () -> Unit, next: String = "Next", content: @Composable () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            Column(Modifier.padding(horizontal = 24.dp).padding(top = 16.dp, bottom = 8.dp)) {
                Text(title, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(8.dp))
                Text(subtitle, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Column(Modifier.padding(horizontal = 8.dp)) { content() }
        }
        Button(onClick = onNext, modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 16.dp).height(56.dp)) { Text(next) }
    }
}

@Composable
private fun Label(text: String) {
    Text(
        text,
        Modifier.padding(start = 16.dp, top = 20.dp, bottom = 8.dp),
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
    )
}

/** One choice of several: a card, outlined in the accent when it's the one picked. */
@Composable
private fun Choice(title: String, description: String?, selected: Boolean, icon: ImageVector? = null, onClick: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    Row(
        Modifier
            .padding(horizontal = 8.dp, vertical = 4.dp)
            .fillMaxWidth()
            .background(if (selected) cs.secondaryContainer else cs.surfaceContainerLow, RoundedCornerShape(20.dp))
            .border(BorderStroke(2.dp, if (selected) cs.primary else Color.Transparent), RoundedCornerShape(20.dp))
            .clickable(onClick = onClick)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            Icon(icon, null, tint = if (selected) cs.onSecondaryContainer else cs.onSurfaceVariant)
            Spacer(Modifier.width(14.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleMedium, color = if (selected) cs.onSecondaryContainer else cs.onSurface)
            if (description != null) {
                Text(description, style = MaterialTheme.typography.bodyMedium, color = if (selected) cs.onSecondaryContainer else cs.onSurfaceVariant)
            }
        }
        if (selected) Box(Modifier.size(24.dp), contentAlignment = Alignment.Center) { Icon(Icons.Rounded.Check, null, tint = cs.primary) }
    }
}
