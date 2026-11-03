import SwiftUI
import XCTest
@testable import Ilay

/// Port of Kotlin's RedditMarkdownTest and RtlTest, plus the messy bodies real threads have.
final class RedditMarkdownTests: XCTestCase {
    private func parse(_ s: String) -> MdDocument { RedditMarkdownParser.parseUncached(s) }

    private func runs(_ doc: MdDocument) -> [MdInline] {
        doc.blocks.flatMap { b -> [MdInline] in
            if case .paragraph(let i) = b { return i }
            return []
        }
    }

    private func joined(_ r: [MdInline]) -> String { r.map(\.text).joined() }

    // MARK: - Ported from Kotlin

    func testSpoilerStaysInlineHiddenUntilTapped() throws {
        let doc = parse("Ending: >!he dies!< sadly.")
        XCTAssertEqual(doc.blocks.count, 1)
        let r = runs(doc)
        XCTAssertEqual(joined(r), "Ending: he dies sadly.")
        let spoiler = try XCTUnwrap(r.first { $0.text == "he dies" })
        XCTAssertEqual(spoiler.spoiler, 0) // tappable (revealed by index in the renderer)
        XCTAssertEqual(doc.spoilerCount, 1)
        XCTAssertTrue(r.filter { $0.text != "he dies" }.allSatisfy { $0.spoiler == -1 })
    }

    func testSpoilerAtLineStartIsNotABlockquote() {
        let doc = parse(">!secret!<")
        XCTAssertFalse(doc.blocks.contains { if case .quote = $0 { true } else { false } })
        XCTAssertTrue(runs(doc).contains { $0.text == "secret" && $0.spoiler == 0 })
    }

    func testARealQuoteIsStillAQuote() {
        let doc = parse("> quoted\n\nafter")
        guard case .quote = doc.blocks[0] else { return XCTFail("\(doc.blocks[0])") }
        guard case .paragraph = doc.blocks[1] else { return XCTFail("\(doc.blocks[1])") }
    }

    func testSuperscriptBothForms() {
        let doc = parse("x^2 and ^(tiny words) end")
        XCTAssertEqual(runs(doc).filter { $0.has(.sup) }.map(\.text), ["2", "tiny words"])
        XCTAssertEqual(joined(runs(doc)), "x2 and tiny words end")
    }

    func testInlineStylesLinksAndAutolinks() throws {
        let r = runs(parse("**b** *i* ~~s~~ `c` [t](https://a.com) https://b.com"))
        func run(_ text: String) throws -> MdInline { try XCTUnwrap(r.first { $0.text == text }) }
        XCTAssertTrue(try run("b").has(.bold))
        XCTAssertTrue(try run("i").has(.italic))
        XCTAssertTrue(try run("s").has(.strike))
        XCTAssertTrue(try run("c").has(.code))
        XCTAssertEqual(try run("t").link, "https://a.com")
        XCTAssertEqual(try run("https://b.com").link, "https://b.com")
    }

    func testListsCodeBlocksAndTables() {
        let doc = parse("1. one\n2. two\n\n```\ncode\n```\n\n| a | b |\n|:-:|--:|\n| 1 | 2 |")
        guard case .list(let ordered, _, let items) = doc.blocks[0] else { return XCTFail() }
        XCTAssertTrue(ordered)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(doc.blocks[1], .code("code"))
        guard case .table(let header, let rows, let align) = doc.blocks[2] else { return XCTFail() }
        XCTAssertEqual(header.map(joined), ["a", "b"])
        XCTAssertEqual(align, [0, 1])
        XCTAssertEqual(rows.count, 1)
    }

    func testSoftBreaksAreSpacesHardBreaksNewlines() {
        XCTAssertEqual(joined(runs(parse("a\nb  \nc"))), "a b\nc")
    }

    func testToolbarWrapsTheSelectionOrAPlaceholder() {
        XCTAssertEqual(mdWrap("say hi", 4, 6, "**", "**"), MdEdit(text: "say **hi**", selStart: 6, selEnd: 8))
        XCTAssertEqual(mdWrap("x", 1, 1, "**", "**", placeholder: "bold"), MdEdit(text: "x**bold**", selStart: 3, selEnd: 7))
        // No valid selection: acts at the end.
        XCTAssertEqual(mdWrap("x", -1, -1, "`", "`", placeholder: "code"), MdEdit(text: "x`code`", selStart: 2, selEnd: 6))
    }

    func testToolbarPrefixesEachSelectedLine() {
        XCTAssertEqual(mdLinePrefix("a\nb\nc", 0, 3, "> "), MdEdit(text: "> a\n> b\nc", selStart: 7, selEnd: 7))
        XCTAssertEqual(mdLinePrefix("a\nb", 3, 3, "- "), MdEdit(text: "a\n- b", selStart: 5, selEnd: 5))
    }

