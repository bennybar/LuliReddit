package com.bennybar.luli_for_reddit.feature.foryou

import androidx.compose.runtime.Immutable
import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.core.double
import com.bennybar.luli_for_reddit.core.long
import com.bennybar.luli_for_reddit.core.storage.Prefs
import com.bennybar.luli_for_reddit.state.userScopedKey
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import java.time.LocalDate
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.ln

// The on-device For You model. All local and per account: every store keys
// its prefs entry with `userScopedKey` and reloads in [load] when the account
// changes. JSON formats are identical to the Flutter build's, so migrated
// data and backups carry over.

private fun readJson(prefs: Prefs, key: String): JsonObject {
    val raw = prefs.getString(key) ?: return JsonObject(emptyMap())
    return runCatching { AppJson.parseToJsonElement(raw).jsonObject }.getOrDefault(JsonObject(emptyMap()))
}

private fun num(e: JsonElement?): Double = e.double() ?: throw IllegalArgumentException("not a number")

private fun doublesObject(m: Map<String, Double>, extra: JsonObjectBuilderBlock = {}): String =
    buildJsonObject {
        for ((k, v) in m) put(k, v)
        extra()
    }.toString()

private typealias JsonObjectBuilderBlock = kotlinx.serialization.json.JsonObjectBuilder.() -> Unit

/**
 * On-device interest model: a per-subreddit affinity score that learns from
 * the user's own actions (upvote / downvote / save / open / comment / share).
 * Entirely local — it never leaves the device and powers "For You (Beta)".
 * Weights decay daily so the feed tracks your *current* taste.
 */
class InterestStore(private val prefs: Prefs, private val trackHistory: () -> Boolean) {
    private var key = BASE
    private var ts: Long? = null // when the weights were last decayed + saved
    private val _state = MutableStateFlow<Map<String, Double>>(emptyMap())
    val state: StateFlow<Map<String, Double>> = _state
    val value: Map<String, Double> get() = _state.value

    @Synchronized
    fun load(username: String) {
        key = userScopedKey(prefs, username, BASE)
        ts = null
        val raw = prefs.getString(key)
        _state.value = if (raw == null) emptyMap() else try {
            val m = AppJson.parseToJsonElement(raw).jsonObject
            ts = m["_ts"].long()
            val w = LinkedHashMap<String, Double>()
            for ((k, v) in m) if (!k.startsWith("_")) w[k] = num(v)
            decayed(w)
        } catch (_: Exception) {
            emptyMap()
        }
    }

    /**
     * Applies the decay owed since the last save. Done on every change, not
     * just at startup: an app left running for days used to save undecayed
     * weights with a fresh timestamp, losing that decay for good.
     */
    private fun decayed(w: Map<String, Double>): Map<String, Double> {
        val f = decayFactor(ts, DECAY_PER_DAY)
        if (f > 0.999) return w
        val out = LinkedHashMap<String, Double>()
        for ((k, v) in w) if (abs(v * f) >= 0.3) out[k] = v * f
        return out
    }

    fun weightFor(subreddit: String): Double = value[subreddit.lowercase()] ?: 0.0

    @Synchronized
    fun bump(subreddit: String, delta: Double) {
        if (subreddit.isEmpty() || delta == 0.0) return
        // Only learn when history/personalization tracking is enabled.
        if (!trackHistory()) return
        val k = subreddit.lowercase()
        val next = LinkedHashMap(decayed(value))
        next[k] = ((next[k] ?: 0.0) + delta).coerceIn(-8.0, 40.0)
        persist(next)
    }

    /** Seeds affinity from the user's own history (cold start); never lowers. */
    @Synchronized
    fun seed(deltas: Map<String, Double>) {
        if (deltas.isEmpty()) return
        val current = decayed(value)
        val next = LinkedHashMap(current)
        for ((k, d) in deltas) next[k] = ((current[k] ?: 0.0) + d).coerceIn(-8.0, 40.0)
        persist(next)
    }

    /** Top affinity subreddits above [min], strongest first. */
    fun top(n: Int, min: Double = 1.0): List<String> =
        value.entries.filter { it.value >= min }.sortedByDescending { it.value }.take(n).map { it.key }

