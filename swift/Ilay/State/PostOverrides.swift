import Foundation
import Observation

/// The current, user-visible state of a post that can change after it's
/// fetched (vote, score, saved, comment count). Shared, keyed by post id, so a
/// feed card and the post-detail screen stay in sync without a refresh.
struct PostOverride: Equatable, Sendable, Copyable {
    var likes: Bool? // true=up, false=down, nil=no vote
    var score: Int
    var numComments: Int
    var saved: Bool
}

@MainActor @Observable
final class PostOverrides: UserScoped {
    nonisolated static func dirOf(_ likes: Bool?) -> Int { likes == true ? 1 : likes == false ? -1 : 0 }

    private(set) var state: [String: PostOverride] = [:]

    // When the user last voted/saved each post. A fresh server copy wins
    // otherwise, so scores don't freeze at whatever was first seen.
    @ObservationIgnored private var localAt: [String: Int] = [:]
    @ObservationIgnored private let votes = LocalVotes()

    init() {}

    /// Effective state for [p] (an override if one exists, else the post's own).
    func effective(_ p: Post) -> PostOverride {
        state[p.id] ?? PostOverride(likes: p.likes, score: p.score, numComments: p.numComments, saved: p.saved)
    }

    // An identical value notifies no one: every card on screen reads this map.
    private func set(_ id: String, _ o: PostOverride) {
        if state[id] != o { state[id] = o }
    }

    /// Applies a vote (−1, 0, +1). Does nothing if it's already the current vote.
    func setVote(_ p: Post, targetDir: Int) {
        let cur = effective(p)
        let curDir = PostOverrides.dirOf(cur.likes)
        if targetDir == curDir { return }
        localAt[p.id] = nowMillis()
        votes.record(p.id, dir: targetDir, serverScore: p.score, serverLikes: p.likes)
        set(p.id, cur.with {
            $0.score = cur.score + (targetDir - curDir)
            $0.likes = LocalVotes.likesOf(targetDir)
        })
    }

    func setSaved(_ p: Post, saved: Bool) {
        localAt[p.id] = nowMillis()
        set(p.id, effective(p).with { $0.saved = saved })
    }

    func bumpComments(_ p: Post, delta: Int) {
        let e = effective(p)
        set(p.id, e.with { $0.numComments = e.numComments + delta })
    }

    /// Refresh from a freshly-fetched post. The server copy wins, except a
    /// vote Reddit's copy doesn't show yet ([LocalVotes]) and saved changed
    /// in the last couple of minutes (a request may still be in flight).
    func syncFromServer(_ p: Post) {
        let existing = state[p.id]
        let recentLocal = existing != nil && localAt[p.id].map { nowMillis() - $0 < 2 * 60_000 } == true
        let (likes, score) = votes.reconcile(p.id, serverLikes: p.likes, serverScore: p.score)
        set(p.id, PostOverride(likes: likes, score: score, numComments: p.numComments, saved: recentLocal ? existing!.saved : p.saved))
    }

    func onUserChanged(_ username: String) {
        localAt.removeAll()
        votes.clear()
        state = [:]
    }
}
