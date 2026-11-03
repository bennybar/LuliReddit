import XCTest
@testable import Ilay

/// Port of the Flutter build's test/for_you_ranker_test.dart.
final class ForYouRankerTests: XCTestCase {
    private let now = 1_791_460_800_000 // 2026-10-08T12:00:00Z
    private var n = 0

    private func p(_ sub: String, _ title: String, score: Int = 500, hoursOld: Double = 3.0, url: String? = nil, ratio: Double? = 0.9) -> Post {
        let id = "p\(n)"
        n += 1
        // created_utc is whole seconds, as Reddit sends it.
        let created = (now - Int((hoursOld * 60).rounded()) * 60_000) / 1000 * 1000
        return Post(id: id, fullname: "t3_\(id)", title: title, subreddit: sub, subredditPrefixed: "r/\(sub)", author: "a", score: score, numComments: 0, upvoteRatio: ratio, createdUtc: created, permalink: "/r/\(sub)/comments/\(id)/", url: url ?? "https://www.reddit.com/r/\(sub)/comments/\(id)/", domain: "", type: url == nil ? .selfPost : .link, isSelf: url == nil)
    }

    private func c(_ ps: [Post], _ src: String = "best") -> [Candidate] { ps.map { Candidate(post: $0, source: src) } }

    func testAStronglyDislikedTopicNeverFlipsTheOrdering() {
        let fav = p("formula1", "Election chaos in the paddock election votes", hoursOld: 72.0)
        let disc = p("random", "Some unrelated discovery post", hoursOld: 72.0)
        let r = rankForYou(c([fav, disc]), RankInputs(favourites: ["formula1"], subscribed: ["formula1"], keywordScore: { $0.contains("Election") ? -6.0 : 0.0 }, now: now))
        XCTAssertEqual(r.ranked.first?.id, fav.id, "favourite × 4 must still beat discovery × 0.4")
    }

    func testAnOpenedPostRanksBelowAnUnopenedTwin() {
        let opened = p("a", "Twin post one")
        let fresh = p("a", "Twin post two")
        let r = rankForYou(c([opened, fresh]), RankInputs(subscribed: ["a"], keywordScore: { _ in -6.0 }, openedAt: [opened.id: now - 3600 * 1000], now: now))
        XCTAssertEqual(r.ranked.first?.id, fresh.id)
    }

    func testNegativeInterestAndLessFromActuallyDemote() {
        // Distinct titles, or the same-story rule would merge them.
        let words = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot"]
        let news = words.map { p("news", "Report \($0)") }
        let pics = words.map { p("pics", "Photo \($0)") }
        func newsInTop6(_ i: RankInputs) -> Int { rankForYou(c(news + pics), i).ranked.prefix(6).filter { $0.subreddit == "news" }.count }
        let subs: Set<String> = ["news", "pics"]
        let neutral = newsInTop6(RankInputs(subscribed: subs, now: now))
        let learnedLess = newsInTop6(RankInputs(subscribed: subs, interest: ["news": -8.0], now: now))
        let askedLess = newsInTop6(RankInputs(subscribed: subs, explicit: ExplicitPrefs(subs: ["news": -1]), now: now))
        XCTAssertLessThan(learnedLess, neutral)
        XCTAssertLessThan(askedLess, neutral)
    }

    func testSameLinkInTwoPlacesIsKeptOnce() {
        let a = p("tech", "Big article", url: "https://www.example.com/x?utm_source=r")
        let b = p("news", "Big article again", url: "https://example.com/x")
        XCTAssertEqual(rankForYou(c([a, b]), RankInputs(subscribed: ["tech", "news"], now: now)).ranked.count, 1)
    }

    func testSameStorySecondCopySpacedOutThirdDropped() {
        let story = ["a", "b", "c"].map { p($0, "Starship launch succeeds orbital flight test today") }
        let filler = (0..<30).map { p("f\($0)", "Filler post about thing\($0)") }
        let r = rankForYou(c(story + filler), RankInputs(subscribed: Set(["a", "b", "c"] + (0..<30).map { "f\($0)" }), now: now))
        let pos = r.ranked.indices.filter { r.ranked[$0].title.hasPrefix("Starship") }
        XCTAssertEqual(pos.count, 2)
        XCTAssertGreaterThanOrEqual(pos[1] - pos[0], 15)
    }

