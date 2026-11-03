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
