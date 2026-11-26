package com.bennybar.luli_for_reddit.feature.about

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bennybar.luli_for_reddit.BuildConfig
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.feature.feed.BloomTopBar
import com.bennybar.luli_for_reddit.feature.markdown.RedditMarkdown
import com.bennybar.luli_for_reddit.nav.Route
import com.bennybar.luli_for_reddit.ui.Overlays

/** One release's highlights, as shown in What's new. */
class Release(val version: String, val date: String, val highlights: List<String>)

/**
 * What's new, newest first: the notable changes of each release since Ilay
 * 2.0 (the native app, with Reddit Home). Add the new release at the top
 * with every release.
 */
val CHANGELOG = listOf(
    Release(
        "2.0.121", "Nov 26, 2026",
        listOf(
            "User pages and your Profile tab get the community page's header: the banner under the status bar with round buttons on it, the picture over its edge, the name once, karma and account age, a round Follow and the description; without a banner, a large centred picture and name (#293)",
            "Another user's page has a 🔍 that searches their posts",
        ),
    ),
    Release(
        "2.0.120", "Nov 26, 2026",
        listOf(
            "Image posts upload their image again: Reddit had started rejecting how Ilay asked for the upload, so posts went up as text only (#296)",
            "Community banners: the status bar icons follow the banner under them and come back right when you leave (#291); a short, low-resolution banner shows sharp over its soft backdrop (#294)",
            "Settings › Feed › \"New posts\" button: turn off the pop-up that offers newer posts (#292)",
            "Search suggestions sit in a rounded group like the rest of the search page (#290)",
            "Explore, Profile and Inbox open search with the same growing animation as Posts (#295)",
        ),
    ),
    Release(
        "2.0.119", "Nov 26, 2026",
        listOf(
            "Appearance: a Preview button on each group (Layout, Colour, Text, Comments) opens the real post with that group's options under it, instead of a preview pinned over the page (#288)",
            "\"r/ and u/ before names\": the setting now also hides the u/ before user names (#289)",
            "Search: a full-width field with ← inside it, growing out of the search button with the words travelling along; page searches (Saved, History, Settings, Summaries) grow from their own 🔍 as a thicker pill, and with the Full top bar they and communities get the round search bar (#285)",
            "Community and profile pictures grow out of their circle into the viewer and back; the viewers close with a back arrow instead of × (#287)",
            "A community's description grows and shrinks smoothly on Show all / Show less (#286)",
            "Spoilers in the Home feed show the photo when tapped, not a blur, and stay revealed on the post page",
        ),
    ),
    Release(
        "2.0.118", "Nov 26, 2026",
        listOf(
            "Appearance: a live preview of a real post at the top, at true size, that changes as you change any option; it switches to a sample comment thread for comment sizes and steps aside for options it can't show",
            "Appearance: options change right on the page (layout chips, segmented choices, colour swatches, sliders), grouped as Layout, Colour, Text and Other, so nothing closes while you try them",
        ),
    ),
    Release(
        "2.0.117", "Nov 26, 2026",
        listOf(
            "Appearance: Corner roundness (Round, Medium, Small, Square) for posts' cards and media (#283)",
            "Two new post layouts: Compact (flat rows, a meta line on top, a slim action row) and Compact cards (the poster's picture, votes on the right) (#284)",
            "The poster's picture shows with the website sign-in too, where Reddit sends it with the post",
        ),
    ),
    Release(
        "2.0.116", "Nov 26, 2026",
        listOf(
            "Home feed: posts arrive complete on the first paint (flair, icons, size), and faster",
            "Feeds: cards fly in once, stay put when updated, and a fresh page doesn't yank you to the top",
            "Search: the search box grows into the search page (#271); with the Expandable top bar, Saved, History, Settings and Summaries search from a 🔍 in the bar (#247)",
            "Subreddit page: the icon sits lower, Join is a + by the name with a \"Joined\" note, no empty description card, and the description keeps its size (#277, #278); search and ⋯ share one pill (#282)",
            "Tap a community's or user's picture to see it full screen (#279)",
            "Side bar: long-press a recently visited community to remove it (#280)",
            "Search history: no more bare author: entries; a search in someone's posts shows their u/name tag (#281)",
            "Subreddit banners: the phone banner when there is one, and no more blurry zoom",
        ),
    ),
    Release(
        "2.0.115", "Nov 25, 2026",
        listOf(
            "Home feed: posts appear at their final size, the photo stays put instead of loading twice, and galleries fill in without resizing",
            "Home feed: the flair fades in when it arrives",
        ),
    ),
    Release(
        "2.0.114", "Nov 25, 2026",
        listOf(
            "Subreddit header: a bigger icon and name, the banner folds with the name, blurred button circles, and status bar icons that follow the banner's lightness (#268)",
            "Settings: the big header when opened from the side bar, and the list split into two groups (#268, #276)",
            "Videos: autoplay Off / On Wi-Fi only / Always, and pinch to zoom in the full-screen viewer",
            "Posts: the poster's picture on post cards, in Appearance (off by default) (#270)",
            "Comments: collapsing and expanding animate (#273); a setting to not reopen threads where you left off (#269)",
            "User pages: the actions in a ⋯ menu (#275); searching a profile shows a \"From u/…\" tag (#271)",
            "Fixes: popups spring back when not swiped away (#269), the ☰ looks like Material's (#258), AI shows busy errors instead of spinning (#267), Notification activity shows your check interval",
        ),
    ),
    Release(
        "2.0.113", "Nov 25, 2026",
        listOf(
            "GIFs: GIF posts Reddit labels as images now play, as Reddit's small mp4 copy (#265)",
            "Updates: the update notice shows what's new in the release it offers (#266)",
        ),
    ),
    Release(
        "2.0.112", "Nov 25, 2026",
        listOf(
            "Subreddit header: a community without a banner or a colour of its own gets a soft band of your accent colour instead of grey (#257)",
        ),
    ),
    Release(
        "2.0.111", "Nov 25, 2026",
        listOf(
            "Videos: a playback speed button (0.5× to 4×) next to Mute, in the viewer and Browse media (#260)",
            "Expandable top bar: the big title on Profile, Saved, History, Read later, Drafts, Custom feeds and Digest too, folding into the bar as you scroll (#247)",
            "Subreddits, with Header height on Medium or Tall: the community's banner (or its colour) as the header, the icon and name sliding into the bar as you scroll, and the description in a card with Show all (#257)",
        ),
    ),
    Release(
        "2.0.110", "Nov 25, 2026",
        listOf(
            "Videos from search and the Home feed can be downloaded again, with their sound (#261)",
            "Viewing a single thread: the capsule floats over the post without leaving a gap, stays while you scroll, and swipes away sideways, as does \"Back where you left off\" (#264)",
            "Top bars: the buttons sit at the same height on every tab and side bar page (#263)",
            "Side bar: the ☰ turns a little more as it fans (#258)",
        ),
    ),
    Release(
        "2.0.109", "Nov 24, 2026",
        listOf(
            "Search: pick a time range (Hour to All time) with any sort, not only Top (#255)",
            "AI: Gemini's OpenAI-compatible URL works as the custom base URL (#254)",
            "Galleries: no more \"X images · tap one to view\" line under them (#256)",
            "Side bar: the ☰ now fans out as the side bar opens, instead of spinning (#258)",
        ),
    ),
    Release(
        "2.0.108", "Nov 24, 2026",
        listOf(
            "Settings regrouped: new Read & hidden and Navigation pages, \"AI summaries\" is now AI, and Account holds your account, keys and API usage. Nothing was changed or removed, and search finds every setting",
            "Viewing a single thread: a floating capsule with Show all, like the scroll-to-top one, that slides away as you scroll (#253)",
            "Side bar: the ☰ turns as the side bar opens and closes (#252)",
        ),
    ),
    Release(
        "2.0.107", "Nov 24, 2026",
        listOf(
            "Expandable top bar: the filter chips no longer vanish for a moment while you pull the header open (#251)",
        ),
    ),
    Release(
        "2.0.106", "Nov 23, 2026",
        listOf(
            "Inbox: one row of chips (All, Unread, Replies, Mentions, Messages, Sent) in place of the tabs and the second row of filters. The bar and chips slide away as you scroll, and you can still swipe between them (#246)",
            "Expandable top bar: a fling back to the top opens the header too (#249), and the chips no longer blink while it folds (#248)",
            "Inbox and Profile: no more shading over the search bar (#248)",
        ),
    ),
    Release(
        "2.0.105", "Nov 23, 2026",
        listOf(
            "Post text in feeds shows its bold, italic, strikethrough and spoilers instead of the markdown marks (#241)",
            "Expandable top bar: scrolling back to the top opens the header as your finger moves, not all at once (#242), and the big title lines up with the chips (#243)",
            "Comment buttons only on tap: the buttons and the score slide and fade in and out; Explore's Show all opens smoothly; no more pop on Save and the Favorites star (#244)",
            "App font: \"Roboto\" is now called \"Default\", as it's your phone's own font (#245)",
        ),
    ),
    Release(
        "2.0.104", "Nov 23, 2026",
        listOf(
            "Settings › Appearance › Header height, for the Expandable top bar: Folded (always the small bar), Medium (as now) or Tall (as in 2.0.96) (#240)",
        ),
    ),
    Release(
        "2.0.103", "Nov 23, 2026",
        listOf(
            "Settings › Comment buttons only on tap: comments show just their text, with the score by the time; tap a comment for Vote, Reply and the rest (#239)",
            "New posts: the title and text start sentences with a capital letter",
            "The big title sits a little higher in the expanded header (#232)",
        ),
    ),
    Release(
        "2.0.102", "Nov 23, 2026",
        listOf(
            "Digest: a post you open and come back from leaves the list too, not only one you swipe (Show read keeps them)",
            "Digest: Standard is now about 20 posts (was 12). Rebuild today's digest from its menu to see it now",
        ),
    ),
    Release(
        "2.0.101", "Nov 23, 2026",
        listOf(
            "Digest: marking a post read takes it off the list at once, as hiding a post does in your feed; Undo puts it back",
            "Haven't tried Digest yet? A card at the top of Posts offers it, once",
        ),
    ),
    Release(
        "2.0.100", "Nov 23, 2026",
        listOf(
            "Text sizes for post titles, post text and comments, each on its own (Settings › Appearance, under Font size). They start at today's size, and \"Reset text sizes\" puts them all back",
        ),
    ),
    Release(
        "2.0.99", "Nov 23, 2026",
        listOf(
            "New: Digest. The posts that stood out in the last 24 hours in your favourite communities, in one short list. Turn it on in Settings › Digest, where \"How Digest works\" explains it",
            "It picks by how unusual a post is for its own community, so a small community's big day isn't drowned out, and a quiet day gives a short digest. No AI needed",
            "Your choice of communities (your favourites, or up to 15), how long it is, and where it shows: a chip at the top of Posts, its own tab, or only in the side bar and Profile menu",
            "Optional: with your own AI key, \"Use AI\" picks the posts, says why each matters, and can open with a short overview. It's off unless you turn it on, and a refresh only sends the new posts",
            "Order it your way: most notable, most upvoted, newest, or the AI's assessment",
            "Swipe a post to mark it read (left, right or both: your choice). Pull down for what's new: a refresh only adds posts, nothing already there goes away",
            "A daily notification at the time you pick, with your digest ready",
            "Settings › Appearance › Inbox in Profile: Inbox opens from an envelope at the top of Profile, for a three-tab bottom bar",
            "Our own subreddit: r/IlayFR, for news, help and ideas (Settings › About)",
            "Top bar: a hidden header stays hidden when you come back from a post; the folded big title sits as snug as other bars; Profile's buttons line up with the other tabs'; pushing a pull to refresh back up no longer folds the header first",
        ),
    ),
    Release(
        "2.0.98", "Nov 23, 2026",
        listOf(
            "Expandable top bar: the big title sits a little higher, and it stays folded when you come back from a post",
            "Settings › Feed: one \"Posts tab feed\" choice (For You, Blend, Reddit Home, Subscriptions) instead of the \"Home shows…\" switches",
        ),
    ),
    Release(
        "2.0.97", "Nov 22, 2026",
        listOf(
            "Home and Blend scroll more smoothly as you go deeper: Ilay reads only the new posts from your Reddit Home",
            "For You loads its later pages faster, and a slow source no longer holds up the first one",
            "On a slow connection, For You keeps what arrives late for the next page instead of dropping it",
            "With Hide read posts on, For You pages come back full",
        ),
    ),
    Release(
        "2.0.96", "Nov 22, 2026",
        listOf(
            "Expandable top bar: the big title sits at the foot of a taller header, and once folded the bar slides away as you scroll, as before",
            "A softer fade behind the status bar when the top bar is away",
            "Back leaves the app (when on) with Android's own back-to-home animation",
            "Search button on Profile, spoiler galleries in a post covered image by image, and outlined icons in Settings",
        ),
    ),
    Release(
        "2.0.95", "Nov 22, 2026",
        listOf(
            "Comments deep in a thread keep their ⋯ menu (Edit, Delete…): on narrow rows Reply and Collapse show just their icons",
            "Polls: \"Vote on reddit.com\" opens the post on Reddit's site, where you can vote",
        ),
    ),
    Release(
        "2.0.94", "Nov 22, 2026",
        listOf(
            "Expandable top bar: a big title at the top of Posts, Explore and Inbox that shrinks into the bar as you scroll",
            "Full top bar on Inbox and Profile too, with a search for your own posts on Profile",
            "New app font: Google Sans Flex, with rounded titles (Settings › Appearance › App font)",
        ),
    ),
    Release(
        "2.0.93", "Nov 22, 2026",
        listOf(
            "Long threads reopen where you left off after using the jump buttons too, and \"Back where you left off\" sits at the top instead of over the buttons",
            "More commenters' pictures show in long threads, and your own on your comments",
            "A reply with an image no longer says it failed when Reddit posted it",
            "Collapse AutoModerator and pinned comments: every pinned comment now starts collapsed",
            "New comment in the thread's ⋯ menu, your picture on the Profile tab, and Report for comments and users",
        ),
    ),
    Release(
        "2.0.92", "Nov 17, 2026",
        listOf(
            "The screen stays on while a video plays full screen",
            "Saved images and videos are named after the post's title",
            "Tap a user flair that's cut short to read all of it",
            "New setting: Hide thread buttons while scrolling (Posts & comments). They step aside while your finger scrolls a thread",
        ),
    ),
    Release(
        "2.0.91", "Nov 16, 2026",
        listOf(
            "New setting: Back leaves the app (Appearance). Off by default: when on, back on Posts leaves once there's nothing else for it to do",
            "Shorter For You tags: \"From r/x\" for communities you engage with, \"Subscribed · r/x\" for yours, and a fire icon for Trending",
            "When the next page fails to load, the feed says so with a Retry button instead of just stopping. Profile, Saved and Search lists show where they end",
            "Swiping to delete a message asks first",
        ),
    ),
    Release(
        "2.0.90", "Nov 16, 2026",
        listOf(
            "Spoiler posts keep their text covered, in feeds and in the thread, until you tap it",
            "Threads in contest mode say so above the comments: random order, scores hidden",
        ),
    ),
    Release(
        "2.0.89", "Nov 16, 2026",
        listOf(
            "Collapse AutoModerator and bots is only in Settings › Posts & comments now: it was also in Content filters, the same switch twice",
        ),
    ),
    Release(
        "2.0.88", "Nov 16, 2026",
        listOf(
            "Translation: DeepL with your own API key, as a service for languages your phone can't translate (Settings › Translation service)",
        ),
    ),
    Release(
        "2.0.87", "Nov 16, 2026",
        listOf(
            "Settings › Feed › Post text in feeds: show 5 or 10 lines of a post's text in feeds",
            "Your own comments have Edit and Delete at the top of their ⋯ menu",
            "Removing an entry from History slides it all the way out before it goes",
        ),
    ),
    Release(
        "2.0.86", "Nov 16, 2026",
        listOf(
            "Notifications: choose how often Reddit is checked, from every 15 minutes to every 6 hours",
            "A comment's ⋯ menu has Select text, to copy just part of it",
            "Names in comments have their own softer colour, so they stand apart from the text",
        ),
    ),
    Release(
        "2.0.85", "Nov 16, 2026",
        listOf(
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
        ),
    ),
    Release(
        "2.0.84", "Nov 15, 2026",
        listOf(
            "Explore: Popular and All are separate sections, so you can move or hide each one (side by side, they stay a pair)",
            "Filtering your communities shows Favorites, Recently visited and Subscriptions under their own headers",
            "The filter bar is one connected piece: its filter icon opens the sort, and the Favorites star is attached to it",
        ),
    ),
    Release(
        "2.0.83", "Nov 15, 2026",
        listOf(
            "Threads reopen where you left off, with a button to jump back to the top",
            "Notifications: a clearer app icon, short titles like \"u/name replied\" with the post's title above, and Mark as read and Reply buttons",
            "Menus have a fresh look: options in rounded groups with icons, and what's picked as a tinted pill",
            "Profile's sort: Top's time ranges show in the same menu",
        ),
    ),
    Release(
        "2.0.82", "Nov 15, 2026",
        listOf(
            "Posts you voted on glow in the vote's colour, as comments do (Settings › Mark what you voted on › Glow)",
            "Floating buttons fold only once you really scroll, open with a little bounce, and have less rounded corners",
            "Explore: each community in a list is its own segment, and the community rows move like the gallery carousel",
            "Explore's Full top bar is the same as Home's; with the side bar on, your picture is smaller and the search bar centred",
        ),
    ),
    Release(
        "2.0.81", "Nov 15, 2026",
        listOf(
            "Calm comments: swiping a comment to vote no longer hides its thread lines; they slide with it",
            "History and Summaries: the selection bar's × and count line up with the title",
            "For You's subtitle is now \"On your phone\", so it fits beside the title",
        ),
    ),
    Release(
        "2.0.80", "Nov 12, 2026",
        listOf(
            "Explore: Popular communities, a row of Reddit's popular communities you haven't joined, with Join",
            "It's loaded at most once a day, and you can hide or move it in Settings › Appearance › Explore sections",
        ),
    ),
    Release(
        "2.0.79", "Nov 12, 2026",
        listOf(
            "Explore redesign: each section sits in its own rounded card",
            "Recommended communities show their banner, with the picture over it",
            "Favorites is a row of community pictures; long press one to remove it",
            "Recently visited shows the first three, with Show all for the rest",
            "Explore's top bar follows Settings › Appearance › Top bar, like Home, and hides as you scroll",
        ),
    ),
    Release(
        "2.0.78", "Nov 12, 2026",
        listOf(
            "Settings › Appearance › Explore sections: show, hide and reorder Explore's sections",
            "Recommended for you is a carousel of up to 10 communities, each with its picture and a Join button",
        ),
    ),
    Release(
        "2.0.77", "Nov 12, 2026",
        listOf(
            "Spoiler and NSFW galleries cover each image, so you can still swipe through them; one tap reveals them all",
            "Spoiler covers have the same rounded corners as the media under them",
            "Calm comment threads: the lines run unbroken, each depth in its own soft colour, with rounded ends",
        ),
    ),
    Release(
        "2.0.76", "Nov 11, 2026",
        listOf(
            "Drafts gets the new look: a top bar that hides as you scroll and rounded containers",
            "Selecting in History flips the picture over to a tick",
            "Softer placeholder pictures, and people's profile pictures in search",
            "The side bar shows your name and karma beside your picture, with an option to hide the u/",
            "The full top bar keeps the ☰ and your picture outside the search bar; calm posts show round community pictures",
        ),
    ),
    Release(
        "2.0.75", "Nov 11, 2026",
        listOf(
            "Explore: Recommended for you, communities you enjoy in For You but haven't joined, with a Join button",
            "History is split by day: Today, Yesterday, then the date",
            "Swiping from the edge on Inbox and Profile drags the side bar out with your finger",
        ),
    ),
    Release(
        "2.0.74", "Nov 11, 2026",
        listOf(
            "Settings › Media › Loop videos: turn it off and full-screen videos stop at the end, with a replay button (GIFs still loop)",
        ),
    ),
    Release(
        "2.0.73", "Nov 11, 2026",
        listOf(
            "History shows each community's picture; tap the name to open the community",
            "History: tap a picture to select posts, then remove them together",
            "Removing from History offers Undo",
            "Profile: its ⋯ menu puts short entries side by side, and its header lines up with Home's",
        ),
    ),
    Release(
        "2.0.72", "Nov 11, 2026",
        listOf(
            "A subreddit or custom feed you open again after a few minutes loads its latest posts, no pull needed",
            "Inbox reloads when you open it and when new mail arrives, and new items show at the top",
        ),
    ),
    Release(
        "2.0.71", "Nov 11, 2026",
        listOf(
            "Read posts stay read: Hide read posts remembers far more of them, covers For You too, and a page of only read posts loads the next",
            "Saved and History: the top bar hides as you scroll, with a 🔍 to bring the search back; Saved's chips have room and float under the bar",
            "History looks like Gmail: one connected list with each community's letter and when you read it; swipe a row left to remove it",
            "Search: Recent in connected cards; a community or user you open from the results takes its search's place, with its picture; long-press one to remove it",
            "Profile: tap your name (▾) to switch accounts, now with their pictures; History, Read later, Drafts and more are in the ⋯ menu",
            "Full top bar without New post: one round bar, Search Reddit in the middle, a smaller picture",
            "With the side bar on, Inbox and Explore leave out the Settings button too",
            "The search tab you pick before searching shows as picked",
        ),
    ),
    Release(
        "2.0.70", "Nov 10, 2026",
        listOf(
            "The side bar slides fully closed before the next page opens",
            "Swiping a post to vote springs back smoothly, even after a quick flick",
            "Votes: no circle or pop on the arrows, just their colour; the glow fades in softly in Calm and shows on the thread's post too",
            "Settings › Posts & comments › Mark what you voted on: Glow, the old edge line, or Off",
            "With the side bar on, Profile leaves out the Settings button and the shortcuts the side bar already has",
        ),
    ),
    Release(
        "2.0.69", "Nov 9, 2026",
        listOf(
            "Settings › Appearance opens normally again (it jumped straight into Theme & colours, and Back couldn't leave)",
            "The side bar closes again after you pick a page or a tab",
        ),
    ),
    Release(
        "2.0.68", "Nov 9, 2026",
        listOf(
            "New Theme & colours page: preview presets, enter any hex colour, and pick a Material palette style (Expressive, Vibrant, Rainbow and more), with a live preview",
            "A short setup on a fresh install: restore a backup, pick your look, navigation and front page, then sign in. Every step can be skipped",
        ),
    ),
    Release(
        "2.0.67", "Nov 9, 2026",
        listOf(
            "Comments show their authors' profile pictures (with the website sign-in), in place of the letter dot. Settings → Posts & comments can turn it off",
        ),
    ),
    Release(
        "2.0.66", "Nov 9, 2026",
        listOf(
            "Comments you voted on glow softly in the vote's colour instead of a line down the side",
            "Threads: put the floating buttons left, middle or right; jump between OP's or your own comments (long-press goes back); hide the next-comment button; link posts show their picture at the top",
            "Unread inbox items stand out with a coloured card, and flairs sit on a light tint so they're easier to read",
            "Explore: a softer fade under the status bar, a search bar that lines up with Search, and long-press a Recently visited subreddit to remove it",
            "The side bar's pages open without a slide and their icons fill in; the floating buttons move down with the bottom bar as it hides",
            "Backups go to a folder you pick once; the History note can be closed; new search icon; no pop on Calm vote arrows",
        ),
    ),
    Release(
        "2.0.65", "Nov 5, 2026",
        listOf(
            "Reposts made with a Reddit share link now show the original post's photo or video instead of a reddit.com link",
        ),
    ),
    Release(
        "2.0.64", "Nov 5, 2026",
        listOf(
            "Crossposts that showed up as a bare reddit.com link now show the original post's photo or video",
            "A link to a Reddit post opens it in the app, and crossposts from someone's profile say \"from u/name\"",
        ),
    ),
    Release(
        "2.0.63", "Nov 5, 2026",
        listOf(
            "Subreddits and custom feeds: a tidier top bar (more actions under ⋯) that hides as you scroll down and comes back when you scroll up, like Home's",
            "Inbox: swiping from the edge (or right on All) opens the side bar, and swiping between sections works again",
        ),
    ),
    Release(
        "2.0.62", "Nov 5, 2026",
        listOf(
            "Pages you open from the side bar act like side-bar tabs: ☰ instead of the back arrow, and the side bar shows where you are",
            "Choose and order the side bar's entries, and the buttons in the top bar's menu (Settings → Appearance)",
            "Dim read posts can be turned off while keeping your history",
            "Browse media: closing it no longer makes the feed jump",
        ),
    ),
    Release(
        "2.0.61", "Nov 5, 2026",
        listOf(
            "Search shows community and user icons, and letter avatars get their own colour",
            "Mini cards: tap the thumbnail to open the photo or video full screen",
            "Clear Recently visited from Explore, or hide it (Settings → Data & storage). Thanks, Nath5!",
            "New option: the Posts tab can show r/all (Settings → Feed)",
        ),
    ),
    Release(
        "2.0.60", "Nov 5, 2026",
        listOf(
            "Browse media: swipe up through a feed's photos, galleries and videos full screen, with votes, comments and saving at hand. Find it in a subreddit's top bar or the Home menu",
        ),
    ),
    Release(
        "2.0.59", "Nov 5, 2026",
        listOf(
            "r/ and u/ mentions in comments and posts are links, and \"Crossposted from\" opens the original post",
            "Hide NSFW posts now also hides them in search, profiles, Saved and History",
            "Recently visited counts your visits, and can list the most visited first (Settings → Data & storage)",
            "The floating button can hide the posts you've read, and floating chips can be transparent or solid",
            "Show subreddit names without the r/ (Settings → Appearance)",
            "Comments: a small pin instead of the PINNED badge, and long flairs no longer hide the username",
            "Calm vote buttons fill with the vote colour and change shape when tapped",
        ),
    ),
    Release(
        "2.0.58", "Nov 3, 2026",
        listOf(
            "Choose the floating button on Home and in subreddits: New post, Search, Scroll to top, Refresh or none. Threads have their own choice (Settings → Appearance)",
            "Filter chips float back under the top bar in subreddits and custom feeds too, on a solid background",
            "Pick any accent colour with the new Custom colour option",
            "Edit the text of your image and gallery posts, not only text posts",
        ),
    ),
    Release(
        "2.0.57", "Nov 3, 2026",
        listOf(
            "For You and Blend: Blend shows more of your Reddit Home, fewer repeats on top, stories you've read step aside, and communities you enjoy but haven't joined show up",
            "Swiping a post or comment only starts on a clearly sideways swipe, so diagonal scrolls stay scrolls",
            "A new flair picker you can search, and Edit flair on your own posts",
            "Replies wait for an attachment to finish preparing, ask before discarding, and show a counter near the length limit",
            "Floating filter chips line up and no longer jump with the Full top bar; the search box is fully round",
        ),
    ),
    Release(
        "2.0.56", "Nov 2, 2026",
        listOf(
            "Full top bar: a wider search bar, and your profile picture opens the menu. New post beside it is optional (Settings → Appearance)",
            "Floating filter chips have an outline and settle into place smoothly, and you can turn them off (Settings → Feed)",
            "On Home the feed now runs softly under the status bar, and a small scroll up always brings the top bar back",
            "The search bar lines up better when you open search",
        ),
    ),
    Release(
        "2.0.55", "Nov 2, 2026",
        listOf(
            "Status bar icons follow the app's theme, so they stay visible when it differs from your phone's",
            "Comments: a big New comment button that folds as you scroll, and larger buttons above it",
            "Home: the filter chips float under the top bar when you scroll back up",
            "Search opens with a fade instead of sliding in, and search bars are fully rounded",
            "Saved and flair chips match the feed's, and content fades out below the status bar",
        ),
    ),
    Release(
        "2.0.54", "Nov 2, 2026",
        listOf(
            "With the side bar on, Back takes you to the top of the page, then to Posts, then opens the side bar",
            "Re-tapping the Profile tab scrolls it back to the top",
        ),
    ),
    Release(
        "2.0.53", "Nov 2, 2026",
        listOf(
            "Settings redesigned: categories with their own pages, rounded containers, and switches with a tick and a cross. Search still finds everything",
            "The floating buttons fold and open smoothly, and the Inbox's New message button folds too",
            "Your profile picture shows in the expanded header and the top bar",
            "Side bar: tap your profile at the top to open the Profile tab, in place of its own row",
        ),
    ),
    Release(
        "2.0.52", "Nov 2, 2026",
        listOf(
            "Recently visited now means the subreddits you actually opened, subscribed or not, in the side bar and in Explore. The list starts fresh with this update",
        ),
    ),
    Release(
        "2.0.51", "Nov 2, 2026",
        listOf(
            "The side bar shows your avatar and karma, your recently visited subreddits and your favorites",
            "A floating button on Home that folds as you scroll: New post or Search (Settings → Floating button on Home)",
            "The New post button in subreddits folds as you scroll, too",
            "The launcher label is now just \"Ilay\"",
        ),
    ),
    Release(
        "2.0.50", "Nov 2, 2026",
        listOf(
            "\"More replies\" works again, after a change on Reddit's side stopped it loading anything",
            "Each subreddit can have its own default sort (its About & rules sheet → Default sort)",
            "Search keeps its sort chips on screen while results load",
            "The tick in the sort chips sits properly toward the chip's edge",
        ),
    ),
    Release(
        "2.0.49", "Nov 1, 2026",
        listOf(
            "The top bar slides away and back with your finger, over the feed, and hides on your first scroll",
            "Comment style: pick Cards or Calm for comments, apart from your post style (Settings → Posts & comments)",
            "Post flairs show their own images, instead of a generic icon",
        ),
    ),
    Release(
        "2.0.48", "Nov 1, 2026",
        listOf(
            "Feeds: sort with one tap on a row of chips (Best, Hot, New, Top, Rising), and on Home switch to For You, Blend or Home the same way",
        ),
    ),
    Release(
        "2.0.47", "Nov 1, 2026",
        listOf(
            "Swiping a post or comment now brings in the action as its own card beside it, Gmail style",
        ),
    ),
    Release(
        "2.0.46", "Nov 1, 2026",
        listOf(
            "Expandable top bar: the title, search and ⋯ come back as soon as you scroll up",
            "Swipe actions fill with the action's color past the trigger point, and the icon pops, Gmail style",
            "Votes and saves pop when you tap them",
            "A Downvoted tab on your own profile",
            "Full-screen videos have a mute button, and Settings → Media can open them muted",
        ),
    ),
    Release(
        "2.0.45", "Oct 30, 2026",
        listOf(
            "Explore: the people you follow have their own Following section, and open their profile",
        ),
    ),
    Release(
        "2.0.44", "Oct 30, 2026",
        listOf(
            "Profiles: sort posts and comments by New, Hot or Top, and the profile header slides away as you scroll",
            "Custom feed share links (reddit.com/u/…/s/…) open the feed, not the user",
            "Swiping a comment in the Calm style slides it over the vote icon like a card, instead of tinting it",
            "The side bar no longer shows the page behind it while it opens",
        ),
    ),
    Release(
        "2.0.43", "Oct 29, 2026",
        listOf(
            "Translate posts, comments and AI summaries: on the post, in a comment's ⋯ menu, into your phone's language or a second one (Settings → Translation). On the phone where it can, else with your OpenAI key or Azure Translator",
            "Reddit Home and Blend load again with the website sign-in, with their galleries, videos and GIFs, and Home no longer falls back to For You after a while away",
            "Quarantined and restricted communities: \"View anyway\" right in Ilay",
            "Comments: collapse only the replies, and an edge marks the ones you voted on (Settings → Posts & comments)",
            "Preview a reply before sending it",
            "Clear cache now empties images and videos too and shows how much it frees; choose the image and video cache sizes",
            "With the website sign-in, feeds, comments, votes and saves switch to Reddit's app API if the website refuses them",
        ),
    ),
    Release(
        "2.0.41", "Oct 28, 2026",
        listOf(
            "Search works again with the website sign-in (Reddit had started refusing it)",
            "Share a Reddit post to \"Summarize with Ilay\": its AI summary opens over the app you're in",
            "\"Open in Ilay\" in the share menu opens a shared post in Ilay",
            "Search no longer crashes when Reddit refuses a request, and a failing tab doesn't hide the others' results",
        ),
    ),
    Release(
        "2.0.40", "Oct 26, 2026",
        listOf("Galleries in your feeds use the carousel too (turn it off in Settings → Media → Gallery carousel in feeds)"),
    ),
    Release(
        "2.0.39", "Oct 26, 2026",
        listOf(
            "Material 3 Expressive menus: grouped, with the current choice highlighted (Display, sort, comment ⋯)",
            "Join, Follow, Save and favourite stars are real toggles that change shape when on",
            "For You mix slider fills from the middle, so you see which way it leans",
            "Buttons' corners tighten as you press them (dialogs, Retry, back, ☰, ⚙)",
            "One pick-one style everywhere: post type, sign-in method, feed privacy",
            "Better with screen readers: tabs, votes, layouts, toggles and the video seek bar announce their state",
            "Galleries: a fling skips several images, and each image is labelled",
        ),
    ),
    Release(
        "2.0.38", "Oct 26, 2026",
        listOf(
            "Connected button groups: the Inbox filters, Search sort and Explore's Popular / All",
            "Polls show as one segmented list",
            "The side bar's ☰ sits in exactly the same spot on every tab",
        ),
    ),
    Release(
        "2.0.37", "Oct 25, 2026",
        listOf(
            "Material 3 Expressive loading: morphing-shape indicators everywhere Ilay is loading, including pull to refresh",
            "Saving media shows a wavy progress bar",
        ),
    ),
    Release(
        "2.0.36", "Oct 25, 2026",
        listOf(
            "User flairs show their emoji (club badges and the like), not just their text",
            "Calm layout: images and links have evenly rounded corners",
        ),
    ),
    Release(
        "2.0.35", "Oct 25, 2026",
        listOf(
            "Gallery posts open as a Material 3 carousel: one big image with the next ones peeking beside it",
            "Bottom bar outline can be turned off (Settings → Appearance)",
        ),
    ),
    Release(
        "2.0.34", "Oct 25, 2026",
        listOf(
            "User flairs next to names in posts and comments, and set your own flair from a community's About",
            "Custom feeds: one screen with all of them, rename, describe, make public or private, share, copy someone's public feed, and tap a community to open it",
            "A ⚙ button opens Settings directly; the Expandable top bar gets a search button",
            "Neater ☰ alignment and a cleaner New post icon",
        ),
    ),
    Release(
        "2.0.33", "Oct 22, 2026",
        listOf("And the other way: replies you opened in Reddit's notifications show as read in Ilay's Inbox (website sign-in)"),
    ),
    Release(
        "2.0.32", "Oct 22, 2026",
        listOf("With the website sign-in, replies you read in the Inbox are marked read in Reddit's notifications too (and Mark all read clears them there)"),
    ),
    Release(
        "2.0.31", "Oct 22, 2026",
        listOf("With the side bar on, swiping back on the main screen opens it, and back again closes it"),
    ),
    Release(
        "2.0.30", "Oct 22, 2026",
        listOf(
            "What's new: this list, once after each update, and any time in Settings → About",
            "Side bar navigation: Settings → Appearance → Navigation (bottom bar, side bar, or both)",
        ),
    ),
    Release(
        "2.0.29", "Oct 21, 2026",
        listOf(
            "AI summaries work with other providers (Groq, OpenRouter…) and any model ID",
            "Add a community to a custom feed from a post's ⋮ menu or the community's top bar",
            "Autoplay with sound, for feed videos (Settings → Media)",
        ),
    ),
    Release(
        "2.0.26 – 2.0.28", "Oct 18, 2026",
        listOf("Remind me about a saved post: pick when, get a notification, and see the reminder on the post"),
    ),
    Release(
        "2.0.24 – 2.0.25", "Oct 17, 2026",
        listOf(
            "Reddit's own notifications in the Inbox (website sign-in), with unread dots and older ones",
            "When Reddit rate-limits you, Ilay says how long to wait",
            "Select and delete several summaries at once",
        ),
    ),
    Release(
        "2.0.22 – 2.0.23", "Oct 17, 2026",
        listOf(
            "Profile tab: your posts, comments, saved and upvoted, with your stuff a tap away",
            "Settings moved to the ⋮ menu at the top of each tab",
            "Reddit Chat, voting in polls and Reddit's account settings (website sign-in)",
            "Poll results and your vote show in the post",
        ),
    ),
    Release(
        "2.0.20 – 2.0.21", "Oct 17, 2026",
        listOf(
            "Your votes stick when you go back into a thread or your profile",
            "Blend: choose Mostly Ilay, Balanced or Mostly Reddit",
            "Already seen elsewhere: drop a post you read in another app",
        ),
    ),
    Release(
        "2.0.19", "Oct 17, 2026",
        listOf(
            "Android 13 support",
            "Follow users",
            "Hide or dim read posts in more places",
        ),
    ),
    Release(
        "2.0.15 – 2.0.18", "Oct 16, 2026",
        listOf(
            "For You is out of beta and learns from more of what you do",
            "Familiar ↔ Discover: how adventurous For You should be",
            "Blend (Beta): your Reddit Home ranked by For You",
        ),
    ),
    Release(
        "2.0.11 – 2.0.14", "Oct 16, 2026",
        listOf(
            "Notification activity, Drafts and Ask AI about a thread",
            "Volume keys jump between comments; saved searches; collapse settings",
            "Smoother scrolling past GIFs in threads",
        ),
    ),
    Release(
        "2.0.1 – 2.0.7", "Oct 14, 2026",
        listOf(
            "Smoother scrolling in image-heavy feeds",
            "GIFs and stickers from your keyboard in replies and messages",
            "Hide a community from your front page, or filter it out everywhere",
            "Back never leaves the app from the main screen",
        ),
    ),
    Release(
        "2.0.0", "Oct 12, 2026",
        listOf(
            "Ilay rebuilt as a native Android app: faster, smoother, same data",
            "Reddit Home (experimental): your real reddit.com Home feed",
        ),
    ),
)

