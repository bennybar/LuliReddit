import SwiftUI

/// A text edit result: new text + selection, as UTF-16 offsets (like Kotlin's, and
/// `UITextView`'s: one emoji is two).
struct MdEdit: Equatable {
    let text: String
    let selStart: Int
    let selEnd: Int
}

/// Wraps the selection (or inserts `placeholder` at the caret) with `left`/`right`
/// and selects the inner text so the user can keep typing over it. An invalid
/// selection (-1) acts at the end of the text.
func mdWrap(_ text: String, _ selStart: Int, _ selEnd: Int, _ left: String, _ right: String, placeholder: String = "") -> MdEdit {
    let ns = text as NSString
    let valid = selStart >= 0 && selEnd >= 0
    let start = valid ? min(min(selStart, selEnd), ns.length) : ns.length
    let end = valid ? min(max(selStart, selEnd), ns.length) : ns.length
    let selected = start == end ? placeholder : ns.substring(with: NSRange(location: start, length: end - start))
    let newText = ns.replacingCharacters(in: NSRange(location: start, length: end - start), with: left + selected + right)
    let inner = start + (left as NSString).length
    return MdEdit(text: newText, selStart: inner, selEnd: inner + (selected as NSString).length)
}

/// Prefixes each selected line (or the caret's line) with `prefix`; caret goes to the block's end.
func mdLinePrefix(_ text: String, _ selStart: Int, _ selEnd: Int, _ prefix: String) -> MdEdit {
    let ns = text as NSString
    let valid = selStart >= 0 && selEnd >= 0
    let start = valid ? min(min(selStart, selEnd), ns.length) : ns.length
    let end = valid ? min(max(selStart, selEnd), ns.length) : ns.length
    let before = ns.range(of: "\n", options: [.backwards, .literal], range: NSRange(location: 0, length: start))
    let lineStart = before.location == NSNotFound ? 0 : before.location + 1
    let after = ns.range(of: "\n", options: .literal, range: NSRange(location: end, length: ns.length - end))
    let lineEnd = after.location == NSNotFound ? ns.length : after.location
    let lines = NSRange(location: lineStart, length: lineEnd - lineStart)
    let updated = ns.substring(with: lines).components(separatedBy: "\n").map { prefix + $0 }.joined(separator: "\n")
    let caret = lineStart + (updated as NSString).length
    return MdEdit(text: ns.replacingCharacters(in: lines, with: updated), selStart: caret, selEnd: caret)
}

/// A compact formatting bar for a Markdown text field. Wraps the current selection
/// (or inserts placeholders at the caret) with Reddit-flavored markdown. Bind it to the
/// same text and selection as the field: `TextEditor(text: $text, selection: $selection)`.
struct MarkdownToolbar: View {
    @Binding var text: String
    @Binding var selection: TextSelection?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                button("bold", "Bold") { wrap("**", "**", "bold") }
                button("italic", "Italic") { wrap("*", "*", "italic") }
                button("strikethrough", "Strikethrough") { wrap("~~", "~~", "text") }
                button("link", "Link") { wrap("[", "](https://)", "text") }
                button("text.quote", "Quote") { prefix("> ") }
                button("list.bullet", "List") { prefix("- ") }
                button("eye.slash", "Spoiler") { wrap(">!", "!<", "spoiler") }
                button("chevron.left.forwardslash.chevron.right", "Code") { wrap("`", "`", "code") }
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private func button(_ symbol: String, _ tip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 40, height: 40)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(tip)
    }

    private func wrap(_ left: String, _ right: String, _ placeholder: String) {
        let (start, end) = offsets
        apply(mdWrap(text, start, end, left, right, placeholder: placeholder))
    }

    private func prefix(_ prefix: String) {
        let (start, end) = offsets
        apply(mdLinePrefix(text, start, end, prefix))
    }

    /// UTF-16 offsets of the selection; -1 with none, or one from before an edit
    /// that made it no longer fit the text.
    private var offsets: (Int, Int) {
        guard case .selection(let range)? = selection?.indices,
              range.upperBound <= text.endIndex else { return (-1, -1) }
        return (range.lowerBound.utf16Offset(in: text), range.upperBound.utf16Offset(in: text))
    }

    private func apply(_ edit: MdEdit) {
        text = edit.text
        let start = String.Index(utf16Offset: edit.selStart, in: edit.text)
        let end = String.Index(utf16Offset: edit.selEnd, in: edit.text)
        selection = start == end ? TextSelection(insertionPoint: start) : TextSelection(range: start..<end)
    }
}

extension View {
    /// `MarkdownToolbar` as the keyboard's accessory bar, for a field bound to the same state.
    func markdownKeyboardToolbar(text: Binding<String>, selection: Binding<TextSelection?>) -> some View {
        toolbar {
            ToolbarItem(placement: .keyboard) {
                MarkdownToolbar(text: text, selection: selection)
            }
        }
    }
}
