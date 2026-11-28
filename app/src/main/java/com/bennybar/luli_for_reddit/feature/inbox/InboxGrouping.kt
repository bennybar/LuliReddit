package com.bennybar.luli_for_reddit.feature.inbox

import com.bennybar.luli_for_reddit.model.InboxItem
import java.time.Instant
import java.time.ZoneId

/** Inbox rows sit under a day (#315): today's, then everything older. */
internal enum class InboxDay(val label: String) { TODAY("Today"), EARLIER("Earlier") }

internal fun inboxDay(createdUtc: Long, now: Long, zone: ZoneId = ZoneId.systemDefault()): InboxDay =
    if (Instant.ofEpochMilli(createdUtc).atZone(zone).toLocalDate() == Instant.ofEpochMilli(now).atZone(zone).toLocalDate()) InboxDay.TODAY
    else InboxDay.EARLIER

/** [items] under their days, Today first, each in the list's own order. */
internal fun byDay(items: List<InboxItem>, now: Long, zone: ZoneId = ZoneId.systemDefault()): List<Pair<InboxDay, List<InboxItem>>> =
    items.groupBy { inboxDay(it.createdUtc, now, zone) }.toList().sortedBy { it.first.ordinal }

/** A message's or reply's text as one line of a row. */
internal fun inboxPreview(body: String): String = body.replace('\n', ' ')

/** Who a private-message thread is with: a person, or a subreddit (its mods, its messages). */
internal data class Correspondent(val key: String, val name: String, val isSubreddit: Boolean)

internal fun correspondent(root: InboxItem, me: String): Correspondent {
    root.subreddit?.takeIf { it.isNotEmpty() }?.let { return Correspondent("r/${it.lowercase()}", it, true) }
    val all = listOf(root) + root.replies
    // Someone in the thread who isn't you, else where yours went.
    val other = all.firstOrNull { !it.author.equals(me, ignoreCase = true) && !it.author.startsWith("[") }?.author
        ?: all.firstNotNullOfOrNull { m -> m.dest?.takeIf { it.isNotEmpty() && !it.equals(me, ignoreCase = true) } }
        ?: root.author
    if (other.startsWith("#")) return Correspondent("r/${other.removePrefix("#").lowercase()}", other.removePrefix("#"), true)
    return Correspondent(other.lowercase(), other, false)
}

/**
 * Every loaded message thread with one person (#315): [threads] oldest activity first, so
 * the one to answer is last; [unread] counts their new messages.
 */
internal data class Conversation(
    val with: Correspondent,
    val threads: List<InboxItem>,
    val latest: InboxItem,
    val unread: Int,
    /** The other person's account id, for their picture. */
    val accountId: String?,
)

private fun InboxItem.messages() = listOf(this) + replies

private fun InboxItem.lastAt() = messages().maxOf { it.createdUtc }

internal fun isMine(m: InboxItem, me: String) = me.isNotEmpty() && m.author.equals(me, ignoreCase = true)

/** The Messages list's threads ([roots], each with its replies) by person, newest first. */
internal fun conversations(roots: List<InboxItem>, me: String): List<Conversation> =
    roots.groupBy { correspondent(it, me).key }.values.map { threads ->
        val all = threads.flatMap { it.messages() }
        val with = correspondent(threads.first(), me)
        Conversation(
            with = with,
            threads = threads.sortedBy { it.lastAt() },
            latest = all.maxBy { it.createdUtc },
            unread = all.count { it.isNew && !isMine(it, me) },
            accountId = all.firstOrNull { !isMine(it, me) && it.author.equals(with.name, ignoreCase = true) }?.authorFullname,
        )
    }.sortedByDescending { it.latest.createdUtc }

/** A line of a conversation's chat: a thread's start, the new ones' start, or a message. */
internal sealed interface ChatEntry {
    val key: String

    data class ThreadStart(val root: InboxItem) : ChatEntry {
        override val key get() = "start_${root.fullname}"
    }

    data class NewFrom(val count: Int) : ChatEntry {
        override val key get() = "new"
    }

    data class Message(val message: InboxItem) : ChatEntry {
        override val key get() = message.fullname
    }
}

/** [threads] as one chat, oldest first: each thread under its date and subject, "N new" before the first unread. */
internal fun chatEntries(threads: List<InboxItem>, me: String, dividers: Boolean): List<ChatEntry> {
    val out = ArrayList<ChatEntry>()
    val unread = threads.sumOf { t -> t.messages().count { it.isNew && !isMine(it, me) } }
    var marked = false
    for (t in threads) {
        if (dividers) out += ChatEntry.ThreadStart(t)
        for (m in t.messages().sortedBy { it.createdUtc }) {
            if (!marked && unread > 0 && m.isNew && !isMine(m, me)) {
                out += ChatEntry.NewFrom(unread)
                marked = true
            }
            out += ChatEntry.Message(m)
        }
    }
    return out
}

/** The unread messages from others in [threads], to mark read together. */
internal fun unreadIn(threads: List<InboxItem>, me: String): List<String> =
    threads.flatMap { it.messages() }.filter { it.isNew && !isMine(it, me) }.map { it.fullname }
