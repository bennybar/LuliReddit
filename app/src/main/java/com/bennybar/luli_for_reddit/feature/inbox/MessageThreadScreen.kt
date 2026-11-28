package com.bennybar.luli_for_reddit.feature.inbox

import androidx.compose.material3.LocalContentColor
import com.bennybar.luli_for_reddit.ui.Loading
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.Send
import androidx.compose.material.icons.outlined.AddPhotoAlternate
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.Videocam
import androidx.compose.material.icons.rounded.ContentPaste
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.net.uploadToCatbox
import com.bennybar.luli_for_reddit.core.timeAgo
import com.bennybar.luli_for_reddit.feature.auth.BloomTextField
import com.bennybar.luli_for_reddit.feature.compose.AttachmentPreview
import com.bennybar.luli_for_reddit.feature.compose.MediaAttachment
import com.bennybar.luli_for_reddit.feature.compose.AttachmentLoading
import com.bennybar.luli_for_reddit.feature.compose.COMMENT_LIMIT
import com.bennybar.luli_for_reddit.feature.compose.LengthCounter
import com.bennybar.luli_for_reddit.feature.compose.keyboardMediaReceiver
import com.bennybar.luli_for_reddit.feature.compose.redditLength
import com.bennybar.luli_for_reddit.feature.compose.pasteImageAttachment
import com.bennybar.luli_for_reddit.feature.compose.readAttachment
import com.bennybar.luli_for_reddit.feature.media.launchForResult
import com.bennybar.luli_for_reddit.ui.Overlays
import com.bennybar.luli_for_reddit.feature.markdown.RedditMarkdown
import com.bennybar.luli_for_reddit.model.InboxItem
import com.bennybar.luli_for_reddit.model.InboxKind
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.nav.NavCache
import com.bennybar.luli_for_reddit.ui.ErrorView
import kotlinx.serialization.json.put
import kotlinx.serialization.json.buildJsonObject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import com.bennybar.luli_for_reddit.ui.userName
import com.bennybar.luli_for_reddit.ui.subredditName
import com.bennybar.luli_for_reddit.feature.feed.LetterAvatar
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material3.HorizontalDivider
import androidx.compose.ui.text.style.TextAlign
import androidx.lifecycle.compose.collectAsStateWithLifecycle

