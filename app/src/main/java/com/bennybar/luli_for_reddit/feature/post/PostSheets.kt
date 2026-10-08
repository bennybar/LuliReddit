package com.bennybar.luli_for_reddit.feature.post

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.TextSnippet
import androidx.compose.material.icons.automirrored.rounded.Send
import androidx.compose.material.icons.outlined.CheckCircleOutline
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.DownloadForOffline
import androidx.compose.material.icons.outlined.Flag
import androidx.compose.material.icons.outlined.GifBox
import androidx.compose.material.icons.outlined.ReportGmailerrorred
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Block
import androidx.compose.material.icons.rounded.LockOpen
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.rounded.OfflinePin
import androidx.compose.material.icons.automirrored.rounded.OpenInNew
import androidx.compose.material.icons.rounded.Repeat
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.RadioButton
import androidx.compose.material3.SheetState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.unit.dp
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.net.RedditApiException
import com.bennybar.luli_for_reddit.core.net.uploadToCatbox
import com.bennybar.luli_for_reddit.data.RedditRepository
import com.bennybar.luli_for_reddit.feature.compose.AttachmentControls
import com.bennybar.luli_for_reddit.feature.compose.MediaAttachment
import com.bennybar.luli_for_reddit.feature.compose.errorText
import com.bennybar.luli_for_reddit.feature.compose.showGiphyPicker
import com.bennybar.luli_for_reddit.feature.foryou.showTuneSheet
import com.bennybar.luli_for_reddit.feature.markdown.MarkdownToolbar
import com.bennybar.luli_for_reddit.model.Comment
import com.bennybar.luli_for_reddit.model.Post
import com.bennybar.luli_for_reddit.nav.Route
import com.bennybar.luli_for_reddit.ui.Overlays
import com.bennybar.luli_for_reddit.ui.friendlyError
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// ---------------------------------------------------------------------------
// Shared sheet helpers
// ---------------------------------------------------------------------------

/** Animates [sheet] closed, then runs [block] (e.g. completing an Overlays result). */
@OptIn(ExperimentalMaterial3Api::class)
fun CoroutineScope.hideThen(sheet: SheetState, block: () -> Unit) {
    launch { sheet.hide() }.invokeOnCompletion { block() }
}

internal fun snack(msg: String) = app.navigator.showSnackbar(msg.removePrefix("Exception: "))

/** Copies [text] to the clipboard and confirms. */
fun copyToClipboard(text: String) {
    val cm = app.context.getSystemService(ClipboardManager::class.java)
    cm?.setPrimaryClip(ClipData.newPlainText("text", text))
    snack("Copied")
}

/** The Bloom filled input: radius 18, no underline. */
@Composable
internal fun bloomFieldColors() = TextFieldDefaults.colors(
    focusedIndicatorColor = Color.Transparent,
    unfocusedIndicatorColor = Color.Transparent,
    disabledIndicatorColor = Color.Transparent,
    errorIndicatorColor = Color.Transparent,
)

internal val BloomFieldShape = RoundedCornerShape(18.dp)

// ---------------------------------------------------------------------------
// Reply / edit composer
// ---------------------------------------------------------------------------

/**
 * Reply composer (bottom sheet) for a post (t3_) or comment (t1_).
 * Supports image (inline via Reddit richtext) / video (Catbox) attachments,
 * GIFs, drafts. Returns the created comment (at depth parentDepth + 1), or
 * null if dismissed.
 */
suspend fun showReplySheet(parentFullname: String, parentDepth: Int, replyingTo: String? = null): Comment? =
    Overlays.show<Comment> { done ->
        ComposeSheet(
            title = if (replyingTo == null) "Reply" else "Reply to u/$replyingTo",
            submitLabel = "Reply",
            allowAttachments = true,
            draftKey = "reply_$parentFullname",
            initialText = null,
            onSubmit = { text, media ->
                val repo = app.repository
                when {
                    media == null -> repo.reply(parentFullname, text, depth = parentDepth + 1)
                    media.isVideo -> {
                        val url = uploadToCatbox(media.bytes, media.filename)
                        repo.reply(parentFullname, if (text.isEmpty()) url else "$text\n\n$url", depth = parentDepth + 1)
                    }
                    else -> repo.replyWithImage(parentFullname, text, media.bytes, media.filename, media.mimeType, depth = parentDepth + 1)
                }
            },
            done = done,
        )
    }

