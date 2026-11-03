import WebKit
import XCTest
@testable import Ilay

/// Reddit Home's page reading against a saved page, in a real WKWebView. Nothing goes to Reddit.
@MainActor final class RedditHomeTests: XCTestCase {
    private func fixture() throws -> String {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "RedditHomeFixture", withExtension: "html"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func loader(html: String) -> RedditHomeLoader {
        let l = RedditHomeLoader()
        l.loadHome = { $0.loadHTMLString(html, baseURL: RedditHomeLoader.home) }
        return l
    }

    func testTheBlockRulesCompileInWebKitsRegexSubset() async throws {
        let list = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "IlayRedditHomeTest", encodedContentRuleList: RedditHomeLoader.blockRules)
        XCTAssertNotNil(list)
    }

    func testReadsThePostsInPageOrderAndSkipsAds() async throws {
        let l = loader(html: try fixture())
        // Fewer than the 10 a refresh wants: returns after the page stays quiet.
        var counts: [Int] = []
        let posts = try await l.next(restart: true, cookieHeader: "", onProgress: { counts.append($0) })
        await l.dispose()

        // ddd444 joined by the scroll that looks for more.
        XCTAssertEqual(posts.map(\.id), ["t3_aaa111", "t3_bbb222", "t3_ccc333", "t3_ddd444"])
        XCTAssertEqual(counts.last, 4)

        let image = posts[0]
        XCTAssertEqual(image.title, "A recommended picture")
        XCTAssertEqual(image.subreddit, "r/pics")
        XCTAssertEqual(image.subredditIcon, "https://styles.redditmedia.com/t5_pics/icon.png")
        XCTAssertEqual(image.author, "alice")
        XCTAssertEqual(image.score, 1234)
        XCTAssertEqual(image.comments, 56)
        XCTAssertEqual(image.createdUtc, Int(ISO8601DateFormatter().date(from: "2026-10-05T12:34:56Z")!.timeIntervalSince1970) * 1000)
        XCTAssertEqual(image.image, "https://preview.redd.it/aaa111.jpg?width=640")
        XCTAssertEqual(image.flair, "Art")
        XCTAssertEqual(image.reason, "Because you visited r/art")
        XCTAssertTrue(image.canShowFewer)

        let text = posts[1]
        XCTAssertEqual(text.author, "[deleted]")
        XCTAssertEqual(text.comments, 0)
        XCTAssertEqual(text.body, "The body of the post.")
        XCTAssertTrue(text.nsfw)
        XCTAssertTrue(text.spoiler)
        XCTAssertNil(text.reason, "a hidden context says nothing")
        XCTAssertFalse(text.canShowFewer, "from a subscription: Reddit doesn't offer it")

        XCTAssertEqual(posts[2].createdUtc, 0, "an unreadable date isn't a failure")
    }

    func testTheShowFewerIdsAreThoseOnThePage() async throws {
        let l = loader(html: try fixture())
        _ = try await l.next(restart: true, cookieHeader: "")
        XCTAssertEqual(l.showFewerIds, ["aaa111"])
        await l.dispose()
        XCTAssertTrue(l.showFewerIds.isEmpty)
    }

    func testARestartReadsThePageAnew() async throws {
        let l = loader(html: try fixture())
        let first = try await l.next(restart: true, cookieHeader: "")
        let again = try await l.next(restart: true, cookieHeader: "")
        await l.dispose()
        XCTAssertEqual(first.first?.id, "t3_aaa111")
        XCTAssertEqual(again.first?.id, "t3_aaa111", "a refresh starts over, the old posts aren't 'seen'")
    }

