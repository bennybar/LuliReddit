import SwiftUI
import UIKit
import XCTest
@testable import Ilay

@MainActor private func eventually(_ condition: () -> Bool) async {
    for _ in 0..<500 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
    XCTAssertTrue(condition(), "timed out")
}

private func post(_ id: String, type: PostType = .selfPost, sub: String = "pics", title: String = "t", change: (inout Post) -> Void = { _ in }) -> Post {
    var p = Post(
        id: id, fullname: "t3_\(id)", title: title, subreddit: sub, subredditPrefixed: "r/\(sub)", author: "a",
        score: 1, numComments: 0, upvoteRatio: 1, createdUtc: 0, permalink: "/p/\(id)", url: "https://example.com/\(id)", domain: "example.com", type: type
    )
    change(&p)
    return p
}

private func config(_ display: PostDisplay, width: CGFloat = 402, carousel: Bool = true, autoplay: Bool = true) -> FeedRowConfig {
    FeedRowConfig(
        display: display, midResThumbnails: true, blurNsfw: true, autoplayMedia: autoplay, feedGalleryCarousel: carousel,
        subredditIcons: true, trackHistory: true, dimReadTextOnly: false, dimRead: true, seedColor: 0, textScale: 1, width: width, scale: 3
    )
}

/// Port of FabScrollTest.kt.
@MainActor final class FabScrollTests: XCTestCase {
    func testFoldsScrollingDownOpensScrollingUpAndIgnoresFlingsAndJitter() {
        let fab = FabScroll()
        XCTAssertTrue(fab.expanded)
        fab.onScroll(available: -20, userInput: true)
        XCTAssertFalse(fab.expanded)
        fab.onScroll(available: 0.5, userInput: true)
        XCTAssertFalse(fab.expanded)
        fab.onScroll(available: 20, userInput: false)
        XCTAssertFalse(fab.expanded)
        fab.onScroll(available: 20, userInput: true)
        XCTAssertTrue(fab.expanded)
    }
}

/// Port of PagedSourceTest.kt.
@MainActor final class PagedSourceTests: XCTestCase {
    func testAPageFetchedBeforeARefreshDoesNotLandOnTheRefreshedList() async {
        var firstPages = 0
        var oldSecond: CheckedContinuation<Listing<String>, Never>?
        let source = PagedSource<String> { @MainActor after in
            if after == nil {
                firstPages += 1
                return firstPages == 1 ? Listing(items: ["old-first"], after: "p2") : Listing(items: ["fresh-first"], after: "p2-fresh")
            }
            return await withCheckedContinuation { oldSecond = $0 }
        }
        source.start()
        await eventually { !source.state.loading }
        source.loadMore() // page two of the old list, still in flight…
        await eventually { oldSecond != nil }
        let refresh = source.load() // …when the list is refreshed
        oldSecond?.resume(returning: Listing(items: ["old-second"], after: "p3"))
        await refresh.value
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(source.state.items, ["fresh-first"])
        XCTAssertEqual(source.state.after, "p2-fresh")
        XCTAssertFalse(source.state.loadingMore)
    }

    func testASilentRefreshFailingKeepsTheList() async {
        var fail = false
        let source = PagedSource<String> { @MainActor _ in
            if fail { throw URLError(.notConnectedToInternet) }
            return Listing(items: ["a"], after: nil)
        }
        source.start()
        await eventually { !source.state.loading }
        fail = true
        await source.load(silent: true).value
        XCTAssertEqual(source.state.items, ["a"])
        XCTAssertNil(source.state.error)
    }
}

/// SwipeActionsTest.kt tested a hand-made gesture state machine. Swipes are UIKit's list
/// swipes here, as in Mail, which handle dragging, thresholds, the haptic and right-to-left
/// mirroring. What's ours is what each side means.
final class PostSwipeTests: XCTestCase {
    func testASideWithNoActionDoesNothing() {
        XCTAssertNil(PostSwipe.effective(.none, dismissible: true, frontpage: true))
        XCTAssertNil(PostSwipe.effective(.collapse, dismissible: true, frontpage: true))
    }

    func testDismissOnlyInHomeAndForYou() {
        XCTAssertEqual(PostSwipe.effective(.dismiss, dismissible: true, frontpage: true), .dismiss)
        XCTAssertNil(PostSwipe.effective(.dismiss, dismissible: false, frontpage: true))
    }