/** Editor for your own post/comment body. Returns the new text, or null. */
suspend fun showEditSheet(thingFullname: String, initialText: String): String? =
    Overlays.show<String> { done ->
        ComposeSheet(
            title = "Edit",
            submitLabel = "Save",
            allowAttachments = false,
            draftKey = null,
            initialText = initialText,
            onSubmit = { text, _ -> app.repository.editText(thingFullname, text); text },
            done = done,
        )
    }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun <T> ComposeSheet(
    title: String,
    submitLabel: String,
    allowAttachments: Boolean,
    /** When set, the in-progress text is autosaved/restored under this key. */
    draftKey: String?,
    initialText: String?,
    onSubmit: suspend (String, MediaAttachment?) -> T,
    done: (T?) -> Unit,
) {
    val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    var value by remember {
        val t = initialText ?: draftKey?.let { app.drafts.get(it) } ?: ""
        mutableStateOf(TextFieldValue(t, TextRange(t.length)))
    }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var media by remember { mutableStateOf<MediaAttachment?>(null) }
    val focus = remember { FocusRequester() }
    val cs = MaterialTheme.colorScheme

    fun setText(v: TextFieldValue) {
        if (v.text != value.text) draftKey?.let { app.drafts.save(it, v.text) }
        value = v
    }

    fun insertGif() = scope.launch {
        val url = showGiphyPicker() ?: return@launch
        val sep = if (value.text.isEmpty()) "" else "\n"
        val t = "${value.text}$sep$url"
        setText(TextFieldValue(t, TextRange(t.length)))
    }

    // Dismissed while sending: the send still completes (as in Flutter) and
    // its result is still delivered; only the sheet goes away.
    var dismissed by remember { mutableStateOf(false) }

    fun submit() {
        val text = value.text.trim()
        if (text.isEmpty() && media == null) return
        busy = true
        error = null
        // On the app scope: closing the sheet mustn't cancel the request.
        app.scope.launch {
            try {
                val result = onSubmit(text, media)
                draftKey?.let { app.drafts.clear(it) }
                if (dismissed) done(result) else scope.hideThen(sheet) { done(result) }
            } catch (e: Exception) {
                if (dismissed) {
                    snack(errorText(e))
                    done(null)
                } else {
                    busy = false
                    error = errorText(e)
                }
            }
        }
    }

    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }

    if (dismissed) return
    ModalBottomSheet(onDismissRequest = { if (busy) dismissed = true else done(null) }, sheetState = sheet) {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(start = 16.dp, end = 16.dp, bottom = 16.dp)
                .imePadding()
                .verticalScroll(rememberScrollState()),
        ) {
            Text(title, style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold))
            Spacer(Modifier.height(12.dp))
            TextField(
                value = value,
                onValueChange = ::setText,
                modifier = Modifier.fillMaxWidth().focusRequester(focus),
                minLines = 3,
                maxLines = 8,
                placeholder = { Text("Markdown supported") },
                shape = BloomFieldShape,
                colors = bloomFieldColors(),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
            )
            MarkdownToolbar(value, ::setText)
            Spacer(Modifier.height(6.dp))
            if (allowAttachments) {
                AttachmentControls(
                    media = media,
                    onChanged = { media = it; error = null },
                    onError = { error = it },
                    leading = {
                        TextButton(onClick = { insertGif() }) {
                            Icon(Icons.Outlined.GifBox, null, Modifier.size(18.dp))
                            Spacer(Modifier.size(8.dp))
                            Text("GIF")
                        }
                    },
                )
            } else {
                TextButton(onClick = { insertGif() }) {
                    Icon(Icons.Outlined.GifBox, null, Modifier.size(18.dp))
                    Spacer(Modifier.size(8.dp))
                    Text("GIF")
                }
            }
            error?.let {
                Spacer(Modifier.height(8.dp))
                Text(it, color = cs.error)
            }
            Spacer(Modifier.height(12.dp))
            Button(onClick = ::submit, enabled = !busy, modifier = Modifier.fillMaxWidth()) {
                if (busy) {
                    CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                } else {
                    Icon(Icons.AutoMirrored.Rounded.Send, null, Modifier.size(18.dp))
                }
                Spacer(Modifier.size(8.dp))
                Text(if (busy) "Sending…" else submitLabel)
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Post overflow sheet
// ---------------------------------------------------------------------------

/**
 * The post overflow sheet: share, save offline, hide, copy, report,
 * block, crosspost, open in browser, mod actions, Tune For You.
 */
fun showPostActionsSheet(post: Post) {
    Overlays.launch { done -> PostActionsSheet(post, done) }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PostActionsSheet(post: Post, done: () -> Unit) {
    val sheet = rememberModalBottomSheetState()
    val scope = rememberCoroutineScope()
    // Ignore taps briefly so the gesture that opened the sheet can't fall
    // through onto an item.
    var armed by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { delay(300); armed = true }
    val offline by app.offline.state.collectAsState()
    val savedOffline = offline.any { it.id == post.id }
    val link = "https://reddit.com${post.permalink}"

    /** Closes the sheet, then runs [action] on the app scope (outlives the sheet). */
    fun pick(action: suspend () -> Unit) {
        if (!armed) return
        scope.hideThen(sheet) {
            done()
            app.scope.launch { action() }
        }
    }

    @Composable
    fun item(icon: ImageVector, title: String, subtitle: String? = null, action: suspend () -> Unit) {
        ListItem(
            headlineContent = { Text(title) },
            supportingContent = subtitle?.let { { Text(it) } },
            leadingContent = { Icon(icon, null) },
            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
            modifier = Modifier.clickable { pick(action) },
        )
    }

    ModalBottomSheet(onDismissRequest = done, sheetState = sheet) {
        Column(Modifier.verticalScroll(rememberScrollState()).navigationBarsPadding()) {
            item(Icons.Outlined.Share, "Share link") {
                // Sharing is a strong interest signal.
                app.forYou.learner.share(post)
                app.navigator.share(link, subject = post.title)
            }
            item(Icons.AutoMirrored.Outlined.TextSnippet, "Share with title", "Includes the post title above the link") {
                app.forYou.learner.share(post)
                app.navigator.shareWithTitle(link, post.title)
            }
            item(Icons.Outlined.VisibilityOff, "Hide") { hidePost(post) }
            item(
                if (savedOffline) Icons.Rounded.OfflinePin else Icons.Outlined.DownloadForOffline,
                if (savedOffline) "Remove offline copy" else "Save for offline",
                if (savedOffline) null else "Keep it with its comments in Read later",
            ) {
                if (savedOffline) {
                    app.offline.remove(post.id)
                    snack("Removed from Read later")
                } else {
                    snack("Saving for offline…")
                    try {
                        app.offline.save(post)
                        snack("Saved to Read later")
                    } catch (e: Exception) {
                        snack("Couldn't save: ${friendlyError(e)}")
                    }
                }
            }
            item(Icons.Outlined.ContentCopy, "Copy text") {
                copyToClipboard(if (post.isSelf && post.selftext.isNotEmpty()) post.selftext else post.title)
            }
            item(Icons.Outlined.Flag, "Report") { showReportDialog(post.fullname) }
            item(Icons.Rounded.Block, "Block u/${post.author}") { confirmBlockUser(post.author) }
            item(Icons.Rounded.Repeat, "Crosspost") { showCrosspostDialog(post) }
            item(Icons.AutoMirrored.Rounded.OpenInNew, "Open in browser") {
                runCatching {
                    app.context.startActivity(
                        Intent(Intent.ACTION_VIEW, Uri.parse(link)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                }.onFailure { snack("No app can open this link.") }
            }
            if (post.canModPost) {
                HorizontalDivider(Modifier.padding(vertical = 4.dp))
                ListItem(
                    headlineContent = { Text("Moderate", style = MaterialTheme.typography.labelLarge) },
                    leadingContent = { Icon(Icons.Outlined.Shield, null) },
                    colors = ListItemDefaults.colors(
                        containerColor = Color.Transparent,
                        headlineColor = MaterialTheme.colorScheme.onSurfaceVariant,
                        leadingIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                    ),
                )
                item(Icons.Outlined.CheckCircleOutline, "Approve") { modAction("Approved") { it.modApprove(post.fullname) } }
                item(Icons.Rounded.Block, "Remove") { modAction("Removed") { it.modRemove(post.fullname) } }
                item(Icons.Outlined.ReportGmailerrorred, "Remove as spam") {
                    modAction("Removed as spam") { it.modRemove(post.fullname, spam = true) }
                }
                item(
                    if (post.locked) Icons.Rounded.LockOpen else Icons.Outlined.Lock,
                    if (post.locked) "Unlock" else "Lock",
                ) { modAction(if (post.locked) "Unlocked" else "Locked") { it.modLock(post.fullname, !post.locked) } }
            }
            HorizontalDivider(Modifier.padding(vertical = 4.dp))
            item(Icons.Rounded.AutoAwesome, "Tune For You", "Why it's here · more or less like it · mute r/${post.subreddit}") {
                showTuneSheet(post)
            }
            Spacer(Modifier.height(8.dp))
        }
    }
}

/** Runs a moderator action and reports the outcome. True when it went through. */
suspend fun modAction(doneMsg: String, action: suspend (RedditRepository) -> Unit): Boolean {
    try {
        action(app.repository)
        snack(doneMsg)
        return true
    } catch (e: RedditApiException) {
        snack(
            if (e.statusCode == 403) "Reddit refused that. If you moderate this community, " +
                "sign out and back in so Ilay can request moderator permission."
            else friendlyError(e),
        )
    } catch (e: Exception) {
        snack(friendlyError(e))
    }
    return false
}

/** Hides [post] on Reddit and in open feeds (app.hiddenPosts), with Undo. */
suspend fun hidePost(post: Post) {
    val repo = app.repository
    app.hiddenPosts.add(post.id)
    try {
        repo.setHidden(post.fullname, true)
        app.navigator.showSnackbar("Post hidden", actionLabel = "Undo") {
            app.hiddenPosts.remove(post.id)
            app.scope.launch { runCatching { repo.setHidden(post.fullname, false) } } // best effort
        }
    } catch (e: Exception) {
        app.hiddenPosts.remove(post.id)
        snack("Couldn't hide: ${friendlyError(e)}")
    }
}

private val reportReasons = listOf(
    "Spam",
    "Harassment or bullying",
    "Hate speech",
    "Violence or threats",
    "Misinformation",
    "Breaks subreddit rules",
)

/** Report dialog: preset reasons or a custom one. Works for posts and comments. */
suspend fun showReportDialog(fullname: String) {
    val reason = Overlays.show<String> { done ->
        var selected by remember { mutableStateOf<String?>(null) }
        var custom by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { done(null) },
            title = { Text("Report") },
            text = {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    for (r in reportReasons) {
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .selectable(selected = selected == r, role = Role.RadioButton) { selected = r; custom = "" }
                                .padding(vertical = 2.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            RadioButton(selected = selected == r, onClick = null)
                            Spacer(Modifier.size(12.dp))
                            Text(r, style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                    Spacer(Modifier.height(8.dp))
                    TextField(
                        value = custom,
                        onValueChange = { custom = it; selected = null },
                        placeholder = { Text("Other reason (optional)") },
                        shape = BloomFieldShape,
                        colors = bloomFieldColors(),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            },
            confirmButton = {
                Button(onClick = { (custom.trim().ifEmpty { null } ?: selected)?.let(done) }) { Text("Report") }
            },
            dismissButton = { TextButton(onClick = { done(null) }) { Text("Cancel") } },
        )
    } ?: return
    try {
        app.repository.report(fullname, reason)
        snack("Reported. Thanks.")
    } catch (e: Exception) {
        snack("Could not report: ${errorText(e)}")
    }
}

private suspend fun showCrosspostDialog(post: Post) {
    val result = Overlays.show<Pair<String, String>> { done ->
        var sr by remember { mutableStateOf("") }
        var title by remember { mutableStateOf(post.title) }
        AlertDialog(
            onDismissRequest = { done(null) },
            title = { Text("Crosspost") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    TextField(
                        value = sr,
                        onValueChange = { sr = it },
                        label = { Text("Subreddit") },
                        prefix = { Text("r/") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(autoCorrectEnabled = false),
                        shape = BloomFieldShape,
                        colors = bloomFieldColors(),
                        modifier = Modifier.fillMaxWidth(),
                    )
                    TextField(
                        value = title,
                        onValueChange = { title = it },
                        label = { Text("Title") },
                        minLines = 1,
                        maxLines = 2,
                        shape = BloomFieldShape,
                        colors = bloomFieldColors(),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            },
            confirmButton = {
                Button(onClick = {
                    val s = sr.trim().removePrefix("r/")
                    if (s.isNotEmpty() && title.trim().isNotEmpty()) done(s to title.trim())
                }) { Text("Post") }
            },
            dismissButton = { TextButton(onClick = { done(null) }) { Text("Cancel") } },
        )
    } ?: return
    val (srName, title) = result
    try {
        val id = app.repository.submitCrosspost(srName, title, post.fullname)
        app.navigator.push(Route.Post(srName, id))
    } catch (e: Exception) {
        snack("Crosspost failed: ${errorText(e)}")
    }
}

/** Confirms and blocks a user. Reusable from posts, comments and profiles. */
suspend fun confirmBlockUser(username: String) {
    if (username.isEmpty() || username == "[deleted]") return
    val ok = Overlays.show<Boolean> { done ->
        AlertDialog(
            onDismissRequest = { done(false) },
            title = { Text("Block u/$username?") },
            text = {
                Text(
                    "You won't see their posts, comments, or messages anymore. You can " +
                        "unblock them later in Reddit settings.",
                )
            },
            confirmButton = { Button(onClick = { done(true) }) { Text("Block") } },
            dismissButton = { TextButton(onClick = { done(false) }) { Text("Cancel") } },
        )
    }
    if (ok != true) return
    try {
        app.repository.blockUser(username)
        snack("Blocked u/$username")
    } catch (e: Exception) {
        snack("Could not block: ${errorText(e)}")
    }
}

/** "Delete [what]? This cannot be undone." */
suspend fun confirmDelete(what: String): Boolean =
    Overlays.show<Boolean> { done ->
        AlertDialog(
            onDismissRequest = { done(false) },
            title = { Text("Delete $what?") },
            text = { Text("This cannot be undone.") },
            confirmButton = { Button(onClick = { done(true) }) { Text("Delete") } },
            dismissButton = { TextButton(onClick = { done(false) }) { Text("Cancel") } },
        )
    } == true
