import SwiftUI

/// Whether a `CollapsingFab` shows its label: it folds as the finger scrolls down and opens on the way up (#62).
@MainActor @Observable final class FabScroll {
    private(set) var expanded = true

    /// `available`: how far the content moved down this step (negative: scrolled down).
    /// Only a finger counts, not a fling.
    func onScroll(available: CGFloat, userInput: Bool) {
        guard userInput else { return }
        if available < -1 {
            if expanded { expanded = false }
        } else if available > 1 {
            if !expanded { expanded = true }
        }
    }
}

/// A floating button with a label, or just its icon once scrolled, like Mail's compose.
struct CollapsingFab: View {
    let systemImage: String
    let label: String
    let expanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                if expanded {
                    Text(label).lineLimit(1).fixedSize().transition(.opacity)
                }
            }
            .font(.subheadline.weight(.semibold))
            .frame(minWidth: 26, minHeight: 30)
            .padding(.horizontal, expanded ? 2 : 0)
        }
        .buttonStyle(.glassProminent)
        .accessibilityLabel(label)
        .animation(.smooth(duration: 0.25), value: expanded)
    }
}
