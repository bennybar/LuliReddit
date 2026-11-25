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
            bannerUrl: clean(d["banner_background_image"].str()) ?? clean(d["banner_img"].str()),
            keyColor: clean(d["primary_color"].str()) ?? clean(d["key_color"].str()),
            over18: d["over18"].isTrue(),
            userHasFavorited: d["user_has_favorited"].isTrue(),
            userIsSubscriber: d["user_is_subscriber"].bool()
        )
    }
}
