import SwiftUI

/// One release's highlights, as shown in What's new.
struct Release: Identifiable {
    let version: String
    let date: String
    let highlights: [String]
    var id: String { version }
}

/// What's new, newest first: the notable changes of each release since Ilay
/// 2.0 (the native app, with Reddit Home). Add the new release at the top
/// with every release.
let CHANGELOG = [
    Release(version: "2.0.122", date: "Nov 27, 2026", highlights: [
        "User pages and your Profile tab fold exactly like a community page: the picture and name slide into the top bar, the round buttons keep their blur, and the banner no longer lingers under the status bar (#298)",
        "A low-resolution banner no longer shows a blurry line where it meets the page",
        "Settings › Floating button in subreddits: its own choice, separate from Home (#300)",
        "Hide the floating button while scrolling: it disappears as you scroll down and comes back on the way up (#301)",
        "Settings › Read & hidden › Save search history: turn it off to keep no recent searches (#302)",
        "Translation: the \"OpenAI\" service is now \"Your AI service\"; it uses your AI summaries key and base URL, so OpenAI-compatible services like Grok, Groq or Gemini work too (#299)",
    ]),
    Release(version: "2.0.121", date: "Nov 26, 2026", highlights: [
        "User pages and your Profile tab get the community page's header: the banner under the status bar with round buttons on it, the picture over its edge, the name once, karma and account age, a round Follow and the description; without a banner, a large centred picture and name (#293)",
        "Another user's page has a 🔍 that searches their posts",
    ]),
    Release(version: "2.0.120", date: "Nov 26, 2026", highlights: [
        "Image posts upload their image again: Reddit had started rejecting how Ilay asked for the upload, so posts went up as text only (#296)",
        "Community banners: the status bar icons follow the banner under them and come back right when you leave (#291); a short, low-resolution banner shows sharp over its soft backdrop (#294)",
        "Settings › Feed › \"New posts\" button: turn off the pop-up that offers newer posts (#292)",
        "Search suggestions sit in a rounded group like the rest of the search page (#290)",
        "Explore, Profile and Inbox open search with the same growing animation as Posts (#295)",
    ]),
    Release(version: "2.0.119", date: "Nov 26, 2026", highlights: [
        "Appearance: a Preview button on each group (Layout, Colour, Text, Comments) opens the real post with that group's options under it, instead of a preview pinned over the page (#288)",
        "\"r/ and u/ before names\": the setting now also hides the u/ before user names (#289)",
        "Search: a full-width field with ← inside it, growing out of the search button with the words travelling along; page searches (Saved, History, Settings, Summaries) grow from their own 🔍 as a thicker pill, and with the Full top bar they and communities get the round search bar (#285)",
        "Community and profile pictures grow out of their circle into the viewer and back; the viewers close with a back arrow instead of × (#287)",
        "A community's description grows and shrinks smoothly on Show all / Show less (#286)",
        "Spoilers in the Home feed show the photo when tapped, not a blur, and stay revealed on the post page",
    ]),
    Release(version: "2.0.118", date: "Nov 26, 2026", highlights: [
        "Appearance: a live preview of a real post at the top, at true size, that changes as you change any option; it switches to a sample comment thread for comment sizes and steps aside for options it can't show",
        "Appearance: options change right on the page (layout chips, segmented choices, colour swatches, sliders), grouped as Layout, Colour, Text and Other, so nothing closes while you try them",
    ]),
    Release(version: "2.0.117", date: "Nov 26, 2026", highlights: [
        "Appearance: Corner roundness (Round, Medium, Small, Square) for posts' cards and media (#283)",
        "Two new post layouts: Compact (flat rows, a meta line on top, a slim action row) and Compact cards (the poster's picture, votes on the right) (#284)",
        "The poster's picture shows with the website sign-in too, where Reddit sends it with the post",
    ]),
    Release(version: "2.0.116", date: "Nov 26, 2026", highlights: [
        "Home feed: posts arrive complete on the first paint (flair, icons, size), and faster; cards land where they stay after a pull to refresh",
        "Feeds: cards fly in once, stay put when updated, and a fresh page doesn't yank you to the top",
        "Search: the search page zooms out of the search button (#271); with the Expandable top bar, Saved, History, Settings and Summaries search from a 🔍 in the bar (#247)",
        "Subreddit page: the icon sits lower, Join is a + by the name with a \"Joined\" note, no empty description card, and the description keeps its size (#277, #278)",
        "Tap a community's or user's picture to see it full screen (#279)",
        "Search history: no more bare author: entries; a search in someone's posts shows their u/name tag (#281)",
        "Subreddit banners: the phone banner when there is one, and no more blurry zoom",
    ]),
    Release(version: "2.0.115", date: "Nov 25, 2026", highlights: [
        "Home feed: posts appear at their final size, the photo stays put instead of loading twice, and galleries fill in without resizing",
        "Home feed: the flair fades in when it arrives",
    ]),
    Release(version: "2.0.114", date: "Nov 25, 2026", highlights: [
        "Subreddit header: a bigger icon and name, sitting lower, and the icon's ring fully around it (#268)",
        "Settings: the big title with the Expandable top bar, and the list split into two groups (#268, #276)",
        "Videos: autoplay Off / On Wi-Fi only / Always, and pinch to zoom in the full-screen viewer",
        "Posts: the poster's picture on post cards, in Appearance (off by default) (#270)",
        "Comments: collapsing a comment animates (#273); a setting to not reopen threads where you left off (#269)",
        "Searching a profile shows a \"From u/…\" tag (#271)",
        "Fixes: popups spring back when not swiped away (#269), AI shows busy errors instead of spinning (#267)",
    ]),
    Release(version: "2.0.113", date: "Nov 25, 2026", highlights: [
        "GIFs: GIF posts Reddit labels as images now play, as Reddit's small mp4 copy (#265)",
        "Settings → Check for updates shows what's new in the release it offers (#266)",
        "Subreddit header: the community's icon is no longer covered by the banner (#257)",
    ]),
    Release(version: "2.0.112", date: "Nov 25, 2026", highlights: [
        "Subreddit header: a shorter band, in your accent colour when the community has no banner or colour; the description card and the icon's ring in the feed's colours (#257)",
    ]),
    Release(version: "2.0.111", date: "Nov 25, 2026", highlights: [
        "Videos: a playback speed button (0.5× to 4×) next to Mute, in the viewer and Browse media (#260)",
        "Expandable top bar: the big title on Saved, History, Read later, Drafts and Custom feeds too (#247)",
        "Subreddits, with the Expandable top bar: the community's banner (or its colour) as the header, the description in a card with Show all (#257)",
    ]),
    Release(version: "2.0.110", date: "Nov 25, 2026", highlights: [
        "Videos from search and the Home feed can be downloaded again, with their sound (#261)",
        "Viewing a single thread: the capsule stays while you scroll and swipes away sideways, as does \"Back where you left off\" (#264)",
    ]),
    Release(version: "2.0.109", date: "Nov 24, 2026", highlights: [
        "Search: a time range (Hour to All time) beside the sort, for any sort, not only Top (#255)",
        "AI: Gemini's OpenAI-compatible URL works as the custom base URL (#254)",
        "Galleries: no more \"X images · tap one to view\" line under them (#256)",
    ]),
    Release(version: "2.0.108", date: "Nov 24, 2026", highlights: [
        "Settings regrouped: new Read & hidden and Navigation pages, \"AI summaries\" is now AI, and Account holds your account, keys and API usage. Nothing was changed or removed, and search finds every setting",
        "Viewing a single thread: a floating capsule with Show all that fades while you scroll (#253)",
    ]),
    Release(version: "2.0.106", date: "Nov 23, 2026", highlights: [
        "Inbox: one row of chips (All, Unread, Replies, Mentions, Messages, Sent) in place of the tabs and the filter menu (#246)",
    ]),
    Release(version: "2.0.105", date: "Nov 23, 2026", highlights: [
        "Post text in feeds shows its bold, italic, strikethrough and spoilers instead of the markdown marks (#241)",
        "Comment buttons only on tap: the comment grows and shrinks smoothly as its buttons show and hide; no more bounce on Save (#244)",
    ]),
    Release(version: "2.0.103", date: "Nov 23, 2026", highlights: [
        "Settings › Comment buttons only on tap: comments show just their text, with the score by the time; tap a comment for Vote, Reply and the rest (#239)",
    ]),
    Release(version: "2.0.102", date: "Nov 23, 2026", highlights: [
        "Digest: a post you open and come back from leaves the list too, not only one you swipe (Show read keeps them)",
        "Digest: Standard is now about 20 posts (was 12). Rebuild today's digest from its menu to see it now",
    ]),
    Release(version: "2.0.101", date: "Nov 23, 2026", highlights: [
        "Digest: marking a post read takes it off the list at once, as hiding a post does in your feed; Undo puts it back",
        "Haven't tried Digest yet? A card at the top of Posts offers it, once",
    ]),
    Release(version: "2.0.100", date: "Nov 23, 2026", highlights: [
        "Text sizes for post titles, post text and comments, each on its own (Settings › Appearance, under Font size). They start at today's size, and \"Reset text sizes\" puts them all back",
    ]),
    Release(version: "2.0.99", date: "Nov 23, 2026", highlights: [
        "New: Digest. The posts that stood out in the last 24 hours in your favourite communities, in one short list. Turn it on in Settings › Digest, where \"How Digest works\" explains it",
        "It picks by how unusual a post is for its own community, so a small community's big day isn't drowned out, and a quiet day gives a short digest. No AI needed",
        "Your choice of communities (your favourites, or up to 15), how long it is, and where it shows: a chip at the top of Posts, its own tab, or only in the side bar and Profile menu",
        "Optional: with your own AI key, \"Use AI\" picks the posts, says why each matters, and can open with a short overview. It's off unless you turn it on, and a refresh only sends the new posts",
        "Order it your way: most notable, most upvoted, newest, or the AI's assessment",
        "Swipe a post to mark it read (left, right or both: your choice). Pull down for what's new: a refresh only adds posts, nothing already there goes away",
        "A daily notification at the time you pick, with your digest ready",
        "Settings › Appearance › Inbox in Profile: Inbox opens from an envelope at the top of Profile, for a three-tab bottom bar",
        "Our own subreddit: r/IlayFR, for news, help and ideas (Settings › About)",
    ]),
    Release(version: "2.0.97", date: "Nov 22, 2026", highlights: [
        "Home and Blend scroll more smoothly as you go deeper: Ilay reads only the new posts from your Reddit Home",
        "For You loads its later pages faster, and a slow source no longer holds up the first one",
        "On a slow connection, For You keeps what arrives late for the next page instead of dropping it",
        "With Hide read posts on, For You pages come back full",
    ]),
    Release(version: "2.0.95", date: "Nov 22, 2026", highlights: [
        "Comments deep in a thread keep their ⋯ menu (Edit, Delete…): on narrow rows Reply and Collapse show just their icons",
        "Polls: \"Vote on reddit.com\" opens the post on Reddit's site, where you can vote",
    ]),
    Release(version: "2.0.93", date: "Nov 22, 2026", highlights: [
        "Long threads reopen where you left off after using the jump buttons too, and \"Back where you left off\" sits at the top instead of over the buttons",
        "More commenters' pictures show in long threads, and your own on your comments",
        "A reply with an image no longer says it failed when Reddit posted it",
        "Collapse AutoModerator and pinned comments: every pinned comment now starts collapsed",
        "New comment in the thread's ⋯ menu, your picture on the Profile tab, and Report for comments and users",
    ]),
    Release(version: "2.0.92", date: "Nov 17, 2026", highlights: [
        "The screen stays on while a video plays full screen",
        "Tap a user flair that's cut short to read all of it",
        "New setting: Hide thread buttons while scrolling (Posts & comments). They step aside while your finger scrolls a thread",
    ]),
    Release(version: "2.0.91", date: "Nov 16, 2026", highlights: [
        "Shorter For You tags: \"From r/x\" for communities you engage with, \"Subscribed · r/x\" for yours, and a fire icon for Trending",
        "When the next page fails to load, the feed says so with a Retry button instead of just stopping. Profile, Saved and Search lists show where they end",
        "Swiping to delete a message asks first",
    ]),
    Release(version: "2.0.90", date: "Nov 16, 2026", highlights: [
        "Spoiler posts keep their text covered, in feeds and in the thread, until you tap it",
        "Threads in contest mode say so above the comments: random order, scores hidden",
    ]),
    Release(version: "2.0.89", date: "Nov 16, 2026", highlights: [
        "Collapse AutoModerator and bots is only in Settings › Posts & comments now: it was also in Content filters, the same switch twice",
    ]),
    Release(version: "2.0.88", date: "Nov 16, 2026", highlights: [
        "Translation: DeepL with your own API key, as a service for languages your phone can't translate (Settings › Translation service)",
    ]),
    Release(version: "2.0.87", date: "Nov 16, 2026", highlights: [
        "Settings › Feed › Post text in feeds: show 5 or 10 lines of a post's text in feeds",
        "Your own comments have Edit and Delete at the top of their ⋯ menu",
        "Removing an entry from History slides it all the way out before it goes",
    ]),
    Release(version: "2.0.86", date: "Nov 16, 2026", highlights: [
        "A comment's ⋯ menu has Select text, to copy just part of it",
        "Names in comments have their own softer colour, so they stand apart from the text",
    ]),
    Release(version: "2.0.85", date: "Nov 16, 2026", highlights: [
        "Tapping the top bar's empty space no longer opens the post under it",
        "Flairs beside long names shorten or step aside instead of showing as an empty chip, and their images are bigger",
        "Links in a community's description, About and rules open",
        "Search suggests communities as you type",
        "Profile pictures in comments also work when signed in with an API key",
        "Mark read on scroll now marks a post once you've scrolled past it",
        "Collapse AutoModerator also collapses pinned bot comments, and it's in Posts & comments settings too",
        "The bottom bar hides with the same scroll as the floating buttons",
        "One Back gesture leaves the media viewer; Tune For You has the new menu look",
        "Settings: the For You and Blend switches say what they are: what Home shows",
    ]),
    Release(version: "2.0.84", date: "Nov 15, 2026", highlights: [
        "Explore: Popular and All are separate sections, so you can move or hide each one (side by side, they stay a pair)",
        "Filtering your communities shows Favorites, Recently visited and Subscriptions under their own headers",
        "The filter bar is one connected piece: its filter icon opens the sort, and the Favorites star is attached to it",
    ]),
    Release(version: "2.0.83", date: "Nov 15, 2026", highlights: [
        "Threads reopen where you left off, with a button to jump back to the top",
        "Menus have a fresh look: options in rounded groups with icons, and what's picked as a tinted pill",
        "Profile's sort: Top's time ranges show in the same menu",
    ]),
    Release(version: "2.0.82", date: "Nov 15, 2026", highlights: [
        "Posts you voted on glow in the vote's colour, as comments do (Settings › Mark what you voted on › Glow)",
        "Floating buttons fold only once you really scroll, open with a little bounce, and have less rounded corners",
        "Explore: each community in a list is its own segment, and the community rows move like the gallery carousel",
        "Explore's Full top bar is the same as Home's; with the side bar on, your picture is smaller and the search bar centred",
    ]),
    Release(version: "2.0.81", date: "Nov 15, 2026", highlights: [
        "Calm comments: swiping a comment to vote no longer hides its thread lines; they slide with it",
        "History and Summaries: the selection bar's × and count line up with the title",
        "For You's subtitle is now \"On your phone\", so it fits beside the title",
    ]),
    Release(version: "2.0.80", date: "Nov 12, 2026", highlights: [
        "Explore: Popular communities, a row of Reddit's popular communities you haven't joined, with Join",
        "It's loaded at most once a day, and you can hide or move it in Settings › Appearance › Explore sections",
    ]),
    Release(version: "2.0.79", date: "Nov 12, 2026", highlights: [
        "Explore redesign: each section sits in its own rounded card",
        "Recommended communities show their banner, with the picture over it",
        "Favorites is a row of community pictures; long press one to remove it",
        "Recently visited shows the first three, with Show all for the rest",
        "Explore's top bar follows Settings › Appearance › Top bar, like Home, and hides as you scroll",
    ]),
    Release(version: "2.0.78", date: "Nov 12, 2026", highlights: [
        "Settings › Appearance › Explore sections: show, hide and reorder Explore's sections",
        "Recommended for you is a carousel of up to 10 communities, each with its picture and a Join button",
    ]),
    Release(version: "2.0.77", date: "Nov 12, 2026", highlights: [
        "Spoiler and NSFW galleries cover each image, so you can still swipe through them; one tap reveals them all",
        "Spoiler covers have the same rounded corners as the media under them",
        "Calm comment threads: the lines run unbroken, each depth in its own soft colour, with rounded ends",
    ]),
    Release(version: "2.0.76", date: "Nov 11, 2026", highlights: [
        "Drafts gets the new look: a top bar that hides as you scroll and rounded containers",
        "Selecting in History flips the picture over to a tick",
        "Softer placeholder pictures, and people's profile pictures in search",
        "The side bar shows your name and karma beside your picture, with an option to hide the u/",
        "The full top bar keeps the ☰ and your picture outside the search bar; calm posts show round community pictures",
    ]),
    Release(version: "2.0.75", date: "Nov 11, 2026", highlights: [
        "Explore: Recommended for you, communities you enjoy in For You but haven't joined, with a Join button",
        "History is split by day: Today, Yesterday, then the date",
    ]),
    Release(version: "2.0.74", date: "Nov 11, 2026", highlights: [
        "Settings › Media › Loop videos: turn it off and full-screen videos stop at the end, with a replay button (GIFs still loop)",
    ]),
    Release(version: "2.0.73", date: "Nov 11, 2026", highlights: [
        "History shows each community's picture; tap the name to open the community",
        "History: tap a picture to select posts, then remove them together",
        "Removing from History offers Undo",
        "Profile: its ⋯ menu puts short entries side by side, and its header lines up with Home's",
    ]),
    Release(version: "2.0.72", date: "Nov 11, 2026", highlights: [
        "A subreddit or custom feed you open again after a few minutes loads its latest posts, no pull needed",
        "Inbox reloads when you open it and when new mail arrives, and new items show at the top",
    ]),
    Release(version: "2.0.71", date: "Nov 11, 2026", highlights: [
        "Read posts stay read: Hide read posts remembers far more of them, covers For You too, and a page of only read posts loads the next",
        "Saved and History: the top bar hides as you scroll, with a 🔍 to bring the search back; Saved's chips have room and float under the bar",
        "History looks like Gmail: one connected list with each community's letter and when you read it; swipe a row left to remove it",
        "Search: Recent in connected cards; a community or user you open from the results takes its search's place, with its picture; long-press one to remove it",
        "Profile: tap your name (▾) to switch accounts, now with their pictures; History, Read later, Drafts and more are in the ⋯ menu",
        "Full top bar without New post: one round bar, Search Reddit in the middle, a smaller picture",
        "With the side bar on, Inbox and Explore leave out the Settings button too",
        "The search tab you pick before searching shows as picked",
    ]),
    Release(version: "2.0.70", date: "Nov 10, 2026", highlights: [
        "The side bar slides fully closed before the next page opens",
        "Swiping a post to vote springs back smoothly, even after a quick flick",
        "Votes: no circle or pop on the arrows, just their colour; the glow fades in softly in Calm and shows on the thread's post too",
        "Settings › Posts & comments › Mark what you voted on: Glow, the old edge line, or Off",
        "With the side bar on, Profile leaves out the Settings button and the shortcuts the side bar already has",
    ]),
    Release(version: "2.0.69", date: "Nov 9, 2026", highlights: [
        "Settings › Appearance opens normally again (it jumped straight into Theme & colours, and Back couldn't leave)",
        "The side bar closes again after you pick a page or a tab",
    ]),
    Release(version: "2.0.68", date: "Nov 9, 2026", highlights: [
        "A short setup on a fresh install: restore a backup, pick your look, navigation and front page, then sign in. Every step can be skipped",
    ]),
    Release(version: "2.0.67", date: "Nov 9, 2026", highlights: [
        "Comments show their authors' profile pictures (with the website sign-in), in place of the letter dot. Settings → Posts & comments can turn it off",
    ]),
    Release(version: "2.0.66", date: "Nov 9, 2026", highlights: [
        "Comments you voted on glow softly in the vote's colour instead of a line down the side",
        "Threads: put the floating buttons left, middle or right; jump between OP's or your own comments (long-press goes back); hide the next-comment button; link posts show their picture at the top",
        "Unread inbox items stand out with a coloured card, and flairs sit on a light tint so they're easier to read",
        "Explore: a softer fade under the status bar, a search bar that lines up with Search, and long-press a Recently visited subreddit to remove it",
        "The side bar's pages open without a slide and their icons fill in; the floating buttons move down with the bottom bar as it hides",
    ]),
    Release(version: "2.0.65", date: "Nov 5, 2026", highlights: [
        "Reposts made with a Reddit share link now show the original post's photo or video instead of a reddit.com link",
    ]),
    Release(version: "2.0.64", date: "Nov 5, 2026", highlights: [
        "Crossposts that showed up as a bare reddit.com link now show the original post's photo or video",
        "A link to a Reddit post opens it in the app, and crossposts from someone's profile say \"from u/name\"",
    ]),
    Release(version: "2.0.63", date: "Nov 5, 2026", highlights: [
        "Subreddits and custom feeds: a tidier top bar (more actions under ⋯) that hides as you scroll down and comes back when you scroll up, like Home's",
    ]),
    Release(version: "2.0.62", date: "Nov 5, 2026", highlights: [
        "Pages you open from the side bar act like side-bar tabs: ☰ instead of the back arrow, and the side bar shows where you are",
        "Choose and order the side bar's entries, and the buttons in the top bar's menu (Settings → Appearance)",
        "Dim read posts can be turned off while keeping your history",
        "Browse media: closing it no longer makes the feed jump",
    ]),
    Release(version: "2.0.61", date: "Nov 5, 2026", highlights: [
        "Search shows community and user icons, and letter avatars get their own colour",
        "Mini cards: tap the thumbnail to open the photo or video full screen",
        "Clear Recently visited from Explore, or hide it (Settings → Data & storage). Thanks, Nath5!",
        "New option: the Posts tab can show r/all (Settings → Feed)",
    ]),
    Release(version: "2.0.60", date: "Nov 5, 2026", highlights: [
        "Browse media: swipe up through a feed's photos, galleries and videos full screen, with votes, comments and saving at hand. Find it in a subreddit's top bar or the Home menu",
    ]),
    Release(version: "2.0.59", date: "Nov 5, 2026", highlights: [
        "r/ and u/ mentions in comments and posts are links, and \"Crossposted from\" opens the original post",
        "Hide NSFW posts now also hides them in search, profiles, Saved and History",
        "Recently visited counts your visits, and can list the most visited first (Settings → Data & storage)",
        "The floating button can hide the posts you've read, and floating chips can be transparent or solid",
        "Comments: a small pin instead of the PINNED badge, and long flairs no longer hide the username",
        "Calm vote buttons fill with the vote colour and change shape when tapped",
    ]),
    Release(version: "2.0.58", date: "Nov 3, 2026", highlights: [
        "Choose the floating button on Home and in subreddits: New post, Search, Scroll to top, Refresh or none. Threads have their own choice (Settings → Appearance)",
        "Filter chips float back under the top bar in subreddits and custom feeds too, on a solid background",
        "Edit the text of your image and gallery posts, not only text posts",
    ]),
    Release(version: "2.0.57", date: "Nov 3, 2026", highlights: [
        "For You and Blend: Blend shows more of your Reddit Home, fewer repeats on top, stories you've read step aside, and communities you enjoy but haven't joined show up",
        "Swiping a post or comment only starts on a clearly sideways swipe, so diagonal scrolls stay scrolls",
        "A new flair picker you can search, and Edit flair on your own posts",
        "Replies wait for an attachment to finish preparing, ask before discarding, and show a counter near the length limit",
        "Floating filter chips line up and no longer jump with the Full top bar; the search box is fully round",
    ]),
    Release(version: "2.0.56", date: "Nov 2, 2026", highlights: [
        "Full top bar: a wider search bar, and your profile picture opens the menu. New post beside it is optional (Settings → Appearance)",
        "Floating filter chips have an outline and settle into place smoothly, and you can turn them off (Settings → Feed)",
        "On Home the feed now runs softly under the status bar, and a small scroll up always brings the top bar back",
        "The search bar lines up better when you open search",
    ]),
    Release(version: "2.0.55", date: "Nov 2, 2026", highlights: [
        "Status bar icons follow the app's theme, so they stay visible when it differs from your phone's",
        "Comments: a big New comment button that folds as you scroll, and larger buttons above it",
        "Home: the filter chips float under the top bar when you scroll back up",
        "Search opens with a fade instead of sliding in, and search bars are fully rounded",
        "Saved and flair chips match the feed's, and content fades out below the status bar",
    ]),
    Release(version: "2.0.54", date: "Nov 2, 2026", highlights: [
        "With the side bar on, Back takes you to the top of the page, then to Posts, then opens the side bar",
        "Re-tapping the Profile tab scrolls it back to the top",
    ]),
    Release(version: "2.0.53", date: "Nov 2, 2026", highlights: [
        "Settings redesigned: categories with their own pages, rounded containers, and switches with a tick and a cross. Search still finds everything",
        "The floating buttons fold and open smoothly, and the Inbox's New message button folds too",
        "Your profile picture shows in the expanded header and the top bar",
        "Side bar: tap your profile at the top to open the Profile tab, in place of its own row",
    ]),
    Release(version: "2.0.52", date: "Nov 2, 2026", highlights: [
        "Recently visited now means the subreddits you actually opened, subscribed or not, in the side bar and in Explore. The list starts fresh with this update",
    ]),
    Release(version: "2.0.51", date: "Nov 2, 2026", highlights: [
        "The side bar shows your avatar and karma, your recently visited subreddits and your favorites",
        "A floating button on Home that folds as you scroll: New post or Search (Settings → Floating button on Home)",
        "The New post button in subreddits folds as you scroll, too",
        "The launcher label is now just \"Ilay\"",
    ]),
    Release(version: "2.0.50", date: "Nov 2, 2026", highlights: [
        "\"More replies\" works again, after a change on Reddit's side stopped it loading anything",
        "Each subreddit can have its own default sort (its About & rules sheet → Default sort)",
        "Search keeps its sort chips on screen while results load",
        "The tick in the sort chips sits properly toward the chip's edge",
    ]),
    Release(version: "2.0.49", date: "Nov 1, 2026", highlights: [
        "The top bar slides away and back with your finger, over the feed, and hides on your first scroll",
        "Comment style: pick Cards or Calm for comments, apart from your post style (Settings → Posts & comments)",
        "Post flairs show their own images, instead of a generic icon",
    ]),
    Release(version: "2.0.48", date: "Nov 1, 2026", highlights: [
        "Feeds: sort with one tap on a row of chips (Best, Hot, New, Top, Rising), and on Home switch to For You, Blend or Home the same way",
    ]),
    Release(version: "2.0.47", date: "Nov 1, 2026", highlights: [
        "Swiping a post or comment now brings in the action as its own card beside it, Gmail style",
    ]),
    Release(version: "2.0.46", date: "Nov 1, 2026", highlights: [
        "Expandable top bar: the title, search and ⋯ come back as soon as you scroll up",
        "Swipe actions fill with the action's color past the trigger point, and the icon pops, Gmail style",
        "Votes and saves pop when you tap them",
        "A Downvoted tab on your own profile",
        "Full-screen videos have a mute button, and Settings → Media can open them muted",
    ]),
    Release(version: "2.0.45", date: "Oct 30, 2026", highlights: [
        "Explore: the people you follow have their own Following section, and open their profile",
    ]),
    Release(version: "2.0.44", date: "Oct 30, 2026", highlights: [
        "Profiles: sort posts and comments by New, Hot or Top, and the profile header slides away as you scroll",
        "Custom feed share links (reddit.com/u/…/s/…) open the feed, not the user",
        "Swiping a comment in the Calm style slides it over the vote icon like a card, instead of tinting it",
        "The side bar no longer shows the page behind it while it opens",
    ]),
    Release(version: "2.0.43", date: "Oct 29, 2026", highlights: [
        "Translate posts, comments and AI summaries: on the post, in a comment's ⋯ menu, into your phone's language or a second one (Settings → Translation). On the phone where it can, else with your OpenAI key or Azure Translator",
        "Reddit Home and Blend load again with the website sign-in, with their galleries, videos and GIFs, and Home no longer falls back to For You after a while away",
        "Quarantined and restricted communities: \"View anyway\" right in Ilay",
        "Comments: collapse only the replies, and an edge marks the ones you voted on (Settings → Posts & comments)",
        "Preview a reply before sending it",
        "Clear cache now empties images and videos too and shows how much it frees; choose the image and video cache sizes",
        "With the website sign-in, feeds, comments, votes and saves switch to Reddit's app API if the website refuses them",
    ]),
    Release(version: "2.0.41", date: "Oct 28, 2026", highlights: [
        "Search works again with the website sign-in (Reddit had started refusing it)",
        "Share a Reddit post to \"Summarize with Ilay\": its AI summary opens over the app you're in",
        "\"Open in Ilay\" in the share menu opens a shared post in Ilay",
        "Search no longer crashes when Reddit refuses a request, and a failing tab doesn't hide the others' results",
    ]),
    Release(version: "2.0.40", date: "Oct 26, 2026", highlights: [
        "Galleries in your feeds use the carousel too (turn it off in Settings → Media → Gallery carousel in feeds)",
    ]),
    Release(version: "2.0.39", date: "Oct 26, 2026", highlights: [
        "Material 3 Expressive menus: grouped, with the current choice highlighted (Display, sort, comment ⋯)",
        "Join, Follow, Save and favourite stars are real toggles that change shape when on",
        "For You mix slider fills from the middle, so you see which way it leans",
        "Buttons' corners tighten as you press them (dialogs, Retry, back, ☰, ⚙)",
        "One pick-one style everywhere: post type, sign-in method, feed privacy",
        "Better with screen readers: tabs, votes, layouts, toggles and the video seek bar announce their state",
        "Galleries: a fling skips several images, and each image is labelled",
    ]),
    Release(version: "2.0.38", date: "Oct 26, 2026", highlights: [
        "Connected button groups: the Inbox filters, Search sort and Explore's Popular / All",
        "Polls show as one segmented list",
        "The side bar's ☰ sits in exactly the same spot on every tab",
    ]),
    Release(version: "2.0.37", date: "Oct 25, 2026", highlights: [
        "Material 3 Expressive loading: morphing-shape indicators everywhere Ilay is loading, including pull to refresh",
        "Saving media shows a wavy progress bar",
    ]),
    Release(version: "2.0.36", date: "Oct 25, 2026", highlights: [
        "User flairs show their emoji (club badges and the like), not just their text",
        "Calm layout: images and links have evenly rounded corners",
    ]),
    Release(version: "2.0.35", date: "Oct 25, 2026", highlights: [
        "Gallery posts open as a Material 3 carousel: one big image with the next ones peeking beside it",
        "Bottom bar outline can be turned off (Settings → Appearance)",
    ]),
    Release(version: "2.0.34", date: "Oct 25, 2026", highlights: [
        "User flairs next to names in posts and comments, and set your own flair from a community's About",
        "Custom feeds: one screen with all of them, rename, describe, make public or private, share, copy someone's public feed, and tap a community to open it",
        "A ⚙ button opens Settings directly; the Expandable top bar gets a search button",
        "Neater ☰ alignment and a cleaner New post icon",
    ]),
    Release(version: "2.0.33", date: "Oct 22, 2026", highlights: [
        "And the other way: replies you opened in Reddit's notifications show as read in Ilay's Inbox (website sign-in)",
    ]),
    Release(version: "2.0.32", date: "Oct 22, 2026", highlights: [
        "With the website sign-in, replies you read in the Inbox are marked read in Reddit's notifications too (and Mark all read clears them there)",
    ]),
    Release(version: "2.0.31", date: "Oct 22, 2026", highlights: [
        "With the side bar on, swiping back on the main screen opens it, and back again closes it",
    ]),
    Release(version: "2.0.30", date: "Oct 22, 2026", highlights: [
        "What's new: this list, once after each update, and any time in Settings → About",
        "Side bar navigation: Settings → Appearance → Navigation (bottom bar, side bar, or both)",
    ]),
    Release(version: "2.0.29", date: "Oct 21, 2026", highlights: [
        "AI summaries work with other providers (Groq, OpenRouter…) and any model ID",
        "Add a community to a custom feed from a post's ⋮ menu or the community's top bar",
        "Autoplay with sound, for feed videos (Settings → Media)",
    ]),
    Release(version: "2.0.26 – 2.0.28", date: "Oct 18, 2026", highlights: [
        "Remind me about a saved post: pick when, get a notification, and see the reminder on the post",
    ]),
    Release(version: "2.0.24 – 2.0.25", date: "Oct 17, 2026", highlights: [
        "Reddit's own notifications in the Inbox (website sign-in), with unread dots and older ones",
        "When Reddit rate-limits you, Ilay says how long to wait",
        "Select and delete several summaries at once",
    ]),
    Release(version: "2.0.22 – 2.0.23", date: "Oct 17, 2026", highlights: [
        "Profile tab: your posts, comments, saved and upvoted, with your stuff a tap away",
        "Settings moved to the ⋮ menu at the top of each tab",
        "Reddit Chat, voting in polls and Reddit's account settings (website sign-in)",
        "Poll results and your vote show in the post",
    ]),
    Release(version: "2.0.20 – 2.0.21", date: "Oct 17, 2026", highlights: [
        "Your votes stick when you go back into a thread or your profile",
        "Blend: choose Mostly Ilay, Balanced or Mostly Reddit",
        "Already seen elsewhere: drop a post you read in another app",
    ]),
    Release(version: "2.0.19", date: "Oct 17, 2026", highlights: [
        "Android 13 support",
        "Follow users",
        "Hide or dim read posts in more places",
    ]),
    Release(version: "2.0.15 – 2.0.18", date: "Oct 16, 2026", highlights: [
        "For You is out of beta and learns from more of what you do",
        "Familiar ↔ Discover: how adventurous For You should be",
        "Blend (Beta): your Reddit Home ranked by For You",
    ]),
    Release(version: "2.0.11 – 2.0.14", date: "Oct 16, 2026", highlights: [
        "Notification activity, Drafts and Ask AI about a thread",
        "Volume keys jump between comments; saved searches; collapse settings",
        "Smoother scrolling past GIFs in threads",
    ]),
    Release(version: "2.0.1 – 2.0.7", date: "Oct 14, 2026", highlights: [
        "Smoother scrolling in image-heavy feeds",
        "GIFs and stickers from your keyboard in replies and messages",
        "Hide a community from your front page, or filter it out everywhere",
        "Back never leaves the app from the main screen",
    ]),
    Release(version: "2.0.0", date: "Oct 12, 2026", highlights: [
        "Ilay rebuilt as a native Android app: faster, smoother, same data",
        "Reddit Home (experimental): your real reddit.com Home feed",
    ]),
]
