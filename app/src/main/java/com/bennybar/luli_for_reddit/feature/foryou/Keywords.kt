package com.bennybar.luli_for_reddit.feature.foryou

import kotlin.math.pow

/** Exponential decay factor for the time since [tsMillis]. */
fun decayFactor(tsMillis: Long?, perDay: Double, now: Long = System.currentTimeMillis()): Double {
    if (tsMillis == null) return 1.0
    val days = ((now - tsMillis) / 60_000L) / (60.0 * 24)
    return if (days <= 0) 1.0 else perDay.pow(days)
}

private val STOPWORDS = setOf(
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
)

private val NON_WORD = Regex("[^\\p{L}\\p{N}\\s\\p{Z}]") // no (?U): Android ICU rejects it
private val WHITESPACE = Regex("[\\s\\p{Z}]+")
private val UPPER = Regex("\\p{Lu}")
private val LETTER = Regex("\\p{L}")
private val DIGIT = Regex("\\d")
private val ALL_DIGITS = Regex("^\\d+$")

// Scripts where short words carry meaning: Hebrew, Arabic, CJK, Hangul.
private val SHORT_SCRIPT = Regex("[֐-׿؀-ۿ぀-ヿ㐀-鿿가-힯]")
private val HEBREW = Regex("[֐-׿]")

/**
 * Tokenizes a post title into learnable keywords — any script, not just
 * ASCII (Hebrew titles used to yield nothing). Latin words need 4+ letters,
 * Hebrew/Arabic/CJK 2+; short acronyms and model names (F1, NBA, AI, PS5)
 * are kept. Hebrew's definite article / "and" prefix (ה, ו) is stripped so
 * "הבחירות" and "בחירות" learn as one word.
 */
fun titleKeywords(title: String): List<String> {
    val out = ArrayList<String>()
    for (w in title.replace(NON_WORD, " ").split(WHITESPACE)) {
        if (w.isEmpty()) continue
        var t = w.lowercase()
        if (SHORT_SCRIPT.containsMatchIn(t)) {
            if (HEBREW.containsMatchIn(t) && t.length >= 4 && (t.startsWith("ה") || t.startsWith("ו"))) {
                t = t.substring(1)
            }
            if (t.length >= 2 && t !in STOPWORDS) out.add(t)
        } else if (w.length in 2..3 &&
            ((w == w.uppercase() && UPPER.containsMatchIn(w)) ||
                (LETTER.containsMatchIn(w) && DIGIT.containsMatchIn(w)))
        ) {
            out.add(t) // acronym / model name
        } else if (t.length >= 4 && t !in STOPWORDS && !ALL_DIGITS.matches(t)) {
            out.add(t)
        }
        if (out.size == 14) break
    }
    return out
}