    func testHideSubredditOnlyOnTheFrontPage() {
        XCTAssertEqual(PostSwipe.effective(.hideSub, dismissible: false, frontpage: true), .hideSub)
        XCTAssertNil(PostSwipe.effective(.hideSub, dismissible: true, frontpage: false))
    }

    func testTheRestApplyEverywhere() {
        for action: SwipeAction in [.upvote, .downvote, .save, .reply, .hide] {
            XCTAssertEqual(PostSwipe.effective(action, dismissible: false, frontpage: false), action)
        }
    }
}

final class FeedPagingTests: XCTestCase {
    func testNearEnd() {
        XCTAssertFalse(PostListCoordinator.isNearEnd(lastVisible: 3, total: 26, fromEnd: 11))
        XCTAssertTrue(PostListCoordinator.isNearEnd(lastVisible: 15, total: 26, fromEnd: 11))
        XCTAssertFalse(PostListCoordinator.isNearEnd(lastVisible: 0, total: 0, fromEnd: 11))
    }

    func testAMultiredditKey() {
        XCTAssertEqual(FeedController.multi("m::me::cats")?.user, "me")
        XCTAssertEqual(FeedController.multi("m::me::cats")?.name, "cats")
        XCTAssertNil(FeedController.multi("m::broken"))
        XCTAssertNil(FeedController.multi("cats"))
    }
}

final class VisibilityDwellTests: XCTestCase {
    func testOnlyASecondAtSixtyPercentCountsAndOnlyOnce() {
        var d = VisibilityDwell()
        XCTAssertEqual(d.update(fractions: ["a": 0.7, "b": 0.5], now: 0), [])
        XCTAssertEqual(d.update(fractions: ["a": 0.7, "b": 0.5], now: 0.5), [])
        XCTAssertEqual(d.update(fractions: ["a": 0.7, "b": 0.5], now: 1), ["a"])
        XCTAssertEqual(d.update(fractions: ["a": 0.7, "b": 0.5], now: 3), [])
    }

    func testAFlungPastCardDoesNotCountAndComingBackCountsAgain() {
        var d = VisibilityDwell()
        _ = d.update(fractions: ["a": 1], now: 0)
        XCTAssertEqual(d.update(fractions: [:], now: 0.5), [])
        XCTAssertEqual(d.update(fractions: ["a": 1], now: 1), [])
        XCTAssertEqual(d.update(fractions: ["a": 1], now: 2), ["a"])
        _ = d.update(fractions: [:], now: 3)
        _ = d.update(fractions: ["a": 1], now: 4)
        XCTAssertEqual(d.update(fractions: ["a": 1], now: 5), ["a"])
    }
}

final class FeedVisibilityTests: XCTestCase {
    private func visible(_ posts: [Post], seen: Set<String>? = nil, hidden: Set<String> = [], dismissed: Set<String> = [], subs: Set<String> = [], filters: ContentFilters = ContentFilters(), viewing: String? = nil) -> [String] {
        FeedVisibility(posts: posts, seen: seen, hiddenIds: hidden, dismissedIds: dismissed, hiddenSubs: subs, filters: filters, viewing: viewing).visible().map(\.id)
    }

    func testHiddenDismissedAndHiddenSubreddits() {
        let posts = [post("a"), post("b"), post("c", sub: "Cats"), post("d")]
        XCTAssertEqual(visible(posts, hidden: ["a"], dismissed: ["b"], subs: ["cats"]), ["d"])
    }

    func testAutoHideOnlyDropsPostsWithAReason() {
        let posts = [post("a"), post("b") { $0.feedReason = "why" }, post("c") { $0.feedReason = "why" }]
        XCTAssertEqual(visible(posts, seen: ["a", "b"]), ["a", "c"])
    }

    func testAFilteredSubredditStillShowsOnItsOwnPage() {
        let posts = [post("a", sub: "cats"), post("b", sub: "dogs")]
        let filters = ContentFilters(subreddits: ["cats"])
        XCTAssertEqual(visible(posts, filters: filters), ["b"])
        XCTAssertEqual(visible(posts, filters: filters, viewing: "cats"), ["a", "b"])
    }

    func testAPageBoundaryRepeatingAPostKeepsIdsUnique() {
        XCTAssertEqual(visible([post("a"), post("b"), post("a")]), ["a", "b"])
    }
}

