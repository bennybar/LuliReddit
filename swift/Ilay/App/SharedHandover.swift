import UIKit

/// What the app and its share and Safari extensions hand each other through `SharedStore`.
enum SharedHandover {
    /// The share extension can't read the app's settings: copy the ones its summary
    /// uses to the shared keychain, now and whenever Ilay leaves the screen.
    static func start() {
        shareAiSettings()
        shareSafariAsk()
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            shareAiSettings()
        }
    }

    /// Settings → "Safari extension: ask which app", for the Safari extension.
    static func shareSafariAsk() {
        let on = UserDefaults.standard.bool(forKey: Prefs.prefix + "safariAsk")
        SharedStore.write(SharedStore.safariAsk, Data((on ? "1" : "0").utf8))
    }

    private static func shareAiSettings() {
        var settings: [String: Any] = [:]
        for key in ["aiModel", "aiSummaryStyle", "aiMaxChars", "aiUseCustomUrl", "aiBaseUrl", "aiSummaryLanguage", "defaultCommentSort"] {
            settings[key] = UserDefaults.standard.object(forKey: Prefs.prefix + key)
        }
        SharedStore.write(SharedStore.aiSettings, try? JSONSerialization.data(withJSONObject: settings))
    }

    /// Summaries made over another app wait in the shared keychain until Ilay runs: into
    /// You → Summaries, once the account's store is loaded. Handed over once.
    @MainActor static func importSummaries() {
        guard let data = SharedStore.read(SharedStore.pendingSummaries) else { return }
        SharedStore.write(SharedStore.pendingSummaries, nil)
        // Oldest first, so the newest ends up on top.
        for summary in parsePendingSummaries(data) { app.summaries.add(summary) }
    }
}

/// The JSON list the extension left: same fields as `SavedSummary`.
func parsePendingSummaries(_ data: Data) -> [SavedSummary] {
    ((try? AppJson.parse(data)).arr() ?? []).compactMap { m in
        guard m.obj() != nil else { return nil }
        return SavedSummary(
            postId: m["postId"].str() ?? "",
            subreddit: m["subreddit"].str() ?? "",
            title: m["title"].str() ?? "",
            permalink: m["permalink"].str() ?? "",
            style: m["style"].str() ?? "",
            model: m["model"].str() ?? "",
            text: m["text"].str() ?? "",
            createdAt: m["createdAt"].long() ?? 0
        )
    }
}
