package com.bennybar.luli_for_reddit.feature.compose

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.Notes
import androidx.compose.material.icons.outlined.CloudDone
import androidx.compose.material.icons.outlined.GifBox
import androidx.compose.material.icons.rounded.AddPhotoAlternate
import androidx.compose.material.icons.rounded.ArrowDropDown
import androidx.compose.material.icons.rounded.Collections
import androidx.compose.material.icons.rounded.Forum
import androidx.compose.material.icons.rounded.Image
import androidx.compose.material.icons.rounded.Link
import androidx.compose.material.icons.rounded.Title
import androidx.compose.material.icons.rounded.VideoCall
import androidx.compose.material.icons.rounded.Videocam
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.core.get
import com.bennybar.luli_for_reddit.core.int
import com.bennybar.luli_for_reddit.core.net.RedditApiException
import com.bennybar.luli_for_reddit.core.str
import com.bennybar.luli_for_reddit.feature.markdown.MarkdownToolbar
import com.bennybar.luli_for_reddit.model.Flair
import com.bennybar.luli_for_reddit.model.Subreddit
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.nav.Route
import com.bennybar.luli_for_reddit.ui.Overlays
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.io.ByteArrayOutputStream

private enum class Kind(val icon: ImageVector, val label: String) {
    TEXT(Icons.AutoMirrored.Rounded.Notes, "Text"),
    LINK(Icons.Rounded.Link, "Link"),
    IMAGE(Icons.Rounded.Image, "Image"),
    GALLERY(Icons.Rounded.Collections, "Gallery"),
    VIDEO(Icons.Rounded.Videocam, "Video"),
}

/** A picked file (read only when submitting). */
private data class Picked(val uri: Uri, val name: String, val mime: String?)

private const val DRAFT_KEY = "compose_post"

private fun picked(context: Context, uri: Uri, fallbackName: String): Picked =
    Picked(uri, displayName(context, uri)?.ifEmpty { null } ?: fallbackName, context.contentResolver.getType(uri))

private suspend fun readBytes(context: Context, uri: Uri): ByteArray = readUriBytes(context, uri)

/** A JPEG poster frame for a video (Reddit needs one for video posts). */
private suspend fun posterFrame(context: Context, uri: Uri): ByteArray? = withContext(Dispatchers.IO) {
    runCatching {
        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(context, uri)
            val frame = r.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC) ?: return@runCatching null
            ByteArrayOutputStream().use { out ->
                frame.compress(Bitmap.CompressFormat.JPEG, 75, out)
                out.toByteArray()
            }
        } finally {
            r.release()
        }
    }.getOrNull()
}

/**
 * An error for display, as the Flutter build showed it: a Reddit API error
 * reads "HTTP 403 (reason)", followed by Reddit's own message when it sent one.
 */
internal fun errorText(e: Throwable): String {
    if (e is RedditApiException) {
        val head = e.toString()
        val msg = e.message
        return when {
            msg.isNullOrBlank() -> head
            msg.contains("HTTP ${e.statusCode}") -> msg // already says it
            else -> "$head: $msg"
        }
    }
    return (e.message ?: e.toString()).removePrefix("Exception: ")
}

private class Draft(val sr: String, val title: String, val body: String, val url: String, val kind: Kind) {
    val hasContent get() = sr.isNotBlank() || title.isNotBlank() || body.isNotBlank() || url.isNotBlank()
}

private fun loadDraft(initialSubreddit: String?): Draft {
    val empty = Draft(initialSubreddit ?: "", "", "", "", Kind.TEXT)
    val raw = app.drafts.get(DRAFT_KEY) ?: return empty
    return runCatching {
        val m = AppJson.parseToJsonElement(raw)
        Draft(
            sr = if (initialSubreddit.isNullOrEmpty()) m["sr"].str() ?: "" else initialSubreddit,
            title = m["title"].str() ?: "",
            body = m["body"].str() ?: "",
            url = m["url"].str() ?: "",
            kind = m["kind"].int()?.let { Kind.entries.getOrNull(it) } ?: Kind.TEXT,
        )
    }.getOrDefault(empty) // ignore a malformed draft
}

