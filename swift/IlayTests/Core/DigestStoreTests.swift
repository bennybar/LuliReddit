import XCTest
@testable import Ilay

/// The digest file: both apps read and write it (the Kotlin DigestStoreTest reads this same fixture).
final class DigestStoreTests: XCTestCase {
    /// Also in the Kotlin DigestStoreTest: keep them the same.
    private let fixture = #"{"days":[{"day":"2027-01-15","built":1000,"refreshed":2000,"seen":1500,"overview":"Calm.","aiFailed":1,"aiAt":2000,"items":[{"raw":{"id":"abc","name":"t3_abc","title":"Hello","subreddit":"swift","subreddit_name_prefixed":"r/swift","author":"a","score":42,"num_comments":7,"created_utc":1800000000,"permalink":"/r/swift/comments/abc/","url":"https://www.reddit.com/r/swift/comments/abc/","is_self":true},"why":"Why.","n":2.5,"at":1000,"imp":4}],"judged":{"abc":[1,2.5,1000,0],"def":[0,1.1,1000,1]}}]}"#

    func testReadsTheSharedFixture() throws {
        let days = decodeDigestDays(try AppJson.parse(fixture))
        XCTAssertEqual(days.count, 1)
        let d = days[0]
        XCTAssertEqual(d.day, "2027-01-15")
        XCTAssertEqual(d.builtAt, 1000)
        XCTAssertEqual(d.refreshedAt, 2000)
        XCTAssertEqual(d.seenAt, 1500)
        XCTAssertEqual(d.overview, "Calm.")
        XCTAssertTrue(d.aiFailed)
        XCTAssertEqual(d.aiAt, 2000)
        XCTAssertEqual(d.items.count, 1)
        let item = d.items[0]
        XCTAssertEqual(item.post.id, "abc")
        XCTAssertEqual(item.post.title, "Hello")
        XCTAssertEqual(item.post.score, 42)
        XCTAssertEqual(item.why, "Why.")
        XCTAssertEqual(item.notability, 2.5)
        XCTAssertEqual(item.addedAt, 1000)
        XCTAssertEqual(item.importance, 4)
        XCTAssertEqual(d.judged["abc"], Judged(picked: true, notability: 2.5, at: 1000, secondLook: false))
        XCTAssertEqual(d.judged["def"], Judged(picked: false, notability: 1.1, at: 1000, secondLook: true))
    }

    func testRoundTrip() throws {
        var raws: [String: JsonElement] = [:]
        let days = decodeDigestDays(try AppJson.parse(fixture)) { raws[$0] = $1 }
        let again = decodeDigestDays(try AppJson.parse(encodeDigestDays(days) { raws[$0] }.encoded()))
        XCTAssertEqual(again, days)
    }

    func testAPostWithNoSavedJsonIsLeftOut() throws {
        let days = decodeDigestDays(try AppJson.parse(fixture))
        let again = decodeDigestDays(try AppJson.parse(encodeDigestDays(days) { _ in nil }.encoded()))
        XCTAssertTrue(again[0].items.isEmpty)
        XCTAssertEqual(again[0].judged, days[0].judged)
    }

    func testTabOrder() {
        XCTAssertEqual(tabOrder(Settings(), signedIn: true), [0, 1, 2, 3])
        var tab = Settings()
        tab.digestEnabled = true
        tab.digestPlace = 1
        XCTAssertEqual(tabOrder(tab, signedIn: true), [0, 1, 4, 2, 3])
        XCTAssertEqual(tabOrder(tab, signedIn: false), [0, 1, 2, 3])
        tab.inboxInProfile = true
        XCTAssertEqual(tabOrder(tab, signedIn: true), [0, 1, 4, 3])
    }
}
