package com.bennybar.luli_for_reddit

import android.app.Application
import coil3.ImageLoader
import coil3.SingletonImageLoader
import coil3.disk.DiskCache
import coil3.disk.directory
import coil3.gif.AnimatedImageDecoder
import coil3.memory.MemoryCache
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import coil3.request.crossfade
import coil3.video.VideoFrameDecoder
import com.bennybar.luli_for_reddit.core.Analytics
import com.bennybar.luli_for_reddit.core.net.Http
import com.bennybar.luli_for_reddit.core.storage.FlutterMigration
import kotlinx.coroutines.launch

class IlayApp : Application(), SingletonImageLoader.Factory {
    override fun onCreate() {
        super.onCreate()
        appInstance = AppContainer(this)
        // First launch after updating from the Flutter build: import its prefs
        // before anything reads settings.
        FlutterMigration.runIfNeeded(this, app.prefs)
        app.settings.reload()
        app.start()
        app.session.reload()

        Analytics.init(this)
        app.scope.launch {
            // Anonymous: which login method this install uses.
            val username = app.secureStore.username()
            val method = when {
                username.isNullOrEmpty() -> "logged_out"
                app.secureStore.authMode() == "web" -> "website"
                else -> "api"
            }
            Analytics.track("app_started", mapOf("login_method" to method))
        }
        // Background inbox notifications (opt-in).
        app.inbox.onAppStart()
    }

    /** One image pipeline: shared OkHttp pool, big memory + disk caches, GIF + video frames. */
    override fun newImageLoader(context: android.content.Context): ImageLoader =
        ImageLoader.Builder(context)
            .components {
                add(OkHttpNetworkFetcherFactory(callFactory = { Http.client }))
                add(AnimatedImageDecoder.Factory())
                add(VideoFrameDecoder.Factory())
            }
            .memoryCache { MemoryCache.Builder().maxSizePercent(context, 0.25).build() }
            .diskCache {
                DiskCache.Builder().directory(context.cacheDir.resolve("image_cache")).maxSizeBytes(512L * 1024 * 1024).build()
            }
            .crossfade(true)
            .build()
}
