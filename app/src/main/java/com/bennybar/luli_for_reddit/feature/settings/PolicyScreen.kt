package com.bennybar.luli_for_reddit.feature.settings

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import com.bennybar.luli_for_reddit.nav.LocalNavigator

/**
 * In-app content & conduct policy (EULA). Required for app-store distribution
 * of an app that surfaces user-generated content.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun PolicyScreen() {
    val nav = LocalNavigator.current
    val context = LocalContext.current
    val cs = MaterialTheme.colorScheme
    fun open(url: String) {
        runCatching {
            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }

    @Composable
    fun H(t: String) = Text(
        t,
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.Bold,
        color = cs.primary,
        modifier = Modifier.padding(top = 18.dp, bottom = 6.dp),
    )

    @Composable
    fun P(t: String) = Text(
        t,
        style = MaterialTheme.typography.bodyMedium.copy(lineHeight = 1.45.em),
        modifier = Modifier.padding(bottom = 8.dp),
    )

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Content & conduct policy") },
                navigationIcon = {
                    IconButton(onClick = { nav.pop() }) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") }
                },
            )
        },
    ) { padding ->
        LazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                start = 16.dp, end = 16.dp,
                top = padding.calculateTopPadding() + 8.dp,
                bottom = padding.calculateBottomPadding() + 32.dp,
            ),
        ) {
            item {
                P(
                    "Ilay is an independent, third-party client for Reddit. It is not made by, endorsed by, or " +
                        "affiliated with Reddit, Inc. All content is hosted by Reddit and provided through your own " +
                        "Reddit account.",
                )
                H("No tolerance for objectionable content")
                P(
                    "By using Ilay you agree not to use it to post, share, or promote content that is illegal, " +
                        "abusive, harassing, hateful, sexually exploitative, or otherwise objectionable. There is " +
                        "zero tolerance for objectionable content or abusive users.",
                )
                H("Reporting and moderation")
                P(
                    "You can report any post or comment from its menu, block users so you no longer see their " +
                        "content or messages, and hide posts. Reports are sent to Reddit and the relevant subreddit " +
                        "moderators, who review and act on them. Where you moderate, you can remove content directly.",
                )
                H("Reddit rules apply")
                P(
                    "All activity is also governed by Reddit's Content Policy and User Agreement. Violations may be " +
                        "actioned by Reddit independently of this app.",
                )
                FlowRow(Modifier.padding(bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    TextButton(onClick = { open("https://www.redditinc.com/policies/content-policy") }) {
                        Text("Reddit Content Policy")
                    }
                    TextButton(onClick = { open("https://www.redditinc.com/policies/user-agreement") }) {
                        Text("Reddit User Agreement")
                    }
                }
                H("Adult content")
                P(
                    "Mature (NSFW) content is off by default and blurred until revealed. By enabling it you confirm " +
                        "you are of legal age to view such content in your jurisdiction.",
                )
                H("Your data")
                P(
                    "Ilay stores your API credentials, tokens, history, and settings only on this device, and talks " +
                        "directly to Reddit. The only other data it sends is anonymous usage analytics (Aptabase): " +
                        "app launches, app version, and OS — no account info, no ad identifiers, nothing that " +
                        "identifies you. To remove your data, use \"Clear all data\" in settings; to delete your " +
                        "Reddit account, visit Reddit's settings.",
                )
                H("AI summaries (optional)")
                P(
                    "If you add your own OpenAI-compatible API key, the \"Summarize thread\" feature sends the post " +
                        "and top comments to the AI endpoint you configure (OpenAI by default, or your own URL). This " +
                        "is the only feature that sends content off-device, it is entirely opt-in, and your key is " +
                        "stored securely and never included in backups. Summaries are generated by a third-party " +
                        "model and may be inaccurate.",
                )
                H("No warranty")
                P("Ilay is provided \"as is\", without warranty of any kind. You use it at your own risk.")
            }
        }
    }
}
