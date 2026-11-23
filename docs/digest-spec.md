# Digest: build brief

**For:** the Claude session that builds this (Opus 5.5). **Written:** 2026-11-23, at
`main` = v2.0.98. **Status:** built (steps A–D, see section 0); not released yet.

Read `CLAUDE.md` first (architecture, build commands, the "never rename" list). This
brief gives you the goal, the decisions already made, where things live, and what
"done" means. It does not dictate code: match the style of the files you touch.

## 0. As built (2026-11-23): what changed from this brief

The owner reviewed each step on their phone. Where this section and the rest of the
brief disagree, this section wins.

- **Shipped so far:** steps A, B, C and D (the bottom tab came early, on request).
- **One list, not grouped by community:** a digest is read across communities; each
  card shows its community, and the "why" line names it ("Top post today in r/pics").
- **Order by** (`digestOrder`): Most notable (default), Most upvoted, Newest, AI's
  assessment (offered while Use AI is on). It sorts what was picked, not what's picked.
- **The cut point (by the numbers):** notable at 2× a typical post; a community's top post
  counts from 1.3×; nothing under 10 points. Standard is 12 posts, at most 2 from a
  community (was 3). A quiet day can give an empty digest.
- **No repeats:** posts shown in an earlier day's digest are left out of a new one.
- **AI, as built:** `digestAiBuilds` (1: the day's first build and Rebuild, default;
  0: every build), `digestAiPick` (default on; off: the numbers pick and the AI only
  writes about the new picks), `digestAiWhy` (default on), `digestOverview`, and
  `digestLanguage` (absent: as AI summaries). The AI lists only posts worth reading.
  When the AI picks but isn't due (automatic build within 12 hours of its last call),
  the build leaves new posts for its next call instead of judging them by the numbers.
- **Settings:** a "Digest" category of its own (not under Feed). Also `digestSwipe`
  (0 left, default; 1 right; 2 both), `digestNotify` / `digestTime`.
- **Bottom tab:** Digest's tab sits after Explore; choosing it moves Inbox into Profile
  (`inboxInProfile`, also its own Appearance switch), with a note; leaving it offers to
  bring Inbox back.
- **Progress line** while building ("Loading posts (4/15)…", "Asking the AI…").
- **Website sign-in:** Reddit sends its web page for a combined `/r/a+b/top`, so each
  community is asked on its own there (about one request per community).
- **iOS list:** the feed's own list (PagedList), so cards follow the layout setting and
  the swipes are the feed's.
- **Unrelated, same build:** Settings › Appearance › Inbox in Profile; the r/IlayFR
  announcement (once) and Settings › About › r/IlayFR.

## 1. What we're building

A **Digest**: "the last 24 hours in the communities you care most about", as a short
list grouped by community, each item with a line saying why it's there. Built once a
day or on demand. It works without AI; with the user's AI key it gets smarter.

It must exist on **both apps** (Kotlin in `app/`, Swift in `swift/`), with the same
behaviour, settings keys and stored formats.

## 2. Decisions already made (don't reopen)

| Topic | Decision |
|---|---|
| Communities | Default: the user's starred favourites. Editable list in Settings, so it can differ from favourites. Cap 15. |
| Window | Last 24 hours. |
| Without AI | Posts judged against their own community's normal, not raw upvotes (section 5). |
| With AI | One call per digest: rate importance, pick, write a one-line "why". Non-AI step runs first and narrows to ~40 candidates. |
| Overview paragraph | Optional, its own switch, off by default. Same AI call. |
| Delivery | The user chooses: a daily notification at a time they set, or just a screen that is fresh when opened. |
| Where it shows | One setting, "Show Digest in": **Posts chip** (default) / **Menu only**. A **Bottom tab** choice is planned as the last step, not part of the first releases (section 2a). |
| AI failure | Fall back to the non-AI digest, and say so on the screen. |
| Read items | In the Digest, **swiping a card left marks it read**. A "Show read" option on the screen shows or hides read items. |
| Refreshing | The app remembers what it has already digested today. A refresh only processes posts it hasn't judged yet; it never redoes the whole digest, and it can always be asked for (section 6a). |
| Explaining it | Settings has a "How Digest works" explainer, shown before the feature is first turned on (section 7). The release's What's new entry explains the feature properly (section 9). |
| Privacy | With AI on, post titles and the user's interest words go to the AI provider they configured. The setting's subtitle must say that. |

