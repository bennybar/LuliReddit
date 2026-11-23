import Foundation
import UserNotifications

/// The Digest's daily notification (Settings › Digest › Daily notification). iOS won't run
/// work at an exact time, so this is a repeating local reminder at `digestTime` ("Your
/// digest is ready"); the digest is built when it's opened, and earlier when iOS gives the
/// app background time (the inbox's background refresh). Tapping it opens the Digest.
enum DigestNotifications {
    static let target = "digest" // InboxNotifications.extraTarget value
    private static let id = "digest_daily"

    /// Schedules the daily reminder, or removes it when the notification is off.
    @MainActor static func reschedule() {
        let s = app.settings.value
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard s.digestEnabled && s.digestNotify else { return }
        let content = UNMutableNotificationContent()
        content.title = "Your digest is ready"
        content.body = "The posts that stood out today in your communities."
        content.sound = .default
        content.userInfo = [InboxNotifications.extraTarget: target]
        var when = DateComponents()
        when.hour = s.digestTime / 60
        when.minute = s.digestTime % 60
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true)))
        // Background time (iOS decides when) builds it ahead of the reminder.
        InboxNotifications.registerPolling()
    }

    /// "08:00" / "8:00 AM", as the phone shows times.
    static func timeLabel(_ minutes: Int) -> String {
        var c = DateComponents()
        c.hour = minutes / 60
        c.minute = minutes % 60
        guard let date = Calendar.current.date(from: c) else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// Turning the daily notification on: it needs notifications allowed.
@MainActor func setDigestNotify(_ on: Bool) async {
    if on, await !app.inbox.requestPermission() {
        app.navigator.showSnackbar("Allow Ilay's notifications to get your digest")
        return
    }
    app.settings.setDigestNotify(on)
    DigestNotifications.reschedule()
}
