import XCTest
@testable import Ilay

/// Saved media is named after the post (#212), as on Android.
final class SavedFileNameTests: XCTestCase {
    func testUsesThePostTitle() {
        XCTAssertEqual(savedFileName("My cat does a backflip", ts: 1), "My cat does a backflip")
    }

    func testDropsCharactersFileSystemsRefuse() {
        XCTAssertEqual(savedFileName("AC/DC live:\nno?", ts: 1), "AC DC live no")
        XCTAssertEqual(savedFileName("a\\b*c|d", ts: 1), "a b c d")
    }

    func testCutsLongTitlesAndTrailingDots() {
        XCTAssertEqual(savedFileName(String(repeating: "x", count: 200), ts: 1).count, 80)
        XCTAssertEqual(savedFileName("Wait for it...", ts: 1), "Wait for it")
    }

    func testFallsBackWithoutATitle() {
        XCTAssertEqual(savedFileName(nil, ts: 42), "ilay_42")
        XCTAssertEqual(savedFileName("  ?? ", ts: 42), "ilay_42")
    }
}
