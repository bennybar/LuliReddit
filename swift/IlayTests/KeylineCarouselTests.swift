import XCTest
@testable import Ilay

final class KeylineCarouselTests: XCTestCase {
    private let k: [CGFloat] = [260, 70, 40]
    private let width: CGFloat = 386 // 260 + 8 + 70 + 8 + 40

    private func frame(_ i: Int, at current: CGFloat, count: Int) -> (x: CGFloat, width: CGFloat) {
        keylineFrame(index: i, current: current, count: count, keylines: k, spacing: 8, width: width)
    }

    func testEveryItemReachesFullSize() {
        for count in [2, 3, 7] {
            for i in 0..<count {
                XCTAssertEqual(frame(i, at: CGFloat(i), count: count).width, 260, accuracy: 0.01, "item \(i) of \(count)")
            }
        }
    }

    func testTheLastItemEndsLargeAgainstTheRightEdge() {
        let f = frame(6, at: 6, count: 7)
        XCTAssertEqual(f.width, 260, accuracy: 0.01)
        XCTAssertEqual(f.x + f.width, width, accuracy: 0.01)
        let before = frame(5, at: 6, count: 7)
        XCTAssertEqual(before.x + before.width + 8, f.x, accuracy: 0.01)
        XCTAssertEqual(before.width, 70, accuracy: 0.01)
    }

    func testTheStartIsLargeMediumSmall() {
        XCTAssertEqual(frame(0, at: 0, count: 7).width, 260, accuracy: 0.01)
        XCTAssertEqual(frame(1, at: 0, count: 7).width, 70, accuracy: 0.01)
        XCTAssertEqual(frame(2, at: 0, count: 7).width, 40, accuracy: 0.01)
    }

    func testMovesWithoutJumpsAcrossTheFlip() {
        for i in 0..<7 {
            var previous = frame(i, at: 0, count: 7)
            for step in 1...600 {
                let f = frame(i, at: CGFloat(step) / 100, count: 7)
                XCTAssertEqual(f.x, previous.x, accuracy: 8, "item \(i) at step \(step)")
                XCTAssertEqual(f.width, previous.width, accuracy: 8, "item \(i) at step \(step)")
                previous = f
            }
        }
    }
}
