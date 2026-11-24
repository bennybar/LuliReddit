import SwiftUI
import XCTest
@testable import Ilay

/// Port of the Flutter build's test/settings_pages_test.dart.
@MainActor
final class SettingsCatalogTests: XCTestCase {
    private let catalog = SettingsCatalog(s: Settings())

    private func titles(section: String) -> [String] { catalog.rows(section: section).map(\.title) }

    func testTheMainPageListsCategoriesNotSettings() {
        let categories = settingsCategories.flatMap { $0 }.map(\.title)
        XCTAssertEqual(categories, [
            "Feed", "Read & hidden", "Digest", "Appearance", "Navigation", "Posts & comments", "Media",
            "Notifications", "Translation", "AI",
            "Data & storage", "Account",
            "About",
        ])
        XCTAssertFalse(categories.contains("Post display"))
    }

    func testSearchFindsSettingsAcrossEveryCategory() {
        func found(_ q: String) -> [String] { catalog.matching(q).map(\.title) }
        XCTAssertEqual(catalog.matching("post display").map(\.section), ["Appearance"])
        XCTAssertTrue(found("post display").contains("Post display"))
        XCTAssertTrue(found("top bar").contains("Top bar"))
        // Case and spaces around it don't matter; subtitles count.
        XCTAssertTrue(found("  COMMENT STYLE ").contains("Comment style"))
        XCTAssertTrue(found("wipes credentials").contains("Clear all data"))
        XCTAssertEqual(found("no such setting anywhere"), [])
        // One from each category.
        for (query, section) in [
            ("posts tab feed", "Feed"), ("content filters", "Read & hidden"), ("accent", "Appearance"),
            ("top bar", "Navigation"), ("comment style", "Posts & comments"),
            ("autoplay", "Media"), ("inbox notifications", "Notifications"), ("second language", "Translation"),
            ("summary style", "AI"), ("clear cache", "Data & storage"), ("giphy", "Account"),
            ("api usage", "Account"), ("licenses", "About"),
        ] {
            XCTAssertTrue(catalog.matching(query).contains { $0.section == section }, query)
        }
    }

    func testACategoryShowsOnlyItsOwnSettings() {
        let feed = titles(section: "Feed")
        XCTAssertTrue(feed.contains("Posts tab feed"))
        XCTAssertFalse(feed.contains("Post display"))
        XCTAssertFalse(feed.contains("Top bar"))
    }

    /// 2.0.108's layout: what drifted into the wrong category is with its kind.
    func testSettingsSitWithTheirKind() {
        var s = Settings()
        s.hideReadPosts = true
        s.trackHistory = true
        let c = SettingsCatalog(s: s)
        func section(_ title: String) -> String? { c.entries.first { $0.title == title }?.section }
        for (title, expected) in [
            ("Track history", "Read & hidden"), ("Dim read posts", "Read & hidden"), ("Hide read posts", "Read & hidden"),
            ("Mark read as you scroll", "Read & hidden"), ("Hide NSFW posts", "Read & hidden"), ("Content filters", "Read & hidden"),
            ("Post display", "Appearance"), ("Floating filter chips", "Appearance"),
            ("Navigation", "Navigation"), ("Top bar", "Navigation"), ("Inbox in Profile", "Navigation"),
            ("Next comment button", "Posts & comments"), ("Open reddit links in Ilay", "Posts & comments"),
            ("Recently visited", "Data & storage"), ("Show API usage instead of search", "Account"),
        ] {
            XCTAssertEqual(section(title), expected, title)
        }
        // A category's rows stay together: its list sections in order, none split apart.
        let sections = c.entries.map(\.section)
        XCTAssertEqual(sections.reduce(into: [String]()) { if $0.last != $1 { $0.append($1) } }, settingsCategories.flatMap { $0 }.map(\.title).filter(sections.contains))
    }

    func testEveryCategoryHasSettings() {
        for (section, setting) in [
            ("Feed", "Keep feed for"),
            ("Read & hidden", "Content filters"),
            ("Navigation", "Top bar"),
            ("Digest", "How Digest works"),
            ("Appearance", "Post display"),
            ("Posts & comments", "Comment style"),
            ("Media", "Blur NSFW media"),
            ("Notifications", "Inbox notifications"),
            ("Translation", "Translation service"),
            ("AI", "OpenAI API key"),
            ("Data & storage", "Recently visited"),
            ("Account", "Clear all data"),
            ("Account", "API usage"),
            ("About", "Content & conduct policy"),
        ] {
            XCTAssertTrue(titles(section: section).contains(setting), section)
        }
        // Every category on the main page has a page of its own, and no row is outside them.
        let categories = Set(settingsCategories.flatMap { $0 }.map(\.title))
        XCTAssertEqual(Set(catalog.entries.map(\.section)), categories)
    }

    func testDroppedSettingsStayOut() {
        for dropped in ["App font", "Dynamic color", "Volume keys move between comments", "Open Reddit app notifications in Ilay", "Bottom bar labels", "Bottom bar outline", "Save media to"] {
            XCTAssertFalse(catalog.entries.contains { $0.title == dropped }, dropped)
        }
    }