/// Slots are fixed from the post's dimensions, so a cell never resizes when images arrive.
@MainActor final class PostRowTests: XCTestCase {
    private func image(_ w: Int?, _ h: Int?) -> Post {
        post("i", type: .image) {
            $0.previewUrl = "https://example.com/full.jpg"
            $0.previewMedUrl = "https://example.com/mid.jpg"
            $0.previewWidth = w
            $0.previewHeight = h
        }
    }

    private func slot(_ row: PostRow) -> (url: URL?, height: CGFloat, pixels: Int, play: Bool, pill: MediaPillInfo?)? {
        if case let .image(url, height, pixels, play, pill) = row.media { (url, height, pixels, play, pill) } else { nil }
    }

    func testDefaultKeepsTheShapeClampedOneToTwo() {
        let width = config(.large).mediaWidth
        XCTAssertEqual(slot(PostRow(image(1000, 1000), config: config(.large)))?.height, width.rounded())
        XCTAssertEqual(slot(PostRow(image(100, 1000), config: config(.large)))?.height, (width * 2).rounded())
        XCTAssertEqual(slot(PostRow(image(4000, 1000), config: config(.large)))?.height, (width / 2).rounded())
        XCTAssertEqual(slot(PostRow(image(nil, nil), config: config(.large)))?.height, (width * 9 / 16).rounded())
    }

    func testCardsIsAFixedBanner() {
        XCTAssertEqual(slot(PostRow(image(100, 1000), config: config(.card)))?.height, 180)
    }

    func testCalmFallsBackToSixteenByTen() {
        let width = config(.calm).mediaWidth
        XCTAssertEqual(slot(PostRow(image(nil, nil), config: config(.calm)))?.height, (width * 10 / 16).rounded())
    }

    func testCalmCardsMediaRunsEdgeToEdgeOfTheCard() {
        XCTAssertEqual(config(.calmCards, width: 400).mediaWidth, 376)
        XCTAssertEqual(config(.calm, width: 400).mediaWidth, 354)
        XCTAssertEqual(config(.large, width: 400).mediaWidth, 368)
    }

    func testMidResWhenTheDataSaverIsOnAndADirectLinkUsesItsUrl() {
        XCTAssertEqual(slot(PostRow(image(10, 10), config: config(.large)))?.url?.absoluteString, "https://example.com/mid.jpg")
        let direct = post("d", type: .image)
        XCTAssertEqual(slot(PostRow(direct, config: config(.large)))?.url?.absoluteString, direct.url)
    }

    func testTheCardAsksForWhatThePrefetcherWarmed() {
        let row = PostRow(image(1000, 500), config: config(.large))
        XCTAssertEqual(row.prefetch.first?.pixels, slot(row)?.pixels)
        XCTAssertEqual(row.prefetch.first?.url, slot(row)?.url)
    }

    func testMiniWarmsNothingButItsAvatar() {
        XCTAssertTrue(PostRow(image(10, 10), config: config(.mini)).prefetch.isEmpty)
        if case .thumbnail = PostRow(image(10, 10), config: config(.mini)).media {} else { XCTFail() }
    }

    func testABlurredMiniThumbnailShowsNoImage() {
        let p = post("n", type: .image) {
            $0.over18 = true
            $0.previewUrl = "https://example.com/x.jpg"
        }
        if case let .thumbnail(url, _, symbol, _) = PostRow(p, config: config(.mini)).media {
            XCTAssertNil(url)
            XCTAssertEqual(symbol, "eye.slash")
        } else {
            XCTFail()
        }
    }

    func testVideoPlaysInlineUnlessBlurredOffOrExternal() {
        let v = post("v", type: .video) {
            $0.hlsUrl = "https://v.redd.it/x/HLSPlaylist.m3u8"
            $0.previewWidth = 16
            $0.previewHeight = 9
        }
        if case .video = PostRow(v, config: config(.calm)).media {} else { XCTFail("inline") }
        if case .image = PostRow(v, config: config(.calm, autoplay: false)).media {} else { XCTFail("autoplay off") }
        var nsfw = v
        nsfw.over18 = true
        if case .image = PostRow(nsfw, config: config(.calm)).media {} else { XCTFail("blurred") }
        let external = post("y", type: .video) { $0.url = "https://youtube.com/watch?v=x"; $0.domain = "youtube.com" }
        let row = PostRow(external, config: config(.large))
        XCTAssertEqual(slot(row)?.pill?.label, "YouTube")
        XCTAssertEqual(row.externalVideoLabel, "YouTube")
    }

