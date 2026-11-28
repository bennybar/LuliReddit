import XCTest
@testable import Ilay

/// Home's row of favorites (#311), as Kotlin's HomeFavoritesTest.
final class HomeFavoritesTests: XCTestCase {
    private func sub(_ name: String, _ fav: Bool) -> Subreddit {
        Subreddit(name: name, namePrefixed: "r/\(name)", title: name, description: "", subscribers: 0, userHasFavorited: fav)
    }

    private func multi(_ name: String, _ fav: Bool) -> Multireddit {
        Multireddit(name: name, displayName: name.uppercased(), path: "/user/me/m/\(name)/", subreddits: [], isFavorited: fav)
    }

    func testFavoriteFeedsComeFirstThenFavoriteCommunities() {
        let got = homeFavorites(
            multis: [multi("tech", true), multi("news", false)],
            subs: [sub("Ninjago", true), sub("AskReddit", false), sub("u_someone", true), sub("CozyPlaces", true)]
        ) { _ in "me" }
        XCTAssertEqual(got, [
            HomeFavorite(key: "m::me::tech", name: "TECH", multi: true),
            HomeFavorite(key: "Ninjago", name: "Ninjago", multi: false),
            HomeFavorite(key: "CozyPlaces", name: "CozyPlaces", multi: false),
        ])
    }

    func testNoFavoritesNoRow() {
        XCTAssertTrue(homeFavorites(multis: [multi("a", false)], subs: [sub("b", false)]) { _ in "me" }.isEmpty)
    }

    func testACustomFeedReadsRedditsFavoriteFlag() {
        let starred = Multireddit.fromData(parseJsonOrNull(#"{"name":"gpt","display_name":"GPT","path":"/user/me/m/gpt/","is_favorited":true}"#)!)
        let plain = Multireddit.fromData(parseJsonOrNull(#"{"name":"x","path":"/user/me/m/x/"}"#)!)
        XCTAssertTrue(starred.isFavorited)
        XCTAssertFalse(plain.isFavorited)
    }
}
