import SwiftUI

/// Reddit's length limits, in characters: it refuses anything longer, so the
/// composers count down and block sending past them instead.
enum TextLimit {
    /// Comments, replies and messages.
    static let comment = 10_000
    static let postBody = 40_000
    static let title = 300
}

/// Characters as Reddit counts them (code points, not grapheme clusters: an emoji
/// with a skin tone is two).
func redditLength(_ text: String) -> Int { text.unicodeScalars.count }

/// "9100 / 10000" once `text` is within 10% of `limit`, nil before that.
func lengthCounter(_ text: String, limit: Int) -> String? {
    let count = redditLength(text)
    return count * 10 >= limit * 9 ? "\(count) / \(limit)" : nil
}

/// The counter under a field, red once over the limit; nothing while far from it.
struct LengthCounter: View {
    let text: String
    let limit: Int

    var body: some View {
        if let label = lengthCounter(text, limit: limit) {
            Text(verbatim: label)
                .font(.caption.monospacedDigit())
                .foregroundStyle(redditLength(text) > limit ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
