package com.bennybar.luli_for_reddit.feature.home

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.layout.Box
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
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Bookmark
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.DynamicFeed
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.OfflinePin
import androidx.compose.material.icons.rounded.PeopleAlt
import androidx.compose.material.icons.rounded.PersonAddAlt1
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.TravelExplore
import androidx.compose.material.icons.rounded.UnfoldMore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalIconButton
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.auth.SessionState
import com.bennybar.luli_for_reddit.feature.feed.Async
import com.bennybar.luli_for_reddit.feature.feed.BloomCard
import com.bennybar.luli_for_reddit.feature.feed.LetterAvatar
import com.bennybar.luli_for_reddit.feature.feed.Tile
import com.bennybar.luli_for_reddit.feature.feed.SectionHeader
import com.bennybar.luli_for_reddit.feature.feed.TapGuard
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.nav.Route
import com.bennybar.luli_for_reddit.ui.Overlays
import kotlinx.coroutines.launch

/** The Account tab: profile + account switcher, Read later, settings, custom feeds. */
@Composable
internal fun AccountTab() {
    val cs = MaterialTheme.colorScheme
    val nav = LocalNavigator.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val session by app.session.state.collectAsStateWithLifecycle()
    val s = (session as? SessionState.LoggedIn)?.session
    val username = s?.username ?: ""
    val anonymous = s?.anonymous ?: false
    val multis by app.feed.multireddits.collectAsStateWithLifecycle()
    val version by app.feed.version.collectAsStateWithLifecycle()
    LaunchedEffect(anonymous, version) { if (!anonymous) app.feed.loadMultireddits() }

    fun accountSheet() = scope.launch { showAccountSheet(username, context) }

    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 130.dp)) {
        if (anonymous) {
            item(key = "signin") {
                SignInPrompt(
                    "You're browsing without an account. Sign in to vote, comment, save, see your inbox and get your own frontpage.",
                )
            }
        } else {
            // Profile header
            item(key = "profile") {
                Row(Modifier.padding(start = 16.dp, top = 16.dp, end = 16.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    LetterAvatar(username, 56.dp, cs.primaryContainer, cs.onPrimaryContainer, fontSize = 22.sp)
                    Spacer(Modifier.width(16.dp))
                    Column(Modifier.weight(1f)) {
                        Row(
                            Modifier.clickable { accountSheet() }.padding(vertical = 2.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                "u/$username",
                                Modifier.weight(1f, fill = false),
                                style = MaterialTheme.typography.titleLarge,
                                fontWeight = FontWeight.Bold,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                            Icon(Icons.Rounded.UnfoldMore, null, Modifier.size(20.dp))
                        }
                        Text(
                            "View profile",
                            Modifier.clickable { nav.openUser(username) }.padding(vertical = 2.dp),
                            color = cs.primary,
                            style = MaterialTheme.typography.labelLarge,
                        )
                    }
                    FilledTonalIconButton(onClick = { accountSheet() }) { Icon(Icons.Rounded.PeopleAlt, "Switch / add account") }
                }
            }
        }
        item(key = "offline") {
            NavTile(Icons.Rounded.OfflinePin, "Read later", "Threads saved for offline reading") { nav.push(Route.Offline) }
        }
        // Settings (primary). The settings list itself lives on its own screen.
        item(key = "settings") {
            NavTile(Icons.Rounded.Settings, "Settings", "Appearance, feeds, privacy, notifications and more") { nav.push(Route.Settings) }
        }
        if (!anonymous) {
            item(key = "saved") { NavTile(Icons.Rounded.Bookmark, "Saved", "Posts and comments you saved") { nav.push(Route.Saved) } }
        }
        item(key = "history") { NavTile(Icons.Rounded.History, "History", "Posts you've viewed on this device") { nav.push(Route.History) } }
        item(key = "div") { HorizontalDivider(Modifier.padding(vertical = 8.dp), color = cs.outlineVariant.copy(alpha = 0.5f)) }

        // Custom feeds (secondary)
        if (!anonymous) {
            item(key = "feeds_header") {
                Row(Modifier.padding(start = 16.dp, top = 8.dp, end = 16.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    SectionHeader("Custom feeds", Modifier.weight(1f))
                    TextButton(onClick = { scope.launch { createMulti(username) } }) {
                        Icon(Icons.Rounded.Add, null, Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("New")
                    }
                }
            }
            when (val m = multis) {
                Async.Loading -> item(key = "feeds_loading") {
                    Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                }
                is Async.Error -> {}
                is Async.Data -> items(m.value, key = { "multi_${it.name}" }) { multi ->
                    Tile(
                        title = { Text(multi.displayName) },
                        subtitle = { Text("${multi.subreddits.size} subreddits") },
                        leading = {
                            Box(
                                Modifier.size(40.dp).background(cs.tertiaryContainer, CircleShape),
                                contentAlignment = Alignment.Center,
                            ) {
                                Icon(Icons.Rounded.DynamicFeed, null, Modifier.size(20.dp), tint = cs.onTertiaryContainer)
                            }
                        },
                        onClick = { nav.push(Route.Multireddit(username, multi.name)) },
                    )
                }
            }
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

private suspend fun createMulti(username: String) {
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
    if (name.isNullOrEmpty()) return
    try {
        app.repository.createMultireddit(username, name)
        app.feed.loadMultireddits(force = true)
    } catch (e: Exception) {
        app.navigatorOrNull?.showSnackbar("Could not create feed: ${(e.message ?: e.toString()).removePrefix("Exception: ")}")
    }
}

@OptIn(ExperimentalMaterial3Api::class)
private suspend fun showAccountSheet(current: String, context: android.content.Context) {
    // What to do once the sheet has closed.
    val action = Overlays.show<AccountAction> { done ->
        val cs = MaterialTheme.colorScheme
        val version by app.session.accountsVersion.collectAsStateWithLifecycle()
        val accounts by produceState(listOf(current), version) { value = app.session.accounts().ifEmpty { listOf(current) } }
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
                                    IconButton(onClick = { done(AccountAction.Remove(a)) }) { Icon(Icons.Rounded.Close, "Remove") }
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
            // Match the current method: website-session add (the web login
            // screen signs the new account in).
            app.navigator.push(Route.WebLogin)
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
