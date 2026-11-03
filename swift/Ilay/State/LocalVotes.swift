import Foundation
import Observation

/// Your recent votes, kept until Reddit's copy shows them. Reddit's copies
/// lag: a fetch soon after voting can still carry the old vote, or the new
/// vote with the score from before it. Trusting it blindly made a vote look
/// un-counted when you went back into a thread.
final class LocalVotes: @unchecked Sendable {
    private struct Pending {
        let dir: Int
        let baseScore: Int
        let baseDir: Int
        let at: Int
    }

    private static let window = 15 * 60_000

    private let lock = NSLock()
    private var pending: [String: Pending] = [:]
    // The last server (score, dir) seen per id: the baseline for the next vote.
    private var seen: [String: (score: Int, dir: Int)] = [:]

    static func likesOf(_ dir: Int) -> Bool? { dir == 1 ? true : dir == -1 ? false : nil }

    /// You voted [dir] on [id]; [serverScore]/[serverLikes] are the copy you voted on.
    func record(_ id: String, dir: Int, serverScore: Int, serverLikes: Bool?) {
        lock.withLock {
            let prev = pending[id]
            let base = seen[id] ?? (serverScore, PostOverrides.dirOf(serverLikes))
            pending[id] = Pending(dir: dir, baseScore: prev?.baseScore ?? base.score, baseDir: prev?.baseDir ?? base.dir, at: nowMillis())
        }
    }

    /// The vote and score to show for a fresh server copy of [id].
    func reconcile(_ id: String, serverLikes: Bool?, serverScore: Int) -> (likes: Bool?, score: Int) {
        lock.withLock {
            let sDir = PostOverrides.dirOf(serverLikes)
            guard let p = pending[id], nowMillis() - p.at <= LocalVotes.window else {
                pending.removeValue(forKey: id)
                seen[id] = (serverScore, sDir)
                return (serverLikes, serverScore)
            }
            let likes = LocalVotes.likesOf(p.dir)
            // Reddit doesn't have the vote yet: its score is from the old one.
            if sDir != p.dir { return (likes, serverScore + (p.dir - sDir)) }
            // The vote is in but the score hasn't moved since you voted.
            if serverScore == p.baseScore { return (likes, serverScore + (p.dir - p.baseDir)) }
            // Reddit has caught up.
            pending.removeValue(forKey: id)
            seen[id] = (serverScore, sDir)
            return (serverLikes, serverScore)
        }
    }

    func isPending(_ id: String) -> Bool { lock.withLock { pending[id] != nil } }

    func clear() {
        lock.withLock {
            pending.removeAll()
            seen.removeAll()
        }
    }
}

/// Your comment votes, keyed by comment id, so a thread you go back into and
/// your profile's comments show them (a thread used to keep them only while open).
@MainActor @Observable
final class CommentVotes: UserScoped {
    struct Vote: Equatable, Sendable {
        let likes: Bool?
        let score: Int
    }

    @ObservationIgnored private let votes = LocalVotes()
    private(set) var state: [String: Vote] = [:]

    init() {}

    func effective(_ c: Comment) -> Vote { state[c.id] ?? Vote(likes: c.likes, score: c.score) }

    /// Applies a vote (−1, 0, +1) on [c] as shown.
    func setVote(_ c: Comment, target: Int) {
        let cur = effective(c)
        votes.record(c.id, dir: target, serverScore: c.score, serverLikes: c.likes)
        state[c.id] = Vote(likes: LocalVotes.likesOf(target), score: cur.score + target - PostOverrides.dirOf(cur.likes))
    }

    /// Fresh comments from Reddit, with the votes it hasn't caught up with yet.
    func apply(_ comments: [Comment]) -> [Comment] {
        state.isEmpty ? comments : comments.map(applyOne)
    }

    private func applyOne(_ c: Comment) -> Comment {
        let withReplies = c.replies.isEmpty ? c : c.with { $0.replies = c.replies.map(applyOne) }
        if c.isMore || state[c.id] == nil { return withReplies }
        let (likes, score) = votes.reconcile(c.id, serverLikes: c.likes, serverScore: c.score)
        if !votes.isPending(c.id) { state.removeValue(forKey: c.id) }
        return withReplies.with {
            $0.likes = likes
            $0.score = score
        }
    }

    func onUserChanged(_ username: String) {
        votes.clear()
        state = [:]
    }
}
