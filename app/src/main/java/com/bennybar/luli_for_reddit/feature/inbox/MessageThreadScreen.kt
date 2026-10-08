package com.bennybar.luli_for_reddit.feature.inbox

import androidx.compose.foundation.background
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
import androidx.compose.material.icons.rounded.GifBox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.net.uploadToCatbox
import com.bennybar.luli_for_reddit.core.timeAgo
import com.bennybar.luli_for_reddit.feature.auth.BloomTextField
import com.bennybar.luli_for_reddit.feature.compose.AttachmentControls
import com.bennybar.luli_for_reddit.feature.compose.MediaAttachment
import com.bennybar.luli_for_reddit.feature.compose.showGiphyPicker
import com.bennybar.luli_for_reddit.feature.markdown.RedditMarkdown
import com.bennybar.luli_for_reddit.model.InboxItem
import com.bennybar.luli_for_reddit.model.InboxKind
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.nav.NavCache
import com.bennybar.luli_for_reddit.ui.ErrorView
import kotlinx.coroutines.launch

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
                r != null -> Thread(r)
                loadError != null -> ErrorView(loadError, onRetry = { attempt++ })
                else -> CircularProgressIndicator(Modifier.align(Alignment.Center))
            }
        }
    }
}

@Composable
private fun Thread(root: InboxItem) {
    val nav = LocalNavigator.current
    val scope = rememberCoroutineScope()
    val draftKey = "msgreply_${root.fullname}"
    val messages = remember(root) { mutableStateListOf<InboxItem>().apply { add(root); addAll(root.replies) } }
    var reply by remember { mutableStateOf(TextFieldValue(app.drafts.get(draftKey) ?: "")) }
    var media by remember { mutableStateOf<MediaAttachment?>(null) }
    var attachOpen by remember { mutableStateOf(false) }
    var sending by remember { mutableStateOf(false) }
    val listState = rememberLazyListState()
    val me = app.session.username
    val cs = MaterialTheme.colorScheme

    // Chat-style: start at (and follow) the newest message.
    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) listState.animateScrollToItem(messages.size - 1)
    }

    fun setReply(v: TextFieldValue) {
        reply = v
        app.drafts.save(draftKey, v.text)
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
                messages.add(
                    InboxItem(
                        fullname = "local_${messages.size}",
                        kind = InboxKind.MESSAGE,
                        author = me.ifEmpty { "you" },
                        subject = root.subject,
                        body = text,
                        createdUtc = System.currentTimeMillis(),
                    ),
                )
                reply = TextFieldValue("")
                media = null
                attachOpen = false
            } catch (e: Exception) {
                nav.showSnackbar((e.message ?: e.toString()).removePrefix("Exception: "))
            } finally {
                sending = false
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
                itemsIndexed(messages, key = { _, m -> m.fullname }, contentType = { _, _ -> "message" }) { _, m ->
                    val mine = me.isNotEmpty() && m.author.equals(me, ignoreCase = true)
                    Box(Modifier.fillMaxWidth().padding(bottom = 10.dp), contentAlignment = if (mine) Alignment.CenterEnd else Alignment.CenterStart) {
                        Column(
                            Modifier
                                .widthIn(max = maxBubble)
                                .background(if (mine) cs.primaryContainer else cs.surfaceContainerHighest, RoundedCornerShape(18.dp))
                                .padding(12.dp),
                        ) {
                            Text("u/${m.author} · ${timeAgo(m.createdUtc)}", fontSize = 11.sp, color = cs.onSurfaceVariant)
                            Spacer(Modifier.height(4.dp))
                            RedditMarkdown(m.body, fontSize = 14.sp, selectable = true, onLinkClick = nav::openLink)
                        }
                    }
                }
            }
        }
        Column(Modifier.navigationBarsPadding().padding(start = 12.dp, end = 12.dp, top = 4.dp, bottom = 12.dp)) {
            if (attachOpen || media != null) {
                AttachmentControls(
                    media = media,
                    onChanged = { media = it },
                    onError = { nav.showSnackbar(it) },
                    catboxForImages = true,
                    leading = {
                        IconButton(onClick = {
                            scope.launch {
                                val gif = showGiphyPicker() ?: return@launch
                                val t = reply.text
                                val next = if (t.isBlank()) gif else "${t.trimEnd()}\n\n$gif"
                                setReply(TextFieldValue(next, TextRange(next.length)))
                            }
                        }) { Icon(Icons.Rounded.GifBox, "GIF") }
                    },
                )
                Spacer(Modifier.height(6.dp))
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = { attachOpen = !attachOpen }, enabled = !sending) {
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
                )
                Spacer(Modifier.size(8.dp))
                FilledIconButton(onClick = ::send, enabled = !sending) {
                    if (sending) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                    else Icon(Icons.AutoMirrored.Rounded.Send, "Send")
                }
            }
        }
    }
}