Decisions I made that the owner hasn't explicitly confirmed. Keep them unless they
object, and mention them when you report:

- The **Posts chip is not a feed choice**: tapping it shows the digest in place of the
  feed, but it isn't saved as the Posts tab's feed, and Settings › Feed › "Posts tab
  feed" doesn't list it. The next launch opens the user's normal feed.
- Whatever "Show Digest in" says, the digest is also reachable from the side bar and
  the Profile ⋯ menu while it's enabled.
- The last 7 digests are kept, so a missed day can be read later.

## 2a. Who decides, and the scope guard

The owner asked that this brief, not the conversation of the day, define the feature:
they know they get carried away, and want something people actually use rather than a
settings maze. So:

- **Build what's here, and nothing more.** No extra settings, modes, filters or
  screens. If something seems missing, ask (section 10) instead of adding it.
- **If the owner asks for an extra during the build**, don't build it on the spot.
  Add it to the "Later" list at the end of this file with one line on what it's for,
  and say so. It gets decided after the current step ships.
- **The test for any addition:** does someone who turns Digest on and never opens its
  settings still get a good digest? Defaults must be enough.
- **It ships in steps**, each usable on its own, so real use decides what comes next:

  | Step | What ships | Phases (section 9) |
  |---|---|---|
  | A | The Digest without AI: screen, Posts chip or menu, communities, size, swipe to mark read, Show read, refresh that only adds what's new, the explainer | 1–2 |
  | B | AI picks and explains, optional overview | 3 |
  | C | Daily notification | 4 |
  | D | Bottom tab placement, only if the owner still wants it after using A–C | 5 |

  Stop after each step and ask the owner before releasing it and before starting the
  next.

Things deliberately left out, so they don't creep back in:

- **No separate "AI threshold" setting.** The size setting already says how much you
  want; with AI on, Brief means the AI's five most important.
- **No per-community settings** (weights, sizes, mute words). The communities list is
  the control.
- **No filters or sorting on the Digest screen** beyond Show read.
- **No digest of comments, no weekly digest, no sharing a digest.**
- **No fifth bottom tab until step D.** It touches the app's whole shell on both apps,
  and the chip already puts the digest one tap away.

## 3. Constraints that have bitten us before

- **Reddit request budget.** The owner's phones and the emulator share ~100
  requests/minute on one account. A digest build should cost 2–4 requests, never one
  per community by default (section 5 says how).
- **Don't spend the owner's AI key.** No real AI calls in tests or on the emulator
  unless they say so. Test the AI path against a fake (section 9).
- **Never act on the owner's Reddit account** on the emulator (it's signed in as their
  real account): no votes, saves, joins, mark-read, replies. Take care with sideways
  swipes and stray taps; check the screen before tapping.
- **Emulator hygiene:** restore any setting you change, force-stop the app and kill the
  emulator when done. It needs the *release* build (`adb install -r`), not debug.
- **Never rename** prefs keys, the applicationId, etc. (see `CLAUDE.md`). New keys are
  fine; once shipped they're permanent, so choose them once (section 7).
- **Ask before releasing.** Commit locally as you go; don't push, tag or release until
  the owner says. Releases are APKs only; the iPhone build is installed on their phone.
- **Leave `gradle.properties` out of commits** (the owner has a local edit).
- Don't promote the website sign-in in any user-facing text.

## 4. Where things live

Android paths are under `app/src/main/java/com/bennybar/luli_for_reddit/`; iOS under
`swift/Ilay/`. Each Android file below has a Swift twin with the same name unless noted.

