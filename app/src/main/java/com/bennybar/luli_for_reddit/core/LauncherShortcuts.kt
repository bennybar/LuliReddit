package com.bennybar.luli_for_reddit.core

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import coil3.SingletonImageLoader
import coil3.request.ImageRequest
import coil3.request.SuccessResult
import coil3.request.allowHardware
import coil3.request.transformations
import coil3.toBitmap
import coil3.transform.CircleCropTransformation
import com.bennybar.luli_for_reddit.IlayActivity
import com.bennybar.luli_for_reddit.R
import com.bennybar.luli_for_reddit.state.RecentSubreddit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/**
 * The launcher's long-press menu (#317): Home, then the subreddits you open
 * most. Rebuilt only when that list changes.
 */
object LauncherShortcuts {
    /** IlayActivity's intent for the Home shortcut. */
    const val ACTION_HOME = "com.bennybar.luli_for_reddit.SHORTCUT_HOME"
    private const val SUBREDDITS = 3 // with Home, the 4 a launcher shows

    fun start(context: Context, scope: CoroutineScope, mostVisited: Flow<List<RecentSubreddit>>) {
        scope.launch {
            mostVisited.map { list -> list.take(SUBREDDITS).map { it.name to it.iconUrl } }
                .distinctUntilChanged()
                .collectLatest { publish(context, it) }
        }
    }

    private suspend fun publish(context: Context, subs: List<Pair<String, String?>>) {
        val activity = ComponentName(context, IlayActivity::class.java)
        val home = ShortcutInfoCompat.Builder(context, "home")
            .setShortLabel("Home")
            .setIcon(IconCompat.createWithResource(context, R.drawable.ic_shortcut_home))
            .setIntent(Intent(ACTION_HOME).setComponent(activity))
            .setRank(0)
            .build()
        val shortcuts = listOf(home) + subs.mapIndexed { i, (name, icon) ->
            ShortcutInfoCompat.Builder(context, "r/${name.lowercase()}")
                .setShortLabel(name)
                .setLongLabel("r/$name")
                .setIcon(icon?.let { iconBitmap(context, it) }?.let(IconCompat::createWithBitmap)
                    ?: IconCompat.createWithResource(context, R.drawable.ic_shortcut_subreddit))
                .setIntent(Intent(Intent.ACTION_VIEW, Uri.parse("https://www.reddit.com/r/$name")).setComponent(activity))
                .setRank(i + 1)
                .build()
        }
        runCatching { ShortcutManagerCompat.setDynamicShortcuts(context, shortcuts) }
    }

    /** The community's picture, round, from Coil's cache when it's there. */
    private suspend fun iconBitmap(context: Context, url: String): Bitmap? = runCatching {
        val request = ImageRequest.Builder(context).data(url).size(192).allowHardware(false)
            .transformations(CircleCropTransformation()).build()
        (SingletonImageLoader.get(context).execute(request) as? SuccessResult)?.image?.toBitmap()
    }.getOrNull()
}