    /**
     * Forgets the learned affinity for one subreddit (used by the "Manage For
     * You" screen to undo a "show less"/"show more"). Works regardless of the
     * track-history setting.
     */
    @Synchronized
    fun reset(subreddit: String) {
        val k = subreddit.lowercase()
        if (k !in value) return
        persist(LinkedHashMap(value).apply { remove(k) })
    }

    @Synchronized
    fun clear() {
        _state.value = emptyMap()
        prefs.remove(key)
    }

    private fun persist(m: Map<String, Double>) {
        val now = System.currentTimeMillis()
        ts = now
        _state.value = m
        prefs.setString(key, doublesObject(m) { put("_ts", now) })
    }

    companion object {
        private const val BASE = "interest_weights"
        private const val DECAY_PER_DAY = 0.95
    }
}

/** Subreddits the user muted from the "For You" feed (local only). */
class MutedSubsStore(private val prefs: Prefs) {
    private var key = BASE
    private val _state = MutableStateFlow<Set<String>>(emptySet())
    val state: StateFlow<Set<String>> = _state
    val value: Set<String> get() = _state.value

    fun load(username: String) {
        key = userScopedKey(prefs, username, BASE)
        _state.value = (prefs.getStringList(key) ?: emptyList()).toCollection(LinkedHashSet())
    }

    fun contains(sub: String): Boolean = sub.lowercase() in value

    fun toggle(sub: String) {
        val k = sub.lowercase()
        val next = LinkedHashSet(value)
        if (!next.remove(k)) next.add(k)
        _state.value = next
        prefs.setStringList(key, next.toList())
    }

    companion object {
        private const val BASE = "muted_subs"
    }
}

/**
 * Learns which title keywords you engage with (upvote/save → +, downvote →
 * −). Powers within-subreddit taste ("F1 but not NBA") and keyword-matched
 * discovery. Local-only; decays like the interest store.
 */
class KeywordStore(private val prefs: Prefs, private val trackHistory: () -> Boolean) {
    private var key = BASE
    private var ts: Long? = null

    // When each word was last reinforced (days since epoch), so a full store
    // evicts what's weak *and* stale — not the word that just arrived.
    private var lastUsed = LinkedHashMap<String, Long>()
    private val _state = MutableStateFlow<Map<String, Double>>(emptyMap())
    val state: StateFlow<Map<String, Double>> = _state
    val value: Map<String, Double> get() = _state.value

    private fun today(): Long = System.currentTimeMillis() / 86_400_000L

    @Synchronized
    fun load(username: String) {
        key = userScopedKey(prefs, username, BASE)
        ts = null
        lastUsed = LinkedHashMap()
        val raw = prefs.getString(key)
        _state.value = if (raw == null) emptyMap() else try {
            val m = AppJson.parseToJsonElement(raw).jsonObject
            ts = m["_ts"].long()
            (m["_lu"] as? JsonObject)?.forEach { (k, v) -> lastUsed[k] = num(v).toLong() }
            val w = LinkedHashMap<String, Double>()
            for ((k, v) in m) if (!k.startsWith("_")) w[k] = num(v)
            decayed(w)
        } catch (_: Exception) {
            emptyMap()
        }
    }

    private fun decayed(w: Map<String, Double>): LinkedHashMap<String, Double> {
        val f = decayFactor(ts, DECAY_PER_DAY)
        if (f > 0.999) return LinkedHashMap(w)
        val out = LinkedHashMap<String, Double>()
        for ((k, v) in w) if (abs(v * f) >= 0.2) out[k] = v * f
        return out
    }

    /** Learns from a post title. [delta] applies per keyword (+1 up, −1 down). */
    @Synchronized
    fun bumpTitle(title: String, delta: Double) {
        if (delta == 0.0) return
        if (!trackHistory()) return
        val words = titleKeywords(title)
        if (words.isEmpty()) return
        val next = decayed(value)
        val today = today()
        for (w in words) {
            next[w] = ((next[w] ?: 0.0) + delta).coerceIn(-10.0, 10.0)
            lastUsed[w] = today
        }
        evict(next, keep = words.toSet())
        persist(next)
    }