    func testDiversityNoLongRunsFromOneSubredditOverflowCarriesOver() {
        // One subreddit with the strongest posts, and plenty of alternatives.
        let big = (0..<20).map { p("big", "Big item \($0)", score: 5000 + $0 * 100) }
        let small = (0..<20).map { p("s\($0)", "Small item \($0)", score: 50) }
        let r = rankForYou(c(big + small), RankInputs(subscribed: Set(["big"] + (0..<20).map { "s\($0)" }), now: now), pageSize: 20)
        var run = 1
        var longest = 1
        for i in 1..<r.ranked.count {
            run = r.ranked[i].subreddit == r.ranked[i - 1].subreddit ? run + 1 : 1
            longest = max(longest, run)
        }
        XCTAssertLessThanOrEqual(longest, 2)
        XCTAssertFalse(r.leftovers.isEmpty)
    }

    func testExplanationsComeFromWhatDroveTheScore() {
        let x = p("formula1", "Verstappen wins again")
        let r = rankForYou(c([x]), RankInputs(subscribed: ["formula1"], explicit: ExplicitPrefs(topics: ["verstappen": 1]), now: now))
        XCTAssertTrue(r.ranked[0].feedReason!.contains("verstappen"))
        XCTAssertFalse(r.meta[x.id]!.why.isEmpty)
    }

    func testTokenizerHebrewAcronymsAccents() {
        XCTAssertTrue(titleKeywords("הבחירות לכנסת בשבוע הבא").contains("בחירות"))
        let k = titleKeywords("F1 and NBA news on PS5")
        XCTAssertTrue(k.contains("f1") && k.contains("nba") && k.contains("ps5"))
        XCTAssertTrue(titleKeywords("New Pokémon game announced").contains("pokémon"))
        XCTAssertFalse(titleKeywords("this is just the help").contains("this"))
    }

    private func title(_ i: Int) -> String { "w\(i)alpha w\(i)beta w\(i)gamma w\(i)delta" }

    func testTheFamiliarDiscoverSettingChangesHowMuchDiscoveryIsPlaced() {
        // 60 subscribed posts across 12 subs, 60 discovery ones across 12 others.
        // Distinct titles (shared words would make them one "story", allowed twice).
        let pool = c((0..<60).map { p("mine\($0 % 12)", title($0)) }) + c((0..<60).map { p("new\($0 % 12)", title(100 + $0)) }, "popular")
        let subs = Set((0..<12).map { "mine\($0)" })
        func discoveryShare(_ mix: Int) -> Int {
            let r = rankForYou(pool, RankInputs(subscribed: subs, discoveryMix: mix, now: now), pageSize: 40)
            return r.ranked.filter { r.meta[$0.id]?.discovery == true }.count
        }
        let familiar = discoveryShare(-2)
        let balanced = discoveryShare(0)
        let discover = discoveryShare(2)
        XCTAssertLessThan(familiar, balanced)
        XCTAssertLessThan(balanced, discover)
    }

    func testPostTypesYouOpenALotRankHigher() {
        let text = p("pics", title(1))
        let link = p("pics", title(2), url: "https://example.com/a")
        // You open most link posts and almost no text posts.
        let r = rankForYou(c([text, link]), RankInputs(subscribed: ["pics"], typeStats: ["link": (40.0, 30.0), "text": (40.0, 1.0)], now: now))
        XCTAssertEqual(r.ranked.first?.id, link.id)
    }

    func testALivelyDiscussionRanksAboveASilentTwin() {
        let busy = p("pics", title(3)).with { $0.numComments = 400 }
        let quiet = p("pics", title(4)).with { $0.numComments = 0 }
        let r = rankForYou(c([quiet, busy]), RankInputs(subscribed: ["pics"], now: now))
        XCTAssertEqual(r.ranked.first?.id, busy.id)
    }

