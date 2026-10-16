package com.bennybar.luli_for_reddit.feature.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Reply
import androidx.compose.material.icons.rounded.DeleteOutline
import androidx.compose.material.icons.rounded.EditNote
import androidx.compose.material.icons.rounded.MailOutline
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.core.get
import com.bennybar.luli_for_reddit.core.str
import com.bennybar.luli_for_reddit.core.timeAgoPhrase
import com.bennybar.luli_for_reddit.feature.feed.BloomTopBar
import com.bennybar.luli_for_reddit.feature.feed.Tile
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.nav.Route
import com.bennybar.luli_for_reddit.state.Draft

/** A draft as a row: what it is, where it goes, its text, and the screen that resumes it. */
private class DraftRow(val icon: ImageVector, val where: String, val preview: String, val open: Route?)

private fun rowOf(d: Draft): DraftRow {
    val info = d.info
    val json = runCatching { AppJson.parseToJsonElement(d.text) }.getOrNull()
    return when {
        d.key.startsWith("reply_") -> DraftRow(
            Icons.AutoMirrored.Rounded.Reply,
            listOfNotNull(
                info["to"].str()?.let { "Reply to u/$it" } ?: "Reply",
                info["title"].str()?.let { "in \"$it\"" },
                info["sub"].str()?.let { "r/$it" },
            ).joinToString(" · "),
            d.text,
            info["post"].str()?.let { Route.Post(info["sub"].str() ?: "_", it, info["comment"].str()) },
        )
        d.key.startsWith("msgreply_") -> DraftRow(
            Icons.Rounded.MailOutline,
            listOfNotNull(info["to"].str()?.let { "Reply to u/$it" } ?: "Message reply", info["subject"].str()?.takeIf { it.isNotBlank() }).joinToString(" · "),
            d.text,
            Route.MessageThread(d.key.removePrefix("msgreply_")),
        )
        d.key == "compose_msg" -> DraftRow(
            Icons.Rounded.MailOutline,
            json["to"].str()?.takeIf { it.isNotBlank() }?.let { "Message to u/$it" } ?: "New message",
            listOfNotNull(json["subject"].str()?.takeIf { it.isNotBlank() }, json["body"].str()?.takeIf { it.isNotBlank() }).joinToString(" — "),
            Route.ComposeMessage(json["to"].str()?.takeIf { it.isNotBlank() }),
        )
        d.key == "compose_post" -> DraftRow(
            Icons.Rounded.EditNote,
            json["sr"].str()?.takeIf { it.isNotBlank() }?.let { "New post in r/$it" } ?: "New post",
            listOfNotNull(json["title"].str()?.takeIf { it.isNotBlank() }, json["body"].str()?.takeIf { it.isNotBlank() } ?: json["url"].str()?.takeIf { it.isNotBlank() }).joinToString(" — "),
            Route.Submit(json["sr"].str()?.takeIf { it.isNotBlank() }),
        )
        else -> DraftRow(Icons.Rounded.EditNote, "Draft", d.text, null)
    }
}

/**
 * You → Drafts: this account's unfinished replies, messages and posts. Tap to
 * go where it belongs (its composer then restores it); swipe to delete.
 */
@Composable
fun DraftsScreen() {
    val cs = MaterialTheme.colorScheme
    val changes by app.drafts.changes.collectAsStateWithLifecycle()
    val drafts = remember(changes) { app.drafts.list() }
    Scaffold(topBar = { BloomTopBar("Drafts") }, containerColor = cs.surface) { padding ->
        Box(Modifier.fillMaxSize().padding(top = padding.calculateTopPadding())) {
            if (drafts.isEmpty()) {
                Box(Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
                    Text(
                        "No drafts. Unfinished replies, messages and posts are kept here until you send them.",
                        textAlign = TextAlign.Center,
                        color = cs.onSurfaceVariant,
                    )
                }
            } else {
                LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 130.dp)) {
                    items(drafts, key = { it.key }) { d -> DraftItem(d) }
                }
            }
        }
    }
}

@Composable
private fun DraftItem(d: Draft) {
    val cs = MaterialTheme.colorScheme
    val nav = LocalNavigator.current
    val row = remember(d) { rowOf(d) }
    val dismiss = rememberSwipeToDismissBoxState()
    SwipeToDismissBox(
        state = dismiss,
        enableDismissFromStartToEnd = false,
        onDismiss = { value ->
            if (value == SwipeToDismissBoxValue.EndToStart) {
                app.drafts.clear(d.key)
                nav.showSnackbar("Draft deleted")
            }
        },
        backgroundContent = {
            Box(
                Modifier.fillMaxSize().background(cs.errorContainer).padding(horizontal = 24.dp),
                contentAlignment = Alignment.CenterEnd,
            ) { Icon(Icons.Rounded.DeleteOutline, "Delete", tint = cs.onErrorContainer) }
        },
    ) {
        Tile(
            title = { Text(row.preview.ifBlank { "(empty)" }, maxLines = 2, overflow = TextOverflow.Ellipsis) },
            subtitle = {
                Text(
                    listOfNotNull(row.where, d.savedAt.takeIf { it > 0 }?.let { timeAgoPhrase(it) }).joinToString(" · "),
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            },
            leading = { Icon(row.icon, null) },
            modifier = Modifier.background(cs.surface),
            onClick = row.open?.let { r -> { nav.push(r) } },
        )
    }
}
