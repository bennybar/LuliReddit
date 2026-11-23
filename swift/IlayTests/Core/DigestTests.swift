import SwiftUI
import XCTest
@testable import Ilay

/// The Digest's selection and refresh rules (docs/digest-spec.md), as the Kotlin app's DigestTest.
final class DigestTests: XCTestCase {
    private let now = 1_800_000_000_000
    private let hour = 3_600_000
    private var n = 0

    private func p(_ sub: String, _ score: Int, comments: Int = 10, title: String? = nil, hoursOld: Int = 3, url: String? = nil, stickied: Bool = false) -> Post {
        let id = "p\(n)"
        n += 1
        var post = Post(id: id, fullname: "t3_\(id)", title: title ?? "Post \(id) about something unique \(id)", subreddit: sub, subredditPrefixed: "r/\(sub)", author: "a", score: score, numComments: comments, upvoteRatio: 0.9, createdUtc: now - hoursOld * hour, permalink: "/r/\(sub)/comments/\(id)/", url: url ?? "https://www.reddit.com/r/\(sub)/comments/\(id)/", domain: "", type: url == nil ? .selfPost : .link, isSelf: url == nil)
        post.stickied = stickied
        return post
    }

    /// A community's ordinary day: `count` posts around `typical` points.
    private func ordinary(_ sub: String, _ typical: Int, _ count: Int = 6) -> [Post] { (0..<count).map { _ in p(sub, typical) } }

    private func build(_ candidates: [Post], size: DigestSize = .standard, read: Set<String> = [], prev: DigestDay? = nil, at: Int? = nil) -> DigestDay {
        mergeDigest(prev, day: "2027-01-15", candidates: candidates, readIds: read, size: size, now: at ?? now)
    }

    private func ids(_ d: DigestDay) -> [String] { d.items.map(\.post.id) }

    func testNotabilityIsRelativeToThePostsOwnCommunity() {
        // A small community's big day beats a big community's ordinary post.
        let smallHit = p("small", 300)
        let bigUsual = p("big", 9000)
        let r = build(ordinary("small", 30) + [smallHit] + ordinary("big", 9000) + [bigUsual])
        XCTAssertEqual(ids(r).first, smallHit.id)
    }

    func testAQuietDayGivesAShortDigestNeverPadded() {
        // Nothing stands out anywhere: nothing to show.
        XCTAssertEqual(build(ordinary("a", 100) + ordinary("b", 50)).items.count, 0)
    }

    func testACommunitysTopPostCountsWhenItStandsOutALittle() {
        let lead = p("a", 150) // 1.35×: under notable, over the top post's bar
        let tiny = p("b", 8) // stands out, but under 10 points
        let r = build(ordinary("a", 100) + [lead] + (0..<6).map { _ in p("b", 2) } + [tiny])
        XCTAssertEqual(r.items.map(\.post.id), [lead.id])
    }

    func testPostsShownOnAnEarlierDayArentShownAgain() {
        let hit = p("a", 5000)
        let other = p("a", 4000)
        let r = mergeDigest(nil, day: "2027-01-16", candidates: [hit, other] + ordinary("a", 10), readIds: [], size: .standard, now: now, shownBefore: [hit.id])
        XCTAssertEqual(r.items.map(\.post.id), [other.id])
        XCTAssertFalse(digestPending(nil, day: "2027-01-16", candidates: [hit, other], readIds: [], now: now, shownBefore: [hit.id]).map(\.id).contains(hit.id))
    }

    func testSizesCapTheTotalAndEachCommunity() {
        let hits = (0..<10).map { p("a", 1000 + $0) } + ordinary("a", 10, 20)
        XCTAssertEqual(build(hits, size: .brief).items.count, 2)
        XCTAssertEqual(build(hits, size: .standard).items.count, 2)
        let many = (0..<12).flatMap { c in [p("c\(c)", 5000), p("c\(c)", 4000)] + ordinary("c\(c)", 10) }
        XCTAssertEqual(build(many, size: .brief).items.count, 5)
        XCTAssertEqual(build(many, size: .standard).items.count, 20)
        XCTAssertEqual(build(many, size: .everything).items.count, 24)
    }

    func testOldStickiedAndAlreadyReadPostsAreLeftOut() {
        let old = p("a", 9000, hoursOld: 30)
        let pinned = p("a", 9000, stickied: true)
        let read = p("a", 8000)
        let fresh = p("a", 7000)
        let r = build([old, pinned, read, fresh] + ordinary("a", 10), read: [read.id])
        XCTAssertFalse(ids(r).contains(old.id))
        XCTAssertFalse(ids(r).contains(pinned.id))
        XCTAssertFalse(ids(r).contains(read.id))
        XCTAssertTrue(ids(r).contains(fresh.id))
    }

    func testOneCopyOfALinkOrAStory() {
        let a = p("a", 5000, url: "https://example.com/story?utm_source=x")
        let b = p("b", 4000, url: "https://www.example.com/story")
        let c = p("c", 5000, title: "Volcano erupts near Reykjavik airport tonight")
        let d = p("d", 4000, title: "Reykjavik airport closed as volcano erupts tonight")
        let r = build([a, b, c, d] + ordinary("a", 10) + ordinary("b", 10) + ordinary("c", 10) + ordinary("d", 10), size: .everything)
        XCTAssertTrue(ids(r).contains(a.id))
        XCTAssertFalse(ids(r).contains(b.id))
        XCTAssertTrue(ids(r).contains(c.id))
        XCTAssertFalse(ids(r).contains(d.id))
    }