    func testBlendARedditHomePickFromASubYouDontFollowBeatsPlainDiscoveryAndSaysWhy() {
        let fromHome = p("watches", title(5))
        let fromPopular = p("watches", title(6))
        let r = rankForYou(c([fromHome], "home") + c([fromPopular], "popular"), RankInputs(now: now))
        XCTAssertEqual(r.ranked.first?.id, fromHome.id)
        XCTAssertEqual(r.meta[fromHome.id]?.discovery, true, "a community you don't follow stays discovery, even when Reddit recommends it")
        XCTAssertTrue(r.ranked[0].feedReason!.hasPrefix("Recommended by Reddit"))
    }

    func testBlendAHomePostFromASubYouFollowSaysItCameFromYourRedditHome() {
        let x = p("running", title(7))
        let r = rankForYou(c([x], "home"), RankInputs(subscribed: ["running"], now: now))
        XCTAssertEqual(r.ranked[0].feedReason, "In your Reddit Home · r/running")
    }

    func testBlendAtMostFamiliarAFloodOfUnfamiliarHomePicksStaysLimited() {
        let subs = Set((0..<10).map { "mine\($0)" })
        let pool = c((0..<40).map { p("mine\($0 % 10)", title($0)) }) + c((0..<40).map { p("strange\($0 % 10)", title(100 + $0)) }, "home")
        let r = rankForYou(pool, RankInputs(subscribed: subs, discoveryMix: -2, blendReddit: 1, now: now), pageSize: 40)
        XCTAssertLessThanOrEqual(r.ranked.filter { $0.subreddit.hasPrefix("strange") }.count, 4)
    }

    func testBlendMostlyRedditGivesYourHomeMoreSpotsThanMostlyIlay() {
        let subs = Set((0..<10).map { "mine\($0)" })
        // Same communities from both sources; Home's are a little less popular.
        let pool = c((0..<40).map { p("mine\($0 % 10)", title($0)) }) + c((0..<40).map { p("mine\($0 % 10)", title(200 + $0), score: 300) }, "home")
        func homeCount(_ preset: Int) -> Int {
            let r = rankForYou(pool, RankInputs(subscribed: subs, blendReddit: preset, now: now), pageSize: 30)
            return r.ranked.filter { r.meta[$0.id]?.source == "home" }.count
        }
        XCTAssertLessThan(homeCount(0), homeCount(2))
    }

    func testAMissingUpvoteRatioIsNeutralNotZero() {
        let missing = p("pics", title(8), ratio: nil)
        let poor = p("pics", title(9), ratio: 0.5)
        let r = rankForYou(c([poor, missing]), RankInputs(subscribed: ["pics"], now: now))
        XCTAssertEqual(r.ranked.first?.id, missing.id, "a Home card without a ratio isn't scored as a 0 ratio")
    }

    func testEachImpressionCosts45Percent() {
        let seen = p("pics", title(10))
        let r = rankForYou(c([seen]), RankInputs(subscribed: ["pics"], impressions: { _ in 1.0 }, now: now))
        XCTAssertTrue(r.meta[seen.id]!.why.contains("Seen 1× before (×0.55)"))
    }

    func testAFastRisingDiscoveryPostGetsAHigherBase() {
        // Each alone in its community, so only the pool-wide speed tells them apart;
        // the slow one is newer (recency alone used to put it first).
        let fast = p("big", title(11), score: 20_000, hoursOld: 3.0)
        let slow = p("small", title(12), score: 10, hoursOld: 1.0)
        let r = rankForYou(c([slow, fast], "explore"), RankInputs(now: now))
        XCTAssertEqual(r.ranked.first?.id, fast.id)
    }

    func testFamiliarStillPlacesSomeDiscovery() {
        let pool = c((0..<60).map { p("mine\($0 % 12)", title($0)) }) + c((0..<60).map { p("new\($0 % 12)", title(100 + $0)) }, "explore")
        let r = rankForYou(pool, RankInputs(subscribed: Set((0..<12).map { "mine\($0)" }), discoveryMix: -2, now: now), pageSize: 30)
        XCTAssertGreaterThanOrEqual(r.ranked.filter { r.meta[$0.id]?.discovery == true }.count, 2, "one in 15 at most familiar (was one in 20)")
    }