    func testImagesRenderMidParagraphSplittingTheTextAroundThem() {
        XCTAssertEqual(parse("look ![cat](https://i.redd.it/a.png) here").blocks, [
            .paragraph([MdInline(text: "look")]),
            .image(url: "https://i.redd.it/a.png", alt: "cat"),
            .paragraph([MdInline(text: "here")]),
        ])
        XCTAssertEqual(parse("![](https://a/x.png)\n![](https://a/y.png)").blocks, [
            .image(url: "https://a/x.png", alt: ""),
            .image(url: "https://a/y.png", alt: ""),
        ])
    }

    func testAHebrewSummaryIsRtlEvenWithEnglishWordsInIt() {
        XCTAssertTrue(isMostlyRtl("TL;DR: המשתמשים ב-Reddit חושבים שהעדכון של iOS 27 פוגע בסוללה, ורובם ממליצים לחכות לגרסה הבאה."))
    }

    func testArabicIsRtl() {
        XCTAssertTrue(isMostlyRtl("يعتقد معظم المعلقين أن التحديث يستهلك البطارية"))
    }

    func testEnglishWithAHebrewWordStaysLtr() {
        XCTAssertFalse(isMostlyRtl("People in the thread say שלום means both hello and goodbye."))
    }

    func testNoLettersStaysLtr() {
        XCTAssertFalse(isMostlyRtl("123 — 456"))
    }

    // MARK: - Messy bodies

    func testNestedQuotes() {
        guard case .quote(let outer) = parse("> a\n> > b\n> > > c\n>\n> d").blocks[0] else { return XCTFail() }
        XCTAssertEqual(outer.count, 3) // a, the nested quote, d
        guard case .quote(let middle) = outer[1], case .quote(let inner) = middle[1] else { return XCTFail("\(outer)") }
        XCTAssertEqual(inner, [.paragraph([MdInline(text: "c")])])
    }

    func testTablePipesInCode() {
        // GFM splits cells before inlines: only an escaped pipe stays inside a code span.
        guard case .table(_, let rows, _) = parse("| a | b |\n|---|---|\n| `x\\|y` | z |").blocks[0] else { return XCTFail() }
        XCTAssertEqual(rows[0][0], [MdInline(text: "x|y", style: .code)])
        XCTAssertEqual(joined(rows[0][1]), "z")
    }

    func testALoneCaretInATableStaysText() {
        // swift-markdown reads it as a row span unless told otherwise.
        guard case .table(_, let rows, _) = parse("| a | b |\n|---|---|\n| ^ | c |").blocks[0] else { return XCTFail() }
        XCTAssertEqual(rows[0].map(joined), ["^", "c"])
    }

    func testSpoilerSpanningEmphasis() {
        let r = runs(parse(">!a *b* **c**!< d"))
        XCTAssertEqual(r.map(\.text), ["a ", "b", " ", "c", " d"])
        XCTAssertEqual(r.map(\.spoiler), [0, 0, 0, 0, -1])
        XCTAssertTrue(r[1].has(.italic))
        XCTAssertTrue(r[3].has(.bold))
    }

    func testEmphasisAcrossASpoilerEdge() {
        let r = runs(parse("*a >!b!< c*"))
        XCTAssertEqual(r.map(\.spoiler), [-1, 0, -1])
        XCTAssertTrue(r.allSatisfy { $0.has(.italic) })
    }

    func testSpoilerEdgeCases() {
        XCTAssertEqual(parse(">!a!< and >!b!<").spoilerCount, 2)
        // Doesn't cross a line, as on Reddit: this is a quote.
        guard case .quote = parse(">!a\nb!<").blocks[0] else { return XCTFail() }
        XCTAssertEqual(joined(runs(parse("not opened!<"))), "not opened!<")
    }

    func testSpoilerSyntaxInCodeStaysAsTyped() {
        // Differs from Kotlin, which shows the parser's private-use markers here.
        XCTAssertEqual(runs(parse("`>!x!<` and ^[y]")).first, MdInline(text: ">!x!<", style: .code))
        XCTAssertEqual(parse("```\n>!x!<\n^[y](z)\n```").blocks, [.code(">!x!<\n^[y](z)")])
    }

    func testSpoileredAutolinkStopsAtTheSpoiler() {
        // Differs from Kotlin, where the end marker lands in the link's destination.
        XCTAssertEqual(runs(parse(">!https://a.com!< x")), [
            MdInline(text: "https://a.com", link: "https://a.com", spoiler: 0),
            MdInline(text: " x"),
        ])
        XCTAssertEqual(runs(parse(">!me@a.com!<")), [MdInline(text: "me@a.com", link: "mailto:me@a.com", spoiler: 0)])
    }

