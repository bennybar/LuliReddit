import XCTest
@testable import Ilay

private func post(_ id: String, _ type: PostType, change: (inout Post) -> Void = { _ in }) -> Post {
    var p = Post(
        id: id, fullname: "t3_\(id)", title: "t", subreddit: "pics", subredditPrefixed: "r/pics", author: "a",
        score: 1, numComments: 0, upvoteRatio: 1, createdUtc: 0, permalink: "/p/\(id)", url: "https://example.com/\(id)", domain: "example.com", type: type
    )
    change(&p)
    return p
}

private func image(_ id: String) -> Post { post(id, .image) { $0.previewUrl = "https://i.redd.it/\(id).jpg" } }
private func text(_ id: String) -> Post { post(id, .selfPost) }

/// The media browser's pure parts (#103): what counts as media, where it starts, paging.
final class MediaBrowserTests: XCTestCase {
    func testClassifiesMediaLikeTappingThePost() {
        XCTAssertEqual(MediaBrowseFeed.media(image("a")), .images(["https://i.redd.it/a.jpg"]))
        XCTAssertEqual(MediaBrowseFeed.media(post("b", .image)), .images(["https://example.com/b"]))
        XCTAssertEqual(MediaBrowseFeed.media(post("c", .gif) { $0.gifMp4Url = "https://x/c.mp4" }), .video("https://x/c.mp4", redgifs: false))
        XCTAssertEqual(MediaBrowseFeed.media(post("d", .gif)), .images(["https://example.com/d"]))
        let gallery = post("e", .gallery) { $0.gallery = [GalleryImage(url: "https://x/1.jpg"), GalleryImage(url: "https://x/2.jpg")] }
        XCTAssertEqual(MediaBrowseFeed.media(gallery), .images(["https://x/1.jpg", "https://x/2.jpg"]))
        XCTAssertNil(MediaBrowseFeed.media(post("f", .gallery)))
        XCTAssertEqual(MediaBrowseFeed.media(post("g", .video) { $0.hlsUrl = "https://v.redd.it/g/HLS.m3u8" }), .video("https://v.redd.it/g/HLS.m3u8", redgifs: false))
        let redgifs = post("h", .video) {
            $0.url = "https://www.redgifs.com/watch/somethingcute"
            $0.gifMp4Url = "https://x/h.mp4"
        }
        XCTAssertEqual(MediaBrowseFeed.media(redgifs), .video("https://x/h.mp4", redgifs: true))
        // YouTube plays in its own app: nothing to browse.
        XCTAssertNil(MediaBrowseFeed.media(post("i", .video) { $0.url = "https://www.youtube.com/watch?v=x"; $0.domain = "youtube.com" }))
        XCTAssertNil(MediaBrowseFeed.media(text("j")))
        XCTAssertNil(MediaBrowseFeed.media(post("k", .link)))
    }

    func testStartsAtTheFirstMediaPostAtOrBelowTheTopOne() {
        let feed = [image("a"), text("b"), text("c"), image("d"), image("e")]
        XCTAssertEqual(MediaBrowseFeed(visible: feed, loaded: 5, startId: "b").posts.map(\.id), ["d", "e"])
        XCTAssertEqual(MediaBrowseFeed(visible: feed, loaded: 5, startId: "d").posts.map(\.id), ["d", "e"])
        XCTAssertEqual(MediaBrowseFeed(visible: feed, loaded: 5, startId: nil).posts.map(\.id), ["a", "d", "e"])
        // The top post filtered out meanwhile: from the top.
        XCTAssertEqual(MediaBrowseFeed(visible: feed, loaded: 5, startId: "zz").posts.map(\.id), ["a", "d", "e"])
        XCTAssertTrue(MediaBrowseFeed(visible: [text("a")], loaded: 1, startId: "a").posts.isEmpty)
    }

    func testNewPagesAddOnlyTheirMediaOnce() {
        var feed = MediaBrowseFeed(visible: [image("a"), text("b"), image("c")], loaded: 3, startId: "b")
        XCTAssertEqual(feed.posts.map(\.id), ["c"])
        // A new page; "a" (above the start) and "c" are known already, "c" dropped as read.
        XCTAssertTrue(feed.update([image("a"), text("b"), text("d"), image("e"), image("f")], loaded: 6))
        XCTAssertEqual(feed.posts.map(\.id), ["c", "e", "f"])
        XCTAssertFalse(feed.update([image("a"), text("b"), text("d"), image("e"), image("f")], loaded: 6))
    }

    func testAsksForMoreNearTheEndAndGivesUpAfterPagesWithoutMedia() {
        var feed = MediaBrowseFeed(visible: (0..<6).map { image("\($0)") }, loaded: 6, startId: nil)
        XCTAssertFalse(feed.wantsMore(at: 0))
        XCTAssertFalse(feed.wantsMore(at: 2))
        XCTAssertTrue(feed.wantsMore(at: 3))
        var visible = feed.posts
        for page in 0..<MediaBrowseFeed.maxBarrenPages {
            XCTAssertTrue(feed.wantsMore(at: 5), "page \(page)")
            visible += (0..<5).map { text("t\(page)-\($0)") }
            feed.update(visible, loaded: visible.count)
        }
        XCTAssertFalse(feed.wantsMore(at: 5))
        // Media again: it keeps going.
        visible.append(image("m"))
        feed.update(visible, loaded: visible.count)
        XCTAssertEqual(feed.posts.last?.id, "m")
        XCTAssertTrue(feed.wantsMore(at: 5))
        // An empty feed wants a page straight away.
        XCTAssertTrue(MediaBrowseFeed(visible: [], loaded: 0, startId: nil).wantsMore(at: 0))
    }

    func testAPageFilteredOutEntirelyStillCountsAsWithoutMedia() {
        var feed = MediaBrowseFeed(visible: [image("a")], loaded: 1, startId: nil)
        for loaded in 2...(1 + MediaBrowseFeed.maxBarrenPages) { feed.update([image("a")], loaded: loaded * 25) }
        XCTAssertFalse(feed.wantsMore(at: 0))
    }
}
