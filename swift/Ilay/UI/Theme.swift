import SwiftUI

/// Upvote / downvote accent colors, brightness-correct.
struct VoteColors {
    let up: Color
    let down: Color
}

extension EnvironmentValues {
    @Entry var voteColors = IlayTheme.voteColors(dark: false)
}

/// The app's look: the accent setting drives `.tint`, the light / dark setting the
/// colour scheme, the font size setting the text size. Everything else is the
/// system's semantic colours.
enum IlayTheme {
    static func voteColors(dark: Bool) -> VoteColors {
        dark
            ? VoteColors(up: Color(argb: 0xFFFF7E54), down: Color(argb: 0xFFBFC0FF))
            : VoteColors(up: Color(argb: 0xFFD93900), down: Color(argb: 0xFF605BFF))
    }

    /// The accent setting's colour. In dark mode a dark seed is lifted so it stays readable on black.
    @MainActor static var accent: Color {
        let seed = Color(argb: app.settings.value.seedColor)
        let light = UIColor(seed)
        return Color(uiColor: UIColor { traits in
            guard traits.userInterfaceStyle == .dark else { return light }
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            light.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            return UIColor(hue: h, saturation: s, brightness: max(b, 0.9), alpha: a)
        })
    }

    /// The font size setting (a multiplier, 0.8–1.4) as Dynamic Type steps away from
    /// the system's own text size, which it used to replace: someone on an accessibility
    /// size who picked 110% got smaller text, not larger. At the default size the steps
    /// land where they always did (90% small … 130% xxxLarge). At 100% the system's size applies.
    static func typeRange(_ scale: Double, system: DynamicTypeSize? = nil) -> ClosedRange<DynamicTypeSize> {
        let steps = switch scale {
        case ..<0.85: -3
        case ..<0.95: -2
        case ..<1.05: 0
        case ..<1.15: 1
        case ..<1.25: 2
        default: 3
        }
        if steps == 0 { return .xSmall ... .accessibility5 }
        let base = system ?? DynamicTypeSize(UIApplication.shared.preferredContentSizeCategory) ?? .large
        let all = DynamicTypeSize.allCases
        let i = min(max((all.firstIndex(of: base) ?? 3) + steps, 0), all.count - 1)
        return all[i] ... all[i]
    }
}

extension Color {
    init(argb: Int) {
        self.init(
            .sRGB,
            red: Double((argb >> 16) & 0xFF) / 255,
            green: Double((argb >> 8) & 0xFF) / 255,
            blue: Double(argb & 0xFF) / 255,
            opacity: Double((argb >> 24) & 0xFF) / 255
        )
    }
}

private struct ThemeModifier: ViewModifier {
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.dynamicTypeSize) private var systemTypeSize // outside the range set below

    func body(content: Content) -> some View {
        let settings = app.settings.value
        let scheme: ColorScheme? = switch settings.themeMode {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
        // A range rather than a branch: a branch would rebuild the whole app when the setting changes.
        content
            .dynamicTypeSize(IlayTheme.typeRange(settings.textScale, system: systemTypeSize))
            .tint(IlayTheme.accent)
            .environment(\.voteColors, IlayTheme.voteColors(dark: (scheme ?? systemScheme) == .dark))
            .preferredColorScheme(scheme)
    }
}

extension View {
    /// Applied once, at the root.
    func ilayTheme() -> some View { modifier(ThemeModifier()) }
}
