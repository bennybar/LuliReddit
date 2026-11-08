import Foundation
import Markdown

/*
 * Reddit-flavoured markdown, parsed into a small immutable model that the
 * SwiftUI renderer (`RedditMarkdown`) draws. Kept free of UI so it can be
 * unit-tested, parsed off the main actor and cached across cell binds.
 *
 * Kotlin parses with commonmark-java; here it's swift-markdown (cmark-gfm),
 * adjusted to give the same model. See `RedditMarkdownParser.source(for:)` and
 * the Parity tests, whose expected values come from the Kotlin parser.
 */

/// Inline style bits for `MdInline.style`.
struct MdStyle: OptionSet, Hashable, Sendable {
    let rawValue: Int
    static let bold = MdStyle(rawValue: 1)
    static let italic = MdStyle(rawValue: 2)
    static let strike = MdStyle(rawValue: 4)
    static let code = MdStyle(rawValue: 8)
    static let sup = MdStyle(rawValue: 16)
}

/// A run of inline text with one style. `spoiler` is the spoiler's index in the document (-1 = none).
struct MdInline: Hashable, Sendable {
    var text: String
    var style: MdStyle = []
    var link: String? = nil
    var spoiler: Int = -1

    func has(_ bit: MdStyle) -> Bool { style.contains(bit) }
}

enum MdBlock: Hashable, Sendable {
    case paragraph([MdInline])
    case heading(level: Int, [MdInline])
    case quote([MdBlock])
    case list(ordered: Bool, start: Int, items: [[MdBlock]])
    case code(String)
    /// `align`: -1 left/none, 0 center, 1 right, per column.
    case table(header: [[MdInline]], rows: [[[MdInline]]], align: [Int])
    case image(url: String, alt: String)
    case rule
}

struct MdDocument: Hashable, Sendable {
    var blocks: [MdBlock]
    var spoilerCount: Int
    /// Decided while parsing (off the main actor), so a cell bind doesn't scan the text.
    var isRtl = false
}

enum RedditMarkdownParser {
    // `>!` at the start of a line would be parsed as a blockquote before any
    // inline syntax runs, so spoilers are swapped for private-use markers first.
    fileprivate static let open: Unicode.Scalar = "\u{E000}"
    fileprivate static let close: Unicode.Scalar = "\u{E001}"
    fileprivate static let openUnit: UInt16 = 0xE000
    fileprivate static let closeUnit: UInt16 = 0xE001
    private static let spoilerRe = try! NSRegularExpression(pattern: ">!(.+?)!<")

    // swift-cmark reads `^[text](attrs)` as an Apple "inline attribute" and it
    // can't be turned off, but on Reddit that's a superscript caret before a
    // link (very common): hide the caret from the parser, like the spoilers.
    fileprivate static let caret: Unicode.Scalar = "\u{E002}"

