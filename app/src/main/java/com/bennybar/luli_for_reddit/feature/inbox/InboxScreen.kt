package com.bennybar.luli_for_reddit.feature.inbox

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier

/** [Agent D] The Inbox tab. [reselect] bumps when the tab is re-tapped (scroll to top). */
@Composable
fun InboxScreen(reselect: Int) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text("InboxScreen (todo)") }
}
