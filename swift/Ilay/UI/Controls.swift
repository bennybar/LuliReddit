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

/// A colour picked from `name` by a stable hash, so a name keeps its colour everywhere: the
/// comment author dots' palette, mid tones that carry white text in light and dark.
func avatarColor(_ name: String) -> Color {
    let palette: [Int] = [0xFF7C5CE0, 0xFF4FA89B, 0xFFC77E4A, 0xFFC46A96, 0xFF5B82CE, 0xFF5FA85A]
    let hash = name.utf16.reduce(0) { ($0 * 31 + Int($1)) & 0x7fffffff }
    return Color(argb: palette[hash % palette.count])
}

/// Circle avatar showing `imageUrl` or the first letter of `name`. The letter sits on a
/// colour picked from the name (#105), so subreddits and users without an icon still stand
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
                if !name.isEmpty { avatarColor(name) }
                Text(name.first.map { String($0).uppercased() } ?? "?")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(name.isEmpty ? content : .white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
    }
}
