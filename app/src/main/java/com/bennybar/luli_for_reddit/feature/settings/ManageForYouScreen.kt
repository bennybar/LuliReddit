package com.bennybar.luli_for_reddit.feature.settings

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.TrendingDown
import androidx.compose.material.icons.automirrored.rounded.TrendingUp
import androidx.compose.material.icons.automirrored.rounded.VolumeOff
import androidx.compose.material.icons.outlined.ThumbDown
import androidx.compose.material.icons.outlined.ThumbUp
import androidx.compose.material.icons.rounded.RestartAlt
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.ui.Overlays
import kotlinx.coroutines.launch
import java.util.Locale
import kotlin.math.abs

/**
 * Everything that shapes the "For You (Beta)" feed, visible and undoable:
 * explicit choices, mutes, learned topics and communities, and a full reset.
 * All local and per-account. Long-press the title for local metrics.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun ManageForYouScreen() {
    val nav = LocalNavigator.current
    val m = app.forYou
    val scope = rememberCoroutineScope()
    val cs = MaterialTheme.colorScheme
    val explicit by m.explicit.state.collectAsStateWithLifecycle()
    val mutedSet by m.muted.state.collectAsStateWithLifecycle()
    val weights by m.interest.state.collectAsStateWithLifecycle()
    val keywords by m.keywords.state.collectAsStateWithLifecycle()
    @Suppress("UNUSED_VARIABLE")
    val docFreq by m.docFreq.state.collectAsStateWithLifecycle() // re-rank topics as rarity changes
    val df = m.docFreq

    val muted = mutedSet.sorted()
    // Learned topics, by how much they actually matter: weight × rarity.
    val topics = keywords.entries.filter { abs(it.value) >= 1 }
        .sortedByDescending { abs(it.value) * df.idf(it.key) }
        .take(20)
    val less = weights.entries.filter { it.value < 0 }.sortedBy { it.value }
    val more = weights.entries.filter { it.value >= 3 }.sortedByDescending { it.value }
    val empty = explicit.isEmpty && muted.isEmpty() && topics.isEmpty() && less.isEmpty() && more.isEmpty()

    @Composable
    fun Sign(v: Int) = Icon(
        if (v > 0) Icons.Outlined.ThumbUp else Icons.Outlined.ThumbDown,
        null,
        tint = if (v > 0) cs.primary else cs.error,
    )

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        "Manage For You",
                        Modifier.combinedClickable(onClick = {}, onLongClick = { scope.launch { showMetrics() } }),
                    )
                },
                navigationIcon = {
                    IconButton(onClick = { nav.pop() }) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") }
                },
            )
        },
    ) { padding ->
        LazyColumn(Modifier.fillMaxSize(), contentPadding = androidx.compose.foundation.layout.PaddingValues(
            top = padding.calculateTopPadding(), bottom = padding.calculateBottomPadding() + 32.dp,
        )) {
            if (empty) item("empty") { EmptyState() }
            if (!explicit.isEmpty) {
                item("h:choices") { SectionHeader("Your choices", "What you asked for with More / Less — these don't fade") }
                for ((sub, v) in explicit.subs) {
                    item("sub:$sub") {
                        LeadingTile(
                            leading = { Sign(v) },
                            title = "r/$sub",
                            subtitle = if (v > 0) "More from here" else "Less from here",
                        ) { TextButton(onClick = { m.explicit.setSub(sub, 0) }) { Text("Remove") } }
                    }
                }
                for ((topic, v) in explicit.topics) {
                    item("topic:$topic") {
                        LeadingTile(
                            leading = { Sign(v) },
                            title = "“$topic”",
                            subtitle = if (v > 0) "More about this" else "Less about this",
                        ) { TextButton(onClick = { m.explicit.setTopic(topic, 0) }) { Text("Remove") } }
                    }
                }
            }
            if (muted.isNotEmpty()) {
                item("h:muted") { SectionHeader("Muted", "Hidden from For You entirely") }
                for (sub in muted) {
                    item("muted:$sub") {
                        SettingTile(
                            "r/$sub", icon = Icons.AutoMirrored.Rounded.VolumeOff,
                            trailing = { TextButton(onClick = { m.muted.toggle(sub) }) { Text("Unmute") } },
                        )
                    }
                }
            }
            if (topics.isNotEmpty()) {
                item("h:topics") { SectionHeader("Topics", "Learned from the titles you engage with") }
                for (e in topics) {
                    item("kw:${e.key}") {
                        SettingTile(
                            "“${e.key}”",
                            icon = if (e.value > 0) Icons.AutoMirrored.Rounded.TrendingUp else Icons.AutoMirrored.Rounded.TrendingDown,
                            trailing = {
                                Row {
                                    TextButton(onClick = { m.keywords.reset(e.key) }) { Text("Reset") }
                                    TextButton(onClick = {
                                        m.keywords.reset(e.key)
                                        m.explicit.setTopic(e.key, -1)
                                    }) { Text("Block") }
                                }
                            },
                        )
                    }
                }
            }
            if (less.isNotEmpty()) {
                item("h:less") { SectionHeader("Showing less", "Learned from what you skip or downvote") }
                for (e in less) {
                    item("less:${e.key}") {
                        SettingTile(
                            "r/${e.key}", icon = Icons.Outlined.ThumbDown,
                            trailing = { TextButton(onClick = { m.interest.reset(e.key) }) { Text("Reset") } },
                        )
                    }
                }
            }
            if (more.isNotEmpty()) {
                item("h:more") { SectionHeader("Showing more", "Learned favourites — reset to forget") }
                for (e in more) {
                    item("more:${e.key}") {
                        SettingTile(
                            "r/${e.key}", icon = Icons.Outlined.ThumbUp,
                            trailing = { TextButton(onClick = { m.interest.reset(e.key) }) { Text("Reset") } },
                        )
                    }
                }
            }
            item("reset") {
                Column(Modifier.padding(top = 12.dp)) {
                    OutlinedButton(
                        onClick = { scope.launch { confirmReset() } },
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                    ) {
                        Icon(Icons.Rounded.RestartAlt, null, Modifier.size(18.dp))
                        Spacer(Modifier.size(8.dp))
                        Text("Reset For You")
                    }
                    Text(
                        "Learned signals fade by half in about two weeks; your explicit choices and mutes don't. " +
                            "Everything here stays on this device.",
                        fontSize = 12.5.sp,
                        color = cs.onSurfaceVariant,
                        modifier = Modifier.padding(start = 16.dp, top = 12.dp, end = 16.dp),
                    )
                }
            }
        }
    }
}

/** A tile whose leading slot is arbitrary content (the explicit-topic thumbs). */
@Composable
private fun LeadingTile(
    leading: @Composable () -> Unit,
    title: String,
    subtitle: String,
    trailing: @Composable () -> Unit,
) {
    androidx.compose.material3.ListItem(
        colors = androidx.compose.material3.ListItemDefaults.colors(containerColor = androidx.compose.ui.graphics.Color.Transparent),
        leadingContent = leading,
        headlineContent = { Text(title) },
        supportingContent = { Text(subtitle) },
        trailingContent = trailing,
    )
}

