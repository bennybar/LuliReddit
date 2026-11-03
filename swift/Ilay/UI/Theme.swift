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

    /// The font size setting (a multiplier, 0.8–1.4), as the Dynamic Type step
    /// nearest it. At 100% the system's own text size applies.
    static func typeSize(_ scale: Double) -> DynamicTypeSize? {
        switch scale {
        case ..<0.85: .xSmall
        case ..<0.95: .small
        case ..<1.05: nil
        case ..<1.15: .xLarge
        case ..<1.25: .xxLarge
        default: .xxxLarge
        }
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

    func body(content: Content) -> some View {
        let settings = app.settings.value
        let scheme: ColorScheme? = switch settings.themeMode {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
        // A range rather than a branch: a branch would rebuild the whole app when the setting changes.
        content
            .dynamicTypeSize(IlayTheme.typeSize(settings.textScale).map { $0...$0 } ?? (.xSmall ... .accessibility5))
            .tint(IlayTheme.accent)
            .environment(\.voteColors, IlayTheme.voteColors(dark: (scheme ?? systemScheme) == .dark))
            .preferredColorScheme(scheme)
    }
}

extension View {
    /// Applied once, at the root.
    func ilayTheme() -> some View { modifier(ThemeModifier()) }
}
