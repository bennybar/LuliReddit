import Foundation
import Observation
import SwiftUI
import UserNotifications

/// "Remind me about this post": offered (a snackbar action) when you save a post, then
/// a local notification at the time you pick, scheduled with the system (it shows even
/// if Ilay isn't running; no push service). Unsaving cancels it. Pending ones are kept
/// (`pending`, post id → when) so the post shows it.
@MainActor @Observable
final class PostReminders {
    static let shared = PostReminders(prefs: app.prefs)

    // Read back by InboxModule.handleNotificationTap.
    static let target = "reminder"

    private static let pref = "postReminders" // post id → when (epoch millis)
    private static let postsPref = "postReminderPosts" // post id → [subreddit, title]

    /// Post id → when its reminder is due (millis).
    private(set) var pending: [String: Int]

    @ObservationIgnored private let prefs: Prefs
    @ObservationIgnored private var sweep: Task<Void, Never>?

    init(prefs: Prefs) {
        self.prefs = prefs
        pending = decodeReminders(prefs.getString(Self.pref))
        // Timers stop with the app, so what came due meanwhile is seen to on return.
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fired() }
        }
    }

    private func store(_ next: [String: Int]) {
        pending = next
        var o = JsonObject()
        for (id, at) in next { o[id] = .int(at) }
        prefs.setString(Self.pref, o.encoded())
        var posts = JsonObject()
        for (id, post) in storedPosts() where next[id] != nil { posts[id] = post }
        prefs.setString(Self.postsPref, posts.encoded())
    }

    private func storedPosts() -> JsonObject {
        prefs.getString(Self.postsPref).flatMap(parseJsonOrNull).obj() ?? JsonObject()
    }

    /// Due ones have fired (the system showed them): no longer pending, and in the
    /// notification log. Then waits for the next one to come due.
    func fired() {
        sweep?.cancel()
        let now = nowMillis()
        let due = pending.filter { $0.value <= now }
        if !due.isEmpty {
            let posts = storedPosts()
            Task {
                let shown = await InboxNotifications.canPost()
                for (id, at) in due.sorted(by: { $0.value < $1.value }) {
                    let sub = posts[id].arr()?.first.str()
                    app.notificationLog.add(NotificationEvent(
                        at: at, account: "", source: NotificationEvent.sourceReminder,
                        title: sub.map { "Reminder · r/\($0)" } ?? "Reminder",
                        text: posts[id].arr().flatMap { $0.count > 1 ? $0[1].str() : nil } ?? "",
                        outcome: shown ? .shown : .notShown,
                        subreddit: sub, postId: sub == nil ? nil : id
                    ))
                }
            }
            store(pending.filter { due[$0.key] == nil })
        }
        guard let next = pending.values.min() else { return }
        sweep = Task {
            try? await Task.sleep(for: .milliseconds(max(next - nowMillis(), 0)))
            if !Task.isCancelled { fired() }
        }
    }

    private func schedule(_ post: Post, at: Int) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Reminder · r/\(post.subreddit)"
        content.body = post.title
        content.sound = .default
        content.userInfo = [
            InboxNotifications.extraTarget: Self.target,
            InboxNotifications.extraSubreddit: post.subreddit,
            InboxNotifications.extraPostId: post.id,
        ]
        let seconds = max(Double(at - nowMillis()) / 1000, 1)
        let request = UNNotificationRequest(
            identifier: "\(reminderNotificationId(post.id))",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        )
        try await UNUserNotificationCenter.current().add(request)
        var posts = storedPosts()
        posts[post.id] = [.string(post.subreddit), .string(post.title)]
        prefs.setString(Self.postsPref, posts.encoded())
        var next = pending
        next[post.id] = at
        store(next)
        fired()
    }

    /// Unsaved: drop its reminder, if any.
    func cancelReminder(_ postId: String) {
        guard pending[postId] != nil else { return }
        let id = "\(reminderNotificationId(postId))"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
        var next = pending
        next[postId] = nil
        store(next)
    }

    /// Just saved `post`: a quiet "Remind me" next to "Saved".
    static func offer(_ post: Post) {
        app.navigator.showSnackbar("Saved", actionLabel: "Remind me") { Task { await pick(post) } }
    }

    /// Tapped a post's reminder line: pick a new time, or cancel it.
    static func manage(_ post: Post) {
        Task { await pick(post, existing: shared.pending[post.id]) }
    }

    /// Unsaved: drop its reminder, if any.
    static func cancel(_ postId: String) { shared.cancelReminder(postId) }

    private enum Choice {
        case hours(Int)
        case cancel
    }

    private static let choices = [("In 1 hour", 1), ("In 3 hours", 3), ("Tomorrow", 24), ("In 3 days", 72), ("In a week", 24 * 7)]

    private static func pick(_ post: Post, existing: Int? = nil) async {
        let nav = app.navigator
        let picked: Choice? = await Overlays.show(detents: [.medium]) { done in
            NavigationStack {
                List {
                    ForEach(choices, id: \.1) { choice in
                        Button(choice.0, systemImage: "clock") { done(.hours(choice.1)) }
                    }
                    if existing != nil {
                        Button("Cancel reminder", systemImage: "bell.slash", role: .destructive) { done(.cancel) }
                    }
                }
                .navigationTitle(existing.map { "Reminder \(whenLabel($0))" } ?? "Remind me about this post")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        switch picked {
        case nil: return
        case .cancel:
            cancel(post.id)
            nav.showSnackbar("Reminder cancelled")
        case let .hours(hours):
            // Reminders need notifications allowed.
            guard await app.inbox.requestPermission() else {
                nav.showSnackbar("Allow Ilay's notifications to get reminders")
                return
            }
            let at = nowMillis() + hours * 60 * 60_000
            do {
                try await shared.schedule(post, at: at)
            } catch {
                nav.showSnackbar("Couldn't set the reminder")
                return
            }
            nav.showSnackbar("I'll remind you \(whenLabel(at))")
        }
    }
}

/// The stored pending reminders; empty when missing or unreadable.
func decodeReminders(_ raw: String?) -> [String: Int] {
    guard let o = raw.flatMap(parseJsonOrNull).obj() else { return [:] }
    var out: [String: Int] = [:]
    for (id, at) in o { if let at = at.long() { out[id] = at } }
    return out
}

/// A stable notification id per post, the same as the Flutter build's (Kotlin's
/// `"reminder_$id".hashCode()`, non-negative): a reminder it scheduled must still be
/// replaceable and cancellable here.
func reminderNotificationId(_ postId: String) -> Int {
    var h: UInt32 = 0
    for c in "reminder_\(postId)".utf16 { h = h &* 31 &+ UInt32(c) }
    return Int(h & 0x7fffffff)
}

/// "today at 14:30", "tomorrow at 09:00", "Tue at 18:05", "on Oct 25 at 10:00".
func whenLabel(_ at: Int, now: Date = Date()) -> String {
    let date = Date(timeIntervalSince1970: Double(at) / 1000)
    if date <= now { return "any moment now" }
    let calendar = Calendar.current
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    let day = switch days {
    case 0: "today"
    case 1: "tomorrow"
    case 2..<7: date.formatted(.dateTime.weekday(.abbreviated))
    default: "on \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }
    return "\(day) at \(date.formatted(date: .omitted, time: .shortened))"
}
