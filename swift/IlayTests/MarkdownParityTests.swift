import XCTest
@testable import Ilay

/// The same bodies through both parsers. `MarkdownParityFixtures.json` holds what
/// Kotlin's `RedditMarkdownParser` (commonmark-java 0.30) produced for each input.
final class MarkdownParityTests: XCTestCase {
    private struct Case: Decodable {
        let input: String
        let dump: String
    }

    /// Inputs where Swift differs on purpose, and why.
    private static let intended: [String: String] = [
        "`code ^sup` and `>!not spoiler!<` trailing": "Kotlin shows its private-use spoiler markers in code",
        "```\n>!in fence!<\n^[x](y)\n```": "Kotlin shows its private-use spoiler markers in code",
        // cmark parses task lists and doesn't keep the checkbox's case; nobody writes this.
        "- [ ] open task\n- [x] done task\n- [X] Done caps": "`[X]` comes out as `[x]`",
    ]

    func testSameModelAsKotlin() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "MarkdownParityFixtures", withExtension: "json"))
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: url))
        XCTAssertGreaterThan(cases.count, 100)
        var different = 0
        for c in cases where Self.intended[c.input] == nil {
            let doc = RedditMarkdownParser.parseUncached(c.input)
            let dump = doc.blocks.map(Self.dump).joined(separator: "\n") + "\n#\(doc.spoilerCount)\nplain:" + doc.plainText()
            if dump != c.dump {
                different += 1
                XCTFail("input: \(c.input)\nkotlin: \(c.dump)\nswift:  \(dump)")
            }
        }
        XCTAssertEqual(different, 0)
    }

    private static func quoted(_ s: String?) -> String {
        guard let s else { return "null" }
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            default:
                if u.value < 0x20 || (0xE000...0xF8FF).contains(u.value) {
                    out += String(format: "\\u%04x", u.value)
                } else {
                    out.unicodeScalars.append(u)
                }
            }
        }
        return out + "\""
    }

    private static func inlines(_ l: [MdInline]) -> String {
        "[" + l.map { "{\(quoted($0.text)),\($0.style.rawValue),\(quoted($0.link)),\($0.spoiler)}" }.joined(separator: ",") + "]"
    }

    private static func dump(_ b: MdBlock) -> String {
        switch b {
        case .paragraph(let i): "P" + inlines(i)
        case .heading(let level, let i): "H\(level)" + inlines(i)
        case .quote(let q): "Q[" + q.map(dump).joined(separator: ",") + "]"
        case .list(let ordered, let start, let items):
            "L(\(ordered),\(start))[" + items.map { "[" + $0.map(dump).joined(separator: ",") + "]" }.joined(separator: ",") + "]"
        case .code(let c): "C" + quoted(c)
        case .table(let header, let rows, let align):
            "T(" + align.map(String.init).joined(separator: ",") + ")[" + header.map(inlines).joined(separator: ",") + "]["
                + rows.map { "[" + $0.map(inlines).joined(separator: ",") + "]" }.joined(separator: ",") + "]"
        case .image(let url, let alt): "I(" + quoted(url) + "," + quoted(alt) + ")"
        case .rule: "R"
        }
    }
}