private const val SEEN_PREF = "whatsNewSeen"

private fun parts(v: String) = v.substringBefore(' ').split('.').map { it.toIntOrNull() ?: 0 }

/** Whether release [a] (its first version, for a range) is newer than version [b]. */
internal fun newer(a: String, b: String): Boolean {
    val x = parts(a)
    val y = parts(b)
    for (i in 0 until maxOf(x.size, y.size)) {
        val d = x.getOrElse(i) { 0 } - y.getOrElse(i) { 0 }
        if (d != 0) return d > 0
    }
    return false
}

/** The update notice's text: [message], then the new release's notes, scrolling when long (#266). */
@Composable
fun UpdateNoticeText(message: String, notes: String?) {
    Column {
        Text(message)
        if (notes != null) {
            Spacer(Modifier.height(12.dp))
            Column(Modifier.heightIn(max = 320.dp).verticalScroll(rememberScrollState())) {
                RedditMarkdown(notes, fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

/**
 * Once after an update: what changed since the version you last saw here
 * (or this release's, the first time). Never on a fresh install.
 */
@OptIn(ExperimentalMaterial3Api::class)
suspend fun maybeShowWhatsNew() {
    val current = BuildConfig.VERSION_NAME
    val seen = app.prefs.getString(SEEN_PREF)
    app.prefs.setString(SEEN_PREF, current)
    if (seen == current) return
    val releases = if (seen == null) {
        val info = runCatching { app.context.packageManager.getPackageInfo(app.context.packageName, 0) }.getOrNull()
        if (info == null || info.firstInstallTime == info.lastUpdateTime) return // a fresh install: nothing is "new"
        CHANGELOG.take(1)
    } else {
        CHANGELOG.filter { newer(it.version.substringAfterLast(' '), seen) }.take(3)
    }
    if (releases.isEmpty()) return
    val all = Overlays.show<Boolean> { done ->
        ModalBottomSheet(onDismissRequest = { done(false) }) {
            Column(
                Modifier.navigationBarsPadding().verticalScroll(rememberScrollState())
                    .padding(start = 20.dp, end = 20.dp, bottom = 12.dp),
            ) {
                Text("What's new in Ilay $current", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.ExtraBold)
                Spacer(Modifier.height(12.dp))
                for (r in releases) ReleaseNotes(r, showVersion = releases.size > 1)
                Row(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.End) {
                    TextButton(onClick = { done(true) }) { Text("All changes") }
                    Spacer(Modifier.width(8.dp))
                    Button(onClick = { done(false) }) { Text("Got it") }
                }
            }
        }
    }
    if (all == true) app.navigatorOrNull?.push(Route.WhatsNew)
}

@Composable
private fun ReleaseNotes(r: Release, showVersion: Boolean = true) {
    val cs = MaterialTheme.colorScheme
    Column(Modifier.padding(bottom = 12.dp)) {
        if (showVersion) {
            Row {
                Text(r.version, fontWeight = FontWeight.Bold, color = cs.primary)
                Spacer(Modifier.width(8.dp))
                Text(r.date, fontSize = 13.sp, color = cs.onSurfaceVariant)
            }
            Spacer(Modifier.height(6.dp))
        }
        for (h in r.highlights) {
            Row(Modifier.padding(bottom = 6.dp)) {
                Text("•", color = cs.primary)
                Spacer(Modifier.width(10.dp))
                Text(h)
            }
        }
    }
}

/** Settings → About → What's new: every release's highlights. */
@Composable
fun WhatsNewScreen() {
    val cs = MaterialTheme.colorScheme
    Scaffold(topBar = { BloomTopBar("What's new") }, containerColor = cs.surface) { padding ->
        LazyColumn(
            Modifier.fillMaxSize().padding(top = padding.calculateTopPadding()),
            contentPadding = PaddingValues(start = 12.dp, top = 8.dp, end = 12.dp, bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items(CHANGELOG, key = { it.version }) { r ->
                Surface(Modifier.fillMaxWidth(), shape = RoundedCornerShape(28.dp), color = cs.surfaceContainerLow) {
                    Column(Modifier.padding(start = 18.dp, top = 16.dp, end = 18.dp, bottom = 6.dp)) { ReleaseNotes(r) }
                }
            }
        }
    }
}
