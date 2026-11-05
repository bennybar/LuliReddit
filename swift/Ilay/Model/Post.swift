import Foundation

enum PostType: Sendable { case selfPost, image, video, gif, gallery, link }

/// A gallery item (resolved image url + dimensions).
struct GalleryImage: Equatable, Sendable {
    let url: String
    var width: Int? = nil
    var height: Int? = nil
}

struct Post: Identifiable, Equatable, Sendable, Copyable {
    var id: String
    var fullname: String // t3_xxx
    var title: String
    var subreddit: String
    var subredditPrefixed: String
    /// The subreddit's icon (from `sr_detail`), or nil: the card shows its first letter.
    var subredditIcon: String? = nil
    var author: String
    var score: Int
    var numComments: Int
    /// Nil when the source doesn't say (a card read from the Home page; GraphQL without the field).
    var upvoteRatio: Double?
    var createdUtc: Int // millis since epoch
    var permalink: String
    var url: String
    var domain: String
    var type: PostType
    var isSelf: Bool = false
    var selftext: String = "" { didSet { parsedSnippet = nil } }
    var over18: Bool = false
    var spoiler: Bool = false
    var stickied: Bool = false
    var locked: Bool = false
    var saved: Bool = false
    var canModPost: Bool = false
    var linkFlairText: String? = nil
    /// The post's flair to show: its words and images (#56).
    var linkFlair: UserFlair? = nil
    var distinguished: String? = nil
    /// The mods' suggested comment sort (e.g. "qa" on AMAs), when set.
    var suggestedSort: String? = nil
    var feedReason: String? = nil // "why you're seeing this" in For You (transient)
    var crosspostFrom: String? = nil // subreddit a crosspost originates from
    /// The original post's id, for opening it from "Crossposted from" (#100).
    var crosspostId: String? = nil
    /// The original's fullname (`crosspost_parent`), also when the listing left out its data.
    var crosspostParent: String? = nil
    /// Images / GIFs referenced inside the body (`media_metadata`), by id — shown inline, not as links.
    var bodyMedia: [String: String] = [:]
    var pollOptions: [String] = []
    /// The author's user flair in this community, as text (nil: none).
    var authorFlair: UserFlair? = nil
    /// Votes per option, same order; empty while Reddit hides them (before you vote or it ends).
    var pollVotes: [Int] = []
    /// Which option you voted for, if you did.
    var pollChoice: Int? = nil
    // media
    var thumbnailUrl: String? = nil
    var previewUrl: String? = nil
    var previewMedUrl: String? = nil // smaller resolution for feed cards
    var blurredPreviewUrl: String? = nil // reddit's pre-blurred NSFW/spoiler variant
    var previewWidth: Int? = nil
    var previewHeight: Int? = nil
    var hlsUrl: String? = nil
    var fallbackVideoUrl: String? = nil
    var gifMp4Url: String? = nil // reddit's mp4 variant for GIF posts (much smaller)
    var gallery: [GalleryImage] = []
    /// Vote state: true = up, false = down, nil = none.
    var likes: Bool? = nil
    /// [snippet], worked out while parsing (off the main thread) so a card never does it.
    var parsedSnippet: String? = nil

    var hasMedia: Bool { previewUrl != nil || !gallery.isEmpty || type == .video }

    /// A crosspost whose listing left out the original (`crosspost_parent_list`; Reddit
    /// omits it at times, e.g. for posts on a user's profile): its media and text are on
    /// the original, fetched afterwards (see `RedditRepository.fillCrossposts`). A
    /// `shareLink` post is one too, once its link is resolved to the original.
    var missingCrosspostParent: Bool { (crosspostParent != nil && crosspostId == nil) || shareLink }

    /// A link post to a Reddit share link (`/r/<sub>/s/<code>`, `/u/<name>/s/<code>`),
    /// Reddit's "repost": a post that only redirects to another one.
    var shareLink: Bool { type == .link && crosspostParent == nil && URL(string: url).map(isShareLink) == true }

    /// The body as a feed card previews it: without image / video links that the post view shows as media.
    var snippet: String { parsedSnippet ?? Post.snippetOf(selftext, bodyMedia) }

    private static func snippetOf(_ selftext: String, _ bodyMedia: [String: String]) -> String {
        bodyMedia.isEmpty && !selftext.contains("http") ? selftext : textWithoutMedia(selftext)
    }