    func testACommunityYouEngageWithButDontFollowStartsNearASubscription() {
        let engaged = p("engaged", title(50))
        let mine = p("mine", title(51))
        let r = rankForYou(c([mine, engaged]), RankInputs(subscribed: ["mine"], interest: ["engaged": 6.0], now: now))
        XCTAssertEqual(r.ranked.first?.id, engaged.id, "base 2.3 × its interest beats a plain subscription (base 0.4 lost)")
        XCTAssertEqual(r.ranked.first?.feedReason, "Because you engage with r/engaged")
        XCTAssertEqual(r.meta[engaged.id]?.why.first, "Because you engage with r/engaged (you don't follow it)")
    }

    func testBlendTheTopOfYourHomeCountsUpTo30Percent() {
        let top = p("pics", title(60))
        let r = rankForYou([Candidate(post: top, source: "home", homePos: 0.0)], RankInputs(subscribed: ["pics"], now: now))
        XCTAssertTrue(r.meta[top.id]!.why.contains { $0.hasPrefix("In your Reddit Home") && $0.hasSuffix("(×1.6)") })
    }

    func testAnUnknownDateIsNeutralNotAncient() {
        let undated = p("pics", title(40)).with { $0.createdUtc = 0 }
        let old = p("pics", title(41), hoursOld: 72.0)
        let r = rankForYou(c([old, undated]), RankInputs(subscribed: ["pics"], now: now))
        XCTAssertEqual(r.ranked.first?.id, undated.id)
    }

    func testAStoryYouReadLatelyIsDemotedNotDropped() {
        let again = p("space", "Starship launch succeeds orbital flight test")
        let other = p("space", title(70))
        let r = rankForYou(c([again, other]), RankInputs(subscribed: ["space"], readTitles: ["Starship launch succeeds orbital flight test today"], now: now))
        XCTAssertEqual(r.ranked.map(\.id), [other.id, again.id])
        XCTAssertEqual(r.ranked.last?.feedReason, "You read about this already")
        XCTAssertTrue(r.meta[again.id]!.why.contains("You read about this already (×0.3)"))
    }

    func testADiscoverySlotGoesToTheTopicalPostBeforeTheBigOne() {
        let filler = (0..<10).map { p("mine\($0)", title(80 + $0)) }
        let niche = p("niche", "nichealpha nichebeta nichegamma nichedelta", score: 20)
        let big = p("popularsub", title(99), score: 50_000)
        let r = rankForYou(c(filler) + c([niche, big], "popular"), RankInputs(subscribed: Set((0..<10).map { "mine\($0)" }), keywordScore: { $0.hasPrefix("niche") ? 3.0 : 0.0 }, now: now))
        let ids = r.ranked.map(\.id)
        XCTAssertEqual(ids.firstIndex(of: niche.id), 5, "the first discovery slot (the 6th)")
        XCTAssertLessThan(ids.firstIndex(of: niche.id)!, ids.firstIndex(of: big.id)!)
    }

    func testNormalisedUrl() {
        func u(_ s: String, isSelf: Bool = false) -> String? { normalisedUrl(post().with { $0.url = s; $0.isSelf = isSelf }) }
        XCTAssertEqual(u("https://WWW.Example.com/a?b=1&utm_x=2&a=3#f"), "example.com/a?a=3&b=1")
        XCTAssertEqual(u("http://example.com"), "example.com/")
        XCTAssertNil(u("/r/x/comments/y"))
        XCTAssertNil(u("https://example.com/a", isSelf: true))
    }
}

@MainActor
final class ForYouReviewTests: XCTestCase {
    func testCommonWordMustBeCountedInEveryDocument() {
        let store = DocFreqStore(prefs: testPrefs())
        store.load("alice")
        store.observe(Array(repeating: "Commonword", count: 100))
        XCTAssertEqual(store.state["commonword"]!, 100.0, accuracy: 0.001)
        XCTAssertEqual(store.idf("commonword"), 0.2, accuracy: 0.001)
        XCTAssertEqual(store.idfFunction()("commonword"), 0.2, accuracy: 0.001)
    }

