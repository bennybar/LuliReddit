import XCTest
@testable import Ilay

/// The Inbox redesign's grouping (#315): rows by day, messages by person, one chat per person.
final class InboxGroupingTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        return c
    }()

    private func at(_ day: Int, _ hour: Int) -> Int {
        let d = calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
        return Int(d.timeIntervalSince1970 * 1000)
    }

    private var now: Int { at(28, 12) }

    private func msg(_ id: String, _ author: String, _ at: Int, dest: String? = nil, new: Bool = false, sub: String? = nil, replies: [InboxItem] = [], subject: String = "Hi") -> InboxItem {
        InboxItem(fullname: "t4_\(id)", kind: .message, author: author, subject: subject, body: "body \(id)", createdUtc: at, isNew: new,
                  subreddit: sub, dest: dest, replies: replies, authorFullname: "t2_\(author)")
    }

    private func reply(_ id: String, _ at: Int) -> InboxItem {
        InboxItem(fullname: "t1_\(id)", kind: .commentReply, author: "someone", subject: "", body: "r", createdUtc: at, subreddit: "pics")
    }

    func testRowsSplitIntoTodayAndEarlier() {
        let days = byDay([reply("a", at(28, 9)), reply("b", at(28, 0)), reply("c", at(27, 23)), reply("d", at(20, 10))], now: now, calendar: calendar)
        XCTAssertEqual(days.map(\.day), [.today, .earlier])
        XCTAssertEqual(days[0].items.map(\.fullname), ["t1_a", "t1_b"])
        XCTAssertEqual(days[1].items.map(\.fullname), ["t1_c", "t1_d"])
    }

    func testOnlyEarlierWhenNothingToday() {
        XCTAssertEqual(byDay([reply("c", at(27, 23))], now: now, calendar: calendar).map(\.day), [.earlier])
    }

    func testThreadsGroupByTheOtherPerson() {
        let a1 = msg("1", "Alice", at(20, 10), dest: "me", replies: [msg("2", "me", at(20, 11), dest: "Alice")])
        // One you started: grouped by where it went.
        let a2 = msg("3", "me", at(27, 9), dest: "alice", replies: [msg("4", "alice", at(28, 8), dest: "me", new: true)])
        let b = msg("5", "Bob", at(26, 9), dest: "me", new: true)
        let mods = msg("6", "SomeMod", at(25, 9), dest: "me", sub: "Android")
        let convs = conversations([a1, b, a2, mods], me: "Me")
        XCTAssertEqual(convs.map(\.with.key), ["alice", "bob", "r/android"])
        let alice = convs[0]
        XCTAssertEqual(alice.threads.map(\.fullname), ["t4_1", "t4_3"]) // oldest activity first
        XCTAssertEqual(alice.latest.fullname, "t4_4")
        XCTAssertEqual(alice.unread, 1)
        XCTAssertEqual(alice.accountId, "t2_Alice")
        XCTAssertTrue(convs[2].with.isSubreddit)
    }

    func testAMessageToASubredditsModsIsTheSubreddit() {
        XCTAssertEqual(correspondent(msg("1", "me", at(27, 9), dest: "#Android"), me: "me"), Correspondent(key: "r/android", name: "Android", isSubreddit: true))
    }

    func testYourOwnUnreadDoesNotCount() {
        let t = msg("1", "bob", at(27, 9), dest: "me", replies: [msg("2", "me", at(27, 10), new: true)])
        XCTAssertEqual(conversations([t], me: "me").first?.unread, 0)
        XCTAssertEqual(unreadIn([t], me: "me"), [])
    }

    func testChatIsOldestFirstWithThreadStartsAndANewLine() {
        let old = msg("1", "bob", at(10, 9), dest: "me", replies: [msg("2", "me", at(10, 10), dest: "bob")], subject: "First")
        let recent = msg("3", "bob", at(28, 9), dest: "me", new: true, replies: [msg("4", "bob", at(28, 10), new: true)], subject: "Second")
        let entries = chatEntries([old, recent], me: "me", dividers: true)
        XCTAssertEqual(entries.map(\.id), ["start_t4_1", "t4_1", "t4_2", "start_t4_3", "new", "t4_3", "t4_4"])
        if case let .newFrom(count) = entries[4] { XCTAssertEqual(count, 2) } else { XCTFail("no new line") }
        XCTAssertEqual(unreadIn([old, recent], me: "me"), ["t4_3", "t4_4"])
    }

    func testASingleThreadHasNoDividers() {
        let t = msg("1", "bob", at(27, 9), dest: "me", replies: [msg("2", "me", at(27, 10))])
        XCTAssertEqual(chatEntries([t], me: "me", dividers: false).map(\.id), ["t4_1", "t4_2"])
    }
}
