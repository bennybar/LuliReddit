package com.bennybar.luli_for_reddit.core.net

import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.Callback
import okhttp3.ConnectionPool
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resumeWithException

/**
 * The one shared OkHttp client (connection pool, HTTP/2, dispatcher) for
 * Reddit, images (Coil) and video (Media3), so every request reuses warm
 * connections. Derive per-use clients with `newBuilder()`.
 */
object Http {
    val client: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(60, TimeUnit.SECONDS)
            // The OS silently drops idle keep-alive sockets while the app is
            // backgrounded; OkHttp retries a dead pooled connection itself, and
            // a short keep-alive retires them before they go stale.
            .connectionPool(ConnectionPool(10, 60, TimeUnit.SECONDS))
            .retryOnConnectionFailure(true)
            .build()
            .also { it.dispatcher.maxRequestsPerHost = 16 }
    }
}

/** Suspends on an OkHttp call, cancelling it with the coroutine. */
suspend fun OkHttpClient.await(request: Request): Response = suspendCancellableCoroutine { cont ->
    val call = newCall(request)
    cont.invokeOnCancellation { call.cancel() }
    call.enqueue(object : Callback {
        override fun onFailure(call: Call, e: IOException) {
            if (cont.isActive) cont.resumeWithException(e)
        }

        override fun onResponse(call: Call, response: Response) {
            cont.resume(response) { _, _, _ -> response.close() }
        }
    })
}
