import Foundation

// ---------------------------------------------------------------------------
// Last ranked page, for an instant first paint
// ---------------------------------------------------------------------------

// [feed] is "foryou" or "home" (Reddit Home): each keeps its own last page.
// Same file as the Flutter build (getApplicationSupportDirectory).
private func cacheFile(_ dir: URL, _ user: String, _ feed: String) -> URL {
    dir.appendingPathComponent("\(feed)_\(user.lowercased()).json")
}

/// Saves the first page (raw post data + each post's reason).
func saveForYouPage(user: String, posts: [Post], raw: (String) -> JsonElement?, feed: String = "foryou", dir: URL = FileLocations.files) async {
    let rows = posts.prefix(40).compactMap { p -> JsonElement? in
        guard let r = raw(p.id) else { return nil }
        return ["raw": r, "reason": .of(p.feedReason)]
    }
    // Best effort.
    try? Data(JsonElement.array(rows).encoded().utf8).write(to: cacheFile(dir, user, feed), options: .atomic)
}

/// When the saved page was written, or nil if there is none.
func savedPageTime(user: String, feed: String = "foryou", dir: URL = FileLocations.files) async -> Int? {
    let attrs = try? FileManager.default.attributesOfItem(atPath: cacheFile(dir, user, feed).path)
    return (attrs?[.modificationDate] as? Date).map { Int($0.timeIntervalSince1970 * 1000) }
}

/// The saved page, minus posts opened since (they'd only be demoted now).
func loadForYouPage(user: String, opened: Set<String>, feed: String = "foryou", dir: URL = FileLocations.files) async -> [Post]? {
    guard let data = try? Data(contentsOf: cacheFile(dir, user, feed)), let rows = (try? AppJson.parse(data))?.arr() else { return nil }
    var posts: [Post] = []
    for r in rows {
        guard let raw = r["raw"] else { return nil }
        let p = Post.fromData(raw).with { $0.feedReason = r["reason"].str() }
        if !opened.contains(p.id) { posts.append(p) }
    }
    return posts.isEmpty ? nil : posts
}
