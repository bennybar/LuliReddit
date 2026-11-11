import XCTest
@testable import Ilay

/// Proves the Swift app reads what the Flutter app wrote. These write exactly
/// what shared_preferences_foundation writes on iOS: `UserDefaults.set` with
/// a Bool, an integer, a Double, a String and an array of Strings, under
/// `flutter.<key>`. Then a binary-plist round trip (the file on disk), which is
/// where a Bool or a whole-number Double could lose its type.
final class FlutterPrefsCompatTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "ilay.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    private func fromDisk(_ values: [String: Any]) throws -> Prefs {
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        let back = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
        defaults.setPersistentDomain(back, forName: suite)
        return Prefs(defaults: defaults)
    }

    func testReadsEveryTypeFromDisk() throws {
        let p = try fromDisk([
            "flutter.aBool": true,
            "flutter.falseBool": false,
            "flutter.anInt": 42,
            "flutter.oneInt": 1,
            "flutter.zeroInt": 0,
            "flutter.bigInt": 0xFF6750A4,
            "flutter.negative": -1,
            "flutter.aDouble": 1.25,
            "flutter.wholeDouble": 1.0,
            "flutter.aString": "hello",
            "flutter.aList": ["a", "b"],
            "flutter.emptyList": [String](),
            "notFlutter": "ignored",
        ])
        XCTAssertEqual(p.getBool("aBool"), true)
        XCTAssertEqual(p.getBool("falseBool"), false)
        XCTAssertEqual(p.getInt("anInt"), 42)
        XCTAssertEqual(p.getInt("oneInt"), 1)
        XCTAssertEqual(p.getInt("zeroInt"), 0)
        XCTAssertEqual(p.getLong("bigInt"), 0xFF6750A4)
        XCTAssertEqual(p.getLong("negative"), -1)
        XCTAssertEqual(p.getDouble("aDouble"), 1.25)
        XCTAssertEqual(p.getDouble("wholeDouble"), 1.0)
        XCTAssertEqual(p.getString("aString"), "hello")
        XCTAssertEqual(p.getStringList("aList"), ["a", "b"])
        XCTAssertEqual(p.getStringList("emptyList"), [])
        XCTAssertNil(p.getString("notFlutter"), "only flutter.-prefixed keys are the app's")
        XCTAssertFalse(p.keys().contains("notFlutter"))
    }

    func testAWrongTypedValueReadsAsAbsent() throws {
        let p = try fromDisk(["flutter.b": true, "flutter.i": 1, "flutter.d": 1.0, "flutter.s": "1", "flutter.l": ["1"]])
        XCTAssertNil(p.getInt("b"), "a Bool isn't an int")
        XCTAssertNil(p.getDouble("b"))
        XCTAssertNil(p.getBool("i"), "1 isn't true")
        XCTAssertNil(p.getDouble("i"))
        XCTAssertNil(p.getInt("d"))
        XCTAssertNil(p.getBool("d"))
        XCTAssertNil(p.getInt("s"))
        XCTAssertNil(p.getString("l"))
        XCTAssertNil(p.getStringList("s"))
    }

    func testWhatItWritesIsWhatFlutterReads() {
        let p = Prefs(defaults: defaults)
        p.setBool("b", true)
        p.setInt("i", 7)
        p.setDouble("d", 2.0)
        p.setString("s", "x")
        p.setStringList("l", ["y"])
        XCTAssertEqual(defaults.object(forKey: "flutter.s") as? String, "x")
        XCTAssertEqual(defaults.object(forKey: "flutter.l") as? [String], ["y"])
        XCTAssertEqual(p.getBool("b"), true)
        XCTAssertEqual(p.getInt("i"), 7)
        XCTAssertEqual(p.getDouble("d"), 2.0)
        XCTAssertEqual(p.all(), ["b": .bool(true), "i": .int(7), "d": .double(2.0), "s": .string("x"), "l": .list(["y"])])
        p.remove("s")
        XCTAssertFalse(p.contains("s"))
        XCTAssertNil(defaults.object(forKey: "flutter.s"))
    }

    func testUserScopedKeyNaming() throws {
        let p = try fromDisk([:])
        XCTAssertEqual(userScopedKey(p, "", "history"), "history", "logged out: the bare key")
        XCTAssertEqual(userScopedKey(p, "BobSmith", "history"), "history_bobsmith", "lowercased")
    }

    func testUserScopedKeyMovesPreMultiAccountData() throws {
        let p = try fromDisk(["flutter.history": ["one"], "flutter.content_filters": "{}", "flutter.interest_weights_bob": "kept", "flutter.interest_weights": "old"])
        XCTAssertEqual(userScopedKey(p, "Bob", "history"), "history_bob")
        XCTAssertEqual(p.getStringList("history_bob"), ["one"])
        XCTAssertFalse(p.contains("history"), "the bare key moves, once")
        _ = userScopedKey(p, "Bob", "content_filters")
        XCTAssertEqual(p.getString("content_filters_bob"), "{}")
        _ = userScopedKey(p, "Bob", "interest_weights")
        XCTAssertEqual(p.getString("interest_weights_bob"), "kept", "an account's own data isn't overwritten")
        XCTAssertEqual(p.getString("interest_weights"), "old")
    }

    @MainActor
    func testSettingsFromFlutterPrefs() throws {
        let p = try fromDisk([
            "flutter.themeMode": 2,
            "flutter.amoled": true,
            "flutter.textScale": 1.2,
            "flutter.seedColor": -10_029_884, // a Dart signed ARGB
            "flutter.defaultSort": 3,
            "flutter.postDisplay": 1,
            "flutter.commentStyle": 2,
            "flutter.swipePostStart": "hideSub",
            "flutter.swipeCommentEnd": "nonsense",
            "flutter.subredditSorts": ["pics|top|week", "bad|row", "x|nope|day"],
            "flutter.collapseBelowScore": -5,
            "flutter.topBarMode": 2,
            "flutter.navStyle": 9,
            "flutter.forYouDiscovery": -9,
            "flutter.aiModel": "gpt-x",
            // Dropped on iOS, their keys stay untouched: never read, never reused.
            "flutter.useDynamicColor": true,
            "flutter.appFont": "jakarta",
            "flutter.volumeKeyNavigation": true,
            "flutter.redditAppNotifications": true,
        ])
        let s = SettingsStore(prefs: p).value
        XCTAssertEqual(s.themeMode, .dark)
        XCTAssertTrue(s.amoled)
        XCTAssertEqual(s.textScale, 1.2)
        XCTAssertEqual(s.seedColor, (-10_029_884) & 0xFFFF_FFFF)
        XCTAssertEqual(s.defaultSort, .top)
        XCTAssertEqual(s.postDisplay, .card)
        XCTAssertEqual(s.commentStyle, .calm)
        XCTAssertTrue(s.calmComments)
        XCTAssertEqual(s.swipePostStart, .hideSub)
        XCTAssertEqual(s.swipeCommentEnd, .downvote)
        XCTAssertEqual(s.subredditSorts, ["pics": SubredditSort(sort: .top, time: .week)])
        XCTAssertEqual(s.collapseBelowScore, -5)
        XCTAssertEqual(s.topBarMode, .expandable, "old indexes clamp")
        XCTAssertEqual(s.navStyle, 2)
        XCTAssertEqual(s.forYouDiscovery, -2)
        XCTAssertEqual(s.aiModel, "gpt-x")
        XCTAssertEqual(p.getBool("useDynamicColor"), true)
    }

    @MainActor
    func testSettingsDefaultsWithNothingStored() throws {
        let s = SettingsStore(prefs: try fromDisk([:])).value
        XCTAssertEqual(s.postDisplay, .calm)
        XCTAssertEqual(s.topBarMode, .expandable)
        XCTAssertEqual(s.seedColor, 0xFF6750A4)
        XCTAssertEqual(s.defaultCommentSort, "confidence")
        XCTAssertEqual(s.aiMaxChars, 100_000)
        XCTAssertNil(s.collapseBelowScore)
    }

    @MainActor
    func testSettingsPersistUnderTheSameKeysAndTypes() {
        let p = Prefs(defaults: defaults)
        let store = SettingsStore(prefs: p)
        var changes = 0
        store.onChange = { _, _ in changes += 1 }
        store.setThemeMode(.light)
        store.setTextScale(1.1)
        store.setSwipeAction("swipePostEnd", .hide)
        store.setSubredditSort("Pics", SubredditSort(sort: .newest, time: .all))
        store.setCollapseBelowScore(3)
        store.setCollapseBelowScore(nil)
        XCTAssertEqual(p.getInt("themeMode"), 1)
        XCTAssertEqual(p.getDouble("textScale"), 1.1)
        XCTAssertEqual(p.getString("swipePostEnd"), "hide")
        XCTAssertEqual(p.getStringList("subredditSorts"), ["pics|new|all"])
        XCTAssertFalse(p.contains("collapseBelowScore"))
        XCTAssertEqual(changes, 6)
        XCTAssertEqual(SettingsStore(prefs: p).value, store.value)
    }

    /// Dim read posts → Off (#106) is its own key: `dimReadTextOnly` keeps its meaning.
    @MainActor
    func testDimReadOffKeepsTheTextOnlyChoice() {
        XCTAssertEqual(Settings().readDim, .card)
        let p = Prefs(defaults: defaults)
        let store = SettingsStore(prefs: p)
        store.setReadDim(.text)
        XCTAssertEqual(store.value.readDim, .text)
        store.setReadDim(.off)
        XCTAssertEqual(store.value.readDim, .off)
        XCTAssertEqual(p.getBool("dimRead"), false)
        XCTAssertEqual(p.getBool("dimReadTextOnly"), true)
        XCTAssertEqual(SettingsStore(prefs: p).value.readDim, .off)
        store.setReadDim(.card)
        XCTAssertEqual(SettingsStore(prefs: p).value.readDim, .card)
        XCTAssertEqual(p.getBool("dimReadTextOnly"), false)
    }

    @MainActor
    func testFrontpageModesExcludeEachOther() {
        let store = SettingsStore(prefs: Prefs(defaults: defaults))
        store.setForYouFeed(true)
        store.setRedditHomeFeed(true)
        XCTAssertFalse(store.value.forYouFeed)
        XCTAssertTrue(store.value.redditHomeFeed)
        store.setForYouFeed(true)
        XCTAssertFalse(store.value.redditHomeFeed)
        store.setRedditHomeAllowed(true)
        store.setRedditHomeFeed(true)
        store.setRedditHomeAllowed(false)
        XCTAssertFalse(store.value.redditHomeFeed)
    }

    @MainActor
    func testPerAccountStoresReadFlutterFormats() throws {
        let p = try fromDisk([
            "flutter.history_bob": [#"{"id":"a","sub":"pics","title":"T","permalink":"/p","ts":1700000000000}"#, "not json", #"{"id":"b"}"#],
            "flutter.content_filters_bob": #"{"keywords":["cat"],"domains":["x.com"],"flairs":[],"subreddits":["politics"],"hideNsfw":true,"collapseAutoMod":true}"#,
            "flutter.offline_threads_bob": #"[{"id":"p1","sub":"pics","title":"Saved","at":1700000000000}]"#,
            "flutter.thread_visits_bob": #"{"old":1,"new":2}"#,
            "flutter.recent_subreddits_bob": [#"{"name":"pics","prefixed":"r/pics","icon":null,"members":5,"ts":9}"#, #"{"name":"noPrefix"}"#],
            "flutter.saved_searches_bob": #"[{"q":"cats","sr":"pics","sort":"top","t":"week"},{"q":"dogs"}]"#,
            "flutter.hiddenPostIds_bob": ["t3_a:\(nowMillis())", "t3_old:1", "garbage", ":5"],
            "flutter.interest_weights_bob": #"{"_ts":\#(nowMillis()),"pics":3.5,"news":-2}"#,
            "flutter.keyword_weights_bob": #"{"_ts":\#(nowMillis()),"_lu":{"cats":20000},"cats":2.5}"#,
            "flutter.fy_impressions_bob": #"{"p1":[2.0,\#(nowMillis())],"legacy":3}"#,
            "flutter.fy_substats_bob": #"{"_ts":\#(nowMillis()),"pics":[10.0,2.0]}"#,
            "flutter.fy_explicit_bob": #"{"subs":{"pics":1},"topics":{"cats":-1}}"#,
            "flutter.fy_docfreq_bob": #"{"_ts":\#(nowMillis()),"_n":60.0,"cats":4.0}"#,
            "flutter.muted_subs_bob": ["pics", "pics", "news"],
        ])
        let history = HistoryStore(prefs: p)
        history.onUserChanged("Bob")
        XCTAssertEqual(history.state.map(\.id), ["a", "b"])
        XCTAssertEqual(history.state[0].viewedAt, 1_700_000_000_000)
        XCTAssertTrue(history.contains("a"))
        let filters = ContentFiltersStore(prefs: p)
        filters.onUserChanged("bob")
        XCTAssertEqual(filters.value.keywords, ["cat"])
        XCTAssertTrue(filters.value.hideNsfw && filters.value.collapseAutoMod)
        let (client, _, _, _) = stubClient([:])
        let offline = OfflineStore(prefs: p, repo: RedditRepository(client: client), filesDir: tempDir())
        offline.onUserChanged("bob")
        XCTAssertEqual(offline.state, [OfflineThread(id: "p1", subreddit: "pics", title: "Saved", savedAt: 1_700_000_000_000)])
        let settings = SettingsStore(prefs: p)
        let visits = ThreadVisits(prefs: p, settings: settings)
        visits.onUserChanged("bob")
        XCTAssertEqual(visits.lastVisit("new"), 2)
        let recent = RecentSubreddits(prefs: p, byVisits: { false })
        recent.onUserChanged("bob")
        XCTAssertEqual(recent.state.map(\.name), ["pics"])
        XCTAssertEqual(recent.state[0].visits, 1, "saved before visits were counted: once")
        let saved = SavedSearches(prefs: p, username: { "bob" })
        saved.refresh()
        XCTAssertEqual(saved.items.map(\.query), ["cats", "dogs"])
        XCTAssertEqual(saved.items[1].sort, "relevance")
        XCTAssertEqual(saved.items[0].key, "pics|cats|top|week")
        let hidden = ExpiringIds(prefs: p, baseKey: "hiddenPostIds") { 86_400_000 }
        hidden.onUserChanged("bob")
        XCTAssertEqual(hidden.ids, ["t3_a"], "the expired and malformed rows go")
        let interest = InterestStore(prefs: p, trackHistory: { true })
        interest.load("bob")
        XCTAssertEqual(interest.weightFor("PICS"), 3.5)
        XCTAssertEqual(interest.weightFor("news"), -2)
        XCTAssertEqual(interest.top(5), ["pics"])
        let keywords = KeywordStore(prefs: p, trackHistory: { true })
        keywords.load("bob")
        XCTAssertEqual(keywords.value["cats"], 2.5)
        XCTAssertEqual(keywords.topKeywordIn("about cats"), "cats")
        let impressions = ImpressionStore(prefs: p, trackHistory: { true })
        impressions.load("bob")
        XCTAssertEqual(impressions.count("p1"), 2.0, accuracy: 0.01)
        XCTAssertEqual(impressions.count("legacy"), 3.0, accuracy: 0.01)
        let stats = SubStatsStore(prefs: p, trackHistory: { true })
        stats.load("bob")
        XCTAssertEqual(stats.value["pics"]!.seen, 10.0, accuracy: 0.01)
        let explicit = ExplicitPrefsStore(prefs: p)
        explicit.load("bob")
        XCTAssertEqual(explicit.value.subs["pics"], 1)
        XCTAssertEqual(explicit.value.topics["cats"], -1)
        let docFreq = DocFreqStore(prefs: p)
        docFreq.load("bob")
        XCTAssertEqual(docFreq.state["cats"]!, 4.0, accuracy: 0.01)
        XCTAssertNotEqual(docFreq.idf("rareword"), 1.0, "enough titles seen for weights")
        let muted = MutedSubsStore(prefs: p)
        muted.load("bob")
        XCTAssertEqual(muted.value, ["pics", "news"])
    }

    // #148: History shows the newest 500, but posts read longer ago still count as
    // read, across restarts; removing or clearing forgets them too.
    @MainActor
    func testReadIdsOutliveTheHistoryCap() {
        let p = Prefs(defaults: defaults)
        p.setStringList("history_bob", [#"{"id":"old","sub":"pics","title":"T","permalink":"/p","ts":1}"#])
        let h = HistoryStore(prefs: p)
        h.onUserChanged("bob")
        XCTAssertTrue(h.contains("old"), "seeded from history")
        for i in 0..<700 { h.markViewed(post("p\(i)", title: "T")) }
        XCTAssertEqual(h.state.count, 500)
        XCTAssertTrue(h.contains("p0") && h.contains("old"))
        XCTAssertTrue(p.getString("readIds_bob")!.hasPrefix("p699:"), "same format as Android")
        let again = HistoryStore(prefs: p)
        again.onUserChanged("bob")
        XCTAssertTrue(again.contains("p0") && again.contains("p699"))
        again.removeViewed("p0")
        XCTAssertFalse(again.contains("p0"))
        again.clearOlderThan(60_000)
        XCTAssertFalse(again.contains("old"), "legacy entries count as old")
        XCTAssertTrue(again.contains("p1"))
        again.clear()
        XCTAssertFalse(again.contains("p1"))
    }

    // #154: Undo puts a removed entry back where it was, read again.
    @MainActor
    func testRestorePutsAHistoryEntryBackInPlace() {
        let h = HistoryStore(prefs: Prefs(defaults: defaults))
        h.onUserChanged("bob")
        for id in ["a", "b", "c"] { h.markViewed(post(id, title: "T")); usleep(2000) }
        let b = h.state.first { $0.id == "b" }!
        h.removeViewed("b")
        XCTAssertFalse(h.contains("b"))
        h.restore(b)
        h.restore(b)
        XCTAssertEqual(h.state.map(\.id), ["c", "b", "a"])
        XCTAssertTrue(h.contains("b"))
    }

    // #159: History's day headers and grouping.
    func testHistoryDayLabelsAndGroups() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 15))!
        func day(_ back: Int) -> Date { cal.startOfDay(for: cal.date(byAdding: .day, value: -back, to: now)!) }
        let us = Locale(identifier: "en_US")
        XCTAssertEqual(historyDayLabel(day(0), now: now, calendar: cal, locale: us), "Today")
        XCTAssertEqual(historyDayLabel(day(1), now: now, calendar: cal, locale: us), "Yesterday")
        XCTAssertEqual(historyDayLabel(day(2), now: now, calendar: cal, locale: us), "Monday")
        XCTAssertEqual(historyDayLabel(day(7), now: now, calendar: cal, locale: us), "Wed, Nov 4")
        XCTAssertEqual(historyDayLabel(cal.date(from: DateComponents(year: 2025, month: 12, day: 31))!, now: now, calendar: cal, locale: us), "Dec 31, 2025")
        XCTAssertEqual(historyDayLabel(nil, now: now, calendar: cal, locale: us), "Earlier")
        let ms = { (d: Date) in Int(d.timeIntervalSince1970 * 1000) + 3_600_000 }
        let entries = [
            HistoryEntry(id: "a", subreddit: "s", title: "", permalink: "", viewedAt: ms(day(0))),
            HistoryEntry(id: "b", subreddit: "s", title: "", permalink: "", viewedAt: ms(day(0))),
            HistoryEntry(id: "c", subreddit: "s", title: "", permalink: "", viewedAt: ms(day(3))),
            HistoryEntry(id: "d", subreddit: "s", title: "", permalink: "", viewedAt: 0),
        ]
        XCTAssertEqual(historyDays(entries, calendar: cal).map { $0.entries.map(\.id) }, [["a", "b"], ["c"], ["d"]])
    }

    @MainActor
    func testStoresWriteFlutterFormats() {
        let p = Prefs(defaults: defaults)
        let history = HistoryStore(prefs: p)
        history.onUserChanged("bob")
        history.markViewed(post("a", title: "T"))
        let row = json(p.getStringList("history_bob")![0])
        XCTAssertEqual(row["id"].str(), "a")
        XCTAssertEqual(row["sub"].str(), "pics")
        XCTAssertNotNil(row["ts"].long())

        let filters = ContentFiltersStore(prefs: p)
        filters.onUserChanged("bob")
        filters.add("subreddit", " /R/Pics ".replacingOccurrences(of: "R", with: "r"))
        filters.add("subreddit", "pics")
        XCTAssertEqual(filters.value.subreddits, ["pics"])
        XCTAssertEqual(json(p.getString("content_filters_bob")!)["subreddits"], ["pics"])

        let hidden = ExpiringIds(prefs: p, baseKey: "dismissedPosts") { 86_400_000 }
        hidden.onUserChanged("bob")
        hidden.add("t3_x")
        XCTAssertTrue(p.getStringList("dismissedPosts_bob")![0].hasPrefix("t3_x:"))
        hidden.remove("t3_x")
        XCTAssertEqual(p.getStringList("dismissedPosts_bob"), [])

        let stats = SubStatsStore(prefs: p, trackHistory: { true }, base: "fy_typestats")
        stats.load("bob")
        stats.impression("image")
        XCTAssertEqual(json(p.getString("fy_typestats_bob")!)["image"][0].double(), 1.0)

        let metrics = ForYouMetrics(prefs: p, trackHistory: { true })
        metrics.load("bob")
        metrics.count("impr.primary", 2)
        XCTAssertEqual(metrics.totals()["impr.primary"], 2)
        XCTAssertEqual(metrics.discoveryAppetite(), 1.0)
        let again = ForYouMetrics(prefs: p, trackHistory: { true })
        again.load("bob")
        XCTAssertEqual(again.totals()["impr.primary"], 2)
    }

    /// `nsfw` is optional both ways: older entries (and older app versions, which ignore it)
    /// read as shown; it's written only when set, the same shape as the Kotlin app.
    @MainActor
    func testHistoryNsfwFlagRoundTrips() throws {
        let p = try fromDisk(["flutter.history_bob": [#"{"id":"old","sub":"pics","title":"T","permalink":"/p","ts":1}"#]])
        let history = HistoryStore(prefs: p)
        history.onUserChanged("bob")
        XCTAssertFalse(history.state[0].nsfw, "no field: unknown, shown")
        history.markViewed(post("n", nsfw: true))
        history.markViewed(post("s"))
        let rows = p.getStringList("history_bob")!.map(json)
        XCTAssertEqual(rows.map { $0["id"].str() }, ["s", "n", "old"])
        XCTAssertNil(rows[0]["nsfw"], "SFW entries keep the old shape")
        XCTAssertEqual(rows[1]["nsfw"].bool(), true)
        XCTAssertNil(rows[2]["nsfw"])
        let again = HistoryStore(prefs: p)
        again.onUserChanged("bob")
        XCTAssertEqual(again.state.map(\.nsfw), [false, true, false])
    }

    @MainActor
    func testThreadVisitsEvictTheOldestAndRememberOrderAcrossRestarts() {
        let p = Prefs(defaults: defaults)
        let settings = SettingsStore(prefs: p)
        let v = ThreadVisits(prefs: p, settings: settings)
        v.onUserChanged("bob")
        for i in 0..<305 { v.record("p\(i)") }
        XCTAssertNil(v.lastVisit("p4"))
        XCTAssertNotNil(v.lastVisit("p5"))
        let back = ThreadVisits(prefs: p, settings: settings)
        back.onUserChanged("bob")
        back.record("another")
        XCTAssertNil(back.lastVisit("p5"), "order survived the JSON: the oldest goes first")
        XCTAssertNotNil(back.lastVisit("p304"))
        settings.setTrackHistory(false)
        back.record("untracked")
        XCTAssertNil(back.lastVisit("untracked"))
    }

    @MainActor
    func testDraftsAreScopedToTheAccount() {
        let p = Prefs(defaults: defaults)
        var user = "Bob"
        let d = Drafts(prefs: p, username: { user })
        d.save("reply_t1_x", "hello", info: ["title": "A post"])
        XCTAssertEqual(p.getString("draft_reply_t1_x_bob"), "hello")
        XCTAssertEqual(d.get("reply_t1_x"), "hello")
        XCTAssertEqual(d.list().map(\.key), ["reply_t1_x"])
        XCTAssertEqual(d.list()[0].info["title"].str(), "A post")
        XCTAssertGreaterThan(d.list()[0].savedAt, 0)
        user = "Eve"
        XCTAssertNil(d.get("reply_t1_x"))
        XCTAssertEqual(d.list().count, 0)
        user = "Bob"
        d.save("reply_t1_x", "   ")
        XCTAssertEqual(d.list().count, 0, "a blank draft clears it")
        XCTAssertEqual(d.changes, 2)
    }

    func testBackupFormatRoundTrips() throws {
        let p = try fromDisk(["flutter.b": true, "flutter.i": 5, "flutter.d": 1.5, "flutter.s": "x", "flutter.l": ["a"], "flutter.draft_x": "skip", "flutter.__t": "skip"])
        let text = Backup.export(p)
        let root = json(text)
        XCTAssertEqual(root["app"].str(), "ilay_for_reddit")
        XCTAssertEqual(root["version"].int(), 1)
        XCTAssertEqual(root["data"]["i"], ["t": "i", "v": 5])
        XCTAssertEqual(root["data"]["d"], ["t": "d", "v": 1.5])
        XCTAssertEqual(root["data"]["l"], ["t": "l", "v": ["a"]])
        XCTAssertNil(root["data"]["draft_x"])
        XCTAssertNil(root["data"]["__t"])
        let other = testPrefs()
        XCTAssertEqual(try Backup.import(other, text), 5)
        XCTAssertEqual(other.getBool("b"), true)
        XCTAssertEqual(other.getInt("i"), 5)
        XCTAssertEqual(other.getDouble("d"), 1.5)
        XCTAssertEqual(other.getStringList("l"), ["a"])
        XCTAssertThrowsError(try Backup.import(other, "not a backup"))
    }

    // A backup from the Flutter or Android build: a whole-number double, written as 1.0.
    func testImportsAWholeDouble() throws {
        let p = testPrefs()
        try Backup.import(p, #"{"app":"ilay_for_reddit","version":1,"data":{"textScale":{"t":"d","v":1.0}}}"#)
        XCTAssertEqual(p.getDouble("textScale"), 1.0)
    }
}

/// Website sessions, OAuth accounts and legacy entries in `accounts_json`, as the Flutter app left them.
final class SecureStoreTests: XCTestCase {
    func testReadsTheActiveSlot() async {
        let b = InMemorySecureBackend(oauthItems(user: "alice"))
        let s = SecureStore(backend: b)
        let accessToken = await s.accessToken()
        let username = await s.username()
        let authMode = await s.authMode()
        let expiry = await s.tokenExpiry()
        XCTAssertEqual(accessToken, "tok")
        XCTAssertEqual(username, "alice")
        XCTAssertEqual(authMode, "oauth", "the default when none is stored")
        XCTAssertNotNil(expiry)
    }

    func testFlutterAccountsMapIncludingLegacyPlainTokens() async {
        let b = InMemorySecureBackend([
            "accounts_json": #"{"zed":{"mode":"oauth","rt":"rt1"},"amy":{"mode":"web","cookie":"c=1","modhash":"mh"},"old":"legacy-token"}"#,
        ])
        let s = SecureStore(backend: b)
        let accounts = await s.accounts()
        XCTAssertEqual(accounts, ["zed", "amy", "old"], "in stored order")
        let mode = await s.accountMode("amy")
        let legacyMode = await s.accountMode("old")
        XCTAssertEqual(mode, "web")
        XCTAssertEqual(legacyMode, "oauth")

        let web = await s.activateAccount("amy")
        XCTAssertTrue(web)
        XCTAssertEqual(b["username"], "amy")
        XCTAssertEqual(b["auth_mode"], "web")
        XCTAssertEqual(b["web_cookie"], "c=1")
        XCTAssertEqual(b["web_modhash"], "mh")
        XCTAssertNil(b["refresh_token"])

        let legacy = await s.activateAccount("old")
        XCTAssertTrue(legacy)
        XCTAssertEqual(b["auth_mode"], "oauth")
        XCTAssertEqual(b["refresh_token"], "legacy-token")
        XCTAssertNil(b["web_cookie"])

        let unknown = await s.activateAccount("nobody")
        XCTAssertFalse(unknown)
    }

    func testAccountWritesKeepFlutterShape() async {
        let b = InMemorySecureBackend()
        let s = SecureStore(backend: b)
        await s.upsertAccount("zed", refreshToken: "rt")
        await s.upsertWebAccount("amy", cookie: "c", modhash: nil)
        XCTAssertEqual(b["accounts_json"], #"{"zed":{"mode":"oauth","rt":"rt"},"amy":{"mode":"web","cookie":"c","modhash":null}}"#)
        await s.removeAccountEntry("zed")
        let left = await s.accounts()
        XCTAssertEqual(left, ["amy"])
        await s.clearAccounts()
        XCTAssertNil(b["accounts_json"])
    }

    func testRenewedCookieGoesToItsOwnAccount() async {
        let b = InMemorySecureBackend([
            "username": "amy", "web_cookie": "old",
            "accounts_json": #"{"amy":{"mode":"web","cookie":"old","modhash":"m"},"zed":{"mode":"oauth","rt":"r"}}"#,
        ])
        let s = SecureStore(backend: b)
        await s.updateWebCookie("new", user: "amy")
        XCTAssertEqual(b["web_cookie"], "new")
        XCTAssertEqual(json(b["accounts_json"]!)["amy"]["cookie"].str(), "new")
        XCTAssertEqual(json(b["accounts_json"]!)["amy"]["modhash"].str(), "m")
        // Switched away meanwhile: the active slot keeps its own.
        await s.updateWebCookie("newer", user: "other")
        XCTAssertEqual(b["web_cookie"], "new")
    }

    func testClearSessionKeepsApiCredentialsAndSavingsClearSlots() async {
        let b = InMemorySecureBackend(oauthItems())
        let s = SecureStore(backend: b)
        await s.saveWebSession(username: "amy", cookie: "c", modhash: "m")
        XCTAssertNil(b["access_token"])
        XCTAssertNil(b["refresh_token"])
        await s.saveOpenaiKey("")
        XCTAssertNil(b["openai_api_key"], "an empty key is no key")
        await s.clearSession()
        XCTAssertNil(b["username"])
        XCTAssertNil(b["auth_mode"])
        XCTAssertEqual(b["client_id"], "cid")
        await s.saveAnonymousSession()
        XCTAssertEqual(b["auth_mode"], "anon")
        await s.clearAll()
        XCTAssertNil(b["client_id"])
    }

    func testAKeychainFailureReadsAsNothingButIsReportedByHasUsername() async {
        let b = InMemorySecureBackend(["username": "amy"])
        b.failReads = true
        let s = SecureStore(backend: b)
        let u = await s.username()
        XCTAssertNil(u)
        do {
            _ = try await s.hasUsername()
            XCTFail("a read failure must not look like no account")
        } catch {}
    }
}

@MainActor
final class SessionManagerTests: XCTestCase {
    private func manager(_ items: [String: String], prefs: Prefs = testPrefs()) -> (SessionManager, InMemorySecureBackend, Prefs) {
        let b = InMemorySecureBackend(items)
        let store = SecureStore(backend: b)
        let repo = AuthRepository(store: store, session: StubProtocol.session())
        return (SessionManager(store: store, repo: repo, prefs: prefs), b, prefs)
    }

    private func loaded(_ m: SessionManager) async -> Bool {
        m.reload()
        return await eventually { m.state != .loading }
    }

    func testRestoresAnOAuthLoginAndAddsItToTheAccounts() async {
        let (m, b, p) = manager(oauthItems(user: "alice"))
        let done = await loaded(m)
        XCTAssertTrue(done)
        XCTAssertEqual(m.state, .loggedIn(AuthSession(username: "alice")))
        XCTAssertEqual(m.username, "alice")
        XCTAssertTrue(m.hasAccount)
        XCTAssertEqual(p.getBool("has_account"), true)
        XCTAssertEqual(json(b["accounts_json"]!)["alice"]["rt"].str(), "rt")
    }

    func testRestoresAWebsiteSession() async {
        let (m, b, _) = manager(webItems(user: "amy"))
        _ = await loaded(m)
        XCTAssertEqual(m.username, "amy")
        XCTAssertEqual(json(b["accounts_json"]!)["amy"]["mode"].str(), "web")
    }

    func testRestoresAnonymousBrowsing() async {
        let (m, _, _) = manager(["auth_mode": "anon", "client_id": "cid"])
        _ = await loaded(m)
        XCTAssertEqual(m.session?.anonymous, true)
        XCTAssertEqual(m.session?.identity, "\0anon")
    }

    func testAnEmptyKeychainIsLoggedOutAndClearsTheFlag() async {
        let p = testPrefs()
        p.setBool("has_account", true)
        let (m, _, _) = manager([:], prefs: p)
        _ = await loaded(m)
        XCTAssertEqual(m.state, .loggedOut)
        XCTAssertFalse(m.hasAccount)
    }

    func testATransientKeychainFailureKeepsTheFlag() async {
        let p = testPrefs()
        p.setBool("has_account", true)
        let (m, b, _) = manager(oauthItems(), prefs: p)
        b.failReads = true
        _ = await loaded(m)
        XCTAssertEqual(m.state, .loggedOut)
        XCTAssertTrue(m.hasAccount, "the UI tells this apart from a real logout")
    }

    func testSwitchRemoveAndLogout() async {
        var items = oauthItems(user: "alice")
        items["accounts_json"] = #"{"alice":{"mode":"oauth","rt":"rt"},"bob":{"mode":"oauth","rt":"rt2"}}"#
        let (m, b, _) = manager(items)
        _ = await loaded(m)
        var seen: [SessionState] = []
        m.onStateChanged = { seen.append($0) }

        await m.switchAccount("bob")
        XCTAssertEqual(m.username, "bob")
        XCTAssertEqual(b["refresh_token"], "rt2")
        XCTAssertEqual(seen, [.loggedIn(AuthSession(username: "bob"))])

        await m.switchAccount("bob")
        XCTAssertEqual(seen.count, 1, "no change, no notice")

        await m.removeAccount("alice")
        XCTAssertEqual(m.username, "bob", "removing another account changes nothing here")
        XCTAssertEqual(m.accountsVersion, 1)

        await m.removeAccount("bob")
        XCTAssertEqual(m.state, .loggedOut)
        XCTAssertFalse(m.hasAccount)
        XCTAssertNil(b["accounts_json"])
        XCTAssertEqual(b["client_id"], "cid")
    }

    func testRemovingTheActiveAccountMovesToTheNext() async {
        var items = oauthItems(user: "alice")
        items["accounts_json"] = #"{"alice":{"mode":"oauth","rt":"rt"},"bob":{"mode":"oauth","rt":"rt2"}}"#
        let (m, _, _) = manager(items)
        _ = await loaded(m)
        await m.removeAccount("alice")
        XCTAssertEqual(m.username, "bob")
    }
}

@MainActor
final class FileStoreTests: XCTestCase {
    func testOfflineStoreReadsPerAccountAndLegacyCopies() async throws {
        let dir = tempDir()
        let p = testPrefs()
        p.setString("offline_threads_bob", #"[{"id":"legacy","sub":"a","title":"L","at":1},{"id":"own","sub":"a","title":"O","at":2}]"#)
        let (client, _, _, _) = stubClient([:])
        let root = dir.appendingPathComponent("offline_threads")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("u_bob"), withIntermediateDirectories: true)
        try Data(#"["old"]"#.utf8).write(to: root.appendingPathComponent("legacy.json"))
        try Data(#"["mine"]"#.utf8).write(to: root.appendingPathComponent("u_bob/own.json"))
        let s = OfflineStore(prefs: p, repo: RedditRepository(client: client), filesDir: dir)
        s.onUserChanged("Bob")
        let legacy = await s.read("legacy")
        let own = await s.read("own")
        let notListed = await s.read("other")
        XCTAssertEqual(legacy, ["old"])
        XCTAssertEqual(own, ["mine"])
        XCTAssertNil(notListed, "not saved by this account")

        await s.remove("legacy")
        XCTAssertFalse(s.contains("legacy"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("legacy.json").path), "no account lists it any more")
    }

    func testSharedLegacyCopyStaysWhileAnotherAccountListsIt() async throws {
        let dir = tempDir()
        let p = testPrefs()
        p.setString("offline_threads_bob", #"[{"id":"x","sub":"a","title":"L","at":1}]"#)
        p.setString("offline_threads_amy", #"[{"id":"x","sub":"a","title":"L","at":1}]"#)
        let (client, _, _, _) = stubClient([:])
        let root = dir.appendingPathComponent("offline_threads")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: root.appendingPathComponent("x.json"))
        let s = OfflineStore(prefs: p, repo: RedditRepository(client: client), filesDir: dir)
        s.onUserChanged("bob")
        await s.remove("x")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("x.json").path))
    }

    func testSummaryStoreReadsFlutterFileMergesEarlyOnesAndWritesBack() async throws {
        let dir = tempDir()
        let file = dir.appendingPathComponent("summaries_bob.json")
        try Data(#"[{"postId":"a","subreddit":"s","title":"T","permalink":"/p","style":"TL;DR","model":"m","text":"sum","createdAt":5}]"#.utf8).write(to: file)
        let s = SummaryStore(filesDir: dir)
        s.onUserChanged("Bob")
        let early = SavedSummary(postId: "new", subreddit: "s", title: "T", permalink: "/p", style: "x", model: "m", text: "t", createdAt: 9)
        s.add(early)
        XCTAssertEqual(s.items.map(\.postId), ["new"])
        let merged = await eventually { s.items.count == 2 }
        XCTAssertTrue(merged)
        XCTAssertEqual(s.items.map(\.postId), ["new", "a"])
        let written = await eventually { (try? Data(contentsOf: file)).flatMap { try? AppJson.parse($0) }.arr()?.count == 2 }
        XCTAssertTrue(written)
        s.remove("new")
        XCTAssertEqual(s.items.map(\.postId), ["a"])
        // Each store writes on its own queue: wait for this one's before a second reads the file.
        _ = await eventually { (try? Data(contentsOf: file)).flatMap { try? AppJson.parse($0) }.arr()?.count == 1 }
        let back = SummaryStore(filesDir: dir)
        back.onUserChanged("bob")
        _ = await eventually { !back.items.isEmpty }
        XCTAssertEqual(back.items.first?.text, "sum")
        XCTAssertEqual(back.items.first?.createdAt, 5)
    }

    func testResponseCacheUsesFlutterFileNames() async {
        let dir = tempDir()
        let c = ResponseCache(cacheDir: dir)
        await c.write("alice|/best?limit=25", Data(#"{"a":1}"#.utf8))
        // md5("alice|/best?limit=25"), the Flutter build's <md5>.json under luli_cache.
        let names = try? FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("luli_cache").path)
        XCTAssertEqual(names?.count, 1)
        XCTAssertTrue(names?.first?.hasSuffix(".json") == true)
        XCTAssertEqual(names?.first?.count, 32 + 5)
        let back = await c.read("alice|/best?limit=25")
        XCTAssertEqual(back, ["a": 1])
        await c.clear()
        let none = await c.read("alice|/best?limit=25")
        XCTAssertNil(none)
    }
}