    /** Seeds weights for a batch of titles (cold start). */
    @Synchronized
    fun seedTitles(titles: Iterable<String>, delta: Double) {
        val next = decayed(value)
        val today = today()
        for (t in titles) {
            for (w in titleKeywords(t)) {
                next[w] = ((next[w] ?: 0.0) + delta).coerceIn(-10.0, 10.0)
                lastUsed[w] = today
            }
        }
        evict(next)
        persist(next)
    }

    // Bounded: drop the words with the least |weight| × recency.
    private fun evict(m: MutableMap<String, Double>, keep: Set<String> = emptySet()) {
        if (m.size <= CAP) return
        val today = today()
        fun score(e: Map.Entry<String, Double>) =
            abs(e.value) * exp(-(today - (lastUsed[e.key] ?: (today - 60))) / 30.0)
        val victims = m.entries.filter { it.key !in keep }.sortedBy { score(it) }
            .take(m.size - CAP).map { it.key }
        for (k in victims) {
            m.remove(k)
            lastUsed.remove(k)
        }
    }

    /**
     * Total affinity of a title against the learned keywords, each word
     * weighted by how distinctive it is ([idf], 1 = average).
     */
    fun scoreTitle(title: String, idf: ((String) -> Double)? = null): Double {
        val s = value
        if (s.isEmpty()) return 0.0
        var sum = 0.0
        for (w in titleKeywords(title)) sum += (s[w] ?: 0.0) * (idf?.invoke(w) ?: 1.0)
        return sum.coerceIn(-6.0, 8.0)
    }

    /**
     * The strongest learned keyword present in [title] (for explainability),
     * preferring distinctive words over generic ones like "help".
     */
    fun topKeywordIn(title: String, idf: ((String) -> Double)? = null): String? {
        val s = value
        var best: String? = null
        var bestW = 2.0 // only surface meaningful signals
        for (w in titleKeywords(title)) {
            val v = (s[w] ?: 0.0) * (idf?.invoke(w) ?: 1.0)
            if (v > bestW) {
                bestW = v
                best = w
            }
        }
        return best
    }

    /** Forgets one learned word (Manage For You → Topics → Reset). */
    @Synchronized
    fun reset(word: String) {
        if (word !in value) return
        lastUsed.remove(word)
        persist(LinkedHashMap(value).apply { remove(word) })
    }

    @Synchronized
    fun clear() {
        _state.value = emptyMap()
        lastUsed = LinkedHashMap()
        prefs.remove(key)
    }

    private fun persist(m: Map<String, Double>) {
        val now = System.currentTimeMillis()
        ts = now
        _state.value = m
        lastUsed.keys.retainAll(m.keys)
        prefs.setString(
            key,
            doublesObject(m) {
                put("_ts", now)
                put("_lu", buildJsonObject { for ((k, v) in lastUsed) put(k, v) })
            },
        )
    }

    companion object {
        private const val BASE = "keyword_weights"
        private const val CAP = 400
        private const val DECAY_PER_DAY = 0.97
    }
}

/**
 * Counts how many times each post was *seen* in the For You feed (≥60% on
 * screen for a second). The count fades — halving every 24h — so a post you
 * skimmed once isn't buried for good, and is counted at most once per app
 * session. Bounded (~600 ids), per-account, and only kept while history
 * tracking is on.
 */
