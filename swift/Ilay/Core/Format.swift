import Foundation

/// Compact formatting helpers for scores, counts and relative time.
func compactNumber(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000.0) }
    if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000.0) }
    return String(n)
}

/// "5m ago", "3h ago"… or "just now", for running text.
func timeAgoPhrase(_ epochMillis: Int) -> String {
    let t = timeAgo(epochMillis)
    return t == "now" ? "just now" : "\(t) ago"
}

/// "5m", "3h", "2d", "4mo", "1y" or "now" since [epochMillis] (UTC).
func timeAgo(_ epochMillis: Int) -> String {
    let diff = nowMillis() - epochMillis
    let minutes = diff / 60_000
    let hours = minutes / 60
    let days = hours / 24
    if days >= 365 { return "\(days / 365)y" }
    if days >= 30 { return "\(days / 30)mo" }
    if days >= 1 { return "\(days)d" }
    if hours >= 1 { return "\(hours)h" }
    if minutes >= 1 { return "\(minutes)m" }
    return "now"
}

/// Where a crosspost came from, for "Crossposted from …": a profile's own subreddit
/// ("u_name") reads as the user.
func crosspostSource(_ subreddit: String) -> String {
    subreddit.hasPrefix("u_") ? "u/" + subreddit.dropFirst(2) : "r/" + subreddit
}
