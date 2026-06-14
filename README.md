# Ilay for Reddit

A fast, modern Reddit client for Android, built with Flutter and a Material 3
Expressive design. You bring your own Reddit API credentials. The app talks
directly to Reddit; the only other data it sends is anonymous usage analytics
(app launches, version, OS — no personal data or ad IDs).

## Features

- Browse the frontpage, subreddits, multireddits, and users
- A personalized **For You** feed built entirely on-device, with explainable
  "why you're seeing this" labels and per-post tuning
- Full participation: vote, comment, reply, submit text/link/image/gallery/video
  posts, edit, and delete — with image/video attachments (and clipboard paste)
  in replies and messages
- Inbox and private messages, with optional background notifications (polling
  only — no Firebase/push services), plus swipe to mark read/unread or delete
- Saved, upvoted, and locally-stored history
- Moderation actions on subreddits you moderate
- Three feed layouts, swipe-to-vote, NSFW blur, AMOLED and dynamic-color themes
- Offline cache, rate-limit awareness, and an in-app updater

## Screenshots

<p>
  <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/1.png" width="200" alt="For You feed">
  <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/2.png" width="200" alt="Post">
  <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/3.png" width="200" alt="Comments">
  <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/4.png" width="200" alt="Explore">
  <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/5.png" width="200" alt="Settings">
</p>

## How the "For You" feed works

Reddit doesn't give third-party apps access to its own recommendation engine, so
Ilay builds one on your device. Nothing about your interests ever leaves the
phone.

1. **Candidates.** Ilay pulls a pool of posts from the sources that actually
   matter to you: your subscription frontpage, fresh posts from your favourite
   subreddits, the communities you engage with most, what's rising in your
   subscriptions, and a small slice of r/popular for discovery. The feed is
   endless — scrolling past the first batch pages deeper into those sources and
   re-ranks as you go.
2. **On-device learning.** As you use the app it quietly learns which
   subreddits you care about — commenting counts most, then saving, upvoting,
   sharing, viewing media, and opening posts. It also learns *within* a
   community from post titles (a tiny local keyword model — so it can tell your
   F1 from your NBA). Everything decays over time, so the feed tracks your
   current taste, not last month's binge. All of it lives only in local
   storage, separately per account.
3. **Ranking.** Each candidate is scored by *community weight* (favourites ≫
   subscribed ≫ discovery, boosted by what you've learned), the post's
   popularity *relative to its own community* (so small subreddits aren't
   drowned out by big ones), recency, upvote ratio, and your keyword affinity.
   Posts you've opened — or that were shown twice and ignored — are demoted, so
   refreshes feel fresh.
4. **Diversity.** No single subreddit can dominate — posts are capped per
   community, and discovery picks are sprinkled in at roughly 1 in 6 so the
   feed stays mostly *your* communities without becoming repetitive. Discovery
   that matches your learned keywords outranks generic popular posts.
5. **Explainable & tunable.** Every post shows why it's there ("★ Favourite",
   "Because you engage with r/…", "Because you read posts about …",
   "Trending"), and a long-press lets you ask for more or less of a community,
   or mute it entirely.

## Install

Download the APK from the
[latest release](https://github.com/bennybar/LuliReddit/releases/latest) and
install it. The app checks GitHub for newer releases and can update itself.

(iOS has no public distribution — build and sideload it yourself; see `ios.txt`.)

## First run

**Recommended — official API (bring your own key):**

1. Go to <https://www.reddit.com/prefs/apps> and create an app of type
   **installed app**.
2. Set the redirect URI to exactly `luli://oauth`.
3. Copy the client ID (shown under the app name) into the login screen and
   connect.

**Fallback — sign in via website (no API key):** Reddit has begun restricting
who can create API keys. If you can't, the login screen offers *"Sign in via
website"*, which logs you in through reddit.com directly (no key needed).

> ⚠️ This fallback is **not** Reddit's official API. It may stop working if
> Reddit changes their site, and Reddit could treat it as against their usage
> policy and restrict or ban accounts that use it. It's off by default and gated
> behind an explicit warning — use it at your own risk. The API-key method above
> is always preferred. (See `docs/hydra-fallback.md`.)

## Build from source

Requires Flutter 3.35+.

```
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter build apk --release
```

## Tech

Flutter, Riverpod, Dio, go_router, Freezed. Reddit OAuth2 (installed-app flow),
credentials stored in the device keychain.

Not affiliated with Reddit, Inc.
