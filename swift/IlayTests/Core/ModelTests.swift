import XCTest
@testable import Ilay

final class AuthorFlairTests: XCTestCase {
    private func flair(_ s: String) -> UserFlair? { flairOf(json(s), "author") }
    private func linkFlair(_ s: String) -> UserFlair? { flairOf(json(s), "link") }

    func testRichtextKeepsTextAndEmojiInOrder() {
        let f = flair(#"{"author_flair_richtext":[{"e":"emoji","a":":watch:","u":"https://emoji.redditmedia.com/w.png"},{"e":"text","t":" Galaxy Watch Ultra "}],"author_flair_text":":watch: Galaxy Watch Ultra"}"#)!
        XCTAssertEqual(f.parts, [FlairPart(emojiUrl: "https://emoji.redditmedia.com/w.png"), FlairPart(text: " Galaxy Watch Ultra")])
        XCTAssertEqual(f.text, "Galaxy Watch Ultra")
    }

    func testEmojiOnlyFlairIsKept() {
        XCTAssertEqual(flair(#"{"author_flair_richtext":[{"e":"emoji","a":":x:","u":"https://e/x.png"}],"author_flair_text":":x:"}"#)!.parts, [FlairPart(emojiUrl: "https://e/x.png")])
    }

    func testPlainTextLosesItsEmojiCodes() {
        XCTAssertEqual(flair(#"{"author_flair_text":":mod: Moderator"}"#)!.text, "Moderator")
    }

    func testNoFlairIsNil() {
        XCTAssertNil(flair(#"{"author_flair_text":null}"#))
        XCTAssertNil(flair(#"{"author_flair_text":":x:"}"#))
    }

    func testAPostsFlairKeepsItsImages() {
        let f = linkFlair(#"{"link_flair_richtext":[{"e":"emoji","a":":a16:","u":"https://emoji.redditmedia.com/a.png"},{"e":"text","t":" Android 16"}],"link_flair_text":":a16: Android 16"}"#)!
        XCTAssertEqual(f.parts, [FlairPart(emojiUrl: "https://emoji.redditmedia.com/a.png"), FlairPart(text: " Android 16")])
    }

    func testPlainFlairTextLosesItsEmojiCodes() {
        XCTAssertEqual(linkFlair(#"{"link_flair_text":":Discussion: Discussion"}"#)!.text, "Discussion")
        XCTAssertEqual(linkFlair(#"{"link_flair_text":":q:  Help   :x_y-1: me"}"#)!.text, "Help me")
        XCTAssertEqual(linkFlair(#"{"link_flair_text":"10:30 AM"}"#)!.text, "10:30 AM")
        XCTAssertNil(linkFlair(#"{"link_flair_text":":star:"}"#))
    }
}

final class CrosspostAndStubTests: XCTestCase {
    func testACrosspostOfATextPostShowsTheOriginalsTextButStaysALinkPost() {
        let p = Post.fromData(json(#"""
        {
          "id": "x2", "title": "Audio book app suggestion.", "subreddit": "audiobookshelf",
          "url": "/r/audiobooks/comments/abc/audio_book_app_suggestion/", "is_self": false, "selftext": "",
          "crosspost_parent_list": [
            { "subreddit": "audiobooks", "is_self": true, "selftext": "Can you suggest a good app?",
              "url": "https://www.reddit.com/r/audiobooks/comments/abc/audio_book_app_suggestion/" }
          ]
        }
        """#))
        XCTAssertEqual(p.type, .selfPost)
        XCTAssertEqual(p.selftext, "Can you suggest a good app?")
        XCTAssertEqual(p.crosspostFrom, "audiobooks")
        XCTAssertFalse(p.isSelf, "not editable as the user's own text")
    }

    func testContinueThisThreadStubsGetUniqueIds() {
        func stub(_ parent: String) -> Comment {
            Comment.fromChild(json(#"{"kind": "more", "data": {"id": "_", "name": "t1__", "parent_id": "\#(parent)", "count": 0, "children": []}}"#), 9)
        }
        let a = stub("t1_aaa")
        let b = stub("t1_bbb")
        XCTAssertNotEqual(a.fullname, b.fullname)
        XCTAssertEqual(a.parentId, "t1_aaa")
        XCTAssertEqual(a.moreChildren, [])
    }
}

final class PostPollTests: XCTestCase {
    private func p(_ poll: String) -> Post {
        Post.fromData(json(#"{"id":"p1","title":"Poll","subreddit":"polls","permalink":"/r/polls/comments/p1/poll/","poll_data":\#(poll)}"#))
    }

    func testBeforeVotingOptionsOnlyNoResults() {
        let x = p(#"{"options":[{"id":"11","text":"Yes"},{"id":"12","text":"No"}],"user_selection":null}"#)
        XCTAssertEqual(x.pollOptions, ["Yes", "No"])
        XCTAssertEqual(x.pollVotes, [])
        XCTAssertNil(x.pollChoice)
    }

    func testAfterVotingCountsAndYourChoiceLineUpWithTheOptions() {
        let x = p(#"{"options":[{"id":"11","text":"Yes","vote_count":30},{"id":"x","text":""},{"id":"12","text":"No","vote_count":10}],"user_selection":"12"}"#)
        XCTAssertEqual(x.pollOptions, ["Yes", "No"])
        XCTAssertEqual(x.pollVotes, [30, 10])
        XCTAssertEqual(x.pollChoice, 1)
    }
}

/// Port of test/post_video_detection_test.dart.
final class PostVideoDetectionTests: XCTestCase {
    func testACrosspostedVReddItVideoIsAVideoNotALink() {
        // Shape of a real crosspost: no media of its own, the video on the parent.
        let p = Post.fromData(json(#"""
        { "id": "x1", "title": "Crossposted clip", "subreddit": "funny", "url": "https://v.redd.it/abc123",
          "domain": "v.redd.it", "is_video": false, "media": null,
          "crosspost_parent_list": [ { "subreddit": "videos", "is_video": true,
            "media": { "reddit_video": { "hls_url": "https://v.redd.it/abc123/HLSPlaylist.m3u8?a=1",
              "fallback_url": "https://v.redd.it/abc123/DASH_720.mp4" } } } ] }
        """#))
        XCTAssertEqual(p.type, .video)
        XCTAssertEqual(p.hlsUrl, "https://v.redd.it/abc123/HLSPlaylist.m3u8?a=1")
        XCTAssertEqual(p.fallbackVideoUrl, "https://v.redd.it/abc123/DASH_720.mp4")
    }

    func testACrosspostedGalleryIsAGallery() {
        let p = Post.fromData(json(#"""
        { "id": "x2", "title": "Crossposted gallery", "url": "https://www.reddit.com/gallery/g1",
          "crosspost_parent_list": [ { "gallery_data": { "items": [ { "media_id": "m1" } ] },
            "media_metadata": { "m1": { "s": { "u": "https://preview.redd.it/m1.jpg", "x": 800, "y": 600 } } } } ] }
        """#))
        XCTAssertEqual(p.type, .gallery)
        XCTAssertEqual(p.gallery.map(\.url), ["https://preview.redd.it/m1.jpg"])
    }

    func testABareVReddItLinkWithNoMetadataGetsItsHlsStream() {
        let p = Post.fromData(json(#"{ "id": "x3", "title": "Bare link", "url": "https://v.redd.it/zzz999", "domain": "v.redd.it" }"#))
        XCTAssertEqual(p.type, .video)
        XCTAssertEqual(p.hlsUrl, "https://v.redd.it/zzz999/HLSPlaylist.m3u8")
    }

    func testAnOrdinaryLinkIsStillALink() {
        let p = Post.fromData(json(#"{ "id": "x4", "title": "Article", "url": "https://example.com/story", "domain": "example.com" }"#))
        XCTAssertEqual(p.type, .link)
        XCTAssertNil(p.hlsUrl)
    }
}

final class PostParsingTests: XCTestCase {
    func testAFullListingPost() {
        let p = Post.fromData(json(#"""
        { "id": "abc", "name": "t3_abc", "title": "  Hi  ", "subreddit": "pics", "subreddit_name_prefixed": "r/pics",
          "author": "me", "score": 5, "num_comments": 2, "upvote_ratio": 0.9, "created_utc": 1700000000.0,
          "permalink": "/r/pics/comments/abc/hi/", "url": "https://i.redd.it/a.jpg", "domain": "i.redd.it",
          "likes": true, "thumbnail": "self", "link_flair_text": "  ", "suggested_sort": "qa",
          "sr_detail": {"community_icon": "https://x/i.png?a=1&amp;b=2", "icon_img": ""},
          "preview": {"images": [{"source": {"url": "https://p/full.jpg", "width": 2000, "height": 1000},
            "resolutions": [{"url": "https://p/s.jpg", "width": 320}, {"url": "https://p/m.jpg", "width": 640}, {"url": "https://p/l.jpg", "width": 1080}],
            "variants": {"nsfw": {"resolutions": [{"url": "https://p/b1.jpg", "width": 108}, {"url": "https://p/b2.jpg", "width": 320}]}}}]} }
        """#))
        XCTAssertEqual(p.title, "Hi")
        XCTAssertEqual(p.createdUtc, 1_700_000_000_000)
        XCTAssertEqual(p.likes, true)
        XCTAssertNil(p.thumbnailUrl)
        XCTAssertNil(p.linkFlairText)
        XCTAssertEqual(p.suggestedSort, "qa")
        XCTAssertEqual(p.subredditIcon, "https://x/i.png?a=1&b=2")
        XCTAssertEqual(p.previewUrl, "https://p/full.jpg")
        XCTAssertEqual(p.previewMedUrl, "https://p/m.jpg")
        XCTAssertEqual(p.blurredPreviewUrl, "https://p/b2.jpg")
        XCTAssertEqual(p.previewWidth, 2000)
        XCTAssertEqual(p.type, .image)
    }

    func testSnippetDropsMediaAndFollowsAnEdit() {
        let p = Post.fromData(json(#"{"id":"a","selftext":"hello\n\nhttps://i.redd.it/a.jpg"}"#))
        XCTAssertEqual(p.snippet, "hello")
        XCTAssertEqual(p.with { $0.selftext = "new https://x" }.snippet, "new https://x")
    }

    func testInboxItemRefs() {
        let i = InboxItem.fromChild(json(#"{"kind":"t1","data":{"name":"t1_c","type":"post_reply","context":"/r/pics/comments/abc/slug/c1/?context=3","author":"a","body":"b"}}"#))
        XCTAssertEqual(i.kind, .postReply)
        XCTAssertEqual(i.postRef?.subreddit, "pics")
        XCTAssertEqual(i.postRef?.postId, "abc")
        XCTAssertEqual(i.contextCommentId, "c1")
        let m = InboxItem.fromChild(json(#"{"kind":"t4","data":{"id":"x","subject":" Hi ","replies":{"data":{"children":[{"kind":"t4","data":{"id":"y"}}]}}}}"#))
        XCTAssertTrue(m.isMessage)
        XCTAssertEqual(m.fullname, "t4_x")
        XCTAssertEqual(m.subject, "Hi")
        XCTAssertEqual(m.replies.map(\.fullname), ["t4_y"])
    }

    func testUserAndSubredditCleanUrls() {
        let u = RedditUser.fromData(json(#"{"name":"me","icon_img":"https://x/a.png?s=1&amp;t=2","subreddit":{"banner_img":"","public_description":" d ","user_is_subscriber":true}}"#))
        XCTAssertEqual(u.iconUrl, "https://x/a.png")
        XCTAssertNil(u.bannerUrl)
        XCTAssertEqual(u.description, "d")
        XCTAssertTrue(u.following)
        let s = Subreddit.fromData(json(#"{"display_name":"pics","community_icon":"","icon_img":"https://x/b.png?a&amp;b"}"#))
        XCTAssertEqual(s.namePrefixed, "r/pics")
        XCTAssertEqual(s.iconUrl, "https://x/b.png?a&b")
        XCTAssertNil(s.userIsSubscriber)
    }

    func testMultireddit() {
        let m = Multireddit.fromData(json(#"{"name":"f","path":"/user/me/m/f/","subreddits":[{"name":"a"},{"name":""}],"icon_url":""}"#))
        XCTAssertEqual(m.displayName, "f")
        XCTAssertEqual(m.subreddits, ["a"])
        XCTAssertEqual(m.visibility, "private")
        XCTAssertNil(m.iconUrl)
    }
}

/// Port of test/comment_media_test.dart.
final class CommentMediaTests: XCTestCase {
    func testAGifOnlyCommentResolvesItsGiphyMedia() {
        let c = Comment.fromChild(json(#"""
        {"kind": "t1", "data": {
          "id": "c1", "name": "t1_c1", "author": "mrsir1987",
          "body": "![gif](giphy|3o7btPCcdNniyf0ArS|downsized)",
          "score": 6100, "created_utc": 1700000000,
          "media_metadata": {
            "giphy|3o7btPCcdNniyf0ArS|downsized": {
              "status": "valid", "e": "AnimatedImage", "m": "image/gif",
              "s": {"y": 200,
                    "gif": "https://external-preview.redd.it/abc.gif?width=200&amp;height=200&amp;s=x",
                    "mp4": "https://external-preview.redd.it/abc.gif?format=mp4&amp;s=y",
                    "x": 200},
              "t": "giphy", "id": "giphy|3o7btPCcdNniyf0ArS|downsized"
            },
            "emote|t5_2qh1i|1234": { "status": "valid", "e": "Image", "s": {"u": "https://reddit-econ.example/emote.png"} }
          }
        }}
        """#), 0)
        XCTAssertEqual(Array(c.media.keys), ["giphy|3o7btPCcdNniyf0ArS|downsized"])
        let segs = bodySegments(c.body, c.media, 3)
        guard segs.count == 1, case .media(let u) = segs[0] else { return XCTFail("\(segs)") }
        XCTAssertEqual(u.absoluteString, "https://external-preview.redd.it/abc.gif?width=200&height=200&s=x")
        XCTAssertTrue(isImageUrl(u))
        XCTAssertTrue(isGifUrl(u))
    }

    func testTextAroundAMediaRefIsKeptUnknownRefsAreLeftAlone() {
        let segs = bodySegments("lol ![gif](giphy|a) and ![img](missing)", ["giphy|a": "https://i.redd.it/a.gif"], 3)
        XCTAssertEqual(segs, [.text("lol"), .media(URL(string: "https://i.redd.it/a.gif")!), .text("and ![img](missing)")])
    }
}