| Need | Look at |
|---|---|
| Favourites / subscriptions | `data/RedditRepository.kt` `getSubscribedSubreddits()` (cached), `Subreddit.userHasFavorited`. For You keeps a snapshot: `feature/foryou/ForYouModule.kt` (`loadSubsSnapshot`). |
| Several communities in one request | `ForYouModule.kt`, the `hot()` helper: `/r/a+b+c/...`, ≤8 names, with a per-community fallback when the combined listing is refused (403). Reuse the idea. |
| Ranking prior art | `feature/foryou/Ranker.kt`: `velPct` (per-community percentile), `titleKeywords` (`Keywords.kt`), `sameStory` (private there; make it shared rather than copying it), `normalisedUrl`. |
| What the user likes | `feature/foryou/Stores.kt`: `KeywordStore`, `InterestStore`, `ExplicitPrefsStore` (More/Less choices). |
| Read / hidden / filtered posts | `app.history.ids`, `app.hiddenPosts`, `app.contentFilters`. Marking read: `state/HistoryStore.kt` (`markViewed`, `removeViewed`). |
| Swipes on a card | `feature/feed/PostCard.kt` takes a `swipeOverride`; `feature/feed/SavedScreen.kt` uses it (both sides unsave), and `feature/feed/HistoryScreen.kt` shows a swipe that removes the row. Swipe specs: `feature/feed/SwipeActions.kt`. |
| Sheets and dialogs | `ui/Overlays` (`Overlays.show { done -> … }`), `feature/settings/SettingsWidgets.kt` (`confirmDialog`), and `confirmRedditHome()` in `SettingsScreen.kt`: an explainer the user must accept before a feature turns on. |
| AI call | `feature/post/AiService.kt` (OpenAI-compatible `/v1/chat/completions`; `chat()` is private, add a `digest()` beside `summarize()`/`translate()`; `translate()` shows the JSON-in/JSON-out pattern and lenient parsing). Key: `app.post.aiKey` / `secureStore.openaiKey()`. Settings: `aiModel`, `aiBaseUrl`, the summary language. Call site to copy: `feature/post/AiSheets.kt`. |
| Per-account stored lists | `state/SummaryStore.kt` (a file per account, `UserScoped`), `feature/foryou/Seeder.kt` (saves raw posts via `repository.rawPost(id)` and reloads them with `Post.fromData`). |
| Settings model + store + screen | `settings/Settings.kt`, `settings/SettingsStore.kt`, `feature/settings/SettingsScreen.kt` (`switch`, `tile`, `pickOption`; iOS: `b.toggle`, `b.picker`). The "Posts tab feed" picker added in v2.0.98 is a good recent example on both apps. |
| Feed chips | Android `feature/feed/PostListView.kt` (`FeedChoice`, the chip row); iOS `Features/Feed/FeedChips.swift`. |
| Bottom tabs | Android `feature/home/HomeScreen.kt` (`navItems`, the floating pill, `NavButton`); iOS `Features/Home/HomeScreen.swift` (`navItems`, `TabView`). Tab index is used in several places (`index == 0`, `tabReselect(3)`, the Back handler): grep before adding a fifth. |
| Side bar + Profile menu | `settings/SideBarItems.kt` (`SideBarItem`, persisted by id; there's `SideBarItemsTest`), `feature/home/AccountTab.kt` (`YourStuffMenu`). |
| Routes | `nav/Route.kt` (`Summaries`, `History` are the pattern); iOS `Nav/Route.swift` + `RouteTests` (every route must survive encoding). |
| Post cards with a "why" line | `Post.feedReason` renders as the reason row above a card (`feature/feed/PostCard.kt` `ReasonRow`). The digest can reuse cards this way. |
| Top bar styles | Screens follow Settings › Appearance › Top bar. `feature/feed/CollapsingTitle.kt` is the new Expandable header (Android); iOS uses large titles. |
| Scheduled work + notifications (Android) | `feature/inbox/InboxNotifications.kt` (WorkManager, channel creation, `openIntent`), `InboxActionReceiver.kt`, `res/drawable/ic_stat_ilay.xml`. |
| Notifications (iOS) | `Features/Inbox/InboxNotifications.swift` (BGTaskScheduler; iOS decides when), `Features/Reminders/PostReminders.swift` (a **local notification at a set time**, which is what a daily digest reminder needs). |
| What's new + version | `feature/about/WhatsNew.kt` (`CHANGELOG`), `app/build.gradle.kts`, and **`swift/project.yml`** (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` must match Android's; the `.xcodeproj` is generated and gitignored, so edit both or regenerate). |

## 5. Building a digest (no AI)

**Candidates.** For the digest communities, ask Reddit for the day's top posts in
combined requests of up to 8 communities each (`/r/a+b+c/top?t=day`, limit 100). A
combined listing is dominated by the big communities, so afterwards, for any community
that got fewer than 3 posts, make one request for that community alone (limit 10).
Expected cost: 2 requests for 15 communities, plus a few top-ups.

**Drop:** stickied posts, posts older than 24h, hidden or filtered ones, NSFW according
to the user's existing settings, and all but the best copy of one link or story
(`normalisedUrl`, `sameStory`). A post the user had **already read before it was first
judged** is dropped too: it shouldn't take a place. A post they read *after* it was
picked stays in the digest, shown as read (section 8).

