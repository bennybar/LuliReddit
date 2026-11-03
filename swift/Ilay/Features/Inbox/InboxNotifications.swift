import BackgroundTasks
import UIKit
import UserNotifications

/// Background polling of the Reddit inbox + local notifications.
///
/// No push service: `BGTaskScheduler` wakes us (roughly every 15 minutes at best:
/// iOS ultimately decides when, and whether, it runs), we fetch `/message/unread`, and
/// fire a local notification for any item we haven't already told the user about.
/// Works for both auth modes (OAuth and the website-session fallback) through the
/// app's RedditClient.
@MainActor enum InboxNotifications {
    // Same task as the Flutter build, so a check it already scheduled lands here.
    // Also in Info.plist's BGTaskSchedulerPermittedIdentifiers.
    static let taskId = "luli.inbox.poll"

    // A notification's userInfo, read back by InboxModule.handleNotificationTap.
    static let extraTarget = "ilay.inbox.target"
    static let extraSubreddit = "ilay.inbox.subreddit"
    static let extraPostId = "ilay.inbox.postId"
    static let extraCommentId = "ilay.inbox.commentId"
    static let extraMessage = "ilay.inbox.message"
    static let targetPost = "post"
    static let targetMessage = "message"
    static let targetApp = "app"

    /// The delegate must be set, and the task registered, before launch finishes.
    /// Once, from `IlayApp.init` (registering twice would crash).
    static func start() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskId, using: .main) { task in
            MainActor.assumeIsolated {
                let job = Task {
                    // Turned off but the request survived (e.g. restored backup): stop polling.
                    guard app.prefs.getBool(InboxModule.notifyInboxPref) == true else {
                        cancelPolling()
                        task.setTaskCompleted(success: true)
                        return
                    }
                    registerPolling() // A request runs once: ask for the next one.
                    _ = await app.inbox.pollInbox(notify: true)
                    // Success anyway unless time ran out; we retry next tick.
                    task.setTaskCompleted(success: !Task.isCancelled)
                }
                task.expirationHandler = { job.cancel() }
            }
        }
    }

    /// Whether a notification would actually show (adding one succeeds silently either way).
    static func canPost() async -> Bool {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    /// Posts `item`'s notification; false if Ilay can't post notifications.
    static func show(_ item: UnreadItem) async -> Bool {
        guard await canPost() else { return false }
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.sound = .default
        if let post = item.post {
            content.userInfo = [
                extraTarget: targetPost, extraSubreddit: post.subreddit,
                extraPostId: post.postId, extraCommentId: post.commentId,
            ]
        } else if let message = item.messageFullname {
            content.userInfo = [extraTarget: targetMessage, extraMessage: message]
        } else {
            content.userInfo = [extraTarget: targetApp]
        }
        let request = UNNotificationRequest(identifier: "inbox_\(item.fullname)", content: content, trigger: nil)
        return (try? await UNUserNotificationCenter.current().add(request)) != nil
    }

    /// Asks for the next ~15-minute check. Replaces a pending one, so it's safe to repeat.
    static func registerPolling() {
        let request = BGAppRefreshTaskRequest(identifier: taskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        // Fails where background refresh isn't available (off in Settings, the simulator):
        // nothing to do, and Notification activity still has Check now.
        try? BGTaskScheduler.shared.submit(request)
    }

    static func cancelPolling() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskId)
    }
}

private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    /// Show it while Ilay is open too, as on Android.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let info = response.notification.request.content.userInfo
        await MainActor.run { app.inbox.handleNotificationTap(info) }
    }
}
