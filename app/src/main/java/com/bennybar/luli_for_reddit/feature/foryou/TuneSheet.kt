package com.bennybar.luli_for_reddit.feature.foryou

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.HelpOutline
import androidx.compose.material.icons.outlined.ThumbDown
import androidx.compose.material.icons.outlined.ThumbUp
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material.icons.rounded.Tag
import androidx.compose.material.icons.automirrored.rounded.VolumeOff
import androidx.compose.material.icons.automirrored.rounded.VolumeUp
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.feature.settings.OverlaySheet
import com.bennybar.luli_for_reddit.model.Post
import com.bennybar.luli_for_reddit.nav.Route
import com.bennybar.luli_for_reddit.ui.Overlays

/**
 * "Tune For You" for one post: why it's here, and explicit More/Less for
 * its subreddit and its most distinctive topics (one "less" no longer
 * demotes every word of the title), plus mute.
 */
fun showTuneSheet(post: Post) {
    val m = app.forYou
    fun toast(msg: String) {
        val nav = app.navigatorOrNull ?: return
        nav.showSnackbar(msg, actionLabel = "Manage") { nav.push(Route.ManageForYou) }
    }

    // The title's 1–2 most distinctive words: rare ones say more than "help".
    val topics = titleKeywords(post.title).distinct().sortedByDescending { m.docFreq.idf(it) }.take(2)

    Overlays.launch { dismiss ->
        OverlaySheet<() -> Unit>(done = { after -> dismiss(); after?.invoke() }) { close ->
            val haptics = LocalHapticFeedback.current
            LaunchedEffect(Unit) { haptics.performHapticFeedback(HapticFeedbackType.LongPress) }
            val cs = MaterialTheme.colorScheme
            val explicit by m.explicit.state.collectAsStateWithLifecycle()
            val mutedSet by m.muted.state.collectAsStateWithLifecycle()
            val metaMap by m.meta.collectAsStateWithLifecycle()
            val learner = m.learner
            val sub = post.subreddit
            val subPref = explicit.subs[sub.lowercase()] ?: 0
            val muted = sub.lowercase() in mutedSet
            val why = metaMap[post.id]?.why

            @Composable
            fun PrefTile(label: String, icon: ImageVector, on: Boolean, f: () -> Unit) = ListItem(
                modifier = Modifier.clickable(onClick = f),
                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                leadingContent = { Icon(icon, null, tint = if (on) cs.primary else cs.onSurfaceVariant) },
                headlineContent = { Text(label) },
                trailingContent = if (on) ({ Icon(Icons.Rounded.Check, null, tint = cs.primary) }) else null,
            )

            Row(Modifier.padding(start = 20.dp, top = 4.dp, end = 20.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.AutoAwesome, null, Modifier.size(18.dp), tint = cs.primary)
                Spacer(Modifier.width(8.dp))
                Text("Tune For You", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
            }
            if (!why.isNullOrEmpty()) {
                var open by remember { mutableStateOf(false) }
                val turn by animateFloatAsState(if (open) 180f else 0f, label = "chevron")
                ListItem(
                    modifier = Modifier.clickable { open = !open },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    leadingContent = { Icon(Icons.AutoMirrored.Rounded.HelpOutline, null) },
                    headlineContent = { Text("Why am I seeing this?") },
                    trailingContent = { Icon(Icons.Rounded.ExpandMore, null, Modifier.rotate(turn)) },
                )
                AnimatedVisibility(open) {
                    Column(Modifier.padding(start = 56.dp, end = 16.dp, bottom = 8.dp)) {
                        for (line in why) {
                            Text("• $line", color = cs.onSurfaceVariant, modifier = Modifier.padding(bottom = 4.dp))
                        }
                    }
                }
            }
            PrefTile("More from r/$sub", Icons.Outlined.ThumbUp, subPref > 0) {
                close {
                    learner.subPreference(post, if (subPref > 0) 0 else 1)
                    toast(if (subPref > 0) "Cleared" else "We'll show more from r/$sub")
                }
            }
            PrefTile("Less from r/$sub", Icons.Outlined.ThumbDown, subPref < 0) {
                close {
                    learner.subPreference(post, if (subPref < 0) 0 else -1)
                    toast(if (subPref < 0) "Cleared" else "We'll show less from r/$sub")
                }
            }
            for (t in topics) {
                ListItem(
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    leadingContent = { Icon(Icons.Rounded.Tag, null) },
                    headlineContent = { Text("“$t”") },
                    supportingContent = { Text("This topic, in any community") },
                    trailingContent = {
                        Row {
                            for ((v, icon) in listOf(1 to Icons.Outlined.ThumbUp, -1 to Icons.Outlined.ThumbDown)) {
                                val on = explicit.topics[t] == v
                                IconButton(
                                    onClick = {
                                        close {
                                            learner.topicPreference(t, if (on) 0 else v)
                                            toast(
                                                if (on) "Cleared"
                                                else "We'll show ${if (v > 0) "more" else "less"} about “$t”",
                                            )
                                        }
                                    },
                                    colors = IconButtonDefaults.iconButtonColors(
                                        contentColor = if (on) cs.primary else cs.onSurfaceVariant,
                                    ),
                                ) {
                                    Icon(icon, contentDescription = "${if (v > 0) "More about" else "Less about"} “$t”")
                                }
                            }
                        }
                    },
                )
            }
            ListItem(
                modifier = Modifier.clickable {
                    close {
                        m.muted.toggle(sub)
                        toast(if (muted) "r/$sub unmuted" else "r/$sub muted from For You")
                    }
                },
                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                leadingContent = {
                    Icon(if (muted) Icons.AutoMirrored.Rounded.VolumeUp else Icons.AutoMirrored.Rounded.VolumeOff, null)
                },
                headlineContent = { Text(if (muted) "Unmute r/$sub" else "Mute r/$sub in For You") },
            )
        }
    }
}