    func testGalleryCarouselHeightIsClampedAndOneImageIsNoCarousel() {
        let images = (0..<3).map { GalleryImage(url: "https://example.com/\($0).jpg", width: 1000, height: 1000) }
        let g = post("g", type: .gallery) { $0.gallery = images }
        if case let .gallery(carousel, _) = PostRow(g, config: config(.large)).media { XCTAssertEqual(carousel, 300) } else { XCTFail() }
        if case let .gallery(carousel, _) = PostRow(g, config: config(.card)).media { XCTAssertEqual(carousel, 220) } else { XCTFail() }
        if case let .gallery(carousel, _) = PostRow(g, config: config(.large, carousel: false)).media { XCTAssertNil(carousel) } else { XCTFail() }
        let one = post("o", type: .gallery) { $0.gallery = [images[0]] }
        if case let .gallery(carousel, _) = PostRow(one, config: config(.large)).media { XCTAssertNil(carousel) } else { XCTFail() }
    }

    func testBlurLabelsAndCalmReason() {
        let n = PostRow(post("n") { $0.over18 = true }, config: config(.calm))
        XCTAssertTrue(n.blur)
        XCTAssertEqual(n.blurLabel, "NSFW")
        let s = PostRow(post("s") { $0.spoiler = true }, config: config(.calm))
        XCTAssertEqual(s.blurLabel, "Spoiler")
        let r = PostRow(post("r") { $0.feedReason = "Popular · r/pics" }, config: config(.calm))
        XCTAssertEqual(r.calmReason, "Popular")
    }

    func testDecodeSizeCoversTheSlotInWholeSteps() {
        let slotSize = CGSize(width: 100, height: 100)
        XCTAssertEqual(feedDecodePixels(slot: slotSize, scale: 3, imageWidth: 100, imageHeight: 100), 320)
        // A 2:1 image: its height has to cover 100pt, so its long side is 200pt.
        XCTAssertEqual(feedDecodePixels(slot: slotSize, scale: 3, imageWidth: 2000, imageHeight: 1000), 640)
        // Unknown shape: half as much again as the slot, like RemoteImage.
        XCTAssertEqual(feedDecodePixels(slot: slotSize, scale: 3), 512)
        // A sliver of a very long image isn't worth a huge decode.
        XCTAssertEqual(feedDecodePixels(slot: slotSize, scale: 3, imageWidth: 100, imageHeight: 10_000), 640)
    }
}

@MainActor final class FeedControllerTests: XCTestCase {
    private final class Stub {
        var pages: [String?: Result<Listing<Post>, Error>] = [:]
        var cached: Listing<Post>?
        var calls: [String?] = []
        var gate: CheckedContinuation<Void, Never>?
        var holdNext = false

        var source: FeedSource {
            FeedSource(
                posts: { @MainActor [self] _, _, after in
                    calls.append(after)
                    if holdNext {
                        holdNext = false
                        await withCheckedContinuation { gate = $0 }
                    }
                    return try pages[after, default: .success(Listing(items: []))].get()
                },
                cached: { @MainActor [self] _, _ in cached }
            )
        }
    }

    private func ids(_ c: FeedController) -> [String] { c.ui.state?.posts.map(\.id) ?? [] }

    func testPaintsTheCachedPageThenTheFreshOne() async {
        let stub = Stub()
        stub.cached = Listing(items: [post("old")], after: "c")
        stub.holdNext = true
        stub.pages[nil] = .success(Listing(items: [post("new")], after: "n"))
        let c = FeedController(key: "cats", source: stub.source)
        c.start()
        await eventually { ids(c) == ["old"] && stub.gate != nil }
        // Paging off a cached page would be overwritten by the fresh one.
        c.loadMore()
        XCTAssertEqual(c.ui.state?.loadingMore, false)
        stub.gate?.resume()
        await eventually { ids(c) == ["new"] }
        XCTAssertEqual(c.ui.state?.after, "n")
    }

    func testRetriesOnceThenKeepsTheCachedPageRatherThanAnError() async {
        let stub = Stub()
        stub.cached = Listing(items: [post("old")])
        stub.pages[nil] = .failure(URLError(.notConnectedToInternet))
        let c = FeedController(key: "cats", source: stub.source)
        c.start()
        await eventually { !c.isBuilding }
        XCTAssertEqual(stub.calls.count, 2)
        XCTAssertEqual(ids(c), ["old"])
    }

