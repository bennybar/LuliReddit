import XCTest
@testable import Ilay

/// The Digest's AI step with canned replies (no real AI calls), and the screen's orders,
/// as the Kotlin app's DigestAiTest.
final class DigestAiTests: XCTestCase {
    private let now = 1_800_000_000_000
    private let hour = 3_600_000
    private var n = 0

    private func p(_ sub: String, _ score: Int, comments: Int = 10, hoursOld: Int = 3, id: String? = nil) -> Post {
        let id = id ?? "p\(n)"
        n += 1
        return Post(id: id, fullname: "t3_\(id)", title: "Post \(id) about something unique \(id)", subreddit: sub, subredditPrefixed: "r/\(sub)", author: "a", score: score, numComments: comments, upvoteRatio: 0.9, createdUtc: now - hoursOld * hour, permalink: "/r/\(sub)/comments/\(id)/", url: "https://www.reddit.com/r/\(sub)/comments/\(id)/", domain: "", type: .selfPost, isSelf: true)
    }

    private func ordinary(_ sub: String, _ score: Int) -> [Post] { (0..<6).map { _ in p(sub, score) } }

    func testCleanJson() {
        let posts = [p("a", 100), p("a", 50), p("b", 10)]
        let r = parseDigestAi(#"{"overview":"Big day.","items":[{"i":0,"importance":5,"why":"Huge."},{"i":2,"importance":1,"why":"Meh."}]}"#, posts: posts)!
        XCTAssertEqual(r.overview, "Big day.")
        XCTAssertEqual(r.verdicts[posts[0].id], AiVerdict(importance: 5, why: "Huge."))
        XCTAssertEqual(r.verdicts[posts[2].id]?.importance, 1)
        XCTAssertNil(r.verdicts[posts[1].id])
    }

    func testFencedJsonWithWordsAround() {
        let posts = [p("a", 100), p("a", 50)]
        let r = parseDigestAi("Here you go:\n```json\n{\"items\":[{\"i\":1,\"importance\":3,\"why\":\"Ok.\"}]}\n```", posts: posts)!
        XCTAssertEqual(r.verdicts[posts[1].id]?.importance, 3)
        XCTAssertNil(r.overview)
    }

    func testGarbageIsAFailure() {
        let posts = [p("a", 100)]
        XCTAssertNil(parseDigestAi("I can't help with that.", posts: posts))
        XCTAssertNil(parseDigestAi("{not json", posts: posts))
        XCTAssertNil(parseDigestAi(#"{"overview":"x"}"#, posts: posts))
    }

    func testWrongIndicesAreSkipped() {
        let posts = [p("a", 100), p("a", 50)]
        let r = parseDigestAi(#"{"items":[{"i":9,"importance":5,"why":"x"},{"i":0,"importance":9,"why":"y"}]}"#, posts: posts)!
        XCTAssertEqual(r.verdicts.count, 1)
        XCTAssertEqual(r.verdicts[posts[0].id]?.importance, 5)
        XCTAssertNil(parseDigestAi(#"{"items":[{"i":7,"importance":5,"why":"x"}]}"#, posts: posts))
    }

    func testTheAiPicksWithItsWhy() {
        let big = p("a", 5000)
        let quiet = p("a", 12)
        let ai = DigestAi(overview: "Today…", verdicts: [quiet.id: AiVerdict(importance: 5, why: "Quietly important."), big.id: AiVerdict(importance: 1, why: "Noise.")])
        let d = mergeDigest(nil, day: "2027-01-15", candidates: ordinary("a", 10) + [big, quiet], readIds: [], size: .standard, now: now, ai: ai)
        XCTAssertEqual(d.items.map(\.post.id), [quiet.id])
        XCTAssertEqual(d.items[0].why, "Quietly important.")
        XCTAssertEqual(d.items[0].importance, 5)
        XCTAssertEqual(d.overview, "Today…")
        XCTAssertEqual(d.aiAt, now)
        XCTAssertEqual(d.judged[big.id]?.picked, false)
    }

    func testARefreshSendsOnlyNewPostsAndKeepsTheOverview() {
        let first = mergeDigest(nil, day: "2027-01-15", candidates: ordinary("a", 10) + [p("a", 5000)], readIds: [], size: .standard, now: now, ai: DigestAi(overview: "Morning.", verdicts: [:]))
        let cands = first.judged.keys.map { p("a", 10, id: $0) }
        let fresh = p("a", 900)
        XCTAssertEqual(digestPending(first, day: "2027-01-15", candidates: cands + [fresh], readIds: [], now: now + hour).map(\.id), [fresh.id])
        XCTAssertTrue(digestPending(first, day: "2027-01-15", candidates: cands, readIds: [], now: now + hour).isEmpty)
        let second = mergeDigest(first, day: "2027-01-15", candidates: cands + [fresh], readIds: [], size: .standard, now: now + hour, ai: DigestAi(overview: "Evening.", verdicts: [fresh.id: AiVerdict(importance: 3, why: "x")]))
        XCTAssertEqual(second.overview, "Morning.")
    }

    func testPostsReadBeforeJudgingArentSent() {
        let read = p("a", 900)
        XCTAssertFalse(digestPending(nil, day: "2027-01-15", candidates: ordinary("a", 10) + [read], readIds: [read.id], now: now).map(\.id).contains(read.id))
    }

    func testAFailedAiGoesByTheNumbers() {
        let big = p("a", 5000)
        let d = mergeDigest(nil, day: "2027-01-15", candidates: ordinary("a", 10) + [big], readIds: [], size: .standard, now: now, aiFailed: true)
        XCTAssertEqual(d.items.map(\.post.id), [big.id])
        XCTAssertTrue(d.aiFailed)
    }

    func testOrders() {
        func item(_ sub: String, _ score: Int, _ hoursOld: Int, _ notability: Double, _ importance: Int) -> DigestItem {
            DigestItem(post: p(sub, score, hoursOld: hoursOld), why: "", notability: notability, addedAt: now, importance: importance)
        }
        let a1 = item("a", 100, 1, 5, 2), a2 = item("a", 900, 9, 2, 4), b1 = item("b", 500, 5, 9, 1)
        let all = [a1, a2, b1]
        func ids(_ o: DigestOrder) -> [String] { orderDigest(all, o).flatMap { $0.items.map(\.post.id) } }
        XCTAssertEqual(ids(.notable), [b1, a1, a2].map(\.post.id))
        XCTAssertEqual(ids(.upvoted), [a2, a1, b1].map(\.post.id))
        XCTAssertEqual(ids(.newest), [a1, a2, b1].map(\.post.id))
        XCTAssertEqual(ids(.ai), [a2, a1, b1].map(\.post.id))
    }
}
