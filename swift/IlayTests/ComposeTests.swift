import XCTest
@testable import Ilay

/// Port of Kotlin's LengthLimitTest.
final class ComposeTests: XCTestCase {
    func testCountsCodePointsAsRedditDoes() {
        XCTAssertEqual(redditLength("hello"), 5)
        XCTAssertEqual(redditLength("😀"), 1)
        // A skin tone is its own code point, as Reddit counts it (one grapheme to Swift).
        XCTAssertEqual(redditLength("👍🏽"), 2)
        XCTAssertEqual(redditLength(""), 0)
    }

    func testCounterShowsOnlyNearTheLimit() {
        XCTAssertNil(lengthCounter(String(repeating: "a", count: 269), limit: TextLimit.title))
        XCTAssertEqual(lengthCounter(String(repeating: "a", count: 270), limit: TextLimit.title), "270 / 300")
        XCTAssertEqual(lengthCounter(String(repeating: "a", count: 301), limit: TextLimit.title), "301 / 300")
        XCTAssertNil(lengthCounter(String(repeating: "a", count: 8999), limit: TextLimit.comment))
        XCTAssertEqual(lengthCounter(String(repeating: "a", count: 9000), limit: TextLimit.comment), "9000 / 10000")
        XCTAssertEqual(lengthCounter(String(repeating: "a", count: 40001), limit: TextLimit.postBody), "40001 / 40000")
    }

    func testPosterFallsBackToABlackFrameNotTheVideo() async {
        // Not a video: the poster must still be a JPEG, never these bytes.
        let notVideo = Data("not a video".utf8)
        let poster = await posterFrame(notVideo)
        XCTAssertNotEqual(poster, notVideo)
        XCTAssertEqual(Array(poster.prefix(2)), [0xFF, 0xD8]) // JPEG
    }
}
