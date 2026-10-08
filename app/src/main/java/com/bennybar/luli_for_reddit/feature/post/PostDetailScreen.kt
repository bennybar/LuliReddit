package com.bennybar.luli_for_reddit.feature.post

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier

/** [Agent B] A post + threaded comments. The already-loaded Post, if any, is in NavCache under postId. */
@Composable
fun PostDetailScreen(subreddit: String, postId: String, focusCommentId: String?) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text("PostDetailScreen (todo)") }
}