    func testAFailedFirstLoadWithNoCacheIsAnError() async {
        let stub = Stub()
        stub.pages[nil] = .failure(URLError(.notConnectedToInternet))
        let c = FeedController(key: "cats", source: stub.source)
        c.start()
        await eventually { c.ui.isError }
    }

    func testAPageInFlightForTheOldListIsDropped() async {
        let stub = Stub()
        stub.pages[nil] = .success(Listing(items: [post("a")], after: "p2"))
        stub.pages["p2"] = .success(Listing(items: [post("stale")], after: "p3"))
        let c = FeedController(key: "cats", source: stub.source)
        c.start()
        await eventually { ids(c) == ["a"] && !c.isBuilding }
        stub.holdNext = true
        c.loadMore()
        await eventually { stub.gate != nil }
        stub.pages[nil] = .success(Listing(items: [post("b")], after: "p9"))
        await c.refresh()
        stub.gate?.resume()
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(ids(c), ["b"])
        XCTAssertEqual(c.ui.state?.after, "p9")
    }

    func testLoadMoreAppendsAndAFailureClearsTheSpinner() async {
        let stub = Stub()
        stub.pages[nil] = .success(Listing(items: [post("a")], after: "p2"))
        stub.pages["p2"] = .success(Listing(items: [post("b")], after: nil))
        let c = FeedController(key: "cats", source: stub.source)
        c.start()
        await eventually { !c.isBuilding }
        c.loadMore()
        await eventually { ids(c) == ["a", "b"] }
        XCTAssertEqual(c.ui.state?.hasMore, false)

        let failing = Stub()
        failing.pages[nil] = .success(Listing(items: [post("a")], after: "p2"))
        failing.pages["p2"] = .failure(URLError(.timedOut))
        let d = FeedController(key: "cats", source: failing.source)
        d.start()
        await eventually { !d.isBuilding }
        d.loadMore()
        await eventually { failing.calls.count == 2 && d.ui.state?.loadingMore == false }
        XCTAssertEqual(ids(d), ["a"])
    }

    func testAStaleFeedStagesNewPostsBehindThePill() async {
        let stub = Stub()
        stub.pages[nil] = .success(Listing(items: [post("a")], after: "p2"))
        let c = FeedController(key: "cats", source: stub.source)
        c.start()
        await eventually { !c.isBuilding }
        stub.pages[nil] = .success(Listing(items: [post("new"), post("a")], after: "q2"))
        c.refreshIfStale(maxAgeMillis: 0)
        await eventually { c.ui.state?.hasPending == true }
        XCTAssertEqual(ids(c), ["a"]) // not yanked out from under the user
        c.applyPending()
        XCTAssertEqual(ids(c), ["new", "a"])
        XCTAssertEqual(c.ui.state?.after, "q2")
        XCTAssertEqual(c.ui.state?.hasPending, false)
    }

    func testNothingNewStagesNothing() async {
        let stub = Stub()
        stub.pages[nil] = .success(Listing(items: [post("a")]))
        let c = FeedController(key: "cats", source: stub.source)
        c.start()
        await eventually { !c.isBuilding }
        c.refreshIfStale(maxAgeMillis: 0)
        await eventually { stub.calls.count == 2 }
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(c.ui.state?.hasPending, false)
    }

    func testASortChangeCancelsTheSlowerOlderBuild() async {
        let stub = Stub()
        stub.pages[nil] = .success(Listing(items: [post("a")]))
        let c = FeedController(key: "cats", source: stub.source)
        c.start()
        await eventually { !c.isBuilding }
        stub.holdNext = true
        stub.pages[nil] = .success(Listing(items: [post("slow")]))
        c.changeSort(.top, time: .week)
        XCTAssertTrue(c.ui.isLoading)
        await eventually { stub.gate != nil }
        stub.pages[nil] = .success(Listing(items: [post("fresh")]))
        c.changeSort(.newest)
        await eventually { ids(c) == ["fresh"] }
        stub.gate?.resume()
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(ids(c), ["fresh"])
        XCTAssertEqual(c.sort, .newest)
        XCTAssertEqual(c.time, .week)
    }
}

/// The floating chips (#73, #80, #81).
final class FloatingChipsTests: XCTestCase {
    private let top: CGFloat = 100

    private func tracker(at offset: CGFloat = 0) -> FloatingChipsTracker {
        var t = FloatingChipsTracker()
        t.scrolled(to: offset, min: 0, max: 5000)
        return t
    }

