import Foundation
import Observation

/// One notification Ilay handled: what came in and what it did with it.
struct NotificationEvent: Equatable, Sendable {
    // The last three come from Android's Reddit-app capture: a restored backup can hold them.
    enum Outcome: String, Sendable {
        case shown = "SHOWN"
        case notShown = "NOT_SHOWN"
        case replaced = "REPLACED"
        case copied = "COPIED"
        case kept = "KEPT"

        var label: String {
            switch self {
            case .shown: "Notified"
            case .notShown: "Not shown: Ilay's notifications are off or blocked"
            case .replaced: "Reddit's replaced by Ilay's"
            case .copied: "Reddit's copied into Ilay"
            case .kept: "Reddit's kept: Ilay can't show notifications"
            }
        }

        var ok: Bool { self != .notShown && self != .kept }
    }

    static let sourceInbox = "inbox"
    static let sourceReddit = "reddit"
    static let sourceReminder = "reminder"

    let at: Int
    let account: String
    /// `sourceInbox`: Ilay's own inbox check; `sourceReminder`: a post reminder;
    /// `sourceReddit`: one from the Reddit app (Android, in a restored backup).
    let source: String
    let title: String
    let text: String
    let outcome: Outcome
    /// Where it opens: a reply / mention (subreddit, post, comment) or a message thread.
    var subreddit: String? = nil
    var postId: String? = nil
    var commentId: String? = nil
    var messageFullname: String? = nil
    /// How a copied Reddit notification's destination was found ("your post, by its title").
    var how: String? = nil
    /// The extra fields Reddit's notification carried (names, and any link), to find an exact one.
    var redditData: String? = nil

    // Same fields as the Flutter and Android builds' logs.
    var json: JsonElement {
        var o = JsonObject()
        o["at"] = .int(at)
        o["acct"] = .string(account)
        o["src"] = .string(source)
        o["title"] = .string(title)
        o["text"] = .string(text)
        o["out"] = .string(outcome.rawValue)
        if let subreddit { o["sub"] = .string(subreddit) }
        if let postId { o["post"] = .string(postId) }
        if let commentId { o["comment"] = .string(commentId) }
        if let messageFullname { o["msg"] = .string(messageFullname) }
        if let how { o["how"] = .string(how) }
        if let redditData { o["data"] = .string(redditData) }
        return .object(o)
    }

    init(at: Int, account: String, source: String, title: String, text: String, outcome: Outcome,
         subreddit: String? = nil, postId: String? = nil, commentId: String? = nil, messageFullname: String? = nil) {
        self.at = at
        self.account = account
        self.source = source
        self.title = title
        self.text = text
        self.outcome = outcome
        self.subreddit = subreddit
        self.postId = postId
        self.commentId = commentId
        self.messageFullname = messageFullname
    }

    init?(json j: JsonElement) {
        guard let at = j["at"].long(), let outcome = j["out"].str().flatMap(Outcome.init(rawValue:)) else { return nil }
        self.at = at
        self.outcome = outcome
        account = j["acct"].str() ?? ""
        source = j["src"].str() ?? Self.sourceInbox
        title = j["title"].str() ?? ""
        text = j["text"].str() ?? ""
        subreddit = j["sub"].str()
        postId = j["post"].str()
        commentId = j["comment"].str()
        messageFullname = j["msg"].str()
        how = j["how"].str()
        redditData = j["data"].str()
    }
}

/// The last notifications Ilay showed or couldn't show (Settings → Notification
/// activity), plus the last inbox check: so a missed one can be found and opened, and
/// it's clear why. On this device only, all accounts (each entry names its account).
@MainActor @Observable
final class NotificationLog {
    private static let key = "notification_log"
    private static let checkKey = "notification_last_check"
    private static let max = 50

    @ObservationIgnored private let prefs: Prefs

    private(set) var events: [NotificationEvent]
    /// The last inbox check: when, and what came of it.
    private(set) var lastCheck: (at: Int, result: String)?

    init(prefs: Prefs) {
        self.prefs = prefs
        events = (prefs.getString(Self.key).flatMap(parseJsonOrNull).arr() ?? []).compactMap(NotificationEvent.init(json:))
        if let raw = prefs.getString(Self.checkKey), let at = Int(raw.substringBefore("|")) {
            lastCheck = (at, raw.substringAfter("|", missing: ""))
        }
    }

    func add(_ e: NotificationEvent) {
        events = Array(([e] + events).prefix(Self.max))
        prefs.setString(Self.key, JsonElement.array(events.map(\.json)).encoded())
    }

    func checked(_ result: String) {
        let now = nowMillis()
        lastCheck = (now, result)
        prefs.setString(Self.checkKey, "\(now)|\(result)")
    }

    func clear() {
        events = []
        prefs.remove(Self.key)
    }
}
