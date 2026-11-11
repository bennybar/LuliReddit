import Foundation

// Website sign-in: Reddit's edge refuses the website's search endpoints and
// /by_id (403), so search and posts by id (Reddit Home, Blend) run on
// Reddit's app GraphQL API, as Reddit's own apps and other clients (e.g.
// Hydra) do. Its operations are persisted queries, run by
// name and the hash of the query Reddit already knows.
let GQL_SEARCH_POSTS = "c3d31b88bfa15180fdcd0c8f6f13b8c0e131d0c981c9b9c8a7c537ddd0ed3348"
let GQL_SEARCH_COMMUNITIES = "b58025ad0c98bdb93e9dc1db909accf440573bd7d3a48d2c73a02e96d33f1943"
let GQL_SEARCH_PEOPLE = "db3607c1a7deea8441614a053c5f434f60da0c8c931db952f819a59d534d9743"
let GQL_POSTS_BY_IDS = "b210ea1d852cdc2c25d9bff2d9fa8a406e1a968f36392798812f336694ac27f4"
let GQL_POST_VOTE = "2523ed203f983488aab97d84f12b46910008244b79a61073b419e33ff98cb7e5"
let GQL_COMMENT_VOTE = "a353fb29741128e9346380c4706af0bf59fc5767608ea6848039c57ae0b08fec"
let GQL_POST_SAVE = "96dbe868ad5b00109ed72048a82290abb86f66ff653cde724458b6f7549918f8"
let GQL_COMMENT_SAVE = "2d2a823e0b5053d39de7d319fd8ccf8b87ddf0ab3ad97cfd621d82f376fcf174"
let GQL_SUBREDDIT_INFO = "8c1815b07b762aee3c086cc84306f14b3907018e9ee152046c8e4d08ad4c7b88"
let GQL_OPT_IN_QUARANTINED = "48f2a98b4df9e6ebb67451c25b35be3f6bd597391a1e13984e0c68680dbdf84a"
let GQL_OPT_IN_GATED = "2f5d960d89de68ea1ce9fcac9cbacfd1161c78e990c8bf79668cf03555bd5678"
let GQL_HOME_FEED = "03d0ec0f2674005fe6c9777f952bd063ea2236527794344d4579fec8a669bea0"
let GQL_POPULAR_FEED = "effee8db2d66287bea4e08a3ccf3a5fcb2db245c363be6fe50a3ba01e9962a24"
let GQL_ALL_FEED = "dea8ebf08bd9127a580fd664b9c312e590a195690f5c04c32d60b9370d876fb0"
let GQL_SUBREDDIT_FEED = "45faffc9969af3d623a079e279c9d9a535b6f877809426a9a8ed203f046a23f0"

/// SubredditInfoByName's variables, as Reddit's app sends them.
func subredditInfoVariables(_ name: String) -> JsonObject {
    [
        "subredditName": .string(name),
        "loggedOutIsOptedIn": false,
        "filterGated": true,
        "includeRecapFields": false,
        "includeWelcomePage": true,
        "includeDevvitData": true,
        "includeFeatureVariants": false,
        "includeManualFeatureVariants": false,
        "includeCommunityGuidanceChecklist": false,
    ]
}

/// A mutation's result: throws Reddit's reason (locked, archived…) unless it went through.
func gqlCheckOk(_ result: JsonElement?) throws {
    if result["ok"].bool() == true { return }
    throw AppException(result["fieldErrors"][0]["message"].str() ?? result["errors"][0]["message"].str() ?? "Reddit refused it")
}

/// A post (not an ad or an unavailable one) in GraphQL's results.
func gqlIsPost(_ n: JsonElement?) -> Bool {
    ["SubredditPost", "ProfilePost", "DeletedSubredditPost"].contains(n["__typename"].str() ?? "")
}

/// PostsByIds' variables.
func postsByIdsVariables(_ ids: [String]) -> JsonObject {
    var o = JsonObject()
    for (k, v) in postFlags { o[k] = .bool(v) }
    o["ids"] = .strings(ids)
    return o
}

