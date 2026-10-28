package com.bennybar.luli_for_reddit

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bennybar.luli_for_reddit.core.redditUrlInText
import com.bennybar.luli_for_reddit.feature.post.SharedSummarySheet
import com.bennybar.luli_for_reddit.ui.theme.IlayTheme

/**
 * "Summarize with Ilay" in the share sheet: the summary sheet over the app the
 * post was shared from, without opening Ilay (a see-through window).
 */
class SummarizeActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.auto(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.auto(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT),
        )
        val link = redditUrlInText(intent.getStringExtra(Intent.EXTRA_TEXT))
        setContent {
            val settings by app.settings.state.collectAsStateWithLifecycle()
            IlayTheme(settings) {
                SharedSummarySheet(
                    link,
                    onOpen = { post ->
                        startActivity(
                            Intent(Intent.ACTION_VIEW, Uri.parse("https://www.reddit.com${post.permalink}"), this, IlayActivity::class.java),
                        )
                        finish()
                    },
                    done = ::finish,
                )
            }
        }
    }
}
