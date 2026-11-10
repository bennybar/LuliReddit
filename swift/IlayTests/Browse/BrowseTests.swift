import XCTest
@testable import Ilay

private func sub(_ name: String, members: Int = 0, fav: Bool = false) -> Subreddit {
    Subreddit(name: name, namePrefixed: name.hasPrefix("u_") ? "u/\(name.dropFirst(2))" : "r/\(name)", title: "", description: "", subscribers: members, userHasFavorited: fav)
}

private func post(_ id: String, title: String = "Title") -> Post {
    Post.fromData(json(#"{"id":"\#(id)","name":"t3_\#(id)","title":"\#(title)","subreddit":"swift","author":"a","permalink":"/r/swift/comments/\#(id)/"}"#))
}

private func comment(_ id: String, body: String = "Body") -> Comment {
    Comment.fromChild(json(#"{"kind":"t1","data":{"id":"\#(id)","name":"t1_\#(id)","body":"\#(body)","author":"a"}}"#), 0)
}

private func recent(_ name: String) -> RecentSubreddit {
    RecentSubreddit(name: name, namePrefixed: "r/\(name)", iconUrl: nil, subscribers: 5, visitedAt: 1)
}

final class ExploreSectionsTests: XCTestCase {
    private let list = [sub("favA", members: 10, fav: true), sub("Bravo", members: 30), sub("u_someone", members: 2), sub("charlie", members: 30)]

    private func sections(query: String = "", favOnly: Bool = false, sort: String = "default", visited: [RecentSubreddit] = [], list: [Subreddit]? = nil) -> [ExploreSection] {
        subscriptionSections(list: list ?? self.list, query: query, favOnly: favOnly, sort: sort, visited: visited)
    }

    func testDefaultViewGroupsRecentFavoritesFollowingAndTheRest() {
        let s = sections(visited: [recent("notjoined"), recent("BRAVO")])
        XCTAssertEqual(s.map(\.title), ["Recently visited", "Favorites", "Following", "Communities"])
        XCTAssertEqual(s[0].subs.map(\.name), ["notjoined", "Bravo"], "the joined one's own data, whatever case it was visited in")
        XCTAssertEqual(s[0].subs[1].subscribers, 30)
        XCTAssertEqual(s[1].subs.map(\.name), ["favA"])
        XCTAssertEqual(s[2].subs.map(\.name), ["u_someone"])
        XCTAssertEqual(s[3].subs.map(\.name), ["Bravo", "charlie"])
    }

    func testPlainListIsCalledSubscriptions() {
        XCTAssertEqual(sections(list: [sub("a")]).map(\.title), ["Subscriptions"])
    }

    func testNoSubscriptionsSaysSo() {
        let s = sections(list: [])
        XCTAssertEqual(s.map(\.title), ["Subscriptions"])
        XCTAssertEqual(s[0].empty, "You have no subscriptions yet")
        XCTAssertEqual(sections(visited: [recent("x")], list: []).map(\.title), ["Recently visited", "Subscriptions"])
    }

    func testFilterIsFlatAndCaseInsensitiveOnTheName() {
        let s = sections(query: "  BRA ")
        XCTAssertEqual(s.map(\.title), ["1 communities"])
        XCTAssertEqual(s[0].subs.map(\.name), ["Bravo"])
        XCTAssertEqual(sections(query: "nope")[0].empty, "No matches")
        XCTAssertTrue(sections(query: "nope")[0].subs.isEmpty)
    }

    func testFavoritesOnly() {
        XCTAssertEqual(sections(favOnly: true)[0].subs.map(\.name), ["favA"])
    }

    func testSorts() {
        XCTAssertEqual(sections(sort: "name")[0].subs.map(\.name), ["Bravo", "charlie", "favA", "u_someone"])
        XCTAssertEqual(sections(sort: "subscribers")[0].subs.map(\.name), ["Bravo", "charlie", "favA", "u_someone"], "equal counts keep their order")
    }
}

final class MultiredditOwnerTests: XCTestCase {
    private func multi(_ path: String) -> Multireddit { Multireddit(name: "n", displayName: "n", path: path, subreddits: []) }

    func testOwnerComesFromThePath() {
        XCTAssertEqual(multi("/user/Alice/m/stuff/").owner(fallback: "me"), "Alice")
    }

    func testAnythingElseIsTheSignedInUser() {
        XCTAssertEqual(multi("").owner(fallback: "me"), "me")
        XCTAssertEqual(multi("/r/foo/").owner(fallback: "me"), "me")
    }
}

final class HistoryFilterTests: XCTestCase {
    private let history = [
        HistoryEntry(id: "1", subreddit: "swift", title: "Actors explained", permalink: ""),
        HistoryEntry(id: "2", subreddit: "pics", title: "A cat", permalink: ""),
    ]

    func testByWordsInTitleOrSubreddit() {
        XCTAssertEqual(filterHistory(history, query: " ACTORS ", subreddit: nil).map(\.id), ["1"])
        XCTAssertEqual(filterHistory(history, query: "pic", subreddit: nil).map(\.id), ["2"])
        XCTAssertEqual(filterHistory(history, query: "", subreddit: nil).count, 2)
    }

    func testBySubreddit() {
        XCTAssertEqual(filterHistory(history, query: "", subreddit: "pics").map(\.id), ["2"])
        XCTAssertTrue(filterHistory(history, query: "actors", subreddit: "pics").isEmpty)
    }
}

@MainActor final class SearchViewModelTests: XCTestCase {
    /// Records what was asked; `gate`d queries wait until released.
    private final class Stub {
        // `async let` runs these off the main actor, side by side.
        private let lock = NSLock()
        var asked: [(q: String, after: String?, sort: String, time: String)] = []
        var subsAsked = 0
        var postsError: Error?
        var subsError: Error?
        var gates: [String: CheckedContinuation<Void, Never>] = [:]
        var gated: Set<String> = []

        var fetcher: SearchFetcher {
            SearchFetcher(
                posts: { [self] q, _, after, sort, time in
                    lock.withLock { asked.append((q, after, sort, time)) }
                    if gated.contains(q) {
                        await withCheckedContinuation { c in lock.withLock { gates[q] = c } }
                    }
                    if let postsError { throw postsError }
                    return Listing(items: [post("\(q)\(after ?? "")")], after: after == nil ? "next" : nil)
                },
                subreddits: { [self] q in
                    lock.withLock { subsAsked += 1 }
                    if let subsError { throw subsError }
                    return [sub("\(q)sub")]
                },
                users: { q in [RedditUser(name: "\(q)user", createdUtc: 0)] }
            )
        }
    }

    private func settle(_ vm: SearchViewModel) async {
        for _ in 0..<500 where vm.loading { try? await Task.sleep(for: .milliseconds(2)) }
    }

    private func model(_ stub: Stub, subreddit: String? = nil, prefs: Prefs = testPrefs(), username: String = "Me", track: Bool = true) -> SearchViewModel {
        SearchViewModel(subreddit: subreddit, prefs: prefs, username: username, fetcher: stub.fetcher, trackHistory: { track })
    }

    func testASearchFillsAllThreeTabs() async {
        let stub = Stub()
        let vm = model(stub)
        vm.search("  cats ")
        XCTAssertEqual(vm.query, "cats")
        await settle(vm)
        XCTAssertEqual(vm.posts?.state.items.map(\.id), ["cats"])
        XCTAssertEqual(vm.subs.map(\.name), ["catssub"])
        XCTAssertEqual(vm.users.map(\.name), ["catsuser"])
    }

    func testAnEmptySearchDoesNothing() {
        let vm = model(Stub())
        vm.search("   ")
        XCTAssertEqual(vm.query, "")
        XCTAssertNil(vm.posts)
    }

    func testRestrictedSkipsSubredditsAndUsers() async {
        let stub = Stub()
        let vm = model(stub, subreddit: "swift")
        vm.search("cats")
        await settle(vm)
        XCTAssertEqual(stub.subsAsked, 0)
        XCTAssertTrue(vm.subs.isEmpty)
        XCTAssertEqual(vm.posts?.state.items.count, 1)
    }

    func testAFailedSubredditSearchStaysOnItsTab() async {
        let stub = Stub()
        stub.subsError = RedditApiException(statusCode: 403)
        let vm = model(stub)
        vm.search("cats")
        await settle(vm)
        XCTAssertNotNil(vm.subsError)
        XCTAssertNil(vm.usersError)
        XCTAssertNil(vm.error)
        XCTAssertEqual(vm.posts?.state.items.count, 1)
        XCTAssertEqual(vm.users.count, 1)
    }

    func testAFailedPostSearchIsTheScreens() async {
        let stub = Stub()
        stub.postsError = RedditApiException(statusCode: 500)
        let vm = model(stub)
        vm.search("cats")
        await settle(vm)
        XCTAssertNotNil(vm.error)
    }

    func testASlowEarlierSearchDoesNotOverwriteANewerOne() async {
        let stub = Stub()
        stub.gated = ["slow"]
        let vm = model(stub)
        vm.search("slow")
        for _ in 0..<500 where stub.gates["slow"] == nil { try? await Task.sleep(for: .milliseconds(2)) }
        vm.search("fast")
        await settle(vm)
        XCTAssertEqual(vm.subs.map(\.name), ["fastsub"])
        stub.gates["slow"]?.resume()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(vm.subs.map(\.name), ["fastsub"], "the old search's tabs don't land")
        XCTAssertEqual(vm.posts?.state.items.map(\.id), ["fast"])
    }

    func testSortAndTimeRunTheSearchAgainWithoutARecent() async {
        let prefs = testPrefs()
        let stub = Stub()
        let vm = model(stub, prefs: prefs)
        vm.search("cats")
        await settle(vm)
        vm.search("dogs")
        await settle(vm)
        vm.setSort("top")
        await settle(vm)
        vm.setTime("week")
        await settle(vm)
        XCTAssertEqual(stub.asked.last?.q, "dogs")
        XCTAssertEqual(stub.asked.last?.sort, "top")
        XCTAssertEqual(stub.asked.last?.time, "week")
        XCTAssertEqual(vm.recent, ["dogs", "cats"], "only typed searches are recents")
    }

    func testPagingContinuesTheSameSearch() async {
        let stub = Stub()
        let vm = model(stub)
        vm.search("cats")
        await settle(vm)
        vm.posts?.loadMore()
        for _ in 0..<500 where vm.posts?.state.items.count != 2 { try? await Task.sleep(for: .milliseconds(2)) }
        XCTAssertEqual(stub.asked.last?.after, "next")
        XCTAssertEqual(stub.subsAsked, 1, "only the first page brings the other tabs")
    }

    func testClearGoesBackToEmptyAndDropsAnInFlightSearch() async {
        let stub = Stub()
        stub.gated = ["slow"]
        let vm = model(stub)
        vm.search("slow")
        for _ in 0..<500 where stub.gates["slow"] == nil { try? await Task.sleep(for: .milliseconds(2)) }
        vm.clear()
        XCTAssertEqual(vm.query, "")
        XCTAssertNil(vm.posts)
        stub.gates["slow"]?.resume()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(vm.subs.isEmpty)
    }

    func testRecentsNewestFirstOnceAndCappedAt12() {
        let prefs = testPrefs()
        let vm = model(Stub(), prefs: prefs)
        for i in 0..<14 { vm.search("q\(i)") }
        vm.search("q5")
        XCTAssertEqual(vm.recent.count, 12)
        XCTAssertEqual(vm.recent.first, "q5")
        XCTAssertEqual(vm.recent.filter { $0 == "q5" }.count, 1)
        XCTAssertEqual(prefs.getStringList("recent_searches_me"), vm.recent, "per account, in the same key as Kotlin's and Flutter's")
    }

    func testNoRecentsWhileTrackingIsOff() {
        let prefs = testPrefs()
        let vm = model(Stub(), prefs: prefs, track: false)
        vm.search("cats")
        XCTAssertTrue(vm.recent.isEmpty)
        XCTAssertFalse(prefs.contains("recent_searches_me"))
    }

    // #149: a community or user opened from the results takes its search's place in
    // Recent, once, with its picture; one entry can be removed.
    func testAnOpenedResultReplacesItsSearchInRecent() async {
        let vm = model(Stub())
        vm.search("dogs")
        vm.search("samsung")
        await settle(vm)
        vm.rememberOpened(kind: "r", name: "samsunggalaxy", icon: "https://i/x.png")
        vm.rememberOpened(kind: "r", name: "SamsungGalaxy", icon: nil)
        XCTAssertEqual(vm.recent.count, 2)
        let top = RecentSearch(vm.recent[0])
        XCTAssertEqual(top.kind, "r")
        XCTAssertEqual(top.name, "SamsungGalaxy")
        XCTAssertEqual(top.label, "r/SamsungGalaxy")
        XCTAssertEqual(RecentSearch(vm.recent[1]).name, "dogs")
        XCTAssertNil(RecentSearch(vm.recent[1]).kind)
        vm.removeRecent(vm.recent[0])
        XCTAssertEqual(vm.recent, ["dogs"])
    }

    func testClearRecent() {
        let prefs = testPrefs()
        let vm = model(Stub(), prefs: prefs)
        vm.search("cats")
        vm.clearRecent()
        XCTAssertTrue(vm.recent.isEmpty)
        XCTAssertFalse(prefs.contains("recent_searches_me"))
    }

    func testTheOldSharedRecentsMoveToTheAccount() {
        let prefs = testPrefs()
        prefs.setStringList("recent_searches", ["old"])
        let vm = model(Stub(), prefs: prefs)
        XCTAssertEqual(vm.recent, ["old"])
        XCTAssertFalse(prefs.contains("recent_searches"))
        XCTAssertEqual(prefs.getStringList("recent_searches_me"), ["old"])
    }

    func testAnonymousKeepsTheBareKey() {
        let prefs = testPrefs()
        prefs.setStringList("recent_searches", ["old"])
        let vm = model(Stub(), prefs: prefs, username: "")
        XCTAssertEqual(vm.recent, ["old"])
        XCTAssertTrue(prefs.contains("recent_searches"))
    }
}

@MainActor final class SavedModelTests: XCTestCase {
    private func settled(_ source: PagedSource<SavedItem>) async {
        for _ in 0..<500 where source.state.loading { try? await Task.sleep(for: .milliseconds(2)) }
    }

    /// `load` has no return to await from outside: give the re-applied list its turn.
    private func turn() async { try? await Task.sleep(for: .milliseconds(30)) }

    func testVisibleByTypeWordsAndRemoved() {
        let items: [SavedItem] = [.post(post("p", title: "Hello Cats")), .comment(comment("c", body: "about CATS")), .post(post("q", title: "Dogs"))]
        func ids(query: String = "", type: String = "all", removed: Set<String> = []) -> [String] {
            SavedModel.visible(items, query: query, type: type, removed: removed).map(\.fullname)
        }
        XCTAssertEqual(ids(), ["t3_p", "t1_c", "t3_q"])
        XCTAssertEqual(ids(type: "posts"), ["t3_p", "t3_q"])
        XCTAssertEqual(ids(type: "comments"), ["t1_c"])
        XCTAssertEqual(ids(query: " cats "), ["t3_p", "t1_c"])
        XCTAssertEqual(ids(query: "cats", type: "posts"), ["t3_p"])
        XCTAssertEqual(ids(removed: ["t3_p"]), ["t1_c", "t3_q"])
    }

    func testVisibleHidesNsfwPostsAndCommentsOnThem() {
        var nsfwPost = post("n")
        nsfwPost.over18 = true
        var nsfwComment = comment("m")
        nsfwComment.over18 = true
        let items: [SavedItem] = [.post(post("p")), .post(nsfwPost), .comment(comment("c")), .comment(nsfwComment)]
        XCTAssertEqual(SavedModel.visible(items, query: "", type: "all", removed: []).count, 4)
        XCTAssertEqual(SavedModel.visible(items, query: "", type: "all", removed: [], hideNsfw: true).map(\.fullname), ["t3_p", "t1_c"])
    }

    func testCommentReadsItsPostsNsfwFlag() {
        XCTAssertTrue(Comment.fromChild(json(#"{"kind":"t1","data":{"id":"x","body":"b","over_18":true}}"#), 0).over18)
        XCTAssertFalse(comment("y").over18)
    }

    func testChangingTheFilterDoesNotAskRedditAgain() async {
        var fetched = 0
        let model = SavedModel { _ in
            fetched += 1
            return Listing(items: [.post(post("p")), .comment(comment("c"))], after: nil)
        }
        model.source.start()
        await settled(model.source)
        XCTAssertEqual(model.source.state.items.count, 2)
        model.setType("comments")
        await turn()
        XCTAssertEqual(model.source.state.items.map(\.fullname), ["t1_c"])
        model.setType("all")
        await turn()
        XCTAssertEqual(model.source.state.items.count, 2)
        XCTAssertEqual(fetched, 1)
    }

    func testAFilterSetBeforeTheFirstPageStillLoadsIt() async {
        let model = SavedModel { _ in Listing(items: [.post(post("p")), .comment(comment("c"))], after: nil) }
        model.setType("posts")
        model.source.start()
        await settled(model.source)
        XCTAssertEqual(model.source.state.items.map(\.fullname), ["t3_p"])
    }

    func testAPullStillAsksReddit() async {
        var fetched = 0
        let model = SavedModel { _ in
            fetched += 1
            return Listing(items: [.post(post("p\(fetched)"))], after: nil)
        }
        model.source.start()
        await settled(model.source)
        await model.source.load().value
        XCTAssertEqual(fetched, 2)
        XCTAssertEqual(model.source.state.items.map(\.fullname), ["t3_p2"])
    }

    func testRemovedGoesAtOnceAndCanComeBack() async {
        let model = SavedModel { _ in Listing(items: [.post(post("p")), .post(post("q"))], after: nil) }
        model.source.start()
        await settled(model.source)
        model.setRemoved("t3_p", true)
        await turn()
        XCTAssertEqual(model.source.state.items.map(\.fullname), ["t3_q"])
        model.setRemoved("t3_p", false)
        await turn()
        XCTAssertEqual(model.source.state.items.map(\.fullname), ["t3_p", "t3_q"])
    }

    func testPagesKeepComingAfterAFilterAndAreNarrowedToo() async {
        let model = SavedModel { after in
            after == nil
                ? Listing(items: [.post(post("p"))], after: "2")
                : Listing(items: [.comment(comment("c")), .post(post("q"))], after: nil)
        }
        model.source.start()
        await settled(model.source)
        model.setType("posts")
        await turn()
        XCTAssertEqual(model.source.state.after, "2", "the cursor survives re-applying")
        model.source.loadMore()
        await turn()
        XCTAssertEqual(model.source.state.items.map(\.fullname), ["t3_p", "t3_q"])
    }

    func testFillsUpToAScreenfulWithinABound() async {
        var pages = 0
        let model = SavedModel { after in
            pages += 1
            return Listing(items: (0..<100).map { .comment(comment("c\(pages)x\($0)")) }, after: "more")
        }
        model.setType("posts")
        model.source.start()
        await settled(model.source)
        for _ in 0..<10 {
            model.fillIfShort()
            await turn()
        }
        XCTAssertEqual(pages, 5, "stops at 500 loaded rows when nothing matches")
    }
}
