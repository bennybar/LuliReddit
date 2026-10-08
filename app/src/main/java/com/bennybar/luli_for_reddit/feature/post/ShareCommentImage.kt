package com.bennybar.luli_for_reddit.feature.post

import android.content.Intent
import android.graphics.Bitmap
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.IosShare
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import com.bennybar.luli_for_reddit.core.compactNumber
import com.bennybar.luli_for_reddit.feature.markdown.RedditMarkdown
import com.bennybar.luli_for_reddit.model.Comment
import com.bennybar.luli_for_reddit.model.Post
import com.bennybar.luli_for_reddit.ui.Overlays
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Previews a comment and its parent chain as an image card, then shares it
 * as a PNG. Usernames can be hidden before sharing.
 */
fun showShareCommentImage(post: Post, chain: List<Comment>) {
    Overlays.launch { done -> ShareImageDialog(post, chain, done) }
}

@Composable
private fun ShareImageDialog(post: Post, chain: List<Comment>, done: () -> Unit) {
    var hideNames by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    val layer = rememberGraphicsLayer()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    fun share() {
        busy = true
        scope.launch {
            try {
                val bitmap = layer.toImageBitmap().asAndroidBitmap()
                val file = withContext(Dispatchers.IO) {
                    val dir = File(context.cacheDir, "share").apply { mkdirs() }
                    File(dir, "ilay_comment_${System.currentTimeMillis()}.png").also { f ->
                        f.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
                    }
                }
                val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
                val send = Intent(Intent.ACTION_SEND).apply {
                    type = "image/png"
                    putExtra(Intent.EXTRA_STREAM, uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                done()
            } catch (_: Exception) {
                snack("Couldn't create the image")
            } finally {
                busy = false
            }
        }
    }

    AlertDialog(
        onDismissRequest = done,
        title = { Text("Share as image") },
        text = {
            Column {
                Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState())) {
                    ChainCard(
                        post,
                        chain,
                        hideNames,
                        Modifier
                            .clip(RoundedCornerShape(12.dp))
                            .drawWithContent {
                                // Record what the card draws, so it can become the PNG.
                                layer.record { this@drawWithContent.drawContent() }
                                drawLayer(layer)
                            },
                    )
                }
                Row(Modifier.fillMaxWidth().padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("Hide usernames", Modifier.weight(1f))
                    Switch(checked = hideNames, onCheckedChange = { hideNames = it })
                }
            }
        },
        confirmButton = {
            Button(onClick = ::share, enabled = !busy) {
                Icon(Icons.Rounded.IosShare, null, Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text("Share")
            }
        },
        dismissButton = { TextButton(onClick = done) { Text("Cancel") } },
    )
}

/** The card that becomes the image: post title, then the comment chain. */
@Composable
private fun ChainCard(post: Post, chain: List<Comment>, hideNames: Boolean, modifier: Modifier) {
    val cs = MaterialTheme.colorScheme
    val names = remember(chain, hideNames) { CommentTree.shareNames(chain, hideNames) }
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    Column(modifier.background(cs.surface).padding(14.dp)) {
        Text("r/${post.subreddit}", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = cs.onSurfaceVariant)
        Spacer(Modifier.height(4.dp))
        Text(post.title, fontSize = 16.sp, fontWeight = FontWeight.Bold, lineHeight = 20.8.sp, color = cs.onSurface)
        Spacer(Modifier.height(12.dp))
        chain.forEachIndexed { i, c ->
            val bar = if (i == chain.lastIndex) cs.primary else cs.outlineVariant
            Column(
                Modifier
                    .padding(start = (i * 10).dp, bottom = 8.dp)
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(12.dp))
                    .background(cs.surfaceContainerLow)
                    .drawBehind {
                        val w = 3.dp.toPx()
                        drawRect(bar, Offset(if (rtl) size.width - w else 0f, 0f), Size(w, size.height))
                    }
                    .padding(start = 10.dp, top = 6.dp, end = 6.dp, bottom = 6.dp)
                    .heightIn(min = 0.dp),
            ) {
                Text(
                    "${names[i]} · ${compactNumber(c.score)} points",
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = cs.onSurfaceVariant,
                )
                Spacer(Modifier.height(4.dp))
                RedditMarkdown(c.body, fontSize = 14.sp, color = cs.onSurface)
            }
        }
        Text(
            "Shared from Ilay for Reddit",
            fontSize = 10.5.sp,
            color = cs.onSurfaceVariant,
            modifier = Modifier.align(Alignment.End),
        )
    }
}
