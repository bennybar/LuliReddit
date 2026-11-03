import SwiftUI

private let easeInOutCubic = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.645, y: 0.045), endControlPoint: UnitPoint(x: 0.355, y: 1))

/// Out to `peak` over the first 40%, back to `end` by 80%, then settle at 0.
private func lerpPath(_ t: Double, _ start: Double, _ peak: Double, _ end: Double) -> Double {
    if t < 0.4 { return start + (peak - start) * easeInOutCubic.value(at: t / 0.4) }
    if t < 0.8 { return peak + (end - peak) * easeInOutCubic.value(at: (t - 0.4) / 0.4) }
    return end * (1 - (t - 0.8) / 0.2)
}

/// Home's and For You's loading state: a small deck of post cards shuffling
/// while a live counter shows how many posts have been found. The feed then
/// deals the first cards in.
struct HomeLoadingDeck: View {
    let forYou: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let found = forYou ? app.forYou.engine.progress : app.forYou.redditHome.progress
        VStack(spacing: 18) {
            // Respect Reduce Motion: a still deck, the counter still counts.
            TimelineView(.animation(paused: reduceMotion)) { context in
                let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                // The top card is flicked out to the right, then slides back
                // in *behind* the others: it switches sides at 41%.
                ZStack {
                    let top = DeckCard(accent: true)
                        .rotationEffect(.degrees(lerpPath(t, 0, 16, -2)))
                        .offset(x: lerpPath(t, 0, 110, 0), y: lerpPath(t, 0, -14, 0))
                    if t >= 0.41 { top }
                    DeckCard(accent: false).rotationEffect(.degrees(-8)).offset(x: -8)
                    DeckCard(accent: false).rotationEffect(.degrees(5)).offset(x: 6)
                    if t < 0.41 { top }
                }
                .frame(width: 230, height: 170)
            }
            .accessibilityHidden(true)

            Group {
                if found == 0 {
                    Text(forYou ? "Personalizing your feed…" : "Opening your Home…")
                } else {
                    let count = Text("\(found)").fontWeight(.heavy).foregroundStyle(.tint)
                    Text("Found \(count) \(found == 1 ? "post" : "posts") \(forYou ? "for you" : "in your Home")")
                }
            }
            .font(.footnote.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .contentTransition(.numericText(value: Double(found)))
            .animation(reduceMotion ? nil : .snappy, value: found)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DeckCard: View {
    let accent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Capsule().fill(.quaternary).frame(width: 60, height: 7)
            Capsule().fill(.quaternary).frame(width: 128, height: 7)
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(accent ? AnyShapeStyle(.tint.opacity(0.3)) : AnyShapeStyle(.quaternary))
                .padding(.top, 2)
        }
        .padding(10)
        .frame(width: 150, height: 120)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}
