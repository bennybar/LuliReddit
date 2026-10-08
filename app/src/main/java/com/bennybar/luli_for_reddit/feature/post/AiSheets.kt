package com.bennybar.luli_for_reddit.feature.post

import android.provider.Settings
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.ErrorOutline
import androidx.compose.material.icons.rounded.Forum
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.feature.markdown.IconTooltip
import com.bennybar.luli_for_reddit.feature.markdown.RedditMarkdown
import com.bennybar.luli_for_reddit.model.Comment
import com.bennybar.luli_for_reddit.model.Post
import com.bennybar.luli_for_reddit.ui.Overlays
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.sin

private fun aiBaseUrl(): String = app.settings.value.let { if (it.aiUseCustomUrl) it.aiBaseUrl else "https://api.openai.com" }

/** Runs an AI thread summary and shows the result (markdown) with copy. */
fun showSummarySheet(post: Post, comments: List<Comment>) {
    val key = app.post.aiKey.value
    if (key.isNullOrEmpty()) {
        snack("Add an OpenAI key in Settings → AI summaries.")
        return
    }
    val s = app.settings.value
    val style = SummaryStyle.entries[s.aiSummaryStyle.coerceIn(0, SummaryStyle.entries.size - 1)]
    val threadText = AiService.buildThreadText(post, comments, s.aiMaxChars)
    val baseUrl = aiBaseUrl()
    Overlays.launch { done -> SummarySheet(baseUrl, key, s.aiModel, style, threadText, done) }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SummarySheet(baseUrl: String, apiKey: String, model: String, style: SummaryStyle, threadText: String, done: () -> Unit) {
    var loading by remember { mutableStateOf(true) }
    var result by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var attempt by remember { mutableIntStateOf(0) }
    val cs = MaterialTheme.colorScheme

    LaunchedEffect(attempt) {
        loading = true
        error = null
        try {
            result = AiService.summarize(baseUrl, apiKey, model, style, threadText)
        } catch (e: CancellationException) {
            throw e // the sheet closed
        } catch (e: Exception) {
            error = (e.message ?: e.toString()).removePrefix("Exception: ")
        }
        loading = false
    }

    // Flutter's DraggableScrollableSheet (opens at 60%, drags up to 92%): the
    // sheet is 92% tall and opens partially expanded; dragging up reveals the rest.
    val maxHeight = LocalConfiguration.current.screenHeightDp.dp * 0.92f
    ModalBottomSheet(onDismissRequest = done, sheetState = rememberModalBottomSheetState()) {
        Column(
            Modifier
                .fillMaxWidth()
                .height(maxHeight)
                .verticalScroll(rememberScrollState())
                .padding(start = 20.dp, end = 20.dp, top = 4.dp, bottom = 28.dp)
                .navigationBarsPadding(),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.AutoAwesome, null, Modifier.size(18.dp), tint = cs.primary)
                Spacer(Modifier.width(8.dp))
                Text(
                    "AI summary · ${style.label}",
                    style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.Bold),
                    modifier = Modifier.weight(1f),
                )
                if (result != null && !loading) {
                    IconTooltip("Copy") {
                        IconButton(onClick = { copyToClipboard(result!!) }) {
                            Icon(Icons.Rounded.ContentCopy, "Copy", Modifier.size(18.dp))
                        }
                    }
                }
            }
            Spacer(Modifier.height(12.dp))
            when {
                loading -> Box(Modifier.fillMaxWidth().padding(28.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
                error != null -> {
                    Text(error!!, color = cs.error)
                    Spacer(Modifier.height(12.dp))
                    Button(onClick = { attempt++ }) { Text("Retry") }
                }
                else -> RedditMarkdown(result ?: "", selectable = true)
            }
            if (!loading && error == null) {
                Spacer(Modifier.height(16.dp))
                Text("Generated by $model. AI summaries can be wrong.", fontSize = 11.sp, color = cs.onSurfaceVariant)
            }
        }
    }
}

/**
 * "Ask about this thread": a short chat with the AI about the post and its
 * comments. Follow-up questions keep the conversation; nothing is kept after
 * the sheet closes.
 */
fun showAskSheet(post: Post, comments: List<Comment>) {
    val key = app.post.aiKey.value
    if (key.isNullOrEmpty()) return
    val s = app.settings.value
    val threadText = AiService.buildThreadText(post, comments, s.aiMaxChars)
    val baseUrl = aiBaseUrl()
    Overlays.launch { done -> AskThreadSheet(baseUrl, key, s.aiModel, threadText, done) }
}

