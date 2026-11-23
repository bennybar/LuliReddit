import SwiftUI

/// A post's text as a feed shows it, a few lines (#241): the inline markdown drawn (bold,
/// italic, strikethrough, code, spoilers covered) instead of its `**` and `>!` showing;
/// links as their words, headings bold, quote marks dropped. Not the thread's full
/// markdown: a cheap pass for a few lines, done once per row. Pure, so it's tested; the
/// Kotlin app's `snippetMarkdown` is the same.
func snippetMarkdown(_ text: String, spoiler: Color = Color(uiColor: .systemGray3)) -> AttributedString {
    let decoded = text.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&amp;", with: "&")
    var out = AttributedString()
    for (n, raw) in decoded.components(separatedBy: "\n").enumerated() {
        if n > 0 { out += AttributedString("\n") }
        var line = Substring(raw)
        var heading = false
        let hashes = line.prefix(while: { $0 == "#" }).count
        if (1...6).contains(hashes), line.dropFirst(hashes).first?.isWhitespace == true {
            line = line.dropFirst(hashes).drop(while: { $0.isWhitespace })
            heading = true
        }
        // A quote's "> " (not a spoiler's ">!").
        while line.hasPrefix(">"), !line.hasPrefix(">!") { line = line.dropFirst().drop(while: { $0 == " " }) }
        out += SnippetInline(spoiler: spoiler).run(Array(line), heading ? .stronglyEmphasized : [])
    }
    return out
}

private struct SnippetInline {
    let spoiler: Color

    private func find(_ s: [Character], _ token: String, from: Int) -> Int? {
        let t = Array(token)
        var i = from
        while i + t.count <= s.count {
            if Array(s[i..<i + t.count]) == t { return i }
            i += 1
        }
        return nil
    }

    /// The closing [token]'s index: text between, not starting or ending with a space.
    private func closing(_ s: [Character], _ token: String, from: Int) -> Int? {
        guard let end = find(s, token, from: from), end > from, !s[from].isWhitespace, !s[end - 1].isWhitespace else { return nil }
        return end
    }

    private func starts(_ s: [Character], _ token: String, at i: Int) -> Bool {
        let t = Array(token)
        return i + t.count <= s.count && Array(s[i..<i + t.count]) == t
    }

    func run(_ s: [Character], _ intent: InlinePresentationIntent, covered: Bool = false) -> AttributedString {
        var out = AttributedString()
        var plain = ""
        func flush() {
            guard !plain.isEmpty else { return }
            var a = AttributedString(plain)
            if !intent.isEmpty { a.inlinePresentationIntent = intent }
            if covered { a.foregroundColor = spoiler; a.backgroundColor = spoiler }
            out += a
            plain = ""
        }
        func nested(_ from: Int, _ to: Int, _ add: InlinePresentationIntent, cover: Bool = false) {
            flush()
            out += run(Array(s[from..<to]), intent.union(add), covered: covered || cover)
        }
        var i = 0
        while i < s.count {
            let c = s[i]
            if c == "\\", i + 1 < s.count, !s[i + 1].isLetter, !s[i + 1].isNumber {
                plain.append(s[i + 1]); i += 2; continue
            }
            if starts(s, ">!", at: i), let end = find(s, "!<", from: i + 2), end > i + 2 {
                nested(i + 2, end, [], cover: true); i = end + 2; continue
            }
            if starts(s, "**", at: i) || starts(s, "__", at: i) || starts(s, "~~", at: i) {
                let token = String(s[i..<i + 2])
                if let end = closing(s, token, from: i + 2) {
                    nested(i + 2, end, token == "~~" ? .strikethrough : .stronglyEmphasized); i = end + 2; continue
                }
            }
            if c == "`", let end = find(s, "`", from: i + 1), end > i + 1 {
                flush()
                var a = AttributedString(String(s[i + 1..<end]))
                a.inlinePresentationIntent = intent.union(.code)
                if covered { a.foregroundColor = spoiler; a.backgroundColor = spoiler }
                out += a
                i = end + 1; continue
            }
            // _italic_ only between words' edges, so snake_case stays as typed.
            if c == "*" || (c == "_" && (i == 0 || !(s[i - 1].isLetter || s[i - 1].isNumber))),
               let end = closing(s, String(c), from: i + 1),
               c == "*" || end + 1 >= s.count || !(s[end + 1].isLetter || s[end + 1].isNumber) {
                nested(i + 1, end, .emphasized); i = end + 1; continue
            }
            if c == "[", let mid = find(s, "](", from: i + 1), let end = find(s, ")", from: mid + 2) {
                nested(i + 1, mid, []); i = end + 1; continue
            }
            plain.append(c)
            i += 1
        }
        flush()
        return out
    }
}
