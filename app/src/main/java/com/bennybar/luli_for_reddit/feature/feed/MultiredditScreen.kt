package com.bennybar.luli_for_reddit.feature.feed

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.nav.Route

/** A custom feed (multireddit): its posts, with a shortcut to manage it. */
@Composable
fun MultiredditScreen(username: String, name: String) {
    val nav = LocalNavigator.current
    Scaffold(
        topBar = {
            BloomTopBar(
                name,
                actions = {
                    IconButton(onClick = { nav.push(Route.ManageMultireddit(username, name)) }) {
                        Icon(Icons.Rounded.Tune, "Manage")
                    }
                },
            )
        },
        containerColor = MaterialTheme.colorScheme.surface,
    ) { padding ->
        PostListView(
            feedKey = "m::$username::$name",
            modifier = Modifier.padding(top = padding.calculateTopPadding()),
            header = {
                Text(
                    name,
                    Modifier.fillMaxWidth().padding(start = 16.dp, top = 12.dp, end = 16.dp),
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.ExtraBold,
                )
            },
        )
    }
}