**Notability**, per post, against its own community in this batch:

```
notability = 0.7 × (score / community median score)
           + 0.3 × (comments / community median comments)     (medians floored at 1)
```

Each community's top post always counts as notable. This is a starting point: tune it
if the results look wrong, but keep it relative to the community and keep it
explainable.

**Size** (a setting):

| Size | Items | Per community |
|---|---|---|
| Brief | best 5 | at most 2 |
| Standard (default) | best 12 | at most 3 |
| Everything notable | notability ≥ 2, or the community's top post; cap 30 | at most 5 |

A quiet day gives a short digest. Never pad it.

**The "why" line without AI** comes from the numbers, for example "3× a normal day in
r/x" or "Top post today in r/x · 240 comments".

Put the selection in a pure function (inputs: candidates, read ids, size; output:
ordered items with notability and why) so it's unit-testable on both apps, like
`rankForYou`.

## 6. The AI step

Only when "Use AI" is on and a key exists. It runs after section 5's filtering, on the
top ~40 candidates by notability (not the final picks: the AI chooses).

**One request.** Send:
- the candidates as a JSON array: index, community, title, score, comments, age in
  hours, flair, and the first ~300 characters of the body if it's a text post;
- the user's interests: their strongest learned keywords (top ~15), and their explicit
  More/Less topics and communities;
- how many items the chosen size wants, and whether an overview paragraph is wanted;
- the language to write in (the existing summary-language setting).

**Ask for JSON only:**

```json
{ "overview": "…", "items": [ { "i": 3, "importance": 4, "why": "…" } ] }
```

`importance` is 1–5, `why` is one sentence (aim under 140 characters), `overview` is
omitted unless requested (2–4 sentences). Parse leniently (models wrap JSON in code
fences), ignore unknown indices, and treat anything unusable as a failure.

**Using the ratings:** items rated below 2 are never shown. The rest are ordered by
importance, then notability, and the size setting decides how many (Brief: the five
most important). There is no separate threshold setting (section 2a).

**On failure** (network, bad JSON, refusal): use the non-AI digest and show a small
note on the screen ("AI wasn't available; picked by activity").

**Cost guard:** an automatic build makes at most one AI call per 12 hours. A manual
refresh may make one, but only for posts not judged yet (section 6a), and not at all
when there are none.

## 6a. Remembering what's been digested

The owner refreshes several times a day. A refresh must not redo the whole digest, and
must not send the AI the same posts twice.

Keep, per account and per day (local calendar day), a record of every candidate that
has been judged: post id, when, the verdict (picked or not), and for picked ones the
importance and "why". There is no database in the app: store it in the digest's
per-account file, like the other stores. Prune it with the 7-day history.

On a refresh (manual, on open, or scheduled) for a day that already has a digest:

1. Fetch candidates as in section 5. This still costs the Reddit requests; it's the
   only way to learn what's new.
2. **Already judged:** keep the verdict, "why" and importance as they are. Update the
   numbers shown (score, comments) from the fresh data.
3. **New candidates** go through section 5, and through the AI step if it's on. The AI
   sees only these.
4. **A second look, once:** a post that wasn't picked earlier but whose notability has
   since at least doubled is treated as new.
5. Merge: today's digest gains the new picks. Nothing already shown is removed or
   reordered away under the user; new items are marked "New" until seen.
6. The size setting is a target for the first build of the day. Later refreshes may add
   up to the per-community cap, and "Everything notable" keeps its cap of 30.

The first build of a new day starts a new digest; yesterday's stays in the history.

A manual refresh within 2 minutes of the last one shows the stored digest without
asking Reddit again (and says "Up to date").

Changing the communities, the size, or the AI switches doesn't wipe the record: it
applies from the next refresh. A "Rebuild today's digest" action in the screen's menu
does wipe today's record and starts over, for when the user wants exactly that.

## 7. Settings

New section or group, "Digest", in Settings › Feed. Keys below are final once shipped;
both apps must use the same names and types.

