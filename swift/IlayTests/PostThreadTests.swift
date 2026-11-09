import XCTest
@testable import Ilay

/// The thread screen's rules. Kotlin's feature/post tests (CommentTree, AiChatUrl, AiCitations,
/// CommentMedia) are already ported in Core/StateTests.swift and Core/ModelTests.swift.
final class PostThreadTests: XCTestCase {
    private func c(_ id: String, author: String = "u", score: Int = 5, depth: Int = 0, replies: [Comment] = [], createdUtc: Int = 0) -> Comment {
        Comment(id: id, fullname: "t1_\(id)", author: author, body: id, score: score, createdUtc: createdUtc, depth: depth, replies: replies)
    }

    private func more(_ id: String, depth: Int = 1) -> Comment {
        Comment(id: id, fullname: "t1_\(id)", author: "", body: "", score: 0, createdUtc: 0, depth: depth, isMore: true, moreCount: 2, moreChildren: ["x"])
    }

    func testStartCollapsedFollowsTheSettings() {
        let tree = [
            c("auto", author: "AutoModerator"),
            c("low", score: -10),
            c("mine", author: "Me", score: -10),
            c("hidden", score: -10).with { $0.scoreHidden = true },
            c("parent", replies: [c("kid", depth: 1)]),
            c("onlyMore", replies: [more("m")]),
        ]
        var rules = CommentsViewModel.CollapseRules(me: "me")
        XCTAssertEqual(CommentsViewModel.startCollapsed(tree, rules: rules), [])

        rules.collapseAutoMod = true
        XCTAssertEqual(CommentsViewModel.startCollapsed(tree, rules: rules), ["auto"])

        // Your own and hidden scores aren't "low".
        rules.below = 0
        XCTAssertEqual(CommentsViewModel.startCollapsed(tree, rules: rules), ["auto", "low"])

        // Top-level comments fold their replies, when there are real ones.
        rules.topLevel = true
        XCTAssertEqual(CommentsViewModel.startCollapsed(tree, rules: rules), ["auto", "low", CommentTree.folded("parent")])

        // Ones already shown are left as they are.
        XCTAssertEqual(CommentsViewModel.startCollapsed(tree, rules: rules, skip: ["auto", "parent"]), ["low"])
    }

    func testToggleCollapse() {
        let parent = c("p", replies: [c("k", depth: 1)])
        let leaf = c("l")
        let flat = [parent, parent.replies[0], leaf]
        let folded = CommentTree.folded("p")
        XCTAssertEqual(CommentsViewModel.toggled([], "p", in: flat, repliesOnly: false), ["p"])
        // "Collapse only the replies" keeps the text, when there are replies to hide.
        XCTAssertEqual(CommentsViewModel.toggled([], "p", in: flat, repliesOnly: true), [folded])
        XCTAssertEqual(CommentsViewModel.toggled([], "l", in: flat, repliesOnly: true), ["l"])
        XCTAssertEqual(CommentsViewModel.toggled([folded], "p", in: flat, repliesOnly: true), [])
        // Expanding a comment also shows its folded replies.
        XCTAssertEqual(CommentsViewModel.toggled(["p", folded], "p", in: flat, repliesOnly: false), [])
    }

    func testTranslatedSwapsTextsAndKeepsTheOriginal() {
        let post = Post.fromData(json(#"{"id":"p","title":"Hello","selftext":"Body","subreddit":"s"}"#))
        let thread = PostThread(post: post, comments: [c("a", replies: [c("b", depth: 1), more("m")])], collapsed: [])
        let shown = thread.translated(["title": "Hola", "body": "Cuerpo", "t1_b": "bee"])
        XCTAssertEqual(shown.post.title, "Hola")
        XCTAssertEqual(shown.post.selftext, "Cuerpo")
        XCTAssertEqual(shown.flat.map(\.body), ["a", "bee", ""])
        XCTAssertEqual(thread.flat.map(\.body), ["a", "b", ""])
        XCTAssertEqual(thread.translated(nil), thread)
    }

    func testJumpFindsTheNextHitBelowTheTopAndWraps() {
        // Row 0 is the post: comment i is row i + 1.
        let flat = [c("a"), c("b", depth: 1), more("m", depth: 1), c("d"), c("e", depth: 1), c("f")]
        let top: (Comment) -> Bool = { $0.depth == 0 }
        XCTAssertEqual(jumpTarget(flat, topIndex: 0, match: top), 1)
        XCTAssertEqual(jumpTarget(flat, topIndex: 1, match: top), 4)
        XCTAssertEqual(jumpTarget(flat, topIndex: 6, match: top), 1) // wraps
        XCTAssertEqual(jumpTarget(flat, topIndex: 4, backwards: true, match: top), 1)
        XCTAssertNil(jumpTarget(flat, topIndex: 1, backwards: true, match: top)) // doesn't wrap backwards
        XCTAssertNil(jumpTarget(flat, topIndex: 0) { $0.author == "nobody" })
        // A "more" row is never a target.
        XCTAssertEqual(jumpTarget(flat, topIndex: 2) { $0.depth == 1 }, 5)
    }

    func testNewMeansSinceTheLastVisitAndNotMine() {
        XCTAssertFalse(isNewComment(c("a", createdUtc: 100), since: nil, me: "me"))
        XCTAssertTrue(isNewComment(c("a", createdUtc: 100), since: 50, me: "me"))
        XCTAssertFalse(isNewComment(c("a", createdUtc: 40), since: 50, me: "me"))
        XCTAssertFalse(isNewComment(c("a", author: "me", createdUtc: 100), since: 50, me: "me"))
        XCTAssertFalse(isNewComment(more("m"), since: -1, me: "me"))
    }

    func testErrorTextReadsLikeFlutters() {
        XCTAssertEqual(errorText(RedditApiException(statusCode: 403, reason: "Forbidden")), "HTTP 403 (Forbidden)")
        XCTAssertEqual(errorText(RedditApiException(statusCode: 403, reason: nil, message: "No")), "HTTP 403: No")
        XCTAssertEqual(errorText(RedditApiException(statusCode: 403, reason: nil, message: "HTTP 403 said no")), "HTTP 403 said no")
        XCTAssertEqual(errorText(AppException("Boom")), "Boom")
    }

    func testCommentBodySegmentsAreCachedPerBody() {
        let comment = c("a").with { $0.body = "text\n\nhttps://i.redd.it/a.jpg" }
        let segments = CommentBody.segments(comment)
        XCTAssertEqual(segments, [.text("text"), .media(URL(string: "https://i.redd.it/a.jpg")!)])
        XCTAssertEqual(CommentBody.segments(comment), segments)
    }
}