    func testRowsFollowTheSettings() {
        var s = Settings()
        XCTAssertFalse(SettingsCatalog(s: s).entries.contains { $0.title == "Azure region" })
        XCTAssertFalse(SettingsCatalog(s: s).entries.contains { $0.title == "Also in subreddits" })
        s.translateService = "azure"
        s.hideReadPosts = true
        XCTAssertTrue(SettingsCatalog(s: s).entries.contains { $0.title == "Azure region" })
        XCTAssertTrue(SettingsCatalog(s: s).entries.contains { $0.title == "Also in subreddits" })
        // The custom endpoint's key is that provider's.
        s.aiUseCustomUrl = true
        XCTAssertTrue(SettingsCatalog(s: s).rows(section: "AI").contains { $0.title == "API key" })
        // Reddit's own settings need the website sign-in.
        XCTAssertFalse(SettingsCatalog(s: s).entries.contains { $0.title == "Reddit account settings" })
        XCTAssertTrue(SettingsCatalog(s: s, secure: SecureFlags(web: true)).entries.contains { $0.title == "Reddit account settings" })
    }

    func testRowIdsAreUnique() {
        var s = Settings()
        s.hideReadPosts = true
        s.redditHomeAllowed = true
        s.forYouFeed = true
        s.blendHome = true
        s.translateService = "azure"
        s.aiUseCustomUrl = true
        s.topBarMode = .full
        let ids = SettingsCatalog(s: s, secure: SecureFlags(web: true)).entries.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}

final class BackupFileTests: XCTestCase {
    /// A file as the Kotlin and Flutter builds write it.
    func testRestoresAFileFromTheOtherBuilds() throws {
        let p = testPrefs()
        let n = try Backup.import(p, """
        {"app":"ilay_for_reddit","version":1,"data":{
          "themeMode":{"t":"i","v":2},
          "blurNsfw":{"t":"b","v":false},
          "textScale":{"t":"d","v":1.25},
          "aiModel":{"t":"s","v":"gpt-5.5"},
          "history_someone":{"t":"l","v":["abc","def"]},
          "seedColor":{"t":"i","v":4284960932}
        }}
        """)
        XCTAssertEqual(n, 6)
        XCTAssertEqual(p.getInt("themeMode"), 2)
        XCTAssertEqual(p.getBool("blurNsfw"), false)
        XCTAssertEqual(p.getDouble("textScale"), 1.25)
        XCTAssertEqual(p.getString("aiModel"), "gpt-5.5")
        XCTAssertEqual(p.getStringList("history_someone"), ["abc", "def"])
        XCTAssertEqual(p.getLong("seedColor"), 4284960932)
    }

    func testTheExportedFileHasNoDraftsOrInternalKeys() throws {
        let p = testPrefs()
        p.setString("draft_reply_t1_x", "private")
        p.setString("__internal", "x")
        p.setBool("amoled", true)
        let root = try AppJson.parse(Backup.export(p))
        XCTAssertEqual(root["app"].str(), "ilay_for_reddit")
        XCTAssertEqual(root["version"].int(), 1)
        XCTAssertEqual(Array(root["data"].obj()!.keys), ["amoled"])
        XCTAssertEqual(root["data"]["amoled"]["t"].str(), "b")
    }

    func testABackupRoundTripsThroughTheFileDocument() throws {
        let p = testPrefs()
        p.setInt("postDisplay", 3)
        p.setStringList("subredditSorts", ["swift|top|week"])
        let doc = BackupDocument(text: Backup.export(p))
        let other = testPrefs()
        XCTAssertEqual(try Backup.import(other, doc.text), 2)
        XCTAssertEqual(other.getInt("postDisplay"), 3)
        XCTAssertEqual(other.getStringList("subredditSorts"), ["swift|top|week"])
    }
}

final class WebSessionHeaderTests: XCTestCase {
    private func cookie(_ name: String, _ value: String, domain: String = ".reddit.com", path: String = "/") -> HTTPCookie {
        HTTPCookie(properties: [.domain: domain, .path: path, .name: name, .value: value])!
    }

    func testNoSessionNoHeader() {
        XCTAssertNil(webSessionHeader([]))
        XCTAssertNil(webSessionHeader([cookie("csrf_token", "x")]))
        XCTAssertNil(webSessionHeader([cookie("reddit_session", "")]))
    }

    func testTheHeaderHoldsWhatAPageRequestWouldSend() {
        let header = webSessionHeader([
            cookie("reddit_session", "s"),
            cookie("loid", "l", domain: "www.reddit.com"),
            cookie("chat", "c", domain: "chat.reddit.com"),
            cookie("other", "o", domain: ".example.com"),
            cookie("sub", "p", path: "/login"),
        ])
        XCTAssertEqual(header, "reddit_session=s; loid=l")
    }

    func testASessionForAnotherSiteDoesntCount() {
        XCTAssertNil(webSessionHeader([cookie("reddit_session", "s", domain: "chat.reddit.com")]))
        XCTAssertNil(webSessionHeader([cookie("reddit_session", "s", domain: ".notreddit.com")]))
    }
}

final class RedditWebHostTests: XCTestCase {
    func testWhatStaysInTheWebView() {
        for url in ["https://www.reddit.com/settings", "https://chat.reddit.com/", "https://reddit.com", "https://x.redditmedia.com/a", "https://www.redditstatic.com/a", "https://redd.it/abc", "about:blank"] {
            XCTAssertTrue(RedditWeb.isReddit(URL(string: url)!), url)
        }
        for url in ["https://example.com", "https://notreddit.com", "https://reddit.com.example.org/"] {
            XCTAssertFalse(RedditWeb.isReddit(URL(string: url)!), url)
        }
    }
}