    // `^(several words)` or `^word`, as Reddit renders them. The whitespace class
    // is spelled out: Java's `\s` is ASCII-only, ICU's isn't.
    fileprivate static let supRe = try! NSRegularExpression(pattern: #"\^\(([^)\n]+)\)|\^([^ \t\n\u000B\f\r^()]+)"#)

    // A bare u/name or r/name, with an optional leading slash, as Reddit links
    // them. Not in the middle of a word or path (and/or/r/foo).
    fileprivate static let mentionRe = try! NSRegularExpression(pattern: #"(?<![\w/])/?[ru]/[A-Za-z0-9_][A-Za-z0-9_-]+"#)

    // Parsing is cheap but a long thread re-binds hundreds of rows while
    // scrolling; keep recent results (keyed by the raw text). NSCache is
    // thread-safe. Kotlin keeps 600; here `prewarm` loads whole threads.
    private static let cache: NSCache<NSString, Box> = {
        let c = NSCache<NSString, Box>()
        c.countLimit = 2000
        return c
    }()
    private final class Box {
        let doc: MdDocument
        init(_ doc: MdDocument) { self.doc = doc }
    }

    /// Parses (or returns the cached parse of) `text`. Thread-safe.
    static func parse(_ text: String) -> MdDocument {
        if let hit = cached(text) { return hit }
        let doc = parseUncached(text)
        cache.setObject(Box(doc), forKey: text as NSString)
        return doc
    }

    /// The cached parse, if any: lets a cell bind avoid parsing a long body on the main actor.
    static func cached(_ text: String) -> MdDocument? { cache.object(forKey: text as NSString)?.doc }

    /// Parses `texts` off the main actor, so the cells that show them bind without parsing:
    /// call it with a thread's or listing's bodies as soon as they load.
    static func prewarm(_ texts: [String]) async {
        await Task.detached(priority: .utility) {
            for t in texts {
                if Task.isCancelled { return }
                _ = parse(t)
            }
        }.value
    }

    static func parseUncached(_ text: String) -> MdDocument {
        // A hostile body (`>>>>…`, `- - - …`, `*a *b *c … c* b* a*`) can nest tens of
        // thousands of levels, and swift-markdown's tree and our walk both recurse:
        // that overflows a background thread's 512 KB stack. Nesting needs a marker
        // per level, so only bodies with many of them pay for a thread with room.
        // Everything that recurses, including freeing the tree, stays on that thread.
        var markers = 0
        for byte in text.utf8 {
            switch byte {
            case 0x3E, 0x2D, 0x2B, 0x2A, 0x5F, 0x7E, 0x5B, 0x21: markers += 1
            default: break
            }
        }
        guard markers > maxMarkersOnNormalStack else { return build(text) }
        var doc = MdDocument(blocks: [], spoilerCount: 0)
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            doc = build(text)
            done.signal()
        }
        thread.stackSize = 64 << 20
        // The caller waits for it: same priority, or that's a priority inversion.
        thread.qualityOfService = Thread.current.qualityOfService
        thread.start()
        done.wait()
        return doc
    }

    private static let maxMarkersOnNormalStack = 200

    private static func build(_ text: String) -> MdDocument {
        let root = Document(parsing: source(for: text), options: [.disableSmartOpts, .disableSourcePosOpts])
        var b = Builder()
        let blocks = b.blocks(root, depth: 0)
        // Hebrew / Arabic bodies are rare: most never get past the byte check.
        let rtl = text.utf8.contains { $0 >= 0xD6 } && isMostlyRtl(flattenInlines(blocks).map(\.text).joined())
        return MdDocument(blocks: blocks, spoilerCount: b.spoilers, isRtl: rtl)
    }

    /// The text cmark actually parses: spoiler and `^[` markers swapped in.
    private static func source(for text: String) -> String {
        var src = text
        if src.contains(">!") {
            let range = NSRange(location: 0, length: (src as NSString).length)
            src = spoilerRe.stringByReplacingMatches(in: src, range: range, withTemplate: "\u{E000}$1\u{E001}")
        }
        if src.contains("^[") { src = src.replacingOccurrences(of: "^[", with: "\u{E002}[", options: .literal) }
        return src
    }

    private struct Builder {
        var spoilers = 0
        private var inSpoiler = -1

        // Past this, quotes and lists are drawn flat: their text stays, but no
        // SwiftUI stack gets nested hundreds of levels deep.
        private static let maxDepth = 16
        // Far past anything real: what's nested deeper isn't walked at all, which
        // keeps this recursion well inside the big stack (see `parseUncached`).
        private static let maxWalkDepth = 500

        mutating func blocks(_ parent: some Markup, depth: Int) -> [MdBlock] {
            var out: [MdBlock] = []
            for n in parent.children { block(n, depth: depth, &out) }
            return out
        }

        private mutating func block(_ n: Markup, depth: Int, _ out: inout [MdBlock]) {
            guard depth < Self.maxWalkDepth else { return }
            switch n {
            case let n as Markdown.Paragraph:
                // Images show as images, also mid-text (`text ![](url) text`,
                // as flutter_markdown does): the paragraph is split into
                // text runs around them.
                var run: [Markup] = []
                for k in n.children {
                    if let image = k as? Markdown.Image {
                        let inl = inlines(run)
                        if !inl.isEmpty { out.append(.paragraph(inl)) }
                        run.removeAll()
                        out.append(.image(url: RedditMarkdownParser.restoringMarkers(image.source ?? ""), alt: altOf(image)))
                    } else {
                        run.append(k)
                    }
                }
                let inl = inlines(run)
                if !inl.isEmpty { out.append(.paragraph(inl)) }
            case let n as Markdown.Heading:
                out.append(.heading(level: n.level, inlines(Array(n.children))))
            case let n as Markdown.BlockQuote:
                let inner = blocks(n, depth: depth + 1)
                if depth >= Self.maxDepth {
                    out.append(contentsOf: inner)
                } else {
                    out.append(.quote(inner))
                }
            case let n as Markdown.UnorderedList:
                appendList(n, ordered: false, start: 1, depth: depth, &out)
            case let n as Markdown.OrderedList:
                appendList(n, ordered: true, start: Int(n.startIndex), depth: depth, &out)
            case let n as Markdown.CodeBlock:
                var code = RedditMarkdownParser.restoringMarkers(n.code)
                while code.hasSuffix("\n") { code.removeLast() }
                out.append(.code(code))
            case is Markdown.ThematicBreak:
                out.append(.rule)
            case let n as Markdown.HTMLBlock:
                out.append(.paragraph(textRuns(n.rawHTML.trimmingKotlinWhitespace(), [], nil)))
            case let n as Markdown.Table:
                out.append(table(n))
            default:
                if n.childCount > 0 { out.append(contentsOf: blocks(n, depth: depth)) }
            }
        }

        private mutating func appendList(_ n: some Markup, ordered: Bool, start: Int, depth: Int, _ out: inout [MdBlock]) {
            var items: [[MdBlock]] = []
            for case let item as Markdown.ListItem in n.children {
                var content = blocks(item, depth: depth + 1)
                // cmark's task lists eat `[ ]`; Reddit doesn't have them, it shows the text.
                if let box = item.checkbox {
                    let mark = MdInline(text: box == .checked ? "[x] " : "[ ] ")
                    if case .paragraph(var inl)? = content.first {
                        if inl[0].style == [] && inl[0].link == nil && inl[0].spoiler == -1 {
                            inl[0].text = mark.text + inl[0].text
                        } else {
                            inl.insert(mark, at: 0)
                        }
                        content[0] = .paragraph(inl)
                    } else {
                        content.insert(.paragraph([MdInline(text: mark.text.trimmingKotlinWhitespace())]), at: 0)
                    }
                }
                items.append(content)
            }
            if depth >= Self.maxDepth {
                out.append(contentsOf: items.joined())
            } else {
                out.append(.list(ordered: ordered, start: start, items: items))
            }
        }

        private mutating func table(_ t: Markdown.Table) -> MdBlock {
            var header: [[MdInline]] = []
            for c in t.head.cells { header.append(cell(c)) }
            var rows: [[[MdInline]]] = []
            for row in t.body.rows {
                var cells: [[MdInline]] = []
                for c in row.cells { cells.append(cell(c)) }
                rows.append(cells)
            }
            let align: [Int] = t.columnAlignments.map {
                switch $0 {
                case .center: 0
                case .right: 1
                default: -1
                }
            }
            return .table(header: header, rows: rows, align: align)
        }

        private mutating func cell(_ c: Markdown.Table.Cell) -> [MdInline] {
            // swift-markdown always parses table spans: a lone `^` means "merge with the
            // cell above" and loses its text. Reddit has no spans, the `^` is just text.
            if c.rowspan == 0 { return [MdInline(text: "^")] }
            return inlines(Array(c.children))
        }

        /// Inline runs of `nodes` (a block's children, or a slice of them).
        mutating func inlines(_ nodes: [Markup]) -> [MdInline] {
            var out: [MdInline] = []
            for n in nodes { walkNode(n, [], nil, &out) }
            // Trim the paragraph's outer whitespace and merge equal runs.
            var merged: [MdInline] = []
            merged.reserveCapacity(out.count)
            for r in out {
                if let last = merged.last, last.style == r.style, last.link == r.link, last.spoiler == r.spoiler {
                    merged[merged.count - 1].text += r.text
                } else {
                    merged.append(r)
                }
            }
            if !merged.isEmpty {
                merged[0].text = String(merged[0].text.drop(while: \.isWhitespace))
                let li = merged.count - 1
                while merged[li].text.last?.isWhitespace == true { merged[li].text.removeLast() }
            }
            return merged.filter { !$0.text.isEmpty }
        }

        private mutating func walk(_ parent: Markup, _ style: MdStyle, _ link: String?, _ out: inout [MdInline]) {
            for n in parent.children { walkNode(n, style, link, &out) }
        }

        private mutating func walkNode(_ n: Markup, _ style: MdStyle, _ link: String?, _ out: inout [MdInline]) {
            switch n {
            case let n as Markdown.Text:
                // commonmark-java autolinks as a post-process, on text outside links.
                if link == nil, let parts = autolinkParts(n.string) {
                    for (text, href) in parts { textRuns(text, style, href, &out) }
                } else {
                    textRuns(n.string, style, link, &out)
                }
            case let n as Markdown.InlineCode:
                out.append(MdInline(text: RedditMarkdownParser.restoringMarkers(n.code), style: style.union(.code), link: link, spoiler: inSpoiler))
            case is Markdown.Emphasis: walk(n, style.union(.italic), link, &out)
            case is Markdown.Strong: walk(n, style.union(.bold), link, &out)
            case is Markdown.Strikethrough: walk(n, style.union(.strike), link, &out)
            case let n as Markdown.Link: walk(n, style, RedditMarkdownParser.restoringMarkers(n.destination ?? ""), &out)
            // An image nested in a link or emphasis: its alt text, linking to the image.
            case let n as Markdown.Image:
                let alt = altOf(n)
                out.append(MdInline(text: alt.isEmpty ? n.source ?? "" : alt, style: style, link: n.source ?? "", spoiler: inSpoiler))
            case is Markdown.SoftBreak: out.append(MdInline(text: " ", style: style, link: link, spoiler: inSpoiler))
            case is Markdown.LineBreak: out.append(MdInline(text: "\n", style: style, link: link, spoiler: inSpoiler))
            case let n as Markdown.InlineHTML: textRuns(n.rawHTML, style, link, &out)
            default: walk(n, style, link, &out)
            }
        }

        private mutating func textRuns(_ text: String, _ style: MdStyle, _ link: String?) -> [MdInline] {
            var out: [MdInline] = []
            textRuns(text, style, link, &out)
            return out
        }

        /// Splits on spoiler markers and superscripts.
        private mutating func textRuns(_ text: String, _ style: MdStyle, _ link: String?, _ out: inout [MdInline]) {
            // Most text has no marker at all: no copy, no per-character walk.
            let hasMarker = text.utf8.contains(0xEE)
            guard hasMarker else {
                supRuns(text, style, link, inSpoiler, &out)
                return
            }
            // By scalar: a combining mark after a marker would hide it inside a Character.
            var sb = ""
            for ch in text.unicodeScalars {
                switch ch {
                case RedditMarkdownParser.open:
                    if !sb.isEmpty { supRuns(sb, style, link, inSpoiler, &out); sb = "" }
                    inSpoiler = spoilers
                    spoilers += 1
                case RedditMarkdownParser.close:
                    if !sb.isEmpty { supRuns(sb, style, link, inSpoiler, &out); sb = "" }
                    inSpoiler = -1
                case RedditMarkdownParser.caret:
                    sb.unicodeScalars.append("^")
                default:
                    sb.unicodeScalars.append(ch)
                }
            }
            if !sb.isEmpty { supRuns(sb, style, link, inSpoiler, &out) }
        }

        private func supRuns(_ text: String, _ style: MdStyle, _ link: String?, _ spoiler: Int, _ out: inout [MdInline]) {
            guard text.utf8.contains(0x5E) else {
                mentionRuns(text, style, link, spoiler, &out)
                return
            }
            let ns = text as NSString
            var i = 0
            for m in RedditMarkdownParser.supRe.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                if m.range.location > i {
                    mentionRuns(ns.substring(with: NSRange(location: i, length: m.range.location - i)), style, link, spoiler, &out)
                }
                let group = m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range(at: 2)
                mentionRuns(ns.substring(with: group), style.union(.sup), link, spoiler, &out)
                i = m.range.location + m.range.length
            }
            if i < ns.length { mentionRuns(ns.substring(from: i), style, link, spoiler, &out) }
        }

        // Reddit links a bare u/name and r/name; the API's markdown leaves them as
        // text (#102). `AppNavigator.openLink` takes them as they are.
        private func mentionRuns(_ text: String, _ style: MdStyle, _ link: String?, _ spoiler: Int, _ out: inout [MdInline]) {
            guard link == nil, text.contains("r/") || text.contains("u/") else {
                out.append(MdInline(text: text, style: style, link: link, spoiler: spoiler))
                return
            }
            let ns = text as NSString
            var i = 0
            for m in RedditMarkdownParser.mentionRe.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                if m.range.location > i {
                    out.append(MdInline(text: ns.substring(with: NSRange(location: i, length: m.range.location - i)), style: style, spoiler: spoiler))
                }
                let name = ns.substring(with: m.range)
                out.append(MdInline(text: name, style: style, link: name, spoiler: spoiler))
                i = m.range.location + m.range.length
            }
            if i < ns.length { out.append(MdInline(text: ns.substring(from: i), style: style, spoiler: spoiler)) }
        }