| Setting | Key | Type / default |
|---|---|---|
| Digest (master switch) | `digestEnabled` | bool, false |
| Communities | `digestSubs` | string list, lowercase; **absent = follow favourites** |
| Size | `digestSize` | int: 0 Brief, 1 Standard, 2 Everything notable; default 1 |
| Use AI to pick and explain | `digestAi` | bool, false. Disabled with a hint when no AI key is set. Subtitle states what is sent to the AI provider. **Owner's rule: never on unless the user turns it on.** An AI key already set (for summaries, translation) must not switch it on, pre-tick it, or make a prompt that defaults to it: no one's AI money is spent without them knowing. |
| Overview paragraph | `digestOverview` | bool, false (needs `digestAi`) |
| Daily notification | `digestNotify` | bool, false |
| Time | `digestTime` | int, minutes after midnight, local; default 480 (08:00) |
| Show Digest in | `digestPlace` | int: 0 Posts chip, 1 Bottom tab (after Explore; the owner asked for it on 2026-11-23, so step D came early), 2 Menu only; default 0. Read an unknown value as 0. |
| Show read items | `digestShowRead` | bool, false. Changed from the Digest screen itself (section 8); also listed here. |

Per-account data (the digest list, communities) uses `userScopedKey` / a per-account
file, like the stores in section 4.

The communities editor: the user's subscriptions as a checklist, favourites first,
with "Use my favourites" to go back to following them. Enforce the cap of 15 with a
clear message.

**"How Digest works" explainer.** People should be able to decide whether to use this,
and how, before turning it on. A sheet (or dialog) that:

- opens the first time the Digest switch is turned on, with "Turn on" / "Not now", as
  `confirmRedditHome()` does for Reddit Home;
- is always reachable from a "How Digest works" row at the top of the Digest settings.

It should say, in plain words and short sections:

- **What it is:** the notable posts of the last 24 hours from the communities you
  choose, in one short list.
- **How it picks without AI:** by how unusual a post is for its own community, so small
  communities aren't drowned out.
- **What AI adds, and what it costs:** it picks and explains using your own AI key; one
  small request per digest (fewer on refresh, since only new posts are sent); post
  titles and the topics you read are sent to the AI provider you set up. Nothing is
  sent unless you turn "Use AI" on.
- **When it's built:** when you open it, or daily at your chosen time if you turn the
  notification on (on iPhone: a reminder at that time, built when you open it).
- **Where you'll find it:** a chip at the top of Posts, or the menu: your choice.
- **What stays on your phone:** the digests themselves and what was already digested.

Write this text once and use the same wording on both apps. Keep it accurate to what
was actually built: if a behaviour changes during the build, change the text.

## 8. Screen, placement, delivery

**The Digest screen**
- Title "Digest", with the day ("Today", "Yesterday", a date). A way to open the
  previous 6.
- The overview paragraph on top, when there is one.
- Items grouped by community, each a normal post card with its "why" line. Opening a
  post, voting, saving etc. behave as anywhere else.
- **Swipe a card left to mark it read** (the trailing side in a left-to-right layout;
  mirror it for right-to-left). Use the card's `swipeOverride`, as Saved does. Marking
  read goes through the history store, so the post is read everywhere in the app. The
  other swipe direction keeps the user's own setting. Offer Undo, as other removals do.
