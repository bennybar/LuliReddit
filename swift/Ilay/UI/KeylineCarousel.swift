import SwiftUI

/// A Material 3 Expressive carousel, kept on iOS on purpose: items sit on
/// "keylines" (large → medium → small) and change width as they move between
/// them, the content masked to the item so a narrow one shows its middle.
struct KeylineCarousel<Item, Content: View>: View {
    let items: [Item]
    var height: CGFloat
    /// Item widths from the leading edge (e.g. large, medium, small).
    var keylines: (CGFloat) -> [CGFloat]
    var spacing: CGFloat = 8
    var cornerRadius: CGFloat = 28
    var inset: CGFloat = 0
    var onTap: (Item) -> Void = { _ in }
    /// VoiceOver name of an item.
    var label: (Item) -> String = { _ in "" }
    @ViewBuilder var content: (Item) -> Content

    /// Scroll position in points, from a real (invisible) horizontal ScrollView:
    /// it gives native swiping, momentum and snapping. A custom drag gesture lost
    /// the touch to the items' tap handling on a real device.
    @State private var scrollX: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width - inset * 2
            let k = keylines(width)
            let stride = (k.first ?? 100) + spacing
            let maxOffset = CGFloat(max(items.count - 1, 0))
            let current = min(max(scrollX / stride, -0.35), maxOffset + 0.35)
            ZStack(alignment: .topLeading) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    let f = keylineFrame(index: i, current: current, count: items.count, keylines: k, spacing: spacing, width: width)
                    if f.width > 1 && f.x < width + 40 && f.x + f.width > -40 {
                        Color.clear
                            .frame(width: f.width, height: height)
                            // Always laid out at the large size, so narrowing masks the
                            // image rather than resizing (and re-decoding) it.
                            .overlay { content(item).frame(width: k.first ?? f.width, height: height) }
                            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
                            .offset(x: f.x)
                    }
                }
            }
            .frame(width: width, height: height, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .padding(.horizontal, inset)
            .overlay {
                // The touch surface: one invisible page per keyline step, snapping.
                ScrollView(.horizontal, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        HStack(spacing: 0) {
                            ForEach(0...Int(maxOffset), id: \.self) { _ in
                                Color.clear.frame(width: stride, height: height)
                            }
                            Color.clear.frame(width: max(geo.size.width - stride, 0), height: height)
                        }
                        .scrollTargetLayout()
                        // One touch target per visible item, over where it's drawn (it
                        // scrolls with the content, so the drawn x plus the scroll).
                        // Inside the ScrollView, so swiping still scrolls.
                        ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                            let f = keylineFrame(index: i, current: current, count: items.count, keylines: k, spacing: spacing, width: width)
                            if f.width > 1 && f.x < width + 40 && f.x + f.width > -40 {
                                Color.clear
                                    .frame(width: f.width, height: height)
                                    .contentShape(.interaction, Rectangle())
                                    .onTapGesture { onTap(item) }
                                    .accessibilityElement()
                                    .accessibilityLabel(label(item))
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityAction { onTap(item) }
                                    .offset(x: inset + f.x + scrollX)
                            }
                        }
                    }
                }
                .scrollTargetBehavior(.viewAligned)
                .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.x }) { _, x in scrollX = x }
            }
        }
        .frame(height: height)
    }
}

/// Where item `index` sits with the carousel scrolled to `current` (in items). Through
/// the list, items run large → medium → small from the left. Over the last steps the
/// keylines flip, as in Material's carousel: small, large, medium; then small, medium,
/// large against the right edge. Every item gets its turn at full size.
func keylineFrame(
    index: Int, current: CGFloat, count: Int, keylines k: [CGFloat], spacing: CGFloat, width: CGFloat
) -> (x: CGFloat, width: CGFloat) {
    guard !k.isEmpty else { return (0, 0) }
    func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    /// Position (in keyline units, 0 = first keyline) → x and width.
    func start(_ p: CGFloat) -> (x: CGFloat, width: CGFloat) {
        var xs: [CGFloat] = []
        var x: CGFloat = 0
        for w in k { xs.append(x); x += w + spacing }
        if p < 0 {
            // Leaving on the left: shrink toward the smallest size, sliding out. Its
            // right edge stays one gap left of the item entering keyline 0.
            let t = min(-p, 1)
            return (-t * (k.last! + spacing), lerp(k[0], k.last!, t))
        }
        let i = Int(p.rounded(.down))
        if i >= k.count - 1 {
            let extra = p - CGFloat(k.count - 1)
            return (xs[k.count - 1] + extra * (k.last! + spacing), k.last!)
        }
        let t = p - CGFloat(i)
        return (lerp(xs[i], xs[i + 1], t), lerp(k[i], k[i + 1], t))
    }

    /// The layout with item `first + step` large. At the first step it hangs from the left
    /// edge as usual; after that from the right, the items before it taking what's left.
    func stop(_ step: Int, first: Int) -> (x: CGFloat, width: CGFloat) {
        let focus = first + step
        let after = count - 1 - focus
        // Further back than the keylines reach: just off the left edge, smallest.
        let distance = min(focus - index, k.count - after)
        func itemWidth(_ i: Int) -> CGFloat {
            k[min(i >= focus ? i - focus : after + (focus - i), k.count - 1)]
        }
        func sum(_ range: Range<Int>) -> CGFloat {
            range.reduce(0) { $0 + itemWidth($1) + spacing }
        }
        let focusX = step == 0 ? 0 : width - sum(focus..<count) + spacing
        if index >= focus { return (focusX + sum(focus..<index), itemWidth(index)) }
        return (focusX - sum((focus - distance)..<focus), itemWidth(index))
    }

    let first = max(count - k.count, 0)
    let stops = count - 1 - first
    let progress = current - CGFloat(first)
    guard progress > 0, stops > 0 else { return start(CGFloat(index) - current) }
    let step = min(Int(progress), stops - 1)
    let t = min(progress - CGFloat(step), 1)
    let a = stop(step, first: first)
    let b = stop(step + 1, first: first)
    return (lerp(a.x, b.x, t), lerp(a.width, b.width, t))
}
