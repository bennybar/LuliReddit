import Foundation
import Observation

/// A thread saved for reading later / offline.
struct OfflineThread: Equatable, Sendable {
    let id: String
    let subreddit: String
    let title: String
    let savedAt: Int
}

/// "Read later": threads saved with their comments for offline reading. The
/// list is per account (prefs `offline_threads_<user>`), and so are the files
/// (Application Support/offline_threads/u_<user>/<postId>.json). Older copies
/// saved straight under offline_threads (the Flutter build) are still read.
@MainActor @Observable
final class OfflineStore: UserScoped {
    private static let base = "offline_threads"
    // The disk cache keeps the file as downloaded, whatever size it's decoded at.
    private static let imagePixelSize = 2048

    @ObservationIgnored private let prefs: Prefs
    @ObservationIgnored private let repo: RedditRepository
    @ObservationIgnored private let filesDir: URL
    @ObservationIgnored private var key = OfflineStore.base
    @ObservationIgnored private var user = ""

    private(set) var state: [OfflineThread] = []

    init(prefs: Prefs, repo: RedditRepository, filesDir: URL = FileLocations.files) {
        self.prefs = prefs
        self.repo = repo
        self.filesDir = filesDir
    }

    private nonisolated static func root(_ filesDir: URL) -> URL { filesDir.appendingPathComponent("offline_threads") }

    // Each account's threads in its own folder: two accounts saving the same
    // thread (or one with access to a private sub) never share or delete a copy.
    private nonisolated static func threadFile(_ filesDir: URL, owner: String, postId: String) -> URL {
        let dir = root(filesDir).appendingPathComponent("u_" + (owner.lowercased().nilIfEmpty ?? "_"))
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(postId).json")
    }

    // Where the Flutter build (and Ilay before 2.0.10) kept them, for every account.
    private nonisolated static func legacyFile(_ filesDir: URL, postId: String) -> URL {
        root(filesDir).appendingPathComponent("\(postId).json")
    }

    func onUserChanged(_ username: String) {
        user = username
        key = userScopedKey(prefs, username, OfflineStore.base)
        state = readIndex(key)
    }

    private func readIndex(_ indexKey: String) -> [OfflineThread] {
        guard let raw = prefs.getString(indexKey), let rows = parseJsonOrNull(raw).arr() else { return [] }
        var out: [OfflineThread] = []
        for r in rows {
            guard let id = r["id"].str() else { return [] }
            out.append(OfflineThread(id: id, subreddit: r["sub"].str() ?? "", title: r["title"].str() ?? "", savedAt: r["at"].long() ?? 0))
        }
        return out
    }

    func contains(_ postId: String) -> Bool { state.contains { $0.id == postId } }

    /// The saved comments response for [postId], or nil if this account didn't save it.
    func read(_ postId: String) async -> JsonElement? {
        guard contains(postId) else { return nil }
        let (owner, dir) = (user, filesDir)
        return await Task.detached {
            let files = [OfflineStore.threadFile(dir, owner: owner, postId: postId), OfflineStore.legacyFile(dir, postId: postId)]
            guard let file = files.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
                  let data = try? Data(contentsOf: file) else { return nil }
            return try? AppJson.parse(data)
        }.value
    }

    private func persist(_ indexKey: String, _ next: [OfflineThread]) {
        if indexKey == key { state = next }
        let json = JsonElement.array(next.map { t in
            ["id": .string(t.id), "sub": .string(t.subreddit), "title": .string(t.title), "at": .int(t.savedAt)]
        })
        prefs.setString(indexKey, json.encoded())
    }

    /// Downloads [post]'s thread (up to 500 comments) and its images.
    func save(_ post: Post) async throws {
        // The account that asked: a switch during the download still files it there.
        let (owner, indexKey, dir) = (user, key, filesDir)
        let raw = try await repo.getCommentsRaw(subreddit: post.subreddit, postId: post.id, limit: 500)
        try await Task.detached {
            try Data(raw.encoded().utf8).write(to: OfflineStore.threadFile(dir, owner: owner, postId: post.id), options: .atomic)
        }.value
        // Images go into the regular image cache, so the post renders offline.
        let urls = ([post.previewUrl, post.previewMedUrl].compactMap { $0 } + post.gallery.map(\.url)).uniqued().compactMap { URL(string: $0) }
        ImageLoader.shared.prefetch(urls: urls, maxPixelSize: OfflineStore.imagePixelSize)
        let current = indexKey == key ? state : readIndex(indexKey)
        persist(indexKey, [OfflineThread(id: post.id, subreddit: post.subreddit, title: post.title, savedAt: nowMillis())] + current.filter { $0.id != post.id })
    }

    func remove(_ postId: String) async {
        let (owner, dir) = (user, filesDir)
        persist(key, state.filter { $0.id != postId })
        // A shared old-style copy goes only once no account lists it.
        let stillListed = prefs.keys().filter { $0 == OfflineStore.base || $0.hasPrefix(OfflineStore.base + "_") }
            .contains { k in readIndex(k).contains { $0.id == postId } }
        await Task.detached {
            try? FileManager.default.removeItem(at: OfflineStore.threadFile(dir, owner: owner, postId: postId))
            if !stillListed { try? FileManager.default.removeItem(at: OfflineStore.legacyFile(dir, postId: postId)) }
        }.value
    }
}