    func testACaretBeforeALinkIsStillALink() {
        // swift-cmark would read `^[…](…)` as its own "inline attribute" syntax.
        XCTAssertEqual(runs(parse("a ^[source](https://a.b)")), [
            MdInline(text: "a ^"),
            MdInline(text: "source", link: "https://a.b"),
        ])
    }

    func testMalformedLinksStayText() {
        XCTAssertEqual(joined(runs(parse("[malformed](http://a.b"))), "[malformed](http://a.b")
        XCTAssertEqual(runs(parse("[spaces](http://a.b/c d)")).first?.link, nil)
        XCTAssertEqual(runs(parse("[empty]()")), [MdInline(text: "empty", link: "")])
    }

    func testTaskListsAreJustText() {
        guard case .list(_, _, let items) = parse("- [ ] open\n- [x] done\n- [ ] **b**").blocks[0] else { return XCTFail() }
        XCTAssertEqual(items[0], [.paragraph([MdInline(text: "[ ] open")])])
        XCTAssertEqual(items[1], [.paragraph([MdInline(text: "[x] done")])])
        XCTAssertEqual(items[2], [.paragraph([MdInline(text: "[ ] "), MdInline(text: "b", style: .bold)])])
    }

    func testStraightQuotesStayStraight() {
        // swift-markdown turns on "smart" punctuation unless told not to.
        XCTAssertEqual(joined(runs(parse(#"it's "x" -- y ... z"#))), #"it's "x" -- y ... z"#)
    }

    func testMentionsLink() {
        // Differs from Kotlin, which leaves these as text; Reddit links them.
        XCTAssertEqual(runs(parse("ask u/some_one in r/foo-bar or /r/baz, not and/or/r/no or r/ or https://x.y/r/also")), [
            MdInline(text: "ask "),
            MdInline(text: "u/some_one", link: "u/some_one"),
            MdInline(text: " in "),
            MdInline(text: "r/foo-bar", link: "r/foo-bar"),
            MdInline(text: " or "),
            MdInline(text: "/r/baz", link: "/r/baz"),
            MdInline(text: ", not and/or/r/no or r/ or "),
            MdInline(text: "https://x.y/r/also", link: "https://x.y/r/also"),
        ])
        XCTAssertEqual(runs(parse("[r/foo](https://a.b) `r/foo`")).first, MdInline(text: "r/foo", link: "https://a.b"))
        XCTAssertEqual(runs(parse("[r/foo](https://a.b) `r/foo`")).last, MdInline(text: "r/foo", style: .code))
        XCTAssertEqual(runs(parse("**r/foo** ^u/bar")), [
            MdInline(text: "r/foo", style: .bold, link: "r/foo"),
            MdInline(text: " "),
            MdInline(text: "u/bar", style: .sup, link: "u/bar"),
        ])
    }

    func testHebrewBody() {
        let doc = parse("שלום **עולם**, זה >!ספוילר!< עם [קישור](https://a.b)\n\n> ציטוט\n\n- פריט")
        XCTAssertTrue(doc.isRtl)
        XCTAssertEqual(doc.spoilerCount, 1)
        XCTAssertEqual(doc.blocks.count, 3)
        XCTAssertFalse(parse("Hello **world**").isRtl)
        XCTAssertFalse(parse("English with one word שלום inside").isRtl)
    }

    func testPlainTextAndFlatten() {
        let doc = parse("# T\n\n> q\n\n- a\n- b\n\n1. c\n\n```\nd\n```\n\n| e | f |\n|---|---|\n| g | h |\n\n![alt](https://i)\n\n---")
        XCTAssertEqual(doc.plainText(), "T\nq\na\nb\nc\nd\ne | f\ng | h\nalt")
        let flat = flattenInlines(doc.blocks)
        XCTAssertEqual(joined(flat), "T\nq\n• a\n• b\n1. c\nd\ne | f\ng | h\nalt")
        XCTAssertTrue(flat[0].has(.bold)) // The heading.
    }

    func testCacheReturnsTheSameDocument() {
        let body = "cache **me** \(UUID())"
        XCTAssertNil(RedditMarkdownParser.cached(body))
        let doc = RedditMarkdownParser.parse(body)
        XCTAssertEqual(RedditMarkdownParser.cached(body), doc)
    }

    func testPrewarmFillsTheCacheOffTheMainActor() async {
        let bodies = (0..<50).map { "body \($0) **bold** \(UUID())" }
        await RedditMarkdownParser.prewarm(bodies)
        XCTAssertTrue(bodies.allSatisfy { RedditMarkdownParser.cached($0) != nil })
    }

    func testParsingIsThreadSafe() {
        let bodies = (0..<400).map { "> **b\($0)** >!s!< https://a.b/\($0)\n\n| a |\n|---|\n| \($0) |" }
        DispatchQueue.concurrentPerform(iterations: 8) { worker in
            for b in bodies { XCTAssertEqual(RedditMarkdownParser.parseUncached(b).blocks.count, 2, "\(worker)") }
        }
    }

    // MARK: - Hostile sizes (none of these may crash, on a background thread's small stack)

    func testHugePlainBody() {
        let paragraph = String(repeating: "lorem ipsum dolor sit amet ", count: 40)
        let body = Array(repeating: paragraph, count: 400).joined(separator: "\n\n") // Over 400 KB.
        XCTAssertEqual(parse(body).blocks.count, 400)
    }

    func testHugeTable() {
        let rows = (0..<2000).map { "| \($0) | `x` | y |" }.joined(separator: "\n")
        guard case .table(_, let parsed, _) = parse("| a | b | c |\n|---|---|---|\n" + rows).blocks[0] else { return XCTFail() }
        XCTAssertEqual(parsed.count, 2000)
    }

    private func onBackgroundThread(_ work: @escaping @Sendable () -> Void) async {
        await Task.detached(operation: work).value
    }

    func testAbsurdQuoteNesting() async {
        await onBackgroundThread {
            // Reddit's longest body is 40,000 characters. Past the walk limit the text goes.
            _ = RedditMarkdownParser.parseUncached(String(repeating: ">", count: 40_000) + " deep")
            let doc = RedditMarkdownParser.parseUncached(String(repeating: ">", count: 300) + " deep")
            XCTAssertEqual(doc.plainText(), "deep")
            // Drawn flat past a limit, so no stack of views goes hundreds of levels deep.
            func depth(_ blocks: [MdBlock]) -> Int {
                blocks.map { b -> Int in
                    switch b {
                    case .quote(let q): 1 + depth(q)
                    case .list(_, _, let items): 1 + (items.map(depth).max() ?? 0)
                    default: 0
                    }
                }.max() ?? 0
            }
            XCTAssertLessThanOrEqual(depth(doc.blocks), 16)
        }
    }

    func testAbsurdListNesting() async {
        await onBackgroundThread {
            let doc = RedditMarkdownParser.parseUncached(String(repeating: "- ", count: 20_000) + "deep")
            XCTAssertTrue(doc.plainText().hasSuffix("deep"))
        }
    }

    func testAbsurdEmphasisNesting() async {
        await onBackgroundThread {
            let stars = String(repeating: "*", count: 20_000)
            XCTAssertTrue(RedditMarkdownParser.parseUncached(stars + "x" + stars).plainText().contains("x"))
            let open = (0..<7000).map { "*a\($0) " }.joined()
            let close = (0..<7000).map { " b\($0)*" }.joined()
            XCTAssertTrue(RedditMarkdownParser.parseUncached(open + "mid" + close).plainText().contains("mid"))
            let brackets = String(repeating: "[", count: 20_000) + "x" + String(repeating: "](u)", count: 20_000)
            XCTAssertTrue(RedditMarkdownParser.parseUncached(brackets).plainText().contains("x"))
            let images = String(repeating: "![", count: 15_000) + "x" + String(repeating: "](u)", count: 15_000)
            _ = RedditMarkdownParser.parseUncached(images)
        }
    }

    func testAbsurdSpoilersAndSuperscripts() {
        XCTAssertEqual(parse(String(repeating: ">!a!< ", count: 5000)).spoilerCount, 5000)
        XCTAssertEqual(runs(parse(String(repeating: "^", count: 5000))).first?.text.count, 5000)
        XCTAssertEqual(runs(parse(String(repeating: "^a ", count: 5000))).filter { $0.has(.sup) }.count, 5000)
    }

    // MARK: - Performance, as a guard and for the numbers

    func testParseSpeed() {
        let comments = (0..<1000).map { i in
            switch i % 4 {
            case 0: "Plain one line comment number \(i), nothing special."
            case 1: "Two paragraphs with **bold** and a [link](https://example.com/\(i)).\n\nAnd *more*, with u/someone in it."
            case 2: "> quoted reply \(i)\n\nAnswer with `code` and >!a spoiler!< and x^2.\n\n- one\n- two\n- three"
            default: "| a | b |\n|---|---|\n| \(i) | 2 |\n\nThe table above, https://example.com/x?y=\(i) for details."
            }
        }
        let start = CFAbsoluteTimeGetCurrent()
        for c in comments { _ = RedditMarkdownParser.parseUncached(c) }
        let perBody = (CFAbsoluteTimeGetCurrent() - start) / Double(comments.count) * 1_000_000
        print("parse: \(Int(perBody)) µs per body")
        // A frame is 8.3 ms at 120 Hz; even a debug build stays far under it.
        XCTAssertLessThan(perBody, 2000)
    }
}
