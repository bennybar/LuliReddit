import Foundation
import Observation

/// User content filters: hide posts whose title contains a keyword, whose
/// domain or flair matches, or from a filtered subreddit; optionally hide all
/// NSFW posts and collapse AutoModerator comments. Local, per-account,
/// applied across every feed.
struct ContentFilters: Equatable, Sendable, Copyable {
    var keywords: [String] { didSet { keywordRegex = ContentFilters.regex(keywords) } }
    var domains: [String]
    var flairs: [String]
    var subreddits: [String] // lowercase names, without "r/"
    var hideNsfw: Bool
    var collapseAutoMod: Bool

    /// All keywords as one whole-word, any-script pattern ("cat" doesn't hide
    /// "vacation"), compiled once per filter set — it used to be compiled per
    /// keyword per post, each time a feed list was recomputed.
    private var keywordRegex: Re?

    init(keywords: [String] = [], domains: [String] = [], flairs: [String] = [], subreddits: [String] = [], hideNsfw: Bool = false, collapseAutoMod: Bool = false) {
        self.keywords = keywords
        self.domains = domains
        self.flairs = flairs
        self.subreddits = subreddits
        self.hideNsfw = hideNsfw
        self.collapseAutoMod = collapseAutoMod
        keywordRegex = ContentFilters.regex(keywords)
    }

    private static func regex(_ keywords: [String]) -> Re? {
        let words = keywords.filter { !$0.isEmpty }
        if words.isEmpty { return nil }
        let alternatives = words.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        return Re("(?<![\\p{L}\\p{N}])(?:\(alternatives))(?![\\p{L}\\p{N}])", ignoreCase: true)
    }

    static func == (a: ContentFilters, b: ContentFilters) -> Bool {
        a.keywords == b.keywords && a.domains == b.domains && a.flairs == b.flairs && a.subreddits == b.subreddits
            && a.hideNsfw == b.hideNsfw && a.collapseAutoMod == b.collapseAutoMod
    }

    var isEmpty: Bool { keywords.isEmpty && domains.isEmpty && flairs.isEmpty && subreddits.isEmpty && !hideNsfw }

    /// Whether [p] is hidden. A filtered subreddit still shows on its own page
    /// ([viewingSubreddit]) — the filter keeps it out of everything else.
    func hides(_ p: Post, viewingSubreddit: String? = nil) -> Bool {
        if hideNsfw && p.over18 { return true }
        let sub = p.subreddit.lowercased()
        if subreddits.contains(sub), viewingSubreddit?.lowercased() != sub { return true }
        if keywordRegex?.contains(p.title) == true { return true }
        let domain = p.domain.lowercased()
        if domains.contains(where: { !$0.isEmpty && domain.contains($0) }) { return true }
        let flair = (p.linkFlairText ?? "").lowercased()
        if !flair.isEmpty, flairs.contains(where: { !$0.isEmpty && flair.contains($0) }) { return true }
        return false
    }
}

@MainActor @Observable
final class ContentFiltersStore: UserScoped {
    private static let base = "content_filters"
    private static let leadingR = Re(#"^/?r/"#)

    @ObservationIgnored private let prefs: Prefs
    @ObservationIgnored private var key = ContentFiltersStore.base
    private(set) var value = ContentFilters()

    init(prefs: Prefs) { self.prefs = prefs }

    func onUserChanged(_ username: String) {
        key = userScopedKey(prefs, username, ContentFiltersStore.base)
        guard let raw = prefs.getString(key), let m = parseJsonOrNull(raw) else {
            value = ContentFilters()
            return
        }
        func g(_ k: String) -> [String] { m[k].arr()?.compactMap { $0.content() } ?? [] }
        value = ContentFilters(keywords: g("keywords"), domains: g("domains"), flairs: g("flairs"), subreddits: g("subreddits"), hideNsfw: m["hideNsfw"].isTrue(), collapseAutoMod: m["collapseAutoMod"].isTrue())
    }

    private func set(_ next: ContentFilters) {
        value = next
        let json: JsonElement = [
            "keywords": .strings(next.keywords), "domains": .strings(next.domains),
            "flairs": .strings(next.flairs), "subreddits": .strings(next.subreddits),
            "hideNsfw": .bool(next.hideNsfw), "collapseAutoMod": .bool(next.collapseAutoMod),
        ]
        prefs.setString(key, json.encoded())
    }

    /// [type] ∈ keyword | domain | subreddit | flair.
    private func list(_ type: String) -> [String] {
        switch type {
        case "keyword": return value.keywords
        case "domain": return value.domains
        case "subreddit": return value.subreddits
        default: return value.flairs
        }
    }

    private func withList(_ type: String, _ v: [String]) -> ContentFilters {
        value.with {
            switch type {
            case "keyword": $0.keywords = v
            case "domain": $0.domains = v
            case "subreddit": $0.subreddits = v
            default: $0.flairs = v
            }
        }
    }

    func add(_ type: String, _ raw: String) {
        var v = raw.trimmed.lowercased()
        if type == "subreddit" { v = ContentFiltersStore.leadingR.replace(v, with: "") }
        if v.isEmpty || list(type).contains(v) { return }
        set(withList(type, list(type) + [v]))
    }

    func remove(_ type: String, _ v: String) { set(withList(type, list(type).filter { $0 != v })) }
    func setHideNsfw(_ v: Bool) { set(value.with { $0.hideNsfw = v }) }
    func setCollapseAutoMod(_ v: Bool) { set(value.with { $0.collapseAutoMod = v }) }
}