// The post fragment's switches, as Reddit's app sets them for full posts.
private let postFlags: [(String, Bool)] = [
    ("includeSubredditInPosts", true), ("includeAwards", true), ("includePostStats", true),
    ("includeCurrentUserAwards", false), ("includeStillMediaAltText", true),
    ("includeExtraStillResolutions", true), ("includeExtendedVideoAsset", false),
    ("includePlaybackMp4s", true), ("includeMuxedMp4s", true), ("includeDevvitData", true),
    ("includeCommunityStatus", true), ("includeIsModRemovedContentReadAllowed", true),
    ("includeVideoPlaybackInComments", false), ("includeSubredditBackgroundColor", true),
    ("includeOverlayData", true), ("includeCtaEnrichedPageTitle", true), ("includePlaCards", true),
    ("includePlaCardThumbnail", false), ("includeWebviewPrefetchField", true),
    ("includeAdBrowserDestinationField", true), ("includeCollectionsHeroCard", true),
    ("includeGalleryAdUrl", true), ("includeCtaMediaColor", true),
    ("includeFollowedForNotificationsStatus", true), ("includePredictedRemovalReasons", true),
    ("includeRedditHandleInfo", true), ("includeVerificationStatus", true),
    ("skipModerationInfo", false), ("includeIsReceivingPostReplies", false),
    ("includeIsActiveComments", true), ("includeMediaSynthesis", true),
    ("skipRedditPlayPlaybackMp4s", true), ("includeLinkPreviewTitle", false),
]

private let gqlSorts = ["relevance": "RELEVANCE", "hot": "HOT", "new": "NEW", "top": "TOP", "comments": "COMMENTS"]

/// SearchPosts' variables; [after] is GraphQL's page cursor.
func searchPostsVariables(_ query: String, _ subreddit: String?, _ after: String?, _ sort: String, _ time: String) -> JsonObject {
    var o = JsonObject()
    for (k, v) in postFlags { o[k] = .bool(v) }
    o["query"] = .string(query)
    o["productSurface"] = "android"
    o["pageSize"] = 25
    o["sort"] = .string(gqlSorts[sort] ?? "RELEVANCE")
    if let after { o["afterCursor"] = .string(after) }
    var filters: [JsonElement] = []
    if time != "all" { filters.append(["key": "time_range", "value": .string(time)]) }
    if let subreddit { filters.append(["key": "subreddit_names", "value": .string(subreddit)]) }
    o["filters"] = .array(filters)
    return o
}

/// One kind of search result (posts, communities, authors): its nodes, and the next page's cursor (nil at the end).
func gqlSearch(_ data: JsonObject, _ kind: String) -> (nodes: [JsonObject], next: String?) {
    let list = data["search"]["general"][kind]
    let info = list["pageInfo"]
    let nodes = list["edges"].arr()?.compactMap { $0["node"].obj() } ?? []
    return (nodes, info["hasNextPage"].bool() == false ? nil : info["endCursor"].str())
}

/// getPosts' feed as Reddit's app loads it ([subreddit] nil: the frontpage):
/// operation, hash and variables, or nil for a feed the app has no
/// equivalent of (combined subreddits, a+b).
func gqlFeedQuery(_ subreddit: String?, _ sort: PostSort, _ time: TopTime, _ after: String?) -> (operation: String, hash: String, variables: JsonObject)? {
    let operation: String
    let hash: String
    if subreddit == nil {
        (operation, hash) = ("HomeFeedSdui", GQL_HOME_FEED)
    } else if subreddit!.lowercased() == "popular" {
        (operation, hash) = ("PopularFeedSdui", GQL_POPULAR_FEED)
    } else if subreddit!.lowercased() == "all" {
        (operation, hash) = ("AllFeedSdui", GQL_ALL_FEED)
    } else if subreddit!.contains("+") {
        return nil
    } else {
        (operation, hash) = ("SubredditFeedSdui", GQL_SUBREDDIT_FEED)
    }
    var o = JsonObject()
    if operation == "SubredditFeedSdui" { o["subredditName"] = .of(subreddit) }
    o["sort"] = .string(sort.path.uppercased())
    if sort.needsTime { o["time"] = .string(time.param.uppercased()) }
    // A feed's cursor is the last post's fullname, base64-encoded, so the
    // listing's `after` stays a plain t3_ fullname like the website's.
    if let after { o["after"] = .string(Data(after.utf8).base64EncodedString()) }
    return (operation, hash, o)
}

