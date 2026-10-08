package com.bennybar.luli_for_reddit.feature.auth

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.HelpOutline
import androidx.compose.material.icons.automirrored.rounded.Login
import androidx.compose.material.icons.automirrored.rounded.OpenInNew
import androidx.compose.material.icons.outlined.Verified
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.ContentPaste
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.Error
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material.icons.rounded.GifBox
import androidx.compose.material.icons.rounded.Key
import androidx.compose.material.icons.rounded.Link
import androidx.compose.material.icons.rounded.Public
import androidx.compose.material.icons.rounded.RocketLaunch
import androidx.compose.material.icons.rounded.SwapHoriz
import androidx.compose.material.icons.rounded.TravelExplore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.auth.AuthException
import com.bennybar.luli_for_reddit.core.RedditConstants
import com.bennybar.luli_for_reddit.feature.media.openExternally
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.nav.Route
import com.bennybar.luli_for_reddit.ui.Overlays
import com.bennybar.luli_for_reddit.ui.friendlyError
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/**
 * The first-run flow: the user connects their own Reddit API app (client id
 * + redirect uri, optional Giphy key), or signs in through the website, or
 * browses without an account. The root navigates on its own once a session
 * exists.
 */
@Suppress("DEPRECATION") // LocalClipboardManager: plain-text paste/copy is all we need.
@Composable
fun LoginScreen() {
    val context = LocalContext.current
    val nav = LocalNavigator.current
    val focus = LocalFocusManager.current
    val clipboard = LocalClipboardManager.current
    val scope = rememberCoroutineScope()
    val cs = MaterialTheme.colorScheme

    var clientId by remember { mutableStateOf(TextFieldValue("")) }
    var redirect by remember { mutableStateOf(TextFieldValue(RedditConstants.DEFAULT_REDIRECT_URI)) }
    var giphy by remember { mutableStateOf(TextFieldValue("")) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var checkResult by remember { mutableStateOf<String?>(null) }
    var checkOk by remember { mutableStateOf(false) }

    // Prefill whatever was saved before (a retry, or after signing out).
    LaunchedEffect(Unit) {
        val store = app.secureStore
        store.clientId()?.let { clientId = TextFieldValue(it, TextRange(it.length)) }
        store.redirectUri()?.let { redirect = TextFieldValue(it, TextRange(it.length)) }
        store.giphyKey()?.let { giphy = TextFieldValue(it, TextRange(it.length)) }
    }

    fun checkConfig() {
        focus.clearFocus()
        busy = true
        error = null
        checkResult = null
        scope.launch {
            val result = app.authRepository.validateClientId(clientId.text)
            busy = false
            checkOk = result.valid
            checkResult = result.message
        }
    }

    fun login() {
        focus.clearFocus()
        val id = clientId.text.trim()
        val uri = redirect.text.trim()
        when {
            id.isEmpty() -> { error = "Enter your Reddit Client ID first."; return }
            uri.isEmpty() -> { error = "A Redirect URI is required."; return }
            "://" !in uri -> {
                error = "The Redirect URI looks invalid — it should look like ${RedditConstants.DEFAULT_REDIRECT_URI}"
                return
            }
        }
        busy = true
        error = null
        scope.launch {
            // Pre-flight: confirm the client id is a valid installed-app credential
            // before launching the browser, so we can give a precise error.
            val check = app.authRepository.validateClientId(id)
            if (!check.valid) {
                busy = false
                error = check.message
                return@launch
            }
            // Persist credentials early so a retry keeps them.
            app.secureStore.saveCredentials(clientId = id, redirectUri = uri, giphyKey = giphy.text.trim())
            try {
                app.session.login(context, id, uri)
                // The root navigates to Home automatically on success.
            } catch (e: CancellationException) {
                throw e
            } catch (e: AuthException) {
                busy = false
                error = e.message
            } catch (e: Exception) {
                busy = false
                error = "Login failed: ${e.message ?: e}"
            }
        }
    }

    // Read-only browsing with just a Client ID (Reddit refuses anonymous
    // requests without one). Voting, commenting and the inbox need an account.
    fun browseAnonymously() {
        focus.clearFocus()
        if (clientId.text.trim().isEmpty()) {
            error = "Browsing without an account still needs a Reddit Client ID — enter it above."
            return
        }
        busy = true
        error = null
        scope.launch {
            try {
                app.session.browseAnonymously(clientId.text.trim())
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = friendlyError(e)
            } finally {
                busy = false
            }
        }
    }

    // Website-session login (no API key). Shows the risks first, then opens a
    // Reddit login WebView, which stores the session itself.
    fun webLogin() {
        scope.launch {
            val ok = Overlays.show<Boolean> { done ->
                AlertDialog(
                    onDismissRequest = { done(false) },
                    title = { Text("Sign in without an API key") },
                    text = {
                        Text(
                            "This signs you in through the Reddit website instead of the API, so " +
                                "you don't need to create an API key.\n\n" +
                                "Important: this is not Reddit's official API path. It may stop " +
                                "working at any time if Reddit changes their site, and Reddit could " +
                                "consider it against their usage policy and restrict or ban accounts " +
                                "that use it. Use it at your own risk.\n\n" +
                                "The recommended method is still the API key above.",
                        )
                    },
                    dismissButton = { TextButton(onClick = { done(false) }) { Text("Cancel") } },
                    confirmButton = { Button(onClick = { done(true) }) { Text("Continue") } },
                )
            }
            if (ok == true) nav.push(Route.WebLogin)
        }
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(cs.surface)
            .imePadding()
            .verticalScroll(rememberScrollState())
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(start = 24.dp, end = 24.dp, top = 32.dp, bottom = 32.dp),
    ) {
        // Brand
        Box(
            Modifier.size(72.dp).background(cs.primaryContainer, RoundedCornerShape(24.dp)),
            contentAlignment = Alignment.Center,
        ) { Icon(Icons.Rounded.RocketLaunch, null, Modifier.size(38.dp), tint = cs.onPrimaryContainer) }
        Spacer(Modifier.height(20.dp))
        Text("Ilay for Reddit", style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.ExtraBold))
        Spacer(Modifier.height(8.dp))
        Text(
            "Connect your own Reddit API app to sign in. Ilay ships without any keys baked in — " +
                "you provide them once, stored securely on this device.",
            style = MaterialTheme.typography.bodyMedium,
            color = cs.onSurfaceVariant,
        )
        Spacer(Modifier.height(24.dp))

        SetupCard(redirect.text)
        Spacer(Modifier.height(20.dp))

        BloomTextField(
            value = clientId,
            onValueChange = { clientId = it },
            label = "Reddit Client ID",
            placeholder = "e.g. AbCdEf123...",
            leadingIcon = { Icon(Icons.Rounded.Key, null) },
            trailingIcon = {
                IconButton(onClick = {
                    val txt = clipboard.getText()?.text?.trim()
                    if (!txt.isNullOrEmpty()) clientId = TextFieldValue(txt, TextRange(txt.length))
                }) { Icon(Icons.Rounded.ContentPaste, "Paste") }
            },
            plain = true,
        )
        Spacer(Modifier.height(12.dp))
        BloomTextField(
            value = redirect,
            onValueChange = { redirect = it },
            label = "Redirect URI",
            placeholder = RedditConstants.DEFAULT_REDIRECT_URI,
            supportingText = "Must match the redirect URI registered on your Reddit app.",
            leadingIcon = { Icon(Icons.Rounded.Link, null) },
            plain = true,
        )
        // A RedReader-issued client ID only redirects to RedReader's URI.
        TextButton(onClick = {
            val r = RedditConstants.REDREADER_REDIRECT_URI
            redirect = TextFieldValue(r, TextRange(r.length))
        }) {
            Icon(Icons.Rounded.SwapHoriz, null, Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text("Using a RedReader client ID?")
        }
        if (redirect.text.trim().startsWith("redreader:")) {
            Text(
                "If RedReader is also installed, Android will ask which app should finish signing in. " +
                    "Pick Ilay. This client ID was issued to RedReader, and Reddit could revoke it.",
                Modifier.padding(start = 4.dp, end = 4.dp, bottom = 8.dp),
                fontSize = 12.5.sp,
                color = cs.onSurfaceVariant,
            )
        }
        Spacer(Modifier.height(4.dp))
        BloomTextField(
            value = giphy,
            onValueChange = { giphy = it },
            label = "Giphy API Key (optional)",
            placeholder = "Enables GIF picker",
            leadingIcon = { Icon(Icons.Rounded.GifBox, null) },
            plain = true,
        )

        checkResult?.let {
            Spacer(Modifier.height(16.dp))
            Banner(checkOk, it)
        }
        error?.let {
            Spacer(Modifier.height(16.dp))
            Banner(false, it)
        }

        Spacer(Modifier.height(24.dp))
        OutlinedButton(
            onClick = ::checkConfig,
            enabled = !busy,
            modifier = Modifier.fillMaxWidth().defaultMinSize(minHeight = 52.dp),
        ) {
            Icon(Icons.Outlined.Verified, null, Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text("Test configuration")
        }
        Spacer(Modifier.height(12.dp))
        Button(
            onClick = ::login,
            enabled = !busy,
            modifier = Modifier.fillMaxWidth().defaultMinSize(minHeight = 52.dp),
        ) {
            if (busy) {
                CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
            } else {
                Icon(Icons.AutoMirrored.Rounded.Login, null, Modifier.size(18.dp))
            }
            Spacer(Modifier.width(8.dp))
            Text(if (busy) "Working…" else "Connect Reddit account", fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
        }
        Spacer(Modifier.height(20.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            HorizontalDivider(Modifier.weight(1f), color = cs.outlineVariant.copy(alpha = 0.5f))
            Text("or", Modifier.padding(horizontal = 10.dp))
            HorizontalDivider(Modifier.weight(1f), color = cs.outlineVariant.copy(alpha = 0.5f))
        }
        Spacer(Modifier.height(8.dp))
        TextButton(onClick = ::webLogin, enabled = !busy, modifier = Modifier.fillMaxWidth()) {
            Icon(Icons.Rounded.Public, null, Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text("Can't get an API key? Sign in via website")
        }
        TextButton(onClick = ::browseAnonymously, enabled = !busy, modifier = Modifier.fillMaxWidth()) {
            Icon(Icons.Rounded.TravelExplore, null, Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text("Browse without signing in")
        }
    }
}

/** "How to get your Client ID": an expandable card with the setup steps. */
@Composable
private fun SetupCard(redirectUri: String) {
    val cs = MaterialTheme.colorScheme
    val context = LocalContext.current
    var expanded by remember { mutableStateOf(false) }
    val arrow by animateFloatAsState(if (expanded) 180f else 0f, label = "expand")
    BloomCard(Modifier.fillMaxWidth()) {
        Column {
            Row(
                Modifier
                    .fillMaxWidth()
                    .clickable { expanded = !expanded }
                    .padding(horizontal = 16.dp, vertical = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.AutoMirrored.Rounded.HelpOutline, null, tint = cs.primary)
                Spacer(Modifier.width(16.dp))
                Text("How to get your Client ID", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
                Icon(Icons.Rounded.ExpandMore, null, Modifier.rotate(arrow), tint = cs.onSurfaceVariant)
            }
            AnimatedVisibility(expanded) {
                Column(Modifier.padding(start = 20.dp, end = 20.dp, bottom = 16.dp)) {
                    Step(1, "Open reddit.com/prefs/apps and tap \"create app\".")
                    Step(2, "Choose the \"installed app\" type (no secret needed).")
                    Step(3, "Set the redirect URI to exactly:  $redirectUri")
                    Step(4, "Create it. The Client ID is the string just under the app name.")
                    Step(5, "Paste that Client ID below and connect.")
                    Spacer(Modifier.height(8.dp))
                    TextButton(onClick = { openExternally(context, "https://www.reddit.com/prefs/apps") }) {
                        Icon(Icons.AutoMirrored.Rounded.OpenInNew, null, Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text("Open Reddit app settings")
                    }
                }
            }
        }
    }
}

@Suppress("DEPRECATION")
@Composable
private fun Step(n: Int, text: String) {
    val cs = MaterialTheme.colorScheme
    val clipboard = LocalClipboardManager.current
    Row(Modifier.padding(vertical = 5.dp), verticalAlignment = Alignment.Top) {
        Box(Modifier.size(22.dp).background(cs.secondaryContainer, CircleShape), contentAlignment = Alignment.Center) {
            Text("$n", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = cs.onSecondaryContainer)
        }
        Spacer(Modifier.width(12.dp))
        Text(text, Modifier.weight(1f).padding(top = 1.dp))
        if (RedditConstants.CALLBACK_SCHEME in text) {
            IconButton(onClick = { clipboard.setText(AnnotatedString(RedditConstants.DEFAULT_REDIRECT_URI)) }) {
                Icon(Icons.Rounded.ContentCopy, "Copy", Modifier.size(18.dp))
            }
        }
    }
}

@Composable
private fun Banner(ok: Boolean, text: String) {
    val cs = MaterialTheme.colorScheme
    val bg = if (ok) cs.primaryContainer else cs.errorContainer
    val fg = if (ok) cs.onPrimaryContainer else cs.onErrorContainer
    val icon: ImageVector = if (ok) Icons.Rounded.CheckCircle else Icons.Rounded.Error
    Row(
        Modifier.fillMaxWidth().background(bg, RoundedCornerShape(16.dp)).padding(14.dp),
        horizontalArrangement = Arrangement.Start,
    ) {
        Icon(icon, null, Modifier.size(20.dp), tint = fg)
        Spacer(Modifier.width(10.dp))
        Text(text, color = fg)
    }
}
