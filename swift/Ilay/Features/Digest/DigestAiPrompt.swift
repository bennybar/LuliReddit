import Foundation

// The Digest's AI step (docs/digest-spec.md, section 6): one request per build, with the
// posts not judged yet; the reply is parsed leniently. Pure, so both are tested with
// canned replies (no real AI calls in tests), like the Kotlin app's.

/// What the AI is told about the user: their strongest learned words, and what they asked for more or less of.
struct DigestInterests: Sendable {
    var keywords: [String] = []
    var moreTopics: [String] = []
    var lessTopics: [String] = []
    var moreCommunities: [String] = []
    var lessCommunities: [String] = []
}

/// The system and user messages for `posts` (indexed in order). `language`: "" for the posts' own.
func digestAiMessages(_ posts: [Post], interests: DigestInterests, size: DigestSize, overview: Bool, language: String, now: Int) -> (system: String, user: String) {
    let lang = language.isEmpty ? "Write in the language most of the titles are in." : "Write in \(language)."
    let system = "You pick the most important Reddit posts of the last day for one reader, from communities "
        + "they follow. Rate each post's importance to this reader from 1 (skip) to 5 (must read), weighing "
        + "real news and substance over jokes and reposts, and the reader's interests. For each post worth "
        + "reading (2 or more), write \"why\": one plain sentence under 140 characters saying what it is "
        + "and why it matters. "
        + (overview ? "Also write \"overview\": 2 to 4 sentences on what stood out today across these communities. " : "")
        + "\(lang) Reply with only JSON, no other text: "
        + (overview ? "{\"overview\": \"…\", \"items\": [{\"i\": 0, \"importance\": 4, \"why\": \"…\"}]}"
            : "{\"items\": [{\"i\": 0, \"importance\": 4, \"why\": \"…\"}]}")
    var interestsJson = JsonObject()
    func list(_ k: String, _ v: [String]) { if !v.isEmpty { interestsJson[k] = .array(v.map(JsonElement.string)) } }
    list("often_reads", interests.keywords)
    list("more_of", interests.moreTopics)
    list("less_of", interests.lessTopics)
    list("favour_communities", interests.moreCommunities)
    list("less_from_communities", interests.lessCommunities)
    let items: [JsonElement] = posts.enumerated().map { i, p in
        var o: JsonObject = [
            "i": .int(i),
            "community": .string(p.subreddit),
            "title": .string(p.title),
            "score": .int(p.score),
            "comments": .int(p.numComments),
            "age_hours": .int(max((now - p.createdUtc) / 3_600_000, 0)),
        ]
        if let flair = p.linkFlairText, !flair.trimmingCharacters(in: .whitespaces).isEmpty { o["flair"] = .string(flair) }
        if p.isSelf && !p.selftext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { o["text"] = .string(String(p.selftext.prefix(300))) }
        return .object(o)
    }
    let user: JsonObject = [
        "wanted": .string("about \(size.items) posts, at most \(size.perCommunity) from one community"),
        "interests": .object(interestsJson),
        "posts": .array(items),
    ]
    return (system, JsonElement.object(user).encoded())
}

/// The AI's `reply` for `posts`: its verdicts by post id, and the overview. Lenient: a code
/// fence or words around the JSON are fine, unknown indices and broken items are skipped.
/// Nil when there's nothing usable (the build then goes by the numbers).
func parseDigestAi(_ reply: String, posts: [Post]) -> DigestAi? {
    guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end,
          let json = try? AppJson.parse(String(reply[start...end])), json.obj() != nil,
          let list = json["items"].arr() else { return nil }
    var verdicts: [String: AiVerdict] = [:]
    for el in list {
        guard el.obj() != nil, let i = el["i"].int(), posts.indices.contains(i), let importance = el["importance"].int() else { continue }
        let why = (el["why"].str() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        verdicts[posts[i].id] = AiVerdict(importance: min(max(importance, 1), 5), why: why)
    }
    if verdicts.isEmpty && !list.isEmpty { return nil }
    let overview = json["overview"].str()?.trimmingCharacters(in: .whitespacesAndNewlines)
    return DigestAi(overview: overview?.isEmpty == false ? overview : nil, verdicts: verdicts)
}