/// The post ids (t3_…) on a page of a feed. The feed itself is server-driven
/// UI: each post comes as cells named by its id, among ads and other cells.
func gqlFeedPostIds(_ data: JsonObject) -> [String] {
    (data.values.first["elements"]["edges"].arr() ?? []).compactMap { e -> String? in
        guard let n = e["node"].obj() else { return nil }
        if let ad = n["adPayload"], ad != .null { return nil }
        guard let id = n["groupId"].str() ?? n["id"].str(), id.hasPrefix("t3_") else { return nil }
        return id
    }.uniqued()
}

// "2026-10-04T00:26:11.575000+0000": up to 9 fraction digits, offset with or without a colon.
private let gqlTime = Re(#"^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)(?:\.\d{0,9})?(?:Z|([+-])(\d\d):?(\d\d))$"#)

/// A GraphQL time in epoch seconds, or 0.
func gqlSeconds(_ iso: String?) -> Double {
    guard let iso, let m = gqlTime.firstMatch(iso) else { return 0 }
    var t = tm()
    t.tm_year = Int32(m.groups[1])! - 1900
    t.tm_mon = Int32(m.groups[2])! - 1
    t.tm_mday = Int32(m.groups[3])!
    t.tm_hour = Int32(m.groups[4])!
    t.tm_min = Int32(m.groups[5])!
    t.tm_sec = Int32(m.groups[6])!
    let offset = (Int(m.groups[8]) ?? 0) * 3600 + (Int(m.groups[9]) ?? 0) * 60
    return Double(timegm(&t) - (m.groups[7] == "-" ? -offset : offset))
}

/// A community search result in the shape Subreddit.fromData reads.
func gqlSubredditData(_ n: JsonObject) -> JsonElement {
    let name = n["name"].str() ?? ""
    return [
        "display_name": .string(name),
        "display_name_prefixed": .string(n["prefixedName"].str() ?? "r/\(name)"),
        "subscribers": .int(n["subscribersCount"].int() ?? 0),
        "public_description": .string(n["publicDescriptionText"].str() ?? ""),
        "icon_img": .of(n["styles"]["icon"].str() ?? n["styles"]["legacyIcon"]["url"].str()),
        "over18": .bool(n["isNsfw"].bool() == true), // for "Hide NSFW posts" (#94), when Reddit sends it
    ]
}

/// A people search result in the shape RedditUser.fromData reads (search only has total karma).
func gqlUserData(_ n: JsonObject) -> JsonElement {
    [
        "name": .of(n["name"].str()),
        "link_karma": .int(n["karma"]["total"].int() ?? 0),
        "comment_karma": 0,
        "created_utc": .double(gqlSeconds(n["profile"]["createdAt"].str())),
        // The avatar, as Reddit's app reads a Redditor's: its icon, else the Snoovatar, else the profile's styles (#105).
        // SearchPeople sends the avatar only in sizes, icon_24…icon_288 (#168).
        "icon_img": .of(n["icon"]["url"].str() ?? n["snoovatarIcon"]["url"].str() ?? n["profile"]["styles"]["icon"].str() ?? n["icon_128"]["url"].str()),
    ]
}

/// A GraphQL post (search, PostsByIds) in the shape Post.fromData reads
/// (Reddit's listing JSON): what a card shows, with its media. Opening it
/// loads the full post.
func gqlPostData(_ n: JsonObject) -> JsonObject {
    let fullname = n["id"].str() ?? ""
    let id = fullname.removePrefix("t3_")
    let community: JsonElement? = n["subreddit"].obj() != nil ? n["subreddit"] : n["profile"].obj() != nil ? n["profile"] : nil
    let sub = community["name"].str() ?? ""
    let url = n["url"].str() ?? ""
    let host = URL(string: url)?.host ?? ""
    let isSelf = n["isSelfPost"].bool() == true
    // The image (a gallery's first) at each size, smallest first.
    typealias Size = (url: String, width: Int?, height: Int?)
    func size(_ s: JsonElement?) -> Size? {
        s["url"].str().map { ($0, s["dimensions"]["width"].int(), s["dimensions"]["height"].int()) }
    }
    let still = n["media"]["still"]
    let asset = n["gallery"]["items"][0]["media"]
    var sizes: [Size] = []
    if still.obj() != nil {
        for k in ["small", "medium", "large", "midlarge480", "xlarge", "xlargePlus720", "xxlarge", "xxxlarge", "source"] {
            if let s = size(still[k]) { sizes.append(s) }
        }
    }
    if asset.obj() != nil {
        for k in ["small", "medium", "large", "xlarge", "xxlarge", "xxxlarge"] {
            if let s = size(asset[k]) { sizes.append(s) }
        }
        if let u = asset["url"].str() { sizes.append((u, asset["width"].int(), asset["height"].int())) }
    }
    var seenSizes = Set<String>()
    sizes = sizes.filter { seenSizes.insert($0.url).inserted }
    let media = n["media"]
    let hls = media["streaming"]["hlsUrl"].str()
    let gifMp4 = (media["animated"]["mp4_source"]["url"] ?? media["animated"]["mp4_xxxlarge"]["url"]).str()
    // Every gallery image, as gallery_data + media_metadata.
    let galleryItems = n["gallery"]["items"].arr()?.compactMap { item -> JsonElement? in
        let m = item["media"]
        return m.obj() != nil && m["url"].str() != nil ? m : nil
    } ?? []
    let root = n["crosspostRoot"]["post"].obj()
    let icon = community["styles"]["icon"].str() ?? community["styles"]["legacyIcon"]["url"].str()

    var o: JsonObject = [
        "id": .string(id),
        "name": .string(fullname),
        "title": .string(n["postTitle"].str() ?? n["title"].str() ?? ""),
        "author": .string(n["authorInfo"]["name"].str() ?? "[deleted]"),
        "subreddit": .string(sub),
        "subreddit_name_prefixed": .string(community["prefixedName"].str() ?? "r/\(sub)"),
        "score": .int(n["score"].int() ?? 0),
        "num_comments": .int(n["commentCount"].int() ?? 0),
        "created_utc": .double(gqlSeconds(n["createdAt"].str())),
        "permalink": .string(n["permalink"].str() ?? "/r/\(sub)/comments/\(id)/"),
        "url": .string(url),
        "domain": .string(isSelf ? "self.\(sub)" : host),
        "is_self": .bool(isSelf),
        "is_video": .bool(host == "v.redd.it"),
        "selftext": .string(n["content"]["markdown"].str() ?? ""),
        "over_18": .bool(n["isNsfw"].bool() == true),
        "spoiler": .bool(n["isSpoiler"].bool() == true),
        "stickied": .bool(n["isStickied"].bool() == true),
        "locked": .bool(n["isLocked"].bool() == true),
        "saved": .bool(n["isSaved"].bool() == true),
    ]
    // Left out when the response doesn't carry it: For You reads a missing ratio as neutral, not 0.
    if let ratio = n["upvoteRatio"].double() { o["upvote_ratio"] = .double(ratio) }
    switch n["voteState"].str() {
    case "UP": o["likes"] = true
    case "DOWN": o["likes"] = false
    default: o["likes"] = .null
    }
    o["link_flair_text"] = .of(n["flair"]["text"].str())
    o["thumbnail"] = .string(sizes.first?.url ?? (isSelf ? "self" : "default"))
    if !sizes.isEmpty {
        o["post_hint"] = host == "i.redd.it" ? "image" : host == "v.redd.it" ? "hosted:video" : "link"
    }
    if let icon { o["sr_detail"] = ["icon_img": .string(icon.substringBefore("?"))] }
    if let hls {
        o["media"] = ["reddit_video": ["hls_url": .string(hls), "is_gif": .bool(media["streaming"]["isGif"].bool() == true)]]
    }
    if !galleryItems.isEmpty {
        o["gallery_data"] = ["items": .array(galleryItems.indices.map { ["media_id": .string("g\($0)")] })]
        var meta = JsonObject()
        for (i, m) in galleryItems.enumerated() {
            meta["g\(i)"] = ["s": ["u": .of(m["url"].str()), "x": .of(m["width"].int()), "y": .of(m["height"].int())]]
        }
        o["media_metadata"] = .object(meta)
    }
    if let root, root["id"].str() != fullname { o["crosspost_parent_list"] = [.object(gqlPostData(root))] }
    if !sizes.isEmpty || gifMp4 != nil {
        var preview = JsonObject()
        if !sizes.isEmpty {
            func image(_ s: Size) -> JsonElement { ["url": .string(s.url), "width": .of(s.width), "height": .of(s.height)] }
            preview["images"] = [["source": image(sizes.last!), "resolutions": .array(sizes.map(image))]]
        }
        if let gifMp4 { preview["reddit_video_preview"] = ["fallback_url": .string(gifMp4)] }
        o["preview"] = .object(preview)
    }
    return o
}
