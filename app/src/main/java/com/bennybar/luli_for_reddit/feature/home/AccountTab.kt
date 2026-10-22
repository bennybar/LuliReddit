package com.bennybar.luli_for_reddit.feature.home

import com.bennybar.luli_for_reddit.feature.feed.UserProfileBody
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.AssistChip
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.material.icons.rounded.EditNote
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Login
import androidx.compose.material.icons.automirrored.rounded.Logout
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.OfflinePin
import androidx.compose.material.icons.rounded.PeopleAlt
import androidx.compose.material.icons.rounded.PersonAddAlt1
import androidx.compose.material.icons.rounded.TravelExplore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.auth.SessionState
import com.bennybar.luli_for_reddit.feature.feed.BloomCard
import com.bennybar.luli_for_reddit.feature.feed.LetterAvatar
import com.bennybar.luli_for_reddit.feature.feed.Tile
import com.bennybar.luli_for_reddit.feature.feed.SectionHeader
import com.bennybar.luli_for_reddit.feature.feed.TapGuard
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.nav.Route
import com.bennybar.luli_for_reddit.ui.Overlays
import kotlinx.coroutines.launch

/**
 * The Profile tab: your profile (Posts, Comments, Saved, Upvoted) under a
 * bar with the account switcher and Settings, and a "Your stuff" row for
 * what's kept on this device. Browsing without an account: sign in, plus
 * your stuff.
 */
@Composable
internal fun ProfileTab() {
    val nav = LocalNavigator.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val session by app.session.state.collectAsStateWithLifecycle()
    val s = (session as? SessionState.LoggedIn)?.session
    val username = s?.username ?: ""
    val anonymous = s?.anonymous ?: false

    Column(Modifier.fillMaxSize()) {
        Row(
            Modifier.fillMaxWidth().padding(start = if (LocalSideBar.current != null) 4.dp else 16.dp, top = 8.dp, end = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            SideBarButton()
            Text("Profile", Modifier.weight(1f), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.ExtraBold)
            if (!anonymous) {
                IconButton(onClick = { scope.launch { showAccountSheet(username, context) } }) {
                    Icon(Icons.Rounded.PeopleAlt, "Switch / add account")
                }
            }
            TabMenuButton()
        }
        if (anonymous || username.isEmpty()) {
            LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 130.dp)) {
                item(key = "signin") {
                    SignInPrompt(
                        "You're browsing without an account. Sign in to vote, comment, save, see your inbox and get your own frontpage.",
                    )
                }
                item(key = "yours_header") { SectionHeader("Your stuff", Modifier.padding(start = 16.dp, top = 8.dp, end = 16.dp)) }
                item(key = "history") {
                    NavTile(Icons.Rounded.History, "History", "Recently viewed (stored on this device)") { nav.push(Route.History) }
                }
                item(key = "offline") {
                    NavTile(Icons.Rounded.OfflinePin, "Read later", "Threads saved for offline reading") { nav.push(Route.Offline) }
                }
                item(key = "summaries") {
                    NavTile(Icons.Rounded.AutoAwesome, "Summaries", "Posts you summarized with AI, and their summaries") { nav.push(Route.Summaries) }
                }
            }
        } else {
            UserProfileBody(username, Modifier.weight(1f)) { YourStuffRow() }
        }
    }
}

