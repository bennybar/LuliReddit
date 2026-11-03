import Foundation

/// Snapshot of Reddit's API rate-limit headers (per OAuth client), taken [at] (millis).
struct RateLimit: Equatable, Sendable {
    let remaining: Int
    let used: Int
    let resetSeconds: Int
    var at: Int = nowMillis()

    var total: Int { remaining + used }

    /// Seconds until this window resets, counted from when it was read.
    func secondsLeft(now: Int = nowMillis()) -> Int { max(resetSeconds - (now - at) / 1000, 0) }
}