    func testSignedOutPageThrows() async throws {
        let html = try fixture().replacingOccurrences(of: #"user-logged-in="true""#, with: "")
        let l = loader(html: html)
        do {
            _ = try await l.next(restart: true, cookieHeader: "")
            XCTFail("expected HomeSignedOutException")
        } catch is HomeSignedOutException {}
        await l.dispose()
    }

    func testShowFewerOpensTheMenuThenPicksIt() async throws {
        let html = try fixture()
        let l = loader(html: html)
        _ = try await l.next(restart: true, cookieHeader: "")
        let picked = await l.showFewer("t3_aaa111")
        XCTAssertTrue(picked)
        let gone = await l.showFewer("t3_nothere")
        XCTAssertFalse(gone)
        await l.dispose()
    }

    func testAPageWithoutPostsGivesUpEarly() async throws {
        let l = loader(html: #"<html><body><shreddit-app user-logged-in="true"></shreddit-app></body></html>"#)
        let started = nowMillis()
        do {
            _ = try await l.next(restart: true, cookieHeader: "")
            XCTFail("expected HomeUnavailableException")
        } catch is HomeUnavailableException {}
        await l.dispose()
        XCTAssertLessThan(nowMillis() - started, 10_000, "not the whole 15s deadline")
    }

    func testGivesUpOnAFailedLoadOrAPageLoadedWithoutPosts() {
        XCTAssertTrue(RedditHomeLoader.givesUp(loadFailed: true, finishedAt: nil, now: 0))
        XCTAssertFalse(RedditHomeLoader.givesUp(loadFailed: false, finishedAt: nil, now: 60_000), "still loading")
        XCTAssertFalse(RedditHomeLoader.givesUp(loadFailed: false, finishedAt: 1_000, now: 5_000))
        XCTAssertTrue(RedditHomeLoader.givesUp(loadFailed: false, finishedAt: 1_000, now: 6_000))
    }

    func testAnOldDocumentReadsAsNil() {
        XCTAssertNil(HomePageRead.parse(nil))
        XCTAssertNil(HomePageRead.parse("null"))
        XCTAssertEqual(HomePageRead.parse("{not json")?.posts, [])
    }

    func testPagePostToPost() {
        func page(type: String, image: String? = nil, href: String = "") -> PagePost {
            PagePost(
                id: "t3_x", title: "T", subreddit: "r/pics", subredditIcon: nil, author: "a", score: 1, comments: 2, createdUtc: 3,
                type: type, permalink: "/r/pics/comments/x/", href: href, domain: "d", image: image, body: "b", flair: "F",
                nsfw: true, spoiler: false, reason: "why", canShowFewer: false
            )
        }
        let p = page(type: "text").toPost()
        XCTAssertEqual(p.id, "x")
        XCTAssertEqual(p.fullname, "t3_x")
        XCTAssertEqual(p.subreddit, "pics")
        XCTAssertEqual(p.subredditPrefixed, "r/pics")
        XCTAssertEqual(p.type, .selfPost)
        XCTAssertTrue(p.isSelf)
        XCTAssertEqual(p.url, "https://www.reddit.com/r/pics/comments/x/")
        XCTAssertEqual(p.linkFlair?.text, "F")
        XCTAssertEqual(p.feedReason, "why")
        XCTAssertTrue(p.over18)

        XCTAssertEqual(page(type: "image").toPost().type, .image)
        XCTAssertEqual(page(type: "gallery").toPost().type, .gallery)
        XCTAssertEqual(page(type: "link").toPost().type, .link)
        XCTAssertEqual(page(type: "crosspost", image: "i").toPost().type, .image, "an unknown type with a picture")
        XCTAssertEqual(page(type: "crosspost").toPost().type, .selfPost)

        let v = page(type: "video", href: "https://v.redd.it/abc").toPost()
        XCTAssertEqual(v.type, .video)
        XCTAssertEqual(v.hlsUrl, "https://v.redd.it/abc/HLSPlaylist.m3u8")
        XCTAssertNil(page(type: "video", href: "https://example.com/abc").toPost().hlsUrl)
    }

    func testBlendCursorCountsMissesAndGivesUp() {
        func next(_ prev: String?, _ r: BlendResult?, first: Bool = false) -> (String?, BlendState?) {
            let n = blendNext(previous: prev, result: r, firstPage: first)
            return (n.cursor, n.state)
        }
        // Still loading: holds its count; says so only on the first page.
        XCTAssertEqual(next(nil, nil, first: true).0, "m0")
        XCTAssertEqual(next(nil, nil, first: true).1, .loading)
        XCTAssertEqual(next("m1", nil).0, "m1")
        XCTAssertNil(next("m1", nil).1)
        // Posts clear the count.
        XCTAssertEqual(next("m2", .posts([])).0, "m0")
        // Up to 3 failures, 2 empty batches.
        XCTAssertEqual(next("m0", .failed).0, "m1")
        XCTAssertEqual(next("m1", .failed).0, "m2")
        XCTAssertNil(next("m2", .failed).0)
        XCTAssertEqual(next("m2", .failed).1, .unavailable(signedOut: false))
        XCTAssertEqual(next("m0", .empty).0, "m1")
        XCTAssertNil(next("m1", .empty).0)
        // Signed out: at once.
        XCTAssertNil(next("m0", .signedOut).0)
        XCTAssertEqual(next("m0", .signedOut).1, .unavailable(signedOut: true))
    }
}

/// The For You build against a stubbed network: the requests it makes, its cursors, its failures.
@MainActor final class ForYouEngineTests: XCTestCase {
    private func listing(_ prefix: String, count: Int = 3, after: String? = nil) -> String {
        let posts = (0..<count).map { #"{"kind":"t3","data":{"id":"\#(prefix)\#($0)","name":"t3_\#(prefix)\#($0)","title":"Title \#(prefix) \#($0)","subreddit":"\#(prefix)","author":"a","created_utc":\#(nowMillis() / 1000 - 3600),"url":"https://example.com/\#(prefix)/\#($0)","score":10,"num_comments":1}}"# }
        let cursor = after.map { #""\#($0)""# } ?? "null"
        return #"{"kind":"Listing","data":{"after":\#(cursor),"children":[\#(posts.joined(separator: ","))]}}"#
    }

    private var module: ForYouModule! // the engine doesn't keep its module alive

    private func engine(_ handler: @escaping (URLRequest) throws -> StubProtocol.Reply) -> ForYouEngine {
        StubProtocol.start(handler)
        module = ForYouModule(app)
        module.onUserChanged("") // the logged-out identity: no seeding, no saved page
        module.engine.repo = RedditRepository(client: stubClient(oauthItems()).client)
        return module.engine
    }

    private func reply(_ r: URLRequest, best: String, rising: String, popular: String) -> StubProtocol.Reply {
        switch r.url!.path {
        case let p where p.hasSuffix("/best"): StubProtocol.Reply(body: best)
        case let p where p.hasSuffix("/rising"): StubProtocol.Reply(body: rising)
        case let p where p.hasSuffix("/popular/hot"): StubProtocol.Reply(body: popular)
        default: StubProtocol.Reply(body: listing("none", count: 0))
        }
    }

    func testFirstPageAsksEverySourceAndItsCursorGoesOnFromThere() async throws {
        let (best, rising, popular) = (listing("best", after: "b2"), listing("rising", after: "r2"), listing("popular"))
        let e = engine { [self] in reply($0, best: best, rising: rising, popular: popular) }

        let page = try await e.page(after: nil, loaded: [])
        XCTAssertFalse(page.items.isEmpty)
        XCTAssertEqual(e.progress, 9, "the deck's count: every post gathered")
        XCTAssertFalse(module.meta.isEmpty)
        XCTAssertEqual(StubProtocol.requests.first { $0.url!.path.hasSuffix("/best") }?.url?.queryParameter("limit"), "100")
        // popular ran out, so it's left out.
        let cursors = try XCTUnwrap(parseJsonOrNull(try XCTUnwrap(page.after)).obj())
        XCTAssertEqual(cursors["best"].str(), "b2")
        XCTAssertEqual(cursors["rising"].str(), "r2")
        XCTAssertNil(cursors["popular"])

        StubProtocol.start { [self] in reply($0, best: listing("best2"), rising: listing("rising2"), popular: listing("wrong")) }
        let second = try await e.page(after: page.after, loaded: page.items)
        let paths = StubProtocol.paths
        XCTAssertFalse(paths.contains { $0.hasSuffix("/popular/hot") }, "an exhausted source isn't asked again")
        let bestRequest = StubProtocol.requests.first { $0.url!.path.hasSuffix("/best") }
        XCTAssertEqual(bestRequest?.url?.queryParameter("after"), "b2")
        XCTAssertEqual(bestRequest?.url?.queryParameter("limit"), "50")
        XCTAssertTrue(second.items.contains { $0.subreddit == "best2" })
        XCTAssertTrue(Set(second.items.map(\.id)).isDisjoint(with: page.items.map(\.id)))
    }

    func testAFailedSourceKeepsItsPlace() async throws {
        let (rising, popular) = (listing("rising"), listing("popular"))
        let e = engine { [self] in
            if $0.url!.path.hasSuffix("/best") { return StubProtocol.Reply(status: 500, body: "{}") }
            return reply($0, best: "", rising: rising, popular: popular)
        }
        let page = try await e.page(after: nil, loaded: [])
        XCTAssertFalse(page.items.isEmpty)
        let cursors = parseJsonOrNull(try XCTUnwrap(page.after)).obj()
        XCTAssertEqual(cursors?["best"].str(), "", "a source that failed starts from the top next time")
    }

    func testOneSourceAnsweringIsNotAFailure() async throws {
        let e = engine { [self] in
            $0.url!.path.hasSuffix("/best") ? StubProtocol.Reply(body: listing("best", count: 0)) : StubProtocol.Reply(status: 500, body: "{}")
        }
        let page = try await e.page(after: nil, loaded: [])
        XCTAssertTrue(page.items.isEmpty, "nothing new: an empty page, not an error that retries the whole build")
    }

    func testARefreshReusesTheExploreListingAndSignedOutNeverAsksForSubscriptions() async throws {
        let e = engine { [self] in reply($0, best: listing("best"), rising: listing("rising"), popular: listing("popular")) }
        _ = try await e.page(after: nil, loaded: [])
        XCTAssertEqual(StubProtocol.paths.filter { $0.hasSuffix("/r/all/top") }.count, 1, "today's top across Reddit, to explore")
        XCTAssertFalse(StubProtocol.paths.contains { $0.contains("/subreddits/mine") })
        StubProtocol.start { [self] in reply($0, best: listing("best"), rising: listing("rising"), popular: listing("popular")) }
        _ = try await e.page(after: nil, loaded: [])
        XCTAssertFalse(StubProtocol.paths.contains { $0.hasSuffix("/r/all/top") }, "kept a few minutes")
        XCTAssertTrue(StubProtocol.paths.contains { $0.hasSuffix("/best") })
    }

    func testTheSeedIsMarkedDoneOnlyWhenItWorked() async throws {
        let user = app.session.username
        let key = userScopedKey(app.prefs, user, "fy_seeded")
        app.prefs.remove(key)
        defer { app.prefs.remove(key) }
        var e = engine { _ in StubProtocol.Reply(status: 500, body: "{}") }
        await e.seedIfNeeded(user: user)
        XCTAssertNil(app.prefs.getBool(key), "a failure is tried again next time")
        e = engine { [self] _ in StubProtocol.Reply(body: listing("liked")) }
        await e.seedIfNeeded(user: user)
        XCTAssertEqual(app.prefs.getBool(key), true)
    }

    func testEverySourceFailingIsAnErrorNotAnEmptyFeed() async {
        let e = engine { _ in StubProtocol.Reply(status: 500, body: "{}") }
        do {
            _ = try await e.page(after: nil, loaded: [])
            XCTFail("expected a failure")
        } catch {}
    }

    func testOnlyPostsForYouPlacedCountAsImpressions() {
        let module = ForYouModule(app)
        let user = "fytest_\(UUID().uuidString)"
        module.onUserChanged(user)
        defer { module.impressions.clear() }
        guard app.settings.value.trackHistory else { return }
        let home = Post.fromData(["id": "h", "subreddit": "pics", "title": "From Home"]).with { $0.feedReason = "Popular near you" }
        let mine = Post.fromData(["id": "f", "subreddit": "pics", "title": "From For You"]).with { $0.feedReason = "From r/pics" }
        module.meta = ["f": ForYouMeta(source: "best", discovery: false, position: 0, why: [])]
        module.forYouLearner.impression(home)
        module.forYouLearner.impression(mine)
        module.impressions.load(user) // saves the batch
        XCTAssertEqual(module.impressions.count("h"), 0, "a Reddit Home card isn't a For You impression")
        XCTAssertEqual(module.impressions.count("f"), 1, accuracy: 0.01)
    }

    func testEngagedCommunitiesOutsideTheTopFiveAreFetchedToo() async throws {
        let e = engine { [self] in reply($0, best: listing("best"), rising: listing("rising"), popular: listing("popular")) }
        module.interest.clear() // the seed test leaves its own communities here
        defer { module.interest.clear() }
        let subs = (0..<8).map { "eng\($0)" }
        module.interest.seed(Dictionary(uniqueKeysWithValues: subs.enumerated().map { ($1, 10.0 - Double($0)) }))
        _ = try await e.page(after: nil, loaded: [])
        let near = StubProtocol.paths.first { $0.contains("eng0") }
        for s in subs { XCTAssertTrue(near?.contains(s) == true, "\(s) in the one combined request") }
    }

    func testEngagementIsDwellOrMediaNotAnOpenAndCountsPerSourceAndSlot() {
        let module = ForYouModule(app)
        module.onUserChanged("fytest_\(UUID().uuidString)")
        defer {
            module.subStats.clear()
            module.typeStats.clear()
            module.metrics.clear()
            module.interest.clear()
        }
        guard app.settings.value.trackHistory else { return }
        let text = Post.fromData(["id": "t", "subreddit": "askx", "title": "A question"])
        let pic = Post.fromData(["id": "i", "subreddit": "picsx", "title": "A photo"])
        module.meta = [
            "t": ForYouMeta(source: "best", discovery: false, position: 2, why: []),
            "i": ForYouMeta(source: "explore", discovery: true, position: 31, why: []),
        ]
        let l = module.forYouLearner
        l.impression(text)
        l.impression(pic)
        l.open(text)
        XCTAssertEqual(module.subStats.value["askx"]?.engaged ?? 0, 0, "an open alone may be a bounce")
        l.dwell(text)
        XCTAssertEqual(module.subStats.value["askx"]?.engaged ?? 0, 1, accuracy: 0.01)
        l.viewMedia(pic)
        XCTAssertEqual(module.subStats.value["picsx"]?.engaged ?? 0, 1, accuracy: 0.01, "viewing the media is engagement")
        l.hidePost(pic)
        let t = module.metrics.totals()
        XCTAssertEqual(t["imp.src.best"], 1)
        XCTAssertEqual(t["open.src.best"], 1)
        XCTAssertEqual(t["open.primary"], 1)
        XCTAssertEqual(t["eng.src.best"], 1)
        XCTAssertEqual(t["eng.src.explore"], 1)
        XCTAssertEqual(t["hide.src.explore"], 1)
        XCTAssertEqual(t["imp.slot.0-9"], 1)
        XCTAssertEqual(t["imp.slot.30+"], 1)
    }

    func testLearnerCountsTheChangeOfAVoteNotEachVote() {
        let module = ForYouModule(app)
        module.onUserChanged("fytest_\(UUID().uuidString)")
        guard app.settings.value.trackHistory else { return }
        let p = Post.fromData(["id": "a", "subreddit": "pics", "title": "Cats"])
        let l = module.forYouLearner
        l.vote(p, from: 0, to: 1)
        let once = module.interest.weightFor("pics")
        l.vote(p, from: 1, to: 0)
        l.vote(p, from: 0, to: 1)
        XCTAssertEqual(module.interest.weightFor("pics"), once, accuracy: 0.01, "up → none → up nets one vote")
        l.open(p)
        let opened = module.interest.weightFor("pics")
        l.open(p)
        XCTAssertEqual(module.interest.weightFor("pics"), opened, "a passive signal counts once a session")
    }
}
