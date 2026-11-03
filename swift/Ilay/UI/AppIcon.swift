import SwiftUI

/// The home-screen icon's colour (Settings → App icon). Each non-default option
/// is an alternate icon in the asset catalog (`AppIcon-<key>`, listed in project.yml).
enum AppIcon: String, CaseIterable, Identifiable {
    case violet, ocean, forest, sunset, midnight
    /// The mark in colour on white, like Google's own app icons.
    case white

    var id: String { rawValue }
    var key: String { rawValue }
    var label: String { rawValue.capitalized }

    static func parse(_ key: String?) -> AppIcon { key.flatMap(AppIcon.init(rawValue:)) ?? .violet }

    /// Switches the home-screen icon (iOS shows its own confirmation).
    @MainActor static func apply(_ icon: AppIcon) {
        UIApplication.shared.setAlternateIconName(icon == .violet ? nil : "AppIcon-\(icon.key)")
    }
}

/// `icon` as a rounded square, for the picker and the login screen.
struct AppIconPreview: View {
    let icon: AppIcon
    var size: CGFloat = 24

    var body: some View {
        // The compiled app icons can't be loaded as images, hence a copy of each.
        Image("AppIconPreview-\(icon.key)")
            .resizable()
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: size * 0.28, style: .continuous))
    }
}
