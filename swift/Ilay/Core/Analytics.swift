import Foundation
import UIKit

/// Privacy-friendly, anonymous usage analytics via Aptabase (the same app key
/// and event shape as the Flutter SDK). No ad IDs, no personal data — just
/// anonymous sessions plus OS/app version and the few events we track.
/// Disabled (a no-op) when [appKey] is empty or the user turned it off
/// (Settings → About → Send anonymous usage stats).
///
/// Counts are sent in coarse buckets ("2-5"), never exact, and nothing names
/// the user, a subreddit or a post.
@MainActor
enum Analytics {
    private static let appKey = "A-US-2578531885"
    private static let sdkVersion = "aptabase_swift@ilay"
    /// The server for a self-hosted Aptabase ("A-SH-…" key), e.g. "https://stats.example.com".
    private static let selfHost = ""
    private static let sessionTimeoutMs = 60 * 60 * 1000

    private static var sessionId = newSessionId()
    private static var lastTouch = nowMillis()

    static var enabled: Bool { !appKey.isEmpty }

    private static var apiUrl: URL? {
        let parts = appKey.components(separatedBy: "-")
        guard parts.count > 1 else { return nil }
        switch parts[1] {
        case "EU": return URL(string: "https://eu.aptabase.com/api/v0/events")
        case "US": return URL(string: "https://us.aptabase.com/api/v0/events")
        case "SH": return selfHost.trimmingEnd("/").nilIfEmpty.flatMap { URL(string: "\($0)/api/v0/events") }
        default: return nil
        }
    }

    private static func newSessionId() -> String {
        "\(nowMillis() / 1000)\(Int.random(in: 10_000_000..<99_999_999))"
    }

    private static func evalSessionId() -> String {
        let now = nowMillis()
        if now - lastTouch > sessionTimeoutMs { sessionId = newSessionId() }
        lastTouch = now
        return sessionId
    }

    /// Records an anonymous event (no-op when disabled).
    static func track(_ event: String, _ props: JsonObject = [:]) {
        guard let url = apiUrl, enabled, !isRunningTests, app.settings.value.analytics else { return }
        #if DEBUG
        let isDebug = true
        #else
        let isDebug = false
        #endif
        let body: JsonElement = [[
            "timestamp": .string(Date.now.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))),
            "sessionId": .string(evalSessionId()),
            "eventName": .string(event),
            "systemProps": [
                "isDebug": .bool(isDebug),
                "osName": "iOS",
                "osVersion": .string(UIDevice.current.systemVersion),
                "locale": .string(Locale.current.identifier(.bcp47)),
                "appVersion": .string(RedditConstants.appVersion),
                "appBuildNumber": .string(RedditConstants.appBuild),
                "sdkVersion": .string(sdkVersion),
            ],
            "props": .object(props),
        ]]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(appKey, forHTTPHeaderField: "App-Key")
        req.setValue(sdkVersion, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(body.encoded().utf8)
        Task.detached { _ = try? await Http.session.send(req) }
    }

    // Posts opened since the app last went to the background: sent as one
    // event per visit instead of one per post, to keep the event count low.
    private static var postsOpened = 0

    static func postOpened() { postsOpened += 1 }

    /// The app went to the background: sends this visit's posts-opened count.
    static func flushPostsOpened() {
        let n = postsOpened
        postsOpened = 0
        if n > 0 { track("posts_opened", ["count": .string(bucket(n, 1, 5, 20))]) }
    }

    /// [n] as a coarse range, e.g. bucket(3, 1, 5, 20) = "2-5"; [edges] ascending.
    nonisolated static func bucket(_ n: Int, _ edges: Int...) -> String {
        var low = 0
        for e in edges {
            if n <= e { return low + 1 >= e ? "\(e)" : "\(low + 1)-\(e)" }
            low = e
        }
        return "\(low + 1)+"
    }
}
