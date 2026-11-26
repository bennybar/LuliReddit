import SwiftUI

/// The system's loading spinner, for Kotlin's `Loading`. Pull to refresh (Kotlin's
/// `RefreshBox`) is simply `.refreshable` here.
struct Loading: View {
    var body: some View { ProgressView() }
}

/// A native menu for picking one of `options`: the current one is ticked (also for
/// screen readers). Picking closes it. `label` is what's tapped to open it.
struct PickOneMenu<K: Hashable, MenuLabel: View>: View {
    let options: [(key: K, label: String)]
    let selected: K?
    let onPick: (K) -> Void
    /// An SF Symbol per option.
    var icon: ((K) -> String)? = nil
    @ViewBuilder var label: () -> MenuLabel

    var body: some View {
        Menu {
            Picker(selection: Binding(get: { selected }, set: { if let key = $0 { onPick(key) } })) {
                ForEach(options, id: \.key) { option in
                    Group {
                        if let icon {
                            Label(option.label, systemImage: icon(option.key))
                        } else {
                            Text(option.label)
                        }
                    }
                    .tag(K?.some(option.key))
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        } label: {
            label()
        }
    }
}

/// A pick-one choice, as a segmented control. `fill`: the segments share the width;
/// otherwise they size to their labels. `icon`: an SF Symbol per option, shown in
/// place of the label (which stays as its description for VoiceOver).
struct ConnectedChoice<K: Hashable>: View {
    let options: [(key: K, label: String)]
    let selected: K
    let onSelect: (K) -> Void
    var fill = true
    var icon: ((K) -> String)? = nil

    var body: some View {
        let picker = Picker("", selection: Binding(get: { selected }, set: onSelect)) {
            ForEach(options, id: \.key) { option in
                Group {
                    if let icon {
                        Image(systemName: icon(option.key)).accessibilityLabel(option.label)
                    } else {
                        Text(option.label)
                    }
                }
                .tag(option.key)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        if fill { picker } else { picker.fixedSize() }
    }
}

/// An on/off icon (save, favourite…): screen readers hear its state, and the
/// symbol swaps with the system's replace effect.
struct ToggleIcon: View {
    let checked: Bool
    let onCheckedChange: (Bool) -> Void
    let on: String
    let off: String
    let description: String

    var body: some View {
        Button { onCheckedChange(!checked) } label: {
            Image(systemName: checked ? on : off)
                .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityLabel(description)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }
}

/// A colour picked from `name` by a stable hash, so a name keeps its colour everywhere:
/// mid tones, the same picks as Kotlin's.
private func avatarArgb(_ name: String) -> Int {
    let palette: [Int] = [0xFF7C5CE0, 0xFF4FA89B, 0xFFC77E4A, 0xFFC46A96, 0xFF5B82CE, 0xFF5FA85A]
    let hash = name.utf16.reduce(0) { ($0 * 31 + Int($1)) & 0x7fffffff }
    return palette[hash % palette.count]
}

func avatarColor(_ name: String) -> Color { Color(argb: avatarArgb(name)) }

/// A placeholder's colours (#168), like WhatsApp's: `name`'s colour faint behind its letter
/// in a deeper shade, and in dark mode deep behind a lighter letter.
func avatarTones(_ name: String) -> (background: Color, letter: Color) {
    let c = avatarArgb(name)
    // `c` mixed toward `to` (0: black, 1: white) by `t`.
    func mix(_ to: CGFloat, _ t: CGFloat) -> UIColor {
        func ch(_ shift: Int) -> CGFloat { CGFloat((c >> shift) & 0xFF) / 255 * (1 - t) + to * t }
        return UIColor(red: ch(16), green: ch(8), blue: ch(0), alpha: 1)
    }
    let background = mix(1, 0.8), darkBackground = mix(0, 0.6), letter = mix(0, 0.3), darkLetter = mix(1, 0.55)
    return (
        Color(UIColor { $0.userInterfaceStyle == .dark ? darkBackground : background }),
        Color(UIColor { $0.userInterfaceStyle == .dark ? darkLetter : letter })
    )
}

/// Circle avatar showing `imageUrl` or the first letter of `name`. The letter sits on a
/// colour picked from the name (#105, softened in #168), so subreddits and users without an icon still stand
/// apart; `container` backs the image while it loads.
struct LetterAvatar: View {
    let name: String
    let size: CGFloat
    var imageUrl: String? = nil
    var container: Color = Color(.secondarySystemFill)
    var content: Color = .secondary

    var body: some View {
        ZStack {
            container
            // Always a still image: see RemoteImage.
            if let url = imageUrl.flatMap(URL.init(string:)) {
                RemoteImage(url: url) { container }
            } else {
                let tones = avatarTones(name)
                if !name.isEmpty { tones.background }
                Text(name.first.map { String($0).uppercased() } ?? "?")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(name.isEmpty ? content : tones.letter)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
    }
}

extension View {
    /// A page's title: big with Settings › Top bar › Expandable, as the tabs' (#247), else in the bar.
    func pageTitle(_ title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(app.settings.value.topBarMode == .expandable ? .large : .inline)
    }

    /// A page's search in its bar, as WhatsApp's: with Expandable a 🔍 (#247), with the Full
    /// bar the tabs' round search bar in place of the title (#285). Either opens a field across
    /// the bar, a pill with its ← inside, growing out of where it was tapped.
    func barSearch(text: Binding<String>, prompt: String) -> some View {
        modifier(BarSearchModifier(text: text, prompt: prompt, full: app.settings.value.topBarMode == .full))
    }
}

/// The page's bar search is open (`barSearch`): the page hides its own bar buttons
/// meanwhile, so the field has the bar, as WhatsApp's (#285).
struct BarSearchOpenKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

private struct BarSearchModifier: ViewModifier {
    @Binding var text: String
    let prompt: String
    let full: Bool

    @State private var open = false
    /// The button it was opened from, on screen: the field grows out of it.
    @State private var from: CGRect?
    /// The page's width: the bar's field spans it (a bar item only takes what it asks for).
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
            .navigationBarBackButtonHidden(open)
            .navigationBarTitleDisplayMode(open || full ? .inline : .large)
            .preference(key: BarSearchOpenKey.self, value: open)
            .toolbar {
                if open {
                    ToolbarItem(placement: .principal) {
                        BarSearchField(text: $text, prompt: prompt, fromSearchBar: full, from: from, width: max(0, width - 32)) {
                            text = ""
                            open = false
                        }
                    }
                } else if full {
                    ToolbarItem(placement: .principal) {
                        Button(action: openField) {
                            Text(prompt)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(width: 220, alignment: .center)
                        }
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(prompt, systemImage: "magnifyingglass", action: openField)
                    }
                }
            }
    }

    private func openField() {
        from = barButtonFrame(prompt)
        open = true
    }
}

/// The open field: a pill as tall as the bar allows, its ← inside, growing out of the button
/// it was opened from (`from`, on screen: the 🔍, or the search bar with its words travelling
/// to the field's start), and shrinking back into it on close.
private struct BarSearchField: View {
    @Binding var text: String
    let prompt: String
    let fromSearchBar: Bool
    let from: CGRect?
    let width: CGFloat
    let onClose: () -> Void

    @State private var grown = false

    var body: some View {
        HStack(spacing: 4) {
            Button("Close search", systemImage: "chevron.backward") { close() }
                .labelStyle(.iconOnly)
                .frame(width: 36, height: 36)
                .opacity(grown ? 1 : 0)
            TextField(prompt, text: $text)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 12)
        .offset(x: travel)
        .frame(height: 44)
        .frame(width: width)
        // From the 🔍 there are no words to move: they fade in as it grows.
        .opacity(grown || fromSearchBar ? 1 : 0)
        .background(alignment: .topLeading) {
            let r = pill
            Capsule()
                .fill(Color(.tertiarySystemFill))
                .frame(width: r.width, height: r.height)
                .offset(x: r.minX, y: r.minY)
        }
        .onAppear {
            // After its first frame, at the button's size.
            Task { withAnimation(.snappy(duration: 0.3)) { grown = true } }
            // The keyboard, once it's in the bar (a focus state doesn't reach into the bar).
            Task {
                try? await Task.sleep(for: .milliseconds(150))
                focusBarField(placeholder: prompt)
            }
        }
    }

    /// The pill, in this view's space (the bar's width less 16 a side): the button it grew
    /// from, or all of it.
    private var pill: CGRect {
        if grown { return CGRect(x: 0, y: 0, width: width, height: 44) }
        if let from { return CGRect(x: from.minX - 16, y: 0, width: from.width, height: 44) }
        return fromSearchBar
            ? CGRect(x: (width - 220) / 2, y: 0, width: 220, height: 44)
            : CGRect(x: width - 44, y: 0, width: 44, height: 44)
    }

    /// From the search bar, the words start where they were on it (its middle) and travel to
    /// the field's start, after the ←: how far right of there.
    private var travel: CGFloat {
        guard !grown, fromSearchBar, let from else { return 0 }
        let words = (prompt as NSString).size(withAttributes: [.font: UIFont.preferredFont(forTextStyle: .body)]).width
        return from.midX - words / 2 - 16 - 44
    }

    private func close() {
        endEditing()
        withAnimation(.snappy(duration: 0.25)) { grown = false } completion: { onClose() }
    }
}

/// Puts the keyboard on the shown text field with `placeholder` (one in the bar can't be
/// focused with a focus state).
@MainActor func focusBarField(placeholder: String) {
    guard let window = topViewController()?.view.window else { return }
    func find(_ v: UIView) -> UITextField? {
        if let f = v as? UITextField, f.placeholder == placeholder, !f.isHidden { return f }
        for s in v.subviews { if let f = find(s) { return f } }
        return nil
    }
    find(window)?.becomeFirstResponder()
}

/// Closes the keyboard, wherever it's typing.
@MainActor func endEditing() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
