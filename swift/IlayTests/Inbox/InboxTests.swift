import WebKit
import XCTest
@testable import Ilay

/// The notification text + tap target built from one raw unread item (inbox_poller.dart parity).
final class InboxPollerParseTests: XCTestCase {
    private func parse(_ s: String) -> UnreadItem { InboxModule.parseUnread(json(s))! }

    func testCommentReplyDeepLinksToTheComment() {
        let u = parse(#"{"name":"t1_c1","author":"bob","was_comment":true,"link_title":"A post","body":"hi\nthere","subreddit":"pics","link_id":"t3_p1"}"#)
        XCTAssertEqual(u.title, "u/bob replied · A post")
        XCTAssertEqual(u.body, "hi there")
        XCTAssertEqual(u.post, UnreadItem.PostTarget(subreddit: "pics", postId: "p1", commentId: "c1"))
        XCTAssertNil(u.messageFullname)
    }

    func testMessageUsesItsSubjectAndOpensTheConversation() {
        let u = parse(#"{"name":"t4_m2","author":"amy","subject":"Hello","body":"","first_message_name":"t4_m1"}"#)
        XCTAssertEqual(u.title, "Hello")
        XCTAssertEqual(u.body, "Open Ilay to read")
        XCTAssertNil(u.post)
        XCTAssertEqual(u.messageFullname, "t4_m1")
    }

    func testLongBodiesAreCutAt140Chars() {
        let u = parse(#"{"name":"t4_m3","author":"amy","subject":"","body":"\#(String(repeating: "x", count: 200))"}"#)
        XCTAssertEqual(u.title, "Message from u/amy")
        XCTAssertEqual(u.body, String(repeating: "x", count: 140) + "…")
        XCTAssertEqual(u.messageFullname, "t4_m3")
    }

    func testNoNameIsNoItem() {
        XCTAssertNil(InboxModule.parseUnread(json(#"{"author":"amy"}"#)))
    }
}

final class RedditNotificationsParseTests: XCTestCase {
    func testReadsWhatThePageListsDropsEmptiesAndRepeats() {
        let items = RedditNotifications.parse(json(#"""
        {"login":false,"ready":true,"items":[
          {"id":"a1","type":"POST_REPLY","link":"https://www.reddit.com/r/x/comments/p1/t/c1/","title":"u/bob replied to your post in r/x","body":"Nice!","ts":"2026-10-17T15:03:29.378Z","avatar":"https://www.redditstatic.com/a.png"},
          {"id":"a1","type":"POST_REPLY","link":null,"title":"dup","body":"","ts":null,"avatar":null},
          {"id":"a2","type":"UPVOTE_POST","link":"javascript:void(0)","title":"10 upvotes!","body":"","ts":"bad","avatar":"/rel.png"},
          {"id":"a3","type":"X","link":null,"title":"","body":"","ts":null,"avatar":null}
        ]}
        """#))
        XCTAssertEqual(items.map(\.id), ["a1", "a2"])
        XCTAssertEqual(items[0].body, "Nice!")
        XCTAssertEqual(items[0].at, 1792249409378)
        XCTAssertNil(items[1].link)
        XCTAssertEqual(items[1].at, 0)
        XCTAssertNil(items[1].avatar)
    }

    func testFindsTheCommentANotificationPointsAt() {
        XCTAssertEqual(RedditNotifications.commentIdOf("https://www.reddit.com/r/GalaxyWatch/comments/1x79dhp/new_button_remapping_app/phbdvfd/"), "phbdvfd")
        XCTAssertEqual(RedditNotifications.commentIdOf("https://www.reddit.com/r/WearOS/comments/1x79h6q/slug/ph6woy7/?screen_view_count=1"), "ph6woy7")
        XCTAssertEqual(RedditNotifications.commentIdOf("https://www.reddit.com/r/x/comments/1x/comment/abc12/"), "abc12")
        XCTAssertNil(RedditNotifications.commentIdOf("https://www.reddit.com/r/WearOS/comments/1x79h6q/new_galaxy_watch/"), "a post, not a comment")
    }

    /// WebKit refuses the whole list over one rule it can't read, and then nothing is blocked.
    @MainActor func testTheBlockRulesCompile() async throws {
        let id = "ilay-tests-\(UUID().uuidString)"
        let list = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: id, encodedContentRuleList: redditNotificationBlockRules)
        XCTAssertNotNil(list)
        try await WKContentRuleListStore.default().removeContentRuleList(forIdentifier: id)
    }
}

/// What the Flutter build left behind must keep working after the update.
final class InboxDataCompatTests: XCTestCase {
    func testFlutterNotificationPayloadsStillOpen() {
        let reply = flutterPayloadRoute("/comments/pics/p1?comment=c1")
        XCTAssertEqual(reply.route, .post(subreddit: "pics", postId: "p1", focusCommentId: "c1"))
        XCTAssertTrue(reply.inbox)
        let message = flutterPayloadRoute("/message?id=t4_m1")
        XCTAssertEqual(message.route, .messageThread(fullname: "t4_m1"))
        XCTAssertTrue(message.inbox)
        let reminder = flutterPayloadRoute("reminder:/comments/pics/p1")
        XCTAssertEqual(reminder.route, .post(subreddit: "pics", postId: "p1"))
        XCTAssertFalse(reminder.inbox)
        XCTAssertNil(flutterPayloadRoute("/somewhere").route)
    }

    @MainActor func testNotificationLogReadsTheFlutterFormatAndWritesItBack() {
        let prefs = testPrefs()
        let raw = #"[{"at":1000,"acct":"bob","src":"reminder","title":"T","text":"B","out":"NOT_SHOWN","sub":"pics","post":"p1"},{"at":5,"out":"UNKNOWN"},{"at":900,"acct":"","src":"reddit","title":"A","text":"","out":"REPLACED","how":"h","data":"d"}]"#
        prefs.setString("notification_log", raw)
        prefs.setString("notification_last_check", "1234|3 unread, nothing new")
        let log = NotificationLog(prefs: prefs)
        XCTAssertEqual(log.events.map(\.at), [1000, 900])
        XCTAssertEqual(log.events[0].outcome, .notShown)
        XCTAssertEqual(log.events[0].subreddit, "pics")
        XCTAssertEqual(log.events[1].how, "h")
        XCTAssertEqual(log.lastCheck?.at, 1234)
        XCTAssertEqual(log.lastCheck?.result, "3 unread, nothing new")

        log.add(NotificationEvent(at: 2000, account: "bob", source: NotificationEvent.sourceInbox, title: "N", text: "", outcome: .shown, messageFullname: "t4_m"))
        let reread = NotificationLog(prefs: prefs)
        XCTAssertEqual(reread.events, log.events)
        XCTAssertEqual(reread.events[0].messageFullname, "t4_m")
        XCTAssertTrue(prefs.getString("notification_log")!.contains(#""out":"SHOWN""#))
    }

    @MainActor func testNotificationLogKeepsTheLast50() {
        let log = NotificationLog(prefs: testPrefs())
        for i in 0..<60 { log.add(NotificationEvent(at: i, account: "", source: "inbox", title: "t", text: "", outcome: .shown)) }
        XCTAssertEqual(log.events.count, 50)
        XCTAssertEqual(log.events.first?.at, 59)
    }

    func testSummariesLeftByTheExtensionParse() {
        let data = Data(#"[{"postId":"p1","subreddit":"pics","title":"T","permalink":"/r/pics/comments/p1","style":"Key points","model":"m","text":"S","createdAt":1234},"junk"]"#.utf8)
        let list = parsePendingSummaries(data)
        XCTAssertEqual(list, [SavedSummary(postId: "p1", subreddit: "pics", title: "T", permalink: "/r/pics/comments/p1", style: "Key points", model: "m", text: "S", createdAt: 1234)])
        XCTAssertEqual(parsePendingSummaries(Data("nope".utf8)), [])
    }
}

final class PostRemindersTests: XCTestCase {
    func testStoredRemindersDecode() {
        XCTAssertEqual(decodeReminders(#"{"p1":1000,"p2":"bad"}"#), ["p1": 1000])
        XCTAssertEqual(decodeReminders(nil), [:])
        XCTAssertEqual(decodeReminders("nope"), [:])
    }

    /// Dart's reminderNotificationId / Kotlin's hashCode of the same string: 'reminder_abc'.
    func testNotificationIdMatchesTheOtherBuilds() {
        var h: Int32 = 0
        for c in "reminder_abc".utf16 { h = h &* 31 &+ Int32(c) }
        XCTAssertEqual(reminderNotificationId("abc"), Int(h) & 0x7fffffff)
        XCTAssertEqual(reminderNotificationId("abc"), reminderNotificationId("abc"))
    }

    func testWhenLabel() {
        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12))!
        func label(days: Int, hours: Int = 0) -> String {
            let d = cal.date(byAdding: .hour, value: hours, to: cal.date(byAdding: .day, value: days, to: now)!)!
            return whenLabel(Int(d.timeIntervalSince1970 * 1000), now: now)
        }
        XCTAssertEqual(whenLabel(Int(now.timeIntervalSince1970 * 1000) - 1, now: now), "any moment now")
        XCTAssertTrue(label(days: 0, hours: 1).hasPrefix("today at "))
        XCTAssertTrue(label(days: 1).hasPrefix("tomorrow at "))
        XCTAssertTrue(label(days: 3).hasPrefix(cal.date(byAdding: .day, value: 3, to: now)!.formatted(.dateTime.weekday(.abbreviated)) + " at "))
        XCTAssertTrue(label(days: 7).hasPrefix("on "))
    }
}

final class KeyboardMediaTests: XCTestCase {
    /// A GIF stays the GIF it is, so it keeps moving (not re-encoded as a PNG).
    @MainActor func testAGifIsPastedAsIs() {
        let board = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: board.name) }
        XCTAssertNil(pasteImageAttachment(from: board))
        let gif = Data("GIF89a-test".utf8)
        board.setData(gif, forPasteboardType: "com.compuserve.gif")
        let m = pasteImageAttachment(from: board)
        XCTAssertEqual(m?.bytes, gif)
        XCTAssertEqual(m?.filename, "pasted.gif")
        XCTAssertEqual(m?.mimeType, "image/gif")
        XCTAssertEqual(m?.isVideo, false)
    }
}

/// `ShareExtension/ShareViewController.swift`, compiled into this target too.
final class ShareLinkTests: XCTestCase {
    func testFindsTheRedditLinkInSharedText() {
        XCTAssertEqual(ShareViewController.redditLink(in: "Cool post https://www.reddit.com/r/pics/comments/p1/t/ via app")?.host, "www.reddit.com")
        XCTAssertEqual(ShareViewController.redditLink(in: "https://redd.it/abc")?.host, "redd.it")
        XCTAssertNil(ShareViewController.redditLink(in: "https://example.com/a"))
    }

    func testTheOpenLinkUsesTheBuildsSchemeAndTheAppReadsIt() {
        let link = URL(string: "https://www.reddit.com/r/pics/comments/p1/t/?a=1&b=2")!
        for scheme in ["luli", "ilayswift"] {
            let url = ShareViewController.shareUrl(link, summarize: true, scheme: scheme)!
            XCTAssertEqual(url.scheme, scheme)
            let shared = sharedLink(url)
            XCTAssertEqual(shared?.url, link)
            XCTAssertEqual(shared?.summarize, true)
        }
        XCTAssertEqual(sharedLink(ShareViewController.shareUrl(link, summarize: false, scheme: "luli")!)?.summarize, false)
    }
}
