import Foundation

// Website sign-in: when Reddit's edge refuses a thread's .json (403, as it did
// search and /by_id), the thread loads like in Reddit's app: the post by id
// and its comment forest from PostComments, mapped to the comments response
// the app already parses (and saves for offline reading).
let GQL_POST_COMMENTS = "8a25ae56c1d4813102f4eded0c427b99f46f6a63f77630e78767f27ef5186f1f"

/// A "more" row from GraphQL holds its cursor as its only child id, behind
/// this prefix: getMoreComments continues it through PostComments, since
/// /api/morechildren only takes comment ids.
let GQL_MORE = "gql:"

// The comment fragment's switches; off: what the app doesn't show.
private let commentFlags: [(String, Bool)] = [
    ("includeAwards", false), ("includeCommentsHtmlField", false), ("includeIsGildable", false),
    ("includeModerationInfo", false), ("subredditUserPostEditingAllowed", false),
    ("includeExtendedVideoAsset", true), ("includePlaybackMp4s", true), ("includeMuxedMp4s", true),
    ("includeVideoPlaybackInComments", false), ("includeCommentViewStats", false),
    ("includePremiumAvatarTreatment", false), ("includeCommentFollowedForNotificationsStatus", false),
    ("includeCommentEntityHighlights", false), ("includeRedditHandleInfo", false),
    ("includeVerificationStatus", false),
]

private let gqlCommentSorts = [
    "confidence": "CONFIDENCE", "top": "TOP", "new": "NEW",
    "controversial": "CONTROVERSIAL", "old": "OLD", "qa": "QA",
]

/// PostComments' variables: a post's comments ([after]: a "more" row's
/// cursor), or [focusCommentId]'s thread with 3 parents, like the website's
/// `?comment=…&context=3`. Reddit sends at most 25 comments per request.
func postCommentsVariables(_ postFullname: String, _ sort: String, _ focusCommentId: String?, _ after: String?) -> JsonObject {
    var o = JsonObject()
    for (k, v) in commentFlags { o[k] = .bool(v) }
    o["id"] = .string(postFullname)
    o["maxDepth"] = 10
    o["count"] = 200
    o["includeAdEligibility"] = false
    o["isUserMod"] = false
    o["skipPostInfoFragment"] = true
    o["includeConsistencyToken"] = false
    o["callerContext"] = ["referrer": "FEED"]
    if let s = gqlCommentSorts[sort] { o["sortType"] = .string(s) }
    if let after { o["after"] = .string(after) }
    if let focusCommentId {
        o["focusedCommentContext"] = [
            "commentId": .string("t1_\(focusCommentId)"),
            "isFocusedThreadOnly": true,
            "minDeepCommentParents": 3,
        ]
        o["numParents"] = 3
    }
    return o
}

/// PostComments' forest (a flat, depth-first list of comments and "more"
/// entries) as listing things (kind t1 / more), each naming its parent: the
/// shape /api/morechildren returns. Depths are relative (a loaded "more"
/// starts deeper, a focused thread's parents are negative), so the shallowest
/// entries hang off the forest's own parent, else [linkFullname].
/// Each comment author's picture in a GraphQL comment forest: lowercased name → its iconSmall url.
func gqlAuthorIcons(_ trees: [JsonElement]) -> [String: String] {
    var out: [String: String] = [:]
    for tree in trees {
        let info = tree["node"]["authorInfo"]
        guard let name = info["name"].str(), let url = info["iconSmall"]["url"].str() else { continue }
        out[name.lowercased()] = url
    }
    return out
}

