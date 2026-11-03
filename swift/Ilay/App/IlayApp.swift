import SwiftUI

@main
struct IlayApp: App {
    init() {
        // Hosted unit tests start the app too: they must not read the real login.
        guard !isRunningTests else { return }
        app.start()
        app.session.reload()
        app.inbox.onAppStart()
        SharedHandover.start()
    }

    var body: some Scene {
        WindowGroup {
            if !isRunningTests {
                AppRoot()
            }
        }
    }
}
