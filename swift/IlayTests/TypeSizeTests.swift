import SwiftUI
import XCTest
@testable import Ilay

/// The font size setting moves from the system's text size instead of replacing it.
final class TypeSizeTests: XCTestCase {
    func testDefaultSystemSizeKeepsTheOldSteps() {
        XCTAssertEqual(IlayTheme.typeRange(0.8, system: .large), .xSmall ... .xSmall)
        XCTAssertEqual(IlayTheme.typeRange(0.9, system: .large), .small ... .small)
        XCTAssertEqual(IlayTheme.typeRange(1.1, system: .large), .xLarge ... .xLarge)
        XCTAssertEqual(IlayTheme.typeRange(1.4, system: .large), .xxxLarge ... .xxxLarge)
    }

    func testHundredPercentLeavesTheSystemSize() {
        XCTAssertEqual(IlayTheme.typeRange(1.0, system: .accessibility3), .xSmall ... .accessibility5)
    }

    func testAccessibilitySizeGoesUpNotDown() {
        XCTAssertEqual(IlayTheme.typeRange(1.1, system: .accessibility1), .accessibility2 ... .accessibility2)
        XCTAssertEqual(IlayTheme.typeRange(1.4, system: .accessibility4), .accessibility5 ... .accessibility5)
        XCTAssertEqual(IlayTheme.typeRange(0.8, system: .xSmall), .xSmall ... .xSmall)
    }
}