private val starters = listOf(
    "What do most people agree on?",
    "Did OP add anything in the comments?",
    "Any useful links or sources?",
    "What are the strongest counterarguments?",
)

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
private fun AskThreadSheet(baseUrl: String, apiKey: String, model: String, threadText: String, done: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val messages = remember { mutableStateListOf<AiMessage>() }
    var input by remember { mutableStateOf("") }
    var waiting by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var failedQuestion by remember { mutableStateOf<String?>(null) } // retried by "Try again"
    val list = rememberLazyListState()
    val scope = rememberCoroutineScope()

    fun toBottom() = scope.launch {
        val n = list.layoutInfo.totalItemsCount
        if (n > 0) list.animateScrollToItem(n - 1)
    }

    fun send(raw: String) {
        val question = raw.trim()
        if (question.isEmpty() || waiting) return
        val history = messages.toList()
        messages.add(AiMessage(true, question))
        waiting = true
        error = null
        failedQuestion = null
        input = ""
        toBottom()
        scope.launch {
            try {
                val answer = AiService.ask(baseUrl, apiKey, model, threadText, history, question)
                messages.add(AiMessage(false, answer))
                waiting = false
            } catch (e: CancellationException) {
                throw e // the sheet closed
            } catch (e: Exception) {
                messages.removeAt(messages.lastIndex) // the question goes back into the box
                input = question
                waiting = false
                error = (e.message ?: e.toString()).removePrefix("Exception: ")
                failedQuestion = question
            }
            delay(16)
            toBottom()
        }
    }

    val height = LocalConfiguration.current.screenHeightDp.dp * 0.75f
    ModalBottomSheet(onDismissRequest = done, sheetState = sheet) {
        Column(Modifier.height(height).imePadding()) {
            Row(Modifier.padding(start = 20.dp, end = 20.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(36.dp).clip(CircleShape).background(cs.primaryContainer), contentAlignment = Alignment.Center) {
                    Icon(Icons.Rounded.Forum, null, Modifier.size(19.dp), tint = cs.onPrimaryContainer)
                }
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text("Ask about this thread", style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold))
                    Text("$model · answers can be wrong", fontSize = 12.sp, color = cs.onSurfaceVariant)
                }
            }
            LazyColumn(
                Modifier.weight(1f).fillMaxWidth(),
                state = list,
                contentPadding = androidx.compose.foundation.layout.PaddingValues(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 12.dp),
            ) {
                if (messages.isEmpty() && !waiting) {
                    item(key = "intro") {
                        Column {
                            Text("Answers come only from this post and its comments.", color = cs.onSurfaceVariant)
                            Spacer(Modifier.height(12.dp))
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                for (q in starters) SuggestionChip(onClick = { send(q) }, label = { Text(q) })
                            }
                        }
                    }
                }
                itemsIndexed(messages, key = { i, _ -> "m$i" }) { _, m -> Bubble(m) }
                if (waiting) item(key = "thinking") { Thinking() }
                if (error != null) {
                    item(key = "error") {
                        Row(Modifier.padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Rounded.ErrorOutline, null, Modifier.size(18.dp), tint = cs.error)
                            Spacer(Modifier.width(8.dp))
                            Text(error!!, color = cs.error, modifier = Modifier.weight(1f))
                            failedQuestion?.let { q -> TextButton(onClick = { send(q) }) { Text("Try again") } }
                        }
                    }
                }
            }
            // One rounded pill: the field (no underline, no outline) with the
            // send button inside it.
            Row(
                Modifier
                    .navigationBarsPadding()
                    .padding(start = 12.dp, end = 12.dp, top = 4.dp, bottom = 12.dp)
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(28.dp))
                    .background(cs.surfaceContainerHigh)
                    .padding(start = 18.dp, end = 5.dp, top = 4.dp, bottom = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(Modifier.weight(1f).padding(vertical = 8.dp)) {
                    if (input.isEmpty()) Text("Ask anything about this thread…", color = cs.onSurfaceVariant)
                    BasicTextField(
                        value = input,
                        onValueChange = { input = it },
                        textStyle = MaterialTheme.typography.bodyLarge.copy(color = cs.onSurface),
                        cursorBrush = SolidColor(cs.primary),
                        minLines = 1,
                        maxLines = 4,
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences, imeAction = ImeAction.Send),
                        keyboardActions = KeyboardActions(onSend = { send(input) }),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                Spacer(Modifier.width(6.dp))
                val ready = !waiting && input.isNotBlank()
                val bg by animateColorAsState(if (ready) cs.primary else cs.surfaceContainerHighest, tween(200), label = "send")
                Box(Modifier.size(42.dp).clip(CircleShape).background(bg), contentAlignment = Alignment.Center) {
                    IconTooltip("Send") {
                        IconButton(onClick = { send(input) }, enabled = ready) {
                            Icon(
                                Icons.Rounded.ArrowUpward,
                                "Send",
                                tint = if (ready) cs.onPrimary else cs.onSurfaceVariant.copy(alpha = 0.6f),
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun Bubble(m: AiMessage) {
    val cs = MaterialTheme.colorScheme
    val maxW = LocalConfiguration.current.screenWidthDp.dp * 0.82f
    Box(Modifier.fillMaxWidth().padding(top = 10.dp), contentAlignment = if (m.fromUser) Alignment.CenterEnd else Alignment.CenterStart) {
        Box(
            Modifier
                .widthIn(max = maxW)
                .clip(RoundedCornerShape(18.dp))
                .background(if (m.fromUser) cs.primaryContainer else cs.surfaceContainerHigh)
                .padding(horizontal = 14.dp, vertical = 10.dp),
        ) {
            if (m.fromUser) Text(m.text, color = cs.onPrimaryContainer)
            else RedditMarkdown(m.text, selectable = true)
        }
    }
}

private val easeInOutCubic = CubicBezierEasing(0.645f, 0.045f, 0.355f, 1f)
private val thinkingStatus = listOf("Reading the post…", "Going through the comments…", "Weighing the replies…", "Writing an answer…")
private val reelWidths = listOf(0.9f, 0.62f, 0.78f, 0.5f, 0.7f)

/**
 * While the AI works: a little reel of comment cards scrolls past while a
 * highlight reads each one, with a pulsing sparkle and a status line that
 * moves from reading to writing. In the spirit of Home's loading deck.
 */
@Composable
private fun Thinking() {
    val cs = MaterialTheme.colorScheme
    val reel = remember { Animatable(0f) }
    var shift by remember { mutableIntStateOf(0) } // rows already scrolled past, so the reel never repeats
    var phase by remember { mutableIntStateOf(0) }
    // "Remove animations" (system animator scale 0): the reel stands still.
    val context = LocalContext.current
    val still = remember { Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f }
    LaunchedEffect(still) {
        while (!still) {
            reel.animateTo(1f, tween(900, easing = LinearEasing))
            shift++
            reel.snapTo(0f)
        }
    }
    LaunchedEffect(Unit) {
        while (phase < thinkingStatus.size - 1) {
            delay(2600)
            phase++
        }
    }
    val rowH = 22.dp
    Box(Modifier.fillMaxWidth().padding(top = 10.dp), contentAlignment = Alignment.CenterStart) {
        Column(
            Modifier
                .width(250.dp)
                .clip(RoundedCornerShape(18.dp))
                .background(cs.surfaceContainerHigh)
                .padding(start = 12.dp, top = 10.dp, end = 14.dp, bottom = 10.dp),
        ) {
            val v = reel.value
            val t = easeInOutCubic.transform(v)
            val pulse = 0.5f + 0.5f * sin(v * PI.toFloat())
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Rounded.AutoAwesome,
                    null,
                    Modifier.size(22.dp).scale(0.85f + 0.25f * pulse).rotate((shift + v) * 30f),
                    tint = lerp(cs.primary, cs.tertiary, pulse),
                )
                Spacer(Modifier.width(10.dp))
                // Three rows visible; the middle one is being "read".
                Box(Modifier.weight(1f).height(rowH * 3).clipToBounds()) {
                    for (i in 0 until 4) {
                        val focus = when (i) { 2 -> t; 1 -> 1 - t; else -> 0f }
                        ReelRow(
                            width = reelWidths[(i + shift) % reelWidths.size],
                            focus = focus,
                            modifier = Modifier.offset(y = rowH * (i - t)).height(rowH),
                        )
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
            AnimatedContent(
                targetState = phase,
                transitionSpec = {
                    (fadeIn(tween(350)) + slideInVertically(tween(350)) { (it * 0.4f).toInt() }) togetherWith fadeOut(tween(350))
                },
                label = "status",
            ) { p ->
                Text(thinkingStatus[p], fontSize = 12.5.sp, fontWeight = FontWeight.SemiBold, color = cs.onSurfaceVariant)
            }
        }
    }
}

/** One mini comment in the reel: an avatar dot and a text bar, tinted by [focus] (0–1) while it's read. */
@Composable
private fun ReelRow(width: Float, focus: Float, modifier: Modifier) {
    val cs = MaterialTheme.colorScheme
    Row(modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(14.dp).clip(CircleShape).background(lerp(cs.surfaceContainerHighest, cs.tertiary, focus)))
        Spacer(Modifier.width(8.dp))
        Box(Modifier.weight(1f)) {
            Box(
                Modifier
                    .fillMaxWidth(width)
                    .height(8.dp)
                    .clip(RoundedCornerShape(5.dp))
                    .background(lerp(cs.surfaceContainerHighest, cs.primary, focus * 0.55f)),
            )
        }
    }
}
