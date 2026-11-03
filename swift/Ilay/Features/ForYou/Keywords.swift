import Foundation

/// Exponential decay factor for the time since [tsMillis].
func decayFactor(_ tsMillis: Int?, perDay: Double, now: Int = nowMillis()) -> Double {
    guard let tsMillis else { return 1.0 }
    let days = Double((now - tsMillis) / 60_000) / (60.0 * 24)
    return days <= 0 ? 1.0 : pow(perDay, days)
}

private let stopwords: Set<String> = [
    "this", "that", "with", "from", "have", "what", "when", "where", "will",
    "just", "like", "your", "about", "they", "them", "their", "there", "been",
    "were", "after", "before", "into", "over", "under", "than", "then",
    "because", "would", "could", "should", "these", "those", "only", "some",
    "most", "more", "very", "much", "many", "made", "make", "makes", "making",
    "years", "year", "today", "every", "first", "people", "reddit", "post",
    "does", "doesn", "while", "being", "still", "until", "never", "always",
    "getting", "here", "looks", "thing", "things", "someone", "anyone",
    // Hebrew function words.
    "של", "את", "על", "זה", "גם", "לא", "מה", "אני", "יש", "כל", "עם", "אם",
    "או", "זו", "הוא", "היא", "הם", "כי", "אבל", "רק", "עוד", "כך", "אז",
    "היום", "אחרי", "לפני", "אחד", "אחת",
]

private let nonWord = Re(#"[^\p{L}\p{N}\s\p{Z}]"#)
private let whitespace = Re(#"[\s\p{Z}]+"#)
private let upper = Re(#"\p{Lu}"#)
private let letter = Re(#"\p{L}"#)
private let digit = Re(#"\d"#)
private let allDigits = Re(#"^\d+$"#)

// Scripts where short words carry meaning: Hebrew, Arabic, CJK, Hangul.
private let shortScript = Re(#"[֐-׿؀-ۿ぀-ヿ㐀-鿿가-힯]"#)
private let hebrew = Re(#"[֐-׿]"#)

/// Tokenizes a post title into learnable keywords — any script, not just
/// ASCII (Hebrew titles used to yield nothing). Latin words need 4+ letters,
/// Hebrew/Arabic/CJK 2+; short acronyms and model names (F1, NBA, AI, PS5)
/// are kept. Hebrew's definite article / "and" prefix (ה, ו) is stripped so
/// "הבחירות" and "בחירות" learn as one word.
func titleKeywords(_ title: String) -> [String] {
    var out: [String] = []
    for w in whitespace.split(nonWord.replace(title, with: " ")) {
        if w.isEmpty { continue }
        var t = w.lowercased()
        if shortScript.contains(t) {
            if hebrew.contains(t), t.length >= 4, t.hasPrefix("ה") || t.hasPrefix("ו") {
                t = String(t.unicodeScalars.dropFirst())
            }
            if t.length >= 2, !stopwords.contains(t) { out.append(t) }
        } else if (2...3).contains(w.length),
                  (w == w.uppercased() && upper.contains(w)) || (letter.contains(w) && digit.contains(w)) {
            out.append(t) // acronym / model name
        } else if t.length >= 4, !stopwords.contains(t), !allDigits.contains(t) {
            out.append(t)
        }
        if out.count == 14 { break }
    }
    return out
}
