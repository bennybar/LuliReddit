package com.bennybar.luli_for_reddit.feature.digest

import android.content.Context
import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.core.arr
import com.bennybar.luli_for_reddit.core.double
import com.bennybar.luli_for_reddit.core.get
import com.bennybar.luli_for_reddit.core.long
import com.bennybar.luli_for_reddit.core.obj
import com.bennybar.luli_for_reddit.core.str
import com.bennybar.luli_for_reddit.model.Post
import com.bennybar.luli_for_reddit.state.UserScoped
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import java.io.File

/**
 * The last [KEEP] days' digests, per account, on this device only: each day's posts
 * (as Reddit sent them, so they show without asking again) and everything judged that
 * day (so a refresh only judges what's new). One file per account, the same format on
 * both apps.
 */
class DigestStore(private val context: Context, private val raw: (String) -> JsonElement?) : UserScoped {
    // One writer at a time, in order.
    private val io = CoroutineScope(SupervisorJob() + Dispatchers.IO.limitedParallelism(1))
    private var file = fileFor("")
    private val _days = MutableStateFlow<List<DigestDay>>(emptyList())

    /** Newest first. */
    val days: StateFlow<List<DigestDay>> = _days

    /** Raw post JSON by id, for posts loaded from the file (the repository only keeps recent ones). */
    private val rawCache = HashMap<String, JsonElement>()

    fun today(day: String): DigestDay? = _days.value.firstOrNull { it.day == day }

    /** Saves [d], replacing its day; keeps the newest [KEEP]. */
    fun put(d: DigestDay) {
        _days.value = (listOf(d) + _days.value.filter { it.day != d.day }).sortedByDescending { it.day }.take(KEEP)
        save()
    }

    fun markSeen(day: String, at: Long) {
        val d = today(day) ?: return
        if (d.seenAt >= at) return
        put(d.copy(seenAt = at))
    }

    override fun onUserChanged(username: String) {
        file = fileFor(username)
        _days.value = emptyList()
        val f = file
        io.launch {
            val list = runCatching { if (f.exists()) decode(AppJson.parseToJsonElement(f.readText())) else emptyList() }.getOrDefault(emptyList())
            if (file == f) _days.value = list
        }
    }

    private fun save() {
        val f = file
        val json = encode(_days.value)
        io.launch {
            runCatching {
                // A temp file swapped in, so a crash mid-write can't truncate it.
                val tmp = File(f.parentFile, f.name + ".tmp")
                tmp.writeText(json)
                if (!tmp.renameTo(f)) { f.delete(); tmp.renameTo(f) }
            }
        }
    }

    private fun fileFor(user: String) = File(context.filesDir, "digest_${user.lowercase()}.json")

    private fun encode(days: List<DigestDay>): String = buildJsonObject {
        putJsonArray("days") {
            for (d in days) add(buildJsonObject {
                put("day", d.day)
                put("built", d.builtAt)
                put("refreshed", d.refreshedAt)
                put("seen", d.seenAt)
                putJsonArray("items") {
                    for (it in d.items) {
                        val r = synchronized(rawCache) { rawCache[it.post.id] } ?: raw(it.post.id)?.also { r -> synchronized(rawCache) { rawCache[it.post.id] = r } } ?: continue
                        add(buildJsonObject {
                            put("raw", r)
                            put("why", it.why)
                            put("n", it.notability)
                            put("at", it.addedAt)
                        })
                    }
                }
                putJsonObject("judged") {
                    for ((id, j) in d.judged) {
                        put(id, JsonArray(listOf(JsonPrimitive(if (j.picked) 1 else 0), JsonPrimitive(j.notability), JsonPrimitive(j.at), JsonPrimitive(if (j.secondLook) 1 else 0))))
                    }
                }
            })
        }
    }.toString()

    private fun decode(json: JsonElement): List<DigestDay> = json["days"].arr().orEmpty().mapNotNull { d ->
        val day = d["day"].str() ?: return@mapNotNull null
        DigestDay(
            day = day,
            builtAt = d["built"].long() ?: 0,
            refreshedAt = d["refreshed"].long() ?: 0,
            seenAt = d["seen"].long() ?: 0,
            items = d["items"].arr().orEmpty().mapNotNull { i ->
                val r = i["raw"] ?: return@mapNotNull null
                val post = runCatching { Post.fromData(r) }.getOrNull() ?: return@mapNotNull null
                synchronized(rawCache) { rawCache[post.id] = r }
                DigestItem(post, i["why"].str().orEmpty(), i["n"].double() ?: 0.0, i["at"].long() ?: 0)
            },
            judged = d["judged"].obj().orEmpty().mapNotNull { (id, v) ->
                val a = v.arr() ?: return@mapNotNull null
                if (a.size < 3) return@mapNotNull null
                id to Judged(
                    picked = a[0].long() == 1L,
                    notability = a[1].double() ?: 0.0,
                    at = a[2].long() ?: 0,
                    secondLook = a.getOrNull(3).long() == 1L,
                )
            }.toMap(),
        )
    }

    companion object {
        const val KEEP = 7
    }
}