        private func altOf(_ image: Markdown.Image) -> String {
            var sb = ""
            for c in image.children {
                if let t = c as? Markdown.Text { sb += t.string }
            }
            return sb
        }
    }

    /// Code and link targets keep their source: spoiler and `^[` markers inside them go
    /// back to what was typed. (Kotlin leaves the private-use characters in.)
    fileprivate static func restoringMarkers(_ code: String) -> String {
        guard code.utf8.contains(0xEE) else { return code }
        return code
            .replacingOccurrences(of: String(open), with: ">!", options: .literal)
            .replacingOccurrences(of: String(close), with: "!<", options: .literal)
            .replacingOccurrences(of: String(caret), with: "^", options: .literal)
    }
}

// MARK: - Autolinks (the rules of autolink-java, which commonmark-java uses)

/// Splits `text` around its bare URLs, `www.` addresses and email addresses as (text, link)
/// parts, nil when there are none. Works on UTF-16 units like the Java it mirrors.
func autolinkParts(_ text: String) -> [(String, String?)]? {
    // Most text has none of the triggers: a cheap byte scan, no array copy.
    guard text.utf8.contains(where: { $0 == 0x3A || $0 == 0x40 || $0 == 0x77 }) else { return nil }
    let input = Array(text.utf16)
    var parts: [(String, String?)] = []
    var index = 0
    var rewind = 0
    var found = false
    func str(_ a: Int, _ b: Int) -> String { String(decoding: input[a..<b], as: UTF16.self) }
    while index < input.count {
        let span: (first: Int, end: Int, prefix: String)?
        switch input[index] {
        case 0x3A: span = urlSpan(input, index, rewind)
        case 0x40: span = emailSpan(input, index, rewind)
        case 0x77: span = wwwSpan(input, index, rewind)
        default: span = nil
        }
        guard let span else {
            index += 1
            continue
        }
        found = true
        if span.first > rewind { parts.append((str(rewind, span.first), nil)) }
        let literal = str(span.first, span.end)
        parts.append((literal, span.prefix + RedditMarkdownParser.restoringMarkers(literal)))
        index = span.end
        rewind = index
    }
    guard found else { return nil }
    if rewind < input.count { parts.append((str(rewind, input.count), nil)) }
    return parts
}

