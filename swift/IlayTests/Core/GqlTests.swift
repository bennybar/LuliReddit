import XCTest
@testable import Ilay

final class GqlCommentsTests: XCTestCase {
    private func comment(_ id: String, _ author: String, _ markdown: String, _ extra: String = "") -> String {
        #"{"__typename":"Comment","id":"\#(id)","authorInfo":{"name":"\#(author)"},"content":{"markdown":"\#(markdown)"},"score":5,"createdAt":"2026-10-04T00:26:11.575000+0000","permalink":"/r/pics/comments/abc/a_post/\#(id.removePrefix("t1_"))/"\#(extra)}"#
    }

    // PostComments' forest: a flat, depth-first list.
    private var trees: [JsonElement] {
        json(#"""
        [
          {"depth":0,"parentId":"t3_abc","node":\#(comment("t1_c1", "alice", "Hello", #","isOP":true,"isStickied":true,"distinguishedAs":"MODERATOR","voteState":"UP","isSaved":true,"authorFlair":{"text":"Mod","richtext":"[{\"e\":\"text\",\"t\":\"Mod\"}]"}"#))},
          {"depth":1,"parentId":"t1_c1","node":\#(comment("t1_c2", "bob", "Reply"))},
          {"depth":2,"parentId":"t1_c2","more":{"count":4,"cursor":"cur-deep"}},
          {"depth":0,"parentId":"t3_abc","node":{"__typename":"DeletedComment","createdAt":"2026-10-04T00:26:11+0000"}},
          {"depth":1,"parentId":"t1_gone","node":\#(comment("t1_c3", "carol", "Under a deleted one", #","voteState":"DOWN""#))},
          {"depth":0,"parentId":"t3_abc","more":{"count":30,"cursor":"cur-top"}}
        ]
        """#).arr()!
    }

    private let postObj: JsonObject = ["id": "abc", "name": "t3_abc", "title": "A post", "author": "alice", "subreddit": "pics", "permalink": "/r/pics/comments/abc/a_post/"]

    func testACommentForestBecomesTheThreadsCommentTree() {
        let body = gqlThreadData(postObj, trees)
        XCTAssertEqual(Post.fromData(body[0]["data"]["children"][0]["data"]!).id, "abc")
        let top = body[1]["data"]["children"].arr()!.map { Comment.fromChild($0, 0) }
        XCTAssertEqual(top.map(\.id), ["c1", "gone", "more_t3_abc"])

        let c1 = top[0]
        XCTAssertEqual(c1.author, "alice")
        XCTAssertEqual(c1.body, "Hello")
        XCTAssertEqual(c1.score, 5)
        XCTAssertEqual(c1.createdUtc, 1_791_073_571_000)
        XCTAssertEqual(c1.distinguished, "moderator")
        XCTAssertTrue(c1.stickied && c1.saved)
        XCTAssertEqual(c1.likes, true)
        XCTAssertEqual(c1.authorFlair?.parts.first?.text, "Mod")
        XCTAssertEqual(c1.parentId, "t3_abc")

        let c2 = c1.replies[0]
        XCTAssertEqual(c2.depth, 1)
        XCTAssertEqual(c2.parentId, "t1_c1")
        let deep = c2.replies[0]
        XCTAssertTrue(deep.isMore)
        XCTAssertEqual(deep.depth, 2)
        XCTAssertEqual(deep.moreCount, 4)
        XCTAssertEqual(deep.parentId, "t1_c2")
        XCTAssertEqual(deep.moreChildren, ["\(GQL_MORE)t1_c2 cur-deep"])

        // The deleted comment gets its id back from its reply.
        let gone = top[1]
        XCTAssertEqual(gone.author, "[deleted]")
        XCTAssertEqual(gone.body, "[deleted]")
        XCTAssertEqual(gone.fullname, "t1_gone")
        XCTAssertEqual(gone.replies[0].likes, false)

        let more = top[2]
        XCTAssertTrue(more.isMore)
        XCTAssertEqual(more.moreCount, 30)
        XCTAssertEqual(more.parentId, "t3_abc")
        XCTAssertEqual(more.moreChildren, ["\(GQL_MORE)t3_abc cur-top"])
    }

    func testALoadedMoreComesFlatRootedWhereTheMoreRowWas() {
        // The page after cursor cur-deep: depths continue from where it sat.
        let page = json(#"""
        [
          {"depth":2,"node":\#(comment("t1_d1", "dan", "One"))},
          {"depth":3,"parentId":"t1_d1","node":\#(comment("t1_d2", "erin", "Two"))},
          {"depth":2,"parentId":"t1_c2","more":{"count":2,"cursor":"cur-next"}}
        ]
        """#).arr()!
        // Rooted at the row's parent even where Reddit leaves parentId out.
        let flat = gqlCommentThings(page, "t3_abc", moreParent: "t1_c2").map { Comment.fromChild($0, 2) }
        XCTAssertEqual(flat.map(\.parentId), ["t1_c2", "t1_d1", "t1_c2"])
        XCTAssertEqual(flat.last?.moreChildren, ["\(GQL_MORE)t1_c2 cur-next"])
    }

    func testFocusedThreadsAndMoreUsePostCommentsVariables() {
        let vars = postCommentsVariables("t3_abc", "qa", "c9", nil)
        XCTAssertEqual(vars["sortType"], "QA")
        XCTAssertEqual(vars["focusedCommentContext"]["commentId"], "t1_c9")
        XCTAssertNil(vars["after"])
        XCTAssertEqual(postCommentsVariables("t3_abc", "confidence", nil, "cur")["after"], "cur")
    }

    private func richtext(_ document: String, _ media: String = "[]") -> JsonElement {
        ["richtext": .string(#"{"document":\#(document)}"#), "richtextMedia": json(media)]
    }

    func testTheSourceMarkdownWinsOverRichtext() {
        XCTAssertEqual(gqlMarkdown(json(#"{"markdown":"**hi**","richtext":"{\"document\":[]}"}"#), "c1"), "**hi**")
    }

    func testRichtextBecomesMarkdown() {
        let md = gqlMarkdown(richtext(
            #"""
            [
              {"e":"h","l":2,"c":[{"e":"text","t":"Title"}]},
              {"e":"par","c":[{"e":"text","t":"bold italic struck 2*3","f":[[1,0,4],[2,5,6],[8,12,6]]},
                {"e":"link","u":"https://example.com/a (b)","t":"a link"},{"e":"text","t":" "},
                {"e":"spoilertext","c":[{"e":"text","t":"secret"}]},{"e":"text","t":" in "},
                {"e":"r/","t":"pics","l":false},{"e":"br"},{"e":"text","t":"x","f":[[64,0,1]]},
                {"e":"text","t":"e=mc2","f":[[32,4,1]]}]},
              {"e":"blockquote","c":[{"e":"par","c":[{"e":"text","t":"quoted"}]},{"e":"par","c":[{"e":"text","t":"more"}]}]},
              {"e":"list","o":true,"c":[{"e":"li","c":[{"e":"par","c":[{"e":"text","t":"one"}]}]},
                {"e":"li","c":[{"e":"par","c":[{"e":"text","t":"two"}]},{"e":"list","o":false,"c":[{"e":"li","c":[{"e":"par","c":[{"e":"text","t":"sub"}]}]}]}]}]},
              {"e":"code","c":[{"e":"raw","t":"val x = 1"},{"e":"raw","t":"  *y*"}]},
              {"e":"hr"},
              {"e":"par","c":[{"e":"gif","id":"giphy|abc123|downsized"}]},
              {"e":"img","id":"img1"},
              {"e":"table","h":[{"a":"L","c":[{"e":"text","t":"A"}]},{"c":[{"e":"text","t":"B"}]}],
                "c":[[{"c":[{"e":"text","t":"1"}]},{"c":[{"e":"text","t":"2"}]}]]}
            ]
            """#,
            #"[{"id":"img1","url":"https://i.redd.it/full.png","large":{"url":"https://preview.redd.it/large.png"}}]"#
        ), "c1")
        XCTAssertEqual(md, [
            "## Title",
            "**bold** *italic* ~~struck~~ 2\\*3[a link](https://example.com/a%20%28b%29) >!secret!< in r/pics  \n`x`e=mc^(2)",
            "> quoted\n>\n> more",
            "1. one\n2. two\n   \n   - sub",
            "```\nval x = 1\n  *y*\n```",
            "---",
            "https://media.giphy.com/media/abc123/giphy.webp",
            "https://preview.redd.it/large.png",
            "| A | B |\n| :-- | --- |\n| 1 | 2 |",
        ].joined(separator: "\n\n"))
    }

    func testFormattingSkipsWhitespaceAndCountsCodePoints() {
        // "😀 wow": the emoji is one code point, so " wow ok" is 1 to 8.
        let md = gqlMarkdown(richtext(#"[{"e":"par","c":[{"e":"text","t":"😀 wow ok","f":[[1,1,7]]}]}]"#), "c1")
        XCTAssertEqual(md.trimmedEnd, "😀 **wow ok**")
    }

    func testAuthorIconsComeFromTheForestByLowercasedName() {
        let forest = json(#"""
        [
          {"depth":0,"node":{"authorInfo":{"name":"Alice","iconSmall":{"url":"https://a/1.png"}}}},
          {"depth":1,"node":{"authorInfo":{"name":"bob","iconSmall":null}}},
          {"depth":1,"more":{"count":3,"cursor":"c"}},
          {"depth":0,"node":{"__typename":"DeletedComment"}}
        ]
        """#).arr()!
        XCTAssertEqual(gqlAuthorIcons(forest), ["alice": "https://a/1.png"])
    }
}

final class GqlSearchTests: XCTestCase {
    func testAGraphQlSearchPostBecomesAPostCard() {
        let n = json(#"""
        {"__typename":"SubredditPost","id":"t3_abc","postTitle":"iPhone 18 Pro review",
         "authorInfo":{"name":"someone"},"subreddit":{"name":"iphone","prefixedName":"r/iphone"},
         "score":120,"commentCount":45,"createdAt":"2026-10-04T00:26:11.575000+0000",
         "permalink":"/r/iphone/comments/abc/iphone_18_pro_review/","url":"https://i.redd.it/x.jpg",
         "isSelfPost":false,"isNsfw":false,"voteState":"UP","flair":{"text":"Review"},
         "media":{"still":{"small":{"url":"https://p/s.jpg","dimensions":{"width":108,"height":81}},
                           "source":{"url":"https://p/src.jpg","dimensions":{"width":1920,"height":1440}}}}}
        """#).obj()!
        let p = Post.fromData(.object(gqlPostData(n)))
        XCTAssertEqual(p.id, "abc")
        XCTAssertEqual(p.title, "iPhone 18 Pro review")
        XCTAssertEqual(p.subreddit, "iphone")
        XCTAssertEqual(p.author, "someone")
        XCTAssertEqual(p.score, 120)
        XCTAssertEqual(p.numComments, 45)
        XCTAssertEqual(p.createdUtc, 1_791_073_571_000) // 2026-10-04T00:26:11Z
        XCTAssertTrue(p.permalink.hasSuffix("/comments/abc/iphone_18_pro_review/"))
    }

    private func node(_ extra: String) -> JsonObject {
        json(#"""
        {"__typename":"SubredditPost","id":"t3_abc","postTitle":"A post","authorInfo":{"name":"someone"},
         "subreddit":{"name":"pics","prefixedName":"r/pics","styles":{"icon":"https://styles.redditmedia.com/icon.png?width=256"}},
         "score":10,"commentCount":2,"createdAt":"2026-10-04T00:26:11.575000+0000",
         "permalink":"/r/pics/comments/abc/a_post/",\#(extra)}
        """#).obj()!
    }

    func testAGalleryKeepsEveryImage() {
        let p = Post.fromData(.object(gqlPostData(node(#""url":"https://www.reddit.com/gallery/abc","gallery":{"items":[{"media":{"url":"https://i.redd.it/1.jpg","width":800,"height":600}},{"media":{"url":"https://i.redd.it/2.jpg","width":600,"height":800}}]}"#))))
        XCTAssertEqual(p.gallery.map(\.url), ["https://i.redd.it/1.jpg", "https://i.redd.it/2.jpg"])
        XCTAssertEqual(p.gallery.first?.width, 800)
        XCTAssertEqual(p.subredditIcon, "https://styles.redditmedia.com/icon.png")
    }

    func testAVideoGetsItsStreamAGifItsMp4() {
        let video = Post.fromData(.object(gqlPostData(node(#""url":"https://v.redd.it/xyz","media":{"streaming":{"hlsUrl":"https://v.redd.it/xyz/HLSPlaylist.m3u8"}}"#))))
        XCTAssertEqual(video.hlsUrl, "https://v.redd.it/xyz/HLSPlaylist.m3u8")
        let gif = Post.fromData(.object(gqlPostData(node(#""url":"https://i.redd.it/a.gif","media":{"still":{"source":{"url":"https://p/a.png","dimensions":{"width":400,"height":300}}},"animated":{"mp4_source":{"url":"https://p/a.mp4"}}}"#))))
        XCTAssertEqual(gif.gifMp4Url, "https://p/a.mp4")
        XCTAssertEqual(gif.previewUrl, "https://p/a.png")
    }

    func testACrosspostCarriesTheOriginalPost() {
        let p = Post.fromData(.object(gqlPostData(node(#""url":"/r/other/comments/orig/","crosspostRoot":{"post":{"__typename":"SubredditPost","id":"t3_orig","subreddit":{"name":"other"},"url":"https://i.redd.it/o.jpg","media":{"still":{"source":{"url":"https://p/o.jpg","dimensions":{"width":10,"height":10}}}}}}"#))))
        XCTAssertEqual(p.crosspostFrom, "other")
        XCTAssertEqual(p.crosspostId, "orig")
    }

    func testSearchResultsCarryTheirIconsGraphQl() {
        let sub = Subreddit.fromData(gqlSubredditData(json(#"{"__typename":"Subreddit","name":"pics","styles":{"icon":"https://styles.redditmedia.com/p.png"}}"#).obj()!))
        XCTAssertEqual(sub.iconUrl, "https://styles.redditmedia.com/p.png")
        let legacy = Subreddit.fromData(gqlSubredditData(json(#"{"name":"old","styles":{"legacyIcon":{"url":"https://b.thumbs/o.png"}}}"#).obj()!))
        XCTAssertEqual(legacy.iconUrl, "https://b.thumbs/o.png")
        let user = RedditUser.fromData(gqlUserData(json(#"{"__typename":"Redditor","name":"spez","icon":{"url":"https://styles.redditmedia.com/i.png?width=256&s=x"},"snoovatarIcon":{"url":"https://i.redd.it/snoo.png"},"karma":{"total":5}}"#).obj()!))
        XCTAssertEqual(user.iconUrl, "https://styles.redditmedia.com/i.png")
        let snoo = RedditUser.fromData(gqlUserData(json(#"{"name":"a","snoovatarIcon":{"url":"https://i.redd.it/snoo.png"}}"#).obj()!))
        XCTAssertEqual(snoo.iconUrl, "https://i.redd.it/snoo.png")
        XCTAssertNil(RedditUser.fromData(gqlUserData(json(#"{"name":"b"}"#).obj()!)).iconUrl)
    }

    func testSearchResultsCarryTheirIconsRest() {
        let sub = Subreddit.fromData(json(#"{"display_name":"pics","community_icon":"https://styles.redditmedia.com/c.png?width=256&amp;s=abc","icon_img":""}"#))
        XCTAssertEqual(sub.iconUrl, "https://styles.redditmedia.com/c.png?width=256&s=abc")
        XCTAssertEqual(Subreddit.fromData(json(#"{"display_name":"x","community_icon":"","icon_img":"https://b.thumbs/x.png"}"#)).iconUrl, "https://b.thumbs/x.png")
        XCTAssertNil(Subreddit.fromData(json(#"{"display_name":"y","community_icon":"","icon_img":""}"#)).iconUrl)
        let user = RedditUser.fromData(json(#"{"name":"spez","icon_img":"https://styles.redditmedia.com/u.png?width=256&amp;s=1"}"#))
        XCTAssertEqual(user.iconUrl, "https://styles.redditmedia.com/u.png")
    }

    func testOnlyPostsCount() {
        XCTAssertTrue(gqlIsPost(json(#"{"__typename":"SubredditPost"}"#)))
        XCTAssertFalse(gqlIsPost(json(#"{"__typename":"UnavailablePost"}"#)))
    }

    func testSearchPagesEndWithoutACursor() {
        let data = json(#"{"search":{"general":{"communities":{"edges":[{"node":{"name":"iphone"}}],"pageInfo":{"endCursor":"Mg==","hasNextPage":false}}}}}"#).obj()!
        let (nodes, next) = gqlSearch(data, "communities")
        XCTAssertEqual(nodes.count, 1)
        XCTAssertNil(next)
    }

    func testAFeedPagesPostIdsSkipAdsItsCursorIsTheLastPost() {
        let data = json(#"""
        {"subredditV3":{"elements":{"edges":[
           {"node":{"__typename":"CellGroup","groupId":"t3_a","id":"x"}},
           {"node":{"__typename":"CellGroup","groupId":"t3_ad","adPayload":{"impressionId":"1"}}},
           {"node":{"__typename":"CellGroup","groupId":"t3_a"}},
           {"node":{"__typename":"CellGroup","id":"t3_b"}},
           {"node":{"__typename":"CellGroup","groupId":"carousel_1"}}]}}}
        """#).obj()!
        XCTAssertEqual(gqlFeedPostIds(data), ["t3_a", "t3_b"])
        let q = gqlFeedQuery("pics", .top, .week, "t3_b")!
        XCTAssertEqual(q.operation, "SubredditFeedSdui")
        XCTAssertEqual(q.variables["subredditName"].str(), "pics")
        XCTAssertEqual(q.variables["sort"].str(), "TOP")
        XCTAssertEqual(q.variables["time"].str(), "WEEK")
        XCTAssertEqual(q.variables["after"].str(), "dDNfYg==") // base64("t3_b")
    }

    func testEachFeedPicksItsQuery() {
        XCTAssertEqual(gqlFeedQuery(nil, .best, .day, nil)?.operation, "HomeFeedSdui")
        XCTAssertEqual(gqlFeedQuery("popular", .hot, .day, nil)?.operation, "PopularFeedSdui")
        XCTAssertEqual(gqlFeedQuery("All", .rising, .day, nil)?.operation, "AllFeedSdui")
        let home = gqlFeedQuery(nil, .newest, .day, nil)!.variables
        XCTAssertEqual(home["sort"].str(), "NEW")
        XCTAssertNil(home["time"])
        XCTAssertNil(home["after"])
        XCTAssertNil(gqlFeedQuery("pics+news", .hot, .day, nil))
    }

    func testTimes() {
        XCTAssertEqual(gqlSeconds("2026-10-04T00:26:11.575000+0000"), 1_791_073_571)
        XCTAssertEqual(gqlSeconds("2026-10-04T00:26:11Z"), 1_791_073_571)
        XCTAssertEqual(gqlSeconds("2026-10-04T02:26:11+02:00"), 1_791_073_571)
        XCTAssertEqual(gqlSeconds("2026-10-03T23:26:11-01:00"), 1_791_073_571)
        XCTAssertEqual(gqlSeconds("nonsense"), 0)
        XCTAssertEqual(gqlSeconds(nil), 0)
    }
}