class ImpressionStore(
    private val prefs: Prefs,
    private val trackHistory: () -> Boolean,
    private val scope: CoroutineScope,
) {
    private var key = BASE
    private val session = HashSet<String>() // ids already counted this app session
    private val pending = LinkedHashSet<String>()
    private var flushScheduled = false
    private val _state = MutableStateFlow<Map<String, Pair<Double, Long>>>(emptyMap())
    val state: StateFlow<Map<String, Pair<Double, Long>>> = _state

    @Synchronized
    fun load(username: String) {
        key = userScopedKey(prefs, username, BASE)
        val raw = prefs.getString(key)
        _state.value = if (raw == null) emptyMap() else try {
            val now = System.currentTimeMillis()
            val out = LinkedHashMap<String, Pair<Double, Long>>()
            for ((k, v) in AppJson.parseToJsonElement(raw).jsonObject) {
                out[k] = if (v is JsonArray) num(v[0]) to num(v[1]).toLong()
                else num(v) to now // legacy: plain count
            }
            out
        } catch (_: Exception) {
            emptyMap()
        }
    }

    /** How many times [postId] has been seen, faded (halves every 24h). */
    fun count(postId: String): Double {
        val v = _state.value[postId] ?: return 0.0
        return v.first * decayFactor(v.second, 0.5)
    }

    /** Records one impression (cheap: batched, once per session per post). */
    @Synchronized
    fun record(postId: String) {
        if (postId.isEmpty() || !session.add(postId)) return
        if (!trackHistory()) return
        pending.add(postId)
        if (flushScheduled) return
        flushScheduled = true
        scope.launch {
            delay(2000)
            flush()
        }
    }

    @Synchronized
    private fun flush() {
        flushScheduled = false
        if (pending.isEmpty()) return
        val now = System.currentTimeMillis()
        val next = LinkedHashMap(_state.value)
        for (id in pending) {
            val c = count(id)
            next.remove(id) // re-insert last: insertion order = recency
            next[id] = (c + 1) to now
        }
        pending.clear()
        while (next.size > CAP) next.remove(next.keys.first())
        _state.value = next
        prefs.setString(
            key,
            buildJsonObject {
                for ((k, v) in next) put(k, JsonArray(listOf(JsonPrimitive(v.first), JsonPrimitive(v.second))))
            }.toString(),
        )
    }

    @Synchronized
    fun clear() {
        _state.value = emptyMap()
        prefs.remove(key)
    }

    companion object {
        private const val BASE = "fy_impressions"
        private const val CAP = 600
    }
}

/**
 * "More / Less from r/x" and "More / Less about 'topic'": what the user
 * *asked* for, kept apart from learned behaviour. Doesn't fade, isn't wiped
 * by resetting a learned weight, and works with history tracking off —
 * explicit controls shouldn't depend on passive tracking.
 */
@Immutable
data class ExplicitPrefs(
    val subs: Map<String, Int> = emptyMap(), // lowercase subreddit → +1 / −1
    val topics: Map<String, Int> = emptyMap(), // keyword (titleKeywords form) → +1 / −1
) {
    val isEmpty: Boolean get() = subs.isEmpty() && topics.isEmpty()
}

class ExplicitPrefsStore(private val prefs: Prefs) {
    private var key = BASE
    private val _state = MutableStateFlow(ExplicitPrefs())
    val state: StateFlow<ExplicitPrefs> = _state
    val value: ExplicitPrefs get() = _state.value

    fun load(username: String) {
        key = userScopedKey(prefs, username, BASE)
        val m = readJson(prefs, key)
        _state.value = try {
            fun g(k: String): Map<String, Int> {
                val out = LinkedHashMap<String, Int>()
                (m[k] as? JsonObject)?.forEach { (kk, v) -> out[kk] = num(v).toInt() }
                return out
            }
            ExplicitPrefs(g("subs"), g("topics"))
        } catch (_: Exception) {
            ExplicitPrefs()
        }
    }

    private fun set(p: ExplicitPrefs) {
        _state.value = p
        prefs.setString(
            key,
            buildJsonObject {
                put("subs", buildJsonObject { for ((k, v) in p.subs) put(k, v) })
                put("topics", buildJsonObject { for ((k, v) in p.topics) put(k, v) })
            }.toString(),
        )
    }

    /** [v] +1 (more), −1 (less) or 0 (forget). */
    fun setSub(sub: String, v: Int) {
        val next = LinkedHashMap(value.subs).apply { remove(sub.lowercase()) }
        if (v != 0) next[sub.lowercase()] = v
        set(ExplicitPrefs(next, value.topics))
    }

    fun setTopic(topic: String, v: Int) {
        val next = LinkedHashMap(value.topics).apply { remove(topic) }
        if (v != 0) next[topic] = v
        set(ExplicitPrefs(value.subs, next))
    }

    fun clear() = set(ExplicitPrefs())

    companion object {
        private const val BASE = "fy_explicit"
    }
}

/**
 * How often each subreddit's posts were seen in For You vs engaged with
 * (opened, read 30s+, voted). Lets the ranker learn *rates*: a subreddit you
 * keep scrolling past fades on its own, and a niche one you always open
 * rises even with few impressions. Decays like the interest model.
 */