/** New post: text / link / image / gallery / video, flair, NSFW/spoiler, drafts. */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun SubmitScreen(subreddit: String?) {
    val nav = LocalNavigator.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val cs = MaterialTheme.colorScheme

    // Restore the draft (text only; attachments aren't kept).
    val draft = remember { loadDraft(subreddit) }
    var sr by remember { mutableStateOf(draft.sr) }
    var title by remember { mutableStateOf(draft.title) }
    var body by remember { mutableStateOf(TextFieldValue(draft.body, TextRange(draft.body.length))) }
    var url by remember { mutableStateOf(draft.url) }
    var kind by remember { mutableStateOf(draft.kind) }
    var image by remember { mutableStateOf<Picked?>(null) }
    var gallery by remember { mutableStateOf<List<Picked>>(emptyList()) }
    var video by remember { mutableStateOf<Picked?>(null) }
    var nsfw by remember { mutableStateOf(false) }
    var spoiler by remember { mutableStateOf(false) }
    var sendReplies by remember { mutableStateOf(true) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var flairs by remember { mutableStateOf<List<Flair>>(emptyList()) }
    var flair by remember { mutableStateOf<Flair?>(null) }
    var flairsFor by remember { mutableStateOf("") }
    var hasDraft by remember { mutableStateOf(draft.hasContent) }

    val hasMedia = image != null || gallery.isNotEmpty() || video != null

    fun loadFlairs() {
        val name = sr.trim().removePrefix("r/")
        if (name.isEmpty() || name == flairsFor) return
        flairsFor = name
        scope.launch {
            val f = app.repository.getLinkFlairs(name)
            flairs = f
            flair = null
        }
    }

    fun saveDraft() {
        app.drafts.save(
            DRAFT_KEY,
            buildJsonObject {
                put("sr", sr); put("title", title); put("body", body.text); put("url", url); put("kind", kind.ordinal)
            }.toString(),
        )
        hasDraft = sr.isNotBlank() || title.isNotBlank() || body.text.isNotBlank() || url.isNotBlank()
    }

    LaunchedEffect(Unit) { if (sr.isNotBlank()) loadFlairs() }

    val pickImage = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { u ->
        if (u != null) image = picked(context, u, "image.jpg")
    }
    val pickGallery = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(20)) { list ->
        if (list.isNotEmpty()) gallery = list.mapIndexed { i, u -> picked(context, u, "image$i.jpg") }
    }
    val pickVideo = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { u ->
        if (u != null) video = picked(context, u, "video.mp4")
    }

    fun finish(msg: String) {
        app.drafts.clear(DRAFT_KEY)
        nav.showSnackbar(msg)
        nav.pop()
    }

    fun goToPost(name: String, id: String) {
        app.drafts.clear(DRAFT_KEY)
        if (id.isEmpty()) {
            finish("Posted")
        } else {
            nav.pop()
            nav.push(Route.Post(name, id))
        }
    }

    fun submit() {
        val name = sr.trim().removePrefix("r/")
        val t = title.trim()
        error = when {
            name.isEmpty() || t.isEmpty() -> "Subreddit and title are required."
            kind == Kind.LINK && url.isBlank() -> "Enter a URL for a link post."
            kind == Kind.IMAGE && image == null -> "Pick an image to upload."
            kind == Kind.GALLERY && gallery.isEmpty() -> "Pick at least one image."
            kind == Kind.VIDEO && video == null -> "Pick a video to upload."
            else -> null
        }
        if (error != null) return
        busy = true
        val repo = app.repository
        scope.launch {
            try {
                when (kind) {
                    Kind.TEXT -> goToPost(
                        name,
                        repo.submitPost(name, t, "self", text = body.text.trim(), nsfw = nsfw, spoiler = spoiler, sendReplies = sendReplies, flair = flair),
                    )
                    Kind.LINK -> goToPost(
                        name,
                        repo.submitPost(name, t, "link", url = url.trim(), nsfw = nsfw, spoiler = spoiler, sendReplies = sendReplies, flair = flair),
                    )
                    Kind.IMAGE -> {
                        val img = image!!
                        val uploaded = repo.uploadImage(readBytes(context, img.uri), img.name, img.mime ?: mimeForImage(img.name))
                        goToPost(
                            name,
                            repo.submitPost(name, t, "image", url = uploaded, nsfw = nsfw, spoiler = spoiler, sendReplies = sendReplies, flair = flair),
                        )
                    }
                    Kind.GALLERY -> {
                        val ids = gallery.map { g ->
                            repo.uploadMediaAsset(readBytes(context, g.uri), g.name, g.mime ?: mimeForImage(g.name)).assetId
                        }
                        repo.submitGalleryPost(name, t, ids, nsfw = nsfw, spoiler = spoiler, sendReplies = sendReplies, flair = flair)
                        finish("Gallery posted")
                    }
                    Kind.VIDEO -> {
                        val v = video!!
                        val videoBytes = readBytes(context, v.uri)
                        val posterBytes = posterFrame(context, v.uri)
                        val uploaded = repo.uploadMediaAsset(videoBytes, v.name, "video/mp4")
                        val poster = repo.uploadMediaAsset(posterBytes ?: videoBytes, "poster.jpg", "image/jpeg")
                        val id = repo.submitVideoPost(
                            name, t, uploaded.url, poster.url,
                            nsfw = nsfw, spoiler = spoiler, sendReplies = sendReplies, flair = flair,
                        )
                        if (id.isNotEmpty()) goToPost(name, id) else finish("Video posted")
                    }
                }
            } catch (e: Exception) {
                busy = false
                error = errorText(e)
            }
        }
    }

    fun leave() {
        if (!hasMedia) {
            nav.pop()
            return
        }
        scope.launch {
            val ok = Overlays.show<Boolean> { done ->
                AlertDialog(
                    onDismissRequest = { done(false) },
                    title = { Text("Discard attachment?") },
                    text = { Text("Your text is saved as a draft, but the attached image/video is not. Leave anyway?") },
                    confirmButton = { Button(onClick = { done(true) }) { Text("Leave") } },
                    dismissButton = { TextButton(onClick = { done(false) }) { Text("Stay") } },
                )
            }
            if (ok == true) nav.pop()
        }
    }
    BackHandler(enabled = hasMedia) { leave() }

    val fieldColors = TextFieldDefaults.colors(
        focusedIndicatorColor = Color.Transparent,
        unfocusedIndicatorColor = Color.Transparent,
        disabledIndicatorColor = Color.Transparent,
        errorIndicatorColor = Color.Transparent,
    )
    val fieldShape = RoundedCornerShape(18.dp)

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("New post") },
                navigationIcon = { IconButton(onClick = ::leave) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") } },
                actions = {
                    if (hasDraft && !busy) {
                        Row(Modifier.padding(end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Outlined.CloudDone, null, Modifier.size(16.dp), tint = cs.onSurfaceVariant)
                            Spacer(Modifier.width(4.dp))
                            Text("Draft saved", fontSize = 12.sp, color = cs.onSurfaceVariant)
                        }
                    }
                    Button(onClick = ::submit, enabled = !busy, modifier = Modifier.padding(end = 8.dp)) {
                        if (busy) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp) else Text("Post")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
        ) {
            TextField(
                value = sr,
                onValueChange = { sr = it; saveDraft() },
                modifier = Modifier.fillMaxWidth().onFocusChanged { if (!it.isFocused) loadFlairs() },
                label = { Text("Subreddit") },
                prefix = { Text("r/") },
                leadingIcon = { Icon(Icons.Rounded.Forum, null) },
                trailingIcon = {
                    IconButton(onClick = {
                        scope.launch {
                            pickSubreddit()?.let {
                                sr = it
                                saveDraft()
                                loadFlairs()
                            }
                        }
                    }) { Icon(Icons.Rounded.ArrowDropDown, "Choose from your subreddits") }
                },
                singleLine = true,
                keyboardOptions = KeyboardOptions(autoCorrectEnabled = false, imeAction = ImeAction.Next),
                keyboardActions = KeyboardActions(onNext = { loadFlairs(); defaultKeyboardAction(ImeAction.Next) }),
                shape = fieldShape,
                colors = fieldColors,
            )
            Spacer(Modifier.height(12.dp))
            TextField(
                value = title,
                onValueChange = { title = it; saveDraft() },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Title") },
                leadingIcon = { Icon(Icons.Rounded.Title, null) },
                minLines = 1,
                maxLines = 2,
                shape = fieldShape,
                colors = fieldColors,
            )
            if (flairs.isNotEmpty()) {
                Spacer(Modifier.height(12.dp))
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (f in flairs) {
                        FilterChip(
                            selected = flair?.id == f.id,
                            onClick = { flair = if (flair?.id == f.id) null else f },
                            label = { Text(f.text) },
                            shape = CircleShape,
                        )
                    }
                }
            }
            Spacer(Modifier.height(16.dp))
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                Kind.entries.forEachIndexed { i, k ->
                    SegmentedButton(
                        selected = kind == k,
                        onClick = { kind = k; saveDraft() },
                        shape = SegmentedButtonDefaults.itemShape(i, Kind.entries.size),
                        icon = {},
                    ) { Icon(k.icon, k.label) }
                }
            }
            Spacer(Modifier.height(16.dp))
            when (kind) {
                Kind.TEXT -> {
                    TextField(
                        value = body,
                        onValueChange = { body = it; saveDraft() },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("Body (Markdown, optional)") },
                        minLines = 5,
                        maxLines = 12,
                        shape = fieldShape,
                        colors = fieldColors,
                    )
                    MarkdownToolbar(body, { body = it; saveDraft() })
                    TextButton(onClick = {
                        scope.launch {
                            val gif = showGiphyPicker() ?: return@launch
                            val sep = if (body.text.isEmpty()) "" else "\n"
                            val t = "${body.text}$sep$gif"
                            body = TextFieldValue(t, TextRange(t.length))
                            saveDraft()
                        }
                    }) {
                        Icon(Icons.Outlined.GifBox, null, Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text("GIF")
                    }
                }
                Kind.LINK -> TextField(
                    value = url,
                    onValueChange = { url = it; saveDraft() },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("URL") },
                    leadingIcon = { Icon(Icons.Rounded.Link, null) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, autoCorrectEnabled = false),
                    shape = fieldShape,
                    colors = fieldColors,
                )
                Kind.IMAGE -> PickerBox(
                    label = image?.name ?: "Tap to choose an image",
                    icon = Icons.Rounded.AddPhotoAlternate,
                    preview = image?.uri,
                ) { pickImage.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
                Kind.GALLERY -> PickerBox(
                    label = if (gallery.isEmpty()) "Tap to choose images" else "${gallery.size} image(s) selected",
                    icon = Icons.Rounded.Collections,
                    preview = gallery.firstOrNull()?.uri,
                ) { pickGallery.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
                Kind.VIDEO -> PickerBox(
                    label = video?.name ?: "Tap to choose a video",
                    icon = Icons.Rounded.VideoCall,
                    preview = null,
                ) { pickVideo.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.VideoOnly)) }
            }
            Spacer(Modifier.height(16.dp))
            SwitchRow("NSFW", nsfw) { nsfw = it }
            SwitchRow("Spoiler", spoiler) { spoiler = it }
            SwitchRow("Send me reply notifications", sendReplies) { sendReplies = it }
            error?.let {
                Spacer(Modifier.height(8.dp))
                Text(it, color = cs.error)
            }
        }
    }
}