/** A private-message conversation. The root InboxItem is in NavCache under [fullname] (else fetched). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MessageThreadScreen(fullname: String) {
    val nav = LocalNavigator.current
    var root by remember { mutableStateOf(NavCache.get<InboxItem>(fullname)) }
    var loadError by remember { mutableStateOf<Throwable?>(null) }
    var attempt by remember { mutableStateOf(0) }

    // Opened from a notification: the thread isn't in memory, so fetch it.
    LaunchedEffect(attempt) {
        if (root != null) return@LaunchedEffect
        loadError = null
        try {
            root = app.repository.getMessageThread(fullname) ?: throw Exception("This message is no longer available.")
        } catch (e: Exception) {
            loadError = e
        }
    }

    val r = root
    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        r?.subject?.ifEmpty { null } ?: "Message",
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold),
                    )
                },
                navigationIcon = {
                    IconButton(onClick = { nav.pop() }) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                    scrolledContainerColor = MaterialTheme.colorScheme.surface,
                ),
            )
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(top = padding.calculateTopPadding())) {
            when {
                r != null -> Thread(listOf(r), conversation = false)
                loadError != null -> ErrorView(loadError, onRetry = { attempt++ })
                else -> Loading(Modifier.align(Alignment.Center))
            }
        }
    }
}

/**
 * Every loaded message with one person (#315), [key] as [Correspondent.key]: the Messages
 * list's threads with them, oldest first, as one chat. Their new ones are read on opening.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConversationScreen(key: String) {
    val nav = LocalNavigator.current
    val state by app.inbox.tab("messages").collectAsStateWithLifecycle()
    val me = app.session.username
    LaunchedEffect(Unit) { app.inbox.ensureLoaded("messages") }
    // Taken once, as it opens: new mail or marking read doesn't rebuild the chat under the
    // reply being typed. The "N new" line keeps showing where the new ones began.
    var conv by remember { mutableStateOf<Conversation?>(null) }
    LaunchedEffect(state.items, state.loading) {
        if (conv != null || state.loading) return@LaunchedEffect
        val found = conversations(state.items, me).firstOrNull { it.with.key == key }
        conv = found
        if (found != null) app.inbox.markReadMany(unreadIn(found.threads, me))
    }
    val c = conv
    val cs = MaterialTheme.colorScheme
    val icons by app.authorAvatars.icons.collectAsStateWithLifecycle()
    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        if (c != null) {
                            if (c.with.isSubreddit) {
                                Box(Modifier.size(36.dp).background(cs.tertiaryContainer, CircleShape), contentAlignment = Alignment.Center) {
                                    Icon(Icons.Outlined.Shield, null, Modifier.size(20.dp), tint = cs.onTertiaryContainer)
                                }
                            } else {
                                LetterAvatar(c.with.name, 36.dp, cs.surfaceContainerHighest, cs.onSurfaceVariant, imageUrl = icons[c.with.name.lowercase()])
                            }
                            Spacer(Modifier.size(10.dp))
                        }
                        Text(
                            c?.let { if (it.with.isSubreddit) subredditName(it.with.name) else userName(it.with.name) } ?: "Messages",
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold),
                        )
                    }
                },
                navigationIcon = {
                    IconButton(onClick = { nav.pop() }) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                    scrolledContainerColor = MaterialTheme.colorScheme.surface,
                ),
            )
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(top = padding.calculateTopPadding())) {
            when {
                c != null -> Thread(c.threads, conversation = true)
                state.loading -> Loading(Modifier.align(Alignment.Center))
                state.error != null -> ErrorView(state.error, onRetry = { app.inbox.refresh("messages") })
                else -> Text("These messages aren't loaded any more.", Modifier.align(Alignment.Center).padding(32.dp))
            }
        }
    }
}

/**
 * [threads] as one chat, oldest first. As a [conversation] (#315) each thread starts under
 * its date and subject, and a line marks where the new ones begin; a reply goes to the
 * newest thread.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Thread(threads: List<InboxItem>, conversation: Boolean) {
    val root = threads.last()
    val nav = LocalNavigator.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val draftKey = "msgreply_${root.fullname}"
    val me = app.session.username
    val entries = remember(threads) { mutableStateListOf<ChatEntry>().apply { addAll(chatEntries(threads, me, dividers = conversation)) } }
    val messages = entries.filterIsInstance<ChatEntry.Message>().map { it.message }
    var reply by remember { mutableStateOf(TextFieldValue(app.drafts.get(draftKey) ?: "")) }
    var media by remember { mutableStateOf<MediaAttachment?>(null) }
    var sending by remember { mutableStateOf(false) }
    // A picked file still being read: sending now would go without it.
    var attaching by remember { mutableStateOf(false) }
    val listState = rememberLazyListState()
    val cs = MaterialTheme.colorScheme

    // Chat-style: start at (and follow) the newest message.
    LaunchedEffect(entries.size) {
        if (entries.isNotEmpty()) listState.animateScrollToItem(entries.size - 1)
    }

    fun setReply(v: TextFieldValue) {
        reply = v
        app.drafts.save(
            draftKey, v.text,
            buildJsonObject {
                put("kind", "msgreply"); put("subject", root.subject)
                (messages.firstOrNull { !it.author.equals(me, ignoreCase = true) }?.author ?: root.author).let { put("to", it) }
            },
        )
    }

    fun send() {
        var text = reply.text.trim()
        val m = media
        if (text.isEmpty() && m == null) return
        sending = true
        // Reply to the most recent real message in the thread for correct threading.
        val target = messages.last { !it.fullname.startsWith("local_") }.fullname
        scope.launch {
            try {
                if (m != null) {
                    // Reddit messages are markdown-text only, so host on Catbox + link.
                    val url = uploadToCatbox(m.bytes, m.filename)
                    text = if (text.isEmpty()) url else "$text\n\n$url"
                }
                app.repository.sendReply(target, text)
                app.drafts.clear(draftKey)
                entries.add(
                    ChatEntry.Message(InboxItem(
                        fullname = "local_${entries.size}",
                        kind = InboxKind.MESSAGE,
                        author = me.ifEmpty { "you" },
                        subject = root.subject,
                        body = text,
                        createdUtc = System.currentTimeMillis(),
                    )),
                )
                reply = TextFieldValue("")
                media = null
            } catch (e: Exception) {
                nav.showSnackbar((e.message ?: e.toString()).removePrefix("Exception: "))
            } finally {
                sending = false
            }
        }
    }

    fun setMedia(emptyMsg: String? = null, pick: suspend () -> MediaAttachment?) {
        scope.launch {
            try {
                val m = pick()
                if (m == null) {
                    if (emptyMsg != null) nav.showSnackbar(emptyMsg)
                    return@launch
                }
                media = m
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                nav.showSnackbar((e.message ?: e.toString()).removePrefix("Exception: "))
            }
        }
    }

    suspend fun pick(isVideo: Boolean): MediaAttachment? {
        val type = if (isVideo) ActivityResultContracts.PickVisualMedia.VideoOnly else ActivityResultContracts.PickVisualMedia.ImageOnly
        val uri = launchForResult(ActivityResultContracts.PickVisualMedia(), PickVisualMediaRequest(type)) ?: return null
        attaching = true
        try {
            return readAttachment(context, uri, isVideo)
        } finally {
            attaching = false
        }
    }

    // The attach menu, as a bottom sheet (image / video / paste).
    fun showAttachMenu() {
        scope.launch {
            val choice = Overlays.show<Int> { done ->
                ModalBottomSheet(onDismissRequest = { done(null) }) {
                    Column(Modifier.navigationBarsPadding()) {
                        AttachOption(Icons.Outlined.Image, "Attach image") { done(0) }
                        AttachOption(Icons.Outlined.Videocam, "Attach video") { done(1) }
                        AttachOption(Icons.Rounded.ContentPaste, "Paste image") { done(2) }
                    }
                }
            } ?: return@launch
            when (choice) {
                0 -> setMedia { pick(isVideo = false) }
                1 -> setMedia { pick(isVideo = true) }
                else -> setMedia(emptyMsg = "No image on the clipboard.") { pasteImageAttachment(context) }
            }
        }
    }

    Column(Modifier.fillMaxSize().imePadding()) {
        BoxWithConstraints(Modifier.weight(1f)) {
            val maxBubble = maxWidth * 0.82f
            LazyColumn(
                state = listState,
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(12.dp),
            ) {
                itemsIndexed(entries, key = { _, e -> e.key }, contentType = { _, e -> e::class.simpleName }) { _, e ->
                    when (e) {
                        is ChatEntry.ThreadStart -> Text(
                            "${dayLabel(e.root.createdUtc)} · ${e.root.subject.ifEmpty { "(no subject)" }}",
                            Modifier.fillMaxWidth().padding(top = 8.dp, bottom = 10.dp),
                            textAlign = TextAlign.Center,
                            fontSize = 12.sp,
                            color = cs.onSurfaceVariant,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        is ChatEntry.NewFrom -> Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                            HorizontalDivider(Modifier.weight(1f), color = cs.outlineVariant)
                            Text("${e.count} new", Modifier.padding(horizontal = 10.dp), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = cs.primary)
                            HorizontalDivider(Modifier.weight(1f), color = cs.outlineVariant)
                        }
                        is ChatEntry.Message -> MessageBubble(e.message, me, maxBubble)
                    }
                }
            }
        }
        Column(Modifier.navigationBarsPadding().padding(start = 12.dp, end = 12.dp, top = 4.dp, bottom = 12.dp)) {
            if (attaching) {
                AttachmentLoading()
                Spacer(Modifier.height(6.dp))
            } else {
                media?.let { m ->
                    AttachmentPreview(m, onRemove = { media = null })
                    Spacer(Modifier.height(6.dp))
                }
            }
            LengthCounter(reply.text, COMMENT_LIMIT)
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = ::showAttachMenu, enabled = !sending && !attaching) {
                    Icon(Icons.Outlined.AddPhotoAlternate, "Attach")
                }
                BloomTextField(
                    value = reply,
                    onValueChange = ::setReply,
                    modifier = Modifier.weight(1f),
                    placeholder = "Reply…",
                    singleLine = false,
                    minLines = 1,
                    maxLines = 5,
                    mediaReceiver = Modifier.keyboardMediaReceiver(onMedia = { media = it }, onError = nav::showSnackbar, onLoading = { attaching = it }),
                )
                Spacer(Modifier.size(8.dp))
                FilledIconButton(onClick = ::send, enabled = !sending && !attaching && redditLength(reply.text.trim()) <= COMMENT_LIMIT) {
                    if (sending) Loading(Modifier.size(24.dp), color = LocalContentColor.current)
                    else Icon(Icons.AutoMirrored.Rounded.Send, "Send")
                }
            }
        }
    }
}

@Composable
private fun AttachOption(icon: ImageVector, label: String, onClick: () -> Unit) {
    ListItem(
        content = { Text(label) },
        leadingContent = { Icon(icon, null) },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        modifier = Modifier.clickable(onClick = onClick),
    )
}

/** A short date for a thread's start in a conversation: "Today", else "Nov 12" (with the year when not this one). */
private fun dayLabel(at: Long): String {
    val zone = java.time.ZoneId.systemDefault()
    val d = java.time.Instant.ofEpochMilli(at).atZone(zone).toLocalDate()
    val today = java.time.LocalDate.now(zone)
    val pattern = if (d.year == today.year) "MMM d" else "MMM d, yyyy"
    return if (d == today) "Today" else d.format(java.time.format.DateTimeFormatter.ofPattern(pattern))
}

@Composable
private fun MessageBubble(m: InboxItem, me: String, maxBubble: androidx.compose.ui.unit.Dp) {
    val nav = LocalNavigator.current
    val cs = MaterialTheme.colorScheme
    val mine = isMine(m, me)
    Box(Modifier.fillMaxWidth().padding(bottom = 10.dp), contentAlignment = if (mine) Alignment.CenterEnd else Alignment.CenterStart) {
        Column(
            Modifier
                .widthIn(max = maxBubble)
                .background(if (mine) cs.primaryContainer else cs.surfaceContainerHighest, RoundedCornerShape(18.dp))
                .padding(12.dp),
        ) {
            Text("${userName(m.author)} · ${timeAgo(m.createdUtc)}", fontSize = 11.sp, color = cs.onSurfaceVariant)
            Spacer(Modifier.height(4.dp))
            RedditMarkdown(m.body, fontSize = 14.sp, selectable = true, onLinkClick = nav::openLink)
        }
    }
}
