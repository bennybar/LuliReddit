import SwiftUI

/// Turns raw errors into friendly, human copy.
@MainActor func friendlyError(_ e: Any?) -> String {
    if let e = e as? RedditApiException {
        switch e.reason {
        case "private": return "This community is private."
        case "banned": return "This community has been banned by Reddit."
        case "quarantined": return "This community is quarantined: it may have shocking or highly offensive content."
        case "gated": return "This community may have sensitive content, such as mature themes or graphic images."
        case "gold_only": return "This community is for premium members only."
        default: break
        }
        switch e.statusCode {
        case 403: return "You don't have permission to do that."
        case 404: return "Not found — it may have been removed."
        case 429: return rateLimited()
        case 500..<600: return "Reddit is having problems right now. Try again later."
        default: break
        }
    }
    if e is URLError { return "You appear to be offline. Check your connection and try again." }
    var s = (e as? Error).map { $0.localizedDescription } ?? e.map { "\($0)" } ?? ""
    if s.hasPrefix("Exception: ") { s.removeFirst("Exception: ".count) }
    let lower = s.lowercased()
    if lower.contains("socket") || lower.contains("connection") || lower.contains("unable to resolve host") {
        return "You appear to be offline. Check your connection and try again."
    }
    if lower.contains("403") { return "You don't have permission to do that." }
    if lower.contains("404") { return "Not found — it may have been removed." }
    if lower.contains("429") { return rateLimited() }
    if lower.contains("500") || lower.contains("502") || lower.contains("503") {
        return "Reddit is having problems right now. Try again later."
    }
    return s
}

/// Rate-limited: when Reddit said the window resets, say how long to wait.
@MainActor private func rateLimited() -> String {
    let left = app.rateLimit?.secondsLeft() ?? 0
    if left <= 0 { return "You're going a bit fast — Reddit is rate-limiting. Try again shortly." }
    if left < 60 { return "Reddit is rate-limiting for a moment. Try again in \(left)s." }
    return "Reddit is rate-limiting. Try again in about \((left + 59) / 60) min."
}

/// Consistent empty / error state with an optional retry. `message` is shown as
/// is when it's a String; anything else goes through `friendlyError`.
struct ErrorView: View {
    let message: Any?
    var onRetry: (() -> Void)? = nil
    var systemImage = "icloud.slash"
    var retryLabel = "Retry"

    var body: some View {
        ContentUnavailableView {
            Image(systemName: systemImage)
        } description: {
            Text(message as? String ?? friendlyError(message))
        } actions: {
            if let onRetry {
                Button(retryLabel, action: onRetry).buttonStyle(.glass)
            }
        }
    }
}

/// The screen for a destination that isn't ported yet (see `RouteView`).
struct PlaceholderScreen: View {
    let title: String

    var body: some View {
        ContentUnavailableView(title, systemImage: "hammer", description: Text("Not ported yet."))
            .navigationTitle(title)
    }
}
