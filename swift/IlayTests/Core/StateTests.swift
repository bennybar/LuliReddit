import XCTest
@testable import Ilay

final class ContentFiltersTests: XCTestCase {
    func testKeywordsMatchWholeWordsInAnyCaseAndScript() {
        let f = ContentFilters(keywords: ["cat", "c++", "שלום"])
        XCTAssertTrue(f.hides(Post.fromData(json(#"{"id":"a","title":"My CAT is cute","subreddit":"x"}"#))))
        XCTAssertFalse(f.hides(post(title: "Summer vacation")))
        XCTAssertTrue(f.hides(post(title: "Learning C++ today")))
        XCTAssertTrue(f.hides(post(title: "אמרתי שלום לכולם")))
        XCTAssertFalse(f.hides(post(title: "nothing here")))
    }

    func testKeywordsMatchWholeWordsOnlyInAnyScript() {
        let f = ContentFilters(keywords: ["cat", "מלחמה"])
        XCTAssertTrue(f.hides(post(title: "My cat sleeps")))
        XCTAssertTrue(f.hides(post(title: "Cat!")))
        XCTAssertFalse(f.hides(post(title: "Vacation photos")))
        XCTAssertFalse(f.hides(post(title: "Category theory")))
        XCTAssertTrue(f.hides(post(title: "עדכון מלחמה היום")))
    }

    func testSubredditFilterSparesTheSubredditsOwnPage() {
        let f = ContentFilters(subreddits: ["politics"])
        let p = post(title: "Hi", sub: "Politics")
        XCTAssertTrue(f.hides(p))
        XCTAssertFalse(f.hides(p, viewingSubreddit: "politics"))
    }

    func testHideNsfw() {
        XCTAssertTrue(ContentFilters(hideNsfw: true).hides(post(title: "x", nsfw: true)))
        XCTAssertFalse(ContentFilters().hides(post(title: "x", nsfw: true)))
    }

    func testHideNsfwKeepsSafePostsAndAppliesOnTheSubredditsOwnPage() {
        let f = ContentFilters(hideNsfw: true)
        XCTAssertFalse(f.isEmpty) // the feed list runs the filter at all
        XCTAssertFalse(f.hides(post(title: "safe")))
        // Unlike a filtered subreddit, an NSFW one's page hides them too (it says so instead).
        XCTAssertTrue(f.hides(post(title: "x", sub: "nsfwsub", nsfw: true), viewingSubreddit: "nsfwsub"))
    }

    func testChangingKeywordsRecompilesThePattern() {
        var f = ContentFilters(keywords: ["cat"])
        f.keywords = ["dog"]
        XCTAssertFalse(f.hides(post(title: "a cat")))
        XCTAssertTrue(f.hides(post(title: "a dog")))
    }

    func testDomainsAndFlairs() {
        let f = ContentFilters(domains: ["example.com"], flairs: ["meme"])
        XCTAssertTrue(f.hides(post(title: "x")))
        let p = post(title: "x").with {
            $0.domain = "other.org"
            $0.linkFlairText = "A MEME"
        }
        XCTAssertTrue(f.hides(p))
    }
}

final class LocalVotesTests: XCTestCase {
    private func eq(_ got: (likes: Bool?, score: Int), _ likes: Bool?, _ score: Int, line: UInt = #line) {
        XCTAssertEqual(got.likes, likes, line: line)
        XCTAssertEqual(got.score, score, line: line)
    }

    func testRedditStillHasTheOldVoteShowYoursOnItsScore() {
        let v = LocalVotes()
        v.record("a", dir: 1, serverScore: 10, serverLikes: nil)
        eq(v.reconcile("a", serverLikes: nil, serverScore: 10), true, 11)
        // Someone else voted meanwhile: their vote counts, yours is added on top.
        eq(v.reconcile("a", serverLikes: nil, serverScore: 12), true, 13)
    }

    func testVoteIsInButScoreHasNotMovedAddIt() {
        let v = LocalVotes()
        v.record("a", dir: 1, serverScore: 10, serverLikes: nil)
        eq(v.reconcile("a", serverLikes: true, serverScore: 10), true, 11)
    }

    func testRedditCaughtUpTrustItFromThenOn() {
        let v = LocalVotes()
        v.record("a", dir: -1, serverScore: 10, serverLikes: nil)
        eq(v.reconcile("a", serverLikes: false, serverScore: 9), false, 9)
        eq(v.reconcile("a", serverLikes: false, serverScore: 7), false, 7)
    }

    func testChangingAVoteTwiceKeepsTheFirstBaseline() {
        let v = LocalVotes()
        _ = v.reconcile("a", serverLikes: true, serverScore: 20) // seen: upvoted at 20
        v.record("a", dir: 0, serverScore: 20, serverLikes: true)
        v.record("a", dir: -1, serverScore: 19, serverLikes: nil)
        eq(v.reconcile("a", serverLikes: true, serverScore: 20), false, 18)
        eq(v.reconcile("a", serverLikes: false, serverScore: 20), false, 18)
    }

    func testNoLocalVoteServerWins() {
        eq(LocalVotes().reconcile("a", serverLikes: nil, serverScore: 5), nil, 5)
    }
}

@MainActor
final class PostOverridesTests: XCTestCase {
    func testVoteMovesScoreAndAgainIsNoOp() {
        let o = PostOverrides()
        let p = post().with { $0.score = 10 }
        o.setVote(p, targetDir: 1)
        XCTAssertEqual(o.effective(p).score, 11)
        XCTAssertEqual(o.effective(p).likes, true)
        o.setVote(p, targetDir: 1)
        XCTAssertEqual(o.effective(p).score, 11)
        o.setVote(p, targetDir: -1)
        XCTAssertEqual(o.effective(p).score, 9)
    }

    func testServerCopyDoesntUndoAFreshVoteOrSave() {
        let o = PostOverrides()
        let p = post().with { $0.score = 10 }
        o.setVote(p, targetDir: 1)
        o.setSaved(p, saved: true)
        o.syncFromServer(p.with { $0.numComments = 7 })
        XCTAssertEqual(o.effective(p).score, 11)
        XCTAssertEqual(o.effective(p).saved, true)
        XCTAssertEqual(o.effective(p).numComments, 7)
    }

    func testAccountChangeForgets() {
        let o = PostOverrides()
        let p = post()
        o.setSaved(p, saved: true)
        o.onUserChanged("bob")
        XCTAssertEqual(o.effective(p).saved, false)
    }

    func testCommentVotesSurviveAStaleFetch() {
        let v = CommentVotes()
        let c = Comment(id: "c", fullname: "t1_c", author: "a", body: "b", score: 5, createdUtc: 0, depth: 0)
        v.setVote(c, target: 1)
        XCTAssertEqual(v.effective(c).score, 6)
        let fresh = v.apply([c])[0]
        XCTAssertEqual(fresh.likes, true)
        XCTAssertEqual(fresh.score, 6)
        // Reddit caught up: the local vote is dropped.
        let later = v.apply([c.with { $0.likes = true; $0.score = 9 }])[0]
        XCTAssertEqual(later.score, 9)
        XCTAssertTrue(v.state.isEmpty)
    }
}

final class RecentSubredditsTests: XCTestCase {
    private func r(_ name: String) -> RecentSubreddit { RecentSubreddit(name: name, namePrefixed: "r/\(name)", iconUrl: nil, subscribers: 0, visitedAt: 0) }

    func testNewestFirstOncePerSubredditWhateverTheCaseAtMostFiveListed() {
        var list: [RecentSubreddit] = []
        for n in ["a", "b", "c", "d", "e", "f"] { list = RecentSubreddits.visited(list, r(n)) }
        XCTAssertEqual(RecentSubreddits.shown(list, byVisits: false).map(\.name), ["f", "e", "d", "c", "b"])
        list = RecentSubreddits.visited(list, r("C"))
        XCTAssertEqual(RecentSubreddits.shown(list, byVisits: false).map(\.name), ["C", "f", "e", "d", "b"])
    }

    func testVisitsAreCountedWhateverTheCase() {
        var list: [RecentSubreddit] = []
        for n in ["pics", "news", "Pics", "PICS"] { list = RecentSubreddits.visited(list, r(n)) }
        XCTAssertEqual(list.map(\.name), ["PICS", "news"])
        XCTAssertEqual(list.map(\.visits), [3, 1])
    }

    func testMostVisitedFirstTiesNewestFirstAndAFrequentOneOutlivesFiveNewer() {
        var list: [RecentSubreddit] = []
        for _ in 0..<4 { list = RecentSubreddits.visited(list, r("often")) }
        for n in ["a", "b", "c", "d", "e", "f"] { list = RecentSubreddits.visited(list, r(n)) }
        list = RecentSubreddits.visited(list, r("b"))
        XCTAssertEqual(RecentSubreddits.shown(list, byVisits: true).map(\.name), ["often", "b", "f", "e", "d"])
        // Most recent: "often" fell off the five listed but kept its count.
        XCTAssertEqual(RecentSubreddits.shown(list, byVisits: false).map(\.name), ["b", "f", "e", "d", "c"])
        XCTAssertEqual(list.first { $0.name == "often" }?.visits, 4)
    }

    func testRemembersAHundred() {
        var list: [RecentSubreddit] = []
        for i in 0..<120 { list = RecentSubreddits.visited(list, r("s\(i)")) }
        XCTAssertEqual(list.count, 100)
        XCTAssertEqual(list.first?.name, "s119")
        XCTAssertEqual(list.last?.name, "s20")
    }

    @MainActor
    func testCountsSurviveARestartPerAccountAndTheOrderFollowsTheSetting() {
        let p = testPrefs()
        var byVisits = false
        let store = RecentSubreddits(prefs: p, byVisits: { byVisits })
        store.onUserChanged("bob")
        for n in ["often", "often", "often", "rare"] { store.visit(Subreddit(name: n, namePrefixed: "r/\(n)", title: "", description: "", subscribers: 0, iconUrl: nil)) }
        XCTAssertEqual(store.state.map(\.name), ["rare", "often"])
        byVisits = true
        store.refresh()
        XCTAssertEqual(store.state.map(\.name), ["often", "rare"])

        let again = RecentSubreddits(prefs: p, byVisits: { true })
        again.onUserChanged("bob")
        XCTAssertEqual(again.state.map(\.name), ["often", "rare"])
        XCTAssertEqual(again.state.map(\.visits), [3, 1])
        again.onUserChanged("alice")
        XCTAssertTrue(again.state.isEmpty, "another account has its own list")
    }
}

/// Port of the share-image test plus the tree operations.
final class CommentTreeTests: XCTestCase {
    private func c(_ id: String, _ author: String, _ body: String, _ parent: String, _ depth: Int = 0, _ replies: [Comment] = []) -> Comment {
        Comment.fromChild(json(#"{"kind":"t1","data":{"id":"\#(id)","name":"t1_\#(id)","author":"\#(author)","body":"\#(body)","score":42,"parent_id":"\#(parent)","created_utc":1700000000}}"#), depth)
            .with { $0.replies = replies }
    }

    private func more(_ id: String, _ parent: String, _ depth: Int, _ children: [String]) -> Comment {
        Comment(id: id, fullname: "t1_\(id)", parentId: parent, author: "", body: "", score: 0, createdUtc: 0, depth: depth, isMore: true, moreCount: children.count, moreChildren: children)
    }

    private var chain: [Comment] { [c("a", "alice", "Top comment", "t3_p"), c("b", "bob", "A reply", "t1_a", 1), c("c", "alice", "Back to you", "t1_b", 2)] }

    func testShareImageNamesHiddenConsistently() {
        XCTAssertEqual(CommentTree.shareNames(chain, hide: false), ["u/alice", "u/bob", "u/alice"])
        // Same author, same placeholder.
        XCTAssertEqual(CommentTree.shareNames(chain, hide: true), ["Commenter 1", "Commenter 2", "Commenter 1"])
    }

    func testChainRunsFromTheTopLevelAncestorToTheComment() {
        let flat = [c("x", "x", "other", "t3_p")] + chain
        XCTAssertEqual(CommentTree.chainTo(flat, chain[2]).map(\.id), ["a", "b", "c"])
        XCTAssertEqual(CommentTree.chainTo(flat, chain[0]).map(\.id), ["a"])
    }

    func testFlattenSkipsCollapsedAndMoreSubtrees() {
        let tree = [c("a", "u", "", "t3_p", 0, [c("b", "u", "", "t1_a", 1, [c("c", "u", "", "t1_b", 2)])])]
        XCTAssertEqual(CommentTree.flatten(tree, []).map(\.id), ["a", "b", "c"])
        XCTAssertEqual(CommentTree.flatten(tree, ["b"]).map(\.id), ["a", "b"])
        XCTAssertEqual(CommentTree.flatten(tree, [CommentTree.folded("b")]).map(\.id), ["a", "b"])
        XCTAssertEqual(CommentTree.replyCount(tree[0]), 2)
    }

    func testInsertUpdateAndRemoveKeepTheTreeConsistent() {
        let tree = [c("a", "u", "", "t3_p", 0, [c("b", "u", "", "t1_a", 1)]), c("z", "u", "", "t3_p")]
        let inserted = CommentTree.insertReply(tree, "t1_b", c("n", "me", "new", "t1_b"))
        XCTAssertEqual(inserted[0].replies[0].replies[0].depth, 2)
        // Untouched subtrees stay as they were.
        let updated = CommentTree.update(tree, "t1_b") { $0.with { $0.score = 1 } }
        XCTAssertEqual(updated[0].replies[0].score, 1)
        XCTAssertEqual(tree[1], updated[1])
        // A deleted comment with replies stays as "[deleted]".
        let removed = CommentTree.remove(tree, "t1_a")
        XCTAssertEqual(removed[0].author, "[deleted]")
        XCTAssertEqual(CommentTree.remove(tree, "t1_a").dropFirst().map(\.id), ["z"])
        XCTAssertEqual(CommentTree.remove(tree, "t1_z").map(\.id), ["a"])
    }

    func testLoadMoreReNestsTheFlatResultInPlaceOfTheStub() {
        let stub = more("m", "t1_a", 1, ["x", "y"])
        let tree = [c("a", "u", "", "t3_p", 0, [c("b", "u", "", "t1_a", 1), stub])]
        let fetched = [c("x", "u", "", "t1_a"), c("y", "u", "", "t1_x")]
        let out = CommentTree.replaceMore(tree, stub, fetched)
        let replies = out[0].replies
        XCTAssertEqual(replies.map(\.id), ["b", "x"])
        XCTAssertEqual(replies[1].depth, 1)
        XCTAssertEqual(replies[1].replies.map(\.id), ["y"])
        XCTAssertEqual(replies[1].replies[0].depth, 2)
        XCTAssertFalse(CommentTree.flatten(out, []).contains { $0.isMore })
    }

    func testLoadMoreDropsCommentsAlreadyOnScreenKeepsARowForTheRest() {
        let stub = more("m", "t1_a", 1, ["x", "y", "z"])
        let tree = [c("a", "u", "", "t3_p", 0, [c("b", "u", "", "t1_a", 1), stub])]
        // Re-reading the thread brings back b, and x twice via its own thread.
        let fetched = [c("b", "u", "", "t1_a"), c("x", "u", "", "t1_a"), c("x", "u", "", "t1_a"), more("m", "t1_a", 1, ["z"])]
        let replies = CommentTree.replaceMore(tree, stub, fetched)[0].replies
        XCTAssertEqual(replies.map(\.id), ["b", "x", "m"])
        XCTAssertEqual(replies.last?.moreChildren, ["z"])
    }

    func testThreadTextRanksCommentsByScoreWithinTheBudget() {
        let p = Post.fromData(json(#"{"id":"p","title":"A big post","subreddit":"test","author":"op","url":"","is_self":true,"selftext":"Body","score":10,"num_comments":2}"#))
        let low = c("l", "low", "meh", "t3_p").with { $0.score = 1 }
        let high = c("h", "high", "x", "t3_p").with { $0.score = 99; $0.body = "great\nline" }
        let text = AiService.buildThreadText(p, [low, high, more("m", "t3_p", 0, ["q"])], maxChars: 100_000)
        XCTAssertTrue(text.hasPrefix("POST in r/test by u/op — score 10, 2 comments\nTITLE: A big post\nBODY: Body\n"))
        XCTAssertLessThan(text.range(of: "[99] u/high: great line")!.lowerBound, text.range(of: "[1] u/low: meh")!.lowerBound)
        XCTAssertTrue(text.hasSuffix("(Included 2 of 2 comments, highest-scored first.)"))
        let tight = AiService.buildThreadText(p, [low, high], maxChars: 120)
        XCTAssertTrue(tight.hasSuffix("(Included 0 of 2 comments, highest-scored first.)"))
    }
}

/// #22: a base that already ends in its version mustn't get a second /v1.
final class AiChatUrlTests: XCTestCase {
    func testBaseWithoutVersionGetsV1() {
        XCTAssertEqual(chatUrl("https://api.openai.com"), "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(chatUrl("https://my-litellm:4000/"), "https://my-litellm:4000/v1/chat/completions")
    }

    func testBaseWithVersionIsUsedAsIs() {
        XCTAssertEqual(chatUrl("https://api.groq.com/openai/v1"), "https://api.groq.com/openai/v1/chat/completions")
        XCTAssertEqual(chatUrl(" https://openrouter.ai/api/v1/ "), "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertEqual(chatUrl("https://example.com/v2"), "https://example.com/v2/chat/completions")
    }
}

final class AiCitationsTests: XCTestCase {
    private let p = Post.fromData(json(#"{"id":"p","title":"Battery life?","subreddit":"GalaxyWatch","num_comments":40}"#))
    private func comment(_ id: String, _ author: String, _ score: Int, _ body: String) -> Comment {
        Comment(id: id, fullname: "t1_\(id)", author: author, body: body, score: score, createdUtc: 0, depth: 0)
    }

    private var comments: [Comment] {
        [comment("a", "low", 1, "Meh."), comment("b", "top", 90, "Two days with AOD off."), comment("c", "mid", 20, "One day with AOD on.")]
    }

    func testCommentsAreTaggedMostUpvotedFirst() {
        let t = AiService.buildCitedThread(p, comments, maxChars: 10_000)
        XCTAssertEqual(t.refs.values.map(\.author), ["top", "mid", "low"])
        XCTAssertTrue(t.text.contains("[c1] [90] u/top: Two days with AOD off."))
        XCTAssertEqual(t.included, 3)
    }

    func testOnlyWhatFitsIsTaggedAndCounted() {
        let t = AiService.buildCitedThread(p, comments, maxChars: 230)
        XCTAssertLessThan(t.included, 3)
        XCTAssertEqual(t.loaded, 3)
        XCTAssertEqual(t.included, t.refs.count)
    }

    func testCitationsBecomeCommentLinksUnknownTagsAreDropped() {
        let t = AiService.buildCitedThread(p, comments, maxChars: 10_000)
        let out = AiService.linkCitations("Most get two days [c1] [c2], one disagrees [c9].", t.refs)
        XCTAssertEqual(out, "Most get two days [u/top](ilay-comment:t1_b) [u/mid](ilay-comment:t1_c), one disagrees .")
    }
}