private func isAlpha(_ c: UInt16) -> Bool { (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) }
private func isDigit(_ c: UInt16) -> Bool { c >= 0x30 && c <= 0x39 }
private func isAlnum(_ c: UInt16) -> Bool { isAlpha(c) || isDigit(c) }

/// Our spoiler markers aren't text: a link never runs through one. (In Kotlin they
/// end up in the link's destination.)
private func isMarker(_ c: UInt16) -> Bool { c == RedditMarkdownParser.openUnit || c == RedditMarkdownParser.closeUnit }

private func urlSpan(_ s: [UInt16], _ trigger: Int, _ rewind: Int) -> (first: Int, end: Int, prefix: String)? {
    let after = trigger + 3
    guard after < s.count, s[trigger + 1] == 0x2F, s[trigger + 2] == 0x2F else { return nil }
    // See "scheme" in RFC 3986.
    var first = -1
    var digit = -1
    var i = trigger - 1
    while i >= rewind {
        let c = s[i]
        if isAlpha(c) {
            first = i
        } else if isDigit(c) {
            digit = i
        } else if c != 0x2B && c != 0x2D && c != 0x2E {
            break
        }
        i -= 1
    }
    // We don't want to extract "abc://foo" out of "1abc://foo".
    // ".abc://foo" and others are ok though, as they feel more like separators.
    if first > 0 && first - 1 == digit { first = -1 }
    guard first != -1 else { return nil }
    let last = urlEnd(s, after)
    guard last != -1 else { return nil }
    return (first, last + 1, "")
}

