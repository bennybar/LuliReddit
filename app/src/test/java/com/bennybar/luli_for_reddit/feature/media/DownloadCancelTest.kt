package com.bennybar.luli_for_reddit.feature.media

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.net.ServerSocket
import kotlin.concurrent.thread

class DownloadCancelTest {
    @Test
    fun `cancel stops a download blocked on a silent server`() = runBlocking {
        // A server that accepts the connection and never answers.
        val server = ServerSocket(0)
        val held = mutableListOf<java.net.Socket>()
        thread(isDaemon = true) { runCatching { while (true) held += server.accept() } }
        val dest = File.createTempFile("ilay-dl", ".bin").apply { deleteOnExit() }
        try {
            val job = async(Dispatchers.IO) { downloadTo("http://127.0.0.1:${server.localPort}/x", dest) { _, _ -> } }
            delay(300) // well into the blocked execute()
            val started = System.currentTimeMillis()
            job.cancel()
            withTimeout(2_000) { job.join() } // used to wait for the server (or the 90 s read timeout)
            assertTrue(job.isCancelled)
            assertTrue(System.currentTimeMillis() - started < 2_000)
        } finally {
            held.forEach { runCatching { it.close() } }
            server.close()
        }
    }
}