    func testLoadingThenLearningMustNotDecayAnOldWeightTwice() {
        let prefs = testPrefs()
        let old = nowMillis() - 10 * 86_400_000
        prefs.setString("interest_weights_alice", #"{"_ts":\#(old),"oldsub":10.0}"#)
        let store = InterestStore(prefs: prefs, trackHistory: { true })
        store.load("alice")
        let justLoaded = store.weightFor("oldsub")
        XCTAssertLessThan(justLoaded, 10)
        store.bump("newsub", 1.0)
        XCTAssertEqual(store.weightFor("oldsub"), justLoaded, accuracy: 0.001)
    }

    func testPendingImpressionsMustNotMoveToAnotherAccount() {
        let prefs = testPrefs()
        let store = ImpressionStore(prefs: prefs, trackHistory: { true })
        store.load("alice")
        store.record("alice_post")
        store.load("bob")
        XCTAssertEqual(store.count("alice_post"), 0.0, accuracy: 0.001)
        store.load("alice")
        XCTAssertEqual(store.count("alice_post"), 1.0, accuracy: 0.01, "saved under the account that saw it")
    }

    func testAnImpressionCountsOncePerFeedBuildAndTheLastTopIsKept() {
        let prefs = testPrefs()
        let store = ImpressionStore(prefs: prefs, trackHistory: { true })
        store.load("alice")
        store.record("p")
        store.record("p") // same build: once
        store.newFeed()
        store.record("p") // the next build: again
        store.setLastTop((0..<12).map { "t\($0)" })
        store.load("alice") // saves, then reads back as a new launch would
        XCTAssertEqual(store.count("p"), 2.0, accuracy: 0.01)
        XCTAssertEqual(store.lastTop, (0..<10).map { "t\($0)" })
        store.load("bob")
        XCTAssertTrue(store.lastTop.isEmpty, "per account")
    }

    func testThirdStoryMustStayExcludedAcrossPages() {
        let title = "Starship launch succeeds orbital flight test"
        let p = post("third", title: title, sub: "space").with { $0.createdUtc = 1000; $0.isSelf = true; $0.type = .selfPost; $0.url = "/x" }
        let result = rankForYou([Candidate(post: p, source: "best")], RankInputs(subscribed: ["space"], previousTitles: [title, title], now: 3_600_000))
        XCTAssertTrue(result.ranked.isEmpty, "Two previous copies should exclude a third")
    }

    func testDecayFactor() {
        XCTAssertEqual(decayFactor(nil, perDay: 0.5), 1.0)
        XCTAssertEqual(decayFactor(0, perDay: 0.5, now: 86_400_000), 0.5, accuracy: 0.0001)
        XCTAssertEqual(decayFactor(100, perDay: 0.5, now: 50), 1.0)
    }

    func testKeywordEvictionKeepsTheWordsJustLearned() {
        let prefs = testPrefs()
        let store = KeywordStore(prefs: prefs, trackHistory: { true })
        store.load("a")
        store.seedTitles((0..<420).map { "uniqueword\($0)" }, 1.0)
        XCTAssertEqual(store.value.count, 400)
        store.bumpTitle("brandnewword", 1.0)
        XCTAssertNotNil(store.value["brandnewword"])
        XCTAssertEqual(store.value.count, 400)
        XCTAssertEqual(store.scoreTitle("brandnewword"), store.scorer(idf: nil)("brandnewword"))
    }

    func testTrackingOffLearnsNothing() {
        let store = InterestStore(prefs: testPrefs(), trackHistory: { false })
        store.bump("pics", 3)
        XCTAssertTrue(store.value.isEmpty)
    }

    func testSeederRoundTrip() async {
        let dir = tempDir()
        let raw: JsonElement = ["id": "a", "title": "Hello"]
        let p = Post.fromData(raw).with { $0.feedReason = "Because" }
        await saveForYouPage(user: "Bob", posts: [p], raw: { _ in raw }, dir: dir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("foryou_bob.json").path))
        let time = await savedPageTime(user: "Bob", dir: dir)
        XCTAssertNotNil(time)
        let back = await loadForYouPage(user: "Bob", opened: [], dir: dir)
        XCTAssertEqual(back?.first?.feedReason, "Because")
        let none = await loadForYouPage(user: "Bob", opened: ["a"], dir: dir)
        XCTAssertNil(none, "only opened posts left: no page")
    }
}