private func wwwSpan(_ s: [UInt16], _ trigger: Int, _ rewind: Int) -> (first: Int, end: Int, prefix: String)? {
    let after = trigger + 4
    guard after < s.count, s[trigger + 1] == 0x77, s[trigger + 2] == 0x77, s[trigger + 3] == 0x2E else { return nil }
    if trigger != rewind {
        let before = s[trigger - 1]
        guard before != 0x2E, !isAlnum(before) else { return nil }
    }
    let last = urlEnd(s, after)
    guard last != -1 else { return nil }
    // At least one dot after the first: www.something isn't a link, www.something.co.uk is.
    var p = last - 1
    while p > after {
        if s[p] == 0x2E { return (trigger, last + 1, "http://") }
        p -= 1
    }
    return nil
}

private func emailSpan(_ s: [UInt16], _ trigger: Int, _ rewind: Int) -> (first: Int, end: Int, prefix: String)? {
    // See "Local-part" in RFC 5321, plus extensions in RFC 6531.
    func localAllowed(_ c: UInt16) -> Bool {
        if isMarker(c) { return false }
        if isAlnum(c) || c >= 0x80 { return true }
        switch c {
        case 0x21, 0x23, 0x24, 0x25, 0x26, 0x27, 0x2A, 0x2B, 0x2D, 0x2F, 0x3D, 0x3F, 0x5E, 0x5F, 0x60, 0x7B, 0x7C, 0x7D, 0x7E: return true
        default: return false
        }
    }
    var first = -1
    var atomBoundary = true
    var i = trigger - 1
    while i >= rewind {
        let c = s[i]
        if localAllowed(c) {
            first = i
            atomBoundary = false
        } else if c == 0x2E {
            if atomBoundary { break }
            atomBoundary = true
        } else {
            break
        }
        i -= 1
    }
    guard first != -1 else { return nil }
    // See "Domain" in RFC 5321, plus the "sub-domain" extension in RFC 6531.
    func domainAllowed(_ c: UInt16) -> Bool { !isMarker(c) && (isAlnum(c) || c >= 0x80) }
    var firstInSubDomain = true
    var canEndSubDomain = false
    var firstDot = -1
    var last = -1
    i = trigger + 1
    while i < s.count {
        let c = s[i]
        if firstInSubDomain {
            guard domainAllowed(c) else { break }
            last = i
            firstInSubDomain = false
            canEndSubDomain = true
        } else if c == 0x2E {
            if !canEndSubDomain { break }
            firstInSubDomain = true
            if firstDot == -1 { firstDot = i }
        } else if c == 0x2D {
            canEndSubDomain = false
        } else if domainAllowed(c) {
            last = i
            canEndSubDomain = true
        } else {
            break
        }
        i += 1
    }
    guard firstDot != -1, firstDot <= last else { return nil }
    return (first, last + 1, "mailto:")
}

