import XCTest
@testable import Ilay

final class RouteTests: XCTestCase {
    func testEveryRouteSurvivesEncoding() throws {
        // The tab stacks are saved as JSON (see AppRoot); a saved route must decode to itself.
        let routes: [Route] = [
            .login, .webLogin(), .webLogin(clearFirst: true), .home, .settings, .settingsSection(title: "Feed"),
            .manageForYou, .contentFilters, .policy, .history, .summaries, .saved, .offline, .notificationActivity,
            .drafts, .whatsNew, .customFeeds, .redditWeb(url: "https://www.reddit.com/notifications", title: "Notifications"),
            .search(), .search(subreddit: "swift", query: "q", sort: "top", time: "week"), .submit(), .submit(subreddit: "swift"),
            .messageThread(fullname: "t4_1"), .composeMessage(), .composeMessage(to: "someone"), .subreddit(name: "swift"),
            .user(username: "someone"), .multireddit(username: "a", name: "b"), .manageMultireddit(username: "a", name: "b"),
            .post(subreddit: "swift", postId: "abc"), .post(subreddit: "swift", postId: "abc", focusCommentId: "def"),
        ]
        let data = try JSONEncoder().encode(routes)
        XCTAssertEqual(try JSONDecoder().decode([Route].self, from: data), routes)
        XCTAssertEqual(Set(routes).count, routes.count, "every route is its own NavigationStack value")
    }

    func testDefaultArgumentsMatchKotlin() {
        XCTAssertEqual(Route.webLogin(), .webLogin(clearFirst: false))
        XCTAssertEqual(Route.search(), .search(subreddit: nil, query: nil, sort: nil, time: nil))
        XCTAssertEqual(Route.post(subreddit: "a", postId: "b"), .post(subreddit: "a", postId: "b", focusCommentId: nil))
    }

    func testNavCacheKeepsTheLatest200() {
        NavCache.put("first", 1)
        XCTAssertEqual(NavCache.get("first") as Int?, 1)
        XCTAssertNil(NavCache.get("first") as String?, "a wrong type reads as absent")
        for i in 0..<200 { NavCache.put("k\(i)", i) }
        XCTAssertNil(NavCache.get("first") as Int?)
        XCTAssertEqual(NavCache.get("k199") as Int?, 199)
    }

    func testNavCacheEvictsLeastRecentlyRead() {
        for i in 0..<200 { NavCache.put("r\(i)", i) }
        _ = NavCache.get("r0") as Int?
        NavCache.put("one more", 0)
        XCTAssertEqual(NavCache.get("r0") as Int?, 0)
        XCTAssertNil(NavCache.get("r1") as Int?)
    }

    @MainActor func testOpenLinkRegexes() {
        XCTAssertEqual(AppNavigator.absoluteLink("  /r/foo "), "https://www.reddit.com/r/foo")
        XCTAssertEqual(AppNavigator.absoluteLink("r/foo"), "https://www.reddit.com/r/foo")
        XCTAssertEqual(AppNavigator.absoluteLink("u/bar"), "https://www.reddit.com/u/bar")
        XCTAssertEqual(AppNavigator.absoluteLink("user/bar"), "https://www.reddit.com/user/bar")
        XCTAssertEqual(AppNavigator.absoluteLink("https://example.com/r/x"), "https://example.com/r/x")
    }
}