@Composable
private fun EmptyState() {
    val cs = MaterialTheme.colorScheme
    Column(
        Modifier.fillMaxWidth().padding(start = 32.dp, top = 48.dp, end = 32.dp, bottom = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(Icons.Rounded.Tune, null, Modifier.size(48.dp), tint = cs.onSurfaceVariant)
        Spacer(Modifier.height(12.dp))
        Text("Nothing to manage yet", style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(6.dp))
        Text(
            "Long-press a For You post to tune it, or use its ⋯ menu. Your choices and what For You learns will show up here.",
            textAlign = TextAlign.Center,
            color = cs.onSurfaceVariant,
        )
    }
}

private suspend fun confirmReset() {
    if (!confirmDialog(
            "Reset For You?",
            "Forgets everything For You learned and your More / Less choices. Mutes are kept.",
            "Reset",
        )
    ) return
    val m = app.forYou
    m.interest.clear()
    m.keywords.clear()
    m.impressions.clear()
    m.explicit.clear()
    m.subStats.clear()
}

/** Local, never-uploaded counters for judging For You changes. */
private suspend fun showMetrics() {
    val m = app.forYou.metrics
    val t = m.totals()
    fun n(k: String) = t[k] ?: 0
    fun rate(opens: String, impr: String): String {
        val i = n(impr)
        return if (i == 0) "–" else String.format(Locale.ROOT, "%.1f%%", 100.0 * n(opens) / i)
    }
    val rows = buildList {
        add("Seen (primary / discovery)" to "${n("impr.primary")} / ${n("impr.discovery")}")
        add("Open rate (primary)" to rate("open.primary", "impr.primary"))
        add("Open rate (discovery)" to rate("open.discovery", "impr.discovery"))
        add("Read 30s+ (primary / discovery)" to "${n("read30.primary")} / ${n("read30.discovery")}")
        add("Votes" to "${n("vote.primary") + n("vote.discovery")}")
        add("More / Less taps" to "${n("more")} / ${n("less")}")
        add("Discovery appetite" to String.format(Locale.ROOT, "%.2f", m.discoveryAppetite()))
        for (e in t.entries.filter { it.key.startsWith("src.ranked.") }.sortedByDescending { it.value }) {
            add("Placed from ${e.key.substring(11)}" to "${e.value}")
        }
    }
    Overlays.show<Unit> { done ->
        AlertDialog(
            onDismissRequest = { done(null) },
            title = { Text("For You · last 7 days") },
            text = {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    for ((k, v) in rows) {
                        Row(Modifier.fillMaxWidth().padding(vertical = 3.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(k, Modifier.weight(1f))
                            Text(v, fontWeight = FontWeight.Bold)
                        }
                    }
                    Spacer(Modifier.height(8.dp))
                    Text("On this device only. Never uploaded.", style = MaterialTheme.typography.bodySmall)
                }
            },
            confirmButton = { TextButton(onClick = { done(null) }) { Text("Close") } },
        )
    }
}