private func urlEnd(_ s: [UInt16], _ begin: Int) -> Int {
    var round = 0
    var square = 0
    var curly = 0
    var singleQuote = false
    var last = -1
    var i = begin
    scan: while i < s.count {
        let c = s[i]
        switch c {
        // Can never be part of a URL (RFC 3986 / 3987), must be percent-encoded in one,
        // or Unicode spaces that look like a space, so it would be confusing not to end there.
        case 0x00...0x20, 0x22, 0x3C, 0x3E, 0x60, 0x7F...0xA0,
             0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000,
             RedditMarkdownParser.openUnit, RedditMarkdownParser.closeUnit:
            break scan
        // These may be part of a URL but not at the end.
        case 0x3F, 0x21, 0x2E, 0x2C, 0x3A, 0x3B:
            break
        // May be at the end, but not if the previous character can't be.
        case 0x2F:
            if last == i - 1 { last = i }
        case 0x28: round += 1
        case 0x29:
            round -= 1
            guard round >= 0 else { break scan }
            last = i
        case 0x5B: square += 1
        case 0x5D:
            square -= 1
            guard square >= 0 else { break scan }
            last = i
        case 0x7B: curly += 1
        case 0x7D:
            curly -= 1
            guard curly >= 0 else { break scan }
            last = i
        case 0x27:
            singleQuote.toggle()
            if !singleQuote { last = i }
        default:
            last = i
        }
        i += 1
    }
    return last
}