@Composable
private fun SwitchRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable { onChange(!checked) }.padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

@Composable
private fun PickerBox(label: String, icon: ImageVector, preview: Uri?, onClick: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    Box(
        Modifier
            .fillMaxWidth()
            .height(150.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(cs.surfaceContainerHighest)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        if (preview != null) {
            AsyncImage(
                model = preview,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
                alpha = 0.35f,
            )
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(icon, null, Modifier.size(40.dp), tint = cs.onSurfaceVariant)
            Spacer(Modifier.height(8.dp))
            Text(label, Modifier.padding(horizontal = 16.dp), textAlign = TextAlign.Center)
        }
    }
}

/** A sheet of the user's subscriptions; returns the chosen name. */
@OptIn(ExperimentalMaterial3Api::class)
private suspend fun pickSubreddit(): String? = Overlays.show<String> { done ->
    var subs by remember { mutableStateOf<List<Subreddit>?>(null) }
    var failed by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        try {
            subs = app.repository.getSubscribedSubreddits()
        } catch (_: Exception) {
            failed = true
        }
    }
    ModalBottomSheet(onDismissRequest = { done(null) }, sheetState = rememberModalBottomSheetState()) {
        val list = subs
        when {
            failed -> Text("Couldn't load your subreddits.", Modifier.padding(24.dp))
            list == null -> Box(Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            list.isEmpty() -> Text("You aren't subscribed to any subreddits.", Modifier.padding(24.dp))
            else -> LazyColumn(Modifier.navigationBarsPadding()) {
                items(list, key = { it.name }) { s ->
                    ListItem(
                        headlineContent = { Text(s.namePrefixed) },
                        leadingContent = {
                            if (s.iconUrl != null) {
                                AsyncImage(s.iconUrl, null, Modifier.size(32.dp).clip(CircleShape), contentScale = ContentScale.Crop)
                            } else {
                                Box(
                                    Modifier.size(32.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer),
                                    contentAlignment = Alignment.Center,
                                ) { Text(s.name.take(1).uppercase(), color = MaterialTheme.colorScheme.onPrimaryContainer) }
                            }
                        },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                        modifier = Modifier.clickable { done(s.name) },
                    )
                }
            }
        }
    }
}
