import SwiftUI

extension EnvironmentValues {
    /// Opens the side bar (Settings › Navigation: side bar / both); nil when it's off.
    @Entry var sideBar: (() -> Void)? = nil
}

/// The ☰ at the start of a tab's toolbar, when the side bar is on. Every tab puts
/// it in `.topBarLeading`, so it doesn't shift as you switch tabs (#34).
struct SideBarButton: View {
    @Environment(\.sideBar) private var open

    var body: some View {
        if let open {
            Button("Open menu", systemImage: "line.3.horizontal", action: open)
        }
    }
}

/// The ⚙ at the top of a tab's main screen: straight to Settings. Left out when
/// the side bar is on, which always has Settings (#138, #145).
struct SettingsButton: View {
    @Environment(AppNavigator.self) private var nav
    @Environment(\.sideBar) private var sideBar

    var body: some View {
        if sideBar == nil {
            Button("Settings", systemImage: "gearshape") { nav.push(.settings) }
        }
    }
}