    /// A crosspost's `d` with its original's `parent` data (fetched separately, as the
    /// listing left it out) put back where Reddit normally sends it, `crosspost_parent_list`.
    /// `fullname` names the original (`crosspost_parent`) for a `shareLink` post, which doesn't.
    static func withCrosspostParent(_ d: JsonElement, _ parent: JsonElement, fullname: String? = nil) -> JsonElement {
        var o = d.obj() ?? JsonObject()
        o["crosspost_parent_list"] = .array([parent])
        if let fullname { o["crosspost_parent"] = .string(fullname) }
        return .object(o)
    }

    /// Parses a single listing child's `data` object.
    static func fromData(_ d: JsonElement) -> Post {
        // A crosspost carries no content of its own: its text, media and
        // link live on the original post (its own url just points there).
        let parent: JsonElement? = d["crosspost_parent_list"].arr()?.first.flatMap { $0.obj() != nil ? $0 : nil }
        let content: JsonElement = parent ?? d
        let preview = firstPreviewImage(d) ?? firstPreviewImage(content)
        func videoOf(_ x: JsonElement?) -> JsonElement? {
            [x["media"]["reddit_video"], x["secure_media"]["reddit_video"]].compactMap { $0 }.first { $0.obj() != nil }
        }
        let redditVideo = videoOf(d) ?? videoOf(parent)
        let ownGallery = parseGallery(d)
        let gallery = !ownGallery.isEmpty || parent == nil ? ownGallery : parseGallery(parent!)
        // A bare v.redd.it link with no video metadata: its HLS stream sits
        // at a fixed address under the video's id.
        let url = content["url"].str() ?? d["url"].str() ?? ""
        let vreddit = URL(string: url)
        let bareVreddit = redditVideo == nil && vreddit?.host == "v.redd.it" && vreddit?.segments.isEmpty == false
        let isVideo = d["is_video"].isTrue() || parent["is_video"].isTrue() || redditVideo != nil || bareVreddit
        let flair = d["link_flair_text"].str()
        let poll = content["poll_data"]
        let pollRaw = (poll["options"].arr() ?? []).filter { $0["text"].str()?.isEmpty == false }
        let pollVotes = pollRaw.map { $0["vote_count"].int() ?? -1 }
        let bodyMedia = Comment.mediaUrls(content["media_metadata"])
        let selftext = d["selftext"].str()?.nilIfEmpty ?? content["selftext"].str() ?? ""

        return Post(
            id: d["id"].str() ?? "",
            fullname: d["name"].str() ?? "t3_\(d["id"].str() ?? "null")",
            title: (d["title"].str() ?? "").trimmed,
            subreddit: d["subreddit"].str() ?? "",
            subredditPrefixed: d["subreddit_name_prefixed"].str() ?? "",
            subredditIcon: (d["sr_detail"]["community_icon"].str()?.nilIfEmpty ?? d["sr_detail"]["icon_img"].str()?.nilIfEmpty)?.htmlAmpFixed(),
            author: d["author"].str() ?? "[deleted]",
            score: d["score"].int() ?? 0,
            numComments: d["num_comments"].int() ?? 0,
            upvoteRatio: d["upvote_ratio"].double(),
            createdUtc: (d["created_utc"].long() ?? 0) * 1000,
            permalink: d["permalink"].str() ?? "",
            url: url,
            domain: content["domain"].str() ?? d["domain"].str() ?? "",
            type: detectType(content, isVideo: isVideo, hasGallery: !gallery.isEmpty),
            // The crosspost itself is a link post (it can't be edited as text),
            // even when it shows the original's text.
            isSelf: d["is_self"].isTrue(),
            selftext: selftext,
            over18: d["over_18"].isTrue(),
            spoiler: d["spoiler"].isTrue(),
            stickied: d["stickied"].isTrue(),
            locked: d["locked"].isTrue(),
            saved: d["saved"].isTrue(),
            canModPost: d["can_mod_post"].isTrue(),
            linkFlairText: flair?.isBlank != false ? nil : flair,
            linkFlair: flairOf(d, "link"),
            distinguished: d["distinguished"].str(),
            suggestedSort: d["suggested_sort"].str()?.nilIfEmpty,
            crosspostFrom: parent["subreddit"].str(),
            crosspostId: parent["id"].str(),
            crosspostParent: d["crosspost_parent"].str()?.nilIfEmpty,
            bodyMedia: bodyMedia,
            pollOptions: pollRaw.map { $0["text"].str()! },
            authorFlair: flairOf(d, "author"),
            pollVotes: !pollVotes.isEmpty && !pollVotes.contains { $0 < 0 } ? pollVotes : [],
            pollChoice: poll["user_selection"].str().flatMap { sel in pollRaw.firstIndex { $0["id"].str() == sel } },
            thumbnailUrl: validThumb(d["thumbnail"].str()) ?? validThumb(content["thumbnail"].str()),
            previewUrl: preview?.url,
            previewMedUrl: medPreviewUrl(d) ?? medPreviewUrl(content) ?? preview?.url,
            blurredPreviewUrl: blurredPreviewUrl(d) ?? blurredPreviewUrl(content),
            previewWidth: preview?.width,
            previewHeight: preview?.height,
            hlsUrl: redditVideo["hls_url"].str() ?? (bareVreddit ? "https://v.redd.it/\(vreddit!.segments[0])/HLSPlaylist.m3u8" : nil),
            fallbackVideoUrl: redditVideo["fallback_url"].str(),
            gifMp4Url: content["preview"]["reddit_video_preview"]["fallback_url"].str(),
            gallery: gallery,
            likes: d["likes"].bool(),
            parsedSnippet: snippetOf(selftext, bodyMedia)
        )
    }