class SubStatsStore(private val prefs: Prefs, private val trackHistory: () -> Boolean) {
    private var key = BASE
    private var ts: Long? = null
    private val _state = MutableStateFlow<Map<String, Pair<Double, Double>>>(emptyMap())
    val state: StateFlow<Map<String, Pair<Double, Double>>> = _state
    val value: Map<String, Pair<Double, Double>> get() = _state.value

    @Synchronized
    fun load(username: String) {
        key = userScopedKey(prefs, username, BASE)
        val m = readJson(prefs, key)
        _state.value = try {
            ts = m["_ts"].long()
            val f = decayFactor(ts, DECAY_PER_DAY)
            val out = LinkedHashMap<String, Pair<Double, Double>>()
            for ((k, v) in m) {
                if (k.startsWith("_")) continue
                val a = v.jsonArray
                out[k] = num(a[0]) * f to num(a[1]) * f
            }
            out
        } catch (_: Exception) {
            ts = null
            emptyMap()
        }
    }

    @Synchronized
    private fun add(sub: String, impr: Double, eng: Double) {
        if (!trackHistory()) return
        val f = decayFactor(ts, DECAY_PER_DAY)
        val next = LinkedHashMap<String, Pair<Double, Double>>()
        for ((k, v) in value) if (v.first * f >= 0.05) next[k] = v.first * f to v.second * f
        val k = sub.lowercase()
        val cur = next.remove(k) ?: (0.0 to 0.0)
        next[k] = cur.first + impr to cur.second + eng
        while (next.size > CAP) next.remove(next.keys.first())
        val now = System.currentTimeMillis()
        ts = now
        _state.value = next
        prefs.setString(
            key,
            buildJsonObject {
                put("_ts", now)
                for ((kk, v) in next) put(kk, JsonArray(listOf(JsonPrimitive(v.first), JsonPrimitive(v.second))))
            }.toString(),
        )
    }

    fun impression(sub: String) = add(sub, 1.0, 0.0)
    fun engaged(sub: String) = add(sub, 0.0, 1.0)

    @Synchronized
    fun clear() {
        _state.value = emptyMap()
        prefs.remove(key)
    }

    companion object {
        private const val BASE = "fy_substats"
        private const val DECAY_PER_DAY = 0.95
        private const val CAP = 400
    }
}

/**
 * How many candidate titles each word appeared in (decayed), so learned
 * keywords are weighted by how distinctive they are: "verstappen" says far
 * more about you than "help". Updated from every For You build.
 */
class DocFreqStore(private val prefs: Prefs) {
    private var key = BASE
    private var ts: Long? = null
    @Volatile private var docs = 0.0 // decayed number of titles seen
    private val _state = MutableStateFlow<Map<String, Double>>(emptyMap())
    val state: StateFlow<Map<String, Double>> = _state

    @Synchronized
    fun load(username: String) {
        key = userScopedKey(prefs, username, BASE)
        val m = readJson(prefs, key)
        _state.value = try {
            ts = m["_ts"].long()
            val f = decayFactor(ts, DECAY_PER_DAY)
            docs = (m["_n"].double() ?: 0.0) * f
            val out = LinkedHashMap<String, Double>()
            for ((k, v) in m) if (!k.startsWith("_")) out[k] = num(v) * f
            out
        } catch (_: Exception) {
            ts = null
            docs = 0.0
            emptyMap()
        }
    }

    @Synchronized
    fun observe(titles: Iterable<String>) {
        val state = _state.value
        val f = decayFactor(ts, DECAY_PER_DAY)
        val next = LinkedHashMap<String, Double>()
        for ((k, v) in state) next[k] = v * f
        var d = docs * f
        for (t in titles) {
            d += 1
            for (w in titleKeywords(t).toSet()) {
                next.remove(w)
                next[w] = (state[w] ?: 0.0) * f + 1 // re-insert: recency order
            }
        }
        while (next.size > CAP) next.remove(next.keys.first())
        val now = System.currentTimeMillis()
        ts = now
        docs = d
        _state.value = next
        prefs.setString(key, doublesObject(next) { put("_ts", now); put("_n", d) })
    }