/** History, Read later, Drafts, Summaries and saved search, as one row of chips. */
@Composable
private fun YourStuffRow() {
    val nav = LocalNavigator.current
    val cs = MaterialTheme.colorScheme
    val changes by app.drafts.changes.collectAsStateWithLifecycle()
    val drafts = remember(changes) { app.drafts.list().size }
    val chips = listOf(
        Triple(Icons.Rounded.History, "History", Route.History),
        Triple(Icons.Rounded.OfflinePin, "Read later", Route.Offline),
        Triple(Icons.Rounded.EditNote, if (drafts == 0) "Drafts" else "Drafts · $drafts", Route.Drafts),
        Triple(Icons.Rounded.AutoAwesome, "Summaries", Route.Summaries),
        Triple(Icons.Outlined.BookmarkBorder, "Search saved", Route.Saved),
    )
    LazyRow(
        Modifier.padding(bottom = 4.dp),
        contentPadding = PaddingValues(horizontal = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(chips, key = { it.third.toString() }) { (icon, label, route) ->
            AssistChip(
                onClick = { nav.push(route) },
                label = { Text(label) },
                leadingIcon = { Icon(icon, null, Modifier.size(18.dp), tint = cs.onSecondaryContainer) },
                shape = CircleShape,
                border = null,
                colors = AssistChipDefaults.assistChipColors(containerColor = cs.surfaceContainerHigh),
            )
        }
    }
}

@Composable
private fun NavTile(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, subtitle: String, onClick: () -> Unit) {
    Tile(
        title = { Text(title) },
        subtitle = { Text(subtitle) },
        leading = { Icon(icon, null) },
        onClick = onClick,
    )
}

/** Asks for a name and creates a custom feed (holding [subreddits]); true if it was created. */
internal suspend fun createMulti(username: String, subreddits: List<String> = emptyList()): Boolean {
    val name = Overlays.show<String> { done ->
        var text by remember { mutableStateOf("") }
        val focus = remember { FocusRequester() }
        LaunchedEffect(Unit) { focus.requestFocus() }
        AlertDialog(
            onDismissRequest = { done(null) },
            title = { Text("New custom feed") },
            text = {
                OutlinedTextField(
                    value = text,
                    onValueChange = { text = it },
                    label = { Text("Feed name") },
                    singleLine = true,
                    shape = RoundedCornerShape(18.dp),
                    keyboardActions = KeyboardActions(onDone = { done(text.trim()) }),
                    modifier = Modifier.focusRequester(focus),
                )
            },
            dismissButton = { TextButton(onClick = { done(null) }) { Text("Cancel") } },
            confirmButton = { Button(onClick = { done(text.trim()) }) { Text("Create") } },
        )
    }
    if (name.isNullOrEmpty()) return false
    return try {
        app.repository.createMultireddit(username, name, subreddits)
        app.feed.loadMultireddits(force = true)
        true
    } catch (e: Exception) {
        app.navigatorOrNull?.showSnackbar("Could not create feed: ${(e.message ?: e.toString()).removePrefix("Exception: ")}")
        false
    }
}

@OptIn(ExperimentalMaterial3Api::class)
private suspend fun showAccountSheet(current: String, context: android.content.Context) {
    // What to do once the sheet has closed.
    val action = Overlays.show<AccountAction> { done ->
        val cs = MaterialTheme.colorScheme
        val version by app.session.accountsVersion.collectAsStateWithLifecycle()
        val accounts by produceState(listOf(current), version) { value = app.session.accounts().ifEmpty { listOf(current) } }
        // Removing another account confirms over the sheet (Cancel returns to it).
        val sheetScope = rememberCoroutineScope()
        ModalBottomSheet(onDismissRequest = { done(null) }) {
            TapGuard {
                Column(Modifier.navigationBarsPadding()) {
                    Text(
                        "Accounts",
                        Modifier.padding(start = 20.dp, top = 4.dp, end = 20.dp, bottom = 8.dp),
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold,
                    )
                    for (a in accounts) {
                        val isCurrent = a == current
                        Tile(
                            title = { Text("u/$a", color = if (isCurrent) cs.primary else Color.Unspecified) },
                            leading = { LetterAvatar(a, 40.dp, cs.primaryContainer, cs.onPrimaryContainer) },
                            trailing = {
                                if (isCurrent) {
                                    Icon(Icons.Rounded.CheckCircle, null, tint = cs.primary)
                                } else {
                                    IconButton(onClick = { sheetScope.launch { confirmRemove(a) } }) { Icon(Icons.Rounded.Close, "Remove") }
                                }
                            },
                            onClick = if (isCurrent) null else ({ done(AccountAction.Switch(a)) }),
                        )
                    }
                    HorizontalDivider(Modifier.padding(vertical = 4.dp))
                    Tile(
                        title = { Text("Add account") },
                        leading = { Icon(Icons.Rounded.PersonAddAlt1, null) },
                        onClick = { done(AccountAction.Add) },
                    )
                    Tile(
                        title = { Text("Log out of u/$current", color = cs.error) },
                        leading = { Icon(Icons.AutoMirrored.Rounded.Logout, null, tint = cs.error) },
                        onClick = { done(AccountAction.Remove(current)) },
                    )
                    Spacer(Modifier.height(8.dp))
                }
            }
        }
    } ?: return
    when (action) {
        is AccountAction.Switch -> app.session.switchAccount(action.username)
        is AccountAction.Remove -> confirmRemove(action.username)
        AccountAction.Add -> addAccount(context)
    }
}

private sealed interface AccountAction {
    data class Switch(val username: String) : AccountAction
    data class Remove(val username: String) : AccountAction
    data object Add : AccountAction
}

private suspend fun addAccount(context: android.content.Context) {
    try {
        if (app.session.authMode() == "web") {
            // Match the current method: website-session add with fresh cookies
            // (the web login screen signs the new account in and reports
            // "Could not add account: …" itself — this push returns at once).
            app.navigator.push(Route.WebLogin(clearFirst = true))
        } else {
            app.session.addAccount(context)
        }
    } catch (e: Exception) {
        app.navigatorOrNull?.showSnackbar("Could not add account: ${(e.message ?: e.toString()).removePrefix("Exception: ")}")
    }
}

private suspend fun confirmRemove(username: String) {
    val ok = Overlays.show<Boolean> { done ->
        AlertDialog(
            onDismissRequest = { done(null) },
            title = { Text("Log out of u/$username?") },
            text = {
                Text("This removes the account from this device. Your saved API credentials stay so you can add it again.")
            },
            dismissButton = { TextButton(onClick = { done(false) }) { Text("Cancel") } },
            confirmButton = { Button(onClick = { done(true) }) { Text("Log out") } },
        )
    }
    if (ok == true) app.session.removeAccount(username)
}

/**
 * Shown where an account is needed while browsing without one: explains it
 * and offers to sign in (which goes back to the login screen).
 */
@Composable
fun SignInPrompt(message: String, modifier: Modifier = Modifier) {
    val cs = MaterialTheme.colorScheme
    val scope = rememberCoroutineScope()
    BloomCard(modifier.padding(16.dp).fillMaxWidth()) {
        Column(Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.TravelExplore, null, tint = cs.primary)
                Spacer(Modifier.width(10.dp))
                Text("Browsing without an account", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            }
            Spacer(Modifier.height(8.dp))
            Text(message)
            Spacer(Modifier.height(12.dp))
            // Ends the anonymous session; the app then shows login (the
            // Client ID stays filled in).
            Button(onClick = { scope.launch { app.session.logout() } }) {
                Icon(Icons.AutoMirrored.Rounded.Login, null, Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text("Sign in")
            }
        }
    }
}
