# Break-glass: the "Hydra" website-session fallback

**Status: contingency only. Not implemented, and not to be shipped in the
publicly-distributed (GitHub/F-Droid) build.**

Luli authenticates with Reddit's official OAuth2 API using **bring-your-own
credentials** (each user registers an "installed app" at
`reddit.com/prefs/apps` and enters the client ID). Reddit is closing that path:
self-service app creation appears gated as of late-2025, and unauthenticated
`.json` endpoints started returning 403 in May 2026. If a user can no longer
obtain or use an API client ID, this document is the migration plan to keep the
app working the way the iOS client **Hydra** (`github.com/dmilin1/hydra`) does.

> ⚠️ **Read this first.** The approach below accesses `reddit.com` the way a
> logged-in browser does, *outside* the official API. That **violates Reddit's
> User Agreement** and puts the **signed-in user's account** at risk of
> suspension (not just an app key). It is also brittle — Reddit can break it
> without notice (they just killed anonymous `.json`). Use it only for a
> **personal build**, where the only account at stake is your own. Do not bake
> it into a release distributed to other people.

---

## 1. How the model works

No OAuth, no client ID. Instead:

1. **Login** — open a `WebView` at `https://www.reddit.com/login`. The user
   signs in there; Reddit sets its normal **session cookies** in the webview's
   cookie store. Detect success by polling for the session cookie
   (`reddit_session`).
2. **Capture cookies** — read the webview's cookies and load them into the HTTP
   client's cookie jar. Persist them (iOS clears session cookies on launch, so
   rewrite them with a far-future expiry — Hydra uses ~10,000 days).
