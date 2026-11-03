import Foundation
import Observation

/// An unfinished reply / message / post: its composer [key] ("reply_t1_…",
/// "msgreply_t4_…", "compose_msg", "compose_post"), its [text] (JSON for the
/// message and post composers) and [info]: where it goes, for the Drafts list.
struct Draft: Sendable {
    let key: String
    let text: String
    let info: JsonElement?
    let savedAt: Int
}

/// Persists in-progress composer text so a long reply/post/message survives
/// navigating away, backgrounding or a crash. Keyed by the signed-in account and
/// the compose target (e.g. the parent fullname), so another account never sees
/// or sends it; a draft from before accounts were part of the key moves to the
/// first account that opens it. Cleared on a successful submit. Local only.
///
/// Next to each draft, [save]'s `info` says where it goes (post title,
/// subreddit, recipient) so You → Drafts can list and reopen it.
@MainActor @Observable
final class Drafts {
    @ObservationIgnored private let prefs: Prefs
    @ObservationIgnored private let username: () -> String

    /// Bumped on every save / clear, so the Drafts list refreshes.
    private(set) var changes = 0

    init(prefs: Prefs, username: @escaping () -> String) {
        self.prefs = prefs
        self.username = username
    }

    private func k(_ key: String) -> String { userScopedKey(prefs, username(), "draft_\(key)") }
    private func infoKey(_ key: String) -> String { userScopedKey(prefs, username(), "draftinfo_\(key)") }

    func get(_ key: String) -> String? { prefs.getString(k(key)) }

    func save(_ key: String, _ value: String, info: JsonObject? = nil) {
        if value.isBlank { return clear(key) }
        prefs.setString(k(key), value)
        var stamped = info ?? JsonObject()
        stamped["at"] = .int(nowMillis())
        prefs.setString(infoKey(key), stamped.encoded())
        changes += 1
    }

    func clear(_ key: String) {
        prefs.remove(k(key))
        prefs.remove(infoKey(key))
        changes += 1
    }

    /// This account's drafts, newest first.
    func list() -> [Draft] {
        guard let user = username().nilIfEmpty else { return [] }
        let suffix = "_" + user.lowercased()
        return prefs.keys()
            .filter { $0.hasPrefix("draft_") && $0.hasSuffix(suffix) }
            .compactMap { full -> Draft? in
                let key = full.removePrefix("draft_").removeSuffix(suffix)
                guard !key.isEmpty, let text = prefs.getString(full), !text.isBlank else { return nil }
                let info = prefs.getString("draftinfo_\(key)\(suffix)").flatMap(parseJsonOrNull)
                return Draft(key: key, text: text, info: info, savedAt: info["at"].long() ?? 0)
            }
            .sorted { $0.savedAt > $1.savedAt }
    }
}
