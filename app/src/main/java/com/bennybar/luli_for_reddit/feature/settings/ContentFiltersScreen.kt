package com.bennybar.luli_for_reddit.feature.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.outlined.SmartToy
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.NoAdultContent
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.InputChip
import androidx.compose.material3.InputChipDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.nav.LocalNavigator

/**
 * Manage content filters: keywords (title), domains, subreddits and flairs
 * that hide matching posts across all feeds.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ContentFiltersScreen() {
    val nav = LocalNavigator.current
    val store = app.contentFilters
    val filters by store.state.collectAsStateWithLifecycle()
    val cs = MaterialTheme.colorScheme

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Content filters") },
                navigationIcon = {
                    IconButton(onClick = { nav.pop() }) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") }
                },
            )
        },
    ) { padding ->
        LazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(top = padding.calculateTopPadding(), bottom = padding.calculateBottomPadding() + 24.dp),
        ) {
            item("intro") {
                Text(
                    "Hide posts that match these. Filters are stored only on this device and apply to every feed.",
                    fontSize = 12.sp,
                    color = cs.onSurfaceVariant,
                    modifier = Modifier.padding(start = 16.dp, top = 12.dp, end = 16.dp, bottom = 4.dp),
                )
            }
            item("keyword") { FilterSection("Title keywords", "e.g. spoiler", "keyword", filters.keywords) }
            item("domain") { FilterSection("Domains", "e.g. twitter.com", "domain", filters.domains) }
            item("subreddit") { FilterSection("Subreddits", "e.g. politics", "subreddit", filters.subreddits) }
            item("subNote") {
                Text(
                    "Hidden from the frontpage, For You, Popular and custom feeds. Its own page still shows it.",
                    fontSize = 12.sp,
                    color = cs.onSurfaceVariant,
                    modifier = Modifier.padding(start = 16.dp, top = 2.dp, end = 16.dp),
                )
            }
            item("flair") { FilterSection("Flairs", "e.g. Politics", "flair", filters.flairs) }
            item("gap") { Spacer(Modifier.height(12.dp)) }
            item("nsfw") {
                SwitchTile(
                    "Hide NSFW posts", "Remove them from feeds instead of blurring", Icons.Rounded.NoAdultContent,
                    filters.hideNsfw, onChange = store::setHideNsfw,
                )
            }
            item("automod") {
                SwitchTile(
                    "Collapse AutoModerator", "Start AutoModerator comments collapsed", Icons.Outlined.SmartToy,
                    filters.collapseAutoMod, onChange = store::setCollapseAutoMod,
                )
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FilterSection(title: String, hint: String, type: String, values: List<String>) {
    val cs = MaterialTheme.colorScheme
    var text by rememberSaveable(type) { mutableStateOf("") }
    fun add() {
        app.contentFilters.add(type, text)
        text = ""
    }
    Column {
        Text(
            title,
            style = MaterialTheme.typography.titleSmall,
            color = cs.primary,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(start = 16.dp, top = 18.dp, end = 16.dp, bottom = 4.dp),
        )
        Row(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            TextField(
                value = text,
                onValueChange = { text = it },
                singleLine = true,
                placeholder = { Text(hint) },
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { add() }),
                shape = RoundedCornerShape(18.dp),
                colors = TextFieldDefaults.colors(
                    focusedIndicatorColor = Color.Transparent,
                    unfocusedIndicatorColor = Color.Transparent,
                ),
                modifier = Modifier.weight(1f),
            )
            Spacer(Modifier.width(8.dp))
            Button(onClick = ::add) { Text("Add") }
        }
        if (values.isNotEmpty()) {
            FlowRow(
                Modifier.padding(start = 16.dp, top = 4.dp, end = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                for (v in values) {
                    InputChip(
                        selected = false,
                        onClick = {}, // only the X removes (as Flutter's deletable chip)
                        label = { Text(v) },
                        trailingIcon = {
                            Icon(
                                Icons.Rounded.Close, "Remove",
                                Modifier.size(InputChipDefaults.IconSize).clickable { app.contentFilters.remove(type, v) },
                            )
                        },
                    )
                }
            }
        }
    }
}