3. **Get the modhash** — `GET https://www.reddit.com/api/me.json` returns
   `data.modhash` (Reddit's CSRF token for the session). Store it in memory.
4. **All requests** go to `reddit.com` `.json` endpoints **with the cookies**.
   Write actions (vote/comment/save/subscribe) additionally send the modhash as
   the `X-Modhash` header (or `uh=<modhash>` form field).

### The big win for Luli
`reddit.com/*.json` returns **the same JSON shapes** as `oauth.reddit.com`. So
the entire model + parsing layer (`Post.fromData`, `Comment.fromChild`,
`Listing`, `Subreddit`, inbox, etc.) and **all UI/feature code stay unchanged.**
Only the transport + auth layer changes.

---

## 2. Files to change

| File | Change |
|---|---|
| `lib/core/reddit_constants.dart` | Add `webBase = 'https://www.reddit.com'`. Keep OAuth constants for the existing mode. |
| `lib/core/network/reddit_client.dart` | New transport: attach **cookies** (cookie jar) instead of `Authorization: bearer`; append `.json` to GET listing paths; add `X-Modhash` to writes; drop the token-refresh interceptor. Keep User-Agent + `raw_json=1` + the defensive String/JSON decoding. |
| `lib/features/auth/auth_repository.dart` | Replace `flutter_web_auth_2` OAuth + token exchange/refresh with: WebView cookie-login → fetch `/api/me.json` → store modhash + username. |
| `lib/features/auth/login_screen.dart` | Replace the client-ID form with a "Sign in with Reddit" button that opens the login WebView. (No credentials are ever typed into Luli — they go to reddit.com in the webview.) |
| `lib/core/storage/secure_store.dart` | Store a **cookie bundle per account** instead of a `refresh_token`. The accounts map becomes `{username: cookieBundleJson}`. |
| `lib/data/reddit_repository.dart` | Mostly unchanged. Audit each endpoint for the `.json` suffix + verify write endpoints (see mapping below). The JSON parsing is untouched. |
| `pubspec.yaml` | Add deps (below). Remove `flutter_web_auth_2` if fully switching. |

---

## 3. Dependencies

```yaml
flutter_inappwebview: ^6.x   # login WebView + CookieManager (read session cookies)
dio_cookie_manager: ^3.x     # bridges dio <-> cookie jar
cookie_jar: ^4.x             # the cookie store (persist to disk)
```

`webview_flutter` + `webview_cookie_manager` is a lighter alternative if you
don't want `flutter_inappwebview`.

---

## 4. Endpoint mapping (oauth.reddit.com → www.reddit.com)

GET listing/detail endpoints: append `.json` **before** the query string.

| Current (OAuth) | Web fallback |
|---|---|
| `GET /best?limit=…` | `GET /best.json?limit=…&raw_json=1` |
| `GET /r/<sub>/<sort>` | `GET /r/<sub>/<sort>.json` |
| `GET /comments/<id>` | `GET /comments/<id>.json` (+ `&comment=<id>&context=3` still works) |
| `GET /r/<sub>/search` | `GET /r/<sub>/search.json` |
| `GET /subreddits/mine/subscriber` | `GET /subreddits/mine/subscriber.json` |
| `GET /message/<where>` | `GET /message/<where>.json` |
| `GET /user/<name>/about` | `GET /user/<name>/about.json` |
| `GET /api/v1/me` (identity) | `GET /api/me.json` → `data.name`, `data.modhash` |

POST action endpoints: same paths on `www.reddit.com`, but require **cookies +
modhash**, not a bearer token. Send modhash as header `X-Modhash: <modhash>`
(and/or form field `uh`).

| Action | Endpoint | Notes |
|---|---|---|
| Vote | `POST /api/vote` | form `id`, `dir`; + `X-Modhash` |
| Save/unsave | `POST /api/save` `/api/unsave` | + `X-Modhash` |
| Comment/reply | `POST /api/comment` | form `thing_id`, `text`; + `X-Modhash` |
| Subscribe | `POST /api/subscribe` | + `X-Modhash` |
| Submit | `POST /api/submit` | + `X-Modhash` |
| Read message | `POST /api/read_message` | + `X-Modhash` |

> Media upload (image/gallery/video) uses the OAuth media-lease flow and has **no
> clean website equivalent** — expect submitting media to break or need a
> separate path. Text/link posts are fine.

---

## 5. Auth flow (replacement for OAuth)

```
login():
  open WebView -> https://www.reddit.com/login
  poll CookieManager for `reddit_session` cookie
  on success:
    copy reddit.com cookies into the cookie jar (persist)
    res = GET https://www.reddit.com/api/me.json   (with cookies)
    username = res.data.name
    modhash  = res.data.modhash         // keep in memory; refetch on app start
    secureStore.saveAccountCookies(username, cookieJar.serialize())
refresh():
  there is no token refresh. If a request 401/403s or redirects to /login,
  the session expired -> prompt re-login. Refetch modhash from /api/me.json
  on cold start.
switchAccount(username):
  load that account's cookie bundle into the jar; refetch modhash.
```

Notes:
- Set a desktop-ish **User-Agent** and keep `raw_json=1`.
- Reddit's login page runs bot detection; Hydra injects CSS into the page and
  uses fallback polling because `onLoadStart` doesn't always fire. Expect to
  iterate here.
- Cookies are the credential — store them in `flutter_secure_storage`, never log
  them.

---

## 6. Multi-account
Today: `{username: refreshToken}`. Fallback: `{username: cookieBundleJson}`.
The switcher UI and `AuthController` flow are unchanged — only what's stored and
how it's "activated" (load cookies + refetch modhash) changes.

---

## 7. Phased checklist
- [ ] Add deps; create a cookie jar + dio cookie manager wired into `RedditClient`.
- [ ] Build the login WebView + cookie capture + `/api/me.json` (username + modhash).
- [ ] Add a runtime switch (e.g. `authMode: oauth | web`) so both modes coexist
      during migration and you can fall back.
- [ ] Point GET requests at `www.reddit.com` + `.json`; verify a feed loads.
- [ ] Wire `X-Modhash` into writes; verify vote/save/comment.
- [ ] Port multi-account to cookie bundles.
- [ ] Handle session-expiry (redirect-to-login detection → re-auth prompt).
- [ ] Accept that media upload may be degraded; gate or hide it.
- [ ] Keep it on a **personal build branch** — do not merge into the distributed release.

---

## 8. Rollback / coexistence
Keep the OAuth path intact behind the `authMode` switch. If Reddit re-opens keys
or breaks the web session, flip back to `oauth` with no data loss (the accounts
map just holds a different credential type per mode).

---

## 9. Reality check
This is a calculated ToS bet that works *until Reddit decides it doesn't*. The
parsing/UI portability makes the migration cheap, but the operational and
account-safety costs are real and ongoing. Prefer staying on OAuth for as long
as it's available; treat this as the emergency exit, for personal use.

_Reference: `github.com/dmilin1/hydra` — `api/RedditApi.ts`,
`api/Authentication.ts`, `components/Modals/Login.tsx`, `utils/RedditCookies`._