func gqlCommentThings(_ trees: [JsonElement], _ linkFullname: String, moreParent: String? = nil) -> [JsonElement] {
    let base = trees.compactMap { $0["depth"].int() }.min() ?? 0
    // ancestors[d]: the latest comment at relative depth d.
    var ancestors: [String] = []
    var out: [JsonElement] = []
    for (i, tree) in trees.enumerated() {
        let depth = tree["depth"].int() ?? base
        let level = depth - base
        // A loaded "more" ([moreParent]): its shallowest entries are that row's
        // replies, whatever form Reddit's parentId takes (CommentTree.replaceMore
        // attaches them by it).
        let parent: String
        if level == 0 {
            parent = moreParent ?? tree["parentId"].str() ?? linkFullname
        } else if level - 1 < ancestors.count {
            parent = ancestors[level - 1]
        } else {
            continue
        }
        if let more = tree["more"].obj() {
            guard let cursor = more["cursor"].str() else { continue }
            out.append([
                "kind": "more",
                "data": [
                    "id": .string("more_\(parent)"),
                    "name": .string("more_\(parent)"),
                    "parent_id": .string(parent),
                    "count": .int(more["count"].int() ?? 0),
                    // The row's parent travels with its cursor, for when it loads.
                    "children": [.string("\(GQL_MORE)\(parent) \(cursor)")],
                ],
            ])
            continue
        }
        guard let n = tree["node"].obj() else { continue }
        // A deleted comment comes without its id, but the replies under it
        // name it as their parent (Reddit only keeps deleted ones with replies).
        var name = n["id"].str()
        if name == nil {
            for t in trees[(i + 1)...] {
                guard (t["depth"].int() ?? depth) > depth else { break }
                if t["depth"].int() == depth + 1, let p = t["parentId"].str() {
                    name = p
                    break
                }
            }
        }
        let fullname = name ?? "t1_deleted\(i)"
        ancestors.removeSubrange(min(level, ancestors.count)...)
        ancestors.append(fullname)
        let deleted = n["__typename"].str() != "Comment" || n["isRemoved"].bool() == true || n["content"].obj() == nil
        let category = n["removedByCategory"].str()
        let gone = category == nil || category == "DELETED" ? "[deleted]" : "[removed]"
        let flair = n["authorFlair"]
        let id = fullname.removePrefix("t1_")
        var data: JsonObject = [
            "id": .string(id),
            "name": .string(fullname),
            "parent_id": .string(parent),
            "author": .string(deleted ? "[deleted]" : n["authorInfo"]["name"].str() ?? "[deleted]"),
            "body": .string(deleted ? gone : gqlMarkdown(n["content"], id)),
            "score": .int(n["score"].int() ?? 0),
            "created_utc": .double(gqlSeconds(n["createdAt"].str())),
        ]
        switch n["distinguishedAs"].str() {
        case "MODERATOR": data["distinguished"] = "moderator"
        case "ADMIN": data["distinguished"] = "admin"
        default: data["distinguished"] = .null
        }
        data["stickied"] = .bool(n["isStickied"].bool() == true)
        data["score_hidden"] = .bool(n["isScoreHidden"].bool() == true)
        data["saved"] = .bool(n["isSaved"].bool() == true)
        data["is_submitter"] = .bool(n["isOP"].bool() == true)
        switch n["voteState"].str() {
        case "UP": data["likes"] = true
        case "DOWN": data["likes"] = false
        default: data["likes"] = .null
        }
        data["permalink"] = .of(n["permalink"].str())
        // The flair's richtext is a JSON string here, an array on the website.
        if let rich = flair["richtext"].str().flatMap(parseJsonOrNull) { data["author_flair_richtext"] = rich }
        data["author_flair_text"] = .of(flair["text"].str())
        // Uploaded images and GIFs the markdown names by id (`![img](id)`).
        let media = n["content"]["richtextMedia"].arr()?.compactMap { m in m["id"].str().map { ($0, mediaUrl(m)) } } ?? []
        if !media.isEmpty {
            var meta = JsonObject()
            for (mid, url) in media {
                var entry: JsonObject = ["status": .string(url != nil ? "valid" : "unprocessed")]
                if let url { entry["s"] = ["u": .string(url)] }
                meta[mid] = .object(entry)
            }
            data["media_metadata"] = .object(meta)
        }
        out.append(["kind": "t1", "data": .object(data)])
    }
    return out
}

/// PostsByIds' post and PostComments' forest as a thread's comments response
/// (`[post listing, comment listing]`), which parseThread reads and the
/// offline copy keeps.
func gqlThreadData(_ post: JsonObject, _ trees: [JsonElement]) -> JsonElement {
    let things = gqlCommentThings(trees, post["name"].str() ?? "")
    let byParent = Dictionary(grouping: things) { $0["data"]["parent_id"].str() ?? "" }
    let names = Set(things.compactMap { $0["data"]["name"].str() })
    func nest(_ t: JsonElement) -> JsonElement {
        guard let replies = byParent[t["data"]["name"].str() ?? ""], var data = t["data"].obj(), var thing = t.obj() else { return t }
        data["replies"] = ["data": ["children": .array(replies.map(nest))]]
        thing["data"] = .object(data)
        return .object(thing)
    }
    let top = things.filter { !names.contains($0["data"]["parent_id"].str() ?? "") }.map(nest)
    return [
        ["data": ["children": [["kind": "t3", "data": .object(post)]]]],
        ["data": ["children": .array(top)]],
    ]
}

// A richtext media asset's URL, largest size first.
private func mediaUrl(_ m: JsonElement?) -> String? {
    for k in ["xxxlarge", "xxlarge", "xlarge", "large", "medium"] {
        if let u = m[k]["url"].str() { return u }
    }
    return m["url"].str()
}