    private static func detectType(_ d: JsonElement, isVideo: Bool, hasGallery: Bool) -> PostType {
        if d["is_self"].isTrue() { return .selfPost }
        if hasGallery { return .gallery }
        if isVideo { return .video }
        switch d["post_hint"].str() {
        case "image": return .image
        case "rich:video", "hosted:video": return .video
        default: break
        }
        let rawUrl = d["url"].str() ?? ""
        let parsed = URL(string: rawUrl)
        // Check the path without query params — preview.redd.it links end
        // with `.png?width=…&s=…`.
        let path = (parsed?.path ?? rawUrl).lowercased()
        if path.hasSuffix(".gif") { return .gif }
        if path.hasSuffix(".jpg") || path.hasSuffix(".jpeg") || path.hasSuffix(".png") || path.hasSuffix(".webp") { return .image }
        if path.hasSuffix(".gifv") || path.hasSuffix(".mp4") { return .video }
        let host = parsed?.host?.lowercased() ?? ""
        if host == "i.redd.it" || host == "preview.redd.it" || host == "i.imgur.com" { return .image }
        return .link
    }

    private static func validThumb(_ thumb: String?) -> String? {
        guard let thumb, !thumb.isEmpty, !["self", "default", "nsfw", "spoiler", "image"].contains(thumb) else { return nil }
        return thumb
    }

    private static func firstPreviewImage(_ d: JsonElement) -> (url: String, width: Int?, height: Int?)? {
        let source = d["preview"]["images"][0]["source"]
        guard let src = source["url"].str() else { return nil }
        return (src, source["width"].int(), source["height"].int())
    }

    /// Reddit's own pre-blurred copy of an NSFW (`nsfw`) or spoiler
    /// (`obfuscated`) preview — the smallest >= 320px wide.
    private static func blurredPreviewUrl(_ d: JsonElement) -> String? {
        let variants = d["preview"]["images"][0]["variants"]
        let v = variants["nsfw"].obj() != nil ? variants["nsfw"] : variants["obfuscated"]
        guard v.obj() != nil else { return nil }
        for r in v["resolutions"].arr() ?? [] where (r["width"].int() ?? 0) >= 320 { return r["url"].str() }
        return v["source"]["url"].str()
    }

    /// ~The smallest preview >= 640px wide, else the largest. Resolutions are ascending.
    private static func medPreviewUrl(_ d: JsonElement) -> String? {
        guard let res = d["preview"]["images"][0]["resolutions"].arr(), !res.isEmpty else { return nil }
        for r in res {
            if let u = r["url"].str(), (r["width"].int() ?? 0) >= 640 { return u }
        }
        return res.last?["url"].str()
    }

    private static func parseGallery(_ d: JsonElement) -> [GalleryImage] {
        guard let galleryData = d["gallery_data"].obj(), let metadata = d["media_metadata"].obj() else { return [] }
        return (galleryData["items"].arr() ?? []).compactMap { item in
            guard let mediaId = item["media_id"].str() else { return nil }
            let s = metadata[mediaId]["s"]
            guard let url = s["u"].str() ?? s["gif"].str() else { return nil }
            return GalleryImage(url: url, width: s["x"].int(), height: s["y"].int())
        }
    }
}
