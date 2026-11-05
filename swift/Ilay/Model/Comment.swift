import Foundation

/// A node in the comment tree. `kind: t1` is a comment; `kind: more` is a
/// "load more comments" placeholder ([isMore]).
struct Comment: Identifiable, Equatable, Sendable, Copyable {
    var id: String
    var fullname: String // t1_xxx
    var parentId: String = "" // t1_xxx or t3_xxx
    var author: String
    var body: String
    var score: Int
    var createdUtc: Int // millis since epoch
    var depth: Int
    var distinguished: String? = nil
    var stickied: Bool = false
    var scoreHidden: Bool = false
    var saved: Bool = false
    var likes: Bool? = nil
    /// The author's user flair in this community, as text (nil: none).
    var authorFlair: UserFlair? = nil
    // Present on user/saved comment listings — link back to the parent post.
    var linkTitle: String = ""
    var permalink: String = ""
    var subreddit: String = ""
    /// The parent post is NSFW (`over_18`, on user/saved listings only).
    var over18: Bool = false
    /// media_metadata id → playable URL, for media referenced as `![gif](giphy|…)`.
    var media: [String: String] = [:]
    var replies: [Comment] = []
    // "more" placeholder fields
    var isMore: Bool = false
    var moreCount: Int = 0
    var moreChildren: [String] = []
    var collapsed: Bool = false

    static func fromChild(_ child: JsonElement, _ depth: Int) -> Comment {
        let kind = child["kind"].str()
        let d = child["data"]

        if kind == "more" {
            let children = d["children"].arr()?.compactMap { $0.str() } ?? []
            // "Continue this thread" stubs all come as id "_" / name "t1__":
            // give each a unique id from its parent, or two in one thread
            // would share a list key (a crash).
            let stub = d["id"].str() == "_"
            let parent = d["parent_id"].str() ?? ""
            return Comment(
                id: stub ? "more_\(parent)" : d["id"].str() ?? "more",
                fullname: stub ? "more_\(parent)" : d["name"].str() ?? "more_\(d["id"].str() ?? "null")",
                parentId: parent,
                author: "",
                body: "",
                score: 0,
                createdUtc: 0,
                depth: depth,
                isMore: true,
                moreCount: d["count"].int() ?? children.count,
                moreChildren: children
            )
        }

        let replies = d["replies"]["data"]["children"].arr()?
            .filter { $0.obj() != nil }
            .map { fromChild($0, depth + 1) } ?? []

        // Some responses (a website-session /api/comment) give the id
        // already prefixed ("t1_abc") and no name.
        let id = d["id"].str()?.removePrefix("t1_")
        return Comment(
            id: id ?? "",
            fullname: d["name"].str() ?? "t1_\(id ?? "null")",
            parentId: d["parent_id"].str() ?? "",
            author: d["author"].str() ?? "[deleted]",
            body: d["body"].str() ?? "",
            score: d["score"].int() ?? 0,
            createdUtc: (d["created_utc"].long() ?? 0) * 1000,
            depth: depth,
            distinguished: d["distinguished"].str(),
            stickied: d["stickied"].isTrue(),
            scoreHidden: d["score_hidden"].isTrue(),
            saved: d["saved"].isTrue(),
            likes: d["likes"].bool(),
            authorFlair: flairOf(d, "author"),
            linkTitle: d["link_title"].str()?.trimmed ?? "",
            permalink: d["permalink"].str() ?? "",
            subreddit: d["subreddit"].str() ?? "",
            over18: d["over_18"].isTrue(),
            media: mediaUrls(d["media_metadata"]),
            replies: replies
        )
    }

    /// Resolves `media_metadata` (GIFs from Reddit's GIF picker, uploaded
    /// images) to one URL per id. Emotes are left out: they sit inline in text.
    static func mediaUrls(_ raw: JsonElement?) -> [String: String] {
        guard let m = raw.obj() else { return [:] }
        var out: [String: String] = [:]
        for (key, value) in m {
            if key.hasPrefix("emote|") || value.obj() == nil { continue }
            if value["status"].str() != "valid" {
                // Reddit often sends GIF-picker GIFs as "invalid" with no URL
                // (its own apps still show them): use Giphy's copy by id.
                if let g = giphyUrl(key) { out[key] = g }
                continue
            }
            guard let s = value["s"].obj(), let url = s["gif"].str() ?? s["u"].str() ?? s["mp4"].str() else { continue }
            out[key] = url.htmlAmpFixed()
        }
        return out
    }
}