// Markdown's inline syntax, escaped in plain text so it reads literally.
private let mdSpecial = Re(#"[\\`*_~^\[\]>]"#)

/// A comment's body as markdown. The source markdown when Reddit sends it
/// (what editing, copying and translating need); otherwise converted from the
/// richtext, Reddit's own parse of the markdown as JSON:
///  - blocks: par, h{l}, blockquote, list{o} > li, code > raw lines, hr,
///    table{h, c}, img / gif / video{id}
///  - inline: text{t, f}, link{u, t, f}, r/ and u/{t, l}, spoilertext{c},
///    br, raw{t}, img / gif / video{id}
///  - f: [bits, start, length] ranges of t, counted in code points; bits
///    1 bold, 2 italic, 8 strike, 32 superscript, 64 code.
/// Media become bare links, which the comment renderer shows as media.
func gqlMarkdown(_ content: JsonElement?, _ thingId: String) -> String {
    if let md = content["markdown"].str(), !md.isEmpty { return md }
    guard let doc = content["richtext"].str().flatMap(parseJsonOrNull)["document"] else { return "" }
    guard doc.arr() != nil else { return "" }
    var media: [String: JsonElement] = [:]
    for m in content["richtextMedia"].arr() ?? [] {
        if let id = m["id"].str() { media[id] = m }
    }
    func escape(_ t: String) -> String { mdSpecial.replace(t) { "\\" + $0.value } }
    func mediaLink(_ n: JsonElement) -> String {
        guard let id = n["id"].str() else { return "" }
        // The player link Reddit's own HTML used for videos in a body.
        if n["e"].str() == "video" { return "https://reddit.com/link/\(thingId)/video/\(id)/player" }
        return giphyUrl(id) ?? mediaUrl(media[id]) ?? ""
    }
    func formatted(_ n: JsonElement, _ render: (String) -> String) -> String {
        let cps = Array((n["t"].str() ?? "").unicodeScalars)
        func slice(_ from: Int, _ to: Int) -> String {
            let a = min(max(from, 0), cps.count)
            let b = min(max(to, a), cps.count)
            var s = String.UnicodeScalarView()
            s.append(contentsOf: cps[a..<b])
            return String(s)
        }
        let ranges = (n["f"].arr() ?? []).compactMap { r -> (Int, Int, Int)? in
            r[0].int().map { ($0, r[1].int() ?? 0, r[2].int() ?? 0) }
        }.sorted { $0.1 < $1.1 }
        var out = ""
        var pos = 0
        for (bits, start, length) in ranges {
            if start > pos { out += render(slice(pos, start)) }
            let text = slice(max(start, pos), start + length)
            pos = max(pos, start + length)
            let core = text.trimmed
            if core.isEmpty {
                out += render(text)
                continue
            }
            // Markers must touch the text: `** bold**` isn't bold.
            var md = bits & 64 != 0 ? "`\(core)`" : render(core)
            if bits & 32 != 0 { md = "^(\(md))" }
            if bits & 8 != 0 { md = "~~\(md)~~" }
            if bits & 2 != 0 { md = "*\(md)*" }
            if bits & 1 != 0 { md = "**\(md)**" }
            let r = text.range(of: core)!
            out += text[..<r.lowerBound] + md + text[r.upperBound...]
        }
        if pos < cps.count { out += render(slice(pos, cps.count)) }
        return out
    }
    func inline(_ nodes: JsonElement?) -> String {
        (nodes.arr() ?? []).map { n -> String in
            let e = n["e"].str()
            switch e {
            case "text": return formatted(n, escape)
            case "link":
                let url = (n["u"].str() ?? "").replacingOccurrences(of: " ", with: "%20")
                    .replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29")
                return formatted(n) { "[\(escape($0))](\(url))" }
            case "r/", "u/": return (n["l"].bool() == true || n["l"].int() == 1 ? "/" : "") + e! + (n["t"].str() ?? "")
            case "spoilertext": return ">!\(inline(n["c"]))!<"
            case "br": return "  \n"
            case "img", "gif", "video": return mediaLink(n)
            default: return escape(n["t"].str() ?? "")
            }
        }.joined()
    }
    func blocks(_ nodes: JsonElement?) -> String {
        (nodes.arr() ?? []).map { n -> String in
            switch n["e"].str() {
            case "par": return inline(n["c"])
            case "h": return String(repeating: "#", count: min(max(n["l"].int() ?? 1, 1), 6)) + " " + inline(n["c"])
            case "blockquote": return blocks(n["c"]).lines().map { $0.isEmpty ? ">" : "> \($0)" }.joined(separator: "\n")
            case "list":
                return (n["c"].arr() ?? []).enumerated().map { i, li -> String in
                    let marker = n["o"].bool() == true ? "\(i + 1). " : "- "
                    return marker + blocks(li["c"]).lines().joined(separator: "\n" + String(repeating: " ", count: marker.count))
                }.joined(separator: "\n")
            case "code": return "```\n" + (n["c"].arr() ?? []).map { $0["t"].str() ?? "" }.joined(separator: "\n") + "\n```"
            case "hr": return "---"
            case "table":
                let head = n["h"].arr() ?? []
                let rows = (n["c"].arr() ?? []).map { row in (row.arr() ?? []).map { inline($0["c"]) } }
                let align = head.map { h -> String in
                    switch h["a"].str() {
                    case "L": return ":--"
                    case "C": return ":-:"
                    case "R": return "--:"
                    default: return "---"
                    }
                }
                return ([head.map { inline($0["c"]) }, align] + rows).map { "| " + $0.joined(separator: " | ") + " |" }.joined(separator: "\n")
            case "img", "gif", "video": return mediaLink(n)
            // Anything newer: its inline content, or its text.
            default: return n["c"].arr() != nil ? inline(n["c"]) : escape(n["t"].str() ?? "")
            }
        }.joined(separator: "\n\n")
    }
    return blocks(doc)
}