// MARK: - Text helpers

private extension String {
    /// Kotlin's `trim()`: Unicode whitespace from both ends.
    func trimmingKotlinWhitespace() -> String {
        var s = Substring(self).drop(while: \.isWhitespace)
        while s.last?.isWhitespace == true { s.removeLast() }
        return String(s)
    }
}

extension MdDocument {
    /// The document's text as one plain string (paragraphs on new lines).
    func plainText() -> String {
        var out = ""
        func inl(_ l: [MdInline]) -> String { l.map(\.text).joined() }
        func walk(_ blocks: [MdBlock]) {
            for b in blocks {
                switch b {
                case .paragraph(let i): out += inl(i) + "\n"
                case .heading(_, let i): out += inl(i) + "\n"
                case .quote(let q): walk(q)
                case .list(_, _, let items): items.forEach(walk)
                case .code(let c): out += c + "\n"
                case .table(let header, let rows, _):
                    for row in [header] + rows { out += row.map(inl).joined(separator: " | ") + "\n" }
                case .image(_, let alt): out += alt + "\n"
                case .rule: break
                }
            }
        }
        walk(blocks)
        while out.last?.isWhitespace == true { out.removeLast() }
        return out
    }
}

/// All inline runs, blocks separated by newlines (for maxLines previews).
func flattenInlines(_ blocks: [MdBlock]) -> [MdInline] {
    var out: [MdInline] = []
    func nl() {
        if !out.isEmpty { out.append(MdInline(text: "\n")) }
    }
    func walk(_ bs: [MdBlock]) {
        for b in bs {
            switch b {
            case .paragraph(let i):
                nl()
                out += i
            case .heading(_, let i):
                nl()
                out += i.map { var r = $0; r.style.insert(.bold); return r }
            case .quote(let q):
                walk(q)
            case .list(let ordered, let start, let items):
                for (i, item) in items.enumerated() {
                    nl()
                    out.append(MdInline(text: ordered ? "\(start + i). " : "• "))
                    let before = out.count
                    walk(item)
                    // The item's first paragraph sits on the bullet's line.
                    if out.count > before, out[before].text == "\n" { out.remove(at: before) }
                }
            case .code(let c):
                nl()
                out.append(MdInline(text: c, style: .code))
            case .table(let header, let rows, _):
                for row in [header] + rows {
                    nl()
                    for (i, cell) in row.enumerated() {
                        if i > 0 { out.append(MdInline(text: " | ")) }
                        out += cell
                    }
                }
            case .image(let url, let alt):
                nl()
                out.append(MdInline(text: alt.isEmpty ? url : alt, link: url))
            case .rule:
                break
            }
        }
    }
    walk(blocks)
    return out
}
