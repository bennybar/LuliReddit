package com.bennybar.luli_for_reddit.ui

import kotlinx.coroutines.flow.distinctUntilChanged
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.LoadingIndicator
import androidx.compose.material3.LoadingIndicatorDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.pulltorefresh.PullToRefreshDefaults
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color

/**
 * Material 3 Expressive's loading indicator (morphing shapes), in place of
 * the plain spinner. Inside a button, pass `LocalContentColor.current`: the
 * default primary colour vanishes on a filled or disabled button.
 */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun Loading(modifier: Modifier = Modifier, color: Color = LoadingIndicatorDefaults.indicatorColor) {
    LoadingIndicator(modifier, color = color)
}

/**
 * A pull to refresh's indicator is out under the finger: pushing back up should put it
 * away before the header above it folds and the list scrolls (#235).
 */
object PullToRefreshActivity {
    var pulling by mutableStateOf(false)
        internal set
}

/** Pull to refresh with the Expressive loading indicator (on its tonal container). */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun RefreshBox(isRefreshing: Boolean, onRefresh: () -> Unit, modifier: Modifier = Modifier, indicatorPadding: Dp = 0.dp, content: @Composable BoxScope.() -> Unit) {
    val state = rememberPullToRefreshState()
    // Out (being pulled): the Expandable header leaves the scroll to it (#235).
    LaunchedEffect(state) {
        snapshotFlow { state.distanceFraction > 0f }.distinctUntilChanged().collect { PullToRefreshActivity.pulling = it }
    }
    PullToRefreshBox(
        isRefreshing = isRefreshing,
        onRefresh = onRefresh,
        modifier = modifier,
        state = state,
        indicator = {
            PullToRefreshDefaults.LoadingIndicator(state = state, isRefreshing = isRefreshing, modifier = Modifier.align(Alignment.TopCenter).padding(top = indicatorPadding))
        },
        content = content,
    )
}
