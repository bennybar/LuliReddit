import SwiftUI

/// Whether a `CollapsingFab` shows its label: it folds as the finger scrolls down and opens on
/// the way up (#62), once the finger has gone 48pt that way, not on the first nudge (#177).
@MainActor @Observable final class FabScroll {
    private(set) var expanded = true
    /// A finger is scrolling the list, or its fling still is (set by the thread's list, #210).
    var userScrolling = false
    /// How far the finger has scrolled since it last turned around (negative: down).
    @ObservationIgnored private var travel: CGFloat = 0

    /// `available`: how far the content moved down this step (negative: scrolled down).
    /// Only a finger counts, not a fling.
    func onScroll(available: CGFloat, userInput: Bool) {
        guard userInput, available != 0 else { return }
        if (available < 0) != (travel < 0) { travel = 0 }
        travel += available
        if travel < -48 {
            if expanded { expanded = false }
        } else if travel > 48 {
            if !expanded { expanded = true }
        }
    }
}

/// A floating button with a label, or just its icon once scrolled, like Mail's compose.
/// `hideOnScroll`: instead of folding, it's gone while scrolling down (#301).
struct CollapsingFab: View {
    let systemImage: String
    let label: String
    let expanded: Bool
    var hideOnScroll = false
    let action: () -> Void

    var body: some View {
        let hidden = hideOnScroll && !expanded
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                if expanded || hideOnScroll {
                    Text(label).lineLimit(1).fixedSize().transition(.opacity)
                }
            }
            .font(.subheadline.weight(.semibold))
            .frame(minWidth: 26, minHeight: 30)
            .padding(.horizontal, expanded || hideOnScroll ? 2 : 0)
        }
        .buttonStyle(.glassProminent)
        .accessibilityLabel(label)
        .scaleEffect(hidden ? 0.4 : 1)
        .opacity(hidden ? 0 : 1)
        .allowsHitTesting(!hidden)
        .accessibilityHidden(hidden)
        // Opens with a little bounce, folds without one (#177).
        .animation(expanded ? .bouncy(duration: 0.4, extraBounce: 0.05) : .smooth(duration: 0.3), value: expanded)
    }
}
