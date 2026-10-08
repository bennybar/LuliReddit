package com.bennybar.luli_for_reddit.feature.compose

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.core.arr
import com.bennybar.luli_for_reddit.core.get
import com.bennybar.luli_for_reddit.core.net.Http
import com.bennybar.luli_for_reddit.core.net.await
import com.bennybar.luli_for_reddit.core.str
import com.bennybar.luli_for_reddit.ui.Overlays
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.Request

private data class Gif(val preview: String, val full: String)

/**
 * Giphy search sheet (uses the stored Giphy key, entered at login). Returns
 * the chosen GIF URL or null.
 */
suspend fun showGiphyPicker(): String? {
    val key = app.secureStore.giphyKey()
    if (key.isNullOrEmpty()) {
        app.navigator.showSnackbar("Add a Giphy API key (login screen) to use the GIF picker.")
        return null
    }
    return Overlays.show<String> { done -> GiphySheet(key, done) }
}

private suspend fun loadGifs(apiKey: String, q: String?): List<Gif> {
    val base = if (q.isNullOrEmpty()) "https://api.giphy.com/v1/gifs/trending" else "https://api.giphy.com/v1/gifs/search"
    val url = base.toHttpUrl().newBuilder()
        .addQueryParameter("api_key", apiKey)
        .apply { if (!q.isNullOrEmpty()) addQueryParameter("q", q) }
        .addQueryParameter("limit", "24")
        .addQueryParameter("rating", "pg-13")
        .build()
    val body = Http.client.await(Request.Builder().url(url).build()).use { withContext(Dispatchers.IO) { it.body.string() } }
    return withContext(Dispatchers.Default) {
        (AppJson.parseToJsonElement(body)["data"].arr() ?: emptyList()).mapNotNull { g ->
            val preview = g["images"]["fixed_width"]["url"].str() ?: return@mapNotNull null
            val full = g["images"]["original"]["url"].str() ?: return@mapNotNull null
            Gif(preview, full)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun GiphySheet(apiKey: String, done: (String?) -> Unit) {
    val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var query by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<Gif>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    var job by remember { mutableStateOf<Job?>(null) }
    val focus = remember { FocusRequester() }

    fun load(q: String?) {
        job?.cancel()
        loading = true
        job = scope.launch {
            results = runCatching { loadGifs(apiKey, q) }.getOrDefault(results)
            loading = false
        }
    }
    LaunchedEffect(Unit) {
        load(null) // trending
        runCatching { focus.requestFocus() }
    }

    val height = LocalConfiguration.current.screenHeightDp.dp * 0.6f
    ModalBottomSheet(onDismissRequest = { done(null) }, sheetState = sheet) {
        Column(Modifier.padding(horizontal = 12.dp).padding(bottom = 12.dp).imePadding().height(height)) {
            TextField(
                value = query,
                onValueChange = { query = it },
                modifier = Modifier.fillMaxWidth().focusRequester(focus),
                placeholder = { Text("Search GIFs") },
                leadingIcon = { Icon(Icons.Rounded.Search, null) },
                singleLine = true,
                shape = RoundedCornerShape(18.dp),
                colors = TextFieldDefaults.colors(
                    focusedIndicatorColor = androidx.compose.ui.graphics.Color.Transparent,
                    unfocusedIndicatorColor = androidx.compose.ui.graphics.Color.Transparent,
                ),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                keyboardActions = KeyboardActions(onSearch = { load(query.trim()) }),
            )
            Spacer(Modifier.height(8.dp))
            Box(Modifier.weight(1f).fillMaxWidth()) {
                if (loading) {
                    CircularProgressIndicator(Modifier.align(Alignment.Center))
                } else {
                    LazyVerticalGrid(
                        columns = GridCells.Fixed(3),
                        modifier = Modifier.fillMaxSize(),
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        items(results, key = { it.full }) { g ->
                            AsyncImage(
                                model = g.preview,
                                contentDescription = null,
                                contentScale = ContentScale.Crop,
                                modifier = Modifier
                                    .aspectRatio(1f)
                                    .clip(RoundedCornerShape(10.dp))
                                    .clickable { scope.launch { sheet.hide() }.invokeOnCompletion { done(g.full) } },
                            )
                        }
                    }
                }
            }
            Text(
                "Powered by GIPHY",
                style = MaterialTheme.typography.labelSmall,
                modifier = Modifier.align(Alignment.End).padding(top = 4.dp),
            )
        }
    }
}