    /**
     * Rarity weight for [word], normalised so a typical word is ~1: rare words
     * count up to 2×, very common ones as little as 0.2×.
     */
    fun idf(word: String): Double {
        val n = docs
        if (n < 50) return 1.0 // not enough data yet
        val v = ln((n + 1) / ((_state.value[word] ?: 0.0) + 1))
        val typical = ln((n + 1) / 4) // seen in ~3 of N titles
        return (v / typical).coerceIn(0.2, 2.0)
    }

    @Synchronized
    fun clear() {
        _state.value = emptyMap()
        docs = 0.0
        prefs.remove(key)
    }

    companion object {
        private const val BASE = "fy_docfreq"
        private const val DECAY_PER_DAY = 0.9
        private const val CAP = 2000
    }
}

/**
 * Rolling 7-day counters of how For You performs (impressions, opens,
 * 30s+ reads, votes, More/Less taps, split by primary vs discovery and by
 * source). On-device only, never uploaded, and only kept while history
 * tracking is on. Shown on a hidden debug screen in Manage For You, and used
 * to adapt how much discovery the feed mixes in.
 */
class ForYouMetrics(private val prefs: Prefs, private val trackHistory: () -> Boolean) {
    private var key = BASE
    private val _state = MutableStateFlow<Map<String, Map<String, Int>>>(emptyMap())
    val state: StateFlow<Map<String, Map<String, Int>>> = _state

    private fun day(d: LocalDate) = d.toString() // yyyy-MM-dd, local date

    @Synchronized
    fun load(username: String) {
        key = userScopedKey(prefs, username, BASE)
        val m = readJson(prefs, key)
        _state.value = try {
            val out = LinkedHashMap<String, Map<String, Int>>()
            for ((d, v) in m) {
                val bucket = LinkedHashMap<String, Int>()
                v.jsonObject.forEach { (k, c) -> bucket[k] = num(c).toInt() }
                out[d] = bucket
            }
            out
        } catch (_: Exception) {
            emptyMap()
        }
    }

    @Synchronized
    fun count(metric: String, n: Int = 1) {
        if (!trackHistory()) return
        val now = LocalDate.now()
        val keep = (0 until 7).map { day(now.minusDays(it.toLong())) }.toSet()
        val today = day(now)
        val next = LinkedHashMap<String, MutableMap<String, Int>>()
        for ((d, v) in _state.value) if (d in keep) next[d] = LinkedHashMap(v)
        val bucket = next.getOrPut(today) { LinkedHashMap() }
        bucket[metric] = (bucket[metric] ?: 0) + n
        _state.value = next
        prefs.setString(
            key,
            buildJsonObject {
                for ((d, b) in next) put(d, buildJsonObject { for ((k, c) in b) put(k, c) })
            }.toString(),
        )
    }

    /** Totals over the last 7 days. */
    fun totals(): Map<String, Int> {
        val out = LinkedHashMap<String, Int>()
        for (d in _state.value.values) for ((k, v) in d) out[k] = (out[k] ?: 0) + v
        return out
    }

    /**
     * How often discovery posts get opened relative to primary ones (1 =
     * same). Drives the adaptive discovery share; 1 until there's data.
     */
    fun discoveryAppetite(): Double {
        val t = totals()
        val di = t["impr.discovery"] ?: 0
        val pi = t["impr.primary"] ?: 0
        if (di < 30 || pi < 30) return 1.0
        val dr = ((t["open.discovery"] ?: 0) + 1.0) / (di + 6)
        val pr = ((t["open.primary"] ?: 0) + 1.0) / (pi + 6)
        return dr / pr
    }

    @Synchronized
    fun clear() {
        _state.value = emptyMap()
        prefs.remove(key)
    }

    companion object {
        private const val BASE = "fy_metrics"
    }
}

/**
 * What the ranker knew about a post it placed: where it came from, whether
 * it was a discovery pick, and the factors behind its score (for "Why am I
 * seeing this?" and the metrics).
 */
@Immutable
data class ForYouMeta(
    val source: String, // best / rising / popular / favourite / interest / community
    val discovery: Boolean,
    val position: Int, // 0-based slot on its page
    val why: List<String>,
)
