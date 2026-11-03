import XCTest
@testable import Ilay

/// RedditClient and the repository against a stub URL protocol: no network, no keychain.
final class RedditClientTests: XCTestCase {
    private let listing = #"{"data":{"after":"t3_b","children":[{"kind":"t3","data":{"id":"a","title":"First"}},{"kind":"t1","data":{"id":"skip"}}]}}"#

    func testOAuthRequestsCarryTheBearerUserAgentAndRawJson() async throws {
        StubProtocol.start { [listing] _ in .init(body: listing) }
        let (client, _, _, _) = stubClient(oauthItems())
        let json = try await client.get("/best", [("limit", "25"), ("after", nil), ("q", "a+b c")])
        XCTAssertEqual(json["data"]["after"].str(), "t3_b")
        let r = StubProtocol.requests[0]
        XCTAssertEqual(r.url?.host, "oauth.reddit.com")
        XCTAssertEqual(r.url?.path, "/best")
        XCTAssertEqual(r.url?.query, "limit=25&q=a%2Bb%20c&raw_json=1")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "bearer tok")
        XCTAssertEqual(r.value(forHTTPHeaderField: "User-Agent"), RedditConstants.userAgent("alice"))
        XCTAssertNil(r.value(forHTTPHeaderField: "cookie"))
    }

    func testRefreshesOnceOnA401AndRetries() async throws {
        StubProtocol.start { r in
            if r.url!.path == "/api/v1/access_token" { return .init(body: #"{"access_token":"fresh","expires_in":3600}"#) }
            return r.value(forHTTPHeaderField: "Authorization") == "bearer fresh" ? .init(body: "{}") : .init(status: 401)
        }
        let (client, _, backend, _) = stubClient(oauthItems())
        _ = try await client.get("/best")
        XCTAssertEqual(StubProtocol.paths, ["/best", "/api/v1/access_token", "/best"])
        XCTAssertEqual(backend["access_token"], "fresh")
        XCTAssertEqual(backend["refresh_token"], "rt", "kept: Reddit sends no new one")
        // The refresh authenticated as the client id, no secret.
        XCTAssertEqual(StubProtocol.requests[1].value(forHTTPHeaderField: "Authorization"), "Basic " + Data("cid:".utf8).base64EncodedString())
    }

    func testAnExpiredTokenRefreshesFirst() async throws {
        var items = oauthItems()
        items["token_expiry"] = "1"
        StubProtocol.start { r in
            r.url!.path == "/api/v1/access_token" ? .init(body: #"{"access_token":"fresh"}"#) : .init(body: "{}")
        }
        let (client, _, _, _) = stubClient(items)
        _ = try await client.get("/best")
        XCTAssertEqual(StubProtocol.paths, ["/api/v1/access_token", "/best"])
        XCTAssertEqual(StubProtocol.requests[1].value(forHTTPHeaderField: "Authorization"), "bearer fresh")
    }

    func testConcurrent401sShareOneRefresh() async {
        StubProtocol.start { r in
            if r.url!.path == "/api/v1/access_token" {
                Thread.sleep(forTimeInterval: 0.1)
                return .init(body: #"{"access_token":"fresh"}"#)
            }
            return .init(body: "{}")
        }
        let store = SecureStore(backend: InMemorySecureBackend(oauthItems()))
        let auth = AuthRepository(store: store, session: StubProtocol.session())
        let tokens = await withTaskGroup(of: String?.self) { group in
            for _ in 0..<5 { group.addTask { await auth.refresh() } }
            return await group.reduce(into: [String?]()) { $0.append($1) }
        }
        XCTAssertEqual(tokens, Array(repeating: "fresh", count: 5))
        XCTAssertEqual(StubProtocol.paths.count, 1)
    }

    func testAStaleSocketIsRetriedOnce() async throws {
        var calls = 0
        let lock = NSLock()
        StubProtocol.start { _ in
            let n = lock.withLock { calls += 1; return calls }
            if n == 1 { throw URLError(.networkConnectionLost) }
            return .init(body: "{}")
        }
        let (client, _, _, _) = stubClient(oauthItems())
        let r = try await client.getResult("/best")
        XCTAssertFalse(r.fromCache)
        XCTAssertEqual(StubProtocol.paths.count, 2)
    }

    func testOfflineFallsBackToTheCachePerAccount() async throws {
        StubProtocol.start { _ in .init(body: #"{"fresh":true}"#) }
        let (client, store, _, _) = stubClient(oauthItems(user: "alice"))
        _ = try await client.get("/best")
        // The write is off the request's path.
        var cached: JsonElement?
        for _ in 0..<200 where cached == nil {
            cached = await client.cached("/best")
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(cached, ["fresh": true])

        StubProtocol.start { _ in throw URLError(.notConnectedToInternet) }
        let offline = try await client.getResult("/best")
        XCTAssertTrue(offline.fromCache)
        XCTAssertEqual(StubProtocol.paths.count, 2, "tried twice first")

        // Another account never gets alice's pages.
        await store.saveUsername("bob")
        client.invalidateAuthConfig()
        let other = await client.cached("/best")
        XCTAssertNil(other)
        do {
            _ = try await client.getResult("/best")
            XCTFail("nothing cached for bob, and offline")
        } catch {
            XCTAssertTrue(error is URLError)
        }

        // Settings → offline cache off.
        await store.saveUsername("alice")
        client.invalidateAuthConfig()
        client.setCacheEnabled(false)
        let off = await client.cached("/best")
        XCTAssertNil(off)
    }

    func testErrorsCarryRedditsReason() async {
        StubProtocol.start { _ in .init(status: 403, body: #"{"reason":"quarantined","message":"Forbidden"}"#) }
        let (client, _, _, _) = stubClient(oauthItems())
        do {
            _ = try await client.get("/r/x/hot")
            XCTFail("a 403 must throw")
        } catch let e as RedditApiException {
            XCTAssertEqual(e.statusCode, 403)
            XCTAssertEqual(e.reason, "quarantined")
            XCTAssertEqual(e.message, "Forbidden")
            XCTAssertEqual(e.errorDescription, "HTTP 403 (quarantined)")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testRateLimitHeadersAreReported() async throws {
        let box = RateBox()
        StubProtocol.start { _ in .init(headers: ["x-ratelimit-remaining": "95.0", "x-ratelimit-used": "5", "x-ratelimit-reset": "120"], body: "{}") }
        let (client, _, _, _) = stubClient(oauthItems(), rateLimit: { box.value = $0 })
        _ = try await client.get("/best")
        XCTAssertEqual(box.value?.remaining, 95)
        XCTAssertEqual(box.value?.used, 5)
        XCTAssertEqual(box.value?.total, 100)
        XCTAssertEqual(box.value?.resetSeconds, 120)

        StubProtocol.start { _ in .init(status: 429, headers: ["retry-after": "30"]) }
        _ = try? await client.post("/api/vote", [("id", "x")])
        XCTAssertEqual(box.value?.remaining, 0)
        XCTAssertEqual(box.value?.resetSeconds, 30)
    }

    func testPostsAreFormEncoded() async throws {
        StubProtocol.start { r in
            XCTAssertEqual(r.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
            return .init(body: "{}")
        }
        let (client, _, _, _) = stubClient(oauthItems())
        try await client.post("/api/vote", [("id", "t3_a"), ("dir", "1")])
        XCTAssertEqual(StubProtocol.requests[0].httpMethod, "POST")
        XCTAssertEqual(StubProtocol.requests[0].url?.query, "raw_json=1")
    }

    func testWebModeTalksToTheSiteLikeABrowser() async throws {
        StubProtocol.start { _ in .init(body: "{}") }
        let items = webItems()
        let (client, _, _, _) = stubClient(items)
        let isWeb = await client.isWebMode()
        XCTAssertTrue(isWeb)
        _ = try await client.get("/r/pics/hot")
        _ = try await client.get("/api/info")
        try await client.post("/api/vote", [("id", "x")])
        let (get, api, post) = (StubProtocol.requests[0], StubProtocol.requests[1], StubProtocol.requests[2])
        XCTAssertEqual(get.url?.absoluteString, "https://www.reddit.com/r/pics/hot.json?raw_json=1", ".json on listing GETs")
        XCTAssertEqual(api.url?.path, "/api/info", "not on /api/")
        XCTAssertEqual(post.url?.path, "/api/vote")
        XCTAssertEqual(get.value(forHTTPHeaderField: "cookie"), items["web_cookie"])
        XCTAssertEqual(get.value(forHTTPHeaderField: "User-Agent"), RedditConstants.webUserAgent)
        XCTAssertNil(get.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(get.value(forHTTPHeaderField: "X-Modhash"), "only on writes")
        XCTAssertEqual(post.value(forHTTPHeaderField: "X-Modhash"), "mh")
    }

    func testAnExpiredTokenV2IsRenewedAndSaved() async throws {
        let fresh = jwt(#"{"exp":\#(nowMillis() / 1000 + 86_400)}"#)
        let session = jwt(#"{"sub":"t2_me"}"#)
        var items = webItems(user: "amy")
        items["web_cookie"] = "reddit_session=\(session); token_v2=\(jwt(#"{"exp":1}"#))"
        items["accounts_json"] = #"{"amy":{"mode":"web","cookie":"x","modhash":"m"}}"#
        StubProtocol.start { r in
            switch r.url!.path {
            case "/": return .init(headers: ["Set-Cookie": "token_v2=\(fresh); Expires=Thu, 01 Jan 2099 00:00:00 GMT; Path=/, loid=l; Path=/"])
            case "/svc/shreddit/graphql": return .init(status: 400)
            default: return .init(body: "{}")
            }
        }
        let (client, _, backend, _) = stubClient(items)
        _ = try await client.get("/best")
        XCTAssertEqual(StubProtocol.paths, ["/", "/svc/shreddit/graphql", "/best.json"])
        XCTAssertNil(cookieValue(StubProtocol.requests[0].value(forHTTPHeaderField: "cookie")!, "token_v2"), "only a request without a token gets a new one")
        let saved = backend["web_cookie"]!
        XCTAssertEqual(cookieValue(saved, "token_v2"), fresh)
        XCTAssertEqual(cookieValue(saved, "loid"), "l")
        XCTAssertEqual(cookieValue(json(backend["accounts_json"]!)["amy"]["cookie"].str()!, "token_v2"), fresh)
        XCTAssertEqual(cookieValue(StubProtocol.requests[2].value(forHTTPHeaderField: "cookie")!, "token_v2"), fresh)
    }

    func testARenewalThatChangesAccountIsRefused() async {
        var items = webItems(user: "amy")
        let me = jwt(#"{"sub":"t2_me"}"#)
        let other = jwt(#"{"sub":"t2_other"}"#)
        let fresh = jwt(#"{"exp":\#(nowMillis() / 1000 + 86_400)}"#)
        items["web_cookie"] = "reddit_session=\(me)"
        StubProtocol.start { _ in .init(headers: ["Set-Cookie": "reddit_session=\(other), token_v2=\(fresh)"]) }
        let session = StubProtocol.session()
        let renewed = await renewWebToken(items["web_cookie"]!, session: session)
        XCTAssertNil(renewed)
    }

    func testGqlSendsThePersistedQueryWithTokenV2AsBearer() async throws {
        let items = webItems()
        StubProtocol.start { r in
            XCTAssertEqual(r.url?.host, "cf.gql-fed.reddit.com")
            return .init(body: #"{"data":{"x":1}}"#)
        }
        let (client, _, _, _) = stubClient(items)
        let data = try await client.gql("Op", "hash", ["a": 1])
        XCTAssertEqual(data["x"], 1)
        XCTAssertEqual(StubProtocol.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer \(cookieValue(items["web_cookie"]!, "token_v2")!)")

        StubProtocol.start { _ in .init(status: 200, body: #"{"errors":[{"message":"no"}]}"#) }
        do {
            _ = try await client.gql("Op", "hash", [:])
            XCTFail("no data must throw")
        } catch let e as RedditApiException {
            XCTAssertEqual(e.message, "no")
        }
    }
}

private final class RateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: RateLimit?
    var value: RateLimit? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

final class RedditRepositoryTests: XCTestCase {
    private func repo(_ items: [String: String]) -> RedditRepository { RedditRepository(client: stubClient(items).client) }

    func testListingsSkipOtherKindsAndKeepTheRawPost() async throws {
        StubProtocol.start { _ in .init(body: #"{"data":{"after":"t3_b","children":[{"kind":"t3","data":{"id":"a","title":"First"}},{"kind":"t1","data":{"id":"skip"}}]}}"#) }
        let r = repo(oauthItems())
        let l = try await r.getPosts(subreddit: "pics", sort: .top, time: .week, after: "x", limit: 10)
        XCTAssertEqual(l.items.map(\.title), ["First"])
        XCTAssertEqual(l.after, "t3_b")
        XCTAssertTrue(l.hasMore)
        XCTAssertEqual(r.rawPost("a")["title"].str(), "First")
        XCTAssertEqual(StubProtocol.requests[0].url?.path, "/r/pics/top")
        XCTAssertEqual(StubProtocol.requests[0].url?.query, "limit=10&sr_detail=true&after=x&t=week&raw_json=1")
    }

    func testPostsByIdsKeepTheOrderGiven() async throws {
        StubProtocol.start { _ in .init(body: #"{"data":{"children":[{"kind":"t3","data":{"id":"b"}},{"kind":"t3","data":{"id":"a"}}]}}"#) }
        let posts = try await repo(oauthItems()).getPostsByIds(["t3_a", "t3_gone", "t3_b"])
        XCTAssertEqual(posts.map(\.id), ["a", "b"])
    }

    private let gqlPost = #"{"__typename":"SubredditPost","id":"t3_a","postTitle":"Via GraphQL","subreddit":{"name":"pics"},"url":"https://example.com"}"#

    func testWebSignInFallsBackToGraphQlWhenTheEdgeRefuses() async throws {
        StubProtocol.start { [gqlPost] r in
            guard r.url!.host == "cf.gql-fed.reddit.com" else { return .init(status: 403, body: "<html>blocked</html>") }
            let body = (try? Data(reading: r.httpBodyStream)) ?? Data()
            if String(decoding: body, as: UTF8.self).contains("PostsByIds") {
                return .init(body: #"{"data":{"postsInfoByIds":[\#(gqlPost)]}}"#)
            }
            return .init(body: #"{"data":{"homeV3":{"elements":{"edges":[{"node":{"groupId":"t3_a"}}]}}}}"#)
        }
        let r = repo(webItems())
        let l = try await r.getPosts()
        XCTAssertEqual(l.items.map(\.title), ["Via GraphQL"])
        XCTAssertEqual(l.after, "t3_a", "a plain fullname, like the website's")
        XCTAssertEqual(StubProtocol.requests.first?.url?.path, "/best.json")
        XCTAssertNotNil(r.rawPost("a"))
    }

    func testA403WithAReasonIsRedditsOwnAnswerNotTheEdge() async {
        StubProtocol.start { _ in .init(status: 403, body: #"{"reason":"private"}"#) }
        do {
            _ = try await repo(webItems()).getPosts(subreddit: "secret")
            XCTFail("must throw")
        } catch let e as RedditApiException {
            XCTAssertEqual(e.reason, "private")
            XCTAssertEqual(StubProtocol.requests.count, 1, "no GraphQL attempt")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testOAuthDoesntFallBack() async {
        StubProtocol.start { _ in .init(status: 403) }
        do {
            _ = try await repo(oauthItems()).getPosts()
            XCTFail("must throw")
        } catch {
            XCTAssertEqual(StubProtocol.requests.count, 1)
        }
    }

    func testAThreadThroughGraphQl() async throws {
        StubProtocol.start { [gqlPost] r in
            guard r.url!.host == "cf.gql-fed.reddit.com" else { return .init(status: 403) }
            let body = String(decoding: (try? Data(reading: r.httpBodyStream)) ?? Data(), as: UTF8.self)
            if body.contains("PostsByIds") { return .init(body: #"{"data":{"postsInfoByIds":[\#(gqlPost)]}}"#) }
            return .init(body: #"{"data":{"postInfoById":{"commentForest":{"trees":[{"depth":0,"parentId":"t3_a","node":{"__typename":"Comment","id":"t1_c","content":{"markdown":"Hi"},"authorInfo":{"name":"bob"},"createdAt":"2026-10-04T00:26:11+0000"}}]}}}}"#)
        }
        let t = try await repo(webItems()).getComments(subreddit: "pics", postId: "a")
        XCTAssertEqual(t.post.title, "Via GraphQL")
        XCTAssertEqual(t.comments.map(\.body), ["Hi"])
    }

    func testVoteFallsBackToItsMutation() async throws {
        StubProtocol.start { r in
            guard r.url!.host == "cf.gql-fed.reddit.com" else { return .init(status: 403) }
            let body = String(decoding: (try? Data(reading: r.httpBodyStream)) ?? Data(), as: UTF8.self)
            XCTAssertTrue(body.contains("UpdatePostVoteState"))
            XCTAssertTrue(body.contains(#""voteState":"UP""#))
            return .init(body: #"{"data":{"updatePostVoteState":{"ok":true}}}"#)
        }
        try await repo(webItems()).vote("t3_a", dir: 1)
        XCTAssertEqual(StubProtocol.requests.count, 2)
    }

    func testAMutationsRefusalIsReported() async {
        StubProtocol.start { r in
            r.url!.host == "cf.gql-fed.reddit.com" ? .init(body: #"{"data":{"updateCommentSaveState":{"ok":false,"fieldErrors":[{"message":"Thread is locked"}]}}}"#) : .init(status: 403)
        }
        do {
            try await repo(webItems()).setSaved("t1_a", saved: true)
            XCTFail("must throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Thread is locked")
        }
    }

    // MARK: #59: "more replies" no longer use /api/morechildren

    private func comment(_ id: String, parent: String, replies: String = "\"\"") -> String {
        #"{"kind":"t1","data":{"id":"\#(id)","name":"t1_\#(id)","parent_id":"\#(parent)","author":"a","body":"\#(id)","created_utc":1,"replies":\#(replies)}}"#
    }

    private func thread(_ children: [String]) -> String {
        #"[{"data":{"children":[{"kind":"t3","data":{"id":"p","title":"T"}}]}},{"data":{"children":[\#(children.joined(separator: ","))]}}]"#
    }

    private func moreRow(parent: String, children: [String], count: Int? = nil) -> Comment {
        Comment(id: children.first ?? "m", fullname: "t1_more", parentId: parent, author: "", body: "", score: 0, createdUtc: 0, depth: 2, isMore: true, moreCount: count ?? children.count, moreChildren: children)
    }

    func testMoreRepliesUnderACommentComeFromItsFocusedThread() async throws {
        let replies = #"{"data":{"children":[\#(comment("x", parent: "t1_c")),\#(comment("y", parent: "t1_x"))]}}"#
        StubProtocol.start { [self] _ in .init(body: thread([comment("c", parent: "t3_p", replies: replies)])) }
        let got = try await repo(oauthItems()).getMoreComments(linkFullname: "t3_p", moreNode: moreRow(parent: "t1_c", children: ["x", "y"]))
        XCTAssertEqual(got.map(\.id), ["x", "y"], "the parent's replies, not the parent")
        let r = StubProtocol.requests[0]
        XCTAssertEqual(r.url?.path, "/comments/p", "the subreddit isn't needed")
        XCTAssertEqual(r.url?.query, "sort=confidence&limit=500&comment=c&context=3&raw_json=1")
        XCTAssertFalse(StubProtocol.paths.contains { $0.contains("morechildren") })
    }

    func testMoreTopLevelCommentsComeFromTheWholeThread() async throws {
        StubProtocol.start { [self] _ in .init(body: thread([comment("a", parent: "t3_p"), comment("b", parent: "t3_p")])) }
        let got = try await repo(oauthItems()).getMoreComments(linkFullname: "t3_p", moreNode: moreRow(parent: "t3_p", children: ["b", "z"]), sort: "top")
        XCTAssertEqual(got.map(\.id), ["a", "b"])
        XCTAssertEqual(StubProtocol.requests.count, 1)
        XCTAssertEqual(StubProtocol.requests[0].url?.query, "sort=top&limit=500&raw_json=1")
    }

    func testPastWhatOnePageHoldsTenAreFetchedOneByOneTheRestStayOnTheRow() async throws {
        let ids = (0..<13).map { "h\($0)" }
        StubProtocol.start { [self] r in
            let focus = URLComponents(url: r.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "comment" }?.value
            // The whole thread doesn't reach them; each hidden comment's own thread has it.
            return .init(body: thread(focus.map { [comment($0, parent: "t3_p")] } ?? [comment("other", parent: "t3_p")]))
        }
        let row = moreRow(parent: "t3_p", children: ids, count: 40)
        let got = try await repo(oauthItems()).getMoreComments(linkFullname: "t3_p", moreNode: row)
        XCTAssertEqual(got.dropLast().map(\.id), Array(ids.prefix(10)))
        let rest = got.last!
        XCTAssertTrue(rest.isMore)
        XCTAssertEqual(rest.moreChildren, ["h10", "h11", "h12"])
        XCTAssertEqual(rest.moreCount, 30)
        XCTAssertEqual(StubProtocol.requests.count, 11)
    }

    func testWhenTheRowsCommentsAllComeBackTheresNoRest() async throws {
        StubProtocol.start { [self] r in
            let focus = URLComponents(url: r.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "comment" }?.value
            return .init(body: thread(focus.map { [comment($0, parent: "t3_p")] } ?? []))
        }
        let got = try await repo(oauthItems()).getMoreComments(linkFullname: "t3_p", moreNode: moreRow(parent: "t3_p", children: ["h1", "h2"]))
        XCTAssertEqual(got.map(\.id), ["h1", "h2"])
    }

    func testAGraphQlMoreRowContinuesByItsCursor() async throws {
        StubProtocol.start { r in
            let body = String(decoding: (try? Data(reading: r.httpBodyStream)) ?? Data(), as: UTF8.self)
            XCTAssertTrue(body.contains(#""after":"cur 1""#), body)
            return .init(body: #"{"data":{"postInfoById":{"commentForest":{"trees":[{"depth":2,"node":{"__typename":"Comment","id":"t1_d","content":{"markdown":"Hi"},"authorInfo":{"name":"b"}}}]}}}}"#)
        }
        let row = moreRow(parent: "t1_c", children: ["\(GQL_MORE)t1_c cur 1"])
        let got = try await repo(webItems()).getMoreComments(linkFullname: "t3_p", moreNode: row)
        XCTAssertEqual(got.map(\.id), ["d"])
        XCTAssertEqual(got[0].parentId, "t1_c")
        XCTAssertEqual(got[0].depth, 2)
    }

    // MARK: others

    func testSubscribedSubredditsAreCachedFavouritesFirst() async throws {
        StubProtocol.start { _ in .init(body: #"{"data":{"children":[{"data":{"display_name":"zed"}},{"data":{"display_name":"Bee"}},{"data":{"display_name":"apple"}},{"data":{"display_name":"fav","user_has_favorited":true}}]}}"#) }
        let r = repo(oauthItems())
        let first = try await r.getSubscribedSubreddits()
        XCTAssertEqual(first.map(\.name), ["fav", "apple", "Bee", "zed"])
        _ = try await r.getSubscribedSubreddits()
        XCTAssertEqual(StubProtocol.requests.count, 1, "from memory")
        _ = try await r.getSubscribedSubreddits(force: true)
        XCTAssertEqual(StubProtocol.requests.count, 2)
        r.setSubsCache(enabled: false, ttlMillis: 60_000)
        _ = try await r.getSubscribedSubreddits()
        XCTAssertEqual(StubProtocol.requests.count, 3)
    }

    func testApiErrorsThrowTheirMessage() async {
        StubProtocol.start { _ in .init(body: #"{"json":{"errors":[["RATELIMIT","Take a break","ratelimit"]]}}"#) }
        do {
            _ = try await repo(oauthItems()).submitPost("x", title: "t", kind: "self", text: "b")
            XCTFail("must throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Take a break")
        }
    }

    func testImagePostHasNoIdYetAndThatsFine() async throws {
        StubProtocol.start { _ in .init(body: #"{"json":{"errors":[],"data":{"websocket_url":"wss://x"}}}"#) }
        let id = try await repo(oauthItems()).submitPost("x", title: "t", kind: "image", url: "https://u")
        XCTAssertEqual(id, "")
    }

    func testSavedMixesPostsAndComments() async throws {
        StubProtocol.start { _ in .init(body: #"{"data":{"children":[{"kind":"t3","data":{"id":"a"}},{"kind":"t1","data":{"id":"b"}},{"kind":"t5","data":{}}]}}"#) }
        let items = try await repo(oauthItems()).getUserSaved("me").items
        XCTAssertEqual(items.count, 2)
        guard case .post = items[0], case .comment = items[1] else { return XCTFail("\(items)") }
    }

    func testRulesFlairsAndMultis() async throws {
        StubProtocol.start { r in
            switch r.url!.path {
            case "/r/x/about/rules": return .init(body: #"{"rules":[{"short_name":" A ","description":" b "},"junk"]}"#)
            case "/r/x/api/link_flair": return .init(body: #"[{"id":"1","text":" F "},{"id":"2","text":""}]"#)
            case "/api/multi/mine": return .init(body: #"[{"data":{"name":"b","display_name":"Beta"}},{"data":{"name":"a","display_name":"alpha"}}]"#)
            default: return .init(status: 404)
            }
        }
        let r = repo(oauthItems())
        let rules = try await r.getSubredditRules("x")
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules[0].title, "A")
        let flairs = await r.getLinkFlairs("x")
        XCTAssertEqual(flairs, [Flair(id: "1", text: "F")])
        let multis = try await r.getMyMultireddits()
        XCTAssertEqual(multis.map(\.name), ["a", "b"])
    }

    func testCachedPostsPaintsTheLastPage() async throws {
        StubProtocol.start { _ in .init(body: #"{"data":{"children":[{"kind":"t3","data":{"id":"a"}}]}}"#) }
        let r = repo(oauthItems())
        _ = try await r.getPosts()
        var cached: Listing<Post>?
        for _ in 0..<200 where cached == nil {
            cached = await r.cachedPosts()
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(cached?.items.map(\.id), ["a"])
        XCTAssertEqual(cached?.fromCache, true)
    }

    func testRawResponseSurvivesOfflineSave() async throws {
        let body = #"[{"data":{"children":[{"kind":"t3","data":{"id":"p","title":"T"}}]}},{"data":{"children":[]}}]"#
        StubProtocol.start { _ in .init(body: body) }
        let r = repo(oauthItems())
        let raw = try await r.getCommentsRaw(subreddit: "x", postId: "p", limit: 500)
        XCTAssertEqual(raw.encoded(), body)
        XCTAssertEqual(try r.parseThread(raw).post.title, "T")
    }
}

private extension Data {
    /// URLProtocol sees a request's body as a stream.
    init(reading stream: InputStream?) throws {
        self.init()
        guard let stream else { return }
        stream.open()
        defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            append(buffer, count: n)
        }
    }
}
