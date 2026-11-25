import Foundation

struct Subreddit: Equatable, Sendable, Copyable {
    var name: String // display_name
    var namePrefixed: String // r/name
    var title: String
    var description: String
    var subscribers: Int
    var iconUrl: String? = nil
    var bannerUrl: String? = nil
    /// The community's own colour ("#0079D3"), for its header without a banner (#257).
    var keyColor: String? = nil
    var over18: Bool = false
    var userHasFavorited: Bool = false
    var userIsSubscriber: Bool? = nil

    static func fromData(_ d: JsonElement) -> Subreddit {
        func clean(_ s: String?) -> String? { s?.nilIfEmpty?.htmlAmpFixed() }
        let name = d["display_name"].str() ?? ""
        return Subreddit(
            name: name,
            namePrefixed: d["display_name_prefixed"].str() ?? "r/\(name)",
            title: (d["title"].str() ?? "").trimmed,
            description: (d["public_description"].str() ?? "").trimmed,
            subscribers: d["subscribers"].int() ?? 0,
            iconUrl: clean(d["community_icon"].str()) ?? clean(d["icon_img"].str()),
            // The banner made for phones first: the desktop one is 4000 px wide and as
            // little as 128 tall, a sliver of it blown up in a phone's header.
            bannerUrl: clean(d["mobile_banner_image"].str()) ?? clean(d["banner_background_image"].str()) ?? clean(d["banner_img"].str()),
            keyColor: clean(d["primary_color"].str()) ?? clean(d["key_color"].str()),
            over18: d["over18"].isTrue(),
            userHasFavorited: d["user_has_favorited"].isTrue(),
            userIsSubscriber: d["user_is_subscriber"].bool()
        )
    }
}

/// Each subreddit's icon as the API gives it (lowercased name → URL). A Reddit Home card,
/// read from Reddit's page, takes its icon from here, so it already shows the URL the full
/// post brings a moment later: no letter turning into an icon, no second load.
struct SubredditIconMap: Equatable {
    static let cap = 2000
    private(set) var icons: [String: String] = [:]
    private var order: [String] = [] // oldest first

    init() {}

    /// From its stored form: "name\turl" per entry, oldest first.
    init(entries: [String]) {
        for e in entries {
            let parts = e.split(separator: "\t", maxSplits: 1)
            if parts.count == 2 { remember(String(parts[0]), String(parts[1])) }
        }
    }

    var entries: [String] { order.compactMap { k in icons[k].map { "\(k)\t\($0)" } } }

    func icon(_ subreddit: String) -> String? { icons[subreddit.lowercased()] }

    /// Remembers `url` for `subreddit`; true if anything changed. With `overwrite: false` a
    /// known one stays (a post's URL wins over the subscription list's).
    @discardableResult
    mutating func remember(_ subreddit: String, _ url: String?, overwrite: Bool = true) -> Bool {
        guard let url, !url.isEmpty, !subreddit.isEmpty else { return false }
        let key = subreddit.lowercased()
        if let old = icons[key] {
            if old == url || !overwrite { return false }
            order.removeAll { $0 == key }
        }
        icons[key] = url
        order.append(key)
        if order.count > Self.cap {
            // Down to 90%: trimmed in steps, not on every new one.
            let drop = order.count - (Self.cap - Self.cap / 10)
            for k in order.prefix(drop) { icons[k] = nil }
            order.removeFirst(drop)
        }
        return true
    }
}

/// The app's `SubredditIconMap`, filled from every parsed post and the subscription list,
/// kept across launches (per device).
final class SubredditIcons: @unchecked Sendable {
    static let shared = SubredditIcons()
    /// "__": a cache, left out of backups.
    static let prefsKey = "__subredditIcons"

    private let lock = NSLock()
    private var map = SubredditIconMap()
    private var prefs: Prefs?
    private var saving = false

    /// Loads the remembered icons (once, at start); any learnt before then are kept.
    func attach(_ prefs: Prefs) {
        let stored = prefs.getStringList(Self.prefsKey) ?? []
        lock.withLock {
            let learnt = map.entries
            map = SubredditIconMap(entries: stored + learnt)
            self.prefs = prefs
        }
    }

    func icon(_ subreddit: String) -> String? { lock.withLock { map.icon(subreddit) } }

    func remember(_ subreddit: String, _ url: String?, overwrite: Bool = true) {
        let save: Bool = lock.withLock {
            guard map.remember(subreddit, url, overwrite: overwrite), prefs != nil, !saving else { return false }
            saving = true
            return true
        }
        // A few seconds later, once for everything learnt by then.
        guard save else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) { [self] in
            let (p, entries) = lock.withLock { () -> (Prefs?, [String]) in
                saving = false
                return (prefs, map.entries)
            }
            p?.setStringList(Self.prefsKey, entries)
        }
    }
}