- **Show read** (`digestShowRead`), in the screen's toolbar or menu. Off: read items
  leave the list (after the swipe's Undo window, not under the finger). On: they stay,
  dimmed like read posts elsewhere. A community whose items are all read and hidden
  doesn't show an empty header. When everything is read and hidden, say so ("You're all
  caught up") with a "Show read" button, not a blank screen.
- Pull to refresh updates it (section 6a): it adds what's new and never redoes the
  whole digest. New items are marked "New". While the first build runs: a loading
  state, not an empty screen.
- The screen's menu: Show read, Previous digests, Rebuild today's digest, Digest
  settings.
- Empty states that say why: nothing notable today / no communities chosen (with a
  button to Settings) / signed out.
- "Fresh when opened": opening the screen builds a new digest when the newest one is
  more than 12 hours old.

**Placement** (`digestPlace`), only while `digestEnabled`:
- **Posts chip:** a "Digest" chip in the Posts chip row, after For You / Blend / Home.
  A dot or count on it while the digest has unread items. See section 2 for its behaviour.
- **Menu only:** no chip.
- **Bottom tab (step D only):** a fifth tab. Check labels still fit on a narrow phone
  on Android's floating pill, and every place that assumes four tabs.
- Always: a side bar item and a Profile ⋯ menu entry.

**Delivery** (`digestNotify`):
- **Android:** a daily WorkManager job at `digestTime` builds the digest in the
  background (network required), then posts one notification in a new "Digest" channel:
  "Your digest: 9 posts from 5 communities". Tapping opens the Digest screen.
  Reschedule when the time or switch changes (see how the inbox worker replaces its
  periodic work when its interval changes).
- **iPhone:** iOS won't run background work at an exact time. Schedule a repeating
  local notification at `digestTime` ("Your digest is ready") as `PostReminders` does,
  build the digest when it's opened, and also build opportunistically in the existing
  background refresh. Say this plainly in the setting's subtitle on iOS.
- With the notification off, nothing is scheduled; the screen builds on open.

## 9. How to work

Build in phases, each one finished on **both apps** before the next, with a local
commit per phase:

1. **Engine and storage, no UI.** Candidate fetch, the selection function, the store
   for the last 7 digests and the "already digested" record, settings keys. Unit tests
   on both apps for the selection (relative scoring, per-community caps, sizes, quiet
   day, posts read before judging dropped, same story kept once), for the refresh merge
   (judged posts keep their verdict, only new ones are processed, a post that doubled
   gets one second look, nothing shown is removed, a new day starts a new digest) and
   for the settings round-trip (iOS has `SettingsCatalogTests` and
   `FlutterCompatTests`; Android has `settings/` tests).
2. **Screen, Settings, placement.** Chip, menu entries, the communities editor, the
   "How Digest works" explainer, swipe to mark read, Show read. **Step A ships here.**
3. **AI.** The request, parsing, ordering by importance, overview, fallback, cost
   guard, and that a refresh sends only posts not judged yet. Tests feed the parser
   canned replies (clean JSON, fenced JSON, garbage, wrong indices). No real AI calls.
   **Step B.**
4. **Notification and scheduling.** **Step C.**
5. **Bottom tab**, only if the owner asks for it after A–C. **Step D.**

Verification for each phase:
- `./gradlew :app:testDebugUnitTest :app:assembleRelease` (see `CLAUDE.md` for the
  environment variables).
- iOS tests on the existing iPhone Air simulator only (never create simulators), under
  the shared lock: `until mkdir /tmp/ilay-sim.lock; do sleep 5; done; … ; rmdir
  /tmp/ilay-sim.lock`, with `-destination id=9591C27B-F376-4249-A3AC-13D6EFEEDEC3
  -only-testing:IlayTests`, then `xcrun simctl shutdown all`.
- On the Android emulator (`Pixel_9_Pro_XL`, start with `-dns-server 8.8.8.8,1.1.1.1
  -no-audio -no-window`): turn Digest on, build one, check each placement that exists
  at that step, then put every setting back. One or two builds is enough; don't loop.
- **Swipe to mark read changes the owner's real reading history** on the emulator.
  Test it on one item at most, undo it, and say that you did. Prefer the unit tests
  for the rest.
- Say plainly what you couldn't check (the iPhone screens, the AI path with a real
  key, a notification firing at its time).

At the end of each step (section 2a): bump the version in `app/build.gradle.kts`
**and** `swift/project.yml`, and ask the owner before pushing or releasing.

**What's new must feature the Digest, and explain it well**, in step A's release (later
steps add a line for what they bring). The `Release(...)` entry
at the top of `CHANGELOG` (`feature/about/WhatsNew.kt`) is what every user sees once
after updating, and many will learn the feature exists only from it. Don't settle for
one line. Lead the entry with the Digest and cover, in a few short highlights:

- what it is and why you'd want it (the notable posts of the last day from your
  favourite communities, in one short list);
- where to turn it on (Settings › Feed › Digest) and that "How Digest works" there
  explains it;
- that it works without AI (in step A, don't promise the AI part before it ships);
- the choices: which communities, how long, where it shows;
- swipe left to mark read, and that refreshing only adds what's new.

Look at how the sheet renders entries before writing (it shows the latest release's
highlights; `WhatsNewTest` fails if the top entry isn't the new `versionName`). If the
current format can't carry this without becoming a wall of text, a short lead
highlight plus a "How Digest works" button in the sheet is a reasonable addition:
propose it to the owner rather than squeezing it in. The GitHub release notes should
carry the same explanation.

## 10. Ask the owner if

- (step D) the bottom tab can't fit five items cleanly on a narrow phone;
- the per-community top-up requests push a build past ~6 requests;
- you want to change anything in section 2;
- you need a real AI call to finish.

## Later (not part of this build)

Ideas raised after this brief was written go here, one line each, and are decided
after the current step ships.

- *(empty)*
