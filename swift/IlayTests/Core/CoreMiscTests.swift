import XCTest
@testable import Ilay

final class SharedTextTests: XCTestCase {
    func testABarePostLink() {
        let url = "https://www.reddit.com/r/Android/comments/abc123/some_title/"
        XCTAssertEqual(redditUrlInText(url), url)
    }

    func testATitleBeforeTheLinkAndTrailingPunctuation() {
        XCTAssertEqual(redditUrlInText("Check this out: https://reddit.com/r/apple/s/AbCdEf."), "https://reddit.com/r/apple/s/AbCdEf")
    }

    func testSkipsLinksThatArentReddit() {
        XCTAssertEqual(redditUrlInText("via https://example.com/a then https://redd.it/xyz"), "https://redd.it/xyz")
    }

    func testNoRedditLink() {
        XCTAssertNil(redditUrlInText("just some text https://example.com"))
        XCTAssertNil(redditUrlInText(nil))
    }
}

/// Port of the Flutter build's test/app_version_test.dart: the update checker
/// compares GitHub's latest release with the app version; if they disagree,
/// an up-to-date install keeps being offered its own version.
final class AppVersionTests: XCTestCase {
    func testAppVersionIsTheBuildsVersion() {
        XCTAssertNotNil(Re(#"^\d+\.\d+\.\d+(-[A-Za-z0-9]+)?$"#).matchEntire(RedditConstants.appVersion))
    }

    func testTheInstalledVersionIsNeverOfferedAsAnUpdate() {
        XCTAssertEqual(UpdateChecker.compareVersions(RedditConstants.appVersion, RedditConstants.appVersion), 0)
    }

    func testVersionsOrderSemverIshPrereleasesBeforeTheirRelease() {
        let ordered = ["1.0.9", "1.0.50", "1.0.51", "2.0.0-beta1", "2.0.0-beta2", "2.0.0-rc1", "2.0.0", "2.0.1", "10.0.0"]
        for (i, a) in ordered.enumerated() {
            for (j, b) in ordered.enumerated() {
                let got = UpdateChecker.compareVersions(a, b).signum()
                XCTAssertEqual(got, (i - j).signum(), "\(a) vs \(b)")
            }
        }
    }

    func testMissingPartsCountAsZero() {
        XCTAssertEqual(UpdateChecker.compareVersions("2.0", "2.0.0"), 0)
        XCTAssertLessThan(UpdateChecker.compareVersions("1.0.51", "2"), 0)
    }
}

final class AnalyticsBucketTests: XCTestCase {
    func testPostsOpenedBuckets() {
        XCTAssertEqual(Analytics.bucket(1, 1, 5, 20), "1")
        XCTAssertEqual(Analytics.bucket(2, 1, 5, 20), "2-5")
        XCTAssertEqual(Analytics.bucket(5, 1, 5, 20), "2-5")
        XCTAssertEqual(Analytics.bucket(6, 1, 5, 20), "6-20")
        XCTAssertEqual(Analytics.bucket(300, 1, 5, 20), "21+")
    }

    func testHomePostBuckets() {
        XCTAssertEqual(Analytics.bucket(0, 0, 9), "0")
        XCTAssertEqual(Analytics.bucket(7, 0, 9), "1-9")
        XCTAssertEqual(Analytics.bucket(10, 0, 9), "10+")
    }
}

final class TranslateTests: XCTestCase {
    func testBatchesKeepOrderAndRespectBothLimits() {
        let texts = ["aaaa", "bb", "cccccc", "d", "ee"]
        XCTAssertEqual(Translate.batches(texts, maxChars: 6, maxCount: 10), [["aaaa", "bb"], ["cccccc"], ["d", "ee"]])
        XCTAssertEqual(Translate.batches(texts, maxChars: 100, maxCount: 2), [["aaaa", "bb"], ["cccccc", "d"], ["ee"]])
        // A text longer than the limit goes alone.
        XCTAssertEqual(Translate.batches(["aaaa", "bb"], maxChars: 3, maxCount: 10), [["aaaa"], ["bb"]])
    }

    func testOldJavaLanguageCodesBecomeTheUsualOnes() {
        XCTAssertEqual(Translate.norm("iw"), "he")
        XCTAssertEqual(Translate.norm("in"), "id")
        XCTAssertEqual(Translate.norm("de"), "de")
    }
}

final class MediaLinksTests: XCTestCase {
    private func texts(_ s: [BodySegment]) -> [String] {
        s.map {
            switch $0 {
            case .text(let t): return "T:\(t)"
            case .media(let u): return "M:\(u.absoluteString)"
            }
        }
    }

    func testAParagraphThatIsOnlyAMediaLinkBecomesMediaInPlace() {
        let body = "Look at this\n\nhttps://preview.redd.it/abc.png?width=640&s=x\n\nThat's it"
        XCTAssertEqual(texts(bodySegments(body, [:], 10)), ["T:Look at this", "M:https://preview.redd.it/abc.png?width=640&s=x", "T:That's it"])
    }

    func testMarkdownLinkToAnImageCountsAsALoneMediaParagraph() {
        XCTAssertEqual(texts(bodySegments("[image](https://i.redd.it/xyz.jpg)", [:], 10)), ["M:https://i.redd.it/xyz.jpg"])
    }

    func testUploadedMediaRefsResolveFromMediaMetadata() {
        let segs = texts(bodySegments("before ![img](abc123) after", ["abc123": "https://i.redd.it/abc123.png"], 10))
        XCTAssertEqual(segs, ["T:before", "M:https://i.redd.it/abc123.png", "T:after"])
    }

    func testMediaInsideASentenceFollowsItsParagraphAndPlainLinksStayText() {
        let body = "see https://i.redd.it/a.jpg here and https://example.com"
        XCTAssertEqual(texts(bodySegments(body, [:], 10)), ["T:see https://i.redd.it/a.jpg here and https://example.com", "M:https://i.redd.it/a.jpg"])
    }

    func testMediaCountIsCapped() {
        let body = (1...5).map { "https://i.redd.it/\($0).jpg" }.joined(separator: "\n\n")
        let media = bodySegments(body, [:], 2).filter { if case .media = $0 { return true } else { return false } }
        XCTAssertEqual(media.count, 2)
    }

    func testAnEmbeddedRedditVideoLinkIsItsVReddItVideo() {
        XCTAssertEqual(inlineRedditVideo(URL(string: "https://reddit.com/link/pdnkxg6/video/pom8yboslath1/player")!)?.absoluteString, "https://v.redd.it/pom8yboslath1")
        XCTAssertNil(inlineRedditVideo(URL(string: "https://www.reddit.com/r/videos/comments/abc/x/")!))
        XCTAssertEqual(resolveVideoUrl("https://reddit.com/link/pdnkxg6/video/pom8yboslath1/player"), "https://v.redd.it/pom8yboslath1/HLSPlaylist.m3u8")
        XCTAssertEqual(resolveVideoUrl("https://v.redd.it/abc"), "https://v.redd.it/abc/HLSPlaylist.m3u8")
        XCTAssertEqual(resolveVideoUrl("https://i.imgur.com/a.gifv"), "https://i.imgur.com/a.mp4")
    }

    func testAnInvalidOrMissingGiphyEntryFallsBackToGiphysOwnCopy() {
        let segs = texts(bodySegments("I could've taken him down!\n![gif](giphy|7AoJzTRD1WzOU)", [:], 3))
        XCTAssertEqual(segs, ["T:I could've taken him down!", "M:https://media.giphy.com/media/7AoJzTRD1WzOU/giphy.webp"])
        XCTAssertNil(giphyUrl("abc123"))
        XCTAssertEqual(giphyUrl("giphy|x1|downsized"), "https://media.giphy.com/media/x1/giphy.webp")
    }

    func testBodiesKeepTheirMarkdownStructure() {
        let code = "Try:\n\n    val x = 1\n    val y = 2"
        XCTAssertEqual(texts(bodySegments(code, [:], 3)), ["T:\(code)"])
        // With media present, indentation of other paragraphs survives too.
        XCTAssertEqual(texts(bodySegments("Try:\n\n    code here\n\nhttps://i.redd.it/a.jpg", [:], 3)), ["T:Try:\n\n    code here", "M:https://i.redd.it/a.jpg"])
    }

    func testTextWithoutMedia() {
        XCTAssertEqual(textWithoutMedia("hello ![img](a)\n\nhttps://i.redd.it/x.jpg\n\nhttps://example.com\n\nbye"), "hello\n\nhttps://example.com\n\nbye")
    }
}

final class DeepLinksTests: XCTestCase {
    private func route(_ s: String) -> Route? { routeForRedditUrl(URL(string: s)!) }

    func testRoutes() {
        XCTAssertEqual(route("https://redd.it/abc"), .post(subreddit: "_", postId: "abc"))
        XCTAssertEqual(route("https://www.reddit.com/r/pics/comments/abc/slug/def/"), .post(subreddit: "pics", postId: "abc", focusCommentId: "def"))
        XCTAssertEqual(route("https://reddit.com/comments/abc"), .post(subreddit: "_", postId: "abc"))
        XCTAssertEqual(route("https://www.reddit.com/gallery/abc"), .post(subreddit: "_", postId: "abc"))
        XCTAssertEqual(route("https://www.reddit.com/user/me/m/feed"), .multireddit(username: "me", name: "feed"))
        XCTAssertEqual(route("https://www.reddit.com/u/me"), .user(username: "me"))
        XCTAssertEqual(route("https://old.reddit.com/r/pics/"), .subreddit(name: "pics"))
        XCTAssertNil(route("https://www.reddit.com/r/pics/s/code"), "a share link must be resolved first")
        XCTAssertNil(route("https://example.com/r/pics"))
    }

    func testShareLinks() {
        XCTAssertTrue(isShareLink(URL(string: "https://www.reddit.com/r/pics/s/abc")!))
        XCTAssertTrue(isShareLink(URL(string: "https://www.reddit.com/u/me/s/abc")!))
        XCTAssertFalse(isShareLink(URL(string: "https://www.reddit.com/r/pics/comments/abc")!))
        XCTAssertFalse(isShareLink(URL(string: "https://example.com/r/pics/s/abc")!))
    }

    func testHosts() {
        XCTAssertTrue(isRedditHost("REDDIT.com"))
        XCTAssertTrue(isRedditHost("v.redd.it"))
        XCTAssertFalse(isRedditHost("notreddit.com"))
        XCTAssertFalse(isRedditHost(nil))
        XCTAssertTrue(isRedditMediaHost("i.redd.it"))
        XCTAssertFalse(isRedditMediaHost("redd.it"))
    }
}

final class WebTokenTests: XCTestCase {
    private let now = 1_800_000_000_000

    func testReadsReplacesAddsAndRemovesCookiesInAHeader() {
        let h = "loid=1; token_v2=old; reddit_session=s"
        XCTAssertEqual(cookieValue(h, "token_v2"), "old")
        XCTAssertNil(cookieValue(h, "csrf_token"))
        XCTAssertEqual(withCookie(h, "token_v2", "new"), "loid=1; token_v2=new; reddit_session=s")
        XCTAssertEqual(withCookie(h, "token_v2", nil), "loid=1; reddit_session=s")
        XCTAssertEqual(withCookie(h, "csrf_token", "c"), "loid=1; token_v2=old; reddit_session=s; csrf_token=c")
    }

    func testATokenExpiringSoonMissingOrUnreadableNeedsRenewing() {
        func header(_ exp: Int) -> String { "reddit_session=s; token_v2=\(jwt(#"{"exp":\#(exp / 1000),"lid":"t2_x"}"#))" }
        XCTAssertFalse(needsNewToken(header(now + 20 * 3_600_000), now: now))
        XCTAssertTrue(needsNewToken(header(now + 2 * 60_000), now: now))
        XCTAssertTrue(needsNewToken(header(now - 3 * 86_400_000), now: now))
        XCTAssertTrue(needsNewToken("reddit_session=s", now: now))
        XCTAssertTrue(needsNewToken("token_v2=garbage", now: now))
    }

    func testRedditsExpiryHasAFractionOfASecond() {
        XCTAssertEqual(tokenExpiry(jwt(#"{"exp":1793307492.7951}"#)), 1_793_307_492_795)
    }

    func testSetCookieHeadersUpdateTheHeaderAndDeletedCookiesDropOut() {
        XCTAssertEqual(
            mergeSetCookies("loid=1; reddit_session=s", [
                "token_v2=fresh; Domain=.reddit.com; Path=/; Max-Age=86400; Secure",
                "csrf_token=c; Path=/",
                "loid=; Max-Age=0",
            ]),
            "reddit_session=s; token_v2=fresh; csrf_token=c"
        )
    }

    func testReadsTheAccountARedditSessionBelongsTo() {
        XCTAssertEqual(sessionAccount("loid=1; reddit_session=\(jwt(#"{"sub":"t2_abc","exp":1}"#))"), "t2_abc")
        XCTAssertNil(sessionAccount("loid=1; reddit_session=opaque"))
        XCTAssertNil(sessionAccount("loid=1"))
    }

    // URLSession joins repeated Set-Cookie headers with ", ", and a cookie's Expires has a comma of its own.
    func testJoinedSetCookieHeadersSplitBackApart() {
        let joined = "token_v2=fresh; Expires=Thu, 01 Jan 2027 00:00:00 GMT; Path=/, loid=; Max-Age=0, csrf_token=c; Secure"
        let res = HTTPURLResponse(url: URL(string: "https://www.reddit.com/")!, statusCode: 200, httpVersion: nil, headerFields: ["Set-Cookie": joined])!
        XCTAssertEqual(setCookies(res), ["token_v2=fresh; Expires=Thu, 01 Jan 2027 00:00:00 GMT; Path=/", "loid=; Max-Age=0", "csrf_token=c; Secure"])
        XCTAssertEqual(mergeSetCookies("loid=1", setCookies(res)), "token_v2=fresh; csrf_token=c")
    }
}

final class RedgifsTests: XCTestCase {
    func testClipIds() {
        XCTAssertEqual(Redgifs.id("https://www.redgifs.com/watch/SomeClip"), "someclip")
        XCTAssertEqual(Redgifs.id("https://redgifs.com/ifr/abc"), "abc")
        XCTAssertEqual(Redgifs.id("https://i.redgifs.com/i/abc-mobile.jpg"), "abc")
        XCTAssertNil(Redgifs.id("https://example.com/watch/abc"))
        XCTAssertNil(Redgifs.id("https://redgifs.com/users/abc/x"))
    }
}
