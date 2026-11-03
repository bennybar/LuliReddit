import Foundation

enum InboxKind: Sendable { case commentReply, postReply, mention, message }

struct InboxItem: Identifiable, Equatable, Sendable, Copyable {
    var fullname: String // t1_ or t4_
    var kind: InboxKind
    var author: String
    var subject: String
    var body: String
    var createdUtc: Int
    var isNew: Bool = false
    var context: String? = nil // permalink for comment replies/mentions
    var linkTitle: String? = nil
    var subreddit: String? = nil
    var dest: String? = nil
    var replies: [InboxItem] = []

    var id: String { fullname }
    var isMessage: Bool { kind == .message }

    private var contextSegments: [String]? {
        context?.substringBefore("?").components(separatedBy: "/").filter { !$0.isEmpty }
    }

    /// For comment replies/mentions: (subreddit, postId) parsed from [context].
    var postRef: (subreddit: String, postId: String)? {
        guard let segs = contextSegments, let ci = segs.firstIndex(of: "comments"), ci >= 1, ci + 1 < segs.count else { return nil }
        return (segs[ci - 1], segs[ci + 1])
    }

    /// The focused comment id in [context] (`…/comments/<post>/<slug>/<comment>/`), if any.
    var contextCommentId: String? {
        guard let segs = contextSegments, let ci = segs.firstIndex(of: "comments"), segs.count > ci + 3 else { return nil }
        return segs[ci + 3]
    }

    static func fromChild(_ child: JsonElement) -> InboxItem {
        let type = child["kind"].str()
        let d = child["data"]
        let created = (d["created_utc"].long() ?? 0) * 1000
        let id = d["id"].str() ?? "null"

        if type == "t4" {
            return InboxItem(
                fullname: d["name"].str() ?? "t4_\(id)",
                kind: .message,
                author: d["author"].str() ?? "[unknown]",
                subject: (d["subject"].str() ?? "").trimmed,
                body: d["body"].str() ?? "",
                createdUtc: created,
                isNew: d["new"].isTrue(),
                subreddit: d["subreddit"].str(),
                dest: d["dest"].str(),
                replies: d["replies"]["data"]["children"].arr()?.map { fromChild($0) } ?? []
            )
        }

        let kind: InboxKind
        switch d["type"].str() {
        case "post_reply": kind = .postReply
        case "username_mention": kind = .mention
        default: kind = .commentReply
        }
        return InboxItem(
            fullname: d["name"].str() ?? "t1_\(id)",
            kind: kind,
            author: d["author"].str() ?? "[deleted]",
            subject: (d["subject"].str() ?? "").trimmed,
            body: d["body"].str() ?? "",
            createdUtc: created,
            isNew: d["new"].isTrue(),
            context: d["context"].str(),
            linkTitle: d["link_title"].str()?.trimmed,
            subreddit: d["subreddit"].str()
        )
    }
}
