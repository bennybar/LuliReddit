import Foundation

struct RedditUser: Equatable, Sendable, Copyable {
    var name: String
    var iconUrl: String? = nil
    var bannerUrl: String? = nil
    var linkKarma: Int = 0
    var commentKarma: Int = 0
    var createdUtc: Int
    var description: String = ""
    /// You follow this user (subscribed to their profile, u_<name>).
    var following: Bool = false

    static func fromData(_ d: JsonElement) -> RedditUser {
        func clean(_ s: String?) -> String? { s?.nilIfEmpty?.htmlAmpFixed().substringBefore("?") }
        let sub = d["subreddit"]
        return RedditUser(
            name: d["name"].str() ?? "",
            iconUrl: clean(d["icon_img"].str()) ?? clean(sub["icon_img"].str()),
            bannerUrl: clean(sub["banner_img"].str()),
            linkKarma: d["link_karma"].int() ?? 0,
            commentKarma: d["comment_karma"].int() ?? 0,
            createdUtc: (d["created_utc"].long() ?? 0) * 1000,
            description: (sub["public_description"].str() ?? "").trimmed,
            following: sub["user_is_subscriber"].isTrue()
        )
    }
}
