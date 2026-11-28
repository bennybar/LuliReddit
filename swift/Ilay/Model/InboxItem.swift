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
    /// The author's account id (t2_…), for their picture (#315).
    var authorFullname: String? = nil

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
                replies: d["replies"]["data"]["children"].arr()?.map { fromChild($0) } ?? [],
                authorFullname: d["author_fullname"].str()
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
            linkTitle: d["link_title"].str().map(decodeEntities)?.trimmed,
            subreddit: d["subreddit"].str(),
            authorFullname: d["author_fullname"].str()
        )
    }
}

/// Reddit sends an inbox item's `link_title` HTML-escaped even with raw_json, sometimes
/// twice ("&amp;#128075;" for 👋), so it's decoded until nothing changes (at most 3 times).
func decodeEntities(_ s: String) -> String {
    var out = s
    for _ in 0..<3 {
        guard out.contains("&") else { return out }
        let ns = out as NSString
        var next = ""
        var last = 0
        for m in entityPattern.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
            next += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let e = ns.substring(with: m.range(at: 1))
            var rep: String?
            if e.lowercased().hasPrefix("#x") { rep = UInt32(e.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) } }
            else if e.hasPrefix("#") { rep = UInt32(e.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) } }
            else { rep = namedEntities[e] }
            next += rep ?? ns.substring(with: m.range)
            last = m.range.location + m.range.length
        }
        next += ns.substring(from: last)
        if next == out { return out }
        out = next
    }
    return out
}

private let entityPattern = try! NSRegularExpression(pattern: "&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|amp|lt|gt|quot|apos|nbsp);")
private let namedEntities = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}"]
