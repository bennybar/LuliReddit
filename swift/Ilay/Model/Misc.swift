import Foundation

/// A user multireddit (custom feed).
struct Multireddit: Equatable, Sendable, Copyable {
    var name: String
    var displayName: String
    var path: String // /user/{username}/m/{name}/
    var subreddits: [String]
    var descriptionMd: String = ""
    var visibility: String = "private"
    var iconUrl: String? = nil

    static func fromData(_ d: JsonElement) -> Multireddit {
        Multireddit(
            name: d["name"].str() ?? "",
            displayName: d["display_name"].str() ?? d["name"].str() ?? "",
            path: d["path"].str() ?? "",
            subreddits: d["subreddits"].arr()?.compactMap { $0["name"].str()?.nilIfEmpty } ?? [],
            descriptionMd: d["description_md"].str() ?? "",
            visibility: d["visibility"].str() ?? "private",
            iconUrl: d["icon_url"].str()?.nilIfEmpty
        )
    }
}

/// One piece of a flair: some text, or an emoji (an image Reddit hosts).
struct FlairPart: Equatable, Sendable {
    var text: String? = nil
    var emojiUrl: String? = nil
}

private let spaces = Re(#"\s+"#)
private let emojiCode = Re(#":[\w+-]+:"#)

/// A user's (#31) or post's (#56) flair: its text and emoji, in order.
struct UserFlair: Equatable, Sendable {
    let parts: [FlairPart]

    /// Just the words, for where images can't go.
    var text: String { spaces.replace(parts.compactMap(\.text).joined(), with: " ").trimmed }
}

/// A flair from a post or comment ([kind] "author" or "link"): the richtext's
/// text and emoji parts; else the plain text without its :emoji: codes (no
/// image links there). Nil when there's none.
func flairOf(_ d: JsonElement?, _ kind: String) -> UserFlair? {
    let parts: [FlairPart]
    if let rich = d["\(kind)_flair_richtext"].arr(), !rich.isEmpty {
        parts = rich.compactMap { p in
            switch p["e"].str() {
            case "text": return p["t"].str()?.nilIfEmpty.map { FlairPart(text: $0) }
            case "emoji":
                guard let u = p["u"].str(), u.hasPrefix("http") else { return nil }
                return FlairPart(emojiUrl: u)
            default: return nil
            }
        }
    } else {
        let plain = d["\(kind)_flair_text"].str().map { spaces.replace(emojiCode.replace($0, with: " "), with: " ").trimmed }
        parts = plain?.nilIfEmpty.map { [FlairPart(text: $0)] } ?? []
    }
    // Tidy the ends: no leading / trailing spaces around the emoji.
    let tidy = parts.enumerated().map { i, p -> FlairPart in
        guard var t = p.text else { return p }
        if i == 0 { t = t.trimmedStart }
        if i == parts.count - 1 { t = t.trimmedEnd }
        return FlairPart(text: t, emojiUrl: p.emojiUrl)
    }.filter { $0.emojiUrl != nil || $0.text?.isEmpty == false }
    return tidy.isEmpty ? nil : UserFlair(parts: tidy)
}

/// A choice of user flair in a community, and whether you may write your own text in it.
struct UserFlairChoice: Equatable, Sendable {
    let id: String
    let text: String
    let editable: Bool
}

/// Your flair in a community now, and what you can pick from.
struct UserFlairSelector: Equatable, Sendable {
    let currentText: String?
    let currentId: String?
    let choices: [UserFlairChoice]
}

/// A subreddit link flair template.
struct Flair: Equatable, Sendable {
    let id: String
    let text: String

    static func fromJson(_ j: JsonElement) -> Flair {
        Flair(id: j["id"].str() ?? "", text: (j["text"].str() ?? "").trimmed)
    }
}

/// A page of items plus the cursor (`after`) for the next page.
struct Listing<T> {
    var items: [T]
    var after: String? = nil
    var fromCache: Bool = false

    var hasMore: Bool { after?.isEmpty == false }
}

extension Listing: Equatable where T: Equatable {}
extension Listing: Sendable where T: Sendable {}
