import Foundation

/// Inbox rows sit under a day (#315): today's, then everything older.
enum InboxDay: Int, Comparable {
    case today, earlier

    var label: String { self == .today ? "Today" : "Earlier" }

    static func < (a: InboxDay, b: InboxDay) -> Bool { a.rawValue < b.rawValue }
}

func inboxDay(_ createdUtc: Int, now: Int, calendar: Calendar = .current) -> InboxDay {
    let at = Date(timeIntervalSince1970: TimeInterval(createdUtc) / 1000)
    let today = Date(timeIntervalSince1970: TimeInterval(now) / 1000)
    return calendar.isDate(at, inSameDayAs: today) ? .today : .earlier
}

/// `items` under their days, Today first, each in the list's own order.
func byDay(_ items: [InboxItem], now: Int, calendar: Calendar = .current) -> [(day: InboxDay, items: [InboxItem])] {
    var groups: [InboxDay: [InboxItem]] = [:]
    for item in items { groups[inboxDay(item.createdUtc, now: now, calendar: calendar), default: []].append(item) }
    return groups.keys.sorted().map { ($0, groups[$0]!) }
}

/// A message's or reply's text as one line of a row.
func inboxPreview(_ body: String) -> String { body.replacingOccurrences(of: "\n", with: " ") }

/// Who a private-message thread is with: a person, or a subreddit (its mods, its messages).
struct Correspondent: Hashable {
    let key: String
    let name: String
    let isSubreddit: Bool
}

func isMine(_ m: InboxItem, me: String) -> Bool { !me.isEmpty && m.author.lowercased() == me.lowercased() }

func correspondent(_ root: InboxItem, me: String) -> Correspondent {
    if let sub = root.subreddit, !sub.isEmpty { return Correspondent(key: "r/\(sub.lowercased())", name: sub, isSubreddit: true) }
    let all = [root] + root.replies
    // Someone in the thread who isn't you, else where yours went.
    let other = all.first(where: { $0.author.lowercased() != me.lowercased() && !$0.author.hasPrefix("[") })?.author
        ?? all.lazy.compactMap { m in m.dest.flatMap { $0.isEmpty || $0.lowercased() == me.lowercased() ? nil : $0 } }.first
        ?? root.author
    if other.hasPrefix("#") {
        let sub = other.removePrefix("#")
        return Correspondent(key: "r/\(sub.lowercased())", name: sub, isSubreddit: true)
    }
    return Correspondent(key: other.lowercased(), name: other, isSubreddit: false)
}

/// Every loaded message thread with one person (#315): `threads` oldest activity first, so
/// the one to answer is last; `unread` counts their new messages.
struct Conversation {
    let with: Correspondent
    let threads: [InboxItem]
    let latest: InboxItem
    let unread: Int
    /// The other person's account id, for their picture.
    let accountId: String?
}

private func messages(_ t: InboxItem) -> [InboxItem] { [t] + t.replies }

private func lastAt(_ t: InboxItem) -> Int { messages(t).map(\.createdUtc).max() ?? t.createdUtc }

/// The Messages list's threads (`roots`, each with its replies) by person, newest first.
func conversations(_ roots: [InboxItem], me: String) -> [Conversation] {
    var order: [String] = []
    var groups: [String: [InboxItem]] = [:]
    for r in roots {
        let key = correspondent(r, me: me).key
        if groups[key] == nil { order.append(key) }
        groups[key, default: []].append(r)
    }
    return order.map { key -> Conversation in
        let threads = groups[key]!
        let all = threads.flatMap(messages)
        let with = correspondent(threads[0], me: me)
        return Conversation(
            with: with,
            threads: threads.sorted { lastAt($0) < lastAt($1) },
            latest: all.max { $0.createdUtc < $1.createdUtc }!,
            unread: all.filter { $0.isNew && !isMine($0, me: me) }.count,
            accountId: all.first { !isMine($0, me: me) && $0.author.lowercased() == with.name.lowercased() }?.authorFullname
        )
    }
    .sorted { $0.latest.createdUtc > $1.latest.createdUtc }
}

/// A line of a conversation's chat: a thread's start, the new ones' start, or a message.
enum ChatEntry: Identifiable {
    case threadStart(InboxItem)
    case newFrom(Int)
    case message(InboxItem)

    var id: String {
        switch self {
        case let .threadStart(root): "start_\(root.fullname)"
        case .newFrom: "new"
        case let .message(m): m.fullname
        }
    }
}

/// `threads` as one chat, oldest first: each thread under its date and subject, "N new" before the first unread.
func chatEntries(_ threads: [InboxItem], me: String, dividers: Bool) -> [ChatEntry] {
    var out: [ChatEntry] = []
    let unread = threads.flatMap(messages).filter { $0.isNew && !isMine($0, me: me) }.count
    var marked = false
    for t in threads {
        if dividers { out.append(.threadStart(t)) }
        for m in messages(t).sorted(by: { $0.createdUtc < $1.createdUtc }) {
            if !marked, unread > 0, m.isNew, !isMine(m, me: me) {
                out.append(.newFrom(unread))
                marked = true
            }
            out.append(.message(m))
        }
    }
    return out
}

/// The unread messages from others in `threads`, to mark read together.
func unreadIn(_ threads: [InboxItem], me: String) -> [String] {
    threads.flatMap(messages).filter { $0.isNew && !isMine($0, me: me) }.map(\.fullname)
}
