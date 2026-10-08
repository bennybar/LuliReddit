# Ilay for Reddit — native Kotlin (branch `kotlin`)

A full Kotlin/Jetpack Compose port of the Flutter app (≤ v1.0.51, still on
`main`). Same applicationId (`com.bennybar.luli_for_reddit`), same signing key,
so it installs as an update over the Flutter build and keeps the user's data.
The Flutter source for reference: `/Users/bennybarak/StudioProjects/luli_for_reddit/lib`.

## Never rename (users depend on these)
applicationId/namespace `com.bennybar.luli_for_reddit`; OAuth redirect
`luli://oauth` (+ `redreader://rr_oauth_redir`); GitHub repo `bennybar/LuliReddit`;
Aptabase key; cache dir `luli_cache`; every prefs key and secure-storage key.

## Build
```
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export ANDROID_HOME="$HOME/Library/Android/sdk"   # local.properties is gitignored
./gradlew :app:assembleDebug        # compile check
./gradlew :app:testDebugUnitTest    # JVM unit tests
```
Release: `./gradlew :app:assembleRelease` (versionCode scheme 20000+build: it must stay above the Flutter per-ABI codes, abi*1000+build, e.g. 2051) (needs `key.properties` + the .jks at
the repo root, copied from the Flutter project's `android/`; both gitignored).
Emulator: `~/Library/Android/sdk/emulator/emulator -avd Pixel_9_Pro_XL`,
adb at `~/Library/Android/sdk/platform-tools/adb`.

Stack: AGP 9.4 (built-in Kotlin), Kotlin 2.4, Compose BOM 2026.09 +
Material 3 1.5 (Expressive), Navigation Compose (type-safe routes), OkHttp 5,
kotlinx.serialization (JsonElement parsing), Coil 3, Media3, WorkManager,
commonmark-java. minSdk 34. No Play Services (F-Droid/IzzyOnDroid-safe).

## Architecture (package `com.bennybar.luli_for_reddit`)
- `app` (global, `AppContainer`) — manual DI: `app.prefs`, `app.secureStore`,
  `app.settings` (StateFlow<Settings>), `app.session` (SessionManager),
  `app.repository` (every Reddit endpoint), `app.client`, `app.rateLimit`,
  shared stores `app.postOverrides`, `app.hiddenPosts`, `app.history`,
  `app.threadVisits`, `app.contentFilters`, `app.offline`, `app.drafts`, and
  feature modules `app.feed`, `app.post`, `app.forYou`, `app.inbox`, `app.media`.
  Module constructors must use their `c: AppContainer` param, not `app`
  (the global is assigned after construction); `app` is fine inside methods.
- Per-account state implements `UserScoped.onUserChanged(username)`; keys via
  `userScopedKey(prefs, username, base)`.
- `core/` — Json helpers (`el["a"]["b"].str()`), RedditConstants, deep links,
  media links, net (RedditClient, Http, Catbox, Redgifs), storage (Prefs with
  Flutter-compatible types, FlutterMigration, SecureStore reading the Flutter
  encrypted file in place), Analytics (Aptabase), Backup, UpdateChecker.
- `model/` — Post, Comment, InboxItem, Subreddit, RedditUser, Multireddit,
  Flair, Listing (immutable data classes, parsed exactly like the Dart models).
- `nav/` — `Route` (all destinations), `NavCache` (pass Post/InboxItem by id),
  `AppNavigator` = `LocalNavigator.current` / `app.navigator`: push, pop,
  openPost, openLink, openInBrowser, openImage/openGallery/openVideo,
  openPostVideo, share, shareWithTitle, showSnackbar, showActionError.
- `ui/` — theme (`IlayTheme`, Bloom palettes, `LocalVoteColors`, fonts),
  `Overlays.show { done -> … }` for imperative bottom sheets/dialogs (the
  Flutter `showModalBottomSheet` pattern), `ErrorView`, `friendlyError`.
- `feature/*` — screens. ViewModels hold screen state as StateFlow.

## Porting rules
- Port behaviour 1:1 from the Dart file(s): every setting, edge case, comment
  and speed trick (cache-first paint, prefetch, retries, debounces). Keep the
  "why" comments.
- Visual parity with Flutter's Material 3 "Bloom" design: cards
  `surfaceContainerLow` radius 28, stadium buttons/chips, filled inputs
  radius 18, floating pill nav, etc. Read the Dart widget tree for sizes.
- Lists: LazyColumn with stable `key`s and `contentType`; images via Coil
  `AsyncImage` sized to the slot; no work in composition that can be remembered.
