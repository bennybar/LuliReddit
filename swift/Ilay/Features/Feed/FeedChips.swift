import SwiftUI

private enum FeedChoice: Hashable {
    case forYou, blend, home
    case sort(PostSort)
}

/// On the frontpage, For You / Blend / Home / Subs as a segmented control, with the sort
/// in a glass button beside it while Subs shows; elsewhere the sort button alone. Top
/// asks for its time range in the sort menu.
struct FeedChips: View {
    let controller: FeedController
    private let height: CGFloat = 36
    let state: FeedChipsState

    var body: some View {
        let s = app.settings.value
        let isFrontpage = controller.key.isEmpty
        // With the Posts tab on r/all (Settings) the frontpage is a plain pushed page.
        let engines = isFrontpage && !s.postsTabAll && app.feed.engines != nil
        let homeAllowed = engines && s.redditHomeAllowed
        let redditHome = homeAllowed && s.redditHomeFeed
        let blend = engines && s.forYouFeed && s.blendHome && s.redditHomeAllowed
        let forYou = engines && s.forYouFeed
        let current: FeedChoice = redditHome ? .home : blend ? .blend : forYou ? .forYou : .sort(controller.sort)

        let sorted = current == .sort(controller.sort)
        HStack(spacing: 10) {
            if engines {
                // Subs is the frontpage of your subscriptions, the only feed a sort applies to.
                let choices: [FeedChoice] = homeAllowed ? [.forYou, .blend, .home, .sort(controller.sort)] : [.forYou, .sort(controller.sort)]
                FeedSegments(
                    labels: homeAllowed ? ["For You", "Blend", "Home", "Subs"] : ["For You", "Subs"],
                    selected: choices.firstIndex(of: current) ?? 0
                ) { i in
                    switch choices[i] {
                    case .forYou: controller.selectForYou()
                    case .blend: controller.selectBlend()
                    case .home: controller.selectRedditHome()
                    case .sort: controller.changeSort(controller.sort)
                    }
                }
                .frame(height: height)
                .overlay { outline }
            }
            if !engines || sorted {
                sortButton(current)
            }
            if !engines { Spacer(minLength: 0) }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        // The same 12 as between two cards.
        .padding(.bottom, 12)
        .animation(.easeOut(duration: 0.15), value: state.floating)
    }

    /// Over the list, an outline keeps it apart from what passes beneath (#80).
    private var outline: some View {
        Capsule().strokeBorder(Color(.separator), lineWidth: 1).opacity(state.floating ? 1 : 0).allowsHitTesting(false)
    }

    /// Glass, in the label colour, with the sort's name.
    private func sortButton(_ current: FeedChoice) -> some View {
        let sorted = current == .sort(controller.sort)
        let name = controller.sort.needsTime ? "\(controller.sort.label) · \(controller.time.label)" : controller.sort.label
        return Menu {
            ForEach(PostSort.allCases, id: \.self) { sort in
                let on = sorted && sort == controller.sort
                if sort.needsTime {
                    Menu {
                        ForEach(TopTime.allCases, id: \.self) { t in
                            Button {
                                if !on || t != controller.time { controller.changeSort(sort, time: t) }
                            } label: {
                                if on && t == controller.time { Label(t.label, systemImage: "checkmark") } else { Text(t.label) }
                            }
                        }
                    } label: {
                        Label(sort.label, systemImage: on ? "checkmark" : sortSymbol(sort))
                    }
                } else {
                    Button {
                        if !on { controller.changeSort(sort) }
                    } label: {
                        Label(sort.label, systemImage: on ? "checkmark" : sortSymbol(sort))
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                Text(name).lineLimit(1).fixedSize()
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .frame(minWidth: height, minHeight: height)
            .glassEffect(.regular.interactive(), in: .capsule)
            .overlay { outline }
        }
        // A menu's label takes the app tint; the sort stays in the label colour.
        .tint(.primary)
        .sensoryFeedback(.selection, trigger: name)
        .accessibilityLabel("Sort")
        .accessibilityValue(sorted ? name : "")
    }
}

/// For You / Blend / Home / Subs: the system segmented control (its own glass and
/// sliding thumb), from UIKit because SwiftUI's only comes 31 or 48 tall and this
/// matches the sort button's 36.
private struct FeedSegments: UIViewRepresentable {
    let labels: [String]
    let selected: Int
    let onPick: (Int) -> Void

    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl(items: labels)
        control.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        // Let SwiftUI's frame set the size, not the control's own 31pt.
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.defaultLow, for: .vertical)
        control.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return control
    }

    func updateUIView(_ control: UISegmentedControl, context: Context) {
        context.coordinator.onPick = onPick
        if (0..<control.numberOfSegments).map({ control.titleForSegment(at: $0) ?? "" }) != labels {
            control.removeAllSegments()
            for (i, label) in labels.enumerated() { control.insertSegment(withTitle: label, at: i, animated: false) }
        }
        if control.selectedSegmentIndex != selected { control.selectedSegmentIndex = selected }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject {
        var onPick: (Int) -> Void
        init(onPick: @escaping (Int) -> Void) { self.onPick = onPick }
        private let feedback = UISelectionFeedbackGenerator()
        @objc func changed(_ control: UISegmentedControl) {
            feedback.selectionChanged()
            onPick(control.selectedSegmentIndex)
        }
    }
}

/// Whether the row of chips is out of its place in the list, i.e. over it.
@MainActor @Observable final class FeedChipsState {
    var floating = false
}

/// Where the row of chips goes (#73, #80, #81). It sits at the top of the list and scrolls
/// away with it. Past that place it stays gone as you scroll down; scrolling up brings it
/// back under the top bar, following the finger, and it leaves again the same way. Back
/// at the top of the list the list's own place takes over, with nothing to swap: it's
/// the same view, at whichever of the two positions is lower. With the setting off it
/// only ever has its place in the list.
struct FloatingChipsTracker {
    var height: CGFloat = 44
    /// How far it's out from under the bar: 0 = fully out, -height = away.
    private(set) var shift: CGFloat = 0
    private var lastOffset: CGFloat?
    private var scrollingUp = false

    /// The list's new position. Rubber-banding at either end doesn't count: it isn't a scroll.
    mutating func scrolled(to offset: CGFloat, min low: CGFloat, max high: CGFloat) {
        let clamped = Swift.min(Swift.max(offset, low), high)
        defer { lastOffset = clamped }
        guard let last = lastOffset, clamped != last else { return }
        let delta = last - clamped // Positive: scrolled up.
        scrollingUp = delta > 0
        shift = Swift.min(Swift.max(shift + delta, -height), 0)
    }

    /// Its position on screen. `rowY`: its place in the list, nil once that's off screen.
    func y(rowY: CGFloat?, top: CGFloat, floats: Bool) -> CGFloat {
        let place = rowY ?? -.greatestFiniteMagnitude
        return floats ? Swift.max(place, top + shift) : place
    }

    /// Fades as it slides under the bar: the bar's glass would show it passing through.
    func alpha(y: CGFloat, top: CGFloat) -> CGFloat {
        y >= top ? 1 : Swift.max(0, (y + height - top) / height)
    }

    /// Stopped half way: finishes the way you were going (a little scroll up brings it
    /// out), and only hides with the list scrolled past its place. Returns if it moved.
    mutating func settle(past: Bool) -> Bool {
        guard shift != 0, shift != -height else { return false }
        shift = past && !scrollingUp ? -height : 0
        return true
    }
}

/// The profile's sort: a round button beside its tabs that opens the list (the menu marks the current one).
struct SortBar: View {
    let sort: PostSort
    let time: TopTime
    let sorts: [PostSort]
    let onPick: (PostSort, TopTime?) -> Void

    var body: some View {
        Menu {
            ForEach(sorts, id: \.self) { s in
                if s.needsTime {
                    Menu {
                        ForEach(TopTime.allCases, id: \.self) { t in
                            Button { onPick(s, t) } label: {
                                if s == sort && t == time { Label(t.label, systemImage: "checkmark") } else { Text(t.label) }
                            }
                        }
                    } label: {
                        Label(s.label, systemImage: sortSymbol(s))
                    }
                } else {
                    Button { onPick(s, nil) } label: {
                        Label(s.label, systemImage: s == sort ? "checkmark" : sortSymbol(s))
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down").frame(width: 20, height: 20)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel("Sort: \(sort.needsTime ? "\(sort.label) · \(time.label)" : sort.label)")
    }
}

private func sortSymbol(_ s: PostSort) -> String {
    switch s {
    case .best: "star"
    case .hot: "flame"
    case .newest: "clock"
    case .top: "chart.bar"
    case .rising: "chart.line.uptrend.xyaxis"
    }
}

/// "Saved Home from 2h ago · Refresh" / "Home couldn't load · showing For You · Retry".
struct HomeStatusStrip: View {
    let status: HomeStatus
    let onRetry: () -> Void

    var body: some View {
        if let (symbol, text) = content {
            let signIn = status == .fellBack(signedOut: true)
            HStack(spacing: 10) {
                Image(systemName: symbol).foregroundStyle(.secondary)
                Text(text).font(.footnote).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                Button(signIn ? "Sign in" : isSaved ? "Refresh" : "Retry") {
                    if signIn { app.navigator.push(.webLogin()) } else { onRetry() }
                }
                .font(.footnote.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 12))
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private var isSaved: Bool {
        if case .saved = status { true } else { false }
    }

    private var content: (String, String)? {
        switch status {
        case let .saved(at): ("clock.arrow.circlepath", "Saved Home, from \(timeAgoPhrase(at))")
        case let .fellBack(signedOut): ("icloud.slash", signedOut ? "Website sign-in expired · showing For You" : "Home couldn't load · showing For You")
        case .live: nil
        }
    }
}

/// The list's end: a spinner while a page loads, "— end —", and how many posts filters hid.
@MainActor @Observable final class FeedFooterModel {
    var loadingMore = false
    var hasMore = false
    var hidden = 0
}

struct FeedFooter: View {
    let model: FeedFooterModel

    var body: some View {
        VStack(spacing: 8) {
            if model.loadingMore {
                ProgressView()
            } else if !model.hasMore {
                Text("— end —").foregroundStyle(.secondary)
            }
            if model.hidden > 0 {
                Text("\(model.hidden) \(model.hidden == 1 ? "post" : "posts") hidden")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.vertical, 20)
    }
}