    func testARefreshKeepsWhatsShownAndOnlyJudgesNewPosts() {
        let hit = p("a", 5000)
        let base = ordinary("a", 10)
        let first = build([hit] + base)
        XCTAssertEqual(ids(first), [hit.id])
        let later = now + 2 * hour
        let newHit = p("a", 6000)
        var moved = hit
        moved.score = 5500
        let second = build([moved, newHit] + base, prev: first, at: later)
        XCTAssertEqual(ids(second), [hit.id, newHit.id])
        XCTAssertEqual(second.items[0].post.score, 5500) // numbers refreshed
        XCTAssertEqual(second.items[0].why, first.items[0].why) // verdict kept
        XCTAssertEqual(second.judged[newHit.id]?.at, later)
        XCTAssertEqual(second.judged[base[0].id]?.at, first.judged[base[0].id]?.at) // not judged again
        XCTAssertTrue(second.isNew(second.items[1]))
        XCTAssertFalse(second.isNew(second.items[0]))
    }

    func testNothingShownIsRemoved() {
        let hit = p("a", 5000)
        let first = build([hit] + ordinary("a", 10))
        let second = build(ordinary("a", 10) + [p("a", 20)], prev: first, at: now + hour)
        XCTAssertTrue(ids(second).contains(hit.id))
    }

    func testAPostThatDoubledGetsOneSecondLook() {
        let base = ordinary("a", 100)
        let top = p("a", 3000)
        let grower = p("a", 150)
        let first = build(base + [top, grower])
        XCTAssertFalse(ids(first).contains(grower.id))
        var grown = grower
        grown.score = 900
        let second = build(base + [top, grown], prev: first, at: now + hour)
        XCTAssertTrue(ids(second).contains(grower.id))
        XCTAssertEqual(second.judged[grower.id]?.secondLook, true)
        // Doubled but still not notable: not picked on its second look, and never judged again.
        let bBase = ordinary("b", 10)
        let bTop = p("b", 900)
        let quiet = p("b", 5, comments: 1)
        let b1 = build(bBase + [bTop, quiet])
        var q2 = quiet
        q2.score = 12
        let b2 = build(bBase + [bTop, q2], prev: b1, at: now + hour)
        XCTAssertEqual(b2.judged[quiet.id]?.secondLook, true)
        XCTAssertFalse(ids(b2).contains(quiet.id))
        var q3 = quiet
        q3.score = 80
        let b3 = build(bBase + [bTop, q3], prev: b2, at: now + 2 * hour)
        XCTAssertEqual(b3.judged[quiet.id], b2.judged[quiet.id])
        XCTAssertFalse(ids(b3).contains(quiet.id))
    }

    func testANewDayStartsANewDigest() {
        let first = build([p("a", 5000)] + ordinary("a", 10))
        let next = mergeDigest(first, day: "2027-01-16", candidates: [p("a", 4000)] + ordinary("a", 10), readIds: [], size: .standard, now: now + 20 * hour)
        XCTAssertEqual(next.day, "2027-01-16")
        XCTAssertEqual(next.items.count, 1)
        XCTAssertFalse(next.isNew(next.items[0]))
    }

    func testLaterRefreshesAddUpToTheCommunityCap() {
        let many = (0..<6).flatMap { c in [p("c\(c)", 5000)] + ordinary("c\(c)", 10) }
        let first = build(many, size: .brief)
        XCTAssertEqual(first.items.count, 5)
        let second = build(many + [p("c0", 6000)], size: .brief, prev: first, at: now + hour)
        XCTAssertEqual(second.items.count, 6)
    }

    func testWhyLinesSayHowAPostStandsOut() {
        let hit = p("pics", 3000, comments: 240)
        let r = build([hit] + ordinary("pics", 100))
        XCTAssertTrue(r.items[0].why.hasPrefix("Top post today in r/pics · "), r.items[0].why)
        XCTAssertTrue(r.items[0].why.contains("240 comments"), r.items[0].why)
    }

    func testTextSizesDefaultTo100Percent() {
        let s = Settings()
        XCTAssertEqual(s.titleTextScale, 1)
        XCTAssertEqual(s.postTextScale, 1)
        XCTAssertEqual(s.commentTextScale, 1)
        // At 100% a kind keeps the app's size; off it, one Dynamic Type step from the phone's.
        XCTAssertEqual(IlayTheme.typeStep(1.0), DynamicTypeSize(UIApplication.shared.preferredContentSizeCategory) ?? .large)
    }

    func testSettingsDefaults() {
        let s = Settings()
        XCTAssertFalse(s.digestEnabled)
        XCTAssertEqual(DigestSize.of(s.digestSize), .standard)
        XCTAssertEqual(s.digestPlace, 0)
        XCTAssertFalse(s.digestShowRead)
        XCTAssertEqual(DigestSize.of(7), .standard)
    }
}
