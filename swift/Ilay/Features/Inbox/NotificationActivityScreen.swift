import SwiftUI
import UserNotifications

/// Settings → Notification activity: whether Ilay can notify you right now (and what
/// to fix if not), "Check now", and the last notifications it showed or couldn't show:
/// tap one to open it.
struct NotificationActivityScreen: View {
    @Environment(AppNavigator.self) private var nav
    @Environment(\.scenePhase) private var scenePhase
    @State private var canNotify = true
    @State private var checking = false

    var body: some View {
        let log = app.notificationLog
        let notifyInbox = app.settings.value.notifyInbox
        List {
            Section {
                StatusRow(
                    ok: canNotify,
                    text: canNotify ? "Ilay can show notifications" : "Ilay's notifications are turned off",
                    fix: canNotify ? nil : "Allow"
                ) {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                }
                // iOS decides how often a background check runs.
                StatusRow(
                    ok: notifyInbox,
                    text: notifyInbox ? "Checks your inbox in the background" : "Inbox notifications are off (Settings → Notifications)",
                    fix: nil
                ) {}
                Text(log.lastCheck.map { "Last check \(timeAgoPhrase($0.at)): \($0.result)" } ?? "No inbox check yet")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(action: checkNow) {
                    Label(checking ? "Checking…" : "Check now", systemImage: "arrow.clockwise")
                }
                .disabled(checking)
            }
            Section("Recent") {
                if log.events.isEmpty {
                    Text("Notifications Ilay shows or can't show will be listed here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(log.events, id: \.rowId) { EventRow(event: $0) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Notification activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !log.events.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") { log.clear() }
                }
            }
        }
        // The permission is the system's: re-read on return from its settings.
        .task(id: scenePhase) { canNotify = await InboxNotifications.canPost() }
    }

    private func checkNow() {
        checking = true
        Task {
            let shown = await app.inbox.pollInbox(notify: true)
            nav.showSnackbar(shown.isEmpty
                ? "Checked: \(app.notificationLog.lastCheck?.result ?? "nothing new")"
                : "\(shown.count) new notification\(shown.count == 1 ? "" : "s")")
            checking = false
        }
    }
}

private struct StatusRow: View {
    let ok: Bool
    let text: String
    let fix: String?
    let onFix: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(ok ? AnyShapeStyle(.tint) : AnyShapeStyle(.red))
            Text(text).font(.subheadline)
            Spacer(minLength: 0)
            if let fix { Button(fix, action: onFix).buttonStyle(.borderless) }
        }
    }
}

private struct EventRow: View {
    let event: NotificationEvent
    @Environment(AppNavigator.self) private var nav

    var body: some View {
        let e = event
        let meta = [
            e.account.nilIfEmpty.map { "u/\($0)" },
            timeAgoPhrase(e.at),
            e.source == NotificationEvent.sourceReddit ? "from the Reddit app" : nil,
        ].compactMap { $0 }.joined(separator: " · ")
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: e.outcome.ok ? "bell.badge" : "bell.slash")
                .foregroundStyle(e.outcome.ok ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
            VStack(alignment: .leading, spacing: 2) {
                Text(e.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                if !e.text.isEmpty {
                    Text(e.text).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
                Text(meta + "\n" + e.outcome.label + (e.how.map { " · \($0)" } ?? "") + (e.redditData.map { "\nReddit sent: \($0)" } ?? ""))
                    .font(.caption)
                    .foregroundStyle(e.outcome.ok ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
            }
            Spacer(minLength: 0)
            Button("Open", action: open).buttonStyle(.borderless)
        }
    }

    /// Opens the event's reply / message.
    private func open() {
        let e = event
        if !e.account.isEmpty, e.account.lowercased() != app.session.username.lowercased() {
            nav.showSnackbar("This was for u/\(e.account): switch to that account to open it")
            return
        }
        if let subreddit = e.subreddit, let postId = e.postId {
            nav.push(.post(subreddit: subreddit, postId: postId, focusCommentId: e.commentId))
        } else if let message = e.messageFullname {
            nav.push(.messageThread(fullname: message))
        } else {
            nav.showSnackbar("Couldn't find it: try your Inbox")
        }
    }
}

private extension NotificationEvent {
    var rowId: String { "\(at)_\(title)" }
}
