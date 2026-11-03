# Porting Ilay to Swift

The native iOS app, replacing the Flutter app (removed from `../ios`; its code is in
git at `4d6bbfd:ios/`, read with `git show 4d6bbfd:ios/lib/...`). The source of
truth is the Kotlin app (`../app/src/main/java/com/bennybar/luli_for_reddit`).
Read `../CLAUDE.md` first.

## Goal
Every feature and edge case of the Kotlin app, native to iOS 26: same behaviour,
Apple's look. Installs over the Flutter app and keeps the user's data.

**Port the behaviour 1:1**: every setting, edge case, retry, debounce, cache-first
paint, and the comments explaining why. Read the Kotlin file before writing Swift.
Where Android has no iOS equivalent, check the Flutter code (`4d6bbfd:ios/lib`) for how it
handled it on iOS (website login, notifications, app icons, share extensions).

**Do not port the look.** Use Apple's patterns instead of Material:
- System fonts and semantic colours (`.primary`, `.secondary`, `Color(.systemBackground)`,
  `.tint`); the user's accent setting drives `.tint`.
- Glass comes from the system: `TabView`, `NavigationStack` toolbars, `.toolbar`
  items, `.buttonStyle(.glass)` / `.glassProminent`, `.glassEffect()` on floating
  controls. Never hand-draw glass, and never put glass on content like post cards.
- Large titles that collapse, `List(.insetGrouped)` settings, `Toggle`, `Picker`,
  `Menu` instead of custom dropdowns, `.sheet` with `.presentationDetents`,
  `.confirmationDialog`, `.alert`, `.swipeActions` / native-feeling swipes,
  `.searchable` where it fits, SF Symbols, `.refreshable`, `ContentUnavailableView`,
  `ProgressView`.
- Kept from Material 3 Expressive on purpose: the photo carousel
  (`UI/KeylineCarousel`, used by `GalleryM3Carousel`), as in Kitzi's iOS app.
- Kept from Flutter's Calm design on purpose, because the user prefers it: a thread's
  comment structure (one rounded card per top-level thread, author dots, one-colour
  rails, labelled Reply, glass pill buttons) and the post header's connected button groups.
  Glass on content is drawn, not live, because live glass in every scrolling row costs
  frames: the thread cards are pre-rendered Liquid Glass platter images per row in
  `CommentCell` (the system effect would also put its own edge on every row), and
  comment and feed-card pills use `GlassPillStyle`, an imitation of the post's glass.
- Dropped as Material or Android only: FeedChip morphs, bounce shapes, dynamic
  colour, app font picker, volume keys, notification listener, Reddit app
  notification capture. Sort becomes a toolbar `Menu` or a native scrolling chip row with
  system styling. If it's unclear whether something still makes sense, keep the
  capability and give it the Apple form.

## Never change (users' data depends on these)
- Bundle id `com.bennybar.lulireddit` (Release), team `57L2ULXB7Z`.
- URL schemes `luli`, `redreader`; the OAuth redirect `luli://oauth`.
- Keychain: `flutter_secure_storage` items (service
  `flutter_secure_storage_service`, account = key name, UTF-8 data, group
  `57L2ULXB7Z.com.bennybar.lulireddit`, accessible after first unlock). Same key
  names as `4d6bbfd:ios/lib/core/storage/secure_store.dart`.
- UserDefaults: the Flutter prefs are read in place, as `flutter.<key>` in
  `UserDefaults.standard`. Same keys and types as Kotlin's and Flutter's, including
  `userScopedKey` naming and lists stored as arrays of strings. Add new keys freely,
  never rename one. Check `4d6bbfd:ios/lib` when a key's storage type looks ambiguous.
- Cache folder name `luli_cache`. Aptabase key from `RedditConstants`.
- `SharedStore` keychain group items used by the share extensions.

## Layout (`swift/`, `xcodegen generate` makes `Ilay.xcodeproj`; folders are synced, so new files need no project edit)
```
Ilay/App        IlayApp, AppContainer (`app`), Info.plist, entitlements
Ilay/Core       Json, Format, MediaLinks, DeepLinks, Translate, Backup, Analytics, UpdateChecker, Constants
Ilay/Core/Net   RedditClient, Http, RateLimit, WebToken, WebSessionCookies, ResponseCache, Catbox, Redgifs
Ilay/Core/Storage Prefs, SecureStore
Ilay/Model      Post, Comment, InboxItem, Subreddit, RedditUser, Multireddit, Flair, Listing
Ilay/Data       RedditRepository, GqlComments, GqlSearch, Sorts
Ilay/State      HistoryStore, PostOverrides, ContentFilters, Drafts, ...
Ilay/Settings   Settings, SettingsStore
Ilay/Auth       AuthRepository, OAuthFlow, SessionManager
Ilay/Nav        Route, AppNavigator
Ilay/UI         shared views: RemoteImage, ErrorView, ...
Ilay/Features/<Area>   Same areas as Kotlin's feature/*
IlayTests       Ports of Kotlin's unit tests
```
Keep Kotlin's file and type names where they still fit, so a change on one side is
easy to find on the other: backports go both ways from now on.

## Architecture
- Swift 5 mode, minimal concurrency checking, iOS 26 only.
- `app` is a global `AppContainer`, as in Kotlin: `app.prefs`, `app.secureStore`,
  `app.settings`, `app.session`, `app.repository`, `app.client`, `app.rateLimit`,
  `app.postOverrides`, `app.hiddenPosts`, `app.history`, `app.threadVisits`,
  `app.contentFilters`, `app.offline`, `app.drafts`, `app.feed`, `app.post`,
  `app.forYou`, `app.inbox`, `app.media`.
- Observable state: `@MainActor @Observable final class`. Kotlin's `StateFlow`
  becomes an observable property. Kotlin's ViewModels stay classes held in `@State`.
- Per-account state implements `UserScoped.onUserChanged(_:)`.
- `async/await` and `URLSession`. JSON through the `Json` helper, the counterpart
  of Kotlin's `el["a"]["b"].str()`; heavy parsing off the main actor.
- Models are immutable structs, parsed exactly like the Kotlin ones.
- Navigation: a `TabView` of `NavigationStack`s, `Route` mirroring `nav/Route.kt`,
  `AppNavigator` for push, pop, openPost, openLink, openImage, showSnackbar, etc.
- No third-party packages unless unavoidable (Apple's `swift-markdown` is fine).
- Long lists use `UICollectionView` with `UIHostingConfiguration` cells: SwiftUI
  content, real cell reuse. Images are downsampled to their slot and cached;
  decode off the main thread. Scrolling smoothness is the reason for this port.

## Working rules
- Surgical code: no speculative options, no single-use helpers unless recursion or
  clarity needs them, no `_underscore` names. Keep the "why" comments.
- Never print tokens, cookies or keys, not even in debug logs. Never run the app
  in a loop against Reddit: it shares the user's request allowance.
- Never vote, post, save, subscribe or otherwise act on the user's account in tests.
- Hydra is AGPL: facts only, no code.
- Do not touch `../app`. Do not commit.

## Checking your work
```
cd swift && xcodebuild -project Ilay.xcodeproj -scheme Ilay -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath /tmp/ilay-<yourarea> build 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'
xcodebuild test ... # same, for IlayTests
```
Use your own `-derivedDataPath`. Other work may be in progress in other folders:
fix errors in your files, and report rather than edit someone else's. Port the
Kotlin unit tests for what you write, plus anything needed to prove data
compatibility. The simulator has no account; the iPhone (Debug build, id
`com.bennybar.lulireddit.swiftdev`) reads the real login.