    func testAtTheTopItSitsInItsPlace() {
        let t = tracker()
        XCTAssertEqual(t.y(rowY: 150, top: top, floats: true), 150)
        XCTAssertEqual(t.alpha(y: 150, top: top), 1)
    }

    func testScrollingDownCarriesItAwayWithTheListThenItStaysGone() {
        var t = tracker()
        t.scrolled(to: 20, min: 0, max: 5000)
        // Its place has gone under the bar by as much as it moved: they stay together.
        XCTAssertEqual(t.y(rowY: top - 20, top: top, floats: true), top - 20)
        t.scrolled(to: 900, min: 0, max: 5000)
        XCTAssertEqual(t.shift, -t.height)
        XCTAssertEqual(t.alpha(y: t.y(rowY: nil, top: top, floats: true), top: top), 0)
        t.scrolled(to: 1500, min: 0, max: 5000)
        XCTAssertEqual(t.alpha(y: t.y(rowY: nil, top: top, floats: true), top: top), 0)
    }

    func testScrollingUpBringsItBackFollowingTheFingerAndDownSendsItAway() {
        var t = tracker()
        t.scrolled(to: 900, min: 0, max: 5000)
        t.scrolled(to: 880, min: 0, max: 5000)
        XCTAssertEqual(t.y(rowY: nil, top: top, floats: true), top - t.height + 20)
        t.scrolled(to: 800, min: 0, max: 5000)
        XCTAssertEqual(t.y(rowY: nil, top: top, floats: true), top)
        XCTAssertEqual(t.alpha(y: top, top: top), 1)
        t.scrolled(to: 860, min: 0, max: 5000)
        XCTAssertEqual(t.shift, -t.height)
    }

    func testBackAtTheTopThereIsNoJump() {
        var t = tracker()
        t.scrolled(to: 900, min: 0, max: 5000)
        t.scrolled(to: 800, min: 0, max: 5000)
        // Floating at the bar; its place arrives from above and takes over at the same spot.
        XCTAssertEqual(t.y(rowY: top - 3, top: top, floats: true), top)
        XCTAssertEqual(t.y(rowY: top, top: top, floats: true), top)
        XCTAssertEqual(t.y(rowY: top + 3, top: top, floats: true), top + 3)
    }

    func testOffItNeverFloats() {
        var t = tracker()
        t.scrolled(to: 900, min: 0, max: 5000)
        t.scrolled(to: 800, min: 0, max: 5000)
        XCTAssertEqual(t.alpha(y: t.y(rowY: nil, top: top, floats: false), top: top), 0)
        XCTAssertEqual(t.y(rowY: 150, top: top, floats: false), 150)
    }

    func testRubberBandingAtTheEndDoesNotBringItOut() {
        var t = tracker()
        t.scrolled(to: 1000, min: 0, max: 1000)
        t.scrolled(to: 1080, min: 0, max: 1000) // Past the end…
        t.scrolled(to: 1000, min: 0, max: 1000) // …and bouncing back.
        XCTAssertEqual(t.shift, -t.height)
    }

    func testStoppingHalfWayFinishesTheWayYouWereGoing() {
        var down = tracker()
        down.scrolled(to: 900, min: 0, max: 5000)
        down.scrolled(to: 880, min: 0, max: 5000)
        down.scrolled(to: 890, min: 0, max: 5000)
        XCTAssertTrue(down.settle(past: true))
        XCTAssertEqual(down.shift, -down.height)

        var up = tracker()
        up.scrolled(to: 900, min: 0, max: 5000)
        up.scrolled(to: 880, min: 0, max: 5000)
        XCTAssertTrue(up.settle(past: true))
        XCTAssertEqual(up.shift, 0)
        XCTAssertFalse(up.settle(past: true))
    }
}

final class AvatarColorTests: XCTestCase {
    // The same picks as Kotlin's AvatarColorTest: a name keeps its colour on both apps.
    func testANameKeepsItsColourPickedLikeTheCommentAuthorDots() {
        XCTAssertEqual(avatarColor("AskReddit"), Color(argb: 0xFFC46A96))
        XCTAssertEqual(avatarColor("pics"), Color(argb: 0xFF5FA85A))
        XCTAssertEqual(avatarColor("spez"), Color(argb: 0xFF7C5CE0))
        XCTAssertNotEqual(avatarColor("pics"), avatarColor("spez"))
    }
}
