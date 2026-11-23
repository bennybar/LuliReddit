import SwiftUI
import XCTest
@testable import Ilay

/// The feed's post text (#241), as the Kotlin app's SnippetMarkdownTest.
final class SnippetMarkdownTests: XCTestCase {
    private let cover = Color.gray

    private func text(_ s: String) -> String { String(snippetMarkdown(s, spoiler: cover).characters) }

    /// The text of each run with [intent] (or, with nil, the covered runs).
    private func runs(_ s: String, _ intent: InlinePresentationIntent?) -> [String] {
        let a = snippetMarkdown(s, spoiler: cover)
        return a.runs.compactMap { run in
            let hit = intent.map { run.inlinePresentationIntent?.contains($0) == true } ?? (run.backgroundColor == cover)
            return hit ? String(a[run.range].characters) : nil
        }
    }

    func testBoldItalicStrikeDrawnWithoutTheirMarks() {
        let s = "A **big** day, *really* and ~~not~~ __this__"
        XCTAssertEqual(text(s), "A big day, really and not this")
        XCTAssertEqual(runs(s, .stronglyEmphasized), ["big", "this"])
        XCTAssertEqual(runs(s, .emphasized), ["really"])
        XCTAssertEqual(runs(s, .strikethrough), ["not"])
    }

    func testSpoilersAreCovered_escapedOrNot() {
        for s in ["It was >!the butler!< all along", "It was &gt;!the butler!&lt; all along"] {
            XCTAssertEqual(text(s), "It was the butler all along")
            XCTAssertEqual(runs(s, nil), ["the butler"])
        }
    }

    func testLinksShowTheirWords_headingsAndQuotesLoseTheirMarks() {
        XCTAssertEqual(text("See [this page](https://example.com)"), "See this page")
        XCTAssertEqual(text("## Title\n> quoted text"), "Title\nquoted text")
        XCTAssertEqual(runs("## Title\nbody", .stronglyEmphasized), ["Title"])
    }

    func testPlainTextAndLoneMarksStayAsTyped() {
        XCTAssertEqual(text("snake_case_name and 2 * 3 * 4"), "snake_case_name and 2 * 3 * 4")
        XCTAssertEqual(text("a ** b"), "a ** b")
        XCTAssertEqual(text("5 &gt; 3 &amp; 1 &lt; 2"), "5 > 3 & 1 < 2")
        XCTAssertEqual(text("#hashtag stays"), "#hashtag stays")
    }

    func testBackslashEscapes() {
        XCTAssertEqual(text("\\*not italic\\*"), "*not italic*")
    }
}
